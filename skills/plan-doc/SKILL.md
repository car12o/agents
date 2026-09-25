---
name: plan-doc
description: Produce a structured implementation plan document and save it to disk. Use when asked to write, create, or generate an implementation plan for a feature or change.
disable-model-invocation: true
---

# Skill: plan-doc

## Behavior

1. **Gather context.** You need two answers from the user: what is being built, and why it matters now. Ask only when one is missing; if the user cannot answer, stop and report what is missing. Then read the code, tests, and docs the change touches and cite their paths in the plan. Record every other unknown as an Assumption or an Open Question.
2. **Decide whether to split.** Each plan must be mergeable as a standalone PR. Split when the plan has more than 10 implementation steps, spans more than two separately built, deployed, or owned components, or contains work that cannot start until another part has shipped. Order the plans so every prerequisite precedes its dependents; each plan names its prerequisites in `Depends on` and its siblings in References.
3. **Derive type and slug.** Type is the `git-conventions` commit prefix of the plan's dominant change: `feat`, `fix`, `refactor`, `docs`, `test`, or `chore`; ask when it is not obvious. Slug: lowercase the subject, replace every run of characters outside `[a-z0-9]` with one hyphen, trim hyphens, keep the first five words; ask if the result is empty. Each split plan gets its own slug.
4. **Name the file.** Plans live in `<root>/.agents/plans/`, where `<root>` is `git rev-parse --show-toplevel`, or the working directory outside a git repository. A single plan is `$(date -u +%Y%m%d%H%M%S)-<slug>.md`. A split set shares one timestamp and adds a two-digit sequence in execution order: `<timestamp>-01-<slug>.md`, `<timestamp>-02-<slug>.md`, ….
5. **Write the plan.** Run `mkdir -p <root>/.agents/plans`, then fill the template below. Its prompts are instructions to you: replace them with content and never copy them into the plan.
6. **Report.** List each written path with a one-line summary, in execution order, and name `plan-review` as the next step. Do not reproduce plan content in chat.

## Plan Template

All numbered sections are required. When one genuinely does not apply, keep its heading and write `Not applicable — <one-line reason>`. For non-deployed code (libraries, CLIs), section 8 describes the versioning strategy and how breaking changes are communicated.

In section 5, Overview and Key decisions are required. The three code subsections are optional; delete the heading of any you omit, no explanation needed:

- **Interfaces & signatures** — only for public APIs, exported functions, RPC methods, or CLI commands.
- **Transport / payload shapes** — only at HTTP, gRPC, CLI, message-queue, or IPC boundaries.
- **Schema & query skeletons** — only when a database schema or a significant query is introduced.

Code appears only inside those three subsections and shows minimal external contracts or structural skeletons, never full implementations.

In section 6, no step is larger than M; decompose anything bigger. In section 9, Blocking is `yes` or `no` and Resolution stays blank until the question is resolved.

---

````markdown
# <Title>

**Type:** <feat | fix | refactor | docs | test | chore>
**Slug:** <slug>
**Date:** <date of the filename timestamp, YYYY-MM-DD>
**Depends on:** <relative paths of prerequisite plans, or none>

---

## 1. Goal

One paragraph: what is being built and why it matters now.

**Success criteria:**
- Measurable outcomes that define "done".

## 2. Context & Motivation

- What problem does this solve, and why is the current approach insufficient?
- Prior art that motivates the design, cited by name; links go in References.

**Assumptions:**
- Claims this plan relies on that were not confirmed.

## 3. Scope

### In scope
- What this plan covers.

### Out of scope
- Explicitly excluded work.

## 4. Dependencies & Risks

- PRs or other work this plan depends on; sibling plans are listed in Depends on.
- External systems, services, or credentials required.
- Teams or people whose sign-off or output is needed before this can proceed.
- Known risks and their mitigations.

## 5. Design

### Overview
Prose description of the approach, one to three paragraphs.

### Key decisions
| Decision | Chosen approach | Alternatives considered | Why rejected |
|----------|-----------------|-------------------------|--------------|

### Interfaces & signatures

### Transport / payload shapes

### Schema & query skeletons

## 6. Implementation Steps

Ordered list; each step is one independently reviewable change.

1. **Step title** — one-sentence description. Verify: how to confirm the step is done. Size: XS (<1 hr) / S (<4 hr) / M (<1 day).

## 7. Testing Strategy

- Unit: what to unit-test and why.
- Integration: what requires a real dependency (DB, network, etc.).
- Edge cases: the non-obvious scenarios that must be covered.
- What is explicitly not tested and why.

## 8. Rollout & Migration

- Feature flags, dark launches, or staged rollouts required.
- Data migrations: reversible? downtime risk?
- Rollback plan.
- Observability: logs, metrics, alerts, or dashboards that show the rollout succeeded.

## 9. Open Questions

| # | Question | Blocking | Owner | Due | Resolution |
|---|----------|----------|-------|-----|------------|

## 10. References

- Links to relevant issues, PRs, docs, RFCs, ADRs, and sibling plans by relative path.

## 11. Revision Log

- YYYY-MM-DD: Initial draft.
````
