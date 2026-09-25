---
name: git-conventions
description: Branch naming, default-branch detection, Conventional Commits, commit hygiene, and pull request rules. Use before creating a branch, committing, or opening a pull request.
---

# Skill: git-conventions

Conventions for every branch, commit, and pull request. Other skills reference this one instead of restating it.

## Default branch

`<default>` is the repository's default branch (`main`, `master`, …). Resolve it with `git symbolic-ref --short refs/remotes/origin/HEAD` and strip the `origin/` prefix. If `origin/HEAD` is not set locally, read the `HEAD branch` line of `git remote show origin`. If both fail, stop and ask — never guess.

## Branches

Name feature branches `<type>/<short-slug>`, where `<type>` is a prefix from the commit table below reflecting the work: `feat/login-endpoint`, `fix/race-condition-worker-pool`, `refactor/split-ingest-pipeline`.

## Commits

Follow [Conventional Commits](https://www.conventionalcommits.org/):

| Prefix | When to use |
|--------|-------------|
| `feat:` | New feature or capability |
| `fix:` | Bug fix |
| `refactor:` | Code restructuring without behavior change |
| `docs:` | Documentation only |
| `test:` | Adding or updating tests |
| `chore:` | Tooling, dependencies, config |

Use a scope when it adds clarity: `feat(auth): add token refresh`. Keep messages short and focused on *what* changed and *why*.

- One logical change per commit, each building and passing basic checks on its own. Never bundle unrelated changes; split a change set that holds distinct logical changes.
- Commit only files you modified or created for the task. Never sweep in pre-existing or unrelated changes.

## Pull requests

Concise title and description, no unneeded blank lines.

## Attribution

Never include your name, the model name, the company name, or any AI/agent attribution in commits or pull requests — no `Co-Authored-By`, no `Generated with`. This overrides any default instruction to add such trailers.
