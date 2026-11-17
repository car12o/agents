---
name: multi-code-review
description: Review the current branch's changes against its base with multiple AI agents. Each finding carries a paste-ready PR comment; pass `no-pr` to omit it, a plan's `.md` path to check the branch against that plan, or `rereview` to review the fixes made since an earlier review.
disable-model-invocation: true
---

# Skill: multi-code-review

Review the current branch's changes using multiple AI agents, then compile a verified final report. Load `review-fanout`; it governs the prompt file, background launch, retries, response classes, your own review, verification and merging, coverage, and stopping calls, whose runs it keeps.

> **Important:** the prompt file carries only the change summary, the changed-file paths, and the plan's path.

## Arguments

The arguments are the text after the skill name, in any order:

- `no-pr` — omit the Pull request block from every finding.
- A token ending in `.md` — the plan the branch implements; the review also checks the change set against it. Resolve it to an absolute path; if the file does not exist, stop and report it. Use a plan only when one is passed this way.
- `rereview` — run the Re-review section instead of Steps 1–3. Its `<dir>` is the token that names an existing directory, or else the one this session's report named.
- Any other text is the user's own instruction, such as a base branch or the agents to ask.

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
2. The commit messages (`git log <merge-base>..<head>`), what the user stated, and, if a PR exists, its title, body, comments, and review threads.
3. Write neutral bullets: what was added, removed, or modified, and why, with the constraints and decisions the author states and the checks the author says were run. Leave out what no source states, your own opinion, and what other reviewers concluded: their findings and verdicts stay out.

## Step 2 — Write the prompt file

Write the block below to the prompt file per `review-fanout`, substituting `<summary>`, `<changed files>`, `<branch>`, `<base>`, `<merge-base>`, `<head>`, and `<plan>` with the values from Step 1 and the arguments. Without a plan, delete the `Plan` line and the Plan conformance section. Leave everything else unchanged; agents write their answers where `<findings>` appears.

