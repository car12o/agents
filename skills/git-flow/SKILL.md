---
name: git-flow
description: Stepped git flow — create a feature branch, commit staged changes, and open a PR. Run all steps or select a subset by number or name (branch, commit, pr).
disable-model-invocation: true
---

# Skill: git-flow

Walk through a stepped git flow: **branch → commit → pull request**.

## Step selection

The skill takes optional arguments selecting which steps to run:

- **No arguments** — run all steps in order.
- Steps can be referenced by number (`1`, `2`, `3`) or name (`branch`, `commit`, `pr`), mixed freely, comma- or space-separated (e.g. `2 3`, `commit,pr`, `1 pr`).
- Selected steps always run in step order (1 → 2 → 3), regardless of the order given.
- If any reference is unknown, abort with an error listing the valid steps (`1`/`branch`, `2`/`commit`, `3`/`pr`). Nothing runs — do not execute the valid steps from a partially invalid selection.

## Conventions

Load the `git-conventions` skill before running any step. It defines `<default>` (resolved once, before Steps 1 and 3), branch naming, commit format, and pull request rules.

## Step 1 — branch

Create a feature branch from an up-to-date `<default>`:

1. Bring `<default>` up to date: if on `<default>`, `git pull --ff-only`; otherwise `git fetch origin <default>:<default>`.
2. Name the branch `<type>/<short-slug>` per `git-conventions`.
3. `git switch -c <type>/<short-slug> <default>`.

## Step 2 — commit

Commit only what is already staged — do **not** stage anything yourself. If nothing is staged, stop and report it.

1. Read the staged diff (`git diff --cached`) to understand what is being committed.
2. If the staged changes contain unrelated work, split them into separate commits, one per logical change.
3. Write each message per `git-conventions`.
4. Push the branch to the remote: `git push -u origin <branch>`.

## Step 3 — pull request

Open a PR from the feature branch into `<default>` (e.g. `gh pr create`) following the pull request rules in `git-conventions`.
