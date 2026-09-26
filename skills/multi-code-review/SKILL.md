---
name: multi-code-review
description: Review the current branch's changes against its base with multiple AI agents. Each finding carries a paste-ready PR comment; pass `no-pr` to omit it.
disable-model-invocation: true
---

# Skill: multi-code-review

Review the current branch's changes using multiple AI agents, then compile a verified final report. By default every finding carries a paste-ready pull request comment; pass `no-pr` to omit it. Load `review-fanout`; it governs the prompt file, launch, failure handling, your own review, merging, and coverage.

> **Important:** the prompt file carries only what agents cannot fetch: the change summary, the changed-file paths, and PR intent and discussion. Never paste diff hunks or file contents into it.

## Step 1 — Check preconditions and pin the change set

Run these checks before touching any ref. If one fails, STOP and report it. Do NOT stash, merge, rebase, or force-reset — the user decides how to resolve it.

1. `git status --porcelain` prints nothing (clean tree).
2. `git branch --show-current` prints a name (not detached HEAD). This is `<branch>`.
3. `git fetch --prune origin`.
4. If `<branch>` has an upstream (`git rev-parse --abbrev-ref @{u}` succeeds): `git pull --ff-only`; a failure means the branch diverged — STOP. With no upstream, continue and record "branch not pushed; local state reviewed" for the report.

Resolve `<base>`, first match wins. If none matches, STOP and ask — never guess:

1. The base the user named.
2. The open PR's base: `gh pr view --json number,baseRefName,title,body,comments`. Keep the other fields for Step 2. `comments` holds issue-style comments only, so also read inline review threads with `gh api repos/{owner}/{repo}/pulls/<number>/comments`. A non-zero exit means there is no PR — not an error.
3. The default branch, resolved as the `git-conventions` skill describes (load it).

Pin the change set to commits so every reviewer sees the same diff. The local `<base>` branch is never updated; `origin/<base>` is the reference:

- `<head>` = `git rev-parse HEAD`
- `<merge-base>` = `git merge-base origin/<base> HEAD`
- The change set is `git diff <merge-base> <head>`. If it is empty, STOP: nothing to review.

Then gather context for the change summary in Step 2 — the raw output never goes into the prompt file:

1. `git diff --name-status <merge-base> <head>` for the changed-file list.
2. The PR title, body, comments, and review threads, if a PR exists.
3. Write neutral bullets: what was added, removed, or modified, and why (per the PR). No opinion.

## Step 2 — Write the prompt file

Write the block below to the prompt file per `review-fanout`, substituting `<summary>`, `<changed files>`, `<branch>`, `<base>`, `<merge-base>`, and `<head>` with the values from Step 1. Leave everything else unchanged; agents write their findings where `<findings>` appears.

