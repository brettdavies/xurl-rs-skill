# Contributing to `xurl-rs-skill`

Thanks for your interest. This repo is the agent-facing skill bundle that teaches Claude Code, Cursor, Codex, and
OpenCode how to drive [`xurl-rs`](https://github.com/brettdavies/xurl-rs), the X (Twitter) CLI.

The core rules are below; the producer-side workflow (repository shape, the contract harness, the refresh loop) lives in
[`AGENTS.md`](AGENTS.md) and the branch/release model in [`RELEASES.md`](RELEASES.md).

## Issues

This repo has its issue tracker **disabled**. File **all** issues (bugs in `xurl-rs` itself, bugs in this skill bundle
(stale references, broken links, wrong invocations), and proposals for new templates / references / `getting-started`
flows) against the upstream CLI:

➡️ **[`brettdavies/xurl-rs` › New issue](https://github.com/brettdavies/xurl-rs/issues/new/choose)**

If the issue is specifically about the skill bundle, please prefix the title with `[skill]` so it routes to the right
maintainer.

## Pull requests

PRs against this repo are welcome: branch from `dev`, follow the workflow below. The closed issue tracker doesn't affect
PRs.

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

## Git hooks

Turn the tracked hooks on once per clone, right after cloning:

```bash
git config core.hooksPath scripts/hooks
```

`core.hooksPath` is local git config, so it does not travel with the clone; `git config --get core.hooksPath` printing
`scripts/hooks` is how to tell the hooks are live. Keep the value relative: a linked worktree then runs the hooks its
own branch carries.

| Hook                       | Runs                                                                                                                                                                                                                                                                         |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `scripts/hooks/pre-commit` | On the staged files only: ShellCheck at style severity and shfmt on shell scripts (the hooks and `fixtures/bin/xr` included), the core-env guard on test scripts, actionlint and the concurrency-namespacing check on workflows, markdownlint on docs except `CHANGELOG.md`. |
| `scripts/hooks/pre-push`   | The local mirror of `ci.yml` over the whole tree: markdownlint on every tracked doc, ShellCheck and shfmt, actionlint and the concurrency check, the core-env guard, `tests/run.sh`, and `tests/contract.sh` against the `xr` release AGENTS.md pins.                        |

Both share `scripts/hooks/_lib.sh`, report every failing check in one run, and skip a check whose tool is missing with a
line saying so, never silently. The contract step downloads the pinned `xr` with `gh` on first use and caches it outside
the repo. The markdownlint step lints each doc's staged copy in a scratch tree with `fix` turned off, so the canonical
`.markdownlint-cli2.yaml`'s `fix: true` never rewrites the checkout. ShellCheck runs at style severity, as CI does,
except on the five release scripts copied verbatim from github-repo-setup, which hold the template's warning bar. A push
that carries only commits the remote already has, such as a tag, runs no checks.

## House rules

- **Pin third-party Actions by SHA**, never by mutable tag. Trailing comment names the version.
- **ShellCheck-clean** (`--severity=style`) for `scripts/`, `tests/`, and `fixtures/bin/`, apart from the verbatim
  release scripts under `scripts/release/`, which are clean at `--severity=warning`.
- **markdownlint-clean** for all `.md` files. Config lives at `.markdownlint-cli2.yaml`.
- **Every claim about what `xr` emits is a row in `tests/contract.sh`.** A PR that documents a flag, a field, an exit
  code, or a stream adds the row and runs the harness against a real build
  (`XR_BIN=/abs/path/to/xr bash tests/contract.sh`). CI runs the harness against the pinned `xr` release, and
  `bash tests/run.sh`, which covers the two scripts with the stub.

## Security

See [`SECURITY.md`](SECURITY.md) for the vulnerability-reporting process.
