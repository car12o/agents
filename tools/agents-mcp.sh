#!/usr/bin/env bash
#
# agents-mcp.sh — Manage the project's MCP server config in the current directory.
#
# JSON is the single source of truth; the TOML is derived from it at runtime.
#   - .mcp.json          (JSON,  Claude Code)
#   - .codex/config.toml (TOML,  Codex — converted from the JSON via jq)
#
# Behavior:
#   - `add` writes both files into the current working directory.
#   - `rm`  removes both files (and the .codex directory if left empty).
#   - Exit codes:
#       0    success
#       1    bad usage, missing dependency, or `rm` when no file exists

set -euo pipefail

readonly JSON_FILE=".mcp.json"
readonly TOML_FILE=".codex/config.toml"

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
        "DATABASE_URI": "postgres://human_ro@0.0.0.0:5433/alarm-processor"
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

usage() {
  cat <<'EOF'
Usage:
  agents-mcp.sh <add|rm>

Commands:
  add  Write .mcp.json and .codex/config.toml to the current directory.
  rm   Remove .mcp.json and .codex/config.toml from the current directory.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

json_to_toml() {
  jq -r "$JQ_TO_TOML" <<<"$JSON_CONFIG"
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
  command -v jq >/dev/null || die "jq is required to generate the TOML config."
  local base="$(pwd)"
  write_file "$base/$JSON_FILE" "$JSON_CONFIG"
  write_file "$base/$TOML_FILE" "$(json_to_toml)"
}

rm_config() {
  local base="$(pwd)"
  remove_file "$base/$JSON_FILE"
  remove_file "$base/$TOML_FILE"
  rmdir "$base/$(dirname "$TOML_FILE")" 2>/dev/null || true
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
    add)
      add_config
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
