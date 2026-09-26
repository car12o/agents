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
│   ├── git-conventions/SKILL.md
│   └── git-flow/SKILL.md
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
| OpenCode (`opencode`) | `install-opencode`, `ask-agent glm/minimax/kimi/qwen/deepseek/grok/gemini` | reads `~/.config/opencode` |
| `jq` | `agents-mcp`, statusline | JSON parsing / TOML generation |
| `perl` | `ask-agent` | strips `<think>…</think>` blocks from responses |
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
- **Engineering principles** — defaults, overridden by a project's own instruction file or a loaded skill, on mindset, code quality, control flow (guard clauses, flat over nested, parse don't validate, no boolean parameters), design principles (SOLID/DRY/YAGNI/KISS as vocabulary, not dogma), architecture (dependencies point inward, pure core/impure shell), and structure (split by rate of change, colocate by feature).
- **Git** — the one always-loaded git rule: no AI/agent attribution in commits or PRs, overriding any harness default or project instruction. Everything else lives in the `git-conventions` skill.
- **Skill triggers** — a trigger table telling the agent to load the matching skill before an action (e.g. load `golang` before reading, editing, generating, or reviewing Go; `git-conventions` before branching, committing, pushing, or opening a PR).
- **Ask agent** — documentation for the `ask-agent` tool: read-only callee, agent table, exit codes, and the rules for fanning out to multiple agents in parallel.

---

## Skills

Skills are structured workflows packaged as a directory containing a `SKILL.md` with YAML frontmatter (`name`, `description`, and optionally the manual-only switches below). They are installed into each agent's `skills/` directory. A manual-only skill is invoked explicitly (e.g. as a slash command) and never auto-triggered by the model. Each runtime has its own switch, so manual-only skills carry both: `disable-model-invocation: true` in the frontmatter for Claude Code, and an `agents/openai.yaml` with `policy.allow_implicit_invocation: false` for Codex. OpenCode has no equivalent switch.

