<!-- Canonical version: 2026.11.02 (generic) -->
# Pre-release verification: `xurl-rs-skill`

Operational pre-flight checklist. Walk it before step 1 of
[`RELEASES.md` § Releasing dev to main](./RELEASES.md#releasing-dev-to-main), the cut: it gates the `release/v<version>`
branch, not the daily dev integration. The automated gates (`scripts/release/preflight.sh all`) run at step 3, against
the committed release branch, because the mechanics checks read the bumped version and the release tree; the cut runs
the drift gate itself before it branches. Each box is an explicit go/no-go. If any item is unchecked or red, hold the
release.

CI catches mechanical regressions inside the repo. This checklist covers what CI structurally can't:

- Behavioral drift against the `xr` consumers actually run. CI's `contract` job runs the harness against the release the
  AGENTS.md "Verified against" table pins and nothing newer, while `xr skill install` users pair the bundle with
  whatever `xr` they installed, often a later one.
- The bundle's own version bookkeeping: `VERSION`, the release changelog, and the `xr` contract version `SKILL.md`
  names.
- What the release adds to `main`, which every consumer clones.

Post-tag verification (`release.yml` → GitHub Release → `main → dev` backport) lives in
[`RELEASES-POSTFLIGHT.md`](./RELEASES-POSTFLIGHT.md). The tag push happens AFTER the release-branch cut and the
PR-to-main merge, so verification of the tag-triggered pipeline is post-flight, not pre-flight.

## Quick start: run the automated gates

Most of this checklist runs from one script. The bundle builds nothing, so run it straight after the cut's commit:

```bash
scripts/release/preflight.sh all
```

`scripts/release/preflight.sh` started from the `github-repo-setup` skill's skeleton. The drift, surface,
changelog-sections, semver, and mechanics gates are the skeleton's; the smoke gate body and the mechanics line that
checks the documented `xr` version are this repo's. `all` runs the drift gate first, since nothing else matters while
`main` holds changes `dev` never received. The recipes in the sections below document what each gate verifies and serve
as the manual fallback when running by hand.

Sub-commands let you re-run one section in isolation:

| Sub-command          | What it checks                                                                                                                                       | Source of truth                                                        |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `drift`              | Commits on `main` since the last release whose changes `dev` lacks, `.github/` parity, lockfile packages `main` resolves newer                       | `scripts/release/drift.sh`                                             |
| `surface`            | Commits since the last release reached `dev`, files changed since the last tag, breaking markers                                                     | `git log`, `git diff`                                                  |
| `smoke`              | The contract harness against the pinned `xr` and the newest `xr` release, and a negative control on `scripts/dry-run-gate.sh`                        | `tests/contract.sh`, `tests/fetch-xr.sh`, `tests/xr-sandbox.sh`        |
| `mechanics`          | `VERSION`, the changelog's top section, the documented `xr` version, leak check, unguarded docs added to `main`, diff-B vs `origin/dev`              | `VERSION`, `CHANGELOG.md`, `SKILL.md`, `AGENTS.md`, `guarded-paths.sh` |
| `changelog-sections` | No PR this release carries leaves its changelog entry to its title for want of a section                                                             | `generate-changelog.py`, `gh`                                          |
| `semver`             | Skips: no `Cargo.toml`                                                                                                                               | `cargo semver-checks`                                                  |
| `all`                | Every above sequentially, drift first. No `surface-smoke`: the bundle has no deployed surface, so `scripts/release/surface-smoke.sh` is not vendored |                                                                        |

Flags:

- `--tag TAG`: override `LAST_TAG` resolution (default: the newest `v[0-9]*` tag)

After `git push origin vX.Y.Z` triggers the release pipeline, run
[`scripts/release/postflight.sh all`](./RELEASES-POSTFLIGHT.md) to verify the downstream chain.

## Establish the surface

Everything below assumes you know what's changing. Run this first.

Driven by `scripts/release/preflight.sh surface`.

```bash
LAST_TAG=$(git tag --list 'v[0-9]*' --sort=-version:refname | head -n 1)
# The commit that synced the tag back into dev opens dev's window.
SINCE=$(git log origin/dev --format='%H %s' \
  | grep -E -m1 "^[0-9a-f]+ chore\(release\): (sync dev after|backport) ${LAST_TAG//./\\.}( |$)" | cut -d' ' -f1)
git log "$SINCE..origin/dev" --oneline                          # commits going out
git diff "$LAST_TAG" origin/dev --name-only \
  | grep -Ev "$(scripts/release/guarded-paths.sh)"              # file-level scope: what ships
git log "$SINCE..origin/dev" --grep '^[a-z]\+\(([^)]*)\)\?!:' --oneline   # Conventional-Commits breaking markers, scoped or not
```

Every release squash-merges into `main`, so the tag shares no recent history with `dev`, and a log from the tag counts
`dev`'s whole past. The window opens at the commit that synced the tag back into `dev`, whose subject reads
`chore(release): sync dev after vX.Y.Z`. The file list compares trees, so it reads from the tag directly, minus the
guarded set `dev` carries but never ships. With no tags yet, or no commit syncing the tag back, `preflight.sh surface`
SKIPs, and the surface is `origin/main..origin/dev`.

The previous release branch took `dev` before that sync commit merged, so a PR that merged between the cut and the sync
went out in neither release, and the log above does not show it. `generate-changelog.py` reads it: it also reads the PRs
between the sync commit before that one and this one, and leaves out every PR `CHANGELOG.md` already lists. The
generated section is the complete list, and a breaking PR merged in that gap appears in its `### Breaking changes`
rather than in the tally.

Every `!:` commit drives the major-version decision and gets a row in the release's `### Breaking changes` section.

## Checklist

### Branch drift (main ahead of dev)

Driven by `scripts/release/preflight.sh drift` (delegates to `scripts/release/drift.sh`).

Security PRs, hotfixes, and config edits land on `main` first. The release branch is cut from `main` and then takes
`dev`'s changes, so anything `main` holds that `dev` never received is reverted by the release or collides with it, and
Dependabot raises the same fix again.

<!-- canonical:begin drift-gate -->

- [ ] The previous release's own bookkeeping reached `dev` (gate 0: the version carriers and `CHANGELOG.md` as the
  release left them). It fails when a backport never ran; run `scripts/sync-dev-after-release.sh v<previous>`, merge its
  PR, and rerun.
