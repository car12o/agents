---
name: plan-review
description: Review a plan doc written by the plan-doc skill with multiple AI agents, verify their findings, and apply the verified fixes to the plan file in place. Use when asked to review, audit, or critique a plan written by plan-doc.
disable-model-invocation: true
---

# Skill: plan-review

Review a plan with multiple AI agents, verify and merge their findings with your own, put every real tradeoff to the user, then apply the fixes to the plan file. Load `review-fanout`; it governs the prompt file, background launch, response classes, your own review, verification and merging, coverage, and cleanup.

## Step 1 — Locate the plan

If the user provided a path, resolve it to an absolute path; stop if it is not a readable file. Otherwise take the newest plan under the repository root; filenames start with a UTC timestamp, so name order is creation order:

```bash
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
find "$root/.agents/plans" -maxdepth 1 -name '*.md' 2>/dev/null | sort | tail -1
```

If the command prints nothing, no plan exists: stop and tell the user.

A plan is one of a split set when other plans share its 14-digit timestamp. Review the whole set in one run, in sequence order; if the user named one plan, review only that one and pass its siblings as context. Every step below applies to each plan under review.

## Step 2 — Check structure

Read the plan in full and check it against the plan-doc template yourself, before any agent runs:

- Header: `Type` is `feat`, `fix`, `refactor`, `docs`, `test`, or `chore`; `Slug` matches the filename; `Date` matches the filename timestamp; `Depends on` is `none` or names plans in the same directory, without a cycle.
- Sections 1–11 present in order, each with content or `Not applicable — <reason>`; section 5's three code subsections are optional.
- Every step in section 6 has a `Verify` condition and a `Size` of XS, S, or M.
- Every test in section 7 and every code-level item in section 8 (migrations, flags, rollback hooks) is scheduled by a step.
- Every row in section 9 has Blocking `yes` or `no`, and Resolution is blank unless the question is resolved.

A file without the plan-doc header is not a plan: stop and tell the user. Record every other miss as a finding of your own, in the format below, for Step 5 to categorize.

## Step 3 — Write the prompt file

Write the block below to the prompt file per `review-fanout`, filling the placeholders and deleting the two optional lines when they do not apply.

```
Plans under review, in execution order:
<one absolute path per line>
Split-set siblings not under review, for context: <absolute paths — optional line>
Context the plans do not record: <user constraints or settled decisions — optional line>

Read each plan first. The repository is checked out locally; read the files a plan references to verify its claims.

The plans follow a fixed template. Do not report what it permits:

- Header (Type, Slug, Date, Depends on) and eleven numbered sections: 1 Goal, 2 Context & Motivation, 3 Scope, 4 Dependencies & Risks, 5 Design, 6 Implementation Steps, 7 Testing Strategy, 8 Rollout & Migration, 9 Open Questions, 10 References, 11 Revision Log.
- A section may read `Not applicable — <reason>`; report it only if the reason is false.
- Section 5's Interfaces & signatures, Transport / payload shapes, and Schema & query skeletons subsections are optional; code appears only there, as contracts or skeletons, never implementations.
- Each step in section 6 is one independently reviewable change with a Verify condition and a Size: XS (<1 hr), S (<4 hr), M (<1 day); nothing larger. Every test in section 7 and every code-level item in section 8 belongs to the step that introduces the behaviour it covers.
- A plan must be mergeable as one standalone PR. It must be split when it has more than 10 steps, spans more than two separately built, deployed, or owned components, or contains work that cannot start until another part has shipped. A split set shares one timestamp with a two-digit sequence; each plan names its prerequisites in Depends on and its siblings in References.
- In section 9, Blocking is yes or no and Resolution stays blank until the question is resolved; implementation stops on Blocking yes with a blank Resolution.
- Missing header fields, sections, Verify, Size, or Blocking values are already recorded; do not report them.

Each finding must use this format exactly:

**Section:** Header, or the plan section's number and name (e.g. 6. Implementation Steps); for several plans, prefix the filename
**Severity:** critical | major | minor
**Confidence:** high | moderate | low
**Issue:** One sentence stating what is wrong, naming the step, row, or decision at fault.
**Evidence:** The plan text quoted, or the heading under which the missing item belongs and what you searched; a claim about the repository cited as `path/to/file:line`. If you cannot cite it, drop the finding.
**Recommendation:** The change to make, as an instruction; or "unclear" plus what decision or information is missing.

Severity: critical means implementation would stop, build the wrong thing, or ship an unmitigated risk; major means a step, test, decision, or rollout item is wrong or missing; minor means clarity.

Separate findings with a blank line.
If a section has no findings, write: _No issues found._

---

## Goal & context
Check for: vague or unmeasurable goals, success criteria that cannot be verified, missing definition of "done", problem not stated, prior art cited without showing why it applies, assumptions the repository confirms or refutes.

<findings>

## Design soundness
Check for: unjustified decisions, alternatives dismissed without rationale, missing key decisions, design that contradicts stated goals, code in section 5 that is an implementation rather than a contract.

Report any materially better design for the same goals — simpler, more robust, lower risk, or reusing something already in the repository — as a finding: Issue names the plan's choice and your alternative; Recommendation states why it is better and what it costs. If the plan rejected it, address its stated reason. A marginal alternative is not a finding.

<findings>

## Implementation feasibility
Check for: missing or mis-sequenced steps, steps that cannot be independently reviewed, a Size unrealistic for the step's content, a Verify that cannot be checked from the repository, a step after which the project's checks could not pass, steps that perform operational actions (deploy, run a migration, flip a flag) instead of committing the code for them, tests or rollout items assigned to a step other than the one introducing the behaviour.

<findings>

## Dependencies & risks
Check for: undeclared external dependencies, missing sign-off requirements, a prerequisite missing from Depends on, circular dependencies, unacknowledged risks, risks without a mitigation.

<findings>

## Rollout & migration
Check for, where applicable: no rollback plan, irreversible migrations without a downtime assessment, no observability signal that shows the rollout succeeded; for non-deployed code, no versioning strategy or breaking-change communication.

<findings>

## Testing strategy
Check for: missing edge cases, no integration or rollback validation, untested areas without a stated reason, testing gaps disproportionate to risk.

<findings>

## Scope
Check for: fuzzy in/out-of-scope boundary, a split trigger met without a split, scope creep.

<findings>

## Open questions
Check for: questions that block execution but are marked no, questions marked yes that block nothing, questions missing owner or due date, questions the plan or the repository already answers.

<findings>

## Split set
For several plans only. Check for: execution order contradicting Depends on, siblings missing from References, work duplicated across plans, work no plan covers, a plan that cannot merge on its own.

<findings>
```

