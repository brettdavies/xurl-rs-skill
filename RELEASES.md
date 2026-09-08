# Releasing `xurl-rs-skill`

Operational runbook for shipping the skill bundle. Every change reaches `main` via this pipeline. Direct commits to
`dev` or `main` are not permitted: every change has a PR number in its squash commit message, which keeps the history
scannable, attributable, and changelog-ready.

```text
feature branch → PR to dev (squash merge)
              → release/* branch built as a clean descendant of main with dev's tree overlaid
              → PR to main (squash merge)
              → annotated tag + GitHub Release
```

Consumers install the bundle with `git clone --depth 1` of this repo and update with `git pull --ff-only`, so the
head of `main` is the shipped artifact. There is no build, registry, or deploy step.

## Branches

| Branch                                 | Role                                    | Lifetime                                    | Protection                           |
| -------------------------------------- | --------------------------------------- | ------------------------------------------- | ------------------------------------ |
| `main`                                 | Production. Only release commits.       | Forever.                                    | `.github/rulesets/protect-main.json` |
| `dev`                                  | Integration. All feature PRs land here. | Forever. Never delete.                      | `.github/rulesets/protect-dev.json`  |
| `feat/*`, `fix/*`, `chore/*`, `docs/*` | Feature work.                           | One PR's worth. Auto-deleted on merge.      | None. Squash into dev freely.        |
| `release/*`                            | Head of a dev → main PR.                | One release's worth. Auto-deleted on merge. | None.                                |

`dev` is a **forever branch**. Never delete it locally or remotely, even after a `release/* → main` merge. The next
release cycle reuses the same `dev`. The repo's `deleteBranchOnMerge: true` setting doesn't touch `dev` as long as `dev`
is never the head of a PR; using a short-lived `release/*` head is what keeps the setting compatible with a forever
integration branch, and `guard-release-branch.yml` rejects any other head on a PR to `main`.

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
- **PR body**: follow `.github/pull_request_template.md`. The `## Changelog` section is the source of truth for
  user-facing release notes; `scripts/generate-changelog.py` extracts these bullets verbatim.
- **Summary describes the net diff only**: what merged `main` looks like vs the base branch. Not commit history,
  intermediate state, or release mechanics.
- **Zero verification artifacts in the body.** No diff stats, leak-check output ("`guard-main-docs` runs clean"),
  pre-push gate results, CI status, or prose-scrub findings. Anomalies get fixed before push, not audit-trailed.

### Dev-direct exception

Paths that live only on `dev` and never ship to `main` can be committed directly to `dev` without a feature branch or
PR. The `guard-main-docs` workflow blocks them from `main` PRs regardless. The exception applies to engineering docs:
`docs/brainstorms/`, `docs/ideation/`, `docs/plans/`, `docs/research/`, `docs/reviews/`, `docs/solutions/`, and
anything under `.context/`.

The standard feature → PR → squash-merge flow remains required for everything else, including consumer-facing markdown
(`SKILL.md`, `references/`, `templates/`, `README.md`, `AGENTS.md`, `CONTRIBUTING.md`, this runbook).

## Releasing dev to main

Engineering docs live on `dev` only. `guard-main-docs.yml` blocks them from reaching `main`,
`guard-release-branch.yml` rejects any PR to main whose head isn't `release/*`, and `guard-main-provenance.yml`
requires every commit on the PR to carry a `(#N)` squash-merge reference.

**Branch naming**: `release/v<version>` or `release/v<version>-<slug>`. `generate-changelog.py` extracts the version
from the branch name, so the `v<version>` prefix is required.

`main` and `dev` share only an ancient merge-base: every release squash-merges into `main`, so the two branches diverge
in history even as their content converges. Reconciling that with a merge, or a branch cut from `dev`, produces
`add/add` and rename/delete conflicts that are artifacts of the lineage, not of the content shipping. The release
branch is therefore built as a **clean descendant of `main`** with `dev`'s tree overlaid on top, asserting the desired
end-state directly:

