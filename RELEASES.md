<!-- Canonical version: 2026.11.03 (generic) -->
<!-- canonical: version-scheme semver -->
# Releasing `xurl-rs-skill`

Operational runbook. Rationale lives in [`RELEASES-RATIONALE.md`](./RELEASES-RATIONALE.md). Pre-cut go/no-go checklist
lives in [`RELEASES-PREFLIGHT.md`](./RELEASES-PREFLIGHT.md); post-tag verification in
[`RELEASES-POSTFLIGHT.md`](./RELEASES-POSTFLIGHT.md).

```text
feature branch → PR to dev (squash merge)
              → dev's tree overlaid onto a release/* branch cut from main
              → PR to main (squash merge)
              → the tag push fires release.yml, which publishes the GitHub Release
```

Direct commits to `dev` or `main` are not permitted: every change has a PR number in its squash commit message.

Consumers install the bundle with `git clone --depth 1` of this repo and update by removing the install directory and
cloning again (`xr skill update`), so the head of `main` is the shipped artifact. There is no build, registry, or deploy
step; the GitHub Release is the published record of what each tag contains.

## Branches

| Branch                                 | Role                                    | Lifetime                                    | Protection                           |
| -------------------------------------- | --------------------------------------- | ------------------------------------------- | ------------------------------------ |
| `main`                                 | Production. Only release commits.       | Forever.                                    | `.github/rulesets/protect-main.json` |
| `dev`                                  | Integration. All feature PRs land here. | Forever. Never delete.                      | `.github/rulesets/protect-dev.json`  |
| `feat/*`, `fix/*`, `chore/*`, `docs/*` | Feature work.                           | One PR's worth. Auto-deleted on merge.      | None. Squash into dev freely.        |
| `release/*`                            | Head of a dev → main PR.                | One release's worth. Auto-deleted on merge. | None.                                |