- [ ] Every commit on `main` since the last release has its changes on `dev` (gate 1 lists the ones that do not, as
  `differs` or `missing`). Backport them by PR into `dev` first, merge, and rerun.
- [ ] Nothing under `.github/` on `main` is missing from `dev` (gate 2). `.github/` reaches `main` through the release,
  so config that has reached `dev` and not `main` is what this release delivers, and the gate counts it. The gate fails
  on the other direction, where `main` holds workflow or ruleset config `dev` never received, and names each path as
  `missing` or `differs`.
- [ ] No lockfile package resolves newer on `main` than on `dev` (gate 3, which reads `package-lock.json`, `bun.lock`,
  and `Cargo.lock`). The one benign case is a version still inside the local package manager's release-age window when
  the advisory is already patched at `dev`'s version.
- [ ] `dev`-newer packages are the routine updates this release ships; the gate counts them and does not list them.

<!-- canonical:end drift-gate -->

### Dependabot

Dependabot watches only the GitHub Actions pins here (`.github/dependabot.yml`), and its PRs target `dev`.

- [ ] No Dependabot PR is open against `dev`: `gh pr list --base dev --author app/dependabot`. Merge or close each one
  first, so the release does not ship an action pin a pending PR already replaces.

### Contract against released `xr`

Driven by `scripts/release/preflight.sh smoke`.

The bundle documents what `xr` does; the binary is the source of truth. CI runs the contract harness against the pinned
release on every PR, so the pinned row is a re-check of the release tree. The newest-release row is the one CI cannot
make.

- [ ] **The pinned release passes the harness.** `tests/pinned-xr.sh` reads the tag from the AGENTS.md "Verified
  against" table, `tests/fetch-xr.sh` downloads and checksum-checks that release, and `tests/contract.sh` runs every
  documented invocation against it.