| Skill | Auto-invokable | What it does |
|-------|:--:|--------------|
| **golang** | ✅ | Self-contained ruleset for writing idiomatic, production-grade Go. Covers style/naming, error handling, concurrency, context, testing, performance, security, modules, JSON, database, production hardening, modern stdlib, tooling, project layout, and anti-patterns. Loaded automatically when touching `*.go`, `go.mod`, or `go.sum`. |
| **plan-doc** | ❌ (explicit) | Produces a structured implementation-plan document and saves it to `<repo root>/.agents/plans/<UTC timestamp>-<slug>.md`. The plan header records Type, Slug, Date, and Depends on; the body follows a required 11-section template (Goal, Context & Motivation, Scope, Dependencies & Risks, Design, Implementation Steps, Testing Strategy, Rollout & Migration, Open Questions, References, Revision Log). Splitting guidance keeps each plan PR-sized; a split set shares one timestamp with a two-digit sequence (`-01-`, `-02-`, …) in execution order and links prerequisites in Depends on. |
| **plan-implement** | ❌ (explicit) | Implements the newest (or specified) plan doc. Gates on prerequisites and blocking questions, then resumes the plan's `<type>/<slug>` branch or creates it from an up-to-date default per `git-conventions`, implements each step with its tests, verifies before every commit, and reports per-step status. Commits stay local; `git-flow pr` pushes and opens the PR. |
| **plan-review** | ❌ (explicit) | Reviews the newest (or specified) plan doc, or a whole split set in one run, using multiple AI agents via `review-fanout`. Checks the plan's structure against the plan-doc template itself, fans out the judgement checks with a self-contained prompt (template conventions, cited evidence, confidence), reviews the plan in parallel, then verifies and merges every finding. Clear fixes are applied to the plan file in place; anything that chooses a goal, scope, design, owner, or risk — including any proposed alternative design and every unresolved Blocking question — is put to the user as a numbered decision with a recommendation before the plan is edited. Ends with coverage, the Revision Log lines added, and a verdict mapped to plan-implement's gates. |
| **multi-code-review** | ❌ (explicit) | Reviews the current branch's changes against the base/HEAD branch using multiple AI agents via `review-fanout`. Syncs local refs and pins the change set, fans out to the agents, runs its own independent review across seven sections (Correctness, Security, Performance, Maintainability, Test coverage, Breaking changes, Alternative approaches), then verifies every finding before compiling a final report with paste-ready PR comments and per-agent coverage. |
| **review-fanout** | ✅ | Shared fan-out protocol for the two review skills: private prompt directory, agent selection, one background `ask-agent` call per agent from the repository root with responses kept in the prompt directory, one retry of empty or narration-only responses, response classes (usable / partial / timeout / error / empty / narration-only), the orchestrator's own review finished before any response is read, citation verification, deduplication into one canonical finding with its sources, the per-agent coverage line, and cleanup. Loaded by `plan-review` and `multi-code-review`; they reference it instead of restating it. |
| **git-conventions** | ✅ | Shared git ruleset: `origin` as the one remote (stop and ask otherwise), default-branch resolution from the remote (`git ls-remote --symref`, never guess) and no commits or pushes to it, `<type>/<slug>` branch naming with a fixed slug format and one creation procedure from a fresh `origin/<default>` (name checked locally and on origin), a closed Conventional Commits type table with subject, body, and breaking-change rules, commit hygiene (one logical change per commit, only the task's paths staged by path and checked in the index, no history rewriting, hooks never bypassed and hook rewrites detected), push rules (stop on any failure, never force), PR rules (Conventional Commits title, what/why/verification body, ready not draft), and the no-attribution rule. Loaded automatically before creating a branch, committing, pushing, or opening a PR; the other git-touching skills reference it instead of restating it. |
| **git-flow** | ❌ (explicit) | Stepped git flow: a preflight checks the selected steps against the repository (current branch, staged changes, commits ahead of the default branch, `gh` auth) before anything runs; then create a `<type>/<slug>` feature branch from an up-to-date default branch, commit already-staged changes as prepared (one commit per logical change, nothing pushed), and push and open a PR against the default branch (reporting an already-open PR instead). Run all three steps or select a subset by number or name (`branch`, `commit`, `pr`); selected steps always run in order. |

The `plan-doc → plan-review → plan-implement` skills form a pipeline: draft a plan, get it adversarially reviewed and refined, then execute it. `git-flow` covers the branch → commit → PR steps on their own and closes the pipeline: `plan-implement` leaves its commits local and hands off to `git-flow pr`. `git-flow` and `plan-implement` defer to `git-conventions` for default-branch, branch, commit, and push rules, `git-flow` also for PR rules; `multi-code-review` loads it only to resolve the default branch; `plan-review` and `multi-code-review` defer to `review-fanout` for the fan-out protocol.

---

## Tools

Standalone shell scripts symlinked onto your `PATH` (extension stripped) by `make install-tools`.

### `ask-agent`

Runs a one-shot prompt against an LLM agent CLI, wrapped in a **15-minute timeout**, in **read-only mode**.

```bash
ask-agent <agent> <prompt-file>
```

- The prompt is read from `<prompt-file>`. The script prepends critical rules forcing the agent into read-only mode and forbidding it from delegating to other agents.
- Once the prompt is accepted it prints **a single line to stdout: the path to a temp file** containing the agent's response (`<think>…</think>` blocks are stripped). That path — not the response — is the API contract; read the file after the process completes. On a non-zero exit the file holds whatever the agent produced before failing. A usage error prints nothing on stdout.
- `ask-agent --list` prints the agent names, one per line.
- **Exit codes:** `0` success · `2` bad usage (missing/unknown agent; prompt file missing, empty, or over 100 KB) · `124` 15-minute timeout reached · any other code propagated from the underlying CLI.

| Agent | Backend | Underlying command |
|-------|---------|--------------------|
| `claude` | Anthropic Claude Code | `claude -p --model claude-opus-5-5 --effort xhigh` |
| `codex` | OpenAI Codex | `codex exec --model gpt-5.6-sol` |
| `glm` | Zhipu GLM (via OpenCode) | `opencode run --model …/glm-5.3 --variant max` |
| `minimax` | MiniMax (via OpenCode) | `opencode run --model …/minimax-m3-coder` |
| `kimi` | Moonshot Kimi (via OpenCode) | `opencode run --model …/k3 --variant max` |
| `qwen` | Alibaba Qwen (via OpenCode) | `opencode run --model …/qwen3.8-max` |
| `deepseek` | DeepSeek (via OpenCode) | `opencode run --model …/deepseek-v4.1-flash --variant max` |
| `grok` | xAI Grok (via OpenCode) | `opencode run --model …/grok-4.7 --variant xhigh` |
| `gemini` | Google Gemini (via OpenCode) | `opencode run --model github-copilot/gemini-3.8-flash --variant high` |

This is the engine behind the `plan-review` and `multi-code-review` skills, which fan out to several of these agents in parallel and cross-check their findings.

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