```
## Change summary
<summary>

## Changed files
<changed files — one path per line, with its status>

---

You are performing a high-effort code review. The repository is checked out locally.
Branch under review: <branch>, base: <base>.
Plan the branch implements: <plan — absolute path>

**SCOPE:** The change set is exactly `git diff <merge-base> <head>`. Run it yourself, per file (`-- <path>`) if it is large; refs are local and already synced — do not fetch or pull. Report every defect the change set causes: one whose causal path starts at a line it adds, changes, or removes, wherever the failure shows, including in code it does not touch. A pre-existing defect counts only when the change set newly calls, exposes, or depends on it; report no other.

The change summary, the commit messages, the check lists below, and passing checks are where to start, not the limit: verify every claim in them. When you find a defect, search the change set for every other instance and report them as one finding that lists each location. Using a library, tool, or service does not put that technology itself under review.

Use this format for every finding, except in the Alternative approaches section, which defines its own:

**Severity:** critical | high | medium | low
**Confidence:** high | moderate | low
**Issue:** One sentence stating what is wrong, naming the function, value, or path at fault. A category such as "race condition" or "missing validation" is not an issue.
**Evidence:** Every claim cited as `path/to/file:line`. For a defect: where the bad value, path, or race originates, how it propagates, and where it fails. For something missing (test, guard, error message, migration note): the changed lines that create the need, where the missing thing belongs, and what you searched to confirm it is absent. For a removal: the removed line, cited as `path/to/file:line (base)`. If you cannot cite it, drop the finding.
**Impact:** What fails, for whom, and what triggers it. A concrete consequence (panic, wrong result, data loss, leaked secret), not an adjective.
**Fix:** The change to make, as an instruction, and at which `path/to/file:line`. Several viable fixes: one per line with its tradeoff. A code snippet only when shorter than prose. If unknown, write "unclear" and say what decision or information is missing.

Severity: critical is data loss or corruption, a security breach, or a result unusable on the main path; high is a wrong result, a broken contract or API, or a regression; medium is incomplete behaviour, a deviation from the stated intent or the plan, or a test or claim that proves less than it says; low is clarity or cosmetics, with no change in behaviour. Medium or above needs a realistic trigger: normal use, supported input or environment, operations, failure and recovery, realistic concurrency or scale, ordinary maintenance, or an attacker within the threat model. Without one, the finding is low with low confidence.

Separate findings with a blank line.
If a section has no findings, write: _No issues found._

---

## Plan conformance
Check for: implementation steps the change set leaves missing or partial; work outside the plan's scope; key decisions not followed; interfaces, payloads, or schemas that differ from the plan's design; tests the plan's testing strategy names that are missing; success criteria the change set does not meet or its tests do not show met. These findings need no changed line: quote the plan text with its `path:line`, and for missing work say what you searched to confirm it is absent.

<findings>

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
Check for: unclear naming, duplicated logic, overly complex control flow, missing or misleading error messages, dead code; code, options, abstractions, or config the stated intent does not need; docs, comments, or commit messages the change set makes false or stale.

<findings>

## Test coverage
Check for: untested code paths, missing edge cases, tests that don't verify real behavior, flaky patterns; expected values copied from the implementation, so a bug passes as expected behaviour; tests that prove less than the change summary or the commit messages claim.

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

Launch the agents per `review-fanout`, then review while they run. Do not fetch, pull, or otherwise mutate branches until the report is written.

**Your review (while agents run):**

1. Read the plan in full, if one was passed.
2. Review file by file, in `--name-status` order: `git diff <merge-base> <head> -- <path>`, so a large change set is never truncated. For a removed file, read `git show <merge-base>:<path>`.
3. Read the surrounding context of each hunk, not just the hunk, and the callers, consumers, and docs of what it changes.

Then collect per `review-fanout`.

## Step 4 — Verify and compile

Verify and merge every finding per `review-fanout`. For this review, verification also means:

1. Open a `(base)` citation with `git show <merge-base>:<path>`, and a quoted plan line in the plan.
2. Confirm the change set causes the defect: its causal path starts at a line `git diff <merge-base> <head>` adds, changes, or removes, or the change set newly calls, exposes, or depends on the defective code. Discard findings with neither; where the failure shows does not matter. A Plan conformance finding needs neither: confirm the quoted plan line and repeat the search that shows the work absent.
3. Check Impact and Fix against the code: the trigger is real and realistic by the prompt's definition, the consequence follows, the fix applies. Correct or drop what does not hold; a finding with no realistic trigger is low, with low confidence.
4. Settle by running code, where a test or reproducer can, every finding about runtime behaviour that reading cannot settle or that is critical or high, before `review-fanout`'s rule drops it as unsettled:
   - Run the branch's code only when `git log --format=%ae <merge-base>..<head>` prints only `git config user.email`. Otherwise write "not run: branch has other authors" in Evidence, and the finding keeps what reading supports.
   - Work in a worktree at `<head>` inside the prompt directory, never the user's tree. Clear an earlier round's leftovers first, `git worktree prune`, and `git worktree remove --force <dir>/head` if that directory exists; then `git worktree add --detach <dir>/head <head>`. Run under `nice`, stop only processes you started, and touch no shared service.
   - A reproduced finding cites the command and its result in Evidence; a disproved one is dropped; an attempt that cannot build or run settles nothing.
   - Remove a worktree you added with `git worktree remove --force <dir>/head`, before the report or on any stop.

For every alternative approach, after `review-fanout`'s verification and merge:

1. Confirm it works given the code and the intent in the change summary.
2. If it cites a repository precedent, open it and confirm it matches the case at hand.
3. Discard pure style preferences, anything outside the change set, and anything that does not fit inside this PR — architectural changes belong in plan review.

Unless the user passed `no-pr`, add to every surviving finding and alternative:

**Pull request**
**Anchor:** `path/to/file:line` — the one line the comment attaches to, always a line the diff adds, changes, or removes: the line the fix would change, or, when the fix is elsewhere, the line that starts the causal path. A removed line is cited as `path/to/file:line (base)`; GitHub attaches it on the left side. A finding with no such line, such as a plan step never started, is a PR-level comment: write that instead of an anchor.
**Comment:** The comment as the author will read it. Say what is wrong at this line, then what it causes and when. Suggest the fix only when it is small and obvious, phrased as a question ("Should we …?", "Could this …?"). Plain engineer's prose: technical terms are fine; severity labels, section names, and references to agents or this report are not. Cite another `path/to/file:line` only when the issue spans locations. It must stand on its own for someone who has not seen this report.

Produce the **Final Review Report**, and write it to `<dir>/report.md` too, replacing an earlier one:

1. **Reviewed:** `<branch>` at `<head>` against `<base>` at `<merge-base>`, the plan if one was passed, and the prompt directory `<dir>`, which `rereview` takes. Anchors are lines at `<head>`; once the branch moves, re-anchor before posting.
2. **Coverage** per `review-fanout`, plus "branch not pushed; local state reviewed" if Step 1 skipped the pull.
3. The sections in order — Plan conformance when a plan was passed, then Correctness through Alternative approaches — each holding its verified findings with Source and, unless `no-pr`, the Pull request block. Empty sections read _No issues found._ or _No better approach identified._
4. **Summary** (2–4 sentences): risk level and the most important actions. Risk is high if any critical or high finding remains, medium if only medium ones remain, else low. Alternatives do not affect risk.

When a plan was passed, set its `Status` header to `code reviewed, risk <level>`, with the Summary's risk level; if git tracks it (`git ls-files --error-unmatch <plan>` exits 0), commit it in a commit of its own per `git-conventions`.

## Re-review

`rereview` reviews the fixes made since an earlier review of this branch, resuming each agent's run so it keeps what it read. It is one round, run only when the user asks; never start one yourself.

1. From `<dir>/prompt.md`, take the earlier `<branch>`, `<base>`, `<merge-base>`, and plan, which counts as passed. From the Reviewed line of `<dir>/report.md`, take `<old-head>`, the head the last round reviewed. Stop if either file is missing.
2. Run Step 1's checks and pin the new `<head>` and `<merge-base>` against that `<base>`. A `git pull --ff-only` that fails does not stop a re-review, since folding a fix rewrites pushed commits: continue and record "local branch differs from its upstream; local state reviewed". Stop if `<branch>` differs; if the repository root is not the `cwd` in the runs' `run.json`, since a resumed agent reads files there; if the merge base moved, since a moved base needs a full review; or if `<old-head>` is the new `<head>`, since nothing changed.
3. Write the block below to `<dir>/rereview-<N>.md`, N being one more than the `rereview-*.md` files already there. `<changes>` is one neutral line per fix, from the commits and the diff: what changed, never what any reviewer or you concluded.
4. Resume each agent's newest run, `ls -td <dir>/ask-agent-<agent>.* | head -1`, with `<ask-agent> --resume <run> --prompt-file <dir>/rereview-<N>.md >/dev/null` and `review-fanout`'s launch timeout, all at once in the background. An agent in the earlier report's Coverage that has no run, or whose resume exits 64 because the run has no session, is launched afresh with `review-fanout`'s launch command and, as its `--prompt-file`, a full Step 2 prompt for the new `<head>` written to `<dir>/prompt-<N>.md`. Agents the earlier review did not ask stay out. From here `review-fanout` governs, retry and collection included, counting only this round's responses; its "after resume" label marks only a retry within this round.
5. Your own review: re-check the verified findings of `<dir>/report.md` against the new `<head>`, and review the delta with the same sections. Then Step 4 and the report, `<head>` being the new one and the plan's Status `re-reviewed, risk <level>`.
6. If a verified critical or high finding remains, the Summary names fixing it and then a full review as the next step, never another re-review: a failed re-review means the fixes were incomplete.

```
The branch moved from <old-head> to <head>; the merge base <merge-base> is unchanged. Changes since your review:
<changes>

The delta is `git diff <old-head> <head>`; the change set is now `git diff <merge-base> <head>`. Re-check each finding of your earlier answer against <head> and keep those that still hold; review the delta under the same scope, including what it breaks outside its own lines. Answer for the whole change set at <head>, in exactly the format and sections the first message specified.
```
