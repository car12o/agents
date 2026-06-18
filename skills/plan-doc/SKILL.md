---
name: plan-doc
description: Produce a structured implementation plan document and save it to disk. Use when asked to write, create, or generate an implementation plan, design doc, or technical spec for a feature or change.
---

# Skill: plan-doc

Produce a structured implementation plan document and save it to disk.

## Behavior

1. **Gather minimum required context before writing.** You need at minimum: (a) what is being built, (b) why it matters now. Ask only for these blockers; capture everything else as assumptions or Open Questions. Do not ask about non-blocking details.
2. **Derive the slug** from the plan's subject: lowercase ASCII, strip punctuation, collapse whitespace to single hyphens, ≤ 5 words (e.g. `auth-token-refresh`). If no clear subject exists, ask the user.
3. **Compute the timestamp** using the shell: `date +%Y%m%d%H%M%S` (YYYYMMDDHHMMSS).
4. **Write the plan** to `.agents/plans/<YYYYMMDDHHMMSS>-<slug>.md` relative to the working directory. Use `mkdir -p` to create the full path. Before writing, check whether the target path already exists; if it does, increment a numeric suffix (`<YYYYMMDDHHMMSS>-<slug>-2.md`, `-3.md`, …) until an unused filename is found.

**Splitting guidance:** Each plan must be an independently executable and reviewable unit of work — something that could be opened, reviewed, and merged as a standalone PR. Split when: the plan has more than ~10 implementation steps, it spans more than two major subsystems, or any section of it cannot be completed without first shipping a different section. When splitting, link the resulting plans to each other via References and note the execution order in Dependencies & Prerequisites.

## Plan Template

All top-level sections are required. When a section genuinely does not apply, keep its heading and write `Not applicable — <one-line reason>` beneath it. Within section 5 (Design), **Overview** and **Key decisions** are required; **Interfaces & signatures**, **Transport / payload shapes**, and **Schema & query skeletons** are optional — omitting them requires no explanation.

Examples: "Omit Transport for internal-only changes." "Omit Schema for non-persistent features." "Rollout: Not applicable — library release, no deployment step."

---

````markdown
# <Title>

**Date:** YYYY-MM-DD
**Slug:** <slug>

---

## 1. Goal

One paragraph. What are we building and why does it matter now?

**Success criteria:**
- Bullet list of measurable outcomes that define "done."
- How will we know this succeeded?

## 2. Context & Motivation

- What problem does this solve?
- Why is the current approach insufficient?
- Relevant prior art, ADRs, or linked issues.

## 3. Scope

### In scope
- Bullet list of what this plan covers.

### Out of scope
- Bullet list of explicitly excluded work.

## 4. Dependencies & Prerequisites

- Other plans or PRs this work depends on.
- External systems, services, or credentials required.
- Teams or people whose sign-off or output is needed before this can proceed.

## 5. Design

### Overview
Prose description of the approach. One to three paragraphs max.

### Key decisions
| Decision | Chosen approach | Alternatives considered |
|----------|-----------------|-------------------------|
| ...      | ...             | ...                     |

### Interfaces & signatures
<!-- Include ONLY for public APIs, exported functions, RPC methods, CLI commands.
     Omit for internal helpers. Snippets must show external contracts only, not full implementations. -->

```<lang>
// Example: exported function signature or interface definition
```

### Transport / payload shapes
<!-- Include ONLY for HTTP, gRPC, CLI, message-queue, or IPC boundaries.
     Show the schema or a representative example payload. -->

```json
// Example: request/response shape or protobuf-equivalent
```

### Schema & query skeletons
<!-- Include ONLY when a database schema or significant query is introduced.
     Show CREATE TABLE / migration skeleton or the query pattern, not full ORM boilerplate. -->

```sql
-- Example: table definition or query skeleton
```

## 6. Implementation Steps

Ordered list. Each step should be independently reviewable.

1. **Step title** — one-sentence description. Estimated size: XS (<1 hr) / S (<4 hr) / M (<1 day) / L (<1 week).
2. ...

## 7. Testing Strategy

- Unit: what to unit-test and why.
- Integration: what requires a real dependency (DB, network, etc.).
- Edge cases: list the non-obvious scenarios that must be covered.
- What is explicitly not tested and why.

## 8. Rollout & Migration

- Feature flags, dark launches, or staged rollouts required.
- Data migrations: reversible? downtime risk?
- Rollback plan.
- Success criteria / observability: how do you know the rollout succeeded? Logs, metrics, alerts, or dashboards to monitor.

> For non-deployed code (libraries, CLIs): describe the versioning strategy and how breaking changes will be communicated instead.

## 9. Open Questions

| # | Question | Owner | Due | Resolution |
|---|----------|-------|-----|------------|
| 1 | ...      | ...   | ... | ...        |

## 10. References

- Links to relevant issues, PRs, docs, RFCs, ADRs, or related plans.

## 11. Revision Log

- YYYY-MM-DD: Initial draft.
````

---

## Code-snippet rules

Only include code in subsections of section 5 (Interfaces & signatures, Transport / payload shapes, Schema & query skeletons). Do **not** add code snippets to Goal, Context, Dependencies, Steps, Testing, or Rollout. Snippets must show minimal external contracts or structural skeletons — not full implementations.