## Step 4 — Run agents and review

Launch the agents per `review-fanout`, then review the plans yourself while they run, reading the files the plans reference. Then collect per `review-fanout`.

## Step 5 — Verify and categorize

Verify and merge every finding per `review-fanout`. For this review, verification also means dropping findings that demand what the template permits.

Categorize each surviving finding:

- **Clear fix** — the plan text, the repository, or the template fully determines the edit: a test section 7 names with no step, a prerequisite in References but not in Depends on, a missing Size or Verify the step's content makes obvious, a duplicated or misplaced item.
- **Decision required** — the edit chooses something: a goal, metric, or success criterion; a scope boundary; a design or a step's behaviour; an owner or due date; accepting a risk; a split. A proposed alternative design is always decision required, even when every source agrees. So is a Blocking question with a blank Resolution, and a finding whose sources contradict each other where the plan text does not settle it.

## Step 6 — Decide with the user

If any finding is decision required, stop before editing and send one message:

1. Coverage, per `review-fanout`.
2. The decisions, numbered D1, D2, …: the plan text quoted, the finding with its Source and why it needs a decision, the options with their tradeoffs, and your recommendation with its reason.
3. The clear fixes about to be applied, one line each, so the user can veto any.

Wait for the answers, then apply only what was answered and not vetoed. A decision the user defers stays out of the plan body and becomes a row in section 9: Blocking `yes` if a step depends on it, Resolution blank. With no decision-required findings, go straight to Step 7.

## Step 7 — Update the plan and report

Edit each plan file in place: apply the clear fixes and the user's resolutions, write each answered question's Resolution in section 9, and append one line per change to section 11, dated today, stating the resulting plan fact. Never mention the review, agents, or findings anywhere in the plan; the body reads as if written correctly from the start. Never create, rename, or delete plan files: when a decision replaces the goal or design, or requires a split, do not patch — report it and recommend re-running plan-doc with the decisions.

Then report:

- Coverage, per `review-fanout`.
- The Revision Log lines added, and the findings discarded and why. Do not quote plan content otherwise.
- Decisions deferred and Blocking questions still open.
- Verdict and next step: **ready to execute** — header valid, every step has Verify and Size, no Blocking question lacks a Resolution, every decision answered; next `plan-implement`. **Needs re-review** — a decision changed Design, Scope, or Implementation Steps; next `plan-review`. **Not ready** — anything else, naming what unblocks it.
