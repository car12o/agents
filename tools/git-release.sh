#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") <patch|minor|major>" >&2
  exit 1
}

error() {
  echo "Error: $1" >&2
  exit 1
}

[[ $# -ne 1 ]] && usage
[[ "$1" != patch && "$1" != minor && "$1" != major ]] && usage

bump="$1"

default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
if [[ -z "$default_branch" ]]; then
  default_branch=$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p')
fi
[[ -z "$default_branch" ]] && error "could not determine the repository's default branch"

git switch "$default_branch"
git pull --ff-only
tag=$(git describe --tags --abbrev=0 2>/dev/null) || error "no git tags found"

if [[ ! "$tag" =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
  error "latest tag '$tag' does not contain a semver version (MAJOR.MINOR.PATCH)"
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"
old_ver="${major}.${minor}.${patch}"

case "$bump" in
  major) new_ver="$((major + 1)).0.0" ;;
  minor) new_ver="${major}.$((minor + 1)).0" ;;
  patch) new_ver="${major}.${minor}.$((patch + 1))" ;;
esac

git switch -c "release/${new_ver}" "origin/${default_branch}"
git push -u origin "release/${new_ver}"
