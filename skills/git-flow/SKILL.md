---
name: git-flow
description: Stepped git flow — create a feature branch, commit staged changes, then push and open a PR. Run all steps or select a subset by number or name (branch, commit, pr).
disable-model-invocation: true
---

# Skill: git-flow

## Step selection

The arguments are the text after the skill name in the invocation.

- **No arguments** — run all steps in order.
- Steps can be referenced by number (`1`, `2`, `3`) or name (`branch`, `commit`, `pr`), mixed freely, comma- or space-separated (e.g. `2 3`, `commit,pr`, `1 2`). Names are case-insensitive; empty tokens and repeats are ignored.
- Selected steps always run in step order (1 → 2 → 3), regardless of the order given.
- If any reference is unknown, stop and report it, listing the valid steps (`1`/`branch`, `2`/`commit`, `3`/`pr`). Nothing runs — do not execute the valid steps from a partially invalid selection.

## Preflight

Load the `git-conventions` skill: it defines `<default>`, branch naming and creation, commits, pushes, and pull requests. Resolve `<default>` once, then run these checks in order. A stop anywhere in this skill ends the run; no later step executes.

- Step 1 selected while not on `<default>`: ask whether to continue on the current branch, skipping Step 1, or create a new one.
- Step 1 not selected or skipped: `git branch --show-current` must print a branch other than `<default>` (a detached HEAD prints nothing); the flow commits and pushes feature branches only.
- Step 2 selected: something must be staged (`git diff --cached --quiet` fails).
- Step 3 selected: `git fetch origin <default>` and `gh auth status` must succeed; without Step 2, `git log origin/<default>..HEAD` must also be non-empty.

## Step 1 — branch

Derive `<type>` and `<slug>` from the staged diff, or from what the user asked for; ask when neither says what the work is. Create the branch per `git-conventions`.

## Step 2 — commit

Commit the staged changes as the user prepared them: do not run checks, edit files, or stage anything that was not staged.

- Read the staged diff (`git diff --cached`) to understand what is being committed.
- Commit per `git-conventions`. To split the staged set into one commit per logical change, unstage whole paths (`git restore --staged`) and re-stage each group by path, so the commits together equal the staged set. Never `git commit -- <path>`: it commits working-tree content. If a file to be split also has unstaged changes, stop and ask.

## Step 3 — pull request

Push per `git-conventions`. If `gh pr view` finds an open PR for the branch, report its URL and stop. Otherwise write the title and body from `git log origin/<default>..HEAD` and its diff, open the PR with `gh pr create --base <default> --title … --body …` per `git-conventions`, and report its URL.
