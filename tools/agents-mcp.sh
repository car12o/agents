#!/usr/bin/env bash
#
# agents-mcp.sh — Manage the MCP servers of the project in the current directory,
# for Claude Code, Codex and opencode at once.
#
# Each server is defined once, as Claude Code JSON in the catalog below, and
# converted for the other agents:
#   - .mcp.json          (JSON, Claude Code)
#   - .codex/config.toml (TOML, Codex)
#   - opencode.json      (JSON, opencode)
# Only the MCP server entries in those files change; any other settings are
# kept, and a file is deleted once nothing else is left in it. A Codex edit is
# re-read with Python's TOML parser and refused when it would change anything
# but the edited servers.
#
# Usage (`agents-mcp.sh -h` for the full help):
#   agents-mcp.sh <mcp> [options]   add an MCP server, or replace its settings
#   agents-mcp.sh rm [<mcp>...]     remove the named servers, or all of them
#   agents-mcp.sh ls                list the servers and which ones are configured here
#   agents-mcp.sh pull [<mcp>...]   pull the Docker images of the named servers, or of all
#
# Needs jq and python3 3.11 or later; pull also needs docker.
# Colour is used when the output is a terminal; set NO_COLOR to turn it off.
# Exit status: 0 success; 1 bad usage, missing dependency, unparsable or
# uneditable config file, nothing to remove, or a failed image pull.

set -euo pipefail
# Most work runs in command substitutions, which would otherwise drop set -e.
shopt -s inherit_errexit

PROG=$(basename -- "$0" .sh)
readonly PROG

readonly FORMATS=(claude codex opencode)
declare -rA FILES=([claude]=.mcp.json [codex]=.codex/config.toml [opencode]=opencode.json)

# Each server's template holds its defaults, with "{image}" in args standing for
# its Docker image. Each flag changes the template in one of three ways: "env"
# sets that env var, "after" replaces the arg that follows the named one, and
# "append" (a switch) appends that arg. A "required" flag has no default and
# must be given; a "secret" one is never printed.
readonly CATALOG='{
  "elastic": {
    "about": "Elasticsearch, through docker.elastic.co/mcp/elasticsearch in Docker.",
    "image": "docker.elastic.co/mcp/elasticsearch",
    "server": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "--network", "host", "-e", "ES_URL", "-e", "ES_API_KEY", "{image}", "stdio"]
    },
    "flags": [
      {"short": "-u", "long": "--url", "value": "url", "env": "ES_URL", "required": true,
       "help": "Elasticsearch URL, passed as ES_URL."},
      {"short": "-k", "long": "--api-key", "value": "key", "env": "ES_API_KEY", "required": true, "secret": true,
       "help": "Elasticsearch API key, passed as ES_API_KEY."}
    ]
  },
  "grafana": {
    "about": "Grafana, through grafana/mcp-grafana in Docker.",
    "image": "grafana/mcp-grafana",
    "server": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "--network", "host", "-e", "GRAFANA_URL", "{image}", "-t", "stdio"],
      "env": {"GRAFANA_URL": "http://localhost:3000/"}
    },
    "flags": [
      {"short": "-u", "long": "--url", "value": "url", "env": "GRAFANA_URL",
       "help": "Grafana base URL, passed as GRAFANA_URL."}
    ]
  },
  "playwright": {
    "about": "A browser driven by @playwright/mcp, run with npx.",
    "server": {
      "command": "npx",
      "args": ["@playwright/mcp@latest", "--executable-path", "/usr/bin/brave"]
    },
    "flags": [
      {"short": "-e", "long": "--executable-path", "value": "path", "after": "--executable-path",
       "help": "Browser executable to drive."},
      {"short": "-a", "long": "--attach", "append": "--extension",
       "help": "Attach to your running browser (needs the Playwright Extension)."}
    ]
  },
  "postgres": {
    "about": "PostgreSQL with unrestricted (read-write) access, through crystaldba/postgres-mcp in Docker.",
    "image": "crystaldba/postgres-mcp",
    "server": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "--network", "host", "-e", "DATABASE_URI", "{image}", "--access-mode=unrestricted"],
      "env": {"DATABASE_URI": "postgres://postgres@localhost:5432/postgres"}
    },
    "flags": [
      {"short": "-u", "long": "--uri", "value": "uri", "env": "DATABASE_URI",
       "help": "Connection URI, passed as DATABASE_URI."}
    ]
  }
}'

