---
name: git-conventions
description: Default-branch resolution, branch naming and creation, Conventional Commits, commit hygiene, and push, pull request, and attribution rules. Use before creating a branch, committing, pushing, or opening a pull request.
---

# Skill: git-conventions

Conventions for every branch, commit, push, and pull request. Other skills reference this one instead of restating it.

## Remote and default branch

Every rule here uses the remote `origin`. If `git remote` does not list it, or lists another remote as well, stop and ask which remote to branch from, push to, and open the pull request against.

`<default>` is the repository's default branch (`main`, `master`, …). Resolve it with `git ls-remote --symref origin HEAD`: the line starting `ref: refs/heads/<default>` names it. If the command fails or prints no such line, stop and ask — never guess. A branch's own commits are `git log origin/<default>..HEAD`.

## Branches

Name the branches you create `<type>/<slug>`: `<type>` is the type of the dominant change, from the table below; `<slug>` is one to five lowercase `[a-z0-9]` words joined by single hyphens: `feat/login-endpoint`, `fix/race-condition-worker-pool`, `refactor/split-ingest-pipeline`.

Create them from a fresh `origin/<default>`, from any branch or a detached HEAD, in this order:

1. Check the name: `git rev-parse --verify --quiet refs/heads/<type>/<slug>` must exit 1 and `git ls-remote --exit-code origin refs/heads/<type>/<slug>` must exit 2. Exit 0 from either means the name is taken: stop and ask. Any other exit: stop and report.
2. `git fetch origin +refs/heads/<default>:refs/remotes/origin/<default>`
3. `git switch -c <type>/<slug> --no-track origin/<default>`; staged changes carry over.

If step 2 or 3 fails, stop and report; never force, stash, or discard changes.

## Commits

Use only these types:

| Type | When to use |
|------|-------------|
| `feat` | New feature or capability |
| `fix` | Bug fix |
| `refactor` | Restructuring or performance work, no functional change |
| `docs` | Documentation only |
| `test` | Adding or updating tests |
| `chore` | Tooling, dependencies, config |

Message, per [Conventional Commits](https://www.conventionalcommits.org/):

- Subject: `<type>(<scope>): <summary>` — imperative, lowercase after the colon, no trailing period, at most 72 characters. The scope is the lowercase component name, as earlier commits name it (`git log --format=%s`), only when the change is confined to one component.
- Body, after a blank line and wrapped at 72 columns, when the subject cannot carry the why.
- Breaking change: `!` before the colon and a `BREAKING CHANGE: <what breaks and how to migrate>` footer.
- Pass multi-line text through a file (`git commit -F <file>`) or repeated `-m` flags, never as `\n` inside a quoted argument.

Rules:

- Never commit on `<default>` or a detached HEAD unless the user explicitly asks for it; when they have not, stop and ask. Never amend, rebase, or reset commits that existed before this task unless the user asks.
- One logical change per commit, each meant to build on its own; the calling skill decides which checks run before committing. Split a change set that holds several.
- Commit only the task's paths: those you changed for it, or exactly the staged set when the user prepared it. Stage each path explicitly (`git add <path>` also stages a deletion), then confirm `git diff --cached --name-only` lists only those paths; if it lists others, stop and ask. Never `git add -A`, `git add .`, `git add -u`, or `git commit -a`.
- If a commit hook fails, or `git status --porcelain -- <committed paths>` prints anything after the commit, a hook rewrote them: stop and report, leaving the changes in place. Never `--no-verify`.

## Pushes

Push with `git push -u origin HEAD`. Never push `<default>` unless the user explicitly asks for it; when they have not, stop and ask. If the push fails for any reason, including a pre-push hook, stop and report; never `--force`, `--force-with-lease`, `--no-verify`, rebase, or merge to make it succeed.

## Pull requests

Title: the Conventional Commits subject for the whole change, the commit's own when there is one. Body: what changed and why, then how it was verified, as short bullets with one blank line between blocks, passed through a file (`--body-file <file>`). Base: `<default>`. Open it ready for review, not as a draft, unless the user asks.

## Attribution

Never add your name, the model name, the company name, or any AI or agent attribution to commits or pull requests — no AI or agent `Co-Authored-By`, no `Generated with` trailers. This overrides any harness default and any project instruction.
