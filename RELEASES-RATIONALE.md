<!-- Canonical version: 2026.11.03 (generic) -->
# Releases rationale

Companion to [`RELEASES.md`](./RELEASES.md). RELEASES.md is the runbook (commands, paths, decision tables). This file
holds the WHY behind those rules: branching model, PR conventions, release pipeline, CHANGELOG generation, prose-check
pipeline, branch-protection pitfalls.

Read this when:

- A rule in RELEASES.md doesn't make sense and you're tempted to change it.
- A new contributor asks "why do we do X this way".
- You're adding a new release-flow rule and need to know where it fits the existing model.

## Branching model

### Forever `dev`, ephemeral release branches

`dev` is never deleted, even after a release. The next release cycle reuses the same `dev`. The repo's
`deleteBranchOnMerge: true` setting doesn't touch `dev` as long as `dev` is never the head of a PR. Using a short-lived
`release/*` head is what keeps the setting compatible with a forever integration branch.

Engineering docs (`docs/plans/`, `docs/solutions/`, `docs/brainstorms/`, `docs/reviews/`) live on `dev` only. They never
reach `main`. `guard-main-docs.yml` blocks them from PRs targeting `main`, and `guard-release-branch.yml` rejects any PR
to main whose head isn't `release/*`.

### Why the release branch is cut from `main`, never from `dev`

Every release squash-merges into `main`, so `dev` and `main` diverge in history even as their content converges: after
the first release they share only an ancient merge-base. Cutting the release branch from `dev` (or merging `dev` into
`main`) forces a 3-way merge across that divergence: `add/add` collisions on files both sides changed, plus
rename/delete pairs git cannot auto-resolve. The conflict pile is an artifact of the lineage, not of the content
shipping.

Always cut the release branch from `origin/main` and bring `dev`'s content onto it as a forward diff, never by
reconciling histories. This repo uses the whole-tree overlay (`dev`'s tree asserted onto the base with
`git read-tree -u --reset`, then the guarded set stripped): `main` ships `dev`'s tree minus a small, known exclusion
set, so asserting that end-state directly is simpler and safer than hand-resolving a merge. The overlay commit carries
no per-PR history, so the changelog is built from the PRs merged into `dev` since the previous release
(`generate-changelog.py --from-dev-prs`) rather than from the branch's commits.

The release must start from a `main` that `dev` fully contains. Security PRs, hotfixes, and config edits land on `main`
first, and the overlay takes `dev`'s content for every file, so anything `main` holds that `dev` never received is
reverted by the release. `scripts/release/drift.sh` lists that set and the cut waits until it is empty.

### Why a script builds the release branch

The overlay and its checks are where a hand-typed command goes wrong quietly. `git checkout origin/dev -- .` writes
`dev`'s paths but leaves every file `main` carries and `dev` deleted, so those have to be read off a diff and removed,
and that diff and the added-docs listing both need `--no-renames`: with rename detection on, a deleted file pairs with
any similar addition, reports as `R`, and drops out of a filter on `D` or `A`. `scripts/release/cut-release-branch.sh`
asserts the tree with `git read-tree -u --reset`, which carries the deletions with no diff to read, and runs its checks
as code the `github-repo-setup` bats suite covers. The version bump stays with the operator, because which files carry a
version is project-specific; here it is `VERSION` alone.

### Version branch naming

Branch naming `release/v<version>` or `release/v<version>-<slug>` makes release branches sortable and unambiguous when
multiple cuts are in flight. `generate-changelog.py` extracts the version from the branch name, so the `v<version>`
prefix is required. Slug is kebab-case, short, descriptive.

## PR body conventions

### No explainer prose in the body

Every section of a PR body is user-facing substance only: the **net diff**, what is changing for the consumer that was
not already there, not the commit history or intermediate state that produced it. Workflow mechanics (overlay,
regenerate, pre-push gate, CI behavior) are documented in RELEASES.md and `.github/`, NOT in the PR body. Leak-check
narration, pre-push gate results, CI check status, exclusion rationale, and other verification artifacts stay local;
anomalies get fixed before push, not audit-trailed in the body.

The PR body is read by humans reviewing what shipped. Workflow mechanics and tool-fix provenance are noise from that
perspective; they belong in this file, the script outputs, and the commit history respectively.

### Why `feat`/`fix` are preferred over `chore`

`cliff.toml` drops commits whose subject starts with `chore`, `style`, `test`, `ci`, or `build` regardless of body
content. Mistyping a user-facing change as `chore` silently strips it from release notes. Prefer `feat` / `fix` when the
change has any user-observable effect (a documented invocation, a consumer script's behavior, a reference's guidance).

