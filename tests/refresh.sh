#!/usr/bin/env bash
# tests/refresh.sh: the bundle-pass loop in one command. Fetches the target
# release's binary (tests/fetch-xr.sh), prints the surface it adds or removes
# since the base tag (tests/surface-diff.sh), runs the contract harness, the
# fixture tests, the core-env guard, shellcheck, and markdownlint with CI's
# globs, and ends with one line per step.
#
# Usage:
#     bash tests/refresh.sh v4.3.0           # base: the tag in AGENTS.md's "Verified against" table
#     bash tests/refresh.sh v4.3.0 v4.2.0    # explicit base
#
# Exit codes: 0 every step passed or was skipped, 1 a step failed, 2 usage.
# A step whose tool is not on PATH is reported as skipped.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 2
NEW=${1:-}
if [ -z "$NEW" ]; then
  printf 'usage: refresh.sh <release tag> [<base tag>]\n' >&2
  exit 2
fi
# The backticks are literal: they quote the tag in the AGENTS.md table row.
# shellcheck disable=SC2016
OLD=${2:-$(sed -n 's/^| xurl-rs commit *| `[0-9a-f]*`, the `\(v[0-9.]*\)` tag.*/\1/p' "$ROOT/AGENTS.md")}
if [ -z "$OLD" ]; then
  printf 'refresh.sh: no tag in the AGENTS.md "Verified against" table; pass the base tag as the second argument\n' >&2
  exit 2
fi

RESULTS=()
FAILED=0

record() {
  if [ "$2" = 0 ]; then
    RESULTS+=("PASS  $1")
  else
    RESULTS+=("FAIL  $1")
    FAILED=1
  fi
}

# Runs a step and prints its output without the per-check PASS lines.
step() {
  local name=$1
  shift
  printf '\n## %s\n' "$name"
  "$@" 2>&1 | grep -v '^PASS '
  record "$name" "${PIPESTATUS[0]}"
}

XR_BIN=$(bash "$ROOT/tests/fetch-xr.sh" "$NEW") || {
  printf 'refresh.sh: could not fetch the %s release asset\n' "$NEW" >&2
  exit 1
}
export XR_BIN
printf 'xr under test: %s (%s)\n' "$("$XR_BIN" --version)" "$XR_BIN"

step "surface diff $OLD..$NEW" bash "$ROOT/tests/surface-diff.sh" "$OLD" "$NEW"
step "contract harness" bash "$ROOT/tests/contract.sh"
step "fixture tests" bash "$ROOT/tests/run.sh"
step "core-env guard" bash tests/core-env-guard.sh
if command -v shellcheck >/dev/null 2>&1; then
  step "shellcheck" shellcheck --severity=style scripts/*.sh tests/*.sh fixtures/bin/xr
else
  RESULTS+=("SKIP  shellcheck (not on PATH)")
fi
if command -v markdownlint-cli2 >/dev/null 2>&1; then
  step "markdownlint" markdownlint-cli2 '**/*.md' '#node_modules'
else
  RESULTS+=("SKIP  markdownlint (markdownlint-cli2 not on PATH)")
fi

printf '\n## Summary\n'
printf '%s\n' "${RESULTS[@]}"
exit "$FAILED"