```
## Change summary
<summary>

## Changed files
<changed files — one path per line, with its status>

---

You are performing a high-effort code review. The repository is checked out locally.
Branch under review: <branch>, base: <base>.

**SCOPE:** The change set is exactly `git diff <merge-base> <head>`. Run it yourself, per file (`-- <path>`) if it is large; refs are local and already synced — do not fetch or pull. Report only defects this change set introduces, including those caused by removed lines. Do not report pre-existing defects the change set does not touch.

Use this format for every finding, except in the Alternative approaches section, which defines its own:

**Severity:** critical | high | medium | low
**Confidence:** high | moderate | low
**Issue:** One sentence stating what is wrong, naming the function, value, or path at fault. A category such as "race condition" or "missing validation" is not an issue.
**Evidence:** Every claim cited as `path/to/file:line`. For a defect: where the bad value, path, or race originates, how it propagates, and where it fails. For something missing (test, guard, error message, migration note): the changed lines that create the need, where the missing thing belongs, and what you searched to confirm it is absent. For a removal: the removed line, cited as `path/to/file:line (base)`. If you cannot cite it, drop the finding.
**Impact:** What fails, for whom, and what triggers it. A concrete consequence (panic, wrong result, data loss, leaked secret), not an adjective.
**Fix:** The change to make, as an instruction, and at which `path/to/file:line`. Several viable fixes: one per line with its tradeoff. A code snippet only when shorter than prose. If unknown, write "unclear" and say what decision or information is missing.

Separate findings with a blank line.
If a section has no findings, write: _No issues found._

---

## Correctness
Check for: logic errors, wrong return values, incorrect assumptions, off-by-one errors, unhandled edge cases, race conditions.

<findings>

## Security
Check for: injection flaws, missing auth checks, data exposure, insecure defaults, unsafe deserialization, hardcoded secrets.

<findings>

## Performance
Check for: algorithmic inefficiency, unnecessary allocations, N+1 queries, missing indexes, blocking calls in hot paths.

<findings>

## Maintainability
Check for: unclear naming, duplicated logic, overly complex control flow, missing or misleading error messages, dead code.

<findings>

## Test coverage
Check for: untested code paths, missing edge cases, tests that don't verify real behavior, flaky patterns.

<findings>

## Breaking changes
Check for: removed or renamed APIs, changed function signatures, altered behavior of existing features, missing migration guidance.

<findings>

## Alternative approaches
Report every materially better alternative that fits inside this PR — simpler, more robust, removes a class of bugs, drops a dependency, or reuses an existing pattern or helper in this repository. Architectural changes belong in plan review. Respect constraints stated in the change summary; if the author rejected an alternative, address their stated reason. A marginal alternative is not a finding.

Format for each alternative:

**Confidence:** high | moderate | low
**Current approach:** What the change set does
**Alternative:** What to do instead
**Why better:** Concrete benefit, with `path/to/file:line` of an existing precedent if there is one
**Tradeoff:** What is lost or made harder
**Location:** `path/to/file:line` in the change set (one per line for multiple)

Separate alternatives with a blank line.
If none: _No better approach identified._

<findings>
```

## Step 3 — Run agents and review in parallel

Launch the agents per `review-fanout`, then review while they run. Do not fetch, pull, or otherwise mutate branches from here on.

**Your review (while agents run):**

1. Review file by file, in `--name-status` order: `git diff <merge-base> <head> -- <path>`, so a large change set is never truncated. For a removed file, read `git show <merge-base>:<path>`.
2. Read the surrounding context of each hunk, not just the hunk.

When every call has returned, read and classify the response files per `review-fanout`.

## Step 4 — Verify and compile

Verify and merge every finding per `review-fanout`. For this review, verification also means:

1. If the code cited in Evidence sits a few lines away, correct the citation.
2. Confirm the change set introduces the defect: the cited lines are added, changed, or removed by `git diff <merge-base> <head>`. Discard findings about code the change set does not touch.
3. Check Impact and Fix against the code: the trigger is real, the consequence follows, the fix applies. Correct or drop what does not hold.

For every alternative approach, after the same verification and merge:

1. Confirm it works given the code and the intent in the change summary.
2. If it cites a repository precedent, open it and confirm it matches the case at hand.
3. Discard pure style preferences, anything outside the change set, and anything that does not fit inside this PR — architectural changes belong in plan review.

Unless the user passed `no-pr`, add to every surviving finding and alternative:

**Pull request**
**Anchor:** `path/to/file:line` — the one line the comment attaches to: the line the fix would change, or where the defect is introduced. A removed line is cited as `path/to/file:line (base)`; GitHub attaches it on the left side.
**Comment:** The comment as the author will read it. Say what is wrong at this line, then what it causes and when. Suggest the fix only when it is small and obvious, phrased as a question ("Should we …?", "Could this …?"). Plain engineer's prose: technical terms are fine; severity labels, section names, and references to agents or this report are not. Cite another `path/to/file:line` only when the issue spans locations. It must stand on its own for someone who has not seen this report.

Produce the **Final Review Report**:

1. **Coverage** per `review-fanout`, plus "branch not pushed; local state reviewed" if Step 1 skipped the pull.
2. The seven sections in order, each holding its verified findings with Source and, unless `no-pr`, the Pull request block. Empty sections read _No issues found._ or _No better approach identified._
3. **Summary** (2–4 sentences): risk level and the most important actions. Risk is high if any critical or high finding remains, medium if only medium ones remain, else low. Alternatives do not affect risk.