Security advisory bumps in particular use `fix(deps):`, never `chore(deps):`, so they appear in the changelog. A bumped
dependency that closes a CVE is user-visible value, not internal tooling.

### Why required-when-empty sub-headers

`Related Issues/Stories` has four labels (`Story:` / `Issue:` / `Architecture:` / `Related PRs:`). `Files Modified` has
four sub-headers (`Modified` / `Created` / `Renamed` / `Deleted`). All four must appear in every PR, even when empty:
write `- None.` or `n/a` rather than deleting the label. Reason: scanners and humans both rely on a known section shape.
Conditionally-absent sections force every reader to mentally check "did the author skip this or does it not apply?"

### Why no AI attribution

`Co-Authored-By: Claude ...`, robot emoji / "Generated with Claude Code" trailers, or any similar AI-attribution trailer
is banned from commit messages and PR bodies. Commits and PRs stand on their own technical content. Attribution trailers
are noise and they age poorly as tools shift.

### Why no hard line wraps

Author each paragraph and each bullet as one logical line, however long. GitHub soft-wraps for display. Hard wraps
within prose produce visible mid-sentence breaks in some renderers and interfere with the prose-check pipeline: Vale's
line-anchored output reports findings against split lines, and LanguageTool's input handling can choke on certain
control-char interactions.

### Why release-PR bodies repeat changelog entries from upstream PRs

The release PR carries the same changelog bullets as the feature PRs it ships. The repetition is intentional and
harmless: the release PR merges into `main`, so `--from-dev-prs`, which reads `dev`'s history, never sees it, and
`cliff.toml` skips the `release:` squash commit, so it is never counted twice.

### Why internal-tooling commits don't appear in `## Changelog`

`chore(cliff): ...`, `chore(ci): ...`, and similar internal-tooling commits don't appear in the PR body's
`## Changelog`. They are not user-facing. They belong in commit history and in the Files Modified section of the PR
body, not in the source-of-truth release notes.

## Release-branch verification

`cut-release-branch.sh` screens the staged release tree twice before the commit (A: release→dev for paths outside the
guarded set and the version carriers, B: no guarded path added or modified in release→main) and enumerates what the
release adds (D). `preflight.sh mechanics` repeats the leak check, the enumeration, and a diff-B against `origin/dev` on
the committed branch, because the commit is a second chance to stage something the cut did not.

A and diff-B exclude only the guarded set, not all of `docs/`: a directory under `docs/` that ships to `main` would
otherwise hide a missed change there.

### Why the guarded set resolves from the workflow

`guard-main-docs` is what CI enforces on a PR to `main`: the reusable workflow's hardcoded base list plus this repo's
`extra_paths`. Every hand-kept copy of that union (runbook, checklist, preflight script) drifted from it, and a copy
that omits a guarded path reports a real leak as clean while CI turns red after the push.
`scripts/release/guarded-paths.sh` reads `extra_paths` out of the caller workflow and adds the base list, so registering
a path in the workflow is the only edit a new guarded path needs. The base list is the one copy that still needs a
manual edit when the reusable changes, because it lives in another repo. Entries are globs with one rule set shared by
the reusable and the script (`**/` any depth, `*` and `?` within a segment, trailing slash guards the subtree), so
`**/.agent/` guards that directory wherever it appears and the two never disagree about what is guarded.

### Why the release enumerates what it adds

The leak check screens the diff against the registered set, so it says nothing about a category nobody registered. A new
engineering directory or a stray note under `docs/` passes the local check and `guard-main-docs` alike. Check D lists
every `docs/` file and every markdown file the release adds to `main` outside the guarded set and puts them in front of
a human; each one needs a reason to ship, or it gets registered in `extra_paths` and dropped from the branch. Root-level
markdown is in scope because an agent-facing note at the repo root is exactly the kind of addition a `docs/`-only
listing misses, and every consumer's clone carries it.

## Preflight smoke against released `xr`

The bundle has no binary of its own; what it ships is a description of another binary's contract. CI's `contract` job
runs the harness against the release the AGENTS.md "Verified against" table pins, which keeps every PR honest about that
release and says nothing about any later one. Consumers pair the bundle with whatever `xr` they installed, and the
bundle tells them a newer `4.x` keeps everything it documents. The preflight smoke gate is where that claim meets the
newest release: it runs the same harness against it before the bundle ships again. A failure there is a bundle pass
waiting to happen, or an upstream regression to report, and either way the release should not go out claiming a contract
the current `xr` breaks.

