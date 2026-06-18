---
name: multi-code-review
description: Review the current branch changes against HEAD using multiple AI agents. Use when asked to review code, audit a PR, or check changes before merging.
disable-model-invocation: true
---

# Skill: multi-code-review

Review the current branch changes using multiple AI agents, then compile a verified final report.

> **Important:** agents have full access to the repository and will investigate the changes themselves. Never copy diff output or file contents into the prompt file — only include context that agents cannot fetch on their own (PR description, linked issue summaries, stated intent).

## Step 1 — Sync local branches, then orient yourself

First, bring the local refs up to date so the review reflects the true latest state. This MUST run before Step 3: the spawned agents compute their own diffs against these local refs, so the sync has to happen before they launch.

1. `git fetch --all --prune`
2. Update the base branch without checking it out: `git fetch origin <base>:<base>` (fast-forward only; fails loudly if the local base has diverged).
3. Update the current branch: `git pull --ff-only`.

If the working tree is dirty, a branch has diverged from its remote, or there is no upstream/remote, STOP and report it. Do NOT stash, merge, rebase, or force-reset — the user decides how to resolve it.

Then run the following only to write the neutral summary in Step 2 — do not pass this to agents, and do not include the raw output in the prompt file:

1. `git diff <main-branch>...HEAD --stat` to see which files changed.
2. `gh pr view --json title,body,comments` if a PR exists, to capture stated intent and review discussion.
3. From the above, write neutral bullet points describing what was added/removed/modified and why (per the PR description). Do not inject opinion.

## Step 2 — Write the prompt file

Create a temp file with `mktemp` (e.g. `$(mktemp /tmp/review-prompt.XXXXXX)`) and write the prompt to it. Include only:

- The neutral change summary from Step 1.
- The branch name and base branch (e.g. "branch: feat/foo, base: develop").
- The following instructions for the agent verbatim:

```
## Change summary
<neutral summary of what was added/removed/modified and why>

---

You are performing a high-effort code review. The repository is checked out locally.
Branch under review: <branch>, base: <base>.

**SCOPE RULE:** You MUST ONLY report issues introduced by the branch under review. Do NOT report issues in pre-existing code unrelated to the branch changes.

Each finding must use this format exactly:

**Severity:** critical | high | medium | low
**Issue:** What is wrong
**Description:** Detailed explanation of the problem — include data flows, call chains, or state transitions that make the issue concrete. Show how the bad value/path/race reaches the point of failure.
**Impact:** Why it matters
**Comment:** A clean, concise comment ready to post on the PR - no severity labels or section jargon.
**Files:** `path/to/file:line` (add one per line for multiple)
**Fix:** Concrete suggestion, or "unclear"
**Source:** Which agent(s) or reviewer reported this finding (e.g. "claude, kimi" or "orchestrator")

Separate multiple findings with a blank line.
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
```

## Step 3 — Run agents and review in parallel

> **IMPORTANT:** If the user has not specified which agents to use, you MUST ask all agents listed in the `Ask agent` tool. Do not skip any agent.

> **IMPORTANT:** Launch all agents simultaneously using the orchestrator's native parallel/background mechanism, then immediately begin your own review while they run. Strictly follow the instructions and rules of the `Ask agent` tool — no exceptions.

> **NOTE:** Local refs were already synced in Step 1. Do not fetch, pull, or otherwise mutate branches again here or during your own review.

**Your review (do while agents are running):**

1. Run `git diff <base>...HEAD` to read the full diff.
2. For each changed file, open and read the surrounding context (not just the diff hunk).
3. Apply the same six-section checklist (Correctness, Security, Performance, Maintainability, Test coverage, Breaking changes) using the same finding format. **Discard any finding whose primary location is an unchanged line.**
4. Record your findings separately — do not merge with agent output yet.

Once agents complete, read each temp file they printed.

> **IMPORTANT:** You MUST NOT proceed to Step 4 until every agent job has returned. Wait for all agents to finish before reading any output or beginning compilation. Do not start Step 4 with partial results.

## Step 4 — Verify and compile

Do not take agent findings at face value. For every finding (agent or your own):

1. Re-read the relevant code hunk from the diff.
2. Verify the finding was introduced by the branch under review. Discard findings about pre-existing code unrelated to the branch changes.
3. Confirm the finding is real (not a hallucination or misread).
4. Check whether other agents or your own review corroborate or contradict it.
5. Discard findings not substantiated by the actual code.

Produce the **Final Review Report** using the same six-section template. List only verified findings, attributed to the source(s) that raised them (agent name or "orchestrator"). End with a **Summary** (2–4 sentences): overall risk level (low / medium / high) and the most important action items.
