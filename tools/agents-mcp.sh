#!/usr/bin/env bash
#
# agents-mcp.sh — Manage the project's MCP server config in the current directory.
#
# JSON is the single source of truth; the other formats are derived from it at runtime.
#   - .mcp.json          (JSON,  Claude Code)
#   - .codex/config.toml (TOML,  Codex    — converted from the JSON via jq)
#   - opencode.json      (JSON,  opencode — converted from the JSON via jq)
#
# Behavior:
#   - `add` writes all files into the current working directory. All MCP servers
#     are included by default; use -m/--mcp to pick a subset and -u/--uri to
#     override the postgres DATABASE_URI.
#   - `rm`  removes all files (and the .codex directory if left empty).
#   - Exit codes:
#       0    success
#       1    bad usage, missing dependency, or `rm` when no file exists

set -euo pipefail

readonly JSON_FILE=".mcp.json"
readonly TOML_FILE=".codex/config.toml"
readonly OPENCODE_FILE="opencode.json"

readonly JSON_CONFIG='{
  "mcpServers": {
    "postgres": {
      "command": "docker",
      "args": [
        "run",
        "-i",
        "--rm",
        "--net",
        "host",
        "-e",
        "DATABASE_URI",
        "crystaldba/postgres-mcp",
        "--access-mode=unrestricted"
      ],
      "env": {
        "DATABASE_URI": "postgres://human_ro@0.0.0.0:5432/database"
      }
    },
    "playwright": {
      "command": "docker",
      "args": [
        "run",
        "-i",
        "--rm",
        "--init",
        "--pull=always",
        "mcr.microsoft.com/playwright/mcp"
      ]
    }
  }
}'

# jq program converting the MCP JSON into Codex TOML: renames mcpServers ->
# mcp_servers, injects `enabled = true` per server, and emits an env table
# only for servers that define one.
readonly JQ_TO_TOML='
[ .mcpServers | to_entries[] |
  [ "[mcp_servers.\(.key)]",
    "command = \"\(.value.command)\"",
    "args = [" + (.value.args | map("\"\(.)\"") | join(", ")) + "]",
    "enabled = true"
  ]
  + (if .value.env then
      [ "", "[mcp_servers.\(.key).env]" ]
      + (.value.env | to_entries | map("\(.key) = \"\(.value)\""))
    else [] end)
  | join("\n")
] | join("\n\n")'

# jq program converting the MCP JSON into opencode JSON: renames mcpServers ->
# mcp, marks each server local, merges command+args into a single command
# array, and renames env -> environment (omitted when the server has no env).
readonly JQ_TO_OPENCODE='{
  mcp: (.mcpServers | with_entries(.value = {
    type: "local",
    command: ([.value.command] + .value.args)
  } + (if .value.env then {environment: .value.env} else {} end)))
}'

usage() {
  cat <<'EOF'
Usage:
  agents-mcp.sh add [-m|--mcp <name>]... [-u|--uri <database-uri>]
  agents-mcp.sh rm

Commands:
  add  Write .mcp.json, .codex/config.toml and opencode.json to the current directory.
         -m, --mcp <name>  MCP server to include; repeat to include several
                           (e.g. -m postgres -m playwright). Default: all.
         -u, --uri <uri>   Override the postgres DATABASE_URI.
  rm   Remove .mcp.json, .codex/config.toml and opencode.json from the current directory.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

contains() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

mcp_names() {
  jq -r '.mcpServers | keys[]' <<<"$JSON_CONFIG"
}

render_json_config() {
  local uri="$1"
  shift
  jq --arg uri "$uri" \
    --argjson names "$(printf '%s\n' "$@" | jq -Rn '[inputs]')" '
    .mcpServers |= with_entries(select(.key | IN($names[])))
    | if $uri != "" and .mcpServers.postgres then
        .mcpServers.postgres.env.DATABASE_URI = $uri
      else . end
  ' <<<"$JSON_CONFIG"
}

json_to_toml() {
  jq -r "$JQ_TO_TOML" <<<"$1"
}

json_to_opencode() {
  jq "$JQ_TO_OPENCODE" <<<"$1"
}

write_file() {
  local path="$1" content="$2"
  mkdir -p "$(dirname "$path")"
  echo "$content" >"$path"
  echo "wrote $path"
}

remove_file() {
  local path="$1"
  [[ -f "$path" ]] || die "no file to remove: $path"
  rm "$path"
  echo "removed $path"
}

add_config() {
  command -v jq >/dev/null || die "jq is required to generate the config files."

  local uri="" mcps=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--mcp)
        [[ -n "${2:-}" ]] || die "$1 requires a value."
        jq -e --arg name "$2" '.mcpServers | has($name)' <<<"$JSON_CONFIG" >/dev/null ||
          die "unknown MCP '$2'. Available: $(mcp_names | paste -sd ' ')."
        mcps+=("$2")
        shift 2
        ;;
      -u|--uri)
        [[ -n "${2:-}" ]] || die "$1 requires a value."
        uri="$2"
        shift 2
        ;;
      *)
        usage >&2
        die "unknown add option '$1'."
        ;;
    esac
  done

  [[ ${#mcps[@]} -gt 0 ]] || mapfile -t mcps < <(mcp_names)
  [[ -z "$uri" ]] || contains postgres "${mcps[@]}" ||
    die "--uri only applies to the postgres MCP."

  local json_config
  json_config="$(render_json_config "$uri" "${mcps[@]}")"

  local base="$(pwd)"
  write_file "$base/$JSON_FILE" "$json_config"
  write_file "$base/$TOML_FILE" "$(json_to_toml "$json_config")"
  write_file "$base/$OPENCODE_FILE" "$(json_to_opencode "$json_config")"
}

rm_config() {
  local base="$(pwd)"
  remove_file "$base/$JSON_FILE"
  remove_file "$base/$TOML_FILE"
  remove_file "$base/$OPENCODE_FILE"
  rmdir "$base/$(dirname "$TOML_FILE")" 2>/dev/null || true
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
    add)
      shift
      add_config "$@"
      ;;
    rm)
      rm_config
      ;;
    "")
      usage >&2
      die "missing <add|rm> argument."
      ;;
    *)
      usage >&2
      die "unknown command '$1'."
      ;;
  esac
}

main "$@"
