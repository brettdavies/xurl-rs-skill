# AGENTS.md for xurl-rs-skill

Producer-side instructions for agents (Claude Code, Codex, Cursor, OpenCode) working **on** this skill bundle.
Consumer-side instructions (how an agent should *use* the bundle once installed) live in `SKILL.md`.

## Verified against

| Field               | Value                                                                                            |
| ------------------- | ------------------------------------------------------------------------------------------------ |
| xurl-rs commit      | `e2c7e8a`, the `v4.2.0` tag (2026-09-30)                                                         |
| Binary self-report  | `xr 4.2.0` (`xdk-rs 0.1.3`), the `x86_64-unknown-linux-gnu` asset of the `v4.2.0` GitHub release |
| Contract documented | 4.2.0: `media alt-text` / `media subtitles`, skill destination variables, `legacy_install_dir`   |
| Harness result      | `tests/contract.sh`: 212 checks (280 assertions) passing against that binary                     |

The bundle documents the contract of the `xr` release it ships beside: the upstream `dev` head when a release is
being cut from it, or the released artifact once it is out. A release that changes nothing the bundle documents (only
the vendored X API spec in `crates/xdk/vendor`, say, or version metadata) gets no bundle pass, and the contract above
holds for it. When any row above moves, re-run the harness and update the row in the same PR. Consumers
install from the head of `main` with the bundle's own `VERSION`; nothing pins the bundle to a binary version on either
side.

## Repository shape

| Path                 | Role                                                                                                                                                                                                                                                                                              |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `SKILL.md`           | Consumer-facing entry point. Loaded by the agent when the skill activates.                                                                                                                                                                                                                        |
| `references/`        | Reference material an agent reads on demand. One topic per file; deterministic.                                                                                                                                                                                                                   |
| `templates/`         | Starter prompts and task recipes that the agent copies into a target project.                                                                                                                                                                                                                     |
| `getting-started.md` | Human-oriented quickstart that complements `SKILL.md`.                                                                                                                                                                                                                                            |
| `scripts/`           | Consumer-side helpers shipped to install dirs (`dry-run-gate.sh`, `paginate.sh`) plus producer-side release tooling (`generate-changelog.py`, `sync-dev-after-release.sh`).                                                                                                                       |
| `scripts/release/`   | Vendored release gates (`drift.sh`, `guarded-paths.sh`, `_lib.sh`). Refreshed as verbatim copies from the `github-repo-setup` skill; never edited in place.                                                                                                                                       |
| `CODEOWNERS`         | Required reviewers for governance, release-integrity, legal-hygiene, and workflow-doc paths; pairs with the rulesets' code-owner-review rule. Lives at the repo root so a local-tree audit sees it.                                                                                               |
| `tests/`             | Producer-side: `run.sh` (script tests, CI); `contract.sh` + `stub-api.py` (the documented invocations against a real `xr`; needs `XR_BIN`); `refresh.sh` (a bundle pass in one command) with `fetch-xr.sh`, `surface-diff.sh`, `xr-sandbox.sh`; `core-env-guard.sh` + allowlist (CI).             |
| `fixtures/`          | Producer-side stub `xr` binary used by `tests/run.sh`; models the real streams (success on stdout, error envelope on stderr with the exit code).                                                                                                                                                  |
| `evals/`             | Self-contained eval prompts dispatched against a fresh agent session. Producer.                                                                                                                                                                                                                   |
| `docs/`              | Planning artifacts (brainstorms, plans, solutions, reviews). Blocked from `main`.                                                                                                                                                                                                                 |
| `docs/solutions/`    | Symlink to `~/dev/solutions-docs` (shared knowledge store; categorized by `problem_type` with YAML frontmatter). Relevant when implementing or debugging in documented areas.                                                                                                                     |
| `.github/`           | Workflows, rulesets, PR template, Dependabot. (Issues disabled; see below.)                                                                                                                                                                                                                       |