```bash
# 0. Nothing on main that dev never received (security PRs, hotfixes, config). Exits 1 while drift exists.
scripts/release/drift.sh

# 1. Branch from main, NOT dev.
git fetch origin
git checkout -B release/v<version> origin/main

# 2. Overlay dev's entire tracked tree onto the main base. `checkout -- .` writes dev's
#    paths but does not delete files that exist on main and are absent on dev, so remove
#    those next (the 'D' rows are main-only files dev deleted).
git checkout origin/dev -- .
git diff --name-status origin/main origin/dev | grep '^D'
trash <each main-only file listed above>

# 3. Strip the paths guard-main-docs forbids on main. The set resolves from the workflow;
#    never restate it inline, because every hand-kept copy drifted from what CI enforces.
GUARDED="$(scripts/release/guarded-paths.sh)"
git ls-files | grep -E "$GUARDED" | xargs -r trash
git add -A                                                      # stages adds, mods, AND deletions

# 4. Bump VERSION (plain text, no leading "v"), then build the changelog from the PRs
#    merged into dev since the previous release. The overlay commit carries no per-PR
#    history, so the section is built from dev's PRs, not from this branch's commits.
printf '%s\n' <version> > VERSION
scripts/generate-changelog.py --from-dev-prs
git add -A

# 5. Verify before committing.
#    A: staged tree equals dev's minus VERSION, CHANGELOG.md, and the stripped guarded paths.
#       Anything else printed here is a mistake.
git diff --cached --name-only origin/dev | grep -Ev "$GUARDED" \
  | grep -Ev '^(VERSION|CHANGELOG\.md)$' \
  && echo "unexpected delta above; investigate" || echo "(clean: only intended deltas)"
#    B: no guarded path in the release tree.
git diff --cached --name-only origin/main | grep -E "$GUARDED" \
  && echo "LEAKED a guarded path: reset and redo" || echo "(no guarded paths)"
#    D: what this release ADDS to main. The leak check screens against the registered
#       set, so it is blind to a category nobody registered yet. Every docs/ entry and
#       every added markdown file needs a reason to ship, or it needs registering in the
#       workflow's extra_paths and removing from the branch.
git diff --cached --diff-filter=A --name-only origin/main | grep -E '(^docs/|\.md$)' | grep -Ev "$GUARDED" || echo "(none unguarded)"

# 6. Commit the overlay as one commit sitting directly on top of main, then re-check that
#    main did not move while the branch was being built.
git commit
scripts/release/drift.sh

# 7. Push and open the PR. Scrub the body in /tmp/ first.
git push -u origin release/v<version>
gh pr create --base main --head release/v<version> --title "release: v<version>" --body-file /tmp/body.md
```

The result is a single commit whose diff against `main` is the release, with `main` as an ancestor, so the PR merges
with zero conflicts. Auto-delete removes `release/v<version>` from the remote on merge. `dev` is untouched.

### Why the release branch is cut from `main`, never from `dev`

Cutting the release branch from `dev` (or merging `dev` into `main`) forces a three-way merge across the squash-merge
divergence: `add/add` collisions on files both sides changed, plus rename/delete pairs git cannot auto-resolve. The
conflict pile is an artifact of the lineage, not of the content shipping. `main` ships `dev`'s tree minus a small,
known exclusion set, so asserting that end-state directly with the overlay is simpler and safer than hand-resolving a
merge. Cherry-picking the dev squash-commits onto `origin/main` is an exception kept for a repo with a stated reason it
cannot overlay; this repo has none.

Either way, the release must start from a `main` that `dev` fully contains. Security PRs, hotfixes, and config edits
land on `main` first, and the overlay takes `dev`'s content for every file, so anything `main` holds that `dev` never
received is reverted by the release. `scripts/release/drift.sh` lists that set and the cut waits until it is empty.

### Why the guarded set resolves from the workflow

