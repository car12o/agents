#!/usr/bin/env bash
# Pull every git repository directly under ROOT that is checked out on its default branch.
# A repository on any other branch is left untouched (no pull, checkout or stash)
# and listed with its pull request status, so you can see when it is ready to
# go back to the default branch.
#
# Usage: pull-repos.sh [ROOT]
#   ROOT defaults to the current directory.
#
# Colour is used when stdout is a terminal; set NO_COLOR to turn it off.
# Exit status is non-zero when any pull failed.
set -uo pipefail

root=${1:-$PWD}
results=$(mktemp -d)
trap 'rm -rf "$results"' EXIT

# Result rows are fields joined by the ASCII unit separator, which cannot appear
# in branch names and, unlike a tab, keeps empty fields when read back.
sep=$'\x1f'

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
  bold=$'\e[1m' dim=$'\e[2m' red=$'\e[31m' green=$'\e[32m' yellow=$'\e[33m' reset=$'\e[0m'
else
  bold='' dim='' red='' green='' yellow='' reset=''
fi

# ---------------------------------------------------------------- per-repo work

default_branch() {
  local ref
  ref=$(git -C "$1" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) || return 1
  printf '%s' "${ref#origin/}"
}

worktree_state() {
  if [ -z "$(git -C "$1" status --porcelain)" ]; then
    printf 'clean worktree'
  else
    printf 'dirty worktree'
  fi
}

