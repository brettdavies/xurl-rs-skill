#!/usr/bin/env bash
# tests/xr-sandbox.sh: run one ad-hoc `xr` probe under the contract
# harness's isolation. XURL_SKILL_HOME and XURL_TOKEN_STORE point into a
# scratch directory that is removed on exit; the host config-directory
# variables that outrank XURL_SKILL_HOME and the variables that change
# output, credentials, or endpoints are unset; and the API points at a
# closed port. A probe reads and writes nothing real and sends nothing to X.
#
# Usage:
#     XR_BIN=/abs/path/to/xr bash tests/xr-sandbox.sh media alt-text 1 "A dog" --dry-run --output json
#
# XR_SANDBOX_API overrides the API origin, such as a running
# tests/stub-api.py for a success path.

set -u

: "${XR_BIN:?set XR_BIN to the absolute path of the xr binary}"

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

unset CLAUDE_CONFIG_DIR KIRO_HOME OPENCODE_CONFIG_DIR \
  XURL_OUTPUT XURL_JSON XURL_JSONL XURL_RAW XURL_DRY_RUN XURL_APP XURL_LIMIT XURL_CURSOR XURL_BEARER_TOKEN \
  CLIENT_ID CLIENT_SECRET REDIRECT_URI AUTH_URL TOKEN_URL INFO_URL 2>/dev/null || true
mkdir -p "$SCRATCH/home"
export XURL_SKILL_HOME="$SCRATCH/home"
export XURL_TOKEN_STORE="$SCRATCH/store.yaml"
export API_BASE_URL="${XR_SANDBOX_API:-http://127.0.0.1:9}"
export NO_COLOR=1

"$XR_BIN" "$@"
