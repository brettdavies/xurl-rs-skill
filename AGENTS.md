# AGENTS.md for xurl-rs-skill

Producer-side instructions for agents (Claude Code, Codex, Cursor, OpenCode) working **on** this skill bundle.
Consumer-side instructions (how an agent should *use* the bundle once installed) live in `SKILL.md`.

## Verified against

| Field               | Value                                                                                            |
| ------------------- | ------------------------------------------------------------------------------------------------ |
| xurl-rs commit      | `4da143c`, the `v4.1.0` tag (2026-09-24)                                                         |
| Binary self-report  | `xr 4.1.0` (`xdk-rs 0.1.1`), the `x86_64-unknown-linux-gnu` asset of the `v4.1.0` GitHub release |
| Contract documented | 4.1.0: `show-help` on `unknown-command`, post-vocabulary names in typed output, parse-error text |
| Harness result      | `tests/contract.sh`: 235 checks passing against that binary                                      |

The bundle documents the contract of the `xr` release it ships beside: the upstream `dev` head when a release is
being cut from it, or the released artifact once it is out. A release that changes nothing the bundle documents gets
no bundle pass: `v4.1.1` changes only the vendored X API spec (`crates/xdk/vendor`) and version metadata, so the
contract above holds for it. When any row above moves, re-run the harness and update the row in the same PR. Consumers
install from the head of `main` with the bundle's own `VERSION`; nothing pins the bundle to a binary version on either
side.

## Repository shape

| Path                 | Role                                                                                                                                                                                                |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `SKILL.md`           | Consumer-facing entry point. Loaded by the agent when the skill activates.                                                                                                                          |
| `references/`        | Reference material an agent reads on demand. One topic per file; deterministic.                                                                                                                     |
| `templates/`         | Starter prompts and task recipes that the agent copies into a target project.                                                                                                                       |
| `getting-started.md` | Human-oriented quickstart that complements `SKILL.md`.                                                                                                                                              |
| `scripts/`           | Consumer-side helpers shipped to install dirs (`dry-run-gate.sh`, `paginate.sh`) plus producer-side release tooling (`generate-changelog.py`, `sync-dev-after-release.sh`).                         |
| `scripts/release/`   | Vendored release gates (`drift.sh`, `guarded-paths.sh`, `_lib.sh`). Refreshed as verbatim copies from the `github-repo-setup` skill; never edited in place.                                         |
| `CODEOWNERS`         | Required reviewers for governance, release-integrity, legal-hygiene, and workflow-doc paths; pairs with the rulesets' code-owner-review rule. Lives at the repo root so a local-tree audit sees it. |
| `tests/`             | Producer-side: `run.sh` (stub-driven script tests, run by CI) and `contract.sh` + `stub-api.py` (the documented invocations against a real `xr`; local, needs `XR_BIN`).                            |
| `fixtures/`          | Producer-side stub `xr` binary used by `tests/run.sh`; models the real streams (success on stdout, error envelope on stderr with the exit code).                                                    |
| `evals/`             | Self-contained eval prompts dispatched against a fresh agent session. Producer.                                                                                                                     |
| `docs/`              | Planning artifacts (brainstorms, plans, solutions, reviews). Blocked from `main`.                                                                                                                   |
| `docs/solutions/`    | Symlink to `~/dev/solutions-docs` (shared knowledge store; categorized by `problem_type` with YAML frontmatter). Relevant when implementing or debugging in documented areas.                       |
| `.github/`           | Workflows, rulesets, PR template, Dependabot. (Issues disabled; see below.)                                                                                                                         |

## Branch model

- `dev`: forever branch. Daily work lands here via `feat/*` / `fix/*` / `chore/*` PRs.
- `main`: forever branch. Receives only `release/*` PRs cut from `origin/main` with `dev`'s tree overlaid on top and
  the guarded set stripped (`scripts/release/guarded-paths.sh`). Engineering docs under `docs/plans/`,
  `docs/solutions/`, `docs/brainstorms/`, `docs/reviews/` are blocked on `main` by `guard-main-docs`.
- `release/*`: ephemeral. Auto-deleted on merge.

See [`RELEASES.md`](RELEASES.md) for the full release workflow.

## CI

