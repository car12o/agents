# agents

A portable configuration and tooling kit for AI coding agents — **Claude Code**, **OpenAI Codex**, and **OpenCode**.

This repo is the **single source of truth** for one engineer's agent setup. Everything lives here under version control and is pushed onto each agent's expected config location via **symlinks**, so editing a file in this repo updates every installed agent live — no re-install needed.

It ships four things:

1. A shared instruction file (`AGENTS.md`) describing how the agents should behave and reason.
2. A set of **skills** — reusable, structured workflows the agents can invoke.
3. A set of **tools** — standalone shell scripts installed onto your `PATH`.
4. A **statusline** script for Claude Code's prompt.

---

## Table of contents

- [Repository layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
  - [What `make install` does](#what-make-install-does)
  - [Where things are installed](#where-things-are-installed)
- [Makefile commands](#makefile-commands)
- [The configuration file (`AGENTS.md`)](#the-configuration-file-agentsmd)
- [Skills](#skills)
- [Tools](#tools)
- [Statusline](#statusline)
- [Uninstall](#uninstall)

---

## Repository layout

```
.
├── AGENTS.md                     # Shared agent instructions (single source of truth)
├── CLAUDE.md                     # Symlink → AGENTS.md (so Claude Code picks up the same file)
├── Makefile                      # install / uninstall targets for all agents + tools
├── skills/                       # Reusable agent workflows (one dir per skill; manual-only ones also carry agents/openai.yaml)
│   ├── golang/SKILL.md
│   ├── plan-doc/SKILL.md
│   ├── plan-implement/SKILL.md
│   ├── plan-review/SKILL.md
│   ├── multi-code-review/SKILL.md
│   ├── review-fanout/SKILL.md
│   ├── ask-agent/                # SKILL.md + ask-agent.sh, called from the skill directory
│   ├── git-conventions/SKILL.md
│   └── git-flow/SKILL.md
├── tools/                        # Standalone shell scripts installed onto PATH
│   ├── agents-mcp.sh
│   └── git-release.sh
└── statusline/
    └── statusline-command.sh     # Claude Code statusline renderer
```

---

## Prerequisites

The installer itself only needs `make` and a POSIX shell. The individual agents and tools have their own runtime dependencies — install only what you actually use:

| Dependency | Needed by | Notes |
|------------|-----------|-------|
| `make`     | the installer | core requirement |
| Claude Code (`claude`) | `install-claude`, the `ask-agent` skill's `claude` agent | reads `~/.claude/CLAUDE.md` and `~/.claude/skills` |
| Codex (`codex`) | `install-codex`, the `ask-agent` skill's `codex` agent | reads `~/.codex/AGENTS.md` and `~/.codex/skills` |
| OpenCode (`opencode`) | `install-opencode`, the `ask-agent` skill's `glm/minimax/kimi/qwen/deepseek/grok/gemini` agents | reads `~/.config/opencode` |
| `jq` 1.7+ | `agents-mcp`, `ask-agent`, statusline | JSON parsing / TOML generation; `ask-agent` needs `--raw-output0` |
| `perl` | `ask-agent` | strips `<think>…</think>` blocks from responses |
| `timeout`, `flock`, `env --default-signal` | `ask-agent` | coreutils and util-linux: the call's time limit, the one-turn-per-run lock, and SIGINT for background launches |
| `bubblewrap`, `socat` | `ask-agent`'s `claude` agent | Claude Code's Bash sandbox on Linux; without them the `claude` call fails, since the sandbox is required |
| `docker` | the MCP config produced by `agents-mcp` | runs the `postgres-mcp` and `playwright` MCP servers |
| `git` | `git-release`, `git-flow`, statusline | release branching, feature branching, branch display |
| `gh` | `git-flow`, `multi-code-review` | opens PRs, reads PR title/body/comments |

> The installer **skips** any agent whose config directory does not exist, printing a `WARNING` instead of failing. You can have only Claude installed and `make install` will still work — it just won't touch Codex or OpenCode.

---

## Installation

From the repo root:

```bash
make install
```

This runs four sub-targets: `install-claude`, `install-codex`, `install-opencode`, and `install-tools`.

### What `make install` does

Everything is wired up with **symlinks pointing back into this repo**. Nothing is copied. That means:

- Edits to `AGENTS.md` or any `skills/*/SKILL.md` take effect immediately for every installed agent.
- Removing this repo from disk **breaks** the installed agents (the symlinks dangle) — uninstall first, or keep the repo in place.

Per agent, the installer:

1. Symlinks the shared instruction file into the agent's config dir.
   - Claude: `~/.claude/CLAUDE.md`
   - Codex: `~/.codex/AGENTS.md`
   - OpenCode: `~/.config/opencode/AGENTS.md`
2. Creates a `skills/` directory inside that config dir and symlinks **every** skill directory from `skills/` into it.

For tools, it symlinks every `tools/*.sh` into `~/.local/bin`, **dropping the `.sh` extension** (so `git-release.sh` becomes the command `git-release`). Make sure `~/.local/bin` is on your `PATH`.

Existing files/symlinks at the targets are removed first (`rm -f` / `rm -rf`), so re-running `make install` is idempotent.

### Where things are installed

| Source in repo | Installed to | Created by |
|----------------|-------------|------------|
| `AGENTS.md` | `~/.claude/CLAUDE.md` (symlink) | `install-claude` |
| `skills/*/` | `~/.claude/skills/*` (symlinks) | `install-claude` |
| `AGENTS.md` | `~/.codex/AGENTS.md` (symlink) | `install-codex` |
| `skills/*/` | `~/.codex/skills/*` (symlinks) | `install-codex` |
| `AGENTS.md` | `~/.config/opencode/AGENTS.md` (symlink) | `install-opencode` |
| `skills/*/` | `~/.config/opencode/skills/*` (symlinks) | `install-opencode` |
| `tools/*.sh` | `~/.local/bin/<name>` (symlinks, no `.sh`) | `install-tools` |

> The `statusline/` script is **not** installed by the Makefile — see [Statusline](#statusline) for how to wire it in.

---

## Makefile commands

| Target | Description |
|--------|-------------|
| `make install` | Run all four install targets below. |
| `make uninstall` | Run all four uninstall targets below. |
| `make install-claude` | Symlink `AGENTS.md` → `~/.claude/CLAUDE.md` and all skills into `~/.claude/skills`. Skips if `~/.claude` is missing. |
| `make uninstall-claude` | Remove the Claude symlinks. |
| `make install-codex` | Symlink `AGENTS.md` → `~/.codex/AGENTS.md` and all skills into `~/.codex/skills`. Skips if `~/.codex` is missing. |
| `make uninstall-codex` | Remove the Codex symlinks. |
| `make install-opencode` | Symlink `AGENTS.md` → `~/.config/opencode/AGENTS.md` and all skills into `~/.config/opencode/skills`. Skips if `~/.config/opencode` is missing. |
| `make uninstall-opencode` | Remove the OpenCode symlinks. |
| `make install-tools` | Symlink every `tools/*.sh` into `~/.local/bin` (extension stripped). Always runs; creates `~/.local/bin` if needed. |
| `make uninstall-tools` | Remove the tool symlinks from `~/.local/bin`. |

---

## The configuration file (`AGENTS.md`)

`AGENTS.md` is the shared system-prompt-level instruction set loaded by every agent. `CLAUDE.md` is just a symlink to it, so all three agents read the identical content. It defines:

- **Interaction** — substance (expert, verified, confidence-tagged claims; no hallucination), tone (blunt, no hedging), and stance (no flattery, lead with the counterargument, don't capitulate without new evidence).
- **Engineering principles** — defaults, overridden by a project's own instruction file or a loaded skill, on mindset, code quality, control flow (guard clauses, flat over nested, parse don't validate, no boolean parameters), design principles (SOLID/DRY/YAGNI/KISS as vocabulary, not dogma), architecture (dependencies point inward, pure core/impure shell), and structure (split by rate of change, colocate by feature).
- **Git** — the one always-loaded git rule: no AI/agent attribution in commits or PRs, overriding any harness default or project instruction. Everything else lives in the `git-conventions` skill.
- **Skill triggers** — a trigger table telling the agent to load the matching skill before an action (e.g. load `golang` before reading, editing, generating, or reviewing Go; `git-conventions` before branching, committing, pushing, or opening a PR).

---

## Skills

Skills are structured workflows packaged as a directory containing a `SKILL.md` with YAML frontmatter (`name`, `description`, and optionally the manual-only switches below). They are installed into each agent's `skills/` directory. A manual-only skill is invoked explicitly (e.g. as a slash command) and never auto-triggered by the model. Each runtime has its own switch, so manual-only skills carry both: `disable-model-invocation: true` in the frontmatter for Claude Code, and an `agents/openai.yaml` with `policy.allow_implicit_invocation: false` for Codex. OpenCode has no equivalent switch.

| Skill | Auto-invokable | What it does |
|-------|:--:|--------------|
| **golang** | ✅ | Self-contained ruleset for writing idiomatic, production-grade Go. Covers style/naming, error handling, concurrency, context, testing, performance, security, modules, JSON, database, production hardening, modern stdlib, tooling, project layout, and anti-patterns. Loaded automatically when touching `*.go`, `go.mod`, or `go.sum`. |
| **plan-doc** | ❌ (explicit) | Produces a structured implementation-plan document and saves it to `<repo root>/.agents/plans/<UTC timestamp>-<slug>.md`. The plan header records Type, Slug, Date, and Depends on; the body follows a required 11-section template (Goal, Context & Motivation, Scope, Dependencies & Risks, Design, Implementation Steps, Testing Strategy, Rollout & Migration, Open Questions, References, Revision Log). Splitting guidance keeps each plan PR-sized; a split set shares one timestamp with a two-digit sequence (`-01-`, `-02-`, …) in execution order and links prerequisites in Depends on. |
| **plan-implement** | ❌ (explicit) | Implements the newest (or specified) plan doc. Gates on prerequisites and blocking questions, then resumes the plan's `<type>/<slug>` branch or creates it from an up-to-date default per `git-conventions`, implements each step with its tests, verifies before every commit, and reports per-step status. Commits stay local; `git-flow pr` pushes and opens the PR. |
| **plan-review** | ❌ (explicit) | Reviews the newest (or specified) plan doc, or a whole split set in one run, using multiple AI agents via `review-fanout`. Checks the plan's structure against the plan-doc template itself, fans out the judgement checks with a self-contained prompt (template conventions, cited evidence, confidence), reviews the plan in parallel, then verifies and merges every finding. Clear fixes, and decisions the evidence settles, are applied to the plan file in place; only decisions with no clear best option — real tradeoffs, missing owners or dates, risk acceptance, Blocking questions nothing answers, a goal or design replacement, a split — are put to the user as a numbered decision with a recommendation before the plan is edited. A decision is carried through every part of the plan that assumed the old text, with the structural checks and split triggers re-run; a choice it leaves open becomes an open question for the user. Ends with coverage, the Revision Log lines added, and a verdict of ready to execute or not ready with what unblocks it. |
| **multi-code-review** | ❌ (explicit) | Reviews the current branch's changes against the base/HEAD branch using multiple AI agents via `review-fanout`. Syncs local refs and pins the change set, fans out to the agents, runs its own independent review across seven sections (Correctness, Security, Performance, Maintainability, Test coverage, Breaking changes, Alternative approaches), then verifies every finding before compiling a final report with paste-ready PR comments and per-agent coverage. |
| **review-fanout** | ✅ | Shared fan-out protocol for the two review skills: private prompt directory, agent selection from the `ask-agent` skill's `--list`, one background `ask-agent` call per agent from the repository root, with its stdout discarded so no response reaches the orchestrator early and every run kept in the prompt directory, at most one retry per agent by resuming its session (an empty or narration-only response asked again for the answer; a timeout asked for its findings so far; a transient failure asked to continue) with findings from both attempts counted, response classes (usable / partial / timeout / error / empty / narration-only), the orchestrator's own review finished before any response is read, citation verification, deduplication into one canonical finding with its sources, the per-agent coverage line, and stopping calls still running; runs are kept for follow-up questions. Loaded by `plan-review` and `multi-code-review`; they reference it instead of restating it, and it loads `ask-agent` for the call itself. |
| **ask-agent** | ✅ | Runs a prompt against another agent's CLI (Claude Code, Codex, or an OpenCode model) that loads the CLI's user and project settings, instructions, skills, and MCP servers, can read anywhere, search, and use the network, but cannot write files, and resumes the conversation by its exact session id. The script lives in the skill directory, not on `PATH`, so a caller has to load the skill to find it. The response comes back on stdout; each call also keeps a run directory under `/tmp`, never deleted by the skills, with the prompt, the CLI's raw event stream, its stderr, the response, and per-turn metadata, and `--show` prints a run's whole conversation. See [`ask-agent`](#ask-agent) below. |
| **git-conventions** | ✅ | Shared git ruleset: `origin` as the one remote (stop and ask otherwise), default-branch resolution from the remote (`git ls-remote --symref`, never guess) and no commits or pushes to it, `<type>/<slug>` branch naming with a fixed slug format and one creation procedure from a fresh `origin/<default>` (name checked locally and on origin), a closed Conventional Commits type table with subject, body, and breaking-change rules, commit hygiene (one logical change per commit, only the task's paths staged by path and checked in the index, no history rewriting, hooks never bypassed and hook rewrites detected), push rules (stop on any failure, never force), PR rules (Conventional Commits title, what/why/verification body, ready not draft), and the no-attribution rule. Loaded automatically before creating a branch, committing, pushing, or opening a PR; the other git-touching skills reference it instead of restating it. |
| **git-flow** | ❌ (explicit) | Stepped git flow: a preflight checks the selected steps against the repository (current branch, staged changes, commits ahead of the default branch, `gh` auth) before anything runs; then create a `<type>/<slug>` feature branch from an up-to-date default branch, commit already-staged changes as prepared (one commit per logical change, nothing pushed), and push and open a PR against the default branch (reporting an already-open PR instead). Run all three steps or select a subset by number or name (`branch`, `commit`, `pr`); selected steps always run in order. |

The `plan-doc → plan-review → plan-implement` skills form a pipeline: draft a plan, get it adversarially reviewed and refined, then execute it. `git-flow` covers the branch → commit → PR steps on their own and closes the pipeline: `plan-implement` leaves its commits local and hands off to `git-flow pr`. `git-flow` and `plan-implement` defer to `git-conventions` for default-branch, branch, commit, and push rules, `git-flow` also for PR rules; `multi-code-review` loads it only to resolve the default branch; `plan-review` and `multi-code-review` defer to `review-fanout` for the fan-out protocol, which calls the agents through `ask-agent`.

### `ask-agent`

```bash
<skill-dir>/ask-agent.sh <agent> [<prompt> | --prompt-file <path>] [--timeout <duration>] [--dry-run]
<skill-dir>/ask-agent.sh --resume <run> [<prompt> | --prompt-file <path>] [--timeout <duration>] [--dry-run]
<skill-dir>/ask-agent.sh --show <run>
<skill-dir>/ask-agent.sh --list
```

- `<skill-dir>` is the installed skill directory, such as `~/.claude/skills/ask-agent`; the script is not on `PATH`.
- The prompt is one argument (`ask-agent.sh glm 'say hello'`), the file given to `--prompt-file`, or stdin when neither is given (`echo 'say hello' | ask-agent.sh glm`, or a heredoc). It is 100 KB or less and is prepended with read-only, no-delegation, non-interactive rules. `--timeout <duration>`, non-zero, replaces the 15-minute default; `--dry-run` prints the command a call would run, `timeout` wrapper included; it starts no agent and changes nothing, running only the read-only lookups the command needs (git, and `codex mcp list` for Codex).
- Every agent loads its CLI's user and project settings, instructions (`AGENTS.md`, `CLAUDE.md`), skills, and MCP servers, reads anywhere, searches, and uses the network, but cannot write files. Each backend enforces that on every turn, with settings that outrank the project's:
  - Codex: a permission profile that extends `:read-only` with the network on, an OS-level sandbox that blocks writes even to `/tmp`, under a random name per turn so a project config cannot extend it. The project is trusted for the call so its `.codex/config.toml` loads, every configured MCP server's tools are pre-approved, and both sub-agent features are disabled.
  - Claude Code: no file-editing tool, `bypassPermissions` for the remaining tools, and Bash in Claude Code's sandbox, which refuses to run unsandboxed and may write only to a private temp directory; writes to the repository's shared `.git` are denied too, which the sandbox would otherwise open from a linked worktree. The sandbox comes from `--settings`, which a repository's own settings cannot loosen.
  - OpenCode: `--standalone` with an agent that allows every tool except edits, questions, sub-agents, and the browser, and a shell limited to git read commands without `--output` or redirects; it reaches the network through its web tools. It has no OS sandbox. The inline config outranks the user's and the project's. The shared background service would ignore that agent and keep a killed turn running; the web search provider is preselected, since `opencode run` cancels the consent prompt and fails the search.
- MCP servers run outside every sandbox: a write-capable server, such as the unrestricted postgres server `agents-mcp` adds, stays write-capable for the agent.
- The caller's session identity variables (`CLAUDE_CODE_MESSAGING_*`, `CODEX_THREAD_ID`, …) are not passed on.
- Claude Code and OpenCode list the session as `ask-agent <agent>: <first prompt line>`, so reviewer sessions are recognisable in their own session pickers. Codex has no session-name flag.
- Each call creates `$TMPDIR/ask-agent-<agent>.XXXXXX/`, holding:
  - `run.json`: agent, backend, model, working directory, and session id.
  - One `turn-N/` per turn: `prompt.md` (the caller's prompt), `events.jsonl` (the CLI's raw event stream), `stderr.log`, `response.md`, and `meta.json` (exit code, status, duration, error, and backend stats).
- Run directories are never deleted by the skills: deleting one loses the session id, and the OS clears `/tmp` on its own.
- Once the prompt is accepted, stdout gets the agent's response on every exit. A stderr line names the run as the agent starts (`ask-agent: run <run> turn <N>, <agent> started`), so a call killed before its summary can still be found; the last stderr line summarises the turn, run and turn first, such as `ask-agent: run /tmp/ask-agent-glm.Ab12Cd turn 1, glm ok, exit 0, 17s`, with `; reason: <reason>` appended on failure.
- `--resume <run>` continues the run's session by its exact id, from the run's original directory, one turn at a time. `--show <run>` prints the whole conversation as Markdown, each turn's prompt followed by its response.
- A TERM, INT, or HUP to the script stops the agent's process group, with a SIGKILL 30 s later, and still finishes the turn. A turn whose script was killed outright is finished by the next `--resume` or `--show` that finds the run idle: it stops the agent if it still runs, marks the turn `stopped`, and recovers its session id and partial text from the event stream.
- **Exit codes:** `0` success · `64` bad usage (unknown agent or run, busy run, missing, doubled, empty, or oversized prompt, invalid timeout) · `124` timeout, `137` when the timeout needed a SIGKILL · `143` stopped by a signal · any other code propagated from the CLI.

| Agent | Backend | Model |
|-------|---------|-------|
| `claude` | Claude Code | `claude-opus-5-5`, effort `xhigh` |
| `codex` | Codex | `gpt-6.1-sol` |
| `glm` | OpenCode | `llm-netdata-cloud/glm-5.3#high` |
| `minimax` | OpenCode | `llm-netdata-cloud/minimax-m3.1-flash` |
| `kimi` | OpenCode | `llm-netdata-cloud/k3#high` |
| `qwen` | OpenCode | `llm-netdata-cloud/qwen3.8-max` |
| `deepseek` | OpenCode | `llm-netdata-cloud/deepseek-v4.1-flash#high` |
| `grok` | OpenCode | `llm-netdata-cloud/grok-4.7#xhigh` |
| `gemini` | OpenCode | `github-copilot/gemini-3.8-flash#high` |

---

## Tools

Standalone shell scripts symlinked onto your `PATH` (extension stripped) by `make install-tools`.

### `agents-mcp`

Manages a project-local **MCP server config** in the current working directory. JSON is the single source of truth; the Codex TOML and opencode JSON are derived from it at runtime via `jq`.

```bash
agents-mcp add [-m|--mcp <name>]... [-u|--uri <database-uri>]
agents-mcp rm
```

- `add` — writes `.mcp.json` (Claude Code format), `.codex/config.toml` (Codex format), and `opencode.json` (opencode format) into the current directory. Two MCP servers are bundled, both run via Docker:
  - `postgres` — `crystaldba/postgres-mcp` in **unrestricted** access mode, with `DATABASE_URI` defaulting to `postgres://human_ro@0.0.0.0:5432/database`. Override it with `-u/--uri`.
  - `playwright` — `mcr.microsoft.com/playwright/mcp`.

  All servers are included by default; pass `-m/--mcp <name>` (repeatable) to include only a subset. `--uri` is rejected unless `postgres` is among the selected servers.
- `rm` — removes all generated files and the `.codex` directory if left empty.
- **Exit codes:** `0` success · `1` bad usage, missing `jq`, or `rm` with no file present.

### `git-release`

Cuts a release branch by bumping the latest semver git tag.

```bash
git-release <patch|minor|major>
```

- Resolves the repository's default branch (from `origin/HEAD`, falling back to `git remote show origin`), switches to it, and pulls fast-forward only.
- Reads the latest tag via `git describe --tags --abbrev=0`, extracts its `MAJOR.MINOR.PATCH` component (so `v1.2.3` works), bumps the requested part, then creates and pushes a `release/<new-version>` branch from `origin/<default-branch>`.
- Errors out if the default branch cannot be determined, there are no tags, or the latest tag does not contain a `MAJOR.MINOR.PATCH` version.

---

## Statusline

`statusline/statusline-command.sh` is a Claude Code **statusline renderer**. It reads Claude's status JSON from stdin and prints a single colored line containing:

- Model display name, reasoning effort level (when present), and current directory
- Git branch (if inside a repo)
- A 10-segment context-usage bar that shifts green → yellow → red as usage climbs
- Session cost in USD and elapsed wall-clock time
- 5-hour and 7-day rate-limit usage percentages (when present), each color-coded

It depends on `jq` and `git`. It is **not** installed by the Makefile — wire it into Claude Code yourself by pointing your `statusLine` setting at the script, e.g. in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/absolute/path/to/this/repo/statusline/statusline-command.sh"
  }
}
```

---

## Uninstall

```bash
make uninstall
```

Removes all symlinks created by the installer (the `CLAUDE.md`/`AGENTS.md` links, the per-agent skill links, and the tool links in `~/.local/bin`). It does **not** delete the agent config directories themselves or anything in this repo.
