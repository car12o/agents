#!/usr/bin/env bash
#
# ask-agent.sh — Run a prompt against an LLM agent CLI that can read and research but not write, and resume the
# conversation later.
#
# Intended to be invoked from any tool to get a read-only second opinion, review, or research from a specific agent.
#
# Behavior:
#   - The prompt is one argument, the file given to --prompt-file, or stdin when neither is given. It is
#     prepended with read-only, no-delegation rules and fed to the CLI on stdin.
#   - The agent loads its CLI's user and project settings, instructions, skills, and MCP servers. It reads anywhere,
#     searches, and uses the network, but cannot write files: Codex and Claude Code run shell commands in their CLI's
#     OS sandbox, read-only with network on; OpenCode, which has none, allows no edit tool and only git read commands
#     in its shell, and reaches the network through its web tools. MCP servers run outside every sandbox.
#   - Each call creates a run directory under ${TMPDIR:-/tmp}, kept so its session can be resumed. Every turn
#     writes a new turn-N/ in it, never overwritten: prompt.md (the caller's prompt), events.jsonl (the CLI's
#     raw event stream), stderr.log, response.md, meta.json.
#   - --resume <run> continues the run's session by its exact id, from the run's working directory.
#   - --show <run> prints the run's conversation: every turn's prompt and response.
#   - --dry-run prints the command a call would run and changes nothing: no agent, run, or file. It runs only the
#     read-only lookups the command needs: git, and `codex mcp list` for Codex.
#   - The CLI call is wrapped in `timeout` (15m unless --timeout), with a SIGKILL 30 s later if it ignores SIGTERM.
#     A TERM, INT, or HUP to this script stops the CLI, with a SIGKILL 30 s later, and still finishes the turn. A
#     turn whose script was killed outright is finished by the next --resume or --show, which also stops its CLI.
#   - Once the prompt is accepted, the agent's response is printed on stdout on every exit; on failure it is
#     whatever text the agent produced. A stderr line names the run as the agent starts; the last stderr line
#     summarises the turn, names its run, and gives the failure reason.
#   - Exit codes:
#       0    success
#       64   bad usage (unknown agent or run, busy run, missing, doubled, empty, or oversized prompt, invalid timeout)
#       124  `timeout` stopped the agent; 137 when it needed the SIGKILL
#       143  this script was told to stop, and stopped the agent
#       *    propagated from the agent CLI
#
# Examples:
#   ask-agent.sh glm 'Say hello.'
#   ask-agent.sh codex --prompt-file ./review-prompt.md
#   ask-agent.sh kimi <<'EOF'
#   Is `parse()` safe on empty input?
#   EOF
#   ask-agent.sh --resume /tmp/ask-agent-kimi.Ab12Cd 'And on a nil reader?'
#   ask-agent.sh --show /tmp/ask-agent-kimi.Ab12Cd
#   ask-agent.sh claude --dry-run 'Say hello.'
#   ask-agent.sh --list

set -euo pipefail

# A background launch starts with SIGINT ignored, and bash cannot trap a signal ignored at entry; restart with its
# default disposition so an INT can stop the agent.
if [[ "$(trap -p INT)" == "trap -- '' SIGINT" && -z "${ASK_AGENT_INT_RESTORED:-}" ]]; then
  ASK_AGENT_INT_RESTORED=1 exec env --default-signal=INT "$BASH" "$0" "$@"
fi
unset ASK_AGENT_INT_RESTORED