## Branch model

- `dev`: forever branch. Daily work lands here via `feat/*` / `fix/*` / `chore/*` PRs.
- `main`: forever branch. Receives only `release/*` PRs cut from `origin/main` with `dev`'s tree overlaid on top and
  the guarded set stripped (`scripts/release/guarded-paths.sh`). Engineering docs under `docs/plans/`,
  `docs/solutions/`, `docs/brainstorms/`, `docs/reviews/` are blocked on `main` by `guard-main-docs`.
- `release/*`: ephemeral. Auto-deleted on merge.

See [`RELEASES.md`](RELEASES.md) for the full release workflow.

## CI

| Workflow                    | Triggers                    | What it checks                                                                                                    |
| --------------------------- | --------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `ci.yml`                    | push + PR to `main` / `dev` | `markdownlint`, `shellcheck` on `scripts/` + `tests/` + `fixtures/bin/`, the core-env guard, fixture-driven tests |
| `guard-main-docs.yml`       | PR to `main`                | Blocks engineering docs from reaching `main`                                                                      |
| `guard-release-branch.yml`  | PR to `main`                | Rejects any head branch not under `release/`                                                                      |
| `guard-main-provenance.yml` | PR to `main`                | Requires every commit to carry a `(#N)` squash-merge reference                                                    |

## Refreshing the bundle against a new `xr`

The documented contract is only as true as the last binary it was run against. A refresh is a five-step loop; skip
none of them, and never trust `xr --help`, the bundled schema files, or a previous pass's prose in place of running
the invocation.

1. Run `bash tests/refresh.sh v<x.y.z>`. It fetches that release's asset for this machine (`tests/fetch-xr.sh`,
   checksum-checked, cached outside the repo), prints the surface the release adds or removes since the tag in the
   table above (`tests/surface-diff.sh`, from upstream's `scripts/check-surface-bump.sh`), runs the contract harness,
   the fixture tests, the core-env guard, shellcheck, and markdownlint with CI's globs, and ends with one line per
   step. For an unreleased `dev` head, build it (`cargo build` in a xurl-rs checkout) and run `XR_BIN=<path> bash
   tests/contract.sh` and the other checks by hand; note the commit either way.
2. Scope the pass to that surface diff plus the release notes' env vars, exit codes, and behavior fixes, which the diff
   has no artifact for. A failing harness check is either a bundle claim that is now wrong (fix the doc and the check)
   or an upstream regression (report it upstream, keep the check failing).
3. Probe new surface with `XR_BIN=<path> bash tests/xr-sandbox.sh <args>`, never a bare `xr`: a Homebrew install and a
   dev build both answer to the name, and the sandbox runs under the harness's isolation (a scratch `XURL_SKILL_HOME`
   and `XURL_TOKEN_STORE`, the host config-directory variables that outrank `XURL_SKILL_HOME` unset, the API at a
   closed port), so a probe reads and writes nothing under the real `~/.xurl` or skill directories
   (`docs/solutions/conventions/hermetic-cli-spawn-seam-with-unwritable-default-store-and-escape-hatch-guard.md`).
   Document what it shows and add the needles or checks.
4. Re-run `tests/refresh.sh` until every step passes, then re-run the evals in `evals/` that touch the changed surface.
5. Update the **Verified against** table above and `SKILL.md`'s contract-version sentence; no other file names the
   version.

The docs state only what the binary cannot tell an agent itself: which stream a document lands on, exit codes, success
shapes, the scripts' behavior, and the gotchas. For counts, name lists, help text, and the environment-variable index
they point at `xr schema --list`, `xr validate --help`, `xr examples`, and `xr --help`, so those facts carry no harness
row and no per-release edit. A row runs its command once and asserts every needle for it (`check LABEL EXIT STREAM
NEEDLE [STREAM NEEDLE]... -- cmd`); add a needle to an existing row before adding a row for the same command.

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
