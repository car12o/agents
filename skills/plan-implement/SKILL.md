---
name: plan-implement
description: Implement a plan written by the plan-doc skill (.agents/plans/*.md) on its feature branch, one commit per logical change. Use only when explicitly asked to implement, execute, or carry out such a plan.
disable-model-invocation: true
---

# Skill: plan-implement

## Step 1 — Locate and gate the plan

If the user provided a path, use it. Otherwise take the newest plan under the repository root; filenames start with a timestamp, so name order is creation order:

```bash
root=$(git rev-parse --show-toplevel) && find "$root/.agents/plans" -maxdepth 1 -name '*.md' 2>/dev/null | sort | tail -1
```

If the command prints nothing, stop and tell the user: there is no plan, or this is not a git repository. A plan is one of a split set when other plans share its 14-digit timestamp: list the set and start at the lowest sequence whose plan is not yet merged, or ask which to implement. If the user names specific steps, implement only those, in plan order.

Read the plan in full. If a header this skill needs (`Type`, `Slug`, `Depends on`) is missing, ask for it. Then check two gates before modifying any file:

- Prerequisites: if `Depends on` names other plans, or section 4 names PRs or sign-offs needed before work can proceed, ask the user to confirm each is merged into `<default>` or done. If any is not, stop; when it is a sibling of the same split set, offer to implement it first.
- Open questions: if any has Blocking `yes` and an empty Resolution, stop and report it.

## Step 2 — Prepare the branch

Load `git-conventions` and resolve `<default>`. Stop and ask if `git status --porcelain` lists anything outside `.agents/plans/`, or if `git branch --show-current` prints nothing (detached HEAD): pre-existing changes would be swept into step commits, and detached commits are lost. Then, by current branch:

- `<type>/<slug>`, from the plan's `Type` and `Slug` headers: resume. Match the commits in `git log origin/<default>..HEAD` to the plan's steps, propose the first unimplemented step, and confirm it with the user.
- `<default>`: if `<type>/<slug>` exists locally or on `origin`, it is most likely an interrupted run of this plan; ask whether to resume on it or name a different branch. Otherwise create it per `git-conventions`.
- Any other branch: stop and ask.

## Step 3 — Implement

Run the project's checks once before the first step; report failures already present and do not fix them, so they are not mistaken for regressions later. Then work through the plan's Implementation Steps in order. For each step:

1. Make the changes the step describes, including the tests Testing Strategy assigns to them. If Testing Strategy names tests no step covers, add them in the step that introduces the behaviour and report the deviation.
2. Check the step's `Verify` condition and run the relevant tests, type-check, or lint. Do not commit until they pass. Fix failures within the step's intent; a fix that would change the plan's intent is a blocker. Report a Verify you cannot check locally as unverified.
3. Commit per `git-conventions`, staging only this step's files. A step that changes nothing is not committed. Never commit the plan doc (`.agents/plans/…`).

If a step cannot be completed as written, see Handling blockers.

## Step 4 — Report

Confirm `git status` shows nothing uncommitted outside `.agents/plans/`, then report:

- One line per step: number, title, and its commits, or why it was skipped or not requested. Do not quote plan content.
- Checks run and their results, and any Verify left unverified.
- Success criteria: which are met and how you checked; the rest as unverified.
- Deviations from the plan and why.
- Follow-ups: each blocker with the question or action that unblocks it, unresolved Open Questions, and Rollout & Migration actions the steps did not do. Never perform rollout actions.
- Status: completed, completed with blockers, or stopped.

Do not push or open a pull request; name the branch and `git-flow pr` as the next step. Do not edit, move, or delete the plan file.

## Handling blockers

A step is blocked when it cannot be completed as written: a missing dependency, an ambiguous requirement, a sign-off not yet given, a check that cannot pass without changing the plan's intent.

- If the user can resolve it, ask now and wait; a deferred answer costs every later step built on a guess.
- Otherwise discard the step's uncommitted changes, skip it, and continue only with later steps that do not build on it; when unsure, ask.
- If the plan itself is wrong (a design error, an Assumption the code disproves, a prerequisite that turns out not to be merged), stop at the last commit and ask whether to revise the plan.

Never work around a blocker in a way that changes the plan's intent.
