#!/usr/bin/env bash
# Backport release artifacts from main to dev after a release tag publishes.
#
# Pulls two files from main and lands them as a single signed commit on dev:
#   - VERSION — overwritten with the released version (plain text, no leading "v").
#   - CHANGELOG.md — copied verbatim from origin/main. Main is fully
#     authoritative for CHANGELOG; dev never edits it directly.
#
# Run AFTER:
#   1. The release/v* -> main PR has merged.
#   2. `git tag -a vX.Y.Z` has been pushed to origin.
#   3. The GitHub Release has been created.
#
# Usage:
#   ./scripts/sync-dev-after-release.sh v0.2.0
#
# Idempotent: safe to re-run. If dev already matches main on these two
# files, the script exits 0 with no commit.
#
# Mirror of ~/dev/agentnative-cli/scripts/sync-dev-after-release.sh; this
# variant drops the Cargo.toml/Cargo.lock steps because the skill bundle
# is markdown-only (single plain-text VERSION file).

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 vX.Y.Z" >&2
    exit 64
fi

VERSION="$1"
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: version must match vMAJOR.MINOR.PATCH (got: $VERSION)" >&2
    exit 64
fi
VERSION_NO_V="${VERSION#v}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: working tree not clean -- commit or stash first" >&2
    git status --short >&2
    exit 65
fi

git fetch origin --tags --quiet

# Verify the release tag exists locally.
if ! git rev-parse --verify --quiet "refs/tags/$VERSION" >/dev/null; then
    echo "error: tag $VERSION not found locally -- run 'git fetch origin --tags' or verify the release published" >&2
    exit 66
fi

# Verify main is at or past the tag (i.e. release/* actually merged).
TAG_SHA="$(git rev-parse "$VERSION")"
if ! git merge-base --is-ancestor "$TAG_SHA" origin/main; then
    echo "error: tag $VERSION is not reachable from origin/main -- wait for release/v* to merge" >&2
    exit 66
fi

# Verify the GitHub Release exists and is not still a draft. The tag can exist
# (above check) while the GitHub Release was never created (or stayed draft),
# in which case consumers won't see the new version via `gh release` and the
# backport is premature.
if command -v gh >/dev/null 2>&1; then
    is_draft="$(gh release view "$VERSION" --json isDraft --jq .isDraft 2>/dev/null || true)"
    case "$is_draft" in
        false)
            ;;
        true)
            echo "error: GitHub Release $VERSION is still draft -- publish it first" >&2
            exit 67
            ;;
        "")
            echo "error: no GitHub Release for $VERSION -- create it with 'gh release create $VERSION'" >&2
            exit 67
            ;;
        *)
            echo "warning: unexpected isDraft value '$is_draft' for $VERSION -- proceeding" >&2
            ;;
    esac
else
    echo "warning: gh not on PATH -- skipping GitHub Release published-state check" >&2
fi

git switch dev
git pull --ff-only origin dev

# VERSION is plain text; overwrite with the released version (no leading "v").
printf '%s\n' "$VERSION_NO_V" > VERSION

# CHANGELOG.md from main (authoritative).
git checkout origin/main -- CHANGELOG.md

if git diff --quiet VERSION CHANGELOG.md; then
    echo "no changes -- dev already in sync with $VERSION"
    exit 0
fi

git add VERSION CHANGELOG.md
git commit -m "chore(release): backport $VERSION artifacts to dev

Brings dev's release-bookkeeping current with the $VERSION release on
main: VERSION bumped to ${VERSION_NO_V} and CHANGELOG.md copied verbatim
from origin/main."

# Post-sync sanity check: re-running generate-changelog.sh against the current
# PR bodies should produce an identical CHANGELOG.md. Drift here means upstream
# PR bodies were edited after main's CHANGELOG.md was generated -- the
# backport brought the stale CHANGELOG over, and a future release-branch
# regen will surface unexpected diffs. Warn, do not fail; the backport is
# still correct against what main currently has.
if [[ -x scripts/generate-changelog.sh ]] && command -v git-cliff >/dev/null 2>&1; then
    if scripts/generate-changelog.sh --dry-run --tag "$VERSION" >/dev/null 2>&1; then
        echo "regen check: CHANGELOG.md matches what PR bodies would produce"
    else
        echo "warning: PR bodies have drifted from main's CHANGELOG.md for $VERSION" >&2
        echo "  re-run 'scripts/generate-changelog.sh --dry-run --tag $VERSION' to see the diff" >&2
        echo "  fix by regenerating CHANGELOG.md on a follow-up release branch" >&2
    fi
fi

echo "committed; push with: git push origin dev"