readonly DEFAULT_TIMEOUT="15m"
readonly KILL_GRACE="30s"
readonly MAX_PROMPT_BYTES=102400
readonly EXIT_USAGE=64
# One row per agent: name, backend, model, description.
readonly AGENTS_TABLE="\
claude    claude    claude-opus-5-5                              Anthropic Claude Code
codex     codex     gpt-6.1-sol                                  OpenAI Codex
glm       opencode  llm-netdata-cloud/glm-5.3#high               Zhipu GLM (via opencode)
minimax   opencode  llm-netdata-cloud/minimax-m3.1-flash         MiniMax (via opencode)
kimi      opencode  llm-netdata-cloud/k3#high                    Moonshot Kimi (via opencode)
qwen      opencode  llm-netdata-cloud/qwen3.8-max                Alibaba Qwen (via opencode)
deepseek  opencode  llm-netdata-cloud/deepseek-v4.1-flash#high   DeepSeek (via opencode)
grok      opencode  llm-netdata-cloud/grok-4.7#xhigh             xAI Grok (via opencode)
gemini    opencode  github-copilot/gemini-3.8-flash#high         Google Gemini (via opencode)"
# The git subcommands OpenCode's shell may run. `git grep` is left out because its -O option runs any program.
readonly GIT_READ_COMMANDS=(blame cat-file diff log ls-files merge-base rev-parse show status)
# The caller's session identity: a callee that inherits it could message or impersonate the caller's session.
readonly CALLER_IDENTITY_VARS=(
  CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION
  CLAUDE_CODE_SESSION_ATTENDED CLAUDE_PID CODEX_THREAD_ID CODEX_SESSION_ID
)
readonly RULES='⚠️ ⚠️ ⚠️  CRITICAL RULES — YOU MUST OBEY THESE WITHOUT EXCEPTION  ⚠️ ⚠️ ⚠️

1. You are running in **READ-ONLY MODE**. You MUST NOT create, modify, or delete
   any files or any other data. You MUST NOT execute any write commands. You may
   ONLY read files, search, run read-only shell commands, use the web, and use
   your skills and MCP tools to read. Some setups allow only read-only `git`
   commands in the shell; prefer your file reading and search tools.

2. You are COMPLETELY FORBIDDEN from using the "Ask agent" tool (or any
   equivalent sub-agent / delegation mechanism). Do NOT invoke `ask-agent`,
   or anything similar. Perform the task yourself directly.

3. This session is **NON-INTERACTIVE**: nobody will answer questions or grant
   permissions. If a command or tool is denied, continue with what you can do,
   and say what you could not check.

---
'

usage() {
  cat <<'EOF'
Usage:
  ask-agent.sh <agent> [<prompt> | --prompt-file <path>] [--timeout <duration>] [--dry-run]
  ask-agent.sh --resume <run> [<prompt> | --prompt-file <path>] [--timeout <duration>] [--dry-run]
  ask-agent.sh --show <run>
  ask-agent.sh --list

Agents:
EOF
  local name backend model description
  while read -r name backend model description; do
    printf '  %-9s %s\n' "$name" "$description"
  done <<<"$AGENTS_TABLE"
  cat <<'EOF'

The prompt is one argument, the file given to --prompt-file, or stdin when neither is given.
It is 100 KB or less and is prepended with read-only rules; the agent can read, search, and
use the web, its skills, and its CLI's MCP servers, but cannot write files.
Once the prompt is accepted, the response is printed on stdout on every exit, and the last
stderr line summarises the turn and names its run.
--resume continues the session of an earlier run; --show prints a run's conversation.
--timeout takes a non-zero `timeout` duration such as 30m (default 15m).
--dry-run prints the command the call would run; it starts no agent and changes nothing.
--list prints the agent names, one per line.
EOF
}

die() {
  echo "Error: $*" >&2
  exit "$EXIT_USAGE"
}

list_agents() {
  local name _
  while read -r name _; do
    echo "$name"
  done <<<"$AGENTS_TABLE"
}

# Sets the globals AGENT, BACKEND, and MODEL from the agents table.
resolve_agent() {
  local name backend model _
  while read -r name backend model _; do
    [[ "$name" == "$1" ]] || continue
    AGENT="$name" BACKEND="$backend" MODEL="$model"
    return 0
  done <<<"$AGENTS_TABLE"
  die "unknown agent '$1'. Valid agents: $(list_agents | paste -sd ' ')"
}

