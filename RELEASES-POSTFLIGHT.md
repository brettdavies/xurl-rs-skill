<!-- Canonical version: 2026.10.22 (generic) -->
# Post-release verification: `xurl-rs-skill`

Operational post-flight checklist. Runs **after** the `release/v<version> → main` PR merges and you push the tag
(`git push origin vX.Y.Z`) per [`RELEASES.md` § Tagging and publishing](./RELEASES.md#tagging-and-publishing). Verifies
that the tag-triggered `release.yml` published the GitHub Release, that a fresh install resolves the release, and that
the release bookkeeping reached `dev`.

Companion to [`RELEASES-PREFLIGHT.md`](./RELEASES-PREFLIGHT.md), which gates the release-branch cut. Both docs follow
the same go/no-go shape: every box is explicit, an unchecked or red item holds the next release (or motivates a hotfix).

## Quick start: run the automated gates

```bash
scripts/release/postflight.sh all
```

The script (`scripts/release/postflight.sh`) is a verbatim copy from the `github-repo-setup` skill, built for the widest
pipeline the fleet runs (`release.yml` → Homebrew tap → `finalize-release.yml` → crates.io). It reads the tag from
`VERSION` and adjusts to what a repo has, so on this bundle three gates check and the rest skip with a reason:

| Sub-command     | Here                                                                                                           |
| --------------- | -------------------------------------------------------------------------------------------------------------- |
| `release`       | Checks: the tag's `release.yml` run concluded `"success"`                                                      |
| `tap`           | Skips: nothing dispatches to `brettdavies/homebrew-tap`, so no tap run follows `release.yml`                   |
| `finalize`      | Skips: no tap calls back, so no `finalize-release.yml` run                                                     |
| `make-latest`   | Checks: the GitHub Release is non-draft and non-prerelease, and `releases/latest` resolves to it               |
| `crates`        | Skips: no `Cargo.toml`                                                                                         |
| `tags`          | Skips: no `Cargo.toml`                                                                                         |
| `backport`      | Checks: a merged PR to `dev` carries the tag in its title, the one `scripts/sync-dev-after-release.sh` opens   |
| `surface-smoke` | Prints nothing: `scripts/release/surface-smoke.sh` is not vendored, because the bundle has no deployed surface |
| `all`           | Every above                                                                                                    |

Flags this repo uses:

- `--tag vX.Y.Z`: override auto-detection (default: `v` plus `VERSION`; falls back to the newest `v[0-9]*` tag)
- `--repo OWNER/REPO`: override the auto-detected nameWithOwner

`--env`, `--tap-repo`, `--crate`, `--staging-url`, and `--prod-url` serve pipelines this repo does not have.

## Checklist

Run once `release.yml` finishes for the tag.

- [ ] **`release.yml` green end-to-end.** `gh run watch <id> --exit-status`, then verify with
  `gh run view <id> --json conclusion --jq .conclusion`, because the watcher exit code alone is not authoritative (a
  completed watcher is not a green watcher). The integrity gate checked the tag shape, its reachability from `main`, and
  `VERSION`; the release job created the GitHub Release. Run `scripts/release/postflight.sh release` for the automated
  check.
- [ ] **GitHub Release published and marked latest.**
  `gh api repos/brettdavies/xurl-rs-skill/releases/latest --jq .tag_name` returns `vX.Y.Z`, not the previous tag. Run
  `scripts/release/postflight.sh make-latest` for the automated check.
- [ ] **The Release notes are this version's `CHANGELOG.md` section.** `gh release view vX.Y.Z --json body --jq .body`
  opens on `## [X.Y.Z]`. A run that found no section warned in its log (`::warning::CHANGELOG.md has no section`) and
  published generated notes instead; fix the changelog through the normal flow, then re-run
  `gh workflow run release.yml -f tag=vX.Y.Z`, which replaces the notes.
- [ ] **A fresh install resolves the release.** Install into a scratch skills directory so the real one is untouched,
  and confirm the clone carries the new version:

  ```bash
  SCRATCH=$(mktemp -d)
  git clone --depth 1 https://github.com/brettdavies/xurl-rs-skill "$SCRATCH/xurl-rs"
  cat "$SCRATCH/xurl-rs/VERSION"      # X.Y.Z
  trash "$SCRATCH"
  ```

  `xr skill install <host>` performs the same shallow clone of `main`, so this is the tree every new install receives.
- [ ] **Last-good identifier recorded.** Before the release goes live, note the previous tag somewhere reachable under
  incident pressure, so a rollback is a single command ([`RELEASES.md` § Rollback](./RELEASES.md#rollback)).
- [ ] **Rollback path confirmed.** If this release is bad, roll back at the surface first, then land a `fix` or `revert`
  through the normal `dev` to `release/*` to `main` flow so `main` reconverges with what is live.
- [ ] **Backport `main` → `dev`** via a **merged PR to `dev` with the version in its title.** Bring the release-only
  changes (`VERSION`, `CHANGELOG.md`, and anything the release branch edited on `main` that never round-tripped to
  `dev`) across with `scripts/sync-dev-after-release.sh`, which opens that PR
  ([`RELEASES.md` § After publish](./RELEASES.md#after-publish-sync-dev-with-the-release)). It keeps the next release's
  drift and `diff-B` checks quiet, so a real missed change stands out instead of hiding in expected divergence.

  ```bash
  scripts/sync-dev-after-release.sh vX.Y.Z
  ```

  The gate (`scripts/release/postflight.sh backport`) searches merged PRs to `dev` by the tag (the search index
  tokenizes `v1.2.0` as one word, so a bare `1.2.0` misses it) and accepts either spelling in the title. Its SKIP and
  FAIL name the sync command to run.

## Related docs

- [`RELEASES-PREFLIGHT.md`](./RELEASES-PREFLIGHT.md): pre-cut go/no-go checklist (runs BEFORE this one).
- [`RELEASES.md`](./RELEASES.md): operational runbook for the full release lifecycle.
- [`RELEASES-RATIONALE.md`](./RELEASES-RATIONALE.md): release-flow rationale.
