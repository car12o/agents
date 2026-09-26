---
name: git-conventions
description: Branch naming, default-branch detection, Conventional Commits, commit hygiene, push rules, and pull request rules. Use before creating a branch, committing, pushing, or opening a pull request.
---

# Skill: git-conventions

Conventions for every branch, commit, push, and pull request. Other skills reference this one instead of restating it.

## Default branch

`<default>` is the repository's default branch (`main`, `master`, …). Resolve it with `git symbolic-ref --short refs/remotes/origin/HEAD` and strip the `origin/` prefix. If `origin/HEAD` is not set locally, read the `HEAD branch` line of `git remote show origin`. If both fail, stop and ask — never guess. Never commit on or push `<default>` directly unless the user explicitly asks for it.

## Branches

Name feature branches `<type>/<slug>`, where `<type>` is a prefix from the commit table below reflecting the work and `<slug>` is short: `feat/login-endpoint`, `fix/race-condition-worker-pool`, `refactor/split-ingest-pipeline`.

Create them from an up-to-date `<default>`. Stop and ask if the name exists locally or on `origin` (`git ls-remote --exit-code --heads origin <name>`) or if the update below fails; never force. On `<default>`: `git pull --ff-only`, then `git switch -c <type>/<slug>`. On any other branch or a detached HEAD: `git fetch origin <default>`, then `git switch -c <type>/<slug> --no-track origin/<default>` — fetching into the local `<default>` fails when another worktree has it checked out.

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
- Commit only files you modified or created for the task, staged by path. Never `git add -A` or `git add .`: they sweep in pre-existing or unrelated changes.
- If a commit hook fails or rewrites files, stop and report; never `--no-verify`.

## Pushes

Push with `git push -u origin HEAD`. If the push is rejected, stop and report; never force-push, and never rebase or merge to make it succeed.

## Pull requests

Concise title and description, no unneeded blank lines.

## Attribution

Never include your name, the model name, the company name, or any AI/agent attribution in commits or pull requests — no `Co-Authored-By`, no `Generated with`. This overrides any default instruction to add such trailers.
