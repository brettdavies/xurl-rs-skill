#!/usr/bin/env bash
# tests/pinned-xr.sh: print the `xr` release tag this bundle is verified
# against, read from the "Verified against" table in AGENTS.md. That table is
# the one place the tag is written; the refresh loop and CI both read it here.
#
# Usage:
#     XR_BIN=$(bash tests/fetch-xr.sh "$(bash tests/pinned-xr.sh)")
#
# Exit codes: 0 the tag was printed, 2 the table names no tag.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# The backticks are literal: they quote the tag in the AGENTS.md table row.
# shellcheck disable=SC2016
TAG=$(sed -n 's/^| xurl-rs commit *| `[0-9a-f]*`, the `\(v[0-9.]*\)` tag.*/\1/p' "$ROOT/AGENTS.md")
if [ -z "$TAG" ]; then
  printf 'pinned-xr.sh: no tag in the AGENTS.md "Verified against" table\n' >&2
  exit 2
fi
printf '%s\n' "$TAG"
