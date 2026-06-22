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
├── skills/                       # Reusable agent workflows (one dir per skill)
│   ├── golang/SKILL.md
│   ├── plan-doc/SKILL.md
│   ├── plan-implement/SKILL.md
│   ├── plan-review/SKILL.md
│   └── multi-code-review/SKILL.md
├── tools/                        # Standalone shell scripts installed onto PATH
│   ├── ask-agent.sh
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
| Claude Code (`claude`) | `install-claude`, `ask-agent claude` | reads `~/.claude/CLAUDE.md` and `~/.claude/skills` |
| Codex (`codex`) | `install-codex`, `ask-agent codex` | reads `~/.codex/AGENTS.md` and `~/.codex/skills` |
| OpenCode (`opencode`) | `install-opencode`, `ask-agent glm/minimax/kimi/qwen/deepseek` | reads `~/.config/opencode` |
| `jq` | `agents-mcp`, statusline | JSON parsing / TOML generation |
| `perl` | `ask-agent` | strips `<think>…</think>` blocks from responses |
| `docker` | the MCP config produced by `agents-mcp` | runs the `postgres-mcp` server |
| `git` | `git-release`, statusline | release branching, branch display |

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

For tools, it symlinks every `tools/*.sh` into `~/.local/bin`, **dropping the `.sh` extension** (so `ask-agent.sh` becomes the command `ask-agent`). Make sure `~/.local/bin` is on your `PATH`.

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
- **Engineering principles** — mandatory rules on mindset, code quality, design principles (SOLID/DRY/YAGNI/KISS as vocabulary, not dogma), architecture (dependencies point inward, pure core/impure shell), and structure (split by rate of change, colocate by feature).
- **Language skills** — a trigger table telling the agent to load the matching skill before reading/editing a file (e.g. load `skills/golang` for `*.go`).
- **Available tools** — documentation for the `ask-agent` tool, including the agent table, exit codes, and the mandatory rules for fanning out to multiple agents in parallel.

---

## Skills

Skills are structured workflows packaged as a directory containing a `SKILL.md` with YAML frontmatter (`name`, `description`, and optionally `disable-model-invocation`). They are installed into each agent's `skills/` directory. Skills with `disable-model-invocation: true` are **not** auto-triggered by the model — they're meant to be invoked explicitly (e.g. as a slash command).

| Skill | Auto-invokable | What it does |
|-------|:--:|--------------|
| **golang** | ✅ | Self-contained ruleset for writing idiomatic, production-grade Go. Covers style/naming, error handling, concurrency, context, testing, performance, security, modules, JSON, database, production hardening, modern stdlib, tooling, project layout, and anti-patterns. Loaded automatically when touching `*.go`, `go.mod`, or `go.sum`. |
| **plan-doc** | ✅ | Produces a structured implementation-plan document and saves it to `.agents/plans/<timestamp>-<slug>.md`. Enforces a required template (Goal, Design, Steps, Testing, Scope, Dependencies, Open Questions, Revision Log) and splitting guidance so each plan is an independently reviewable, PR-sized unit. |
| **plan-implement** | ❌ (explicit) | Implements the most recent (or specified) plan doc. Locates the plan, creates a `<type>/<slug>` feature branch if on the HEAD branch, and commits in logical chunks using Conventional Commits. |
| **plan-review** | ❌ (explicit) | Reviews a plan doc using multiple AI agents (via `ask-agent`), independently verifies their findings against the plan and repo, and applies the verified findings directly back to the plan file. |
| **multi-code-review** | ❌ (explicit) | Reviews the current branch's changes against the base/HEAD branch using multiple AI agents in parallel. Syncs local refs, fans out to the agents, runs its own independent review across six dimensions (Correctness, Security, Performance, Maintainability, Test coverage, Breaking changes), then verifies every finding before compiling a final report. |

The `plan-doc → plan-review → plan-implement` skills form a pipeline: draft a plan, get it adversarially reviewed and refined, then execute it.

---

## Tools

Standalone shell scripts symlinked onto your `PATH` (extension stripped) by `make install-tools`.

### `ask-agent`

Runs a one-shot prompt against an LLM agent CLI, wrapped in a **15-minute timeout**, in **read-only mode**.

```bash
ask-agent <agent> <prompt-file>
```

- The prompt is read from `<prompt-file>`. The script prepends critical rules forcing the agent into read-only mode and forbidding it from delegating to other agents.
- On success it prints **a single line to stdout: the path to a temp file** containing the agent's response (`<think>…</think>` blocks are stripped). That path — not the response — is the API contract; read the file after the process completes.
- **Exit codes:** `0` success · `2` bad usage (missing/unknown agent, missing/empty prompt file) · `124` 15-minute timeout reached · `*` propagated from the underlying CLI.

| Agent | Backend | Underlying command |
|-------|---------|--------------------|
| `claude` | Anthropic Claude Code | `claude -p --model claude-opus-4-8` |
| `codex` | OpenAI Codex | `codex exec --skip-git-repo-check` |
| `glm` | Zhipu GLM (via OpenCode) | `opencode run --model …/glm-5.2-max` |
| `minimax` | MiniMax (via OpenCode) | `opencode run --model …/minimax-m3-coder` |
| `kimi` | Moonshot Kimi (via OpenCode) | `opencode run --model …/kimi-k2.7-code` |
| `qwen` | Alibaba Qwen (via OpenCode) | `opencode run --model …/qwen3.7-plus` |
| `deepseek` | DeepSeek (via OpenCode) | `opencode run --model …/deepseek-v4-pro` |

This is the engine behind the `plan-review` and `multi-code-review` skills, which fan out to several of these agents in parallel and cross-check their findings.

### `agents-mcp`

Manages a project-local **MCP server config** in the current working directory. JSON is the single source of truth; the Codex TOML is derived from it at runtime via `jq`.

```bash
agents-mcp add <database>
agents-mcp rm
```

- `add <database>` — writes `.mcp.json` (Claude Code format), `.codex/config.toml` (Codex format), and `opencode.json` (opencode format) into the current directory. The bundled config defines a `postgres` MCP server that runs `crystaldba/postgres-mcp` via Docker in restricted/read-only access mode and points `DATABASE_URI` at `<database>`.
- `rm` — removes all generated files and the `.codex` directory if left empty.
- **Exit codes:** `0` success · `1` bad usage, missing `jq`, or `rm` with no file present.

### `git-release`

Cuts a release branch by bumping the latest semver git tag.

```bash
git-release <patch|minor|major>
```

- Switches to the current branch, pulls, reads the latest tag via `git describe --tags`, bumps the requested component, then creates and pushes a `release/<new-version>` branch from `origin/<current-branch>`.
- Errors out if there are no tags or the latest tag isn't valid semver.

---

## Statusline

`statusline/statusline-command.sh` is a Claude Code **statusline renderer**. It reads Claude's status JSON from stdin and prints a single colored line containing:

- Model display name and current directory
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
