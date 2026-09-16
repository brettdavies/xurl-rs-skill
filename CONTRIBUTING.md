# Contributing to `xurl-rs-skill`

Thanks for your interest. This repo is the agent-facing skill bundle that teaches Claude Code, Cursor, Codex, and
OpenCode how to drive [`xurl-rs`](https://github.com/brettdavies/xurl-rs), the X (Twitter) CLI.

The core rules are below; the producer-side workflow (repository shape, the contract harness, the refresh loop) lives
in [`AGENTS.md`](AGENTS.md) and the branch/release model in [`RELEASES.md`](RELEASES.md).

## Issues

This repo has its issue tracker **disabled**. File **all** issues (bugs in `xurl-rs` itself, bugs in this skill bundle
(stale references, broken links, wrong invocations), and proposals for new templates / references / `getting-started`
flows) against the upstream CLI:

➡️ **[`brettdavies/xurl-rs` › New issue](https://github.com/brettdavies/xurl-rs/issues/new/choose)**

If the issue is specifically about the skill bundle, please prefix the title with `[skill]` so it routes to the right
maintainer.

## Pull requests

PRs against this repo are welcome: branch from `dev`, follow the workflow below. The closed issue tracker doesn't
affect PRs.

## Workflow

- **Branch from `dev`.** `feat/*` for additions, `fix/*` for bug fixes, `chore/*` for tooling, `docs/*` for repo-level
  documentation only. Engineering docs under `docs/plans/`, `docs/solutions/`, `docs/brainstorms/`, `docs/reviews/` are
  blocked from `main` by `guard-main-docs`.
- **PR to `dev`.** Squash merge. PR title becomes the commit title; PR body becomes the commit message.
- **Conventional Commits.** `type(scope): description`. Prefer `feat` / `fix` over `chore` for anything user-observable
  since `cliff.toml` drops `chore`, `style`, `test`, `ci`, `build` from the changelog.
- **Signed commits required** on `main` and `dev` (ruleset-enforced).
- **No AI attribution** in commit messages or PR bodies.

See [`AGENTS.md`](AGENTS.md) for the full producer-side guide and [`RELEASES.md`](RELEASES.md) for the release model.

## House rules

- **Pin third-party Actions by SHA**, never by mutable tag. Trailing comment names the version.
- **ShellCheck-clean** (`--severity=style`) for `scripts/`, `tests/`, and `fixtures/bin/`.
- **markdownlint-clean** for all `.md` files. Config lives at `.markdownlint-cli2.yaml`.
- **Every claim about what `xr` emits is a row in `tests/contract.sh`.** A PR that documents a flag, a field, an exit
  code, or a stream adds the row and runs the harness against a real build (`XR_BIN=/abs/path/to/xr bash
  tests/contract.sh`); `bash tests/run.sh` covers the two scripts with the stub and runs in CI.

## Security

See [`SECURITY.md`](SECURITY.md) for the vulnerability-reporting process.