- [ ] **The newest `xr` release passes the harness, or the release waits for a bundle pass.** When the newest
  `brettdavies/xurl-rs` release is not the pinned one, the gate runs the same harness against it. A failure means the
  bundle documents behavior the current `xr` no longer has; run the refresh loop in
  [`AGENTS.md` § Refreshing the bundle against a new `xr`](AGENTS.md#refreshing-the-bundle-against-a-new-xr) first, or
  report the regression upstream when the binary is wrong.
- [ ] **Negative control: `scripts/dry-run-gate.sh` refuses a write whose preflight fails.** The gate runs the shipped
  dry-run gate against the pinned `xr` with an empty post, under `tests/xr-sandbox.sh`'s isolation, and requires exit 1
  with the gate's own `would NOT succeed ... reason=empty-body` line. `xr`'s live call refuses an empty post with exit 1
  as well, so the line, not the exit code, is what shows the gate still runs the preflight.

### Release mechanics sanity

Driven by `scripts/release/preflight.sh mechanics`.

These items duplicate steps in `RELEASES.md` deliberately: easy to skip, expensive to recover from. Confirm explicitly.

- [ ] `VERSION` bumped to the new tag value (`release.yml`'s integrity gate enforces this; catch early).
- [ ] `CHANGELOG.md`'s top section names that version and holds no `[Unreleased]` placeholder.
- [ ] `SKILL.md`'s contract sentence ("This bundle describes the `xr X.Y.Z` contract") names the release the AGENTS.md
  "Verified against" table pins. Those are the two places a bundle pass updates, and the gate fails when they disagree.
- [ ] No PR this release carries leaves its changelog entry to its title. Swept, not sampled, by
  `scripts/release/preflight.sh changelog-sections`, which runs `generate-changelog.py --audit-sections` over the PRs
  merged into `dev` since the previous release and names every one that never offered the `## Changelog` section under a
  title the fallback would print. A section left empty on purpose passes.
- [ ] The full local pre-push check (`scripts/hooks/pre-push`) mirrors CI; run it explicitly before pushing the release
  branch.
- [ ] `scripts/release/cut-release-branch.sh` exited 0, so its check A held: the staged tree equals `origin/dev`'s apart
  from `VERSION`, `CHANGELOG.md`, and the guarded paths.
- [ ] **Leak check before pushing the release branch.** No guarded path may be added or modified in the diff vs
  `origin/main`. The cut's check B screens the staged tree, and `preflight.sh mechanics` screens the committed branch;
  both resolve the set from `.github/workflows/guard-main-docs.yml` via `scripts/release/guarded-paths.sh`, so never
  restate the pattern inline. `--diff-filter=ACMR`, because a release that removes a guarded doc `main` still carries
  lists the removal too, and that is cleanup, not a leak.

  ```bash
  GUARDED="$(scripts/release/guarded-paths.sh)"
  git diff origin/main..HEAD --diff-filter=ACMR --name-only | grep -E "$GUARDED" && echo "LEAKED: reset and redo" || echo "(clean)"
  ```

- [ ] **Every doc this release adds to `main` is meant to ship.** The leak check is blind to a category nobody
  registered. The cut's check D and `preflight.sh mechanics` list the unguarded additions, as does the command below;
  each one needs a reason to ship, or it gets registered in the workflow's `extra_paths` and removed from the branch.
  `--no-renames` lists a doc moved from one `main` carries as added, where rename detection would report it as a rename
  and the `A` filter would drop it.

  ```bash
  git diff --no-renames origin/main..HEAD --diff-filter=A --name-only | grep -E '(^docs/|\.md$)' | grep -Ev "$GUARDED"
  ```

### Post-tag verification

Moved to [`RELEASES-POSTFLIGHT.md`](./RELEASES-POSTFLIGHT.md) because tagging happens **after** the release-branch cut
and PR-to-main merge, so verification of the tag-triggered pipeline is post-flight, not pre-flight. Run
`scripts/release/postflight.sh all` once `release.yml` finishes for the tag.

## Related docs

- [`RELEASES-POSTFLIGHT.md`](./RELEASES-POSTFLIGHT.md). Runs AFTER the tag push to verify the downstream pipeline.
- [`RELEASES.md`](./RELEASES.md). Operational runbook this checklist gates.
- [`RELEASES-RATIONALE.md`](./RELEASES-RATIONALE.md). Release-flow rationale.
- [`AGENTS.md`](./AGENTS.md). The "Verified against" table, the contract harness, and the bundle refresh loop.