# Prints "<tag>${sep}<detail>" for the branch's most recent pull request, e.g.
# "PR #42 open${sep}approved · mergeable", "PR #42 merged${sep}" or "no PR${sep}".
pr_status() {
  local path=$1 branch=$2
  command -v gh >/dev/null || { printf 'gh not installed%s' "$sep"; return; }
  (cd "$path" && gh pr list --head "$branch" --state all --limit 1 \
      --json number,state,reviewDecision,mergeStateStatus \
      --jq '
        def review: {APPROVED: "approved", CHANGES_REQUESTED: "changes requested",
                     REVIEW_REQUIRED: "review required"}[.reviewDecision // "NONE"] // "no review";
        def merge:  {CLEAN: "mergeable", HAS_HOOKS: "mergeable", BEHIND: "behind base",
                     BLOCKED: "blocked", DIRTY: "conflicts", UNSTABLE: "checks not green",
                     DRAFT: "draft"}[.mergeStateStatus // "UNKNOWN"] // "merge state unknown";
        if length == 0 then "no PR\u001f"
        else .[0] | "PR #\(.number) \(.state | ascii_downcase)\u001f"
             + (if .state == "OPEN" then "\(review) · \(merge)" else "" end)
        end' 2>/dev/null) || printf 'PR lookup failed%s' "$sep"
}

# Pulls run in parallel and unattended, so a credential, passphrase or host-key
# prompt fails the pull instead of waiting on the terminal; credentials have to
# come from a credential helper or ssh-agent. An empty GIT_ASKPASS also stops git
# from falling back to SSH_ASKPASS.
pull_without_prompts() {
  GIT_TERMINAL_PROMPT=0 GIT_ASKPASS='' SSH_ASKPASS=false SSH_ASKPASS_REQUIRE=force \
    git -C "$1" pull --ff-only 2>&1
}

join_parts() {  # join_parts PART... — joins the non-empty parts with " · "
  local out='' part
  for part in "$@"; do
    [ -n "$part" ] || continue
    out="${out:+$out · }$part"
  done
  printf '%s' "$out"
}

emit() {  # emit REPO OUTCOME BRANCH DEFAULT TAG DETAIL — writes one result row
  local IFS=$sep
  printf '%s\n' "$*"
}

# outcome is one of: updated, current, skipped, failed.
# DEFAULT is filled only where it adds information: when the repo is not on it,
# or when the pull on it failed.
update_repo() {
  local repo=$1 path="$root/$1" default current log tag detail

  if ! default=$(default_branch "$path"); then
    emit "$repo" skipped "$(git -C "$path" branch --show-current)" 'unresolved' 'no origin/HEAD' "$(worktree_state "$path")"
    return
  fi

  current=$(git -C "$path" branch --show-current)
  if [ -z "$current" ]; then
    emit "$repo" skipped '<detached>' "$default" 'detached HEAD' "$(worktree_state "$path")"
    return
  fi
  if [ "$current" != "$default" ]; then
    IFS=$sep read -r tag detail < <(pr_status "$path" "$current")
    [[ $tag == *merged ]] && detail="ready to switch to $default"
    emit "$repo" skipped "$current" "$default" "$tag" "$(join_parts "$detail" "$(worktree_state "$path")")"
    return
  fi

  if ! log=$(pull_without_prompts "$path"); then
    emit "$repo" failed "$default" "$default" '' "$(printf '%s' "$log" | grep -v '^hint:' | tr '\n\t' '  ' | sed 's/ *$//')"
    return
  fi
  if [[ $log == *'Already up to date.'* ]]; then
    emit "$repo" current "$default" '' '' ''
    return
  fi
  emit "$repo" updated "$default" '' '' "$(printf '%s' "$log" | grep -E '^ [0-9]+ files? changed' | sed 's/^ //')"
}

# -------------------------------------------------------------------- reporting

rows_with_outcome() {
  awk -F "$sep" -v outcome="$1" '$2 == outcome' "$results"/* | sort
}

count_with_outcome() {
  rows_with_outcome "$1" | wc -l
}

field_width() {  # field_width N — length of the longest value in field N across all rows
  awk -F "$sep" -v n="$1" '{ if (length($n) > w) w = length($n) } END { print w + 0 }' "$results"/*
}

colour_tag() {
  case $1 in
    *merged) printf '%s%s%s' "$green" "$1" "$reset" ;;
    *open)   printf '%s%s%s' "$yellow" "$1" "$reset" ;;
    *)       printf '%s%s%s' "$dim" "$1" "$reset" ;;
  esac
}

print_heading() {  # print_heading TITLE COUNT [SUBTITLE]
  printf '\n%s%s (%d)%s' "$bold" "$1" "$2" "$reset"
  [ -z "${3:-}" ] || printf '  %s%s%s' "$dim" "$3" "$reset"
  printf '\n'
}

print_section() {  # print_section OUTCOME GLYPH COLOUR TITLE [SUBTITLE]
  local outcome=$1 glyph=$2 colour=$3 count repo _ branch default tag detail
  count=$(count_with_outcome "$outcome")
  [ "$count" -gt 0 ] || return 0
  print_heading "$4" "$count" "${5:-}"
  while IFS=$sep read -r repo _ branch default tag detail; do
    [ -z "$tag" ] || tag=$(colour_tag "$tag")
    detail=${detail//dirty worktree/${red}dirty worktree${reset}}
    printf '  %s%s %-*s%s  %s%-*s%s' \
      "$colour" "$glyph" "$repo_width" "$repo" "$reset" \
      "$dim" "$branch_width" "$branch" "$reset"
    [ -z "$default" ] || printf '  %s%-*s%s' "$dim" "$default_width" "$default_prefix$default" "$reset"
    printf '  %s\n' "$(join_parts "$tag" "$detail")"
  done < <(rows_with_outcome "$outcome")
}

print_up_to_date() {
  local count width line
  count=$(count_with_outcome current)
  [ "$count" -gt 0 ] || return 0
  width=$(( ${COLUMNS:-$(tput cols 2>/dev/null || echo 80)} - 2 ))
  print_heading 'Up to date' "$count"
  rows_with_outcome current | cut -d "$sep" -f1 | paste -sd ',' | sed 's/,/, /g' | fold -s -w "$width" |
    while IFS= read -r line; do
      printf '  %s%s%s\n' "$dim" "$line" "$reset"
    done
}

count_label() {  # count_label OUTCOME COLOUR LABEL — dimmed when the count is zero
  local n colour=$2
  n=$(count_with_outcome "$1")
  [ "$n" -gt 0 ] || colour=$dim
  printf '%s%d %s%s' "$colour" "$n" "$3" "${colour:+$reset}"
}

print_summary() {
  printf '\n%s%d repositories%s: %s, %s, %s, %s\n' \
    "$bold" "${#repos[@]}" "$reset" \
    "$(count_label updated "$green" updated)" \
    "$(count_label current '' 'up to date')" \
    "$(count_label skipped "$yellow" skipped)" \
    "$(count_label failed "$red" failed)"
}

# ------------------------------------------------------------------------- main

repos=()
for dir in "$root"/*/; do
  [ -d "$dir/.git" ] && repos+=("$(basename "$dir")")
done
if [ "${#repos[@]}" -eq 0 ]; then
  printf 'no git repositories under %s\n' "$root" >&2
  exit 1
fi

printf 'Pulling %d repositories under %s …\n' "${#repos[@]}" "$root" >&2
for repo in "${repos[@]}"; do
  update_repo "$repo" > "$results/$repo" &
done
wait

repo_width=$(field_width 1)
branch_width=$(field_width 3)
default_prefix='default: '
default_width=$(( $(field_width 4) + ${#default_prefix} ))

print_up_to_date
print_section updated '✓' "$green"  'Updated'
print_section skipped '↷' "$yellow" 'Skipped' 'not on their default branch, left untouched'
print_section failed  '✗' "$red"    'Failed'
print_summary

[ "$(count_with_outcome failed)" -eq 0 ]