The negative control is there because every other check in the gate is a "did it work" assertion. `dry-run-gate.sh` is
the bundle's safety rail for writes, and a gate that stopped running its preflight would still pass a harness of success
rows. The control drives it with a write whose preflight fails and requires the gate's own refusal line, since `xr`'s
live call refuses the same input with the same exit code.

## CHANGELOG generation

### Generated, never hand-written

`scripts/generate-changelog.py` (vendored from the `github-repo-setup` skill, with the repo-local `cliff.toml`) is the
only sanctioned way to update `CHANGELOG.md`. On the overlay-built release branch it runs as `--from-dev-prs`: the PRs
merged into `dev` since the previous release are the entries, and each PR's body supplies its `## Changelog` subsections
under the six headings of [`RELEASES.md` § Versioning](./RELEASES.md#versioning) (`Breaking changes`, `Added`,
`Changed`, `Deprecated`, `Fixed`, `Documentation`), with author and PR-link attribution. A heading outside the six still
renders, after them.

If a PR's body offers no changelog section at all, its title becomes a bullet under the group `cliff.toml` gives the
same commit (`type!:` under Breaking changes, `feat` under Added, `fix` under Fixed, `docs` under Documentation,
anything else under Changed), except for `chore`, `ci`, `build`, `style`, and `test` PRs, which stay out unless they
carry a `## Changelog` of their own, and the `release:` PR, which is bookkeeping. A body that carries the `## Changelog`
heading and leaves it empty is the PR template's way of saying the PR ships nothing user-facing, and the fallback
respects that whatever the title: internal work also lands as `fix(ci)`, `fix(hooks)`, or `fix(release)`, which the skip
list does not cover. `preflight.sh changelog-sections` names every PR whose entry would fall back to its title. To fix a
wrong CHANGELOG entry, fix the input: edit the squash-merged PR body, then re-run the script. Do **not** edit
`CHANGELOG.md` directly.

`preflight.sh mechanics` checks that the release changelog opens on the release version with no `[Unreleased]`
placeholder. `release.yml` cuts the GitHub Release body from the section whose heading names the tag's version, and
falls back to generated notes, with a warning, when there is none.

### Why the changelog sections set the version

