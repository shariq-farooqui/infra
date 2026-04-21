# Contributing

This repository describes my personal homelab, so I do not expect external contributions. If you have forked it as a starting point for your own lab and hit a bug or a rough edge in the setup, an issue or PR is welcome.

## Local setup

1. Clone the repo.
2. Install [pre-commit](https://pre-commit.com). On Arch: `sudo pacman -S pre-commit`. Portable: `uv tool install pre-commit`.
3. Install the hook scripts: `pre-commit install --install-hooks`.

## Before committing

- `pre-commit run --all-files` matches what CI runs.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org). The `commit-msg` hook enforces this locally; CI re-checks.

## Branching and merging

- Branches: `feat/<name>`, `fix/<name>`, `docs/<name>`, and so on.
- Merges are local: rebase the feature branch onto `main`, then `git merge --ff-only` and push. The PR auto-closes; per-commit history stays visible on the PR page.

## Layout

Directories appear as features land; not all of them exist yet.