→ Rationale: [`RELEASES-RATIONALE.md` § Branching model](./RELEASES-RATIONALE.md#branching-model).

## Daily development (feature → dev)

```bash
git checkout dev && git pull
git checkout -b feat/short-description
# ... work ...
git push -u origin feat/short-description
gh pr create --base dev --title "feat(scope): what changed"
# CI passes → squash-merge (PR_BODY becomes the dev commit message)
```

- **Commit style**: [Conventional Commits](https://www.conventionalcommits.org/).
- **PR body**: follow `.github/pull_request_template.md`. See [§ PR body](#pr-body).
- **Git hooks**: `git config core.hooksPath scripts/hooks` once per clone runs the staged checks on commit and the local
  CI mirror on push ([`CONTRIBUTING.md` § Git hooks](CONTRIBUTING.md#git-hooks)).

### Dev-direct exception

Paths that live only on `dev` and never ship to `main` can be committed directly to `dev` without a feature branch or
PR. The `guard-main-docs` workflow blocks them from `main` PRs regardless. The exception applies to:

- Engineering docs: `docs/brainstorms/`, `docs/ideation/`, `docs/plans/`, `docs/research/`, `docs/reviews/`,
  `docs/solutions/`, and anything under `.context/`.

`scripts/release/guarded-paths.sh` prints the authoritative set, resolved from the workflow. Run it rather than trusting
this list, which is a reading aid. A path that stays off `main` but is not in the reusable workflow's base list is
registered through the caller's `extra_paths` input in `.github/workflows/guard-main-docs.yml`; entries are globs (`**/`
any depth, `*` and `?` within a segment, a trailing `/` guards the subtree).

The standard feature → PR → squash-merge flow remains required for everything else, including consumer-facing markdown
(`SKILL.md`, `references/`, `templates/`, `README.md`, `AGENTS.md`, `CONTRIBUTING.md`, these runbooks).

## PR body

Every PR (feature, fix, docs, release) uses `.github/pull_request_template.md` verbatim. Six required sections, in
template order, no inventions: `## Summary`, `## Changelog`, `## Type of Change`, `## Related Issues/Stories`,
`## Testing`, `## Files Modified`. The template's other sections (`## Key Features`, `## Benefits`,
`## Breaking Changes`, `## Deployment Notes`, `## Screenshots/Recordings`, `## Checklist`, `## Additional Context`) are
optional: fill `## Breaking Changes` on a major, delete the rest when they do not apply.

- **No explainer prose anywhere in the body.** User-facing substance only.
- **Summary describes the net diff only**: what merged `main` looks like vs the base branch. Not commit history,
  intermediate state, or release mechanics.
- **Zero verification artifacts in the body.** No diff stats, leak-check output, pre-push gate results, CI status, or
  prose-scrub findings. Anomalies get fixed before push, not audit-trailed.
- **Changelog** subsections (`### Breaking changes` / `### Added` / `### Changed` / `### Deprecated` / `### Fixed` /
  `### Documentation`, the six headings of [§ Versioning](#versioning)): 1-5 bullets each, delete empty subsections,
  each bullet starts with a verb. A `## Changelog` heading left standing with no bullets under it says the PR ships
  nothing user-facing, and `generate-changelog.py` adds nothing for it, whatever the PR title says.
- **Type of Change**: one checkbox. Prefer `feat`/`fix` over `chore` for any user-observable change.
- **Related Issues/Stories**: four labels (`Story:` / `Issue:` / `Architecture:` / `Related PRs:`). All four required
  even when empty (`- None.` / `n/a`).
- **Files Modified**: four sub-headers (`Modified` / `Created` / `Renamed` / `Deleted`). All four required even when
  empty.
- **No AI attribution** in commits or PR bodies.
- **No hard line wraps**: one logical line per paragraph or bullet.

→ Rationale: [`RELEASES-RATIONALE.md` § PR body conventions](./RELEASES-RATIONALE.md#pr-body-conventions).

## Versioning

The marked lines below are github-repo-setup's SemVer section of `references/versioning.md`, which the drift check
compares, and line 2 declares the scheme. A site, a CalVer repo, or one that ships no version changes the declaration
and copies that scheme's section in their place.

<!-- canonical:begin versioning-semver -->

This repo follows [SemVer 2.0.0](https://semver.org/). Its version comes from its changelog: every PR files each
user-facing change under one of the six headings below, and a release takes the highest bump any of its PRs calls for.
The rules cover only the surfaces § What the contract is names.

### What the contract is

<!-- canonical:repo-begin contract -->

The bundle's contract is what an agent reading an installed copy relies on:

- **Skill identity:** `SKILL.md`'s frontmatter `name`, `xurl-rs`, which names the directory `xr skill install` writes
  and the skill a host activates.
- **Bundle layout:** the paths an agent opens by name: `SKILL.md`, `getting-started.md`, each `references/<topic>.md`,
  each `templates/<recipe>.md`, and `scripts/dry-run-gate.sh` and `scripts/paginate.sh` with the `scripts/_common.sh`
  they source.
- **The shipped scripts:** each script's usage line, flags, exit codes, and which stream carries what, as its header and
  [`scripts/README.md`](./scripts/README.md) state them.
- **The documented `xr` contract:** the `xr` release `SKILL.md` names, and each invocation, envelope field, and exit
  code the bundle states for it, every one checked by `tests/contract.sh`.

The wording of the docs, the frontmatter `description` included, is not contract, and neither are the producer files:
`scripts/release/`, `scripts/generate-changelog.py`, `scripts/sync-dev-after-release.sh`, `tests/`, `fixtures/`,
`evals/`, the runbooks, `AGENTS.md`, and `CONTRIBUTING.md`.

<!-- canonical:repo-end -->

### The six headings

| Heading            | Holds                                                                   | Bump  |
| ------------------ | ----------------------------------------------------------------------- | ----- |
| `Breaking changes` | a contract surface removed, renamed, or retyped, or its meaning changed | major |
| `Added`            | a new contract surface                                                  | minor |
| `Changed`          | a visible change outside the contract                                   | patch |
| `Deprecated`       | a contract surface marked for removal                                   | minor |
| `Fixed`            | behavior brought back to the documented contract                        | patch |
| `Documentation`    | documentation only                                                      | patch |

`generate-changelog.py` writes them in this order and any other heading after them. A contract removal is a
`Breaking changes` bullet that starts with "Remove"; a removal outside the contract goes under `Changed`, or is left
out. Removals ship when they are ready, with no deprecation schedule. A `type!:` commit is a prompt to check the PR's
sections, never the bump itself.

### The bump

`scripts/generate-changelog.py --bump` prints the next version from the PRs merged since the last release, and
`cut-release-branch.sh` prints it beside the version the cut is given:

- The highest heading among their sections sets the bump.
- A `rust-version` raised since the last tag is a minor-level change, so it lifts a patch to a minor. A Rust repo's
  `rust-version` equals the toolchain `rust-toolchain.toml` pins, and CI's MSRV job builds on exactly that version.
- Before 1.0, a major or a minor moves the middle number and a patch moves the last: `0.4.2` becomes `0.5.0` or `0.4.3`.
  This is stricter than Cargo's convention on purpose: an addition never ships as a last-number bump, so a `^0.y`
  dependent receives only fixes until it opts in.
- From 1.0, when the sections call for a major, the release agent asks the maintainer: a major, or a minor under the
  small-break exception. A minor ships `docs/migrating/v<version>.md`, whose first line names the exception, and
  preflight fails a 1.0+ release that keeps its major and carries `### Breaking changes` without that guide.

### Overrides

<!-- canonical:repo-begin overrides -->

None. A repo that departs from the bump, the pre-1.0 rule, or the MSRV rule states the rule it follows here.

<!-- canonical:repo-end -->

<!-- canonical:end versioning-semver -->

## Releasing dev to main

Before cutting a release branch, walk [`RELEASES-PREFLIGHT.md`](./RELEASES-PREFLIGHT.md) end-to-end. Any unchecked item
holds the release.

Engineering docs (`docs/plans/`, `docs/solutions/`, `docs/brainstorms/`, `docs/reviews/`) live on `dev` only.
`guard-main-docs.yml` blocks them from reaching `main`, `guard-release-branch.yml` rejects any PR to main whose head
isn't `release/*`, and `guard-main-provenance.yml` requires every commit on the PR to carry a `(#N)` squash-merge
reference.

**Branch naming**: `release/v<version>` or `release/v<version>-<slug>`. `generate-changelog.py` extracts the version
from the branch name, so the `v<version>` prefix is required.

`main` and `dev` share only an ancient merge-base: every release squash-merges into `main`, so the two branches diverge
in history even as their content converges. Reconciling that with a merge, or a branch cut from `dev`, produces a pile
of `add/add` and rename/delete conflicts that are artifacts of the lineage, not of the content shipping. The release
branch is therefore built as a **clean descendant of `main`** with `dev`'s tree overlaid on top, asserting the desired
end-state directly. `scripts/release/cut-release-branch.sh` builds it:

```bash
# 1. Build the branch: drift gate, branch from main, overlay dev's tree, strip the
#    guarded paths, generate the changelog, and run checks A, B, and D. Stops
#    before committing; --dry-run prints the plan and touches nothing.
scripts/release/cut-release-branch.sh <version>

# 2. Bump the version carrier: VERSION, plain text, no leading "v".
printf '%s\n' <version> > VERSION

# 3. Commit the overlay as one commit sitting directly on top of main, then run the
#    preflight gates against it.
git add -A
git commit
scripts/release/preflight.sh all

# 4. Push and open the PR. Scrub the body in /tmp/ first.
git push -u origin release/v<version>
gh pr create --base main --head release/v<version> --title "release: v<version>" --body-file /tmp/body.md
```

The script asserts `dev`'s tree onto the `main` base with `git read-tree -u --reset`, one operation that carries the
deletions too. Asserting the tree is what keeps a file `main` carries and `dev` deleted from shipping to `main` anyway.
A diff-driven overlay has to enumerate those deletions separately, and with rename detection on, such a file pairs with
any similar `dev`-side addition, reports as `R` rather than `D`, and drops off the list entirely.

It then strips the paths `guard-main-docs` forbids, resolved from the workflow by `scripts/release/guarded-paths.sh`
rather than from any restated copy, writes the changelog with
`scripts/generate-changelog.py --from-dev-prs --tag v<version>`, and runs three checks:

| Check                                    | Asserts                                                                                                                                                                           | On failure                                                                                                     |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| A: staged tree vs `origin/dev`           | nothing differs but the version carriers (`VERSION` and `CHANGELOG.md` here) and the stripped guarded paths                                                                       | fails, naming each unexpected path                                                                             |
| B: guarded paths vs `origin/main`        | no guarded path is added or modified (`--diff-filter=ACMR`, so removing a guarded doc `main` still carries reads as cleanup, not a leak)                                          | fails, naming each leak                                                                                        |
| D: unguarded docs added to `origin/main` | every added `docs/` entry or markdown file is meant to ship (`--no-renames`, so a doc moved from one `main` carries lists as added rather than as a rename the filter would drop) | reports, never fails: each needs a reason to ship, or registering in the workflow's `extra_paths` and removing |

The worktree must be clean before it runs, because the overlay resets the index and working tree. Only exit 0 leads to
step 2:

| Exit | Meaning                                                                                    | Next                                                                                          |
| ---- | ------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------- |
| 0    | The branch is staged and every check passed; the script prints the commit steps.           | Step 2.                                                                                       |
| 1    | The drift gate, the changelog step, or a check failed.                                     | Never commit the branch. A drift failure stops before branching; any other recovers as below. |
| 2    | Setup error: a dirty worktree, an unknown ref, a missing tool, or no guarded-path pattern. | Fix what it names. Only the guarded-path error stops after branching; it recovers as below.   |

A cut that stopped after branching, at a failed check or at any failing step, leaves the overlay staged on the release
branch and prints the way back instead of the commit steps. Everything staged is the script's own output, because the
worktree was clean when it started, so discarding it loses nothing:

```bash
git checkout -f dev
git branch -D release/v<version>
```

Then fix the cause and re-run; the script refuses the dirty worktree a failed cut leaves behind.

The result is a single commit whose diff against `main` is the release, with `main` as an ancestor, so the PR merges
with zero conflicts. The merge publishes nothing by itself: the GitHub Release comes from the annotated tag
([§ Tagging and publishing](#tagging-and-publishing)), so merge and tag in one sitting and `main` never carries a
`VERSION` with no Release behind it. Auto-delete removes `release/v<version>` from the remote on merge. `dev` is
untouched.

The overlay is this repo's only release construction. Cherry-picking `dev`'s squash commits onto the `origin/main` base
is kept, in the `github-repo-setup` template, for a repo with a stated reason it cannot overlay; this repo has none.

→ Rationale (why overlay, not merge; why cut from `main`):
[`RELEASES-RATIONALE.md` § Branching model](./RELEASES-RATIONALE.md#branching-model). CHANGELOG mechanics:
[`RELEASES-RATIONALE.md` § CHANGELOG generation](./RELEASES-RATIONALE.md#changelog-generation).

## Tagging and publishing

After the `release/v<version> → main` PR merges, tag and push:

```bash
git checkout main && git pull
git tag -a -m "Release v<version>" v<version>
git push origin v<version>
```

Always use annotated tags (`-a -m`): a bare `git tag <name>` fails with `fatal: no tag message?` on machines where
`tag.gpgsign=true` is set globally.

The tag push triggers `.github/workflows/release.yml`. Its integrity gate fails the run unless the tag is `vX.Y.Z`, its
commit is reachable from `main`, and `VERSION` at that commit equals the tag's version. Its release job then creates the
GitHub Release, published and, as the highest version, latest, with notes cut from the `CHANGELOG.md` section that names
the tag's version, matched by version string and never by position. With no such section it falls back to generated
notes and says so in a `::warning::`. Once the run is green, run
[`scripts/release/postflight.sh all`](./RELEASES-POSTFLIGHT.md).

A failed run is retried against the existing tag, without cutting a new one:

```bash
gh workflow run release.yml -f tag=v<version>
```

The retry recreates nothing that exists: over an existing Release it replaces the notes from the tagged commit's
`CHANGELOG.md`, or leaves them when there is no section to replace them with. A section that lands on `main` after the
tag is applied by hand ([`RELEASES-POSTFLIGHT.md`](./RELEASES-POSTFLIGHT.md)).

→ Rationale: [`RELEASES-RATIONALE.md` § Release pipeline](./RELEASES-RATIONALE.md#release-pipeline).

### After publish: sync `dev` with the release

Once the GitHub Release is published, bring the release bookkeeping (`VERSION`, `CHANGELOG.md`) back to `dev` so the
integration branch starts from the released baseline:

```bash
scripts/sync-dev-after-release.sh v<version> --dry-run   # see what diverged
scripts/sync-dev-after-release.sh v<version>
```

The script verifies the tag is reachable from `origin/main` and the GitHub Release is not a draft, cuts a
`chore/sync-dev-after-v<version>` branch, writes the released number into `VERSION`, copies `CHANGELOG.md` from `main`,
adopts the paths discovery classes as release-prep, and opens a PR against `dev` with the version in its title.
`--dry-run` prints the contested paths and the paths it would sync, then creates no branch and leaves the tree clean. A
`dev` already in sync exits 0 with nothing committed.

Besides `VERSION` and `CHANGELOG.md`, the script **discovers** every other path `main` and `dev` disagree about, minus
the guarded set. A release branch gets edited for reasons no fixed list predicts, and those edits are made against
`main`'s base and never round-trip; without discovery they stay on `main` alone until the next release quietly reverts
them.

Each discovered path is classified against the **previous** release tag, the last point the branches agreed:

| Class          | Condition                                                   | Action                                          |
| -------------- | ----------------------------------------------------------- | ----------------------------------------------- |
| `release-prep` | `dev`'s copy is byte-identical to its copy at the prior tag | Adopted: `main`'s version is pure release-prep  |
| `contested`    | Both branches moved the path since the prior tag            | Reported, not adopted, unless you say otherwise |

The classification is what keeps a wider copy safe, since `dev` is normally ahead of `main` and adopting `main`'s
version of a file `dev` has moved on would revert unreleased work. `--include-contested` takes every contested path,
which is rarely right. Prefer `--only PATH` (repeatable) to name the ones you want; it intersects with the discovered
set, so a guarded, undiverged, or misspelled path is refused rather than forced through. Guarded paths never enter
discovery, so the sync cannot remove `dev`-only content.

After the commit, when the sync carried `CHANGELOG.md` and `git-cliff` is installed, the script re-runs
`scripts/generate-changelog.py --dry-run --tag v<version>` and, if that does not pass, warns with the generator's own
reason line (a PR body edited after the release, or a difference in line wrapping only). The warning does not block the
backport.

Merge the PR once CI is green; the postflight backport gate looks for its `chore(release): sync dev after <tag>` subject
on `dev`. Never merge `main` into `dev` or push to `dev` directly: the squash-merged histories share no recent ancestry,
so the merge conflicts on every file both sides touched, and a direct push bypasses `dev`'s required checks.

After it merges, confirm the branches actually converged. This is what catches a contested path nobody resolved:

```bash
git fetch origin
git diff --name-only origin/dev origin/main | grep -Ev "$(scripts/release/guarded-paths.sh)" || echo "(converged)"
```

→ Rationale: [`RELEASES-RATIONALE.md` § Release pipeline](./RELEASES-RATIONALE.md#release-pipeline).

## Rollback

A bad release is rolled back at the surface users consume first, then repaired in git. Rollback re-points what users
get; it does not revert history. `main` blocks force-pushes, so the surface here is the GitHub Release marker and the
head of `main`. Knowing the last-good tag before the release goes out is a
[`RELEASES-POSTFLIGHT.md`](./RELEASES-POSTFLIGHT.md) gate.

```bash
# 1. Re-point "Latest" at the last-good release so `gh release view` and the Releases page
#    stop advertising the bad one.
gh release edit v<last-good> --latest

# 2. Land the revert through the normal flow so consumers' next `xr skill update`
#    picks it up: a fix/* or revert PR into dev, then a release/* branch into main.
git checkout dev && git pull
git checkout -b fix/revert-v<version>
git revert <release-squash-sha>
```

After rolling back, `main` matches what is live again only once the revert release merges; until then the bad tree is
what a fresh `xr skill install` clones. Keep the window short.

→ Rationale: [`RELEASES-RATIONALE.md` § Rollback](./RELEASES-RATIONALE.md#rollback).

## Prose scrubbing

Three release-flow artifacts live outside any automated prose check and need a manual scrub before they ship:

- PR bodies (`gh pr create` / `gh pr edit` send body text directly to GitHub).
- `CHANGELOG.md` (a generated artifact built from upstream PR bodies).
- Release-PR bodies (composed after `CHANGELOG.md` has been generated).

The canonical Vale + LanguageTool rule packs live in the agentnative-spec repo at
`~/dev/agentnative-spec/docs/architecture/voice-enforcement.md`. Point Vale at the spec checkout via `--config`; the
spec is the source of truth, not vendored locally.

```bash
# 1. Save the artifact to /tmp/.
gh pr view <num> --json body --jq .body > /tmp/body.md         # for PR body edits
# cp CHANGELOG.md /tmp/body.md                                 # for changelog scrub

# 2. Vale (against the spec's rule packs).
vale --no-global --config ~/dev/agentnative-spec/.vale.ini --output=line --minAlertLevel=error /tmp/body.md

# 3. LanguageTool grammar check via lt_check (~/dotfiles/config/shell/languagetool.sh).
#    Skips cleanly if LanguageTool is unreachable. Inspect: `lt_rules`, `lt_info`.
lt_check /tmp/body.md

# 4. unslop (em-dash density and AI-unique structural patterns).
~/.claude/skills/unslop/scripts/score.py /tmp/body.md

# 5. Apply fixes per finding. Re-run until 0 blocking and unslop score is 0.

# 6. Apply the cleaned version.
gh pr edit <num> --body-file /tmp/body.md     # for PR body edits
```

For a `CHANGELOG.md` finding, fix the upstream PR body (which `generate-changelog.py` re-fetches every run) and
regenerate. Hand-editing `CHANGELOG.md` directly produces drift the next regeneration overwrites.

→ Rationale + which artifacts need this:
[`RELEASES-RATIONALE.md` § Prose scrubbing scope](./RELEASES-RATIONALE.md#prose-scrubbing-scope).

## Branch protection

Two rulesets are committed under `.github/rulesets/` and applied to the repo via the GitHub API:

- `protect-main.json`: required signatures, linear history, squash-only merges via PR with one approving review,
  required status checks (`markdownlint`, `shellcheck`, `scripts-tests`, `contract`,
  `guard-docs / check-forbidden-docs`, `guard-release / check-release-branch-name`,
  `guard-provenance / check-provenance`), creation/deletion blocked, non-fast-forward blocked.
- `protect-dev.json`: required signatures, deletion blocked, non-fast-forward blocked. No PR-requirement at the ruleset
  level; the PR-only norm is enforced by convention + `guard-release-branch` on the main side.

### Applying changes

```bash
# First apply (creating a ruleset):
gh api -X POST repos/<owner>/<repo>/rulesets --input .github/rulesets/protect-dev.json

# Subsequent updates (replace by ID; find it via `gh api repos/<owner>/<repo>/rulesets`):
gh api -X PUT repos/<owner>/<repo>/rulesets/<id> --input .github/rulesets/protect-main.json
```

→ Status-check context strings (inline vs reusable):
[`RELEASES-RATIONALE.md` § Status-check context strings](./RELEASES-RATIONALE.md#status-check-context-strings).

## Project specifics

- **Version carrier**: `VERSION` (plain text, no leading `v`), bumped in step 2 of the cut. It versions the bundle on
  its own line; the `xr` release the bundle documents is the AGENTS.md "Verified against" row, which the preflight smoke
  gate and CI's contract job read. `scripts/sync-dev-after-release.sh` writes `VERSION` back to `dev`.
- **Required secrets**: none. `release.yml` publishes with the workflow's own `GITHUB_TOKEN`; `generate-changelog.py`,
  the sync script, and the orchestrators use the local `gh` auth token.
- **Distribution channels**:

| Channel         | How it gets the release                                                                  |
| --------------- | ---------------------------------------------------------------------------------------- |
| `xr skill`      | `xr skill install <host>` clones the head of `main`; `xr skill update <host>` re-clones. |
| Manual clone    | `git clone https://github.com/brettdavies/xurl-rs-skill <skills dir>/xurl-rs`.           |
| GitHub Releases | `release.yml` publishes one Release per tag, notes from `CHANGELOG.md`, no assets.       |

- **Release scripts**: `scripts/release/_lib.sh`, `drift.sh`, `guarded-paths.sh`, `cut-release-branch.sh`, and
  `postflight.sh`, plus `scripts/generate-changelog.py`, `scripts/sync-dev-after-release.sh`, and
  `scripts/check-workflow-concurrency.sh`, are verbatim copies from the `github-repo-setup` skill; edits land upstream
  and propagate by re-copy. `scripts/release/preflight.sh`, `scripts/release/release.env`, and the hook trio under
  `scripts/hooks/` started from that skill's skeletons and carry this repo's own gates.
- **Rollback commands**: [§ Rollback](#rollback).

## Related docs

- [`RELEASES-PREFLIGHT.md`](./RELEASES-PREFLIGHT.md): pre-cut go/no-go checklist gating release-branch creation.
- [`RELEASES-POSTFLIGHT.md`](./RELEASES-POSTFLIGHT.md): post-tag verification of the publish pipeline.
- [`RELEASES-RATIONALE.md`](./RELEASES-RATIONALE.md), release-flow rationale: branching, PR body, pipeline, prose-check.
- [`.github/pull_request_template.md`](.github/pull_request_template.md): PR body structure with changelog sections.
- [`AGENTS.md`](AGENTS.md): producer-side workflow, repository shape, CI table, the bundle refresh loop.
- [`CONTRIBUTING.md`](CONTRIBUTING.md): contribution routing, house rules, and the git hooks.