`guard-main-docs` is what CI enforces on a PR to `main`: the reusable workflow's hardcoded base list plus this repo's
`extra_paths`. Every hand-kept copy of that union drifted from it, and a copy that omits a guarded path reports a real
leak as clean while CI turns red after the push. `scripts/release/guarded-paths.sh` reads `extra_paths` out of the
caller workflow and adds the base list, so registering a path in `.github/workflows/guard-main-docs.yml` is the only
edit a new guarded path needs. Entries are globs with one rule set shared by the reusable and the script (`**/` any
depth, `*` and `?` within a segment, trailing slash guards the subtree).

### Why the release enumerates what it adds

The leak check screens the diff against the registered set, so it says nothing about a category nobody registered.
Step D lists every `docs/` file and every markdown file the release adds to `main` outside the guarded set and puts
them in front of a human; each one needs a reason to ship, or it gets registered in `extra_paths` and dropped from the
branch. Root-level markdown is in scope because an agent-facing note at the repo root is exactly the kind of addition a
`docs/`-only listing misses.

## Tagging and publishing

After the `release/v<version> → main` PR merges, tag, push, and create the GitHub Release from the CHANGELOG section
for that version. Always use annotated tags (`-a -m`): a bare `git tag <name>` fails with `fatal: no tag message?` on
machines where `tag.gpgsign=true` is set globally.

```bash
git checkout main && git pull
git tag -a -m "Release v<version>" v<version>
git push origin main --tags

# Release notes: the CHANGELOG section for this version, selected by version string,
# never by position. Falls back to generated notes when no section matches.
awk -v v='<version>' '/^## \[/{p = index($0, "[" v "]") > 0} p' CHANGELOG.md > /tmp/notes.md
[[ -s /tmp/notes.md ]] \
  && gh release create v<version> --title "v<version>" --notes-file /tmp/notes.md \
  || gh release create v<version> --title "v<version>" --generate-notes
```

No workflow runs on the tag: the repo ships markdown and shell, and consumers pull `main` directly. The GitHub Release
is the published record of what each tag contains and is what `scripts/sync-dev-after-release.sh` checks before it
backports.

### After publish: sync `dev` with the release

Once the GitHub Release is published, bring the release bookkeeping (`VERSION`, `CHANGELOG.md`) back to `dev` so the
integration branch starts from the released baseline:

```bash
scripts/sync-dev-after-release.sh v<version>
```

The script verifies the tag is reachable from `origin/main` and the GitHub Release is not a draft, writes the released
number into `VERSION`, copies `CHANGELOG.md` verbatim from `origin/main`, cuts a `chore/sync-dev-after-v<version>`
branch off `dev`, and opens a PR against `dev`. Merge it once CI is green. Never merge `main` into `dev` or push to
`dev` directly: the squash-merged histories share no recent ancestry, so the merge conflicts on every file both sides
touched, and a direct push bypasses `dev`'s required checks.

The backport is idempotent: re-running on a `dev` already in sync with `main` exits 0 without creating a branch or PR.

## Rollback

A bad release is rolled back at the surface users consume first, then repaired in git. Rollback re-points what users
get; it does not revert history. `main` blocks force-pushes, so the surface here is the GitHub Release marker and the
head of `main`:

```bash
# 1. Re-point "Latest" at the last-good release so `gh release view` and the Releases page
#    stop advertising the bad one. Know the last-good tag before the release goes out.
gh release edit v<last-good> --latest

# 2. Land the revert through the normal flow so consumers' next `git pull --ff-only`
#    picks it up: a fix/* or revert PR into dev, then a release/* branch into main.
git checkout dev && git pull
git checkout -b fix/revert-v<version>
git revert <release-squash-sha>
```

After rolling back, `main` matches what is live again only once the revert release merges; until then the bad tree is
what a fresh `xr skill install` clones. Keep the window short.

## PRs and changelog generation

Every PR **must** follow `.github/pull_request_template.md`. The template has a `## Changelog` section with these
subsections:

- `### Added`: new user-visible features or capabilities
- `### Changed`: changes to existing behavior
- `### Fixed`: bug fixes
- `### Documentation`: documentation-only changes users would notice

