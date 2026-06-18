#!/usr/bin/env bash
#
# ask-agent.sh — Run a one-shot prompt against an LLM agent CLI, with a 15m timeout cap.
#
# Intended to be invoked from any tool to get a quick second opinion or delegate a task to a specific agent.
#
# Behavior:
#   - Prompt is read from the file at <prompt-file>.
#   - Underlying agent call is wrapped in `timeout 15m`.
#   - Exit codes:
#       0    success
#       2    bad usage (missing agent, unknown agent, missing/empty prompt file)
#       124  `timeout` killed the agent (15m cap reached)
#       *    propagated from the agent CLI
#
# Examples:
#   ask-agent.sh codex ./review-prompt.md
#   ask-agent.sh claude ./summarize.txt
#   ask-agent.sh glm ./big-prompt.md

set -euo pipefail

readonly TIMEOUT="15m"
readonly VALID_AGENTS="claude, codex, glm, minimax, kimi, qwen, deepseek"
readonly RULES='⚠️ ⚠️ ⚠️  CRITICAL RULES — YOU MUST OBEY THESE WITHOUT EXCEPTION  ⚠️ ⚠️ ⚠️

1. You are running in **READ-ONLY MODE**. You MUST NOT create, modify, or delete
   any files. You MUST NOT execute any write commands. You may ONLY read files
   and search the codebase.

2. You are COMPLETELY FORBIDDEN from using the "Ask agent" tool (or any
   equivalent sub-agent / delegation mechanism). Do NOT invoke `ask-agent`,
   or anything similar. Perform the task yourself directly.

---
'

usage() {
  cat <<'EOF'
Usage:
  ask-agent.sh <agent> <prompt-file>

Agents:
  claude    Anthropic Claude Code
  codex     OpenAI Codex
  glm       Zhipu GLM (via opencode)
  minimax   MiniMax (via opencode)
  kimi      Moonshot Kimi (via opencode)
  qwen      Alibaba Qwen (via opencode)
  deepseek  DeepSeek (via opencode)

The prompt is read from <prompt-file>.
The agent call is wrapped in `timeout 15m`.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 2
}

# Sets the global CMD array based on the agent name.
resolve_agent() {
  case "$1" in
    claude)   CMD=(claude -p --model claude-opus-4-8) ;;
    codex)    CMD=(codex exec --skip-git-repo-check) ;;
    glm)      CMD=(opencode run --model llm-netdata-cloud/glm-5.2-max) ;;
    minimax)  CMD=(opencode run --model llm-netdata-cloud/minimax-m3-coder) ;;
    kimi)     CMD=(opencode run --model llm-netdata-cloud/kimi-k2.7-code) ;;
    qwen)     CMD=(opencode run --model llm-netdata-cloud/qwen3.7-plus) ;;
    deepseek) CMD=(opencode run --model llm-netdata-cloud/deepseek-v4-pro) ;;
    *)        die "unknown agent '$1'. Valid agents: $VALID_AGENTS" ;;
  esac
}

# Validates the prompt file and sets the global PROMPT_FILE.
prepare_prompt() {
  local file="${1:-}"
  [[ -n "$file" ]] || die "missing <prompt-file> argument."
  [[ -f "$file" ]] || die "prompt file not found: $file"
  [[ -s "$file" ]] || die "prompt file is empty: $file"
  PROMPT_FILE="$file"
}

run_agent() {
  local agent="$1"
  local out
  out="$(mktemp -t "${agent}-output.XXXXXX")"
  timeout "$TIMEOUT" "${CMD[@]}" "$(echo "$RULES" && cat "$PROMPT_FILE")" \
    | perl -0777 -pe 's/<think>.*?<\/think>\n?//gs' >"$out"
  echo "$out"
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
    "")
      usage >&2
      die "missing <agent> argument."
      ;;
  esac

  local agent="$1"
  resolve_agent "$agent"
  prepare_prompt "${2:-}"
  run_agent "$agent"
}

main "$@"