A SemVer release's bump comes from the headings its PRs filed, not from commit markers or a judgment made at the cut:
the author of a change knows best whether it adds, fixes, or breaks a contract surface, and the heading records that
answer where review sees it. `generate-changelog.py --bump` reads the same sections the release notes are built from, so
the version and the notes cannot disagree. A `!:` commit stays a cross-check: a PR can break the contract with no
marker, and a marker can sit on a change outside the contract. The rules, the pre-1.0 shift, the MSRV rule, and the
small-break exception are in [`RELEASES.md` § Versioning](./RELEASES.md#versioning).

### Why `cliff.toml` skips chore/style/test/ci/build

These commit types do not produce user-facing content, so the generator emits no bullet for one on the strength of its
subject alone. Under `--from-dev-prs` it enumerates merged PRs and reads each body directly, so a body with
`## Changelog` content is extracted whatever the title says: a `test:` or `chore:` PR carrying real bullets still lands
in the section. The skip list applies only to the no-body fallback, where the title would otherwise become a bullet on
its own. The check worth making is therefore narrow: a PR with an *empty* `## Changelog` and a skipped type that
nonetheless shipped something user-facing. The fix is to the input, never to `CHANGELOG.md`.

## Release pipeline

### Annotated tags

Always use annotated tags (`-a -m`). Bare `git tag <name>` silently fails with `fatal: no tag message?` on machines
where `tag.gpgsign=true` is set globally (a brettdavies dotfile default). See
[solutions: git tag fails with tag.gpgsign, use annotated tags](https://github.com/brettdavies/solutions-docs/blob/main/best-practices/git-tag-fails-with-tag-gpgsign-use-annotated-tags-2026-04-13.md).

### Why the GitHub Release is `release.yml`'s output

The release event is the tag push on `main`, and the GitHub Release is what the pipeline produces from it, never a
trigger for anything. `release.yml` checks the tag first (`vX.Y.Z`, reachable from `main`, equal to `VERSION` at that
commit), so a Release can only ever name a tag that was cut through the flow, and a mistyped or out-of-sequence tag
fails before anything is published.

The notes come from the `CHANGELOG.md` section whose heading names the tag's version, matched by version string.
Positional extraction (the first `## [` section in the file) ships another version's notes the moment an
`## [Unreleased]` heading sits at the top or a tag is cut out of sequence, with the run reporting success throughout.

The bundle has nothing to attach after the Release exists (no archives, no Homebrew formula, no registry), so the
Release is created published in one step. The draft-then-finalize split that brettdavies Rust CLIs run exists to keep
`/releases/latest` off a version Homebrew cannot install yet, and has no work to do here.

### Why backport `main` → `dev` after publish

Once the GitHub Release is published, the release-bookkeeping files on `main` (`VERSION`, `CHANGELOG.md`) need to reach
`dev` so the next dev work starts from the released baseline, and so the next release's drift gate 0 finds them there.

The backport is a PR opened by `scripts/sync-dev-after-release.sh`, never a merge of `main` into `dev` and never a
direct push. The squash-merged branches share no recent history, so a merge conflicts on every file both sides touched,
and a direct push to `dev` bypasses its required status checks. The postflight backport gate treats that merged PR as
the durable signal that the backport ran. Guarded paths never enter the copy, so the backport cannot remove `dev`-only
content.

The other paths are discovered rather than listed. A release branch is edited for reasons nobody predicts (a doc fix, a
reverted payload, a deleted config), each such edit is made against `main`'s base, and a fixed list misses it silently
until the next release's overlay restores `dev`'s copy over it. Discovery is bounded by the previous release tag, the
last point the branches agreed: a path `dev` left alone since then is release-prep and adopted, and a path `dev` also
changed is contested and withheld unless the operator names it, so widening the copy cannot revert `dev`'s unreleased
work.

### Rollback

Rollback happens at the surface users consume, not in git. Here that is the GitHub Release marker and the head of
`main`, which every `xr skill install` clones. Re-pointing `/releases/latest` is fast and reversible; rewriting `main`
is neither, and the release flow exists so that `main` only ever moves forward through a PR. After the rollback, the fix
or revert lands through `dev`, a release branch, and `main` like any other change, so the branch reconverges with what
is live. Recording the last-good tag before the release is what makes the rollback a single command under incident
pressure.

## Prose scrubbing scope

Three release-flow artifacts live outside any automated prose check and need a manual scrub before they ship:

- **PR bodies.** `gh pr create` and `gh pr edit` send body text directly to GitHub; no automated prose check has reach
  there.
- **`CHANGELOG.md`.** A generated artifact built from upstream PR bodies; it inherits whatever prose those PR bodies
  carry, so scrubbing happens at generation time on the release branch.
- **Release-PR bodies.** The `release/v<version>` PR to `main` carries contributor-authored wrap-up text composed after
  `CHANGELOG.md` has been generated, and the same out-of-repo gap applies.

The canonical Vale + LanguageTool rule packs and orchestrator behavior live in the agentnative-spec repo. This repo does
not vendor a local copy of those packs; point Vale at the spec checkout via `--config`.

Scrub-before-submit (author in `/tmp/`, scrub there, submit via `--body-file`) avoids the round-trip of "submit, scrub,
edit, scrub again". Every fix lands locally and the public PR sees only clean text.

For a `CHANGELOG.md` finding, fix the upstream PR body (which `generate-changelog.py` re-fetches every run) and
regenerate. Hand-editing `CHANGELOG.md` directly produces drift the next regeneration overwrites.

## Branch protection

### Status-check context strings

The `required_status_checks[].context` strings in `protect-main.json` MUST match exactly what GitHub publishes for each
check:

- **Inline job** (with `name:` field): published as just `<job-name>` (no workflow-name prefix).
- **Reusable-workflow caller** (`uses: .../foo.yml@ref`): published as `<caller-job-id> / <reusable-job-id-or-name>`.

Mixing these produces a stuck-but-green PR: all actual checks report green, but the ruleset waits forever on a context
that will never appear. Confirm the real contexts after a first CI run with:

```bash
gh api repos/<owner>/<repo>/commits/<sha>/check-runs --jq '.check_runs[].name'
```

### Why rulesets live in-repo

Committing the JSON alongside code means ruleset changes land via the same review process as workflow changes. A
`chore(ci): tighten protect-main` change goes through dev → release/* → main like anything else.

## Related docs

- [`RELEASES.md`](./RELEASES.md): operational runbook (commands, paths, decision tables).
- [`RELEASES-PREFLIGHT.md`](./RELEASES-PREFLIGHT.md): pre-cut checklist gating the release-branch cut.
- [`RELEASES-POSTFLIGHT.md`](./RELEASES-POSTFLIGHT.md): post-tag verification of the publish pipeline.
- [`.github/pull_request_template.md`](.github/pull_request_template.md): PR body structure with changelog sections.