`scripts/generate-changelog.py` (vendored from the `github-repo-setup` skill, with the repo-local `cliff.toml`) is the
only sanctioned way to update `CHANGELOG.md`. On the overlay-built release branch it runs as `--from-dev-prs`: the PRs
merged into `dev` since the previous release are the entries, and each PR's body supplies its `## Changelog`
subsections with author and PR-link attribution. If a PR's body carries no changelog content, its title becomes a
`Changed` bullet, except for `chore`, `ci`, `build`, `style`, and `test` PRs, which stay out unless they carry a
`## Changelog` of their own. To fix a wrong entry, fix the input: edit the squash-merged PR body on GitHub, then re-run
the script. Do **not** edit `CHANGELOG.md` directly.

`cliff.toml` skips `chore`, `style`, `test`, `ci`, and `build` commits regardless of body content, so prefer `feat` /
`fix` for anything user-observable.

## Branch protection

Two rulesets are committed under `.github/rulesets/` and applied to the repo via the GitHub API:

- `protect-main.json`: required signatures, linear history, squash-only merges via PR with one approving review,
  required status checks (`markdownlint`, `shellcheck`, `guard-docs / check-forbidden-docs`,
  `guard-release / check-release-branch-name`, `guard-provenance / check-provenance`), creation/deletion blocked,
  non-fast-forward blocked.
- `protect-dev.json`: required signatures, deletion blocked, non-fast-forward blocked. No PR-requirement at the ruleset
  level; the PR-only norm is enforced by convention + `guard-release-branch` on the main side.

### Applying changes

Edit the JSON locally, then sync to the remote:

```bash
# First apply (creating a ruleset):
gh api -X POST repos/<owner>/<repo>/rulesets --input .github/rulesets/protect-dev.json

# Subsequent updates (replace by ID; find it via `gh api repos/<owner>/<repo>/rulesets`):
gh api -X PUT repos/<owner>/<repo>/rulesets/<id> --input .github/rulesets/protect-main.json
```

Committing the JSON alongside code means ruleset changes land via the same review process as workflow changes: a
`chore(ci): tighten protect-main` change goes through dev → release/* → main like anything else.

### Status-check context pitfall

The `required_status_checks[].context` strings in `protect-main.json` must match exactly what GitHub publishes for each
check:

- **Inline job** (with `name:` field): published as just `<job-name>` (no workflow-name prefix).
- **Reusable-workflow caller** (`uses: .../foo.yml@ref`): published as `<caller-job-id> / <reusable-job-id-or-name>`.

Mixing these produces a stuck-but-green PR: all actual checks report green, but the ruleset waits forever on a context
that will never appear. Confirm the real contexts after a first CI run with:

```bash
gh api repos/<owner>/<repo>/commits/<sha>/check-runs --jq '.check_runs[].name'
```

## Project specifics

- **Version carrier**: `VERSION` (plain text, no leading `v`). `scripts/sync-dev-after-release.sh` writes it.
- **Distribution**: `git clone --depth 1` of this repo by `xr skill install <host>`; updates are `git pull --ff-only`
  in the install directory. No registry, no Homebrew, no binaries.
- **Release scripts**: `scripts/release/_lib.sh`, `drift.sh`, and `guarded-paths.sh`, plus
  `scripts/generate-changelog.py` and `scripts/sync-dev-after-release.sh`, are verbatim copies from the
  `github-repo-setup` skill. Edits land upstream and propagate by re-copy. The repo does not vendor a preflight or
  postflight skeleton because the runbook above needs only the drift gate.
- **Required secrets**: none. `generate-changelog.py` and the sync script use the local `gh` auth token.

## Related docs

- [`.github/pull_request_template.md`](.github/pull_request_template.md): PR body structure with changelog sections.
- [`AGENTS.md`](AGENTS.md): producer-side workflow, repository shape, CI table.
- [`CONTRIBUTING.md`](CONTRIBUTING.md): contribution routing and house rules.
