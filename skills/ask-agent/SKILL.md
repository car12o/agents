---
name: ask-agent
description: Ask another agent's CLI (claude, codex, glm, kimi, …) for a read-only second opinion, review, or research, and continue that conversation later. Use when the user asks to consult another agent or model, or when another skill says to. Never use it when you were invoked through ask-agent yourself.
---

# Skill: ask-agent

Runs a prompt against another agent's CLI. The agent loads its CLI's user and project settings, instructions (AGENTS.md, CLAUDE.md), skills, and MCP servers; it can read anywhere, search, and use the network, but cannot write files or delegate to other agents. Use it for review, analysis, and research, never for work that must modify files. MCP servers run outside every sandbox, so a write-capable server stays write-capable.

The script is `ask-agent.sh` in the directory holding this SKILL.md; `<ask-agent>` below is its full path. It is not on `PATH`. If it is missing, say so; do not substitute another mechanism.

## Calls

```bash
<ask-agent> <agent> 'Short prompt, no apostrophe'
<ask-agent> <agent> --prompt-file <path>
<ask-agent> <agent> <<'EOF'
<prompt>
EOF
<ask-agent> --resume <run> <prompt, in any of the three forms>
<ask-agent> --show <run>
<ask-agent> --list
```

- `<agent>` is a name `--list` prints; `--help` also shows each agent's backend.
- The prompt comes from exactly one source: one argument, `--prompt-file <path>`, or stdin when neither is given. It is 100 KB or less. Agents read the repository themselves: give them paths, intent, constraints, and settled decisions, never file content.
- Keep the prompt neutral: ask the question, not your answer. Include your own conclusion only to have it checked, and then ask the agent to verify or reject it with reasoning.
- The shell expands an argument before the script sees it: use the argument form only for short text in single quotes with no apostrophe. Text with an apostrophe, a backtick, or `$` goes on stdin through a heredoc with a quoted delimiter (`<<'EOF'`), or in a file.
- Call from the directory the prompt's relative paths start from; in a repository, its root. A resume always runs in the run's original directory.
- `--timeout <duration>`, a non-zero `timeout` duration such as `30m`, replaces the 15-minute default.
- `--dry-run` prints the command a call would run, and where. It starts no agent and changes nothing; it runs only the read-only lookups the command needs (git, and `codex mcp list` for Codex).

## Output

Each call creates a run directory under `$TMPDIR` (default `/tmp`); each turn adds a `turn-N/` that is never overwritten:

| File           | Holds                                                                                         |
|----------------|-----------------------------------------------------------------------------------------------|
| `prompt.md`    | The caller's prompt; the read-only rules are prepended when it is sent                        |
| `events.jsonl` | The CLI's raw event stream: every message, tool call, and tool result                         |
| `stderr.log`   | The CLI's stderr                                                                              |
| `response.md`  | The agent's response; on a failed turn, whatever text it produced                             |
| `meta.json`    | Exit code, status (`ok`, `timeout`, `stopped`, `error`), duration, error, session id, and backend stats such as cost or permission denials |

Once the prompt is accepted, stdout gets the agent's response on every exit. The last stderr line summarises the turn, run and turn first: `ask-agent: run /tmp/ask-agent-glm.Ab12Cd turn 1, glm ok, exit 0, 17s`, followed by `; reason: <reason>` when the turn failed. `--resume` and `--show` take that run; the response is also in `<run>/turn-<N>/response.md`. The CLI's own stderr stays in `stderr.log`. An earlier stderr line, `ask-agent: run <run> turn <N>, <agent> started`, names the run as the agent starts, so a call killed before its summary can still be resumed or shown; a call with no `ask-agent: run` line never started a run.

A TERM, INT, or HUP stops the agent, with a SIGKILL 30 s later, and still finishes the turn, with exit 143. A turn whose script was killed outright never finishes on its own: the next `--resume` or `--show` that finds the run idle stops its agent if it still runs, marks the turn `stopped`, and recovers its session id and partial text, so the run stays resumable.

| Exit         | Meaning                                                                                                       |
|--------------|---------------------------------------------------------------------------------------------------------------|
| `0`          | Success                                                                                                       |
| `64`         | Bad usage: unknown agent or run, busy run, missing, doubled, empty, or oversized prompt, or invalid timeout. Nothing on stdout, no run created |
| `124`, `137` | Timeout: the agent was stopped, with a SIGKILL for `137`                                                      |
| `143`        | Stopped: the script was told to stop, and stopped the agent                                                   |

Any other code is the CLI's own, propagated.

## Rules

1. **Independent calls run in parallel, in the background.** One direct call per agent through the host's background mechanism, never chained or serialized: a foreground call is subject to the host's own timeout, which can be shorter than the call needs. If the host has no background mode, run one shell call with its timeout at the maximum, `(<ask-agent> <agent> --prompt-file <path>; echo "<agent> exit $?") &` per agent then `wait`; a bare `wait` discards the exit codes. Run calls in sequence only when a prompt depends on an earlier response.
2. **Agents asked the same question get the same prompt file.**
3. **Check the exit code before trusting the response:** a non-zero exit means it is partial or absent.
4. **Resume rather than relaunch.** `--resume <run>` continues the same session by its exact id, so the agent keeps everything it read: use it for a follow-up, to ask again for an answer that came back malformed or cut short, or to salvage a timeout with a short `--timeout` and a request to report what it has. A run takes one turn at a time; a resume of a busy run exits 64. To continue a conversation whose turns are no longer in your context, read `--show <run>` first.
5. **Never delete a run directory.** Deleting it ends the conversation, since nothing else records its session id; the OS clears temporary files on its own.