| Workflow                    | Triggers                    | What it checks                                                                                |
| --------------------------- | --------------------------- | --------------------------------------------------------------------------------------------- |
| `ci.yml`                    | push + PR to `main` / `dev` | `markdownlint`, `shellcheck` on `scripts/` + `tests/` + `fixtures/bin/`, fixture-driven tests |
| `guard-main-docs.yml`       | PR to `main`                | Blocks engineering docs from reaching `main`                                                  |
| `guard-release-branch.yml`  | PR to `main`                | Rejects any head branch not under `release/`                                                  |
| `guard-main-provenance.yml` | PR to `main`                | Requires every commit to carry a `(#N)` squash-merge reference                                |

## Refreshing the bundle against a new `xr`

The documented contract is only as true as the last binary it was run against. A refresh is a five-step loop; skip
none of them, and never trust `xr --help`, the bundled schema files, or a previous pass's prose in place of running
the invocation.

1. Pick the target. When a release is out and `git diff --stat <tag> origin/dev -- crates/*/src` is empty, the
   Homebrew bottle is the contract (`brew upgrade xurl-rs`, then `xr --version`). When the bottle has moved past the
   target release, use that release's asset: `gh release download v<x.y.z> -R brettdavies/xurl-rs -p
   'xurl-rs-x86_64-unknown-linux-gnu.tar.gz' -p sha256sum.txt`, check it with `sha256sum -c`, and unpack it outside
   the repo. Otherwise build the head: `cd ~/dev/xurl-rs && git checkout dev && git pull && cargo build`. Note the
   commit either way.
2. Run the harness with the full path, never a bare `xr` (a Homebrew install and a dev build both answer to the name):
   `XR_BIN=$(brew --prefix)/bin/xr bash tests/contract.sh` or `XR_BIN=$HOME/dev/xurl-rs/target/debug/xr …`. Every
   failing row is either a bundle claim that is now wrong (fix the doc and the row) or an upstream regression (report
   it upstream, keep the row failing). The harness runs under a scratch `HOME` and `XURL_TOKEN_STORE`; keep every
   ad-hoc probe under the same two overrides, because a `cargo test` run in `xurl-rs` once overwrote a real `~/.xurl`
   (`docs/solutions/conventions/hermetic-cli-spawn-seam-with-unwritable-default-store-and-escape-hatch-guard.md`).
3. Read the upstream delta (`git log --stat <last-verified>..HEAD`) for surface the harness has no row for: a new
   command, a new flag, a new reason. Probe it, document it, add a row.
4. Re-run `bash tests/run.sh` (the stub tests), `shellcheck --severity=style scripts/*.sh tests/*.sh fixtures/bin/xr`,
   and `markdownlint-cli2 .`; then re-run the evals in `evals/` that touch the changed surface.
5. Update the **Verified against** table above and `SKILL.md`'s contract-version sentence.

Two groups in the harness matter equally. Group 1 runs against an empty store and a closed port and sees every failure
envelope; group 2 runs against `tests/stub-api.py` with a fake user token and sees every **success** document. A
closed-port harness alone never observes a success, so a bundle verified that way can document a success key the
binary never emits and ship a paginator that fails on every real page. The stub server is what makes the success half
checkable; the reasoning and the failure it guards against are in
`docs/solutions/developer-experience/verify-cli-success-paths-with-a-stub-server-not-a-closed-port.md`.

`tests/contract.sh` is not wired into CI: it needs a built `xr`, and the bundle intentionally tracks the upstream
`dev` head ahead of any release artifact CI could download. Run it locally before every bundle pass.

## Issues

This repo has its issue tracker **disabled** (`has_issues: false`). Do not attempt to file issues here; the API will
reject them and the UI hides the tab.

All issues, whether `xurl-rs` CLI bugs, skill-bundle bugs (stale references, broken links, wrong invocations), or
proposals for new templates / references / `getting-started` flows, route to the upstream CLI repo:

➡️ **<https://github.com/brettdavies/xurl-rs/issues/new/choose>**

When an agent files an issue about this skill bundle specifically, **prefix the title with `[skill]`** so the upstream
maintainer can triage it.

## House rules

- **No AI attribution in commits or PR bodies.** No `Co-Authored-By: Claude`, no `Generated with` trailers.
- **Signed commits required** on `main` and `dev` (ruleset-enforced).
- **Squash merges only.** PR title becomes the commit title; PR body becomes the commit message.
- **Conventional Commits**: `type(scope): description`. Prefer `feat` / `fix` over `chore` for anything user-observable.
- **Pin third-party actions by SHA**, never mutable tag. Trailing comment names the version.
