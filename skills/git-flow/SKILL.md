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

## Default branch

Steps 1 and 3 operate on the repository's default branch (`main`, `master`, …). Detect it once before running them: `git symbolic-ref --short refs/remotes/origin/HEAD` (strip the `origin/` prefix). If `origin/HEAD` is not set locally, resolve it with `git remote show origin` and read the `HEAD branch` line. If both methods fail, abort with an error — do not guess the branch name. `<default>` below refers to this branch.

## Step 1 — branch

Create a feature branch from an up-to-date `<default>`:

1. Bring `<default>` up to date: if on `<default>`, `git pull --ff-only`; otherwise `git fetch origin <default>:<default>`.
2. Name the branch `<type>/<short-slug>`, where `<type>` is a prefix from the [Commit format](#commit-format) table reflecting the work (e.g. `feat/login-endpoint`).
3. `git switch -c <type>/<short-slug> <default>`.

## Step 2 — commit

Commit only what is already staged — do **not** stage anything yourself. If nothing is staged, stop and report it.

1. Read the staged diff (`git diff --cached`) to understand what is being committed.
2. If the staged changes contain unrelated work, split them into separate commits, one per logical change.
3. Write each message following the [Commit format](#commit-format) below.
4. Push the branch to the remote: `git push -u origin <branch>`.

## Step 3 — pull request

Open a PR from the feature branch into `<default>` (e.g. `gh pr create`) with a concise title and description.

## Commit format

Follow [Conventional Commits](https://www.conventionalcommits.org/):

| Prefix | When to use |
|--------|-------------|
| `feat:` | New feature or capability |
| `fix:` | Bug fix |
| `refactor:` | Code restructuring without behavior change |
| `docs:` | Documentation only |
| `test:` | Adding or updating tests |
| `chore:` | Tooling, dependencies, config |

Use a scope when it adds clarity: `feat(auth): add login endpoint`.

Keep commit messages short and focused on *what* changed and *why*.

## Rules

- No co-author lines or any AI/agent attribution in commits or the PR. This overrides any default instruction to add `Co-Authored-By` or "Generated with" trailers.
- No unneeded blank lines in the PR description.