readonly JQ_DEFS='
def document:
  if length > 1 then error("holds more than one JSON value") end
  | (.[0] // {})
  | if type != "object" then error("is not a JSON object") end;

def server_names($table):
  if type != "object" then error("\($table) is not an object") end
  | to_entries[]
  | if (.value | type) != "object" then error("\($table).\(.key) is not an object") end
  | .key;

def template($mcp):
  $mcp.server | .args |= map(if . == "{image}" then $mcp.image end);

def apply($flag; $value):
  if $flag.env then .env[$flag.env] = $value
  elif $flag.after then .args[(.args | index($flag.after)) + 1] = $value
  else .args += [$flag.append] end;

def setting($flag):
  ((.env | objects) // {}) as $env
  | ((.args | arrays) // []) as $args
  | if $flag.env then $env[$flag.env]
    elif $flag.after then ($args | index($flag.after)) as $i | if $i == null then null else $args[$i + 1] end
    else $args | index($flag.append) != null end;

def to_opencode:
  {type: "local", command: ([.command] + .args)} + (if .env then {environment: .env} else {} end);

def from_opencode:
  ((.command | arrays) // []) as $command
  | {command: $command[0], args: $command[1:], env: .environment}
  | with_entries(select(.value != null));

# opencode 2 keeps servers under mcp.servers and reserves mcp.timeout; older
# versions keep them directly under mcp, which opencode 2 still reads.
def opencode_servers:
  (.mcp // {})
  | if type != "object" then error("mcp is not an object") end
  | del(.servers, .timeout) + (.servers // {});

def mask:
  sub("(?<head>://[^:/@]*):[^/]*@"; "\(.head):****@")
  | gsub("(?<key>(?:^|[?&\\s])(?:ssl)?password=)(?:\\x27(?:[^\\x27\\\\]|\\\\.)*\\x27|[^&\\s]*)"; "\(.key)****");

def flag_usage: "\(.short), \(.long)" + (if .value then " <\(.value)>" else "" end);

def pad($width): . + " " * ($width - length);
'

# Reads, edits and checks the mcp_servers tables of a Codex config.toml. The
# current content comes on stdin; names, a server as JSON, or the new content
# go to stdout. A failure prints its reason on stderr and exits 1.
CODEX_PY=$(cat <<'PY'
import json
import re
import sys
import tomllib

KEY = r'(?:[A-Za-z0-9_-]+|"(?:[^"\\]|\\.)*"|\'[^\']*\')'
HEADER = re.compile(rf"\s*\[\[?\s*({KEY}(?:\s*\.\s*{KEY})*)\s*\]\]?\s*(?:#.*)?")


def parse(text):
    try:
        return tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        sys.exit(f"invalid TOML: {error}")


def servers(config):
    table = config.get("mcp_servers", {})
    if not isinstance(table, dict) or not all(isinstance(server, dict) for server in table.values()):
        sys.exit("mcp_servers is not a table of server tables")
    return table


def key_path(key):
    # tomllib decodes each quoted part exactly as TOML does.
    return [tomllib.loads(f"k = {part}")["k"] if part[0] in "\"'" else part
            for part in re.findall(KEY, key)]


def advance(line, string, depth):
    """Returns the multi-line string delimiter left open after line, and the
    depth of the brackets and braces of a value spanning lines."""
    i = 0
    while i < len(line):
        if string:
            if string == '"""' and line[i] == "\\":
                i += 2
            elif line.startswith(string, i):
                while line.startswith(string, i + 1):
                    i += 1
                string, i = None, i + 3
            else:
                i += 1
        elif line[i] == "#":
            break
        elif line.startswith(('"""', "'''"), i):
            string, i = line[i:i + 3], i + 3
        elif line[i] in "\"'":
            quote, i = line[i], i + 1
            while i < len(line) and line[i] != quote:
                i += 2 if quote == '"' and line[i] == "\\" else 1
            i += 1
        else:
            if line[i] in "[{":
                depth += 1
            elif line[i] in "]}":
                depth -= 1
            i += 1
    return string, depth


def sections(lines):
    """Splits lines into the preamble and one (key path, lines, kinds) section
    per table header. A section starts at the comments directly above its
    header and runs until the next section starts; a line is a header, comment,
    blank or other, and lines inside a multi-line value are all other."""
    kinds, paths = [], []
    string, depth = None, 0
    for line in lines:
        top = string is None and depth == 0
        header = HEADER.fullmatch(line) if top else None
        if header:
            kinds.append("header")
            paths.append(key_path(header[1]))
            continue
        if top and not line.strip():
            kinds.append("blank")
        elif top and line.lstrip().startswith("#"):
            kinds.append("comment")
        else:
            kinds.append("other")
        paths.append(None)
        string, depth = advance(line, string, depth)

    starts = []
    for index, kind in enumerate(kinds):
        if kind == "header":
            start = index
            while start > 0 and kinds[start - 1] == "comment":
                start -= 1
            starts.append((start, paths[index]))
    bounds = [start for start, _ in starts] + [len(lines)]
    return lines[:bounds[0]], [
        (path, lines[bounds[i]:bounds[i + 1]], kinds[bounds[i]:bounds[i + 1]])
        for i, (_, path) in enumerate(starts)
    ]


def owned(path, names):
    return len(path) > 1 and path[0] == "mcp_servers" and path[1] in names


def trimmed(lines):
    while lines and not lines[-1].strip():
        lines.pop()
    return lines


def toml_key(part):
    return part if re.fullmatch(r"[A-Za-z0-9_-]+", part) else json.dumps(part)


def render(name, server):
    # JSON strings and arrays of strings are valid TOML values.
    head = f"mcp_servers.{toml_key(name)}"
    lines = [f"[{head}]",
             f"command = {json.dumps(server['command'], ensure_ascii=False)}",
             f"args = {json.dumps(server.get('args', []), ensure_ascii=False)}",
             "enabled = true"]
    if server.get("env"):
        lines += ["", f"[{head}.env]"]
        lines += [f"{toml_key(k)} = {json.dumps(v, ensure_ascii=False)}" for k, v in server["env"].items()]
    return lines


def checked(lines, expected, names):
    """Returns lines as text once they parse to the expected config."""
    text = "\n".join(lines)
    try:
        actual = tomllib.loads(text)
    except tomllib.TOMLDecodeError:
        actual = None
    if without_empty_servers(actual) != without_empty_servers(expected):
        sys.exit(f"cannot edit {', '.join(names)} without changing other settings; an inline "
                 "table or dotted keys cannot be edited, so change the file by hand")
    return text


def without_empty_servers(config):
    if config is None or config.get("mcp_servers") != {}:
        return config
    return {key: value for key, value in config.items() if key != "mcp_servers"}


def list_names(config, lines):
    return "".join(f"{name}\n" for name in servers(config))


def show_server(config, lines, name):
    return json.dumps(servers(config)[name], default=str)


def put(config, lines, name, server_json):
    table = render(name, json.loads(server_json))
    expected = dict(config, mcp_servers={**servers(config), name: tomllib.loads("\n".join(table))["mcp_servers"][name]})
    preamble, parts = sections(lines)
    edited, placed = list(preamble), False
    for path, body, kinds in parts:
        if not owned(path, {name}):
            edited += body
        elif not placed:
            lead = kinds.index("header")
            tail = len(kinds)
            while tail > lead + 1 and kinds[tail - 1] in ("blank", "comment"):
                tail -= 1
            edited += body[:lead] + table + body[tail:]
            placed = True
    if not placed:
        edited = trimmed(edited)
        edited += ([""] if edited else []) + table
    return checked(trimmed(edited), expected, [name])


def delete(config, lines, *names):
    expected = dict(config, mcp_servers={key: value for key, value in servers(config).items() if key not in names})
    preamble, parts = sections(lines)
    edited = preamble + [line for path, body, _ in parts if not owned(path, names) for line in body]
    return checked(trimmed(edited), expected, names)


COMMANDS = {"names": list_names, "server": show_server, "put": put, "del": delete}

text = sys.stdin.read()
sys.stdout.write(COMMANDS[sys.argv[1]](parse(text), text.splitlines(), *sys.argv[2:]))
PY
)
readonly CODEX_PY

# Succeeds when stdin is not JSON but is JSON with comments or trailing commas,
# which opencode accepts. Strings are matched first, so their content is kept.
JSONC_PY=$(cat <<'PY'
import json
import re
import sys

STRING = r'"(?:[^"\\]|\\.)*"'


def without(pattern, text):
    return re.sub(rf"({STRING})|{pattern}", lambda match: match[1] or "", text, flags=re.S)


text = sys.stdin.read()
try:
    json.loads(text)
    sys.exit(1)
except ValueError:
    pass
try:
    json.loads(without(r",(?=\s*[}\]])", without(r"//[^\n]*|/\*.*?\*/", text)))
except ValueError:
    sys.exit(1)
PY
)
readonly JSONC_PY

# ----------------------------------------------------------------------- output

join_by() {  # join_by SEPARATOR ITEM...
  local separator=$1 first=${2:-}
  shift 2 || return 0
  printf '%s' "$first" "${@/#/$separator}"
}

max_length() {  # max_length ITEM... — length of the longest ITEM
  local item max=0
  for item; do ((${#item} <= max)) || max=${#item}; done
  echo "$max"
}

json_strings() {  # json_strings STRING... — the strings as a JSON array
  printf '%s\n' "$@" | jq -nRc '[inputs]'
}

FILE_WIDTH=$(max_length "${FILES[@]}")
readonly FILE_WIDTH

colour_enabled() {  # colour_enabled FD
  [[ -t $1 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]
}

if colour_enabled 1; then
  bold=$'\e[1m' dim=$'\e[2m' red=$'\e[31m' green=$'\e[32m' yellow=$'\e[33m' reset=$'\e[0m'
else
  bold='' dim='' red='' green='' yellow='' reset=''
fi
readonly bold dim red green yellow reset

declare -rA CHANGE_GLYPH=([created]='+' [updated]='~' [deleted]='-' [unchanged]='=')
declare -rA CHANGE_COLOUR=([created]=$green [updated]=$yellow [deleted]=$red [unchanged]=$dim)

die() {
  local prefix='error:'
  if colour_enabled 2; then prefix=$'\e[31merror:\e[0m'; fi
  printf '%s %s\n' "$prefix" "$*" >&2
  exit 1
}

usage_error() {
  die "$*"$'\n'"Run '$PROG -h' for usage."
}

print_change() {  # print_change FORMAT OUTCOME
  printf '  %s%s %-*s%s %s%s%s\n' "${CHANGE_COLOUR[$2]}" "${CHANGE_GLYPH[$2]}" "$FILE_WIDTH" "${FILES[$1]}" "$reset" \
    "$dim" "$2" "$reset"
}

# ---------------------------------------------------------------------- catalog

mcp_names() {
  jq -r 'keys[]' <<<"$CATALOG"
}

is_mcp() {
  jq -e --arg name "$1" 'has($name)' <<<"$CATALOG" >/dev/null
}

# Prints "<long>\t<value name>" for NAME's option OPT, the value name empty for
# a switch; fails when NAME has no such option.
find_flag() {  # find_flag NAME OPT
  jq -er --arg name "$1" --arg opt "$2" \
    'first(.[$name].flags[] | select(.short == $opt or .long == $opt)) | [.long, .value // ""] | @tsv' <<<"$CATALOG"
}

# Prints NAME's server JSON with the flags in VALUES, an object keyed by long
# flag, applied to its template.
render_server() {  # render_server NAME VALUES
  jq --arg name "$1" --argjson values "$2" "$JQ_DEFS"'
    .[$name] as $mcp
    | reduce ($mcp.flags[] | select($values[.long] != null)) as $flag
        (template($mcp); apply($flag; $values[$flag.long]))' <<<"$CATALOG"
}

# Prints the long names of NAME's required flags missing from VALUES, an object
# keyed by long flag, joined by ", "; empty when none is missing.
missing_flags() {  # missing_flags NAME VALUES
  jq -r --arg name "$1" --argjson values "$2" \
    '[.[$name].flags[] | select(.required and $values[.long] == null) | .long] | join(", ")' <<<"$CATALOG"
}

# Prints the options set in SERVER, NAME's server JSON, on one line, such as
# "uri postgres://… (default) · attach", with passwords and secrets masked.
settings_line() {  # settings_line NAME SERVER
  jq -r --arg name "$1" --argjson server "$2" --arg dim "$dim" --arg reset "$reset" "$JQ_DEFS"'
    .[$name] as $mcp
    | [ $mcp.flags[] as $flag
        | ($server | setting($flag)) as $value
        | select($value != null and $value != false)
        | ($flag.long | ltrimstr("--")) as $label
        | (if $value == true then $label
           else "\($dim)\($label)\($reset) \(if $flag.secret then "****" else $value | tostring | mask end)" end)
          + (if $value == ($mcp.server | setting($flag)) then " \($dim)(default)\($reset)" else "" end) ]
    | join(" \($dim)·\($reset) ")' <<<"$CATALOG"
}

# Prints NAME's description and options, as listed in the help.
mcp_block() {  # mcp_block NAME
  jq -r --arg name "$1" --arg bold "$bold" --arg dim "$dim" --arg reset "$reset" "$JQ_DEFS"'
    .[$name] as $mcp
    | ([$mcp.flags[] | flag_usage | length] | max) as $width
    | "  \($bold)\($name)\($reset)  \($mcp.about)",
      ( $mcp.flags[] as $flag
        | "    \($flag | flag_usage | pad($width))   \($flag.help)",
          ( if $flag.required then "Required." else $mcp.server | setting($flag) | strings | "Default: \(.)" end
            | "    \("" | pad($width))   \($dim)\(.)\($reset)" ) )' <<<"$CATALOG"
}

mcp_about() {  # mcp_about NAME
  jq -r --arg name "$1" '.[$name].about' <<<"$CATALOG"
}

mcp_image() {  # mcp_image NAME — empty when NAME does not run in Docker
  jq -r --arg name "$1" '.[$name].image // empty' <<<"$CATALOG"
}

# -------------------------------------------------------------- config formats
# Each format FORMAT has FORMAT_names, FORMAT_server, FORMAT_put and FORMAT_del.
# They read the file's current content on stdin and print the server names, a
# server in Claude Code's shape, or the new content; an empty new content means
# nothing is left and the file is deleted. Names and the server are only asked
# for after FORMAT_names has accepted the content.

claude_names() {
  jq -rs "$JQ_DEFS"'document | (.mcpServers // {}) | server_names("mcpServers")'
}

claude_server() {  # claude_server NAME < config
  jq -s --arg name "$1" "$JQ_DEFS"'document | .mcpServers[$name]'
}

claude_put() {  # claude_put NAME SERVER < config
  jq -s --arg name "$1" --argjson server "$2" "$JQ_DEFS"'document | .mcpServers[$name] = $server'
}

claude_del() {  # claude_del NAME... < config
  jq -s --argjson names "$(json_strings "$@")" "$JQ_DEFS"'
    document
    | del(.mcpServers[$names[]])
    | if .mcpServers == {} then del(.mcpServers) end
    | if . == {} then empty end'
}

opencode_names() {
  jq -rs "$JQ_DEFS"'document | opencode_servers | server_names("mcp")'
}

opencode_server() {  # opencode_server NAME < config
  jq -s --arg name "$1" "$JQ_DEFS"'document | opencode_servers[$name] | from_opencode'
}

# Writes under mcp.servers when the file already uses that layout, and directly
# under mcp otherwise, which every opencode version reads.
opencode_put() {  # opencode_put NAME SERVER < config
  jq -s --arg name "$1" --argjson server "$2" "$JQ_DEFS"'
    document
    | ($server | to_opencode) as $entry
    | if (.mcp.servers | type) == "object" then del(.mcp[$name]) | .mcp.servers[$name] = $entry
      else .mcp[$name] = $entry end'
}

opencode_del() {  # opencode_del NAME... < config
  jq -s --argjson names "$(json_strings "$@")" "$JQ_DEFS"'
    document
    | del(.mcp.servers[$names[]], .mcp[$names[]])
    | if .mcp.servers == {} then del(.mcp.servers) end
    | if .mcp == {} then del(.mcp) end
    | if . == {} then empty end'
}

codex_toml() {  # codex_toml COMMAND ARG... < config
  python3 -I -c "$CODEX_PY" "$@"
}

codex_names()  { codex_toml names; }
codex_server() { codex_toml server "$1"; }
codex_put()    { codex_toml put "$1" "$2"; }
codex_del()    { codex_toml del "$@"; }

# ---------------------------------------------------------------- config files

declare -A content=() configured=()

# Reads every config file in the current directory and the servers it holds;
# fails before anything is written when a file cannot be parsed.
load_configs() {
  python3 -I -c 'import tomllib' 2>/dev/null || die "python3 3.11 or later is required."
  local format file
  for format in "${FORMATS[@]}"; do
    file=${FILES[$format]}
    content[$format]=''
    if [[ -e $file ]]; then content[$format]=$(<"$file"); fi
    configured[$format]=$("${format}_names" <<<"${content[$format]}" 2>/dev/null) || unparsable "$format"
  done
}

# Stops, saying why FORMAT's file cannot be read: the parser's own error, or
# that it is JSON with comments, whose parser error would only mislead.
unparsable() {  # unparsable FORMAT
  local file=${FILES[$1]}
  if python3 -I -c "$JSONC_PY" <<<"${content[$1]}"; then
    die "$file has comments or trailing commas, which $PROG cannot keep; remove them first."
  fi
  "${1}_names" <<<"${content[$1]}" >/dev/null || true
  die "cannot parse $file."
}

has_server() {  # has_server FORMAT NAME
  [[ -n $2 ]] && grep -qxF -- "$2" <<<"${configured[$1]}"
}

is_configured() {  # is_configured NAME — whether any of the files holds NAME
  local format
  for format in "${FORMATS[@]}"; do
    if has_server "$format" "$1"; then return 0; fi
  done
  return 1
}

all_configured() {
  printf '%s\n' "${configured[@]}" | sed '/^$/d' | sort -u
}

# Prints NAME's server, in Claude Code's shape, from the first file holding it.
configured_server() {  # configured_server NAME
  local format
  for format in "${FORMATS[@]}"; do
    if has_server "$format" "$1"; then
      "${format}_server" "$1" <<<"${content[$format]}"
      return
    fi
  done
}

# Writes NEW to FORMAT's file, or deletes the file when NEW is empty, and
# prints what happened to it.
save() {  # save FORMAT NEW
  local file=${FILES[$1]} new=$2
  if [[ -z $new ]]; then
    rm -f -- "$file"
    if [[ $file == */* ]]; then rmdir -- "${file%/*}" 2>/dev/null || true; fi
    echo deleted
    return
  fi
  if [[ $new == "${content[$1]}" ]]; then
    echo unchanged
    return
  fi
  local outcome=updated
  if [[ ! -e $file ]]; then outcome=created; fi
  mkdir -p -- "$(dirname -- "$file")"
  printf '%s\n' "$new" >"$file"
  echo "$outcome"
}

# -------------------------------------------------------------------- commands

print_help() {
  local name blocks=()
  for name in $(mcp_names); do blocks+=("$(mcp_block "$name")"); done
  cat <<EOF
${bold}$PROG${reset} — manage the MCP servers of the project in the current directory,
for Claude Code, Codex and opencode at once.

${bold}Usage${reset}
  $PROG <mcp> [options]    Add an MCP server, or replace its settings.
  $PROG rm [<mcp>...]      Remove the named MCP servers, or all of them.
  $PROG ls                 List the MCP servers and which ones are configured here.
  $PROG pull [<mcp>...]    Pull the Docker images of the named MCP servers, or of all.
  $PROG [<mcp>] -h         Show this help, or one MCP server's options.

${bold}MCP servers${reset}
$(printf '%s\n\n' "${blocks[@]}")

${bold}Files${reset}
  .mcp.json (Claude Code), .codex/config.toml (Codex), opencode.json (opencode).
  Only their MCP server entries change; a file is deleted once nothing else is left in it.
  Adding a server that is already there replaces it: an option left out takes its default.
EOF
}

print_mcp_help() {  # print_mcp_help NAME
  cat <<EOF
${bold}Usage${reset}: $PROG $1 [options]
Adds the $1 MCP server, or replaces its settings: an option left out takes its default.

$(mcp_block "$1")
EOF
}

# Prints the help for -h or --help and rejects any other option and an empty
# name, for the commands that take only MCP server names.
names_only() {  # names_only COMMAND ARG...
  local arg
  for arg in "${@:2}"; do
    case $arg in
      -h|--help) print_help; exit 0 ;;
      -*) usage_error "unknown $1 option '$arg'." ;;
      '') usage_error "empty MCP server name." ;;
    esac
  done
}

add_server() {  # add_server NAME [OPTION]...
  local name=$1 spec long values='{}' missing server verb=Added format
  local hint=$'\n'"Run '$PROG $name -h' for its options."
  shift
  while (($#)); do
    case $1 in -h|--help) print_mcp_help "$name"; return ;; esac
    spec=$(find_flag "$name" "$1") || die "unknown $name option '$1'.$hint"
    long=${spec%%$'\t'*}
    if [[ -z ${spec#*$'\t'} ]]; then
      values=$(jq -c --arg long "$long" '.[$long] = true' <<<"$values")
      shift
      continue
    fi
    [[ -n ${2:-} ]] || die "$1 requires a value.$hint"
    values=$(jq -c --arg long "$long" --arg value "$2" '.[$long] = $value' <<<"$values")
    shift 2
  done
  missing=$(missing_flags "$name" "$values")
  [[ -z $missing ]] || die "$name requires $missing.$hint"

  server=$(render_server "$name" "$values")
  load_configs
  if is_configured "$name"; then verb=Updated; fi

  local -A new=() outcome=()
  for format in "${FORMATS[@]}"; do
    new[$format]=$("${format}_put" "$name" "$server" <<<"${content[$format]}") ||
      die "cannot update ${FILES[$format]}."
  done
  for format in "${FORMATS[@]}"; do
    outcome[$format]=$(save "$format" "${new[$format]}")
  done

  printf '%s✓%s %s %s%s%s\n' "$green" "$reset" "$verb" "$bold" "$name" "$reset"
  printf '  %s\n' "$(settings_line "$name" "$server")"
  for format in "${FORMATS[@]}"; do print_change "$format" "${outcome[$format]}"; done
}

remove_servers() {  # remove_servers [NAME]...
  names_only rm "$@"
  load_configs
  local names=("$@") name format targets
  if (($# == 0)); then
    mapfile -t names < <(all_configured)
    ((${#names[@]})) || die "no MCP servers configured in $PWD."
  fi
  for name in "${names[@]}"; do
    is_configured "$name" || die "$name is not configured in $PWD."
  done

  local -A new=() outcome=()
  for format in "${FORMATS[@]}"; do
    targets=()
    for name in "${names[@]}"; do
      if has_server "$format" "$name"; then targets+=("$name"); fi
    done
    ((${#targets[@]})) || continue
    new[$format]=$("${format}_del" "${targets[@]}" <<<"${content[$format]}") ||
      die "cannot update ${FILES[$format]}."
  done
  for format in "${FORMATS[@]}"; do
    if [[ -v new[$format] ]]; then outcome[$format]=$(save "$format" "${new[$format]}"); fi
  done

  mapfile -t names < <(printf '%s\n' "${names[@]}" | sort -u)
  printf '%s✓%s Removed %s%s%s\n' "$green" "$reset" "$bold" "$(join_by ', ' "${names[@]}")" "$reset"
  for format in "${FORMATS[@]}"; do
    if [[ -v outcome[$format] ]]; then print_change "$format" "${outcome[$format]}"; fi
  done
}

# Prints one ls row: a configured server with its settings, or a catalog server
# that is not configured with its description. A server missing from some of
# the files is flagged, as the agents reading those files will not see it.
print_server() {  # print_server NAME WIDTH
  local name=$1 width=$2 format missing=() detail=''
  for format in "${FORMATS[@]}"; do
    if ! has_server "$format" "$name"; then missing+=("${FILES[$format]}"); fi
  done

  if ((${#missing[@]} == ${#FORMATS[@]})); then
    printf '  %s○ %-*s  %s%s\n' "$dim" "$width" "$name" "$(mcp_about "$name")" "$reset"
    return
  fi

  if is_mcp "$name"; then
    detail=$(settings_line "$name" "$(configured_server "$name")")
  else
    detail="${dim}not in the $PROG catalog${reset}"
  fi
  if ((${#missing[@]})); then
    detail+="${detail:+ $dim·$reset }${yellow}missing from $(join_by ', ' "${missing[@]}")${reset}"
  fi
  printf '  %s✓%s %s%-*s%s  %s\n' "$green" "$reset" "$bold" "$width" "$name" "$reset" "$detail"
}

list_servers() {
  names_only ls "$@"
  (($# == 0)) || usage_error "ls takes no arguments."
  load_configs
  local names name width
  mapfile -t names < <({ mcp_names; all_configured; } | awk '!seen[$0]++')
  width=$(max_length "${names[@]}")

  printf '%sMCP servers%s %sin %s%s\n' "$bold" "$reset" "$dim" "$PWD" "$reset"
  for name in "${names[@]}"; do print_server "$name" "$width"; done
}

# Pulls IMAGE and prints whether it was updated; on a terminal, a progress line
# shows while the pull runs, since docker's own output is captured.
pull_image() {  # pull_image IMAGE WIDTH
  local image=$1 width=$2 log failed=false status
  if [[ -t 1 ]]; then printf '  %s↓ %-*s  pulling…%s' "$dim" "$width" "$image" "$reset"; fi
  log=$(docker pull "$image" 2>&1) || failed=true
  if [[ -t 1 ]]; then printf '\r\e[2K'; fi

  if [[ $failed == true ]]; then
    printf '  %s✗%s %-*s  %s%s%s\n' "$red" "$reset" "$width" "$image" "$red" "$(tail -n 1 <<<"$log")" "$reset"
    return 1
  fi
  case $log in
    *'Image is up to date'*) status="${dim}up to date${reset}" ;;
    *'Downloaded newer image'*) status="${green}updated${reset}" ;;
    *) status="${green}pulled${reset}" ;;
  esac
  printf '  %s✓%s %-*s  %s\n' "$green" "$reset" "$width" "$image" "$status"
}

pull_images() {  # pull_images [NAME]...
  names_only pull "$@"
  command -v docker >/dev/null || die "docker is required to pull images."
  local images=() name image width failed=0
  if (($# == 0)); then
    mapfile -t images < <(jq -r '[.[].image // empty] | unique[]' <<<"$CATALOG")
  fi
  for name in "$@"; do
    is_mcp "$name" || usage_error "unknown MCP server '$name'."
    image=$(mcp_image "$name")
    [[ -n $image ]] || die "$name has no Docker image: it runs through $(jq -r --arg name "$name" '.[$name].server.command' <<<"$CATALOG")."
    images+=("$image")
  done
  width=$(max_length "${images[@]}")

  local noun=images
  if ((${#images[@]} == 1)); then noun=image; fi
  printf '%sPulling %d %s%s\n' "$bold" "${#images[@]}" "$noun" "$reset"
  for image in "${images[@]}"; do
    pull_image "$image" "$width" || failed=$((failed + 1))
  done
  ((failed == 0)) || exit 1
}

main() {
  command -v jq >/dev/null || die "jq is required."
  local subcommand=${1:-}
  if (($#)); then shift; fi
  case $subcommand in
    '') usage_error "missing command or MCP server." ;;
    -h|--help) print_help ;;
    ls) list_servers "$@" ;;
    rm) remove_servers "$@" ;;
    pull) pull_images "$@" ;;
    *)
      is_mcp "$subcommand" ||
        usage_error "unknown command or MCP server '$subcommand'. MCP servers: $(mcp_names | paste -sd ' ')."
      add_server "$subcommand" "$@"
      ;;
  esac
}

main "$@"