require_value() {
  [[ $# -ge 2 ]] || die "option '$1' needs a value."
}

# Records the one --prompt-file given; a repeat or an empty path is a usage error.
set_prompt_file() {
  [[ -z "$PROMPT_FILE" ]] || die "pass --prompt-file only once."
  [[ -n "$1" ]] || die "option '--prompt-file' needs a path."
  PROMPT_FILE="$1"
}

# Sets the globals PROMPT_ARGS, PROMPT_FILE, TIMEOUT, and DRY_RUN from the arguments that follow the agent or run.
parse_options() {
  PROMPT_ARGS=()
  PROMPT_FILE=""
  TIMEOUT="$DEFAULT_TIMEOUT"
  DRY_RUN=""
  while (($#)); do
    case "$1" in
      --prompt-file) require_value "$@"; set_prompt_file "$2"; shift 2 ;;
      --timeout)     require_value "$@"; TIMEOUT="$2"; shift 2 ;;
      --dry-run)     DRY_RUN=1; shift ;;
      -*)            die "unknown option '$1'; a prompt starting with '-' goes on stdin." ;;
      *)             PROMPT_ARGS+=("$1"); shift ;;
    esac
  done
  ((${#PROMPT_ARGS[@]} <= 1)) || die "pass the prompt as one quoted argument."
  [[ -z "$PROMPT_FILE" || ${#PROMPT_ARGS[@]} -eq 0 ]] || die "pass the prompt as an argument or with --prompt-file, not both."
  # A zero duration would disable the time limit.
  [[ "$TIMEOUT" =~ ^[0-9]+([.][0-9]+)?[smhd]?$ && "$TIMEOUT" =~ [1-9] ]] \
    || die "invalid --timeout '$TIMEOUT'; use a non-zero duration such as 30m."
}

# Sets the global PROMPT from the one source given: the argument, the --prompt-file file, or stdin.
read_prompt() {
  if ((${#PROMPT_ARGS[@]})); then
    PROMPT="${PROMPT_ARGS[0]}"
  elif [[ -n "$PROMPT_FILE" ]]; then
    [[ -f "$PROMPT_FILE" && -r "$PROMPT_FILE" ]] || die "prompt file not found or unreadable: $PROMPT_FILE"
    PROMPT="$(cat -- "$PROMPT_FILE")"
  else
    [[ ! -t 0 ]] || die "missing prompt: pass it as an argument, with --prompt-file, or on stdin."
    PROMPT="$(cat)"
  fi
  [[ "$PROMPT" =~ [^[:space:]] ]] || die "prompt is empty; pass it as an argument, with --prompt-file, or on stdin."
  [[ "$(printf '%s' "$PROMPT" | wc -c)" -le "$MAX_PROMPT_BYTES" ]] || die "prompt exceeds ${MAX_PROMPT_BYTES} bytes."
}

# The name the CLI lists the session under, such as in Claude's /resume picker: the agent and the prompt's
# first line.
session_title() {
  local line
  line="$(awk 'NF { $1 = $1; print; exit }' <<<"$PROMPT")"
  printf 'ask-agent %s: %s' "$AGENT" "${line:0:60}"
}

# Creates the run directory and its run.json; sets the globals RUN_DIR and SESSION_ID.
create_run() {
  RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ask-agent-${AGENT}.XXXXXX")"
  SESSION_ID=""
  jq -n --arg agent "$AGENT" --arg backend "$BACKEND" --arg model "$MODEL" --arg cwd "$PWD" \
    --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{agent: $agent, backend: $backend, model: $model, cwd: $cwd, created: $created, session_id: null}' \
    >"$RUN_DIR/run.json"
}

# Loads an earlier run into the globals RUN_DIR, AGENT, BACKEND, MODEL, RUN_CWD, CREATED, and SESSION_ID. A first
# turn killed before it finished never recorded its session id, but its events still name it.
load_run() {
  local dir="$1" fields=()
  [[ -n "$dir" ]] || die "missing <run> argument."
  [[ -f "$dir/run.json" ]] || die "not an ask-agent run directory: $dir"
  RUN_DIR="$(cd -- "$dir" && pwd)"
  mapfile -d '' -t fields \
    < <(jq --raw-output0 '.agent, .backend, .model, .cwd, .created, (.session_id // "")' "$RUN_DIR/run.json")
  ((${#fields[@]} == 6)) || die "unreadable run.json: $dir"
  AGENT="${fields[0]}" BACKEND="${fields[1]}" MODEL="${fields[2]}"
  RUN_CWD="${fields[3]}" CREATED="${fields[4]}" SESSION_ID="${fields[5]}"
  declare -F "${BACKEND}_start" >/dev/null || die "run has an unknown backend '$BACKEND': $dir"
  [[ -n "$SESSION_ID" || ! -f "$RUN_DIR/turn-1/events.jsonl" ]] \
    || SESSION_ID="$("${BACKEND}_session_id" "$RUN_DIR/turn-1/events.jsonl")"
}

require_resumable() {
  [[ -n "$SESSION_ID" ]] || die "run has no session to resume; its first turn never reached the agent: $RUN_DIR"
  [[ -d "$RUN_CWD" ]] || die "run's working directory no longer exists: $RUN_CWD"
}

# Takes an exclusive lock on the run, held by this script only, so two turns never drive one session at once.
try_lock_run() {
  exec 9>"$RUN_DIR/lock"
  flock -n 9
}

lock_run() {
  try_lock_run || die "run is busy with another turn: $RUN_DIR"
}

# Sets the globals TURN and TURN_DIR to the run's next turn, and writes its prompt.
start_turn() {
  TURN=1
  while [[ -e "$RUN_DIR/turn-$TURN" ]]; do
    TURN=$((TURN + 1))
  done
  TURN_DIR="$RUN_DIR/turn-$TURN"
  mkdir "$TURN_DIR"
  printf '%s\n' "$PROMPT" >"$TURN_DIR/prompt.md"
}

# Runs a jq program over the array of a turn's JSON events; non-JSON lines are skipped.
query_events() {
  jq -nrR "[inputs | fromjson?] | $2" "$1"
}

# Each backend defines <backend>_start and <backend>_resume <session-id>, which set the global CMD, and
# <backend>_session_id, <backend>_response, and <backend>_meta, which read a turn's events file.

# User, project, and local settings all load, with their instructions, skills, and MCP servers. No tool can edit
# files, and Bash runs in the sandbox, which may write only to the working directory, denied below, and to its temp
# directory. That directory gets a private, short path: a long TMPDIR overflows the sandbox's socket paths, and a
# shared one would let the callee write where other runs live. The --settings sandbox outranks project settings.
# A dry run names the directory instead of creating it.
claude_command() {
  local sandbox_tmp="<private temp dir>"
  [[ -n "$DRY_RUN" ]] || sandbox_tmp="$(mktemp -d /tmp/ask-agent-sandbox.XXXXXX)"
  CMD=(env "TMPDIR=$sandbox_tmp" claude -p --model "$MODEL" --effort xhigh
    --output-format stream-json --verbose
    --tools Read,Grep,Glob,Bash,WebFetch,WebSearch,Skill --permission-mode bypassPermissions
    --settings "$(claude_settings)")
}

# Writes are also denied to the repository's shared .git directory, which the sandbox otherwise opens when the
# working directory is a linked worktree.
claude_settings() {
  local cwd="${RUN_CWD:-$PWD}" git_dir
  git_dir="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || git_dir=""
  jq -cn --arg cwd "$cwd" --arg git_dir "$git_dir" '{sandbox: {enabled: true, failIfUnavailable: true,
    allowUnsandboxedCommands: false, filesystem: {denyWrite: ([$cwd, $git_dir] | map(select(. != "")) | unique)}}}'
}

claude_start() {
  claude_command
  CMD+=(--name "$(session_title)")
}

claude_resume() {
  claude_command
  CMD+=(--resume "$1")
}

claude_session_id() {
  query_events "$1" 'first(.[] | .session_id // empty)'
}

# The final answer when the turn finished, else every text block so far.
claude_response() {
  query_events "$1" '
    (map(select(.type == "result")) | last) as $result
    | if $result and ($result.is_error | not) then $result.result
      else [.[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text] | join("\n\n")
      end'
}

# An execution error carries its reason in `errors` rather than `result`.
claude_meta() {
  query_events "$1" '
    (map(select(.type == "result")) | last) as $result
    | {stop_reason: $result.stop_reason, num_turns: $result.num_turns, cost_usd: $result.total_cost_usd,
       permission_denials: ($result.permission_denials // [] | length),
       error: (if $result.is_error then ($result.result // ($result.errors // [] | join("; "))) else null end)}'
}

# Sets the global CODEX_OPTIONS. The permission profile reads anywhere, writes nowhere, and keeps the network on,
# which `sandbox_mode="read-only"` cannot. It gets a random name each turn, because a trusted project's config can
# add keys to a profile it can name. The project is trusted for the call so its own config, MCP servers included,
# loads; -c values outrank it.
codex_options() {
  local cwd="${RUN_CWD:-$PWD}" profile root trust
  profile="ask_agent_$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
  root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")"
  trust="projects={$(jq -rn --arg path "$root" '$path | tojson')={trust_level=\"trusted\"}}"
  CODEX_OPTIONS=(--json --skip-git-repo-check --disable multi_agent --disable multi_agent_v2
    -c "permissions.$profile={extends=\":read-only\", network={enabled=true}}" -c "default_permissions=\"$profile\""
    -c "$trust" -c "$(codex_mcp_approvals "$cwd" "$trust")"
    -c 'approval_policy="never"' -c 'web_search="live"')
}

# Pre-approves the tools of every MCP server the call sees, the user's and the project's: with approval_policy
# "never", a tool call that needs approval is refused. Empty output from codex still yields a valid override.
codex_mcp_approvals() {
  { (cd -- "$1" && codex -c "$2" mcp list --json 2>/dev/null) \
      | jq -rn '(input? // []) as $servers
          | "mcp_servers={" + ([$servers[] | "\(.name | tojson)={default_tools_approval_mode=\"approve\"}"]
              | join(", ")) + "}"'
  } || echo 'mcp_servers={}'
}

codex_start() {
  codex_options
  CMD=(codex exec "${CODEX_OPTIONS[@]}" --model "$MODEL" -)
}

codex_resume() {
  codex_options
  CMD=(codex exec resume "${CODEX_OPTIONS[@]}" --model "$MODEL" "$1" -)
}

codex_session_id() {
  query_events "$1" 'first(.[] | select(.type == "thread.started") | .thread_id)'
}

# The final message when the turn finished, else every message so far.
codex_response() {
  query_events "$1" '
    [.[] | select(.type == "item.completed" and .item.type == "agent_message") | .item.text] as $messages
    | if any(.[]; .type == "turn.completed") then $messages | last // "" else $messages | join("\n\n") end'
}

codex_meta() {
  query_events "$1" '
    {usage: ([.[] | select(.type == "turn.completed") | .usage] | last),
     error: ([.[] | select(.type == "error" or .type == "turn.failed") | .message // .error.message] | last)}'
}

# --standalone starts a private server: the shared background service ignores per-run config and keeps a
# turn running after its client is killed.
opencode_command() {
  CMD=(env "OPENCODE_CONFIG_CONTENT=$(opencode_config)" opencode run --standalone --agent ask-agent-readonly
    --model "$MODEL" --format json)
}

opencode_start() {
  opencode_command
  CMD+=(--title "$(session_title)")
}

opencode_resume() {
  opencode_command
  CMD+=(--session "$1")
}

# OpenCode loads the user's and the project's config, instructions, skills, and MCP servers; this inline config
# outranks both. It has no OS sandbox, so its agent allows every tool, MCP servers, skills, and reads anywhere included,
# except edits, questions, sub-agents, and the browser; its shell runs only git read commands, without --output or
# redirects. The top-level edit denial replaces any edit allowance in the user's config, whose rules apply after
# the agent's. The web search provider is preselected because otherwise the first search asks for consent on a
# form that `opencode run` cancels, failing the search and exiting 1.
opencode_config() {
  jq -cn --args '
    ($ARGS.positional | map(
        {key: "git \(.)", value: "allow"}, {key: "git \(.) *", value: "allow"},
        {key: "git --no-pager \(.)", value: "allow"}, {key: "git --no-pager \(.) *", value: "allow"})
      | from_entries) as $git
    | {websearch: {provider: "random"},
       permission: {edit: "deny"},
       agent: {"ask-agent-readonly": {mode: "primary", permission: {
         "*": "allow", read: "allow", external_directory: "allow",
         edit: "deny", question: "deny", subagent: "deny", browser: "deny", doom_loop: "deny",
         shell: ({"*": "deny"} + $git + {"git *--output*": "deny", "*>*": "deny"})}}}}' "${GIT_READ_COMMANDS[@]}"
}

opencode_session_id() {
  query_events "$1" 'first(.[] | .sessionID // empty | select(length > 0))'
}

opencode_response() {
  query_events "$1" '[.[] | select(.type == "text") | .part.text // empty] | join("\n\n")'
}

opencode_meta() {
  query_events "$1" '
    {failed_tool_calls: ([.[] | select(.type == "tool_use" and .part.state.status == "error")] | length),
     error: ([.[] | select(.type == "error") | .error.message // .error.data.message // (.error | tostring)] | last)}'
}

# Some CLIs drop the opening tag of the first thinking block, leaving a bare closing tag; that leading
# block is stripped too. A tag quoted in backticks is part of the answer and is left alone.
strip_thinking() {
  perl -0777 -pe 's/(?<!`)<think>.*?<\/think>(?!`)\n?//gs; s/\A.*?(?<!`)<\/think>(?!`)\n?//s'
}

# Prints the command a turn would run, and where, instead of running it.
preview() {
  printf '# runs in %s, reading the read-only rules and the prompt on stdin\n' "${RUN_CWD:-$PWD}"
  printf '%q ' timeout -k "$KILL_GRACE" "$TIMEOUT" "${CMD[@]}"
  printf '\n'
}

# The start time of a process, which tells a live process from a later one that reused its pid.
process_start() {
  local stat fields
  stat="$(cat "/proc/$1/stat" 2>/dev/null)" || return 1
  read -r -a fields <<<"${stat##*) }"
  echo "${fields[19]}"
}

cli_alive() {
  [[ -n "$CLI_START" && "$(process_start "$CLI_PID")" == "$CLI_START" ]]
}

# Stops the CLI's process group when this script is told to stop, with a SIGKILL after the grace period, so no
# orphan keeps running; the turn still finishes. The plain pid covers the moment before `timeout` makes its group.
stop_cli() {
  cli_alive || return 0
  STOPPED=1
  kill -TERM -- "-$CLI_PID" 2>/dev/null || kill -TERM "$CLI_PID" 2>/dev/null || true
  (
    sleep "$KILL_GRACE"
    [[ "$(process_start "$CLI_PID")" != "$CLI_START" ]] || kill -KILL -- "-$CLI_PID"
  ) </dev/null >/dev/null 2>&1 9>&- &
}

# The CLI reads the read-only rules, then the caller's prompt, on stdin. `timeout` makes it a process group of its
# own, recorded so a later call can stop it if this script dies. It runs in the background so a trapped signal
# interrupts `wait`; waiting again lets it exit before the turn is finished. It never inherits the run's lock.
run_cli() {
  local status=0
  unset "${CALLER_IDENTITY_VARS[@]}"
  STOPPED=""
  CLI_PID=""
  CLI_START=""
  trap stop_cli TERM INT HUP
  timeout -k "$KILL_GRACE" "$TIMEOUT" "${CMD[@]}" < <(printf '%s\n' "$RULES"; cat "$TURN_DIR/prompt.md") \
    >"$TURN_DIR/events.jsonl" 2>"$TURN_DIR/stderr.log" 9>&- &
  CLI_PID=$!
  CLI_START="$(process_start "$CLI_PID")" || CLI_START=""
  printf '%s %s\n' "$CLI_PID" "$CLI_START" >"$TURN_DIR/cli.pid"
  wait "$CLI_PID" || status=$?
  while cli_alive; do
    status=0
    wait "$CLI_PID" || status=$?
  done
  # A stop that raced a CLI already finishing cleanly leaves the turn a success.
  [[ -z "$STOPPED" || "$status" == 0 ]] || status=143
  return "$status"
}

# Stops the process group of a CLI whose script was killed outright, unless the pid now belongs to another process.
stop_orphaned_cli() {
  local pid="" start="" _
  [[ -f "$TURN_DIR/cli.pid" ]] || return 0
  read -r pid start _ <"$TURN_DIR/cli.pid" || true
  [[ -n "$start" && "$(process_start "$pid")" == "$start" ]] || return 0
  kill -TERM -- "-$pid" 2>/dev/null || true
  for _ in {1..30}; do
    [[ "$(process_start "$pid")" == "$start" ]] || return 0
    sleep 1
  done
  kill -KILL -- "-$pid" 2>/dev/null || true
}

# Records the session id the run's first turn started; later turns resume that id.
record_session_id() {
  [[ -n "$SESSION_ID" ]] || SESSION_ID="$("${BACKEND}_session_id" "$TURN_DIR/events.jsonl")"
  [[ -n "$SESSION_ID" ]] || return 0
  jq --arg id "$SESSION_ID" '.session_id //= $id' "$RUN_DIR/run.json" >"$RUN_DIR/run.json.new" \
    && mv "$RUN_DIR/run.json.new" "$RUN_DIR/run.json"
}

last_line() {
  awk 'NF { line = $0 } END { print line }' "$1"
}

meta_valid() {
  jq -e 'type == "object" and has("status")' "$1" >/dev/null 2>&1
}

# A null exit code marks a turn whose script was killed before finishing it. The reason for a timeout or a stop
# is the timeout or stop itself: whatever the killed CLI reported last is a symptom of the kill. The file is
# replaced atomically, so a kill mid-write never leaves a truncated one.
write_meta() {
  local exit_code="$1" seconds="$2"
  "${BACKEND}_meta" "$TURN_DIR/events.jsonl" | jq \
    --argjson turn "$TURN" --argjson exit_code "$exit_code" --argjson seconds "$seconds" --arg timeout "${TIMEOUT-}" \
    --arg session_id "$SESSION_ID" --arg stderr_tail "$(last_line "$TURN_DIR/stderr.log")" '
    {turn: $turn, exit_code: $exit_code,
     status: ({"0": "ok", "124": "timeout", "137": "timeout", "143": "stopped", "null": "stopped"}[$exit_code | tostring]
              // "error"),
     duration_seconds: $seconds, session_id: ($session_id | select(. != "") // null)}
    + .
    + {error: (if $exit_code == 124 or $exit_code == 137 then "killed after the \($timeout) timeout"
               elif $exit_code == 143 or $exit_code == null then "stopped before it finished"
               else .error // (if $exit_code == 0 or $stderr_tail == "" then null else $stderr_tail end) end)}' \
    >"$TURN_DIR/meta.json.new" && mv "$TURN_DIR/meta.json.new" "$TURN_DIR/meta.json"
}

finalize_turn() {
  local exit_code="$1" seconds="$2"
  record_session_id
  "${BACKEND}_response" "$TURN_DIR/events.jsonl" | strip_thinking >"$TURN_DIR/response.md"
  write_meta "$exit_code" "$seconds"
}

# Finishes every turn whose script was killed before it could, stopping its CLI if that still runs and recovering
# what its events recorded. Callers hold the run's lock, so an unfinished turn can only be a killed one. A turn
# killed before its CLI started has no event or stderr file yet; empty ones let it finish all the same.
reconcile_turns() {
  TURN=1
  while [[ -d "$RUN_DIR/turn-$TURN" ]]; do
    TURN_DIR="$RUN_DIR/turn-$TURN"
    if ! meta_valid "$TURN_DIR/meta.json"; then
      stop_orphaned_cli
      touch "$TURN_DIR/events.jsonl" "$TURN_DIR/stderr.log"
      finalize_turn null null || true
    fi
    TURN=$((TURN + 1))
  done
}

# The last stderr line: the run and turn first, then the outcome, then the first line of its error.
summarize_turn() {
  jq -r --arg agent "$AGENT" --arg run "$RUN_DIR" '
    "ask-agent: run \($run) turn \(.turn), \($agent) \(.status), exit \(.exit_code), \(.duration_seconds)s"
    + (if .error then "; reason: " + (.error | tostring | split("\n") | map(select(test("\\S"))) | first // "")
       else "" end)' \
    "$TURN_DIR/meta.json" >&2
}

# Prints the response on every exit, whatever finalization manages, so a partial response survives a
# timeout, a stop, or a CLI failure. The run is named on stderr before the agent starts, so a caller whose call was
# killed before the summary can still find it.
run_turn() {
  local status=0
  start_turn
  echo "ask-agent: run $RUN_DIR turn $TURN, $AGENT started" >&2
  SECONDS=0
  run_cli || status=$?
  finalize_turn "$status" "$SECONDS" || true
  cat "$TURN_DIR/response.md" 2>/dev/null || true
  summarize_turn || echo "ask-agent: run $RUN_DIR turn $TURN, $AGENT exit $status" >&2
  return "$status"
}

show_turn() {
  local dir="$1" turn="$2" outcome="in progress"
  ! meta_valid "$dir/meta.json" || outcome="$(jq -r '
    [.status, (.exit_code // empty | "exit \(.)"), (.duration_seconds // empty | "\(.)s")] | join(", ")' "$dir/meta.json")"
  printf '\n## Turn %s: %s\n\n### Prompt\n\n' "$turn" "$outcome"
  cat "$dir/prompt.md" 2>/dev/null || true
  printf '\n### Response\n\n'
  cat "$dir/response.md" 2>/dev/null || true
}

ask() {
  resolve_agent "$1"
  shift
  parse_options "$@"
  read_prompt
  "${BACKEND}_start"
  [[ -z "$DRY_RUN" ]] || { preview; return 0; }
  create_run
  lock_run
  run_turn
}

# The lock and the recovery of killed turns come before anything else: a busy run fails before its prompt is read,
# and a killed first turn gets its CLI stopped and its session id recovered before the run is judged resumable. A
# dry run changes nothing, so it skips both.
resume() {
  load_run "${1-}"
  shift
  parse_options "$@"
  [[ -n "$DRY_RUN" ]] || { lock_run; reconcile_turns; }
  require_resumable
  read_prompt
  "${BACKEND}_resume" "$SESSION_ID"
  [[ -z "$DRY_RUN" ]] || { preview; return 0; }
  cd -- "$RUN_CWD"
  run_turn
}

# Prints the run's conversation as Markdown: each turn's prompt, then its response. An idle run's killed turns
# are finished first; a busy run's last turn shows as in progress.
show() {
  load_run "${1-}"
  [[ $# -le 1 ]] || die "unexpected argument '$2'."
  if try_lock_run; then
    reconcile_turns
    exec 9>&-
  fi
  printf '# %s run %s\n\nModel `%s`, started %s in `%s`.\n' "$AGENT" "$RUN_DIR" "$MODEL" "$CREATED" "$RUN_CWD"
  local turn=1
  while [[ -d "$RUN_DIR/turn-$turn" ]]; do
    show_turn "$RUN_DIR/turn-$turn" "$turn"
    turn=$((turn + 1))
  done
}

main() {
  case "${1:-}" in
    -h|--help) usage ;;
    -l|--list) list_agents ;;
    --resume)  shift; resume "$@" ;;
    --show)    shift; show "$@" ;;
    "")        usage >&2; die "missing <agent> argument." ;;
    -*)        usage >&2; die "unknown option '$1'." ;;
    *)         ask "$@" ;;
  esac
}

main "$@"
