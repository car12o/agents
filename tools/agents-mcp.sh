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
#   - `add` writes all files into the current working directory.
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
        "--access-mode=restricted"
      ],
      "env": {
        "DATABASE_URI": "postgres://human_ro@0.0.0.0:5432/database"
      }
    }
  }
}'

# jq program converting the MCP JSON into Codex TOML: renames mcpServers ->
# mcp_servers and injects `enabled = true` per server.
readonly JQ_TO_TOML='
[ .mcpServers | to_entries[] |
  "[mcp_servers.\(.key)]",
  "command = \"\(.value.command)\"",
  "args = [" + (.value.args | map("\"\(.)\"") | join(", ")) + "]",
  "enabled = true",
  "",
  "[mcp_servers.\(.key).env]",
  (.value.env | to_entries[] | "\(.key) = \"\(.value)\"")
] | join("\n")'

# jq program converting the MCP JSON into opencode JSON: renames mcpServers ->
# mcp, marks each server local, merges command+args into a single command
# array, and renames env -> environment.
readonly JQ_TO_OPENCODE='{
  mcp: (.mcpServers | to_entries | map({
    key: .key,
    value: {
      type: "local",
      command: ([.value.command] + .value.args),
      environment: .value.env
    }
  }) | from_entries)
}'

usage() {
  cat <<'EOF'
Usage:
  agents-mcp.sh add [database-uri]
  agents-mcp.sh rm

Commands:
  add  Write .mcp.json, .codex/config.toml and opencode.json to the current directory.
       Pass [database-uri] to override the default DATABASE_URI.
  rm   Remove .mcp.json, .codex/config.toml and opencode.json from the current directory.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

render_json_config() {
  local uri="$1"
  jq --arg uri "$uri" '.mcpServers.postgres.env.DATABASE_URI = $uri' <<<"$JSON_CONFIG"
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
  local uri="${1:-}"
  command -v jq >/dev/null || die "jq is required to generate the TOML config."

  local json_config="$JSON_CONFIG"
  [[ -n "$uri" ]] && json_config="$(render_json_config "$uri")"

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
      [[ $# -le 2 ]] || die "add accepts an optional [database-uri] argument."
      add_config "${2:-}"
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
