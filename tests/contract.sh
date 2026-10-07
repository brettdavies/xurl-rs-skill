#!/usr/bin/env bash
# tests/contract.sh: run the invocations this bundle documents against a
# real `xr` binary and assert the exit code, the stream, and the body: a
# field of a JSON document, the document's layout, or a substring of text.
# Every claim in SKILL.md, references/, and templates/ about what the binary
# emits has a row here; a refresh of the bundle starts by running this
# against the target build.
#
# Hermetic: XURL_SKILL_HOME and XURL_TOKEN_STORE point at a scratch
# directory, and the host config-directory variables that outrank
# XURL_SKILL_HOME in skill destinations are unset (XDG_CONFIG_HOME ranks
# below it and stays). The failure group talks to a closed port, and the
# success group talks to tests/stub-api.py (standard-library Python) whose
# request log the harness reads back. No live X API call is made and nothing
# under the real ~/.xurl or any skill host's directory is touched.
#
# Usage:
#     XR_BIN=/abs/path/to/xr bash tests/contract.sh
#
# XR_BIN is required; there is no PATH fallback, because a Homebrew install
# and a development build both answer to `xr`, and the bundle documents one
# specific build.
#
# Requires: bash, python3, jaq or jq

set -u

if [ -z "${XR_BIN:-}" ]; then
  printf 'contract.sh: set XR_BIN to the absolute path of the xr binary to verify.\n' >&2
  exit 2
fi
if [ ! -x "$XR_BIN" ]; then
  printf 'contract.sh: XR_BIN=%s is not executable.\n' "$XR_BIN" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  printf 'contract.sh: python3 is required for the stub API.\n' >&2
  exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PASSED=0
FAILED=0
ASSERTIONS=0

WORK=$(mktemp -d)
trap 'kill "${STUB_PID:-}" 2>/dev/null; rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home"
export XURL_SKILL_HOME="$WORK/home"
export NO_COLOR=1
unset XURL_OUTPUT XURL_JSON XURL_JSONL XURL_RAW XURL_DRY_RUN XURL_APP XURL_LIMIT XURL_CURSOR XURL_BEARER_TOKEN \
  CLAUDE_CONFIG_DIR KIRO_HOME OPENCODE_CONFIG_DIR 2>/dev/null || true

CLOSED_PORT=9
STUB_PORT=${STUB_PORT:-18099}
REQUEST_LOG="$WORK/requests.log"

# --- Scaffolding -----------------------------------------------------------

# shellcheck source=contract-lib.sh disable=SC1091
. "$ROOT/tests/contract-lib.sh"
if [ -z "$CONTRACT_JQ" ]; then
  printf 'contract.sh: jaq or jq is required to read JSON output.\n' >&2
  exit 2
fi

# --- Group 1: empty store, closed port (every failure path) ---------------

export XURL_TOKEN_STORE="$WORK/empty.yaml"
export API_BASE_URL="http://127.0.0.1:$CLOSED_PORT"
X=$XR_BIN
printf x >"$WORK/tiny.png"
cat >"$WORK/bearer.yaml" <<'EOF'
apps:
  demo:
    client_id: abcdefgh12345
    client_secret: shh
    bearer_token:
      type: bearer
      bearer: fakebearer
default_app: demo
EOF
cat >"$WORK/creds.yaml" <<'EOF'
apps:
  demo:
    client_id: abcdefgh12345
    client_secret: shh
default_app: demo
EOF

printf '\n# Group 1: empty store, closed port\n'
check "auth status: apps wrapper, empty; status ok" 0 \
  out.json .apps '[]' \
  out.json .status ok \
  -- "$X" auth status --output json
check "auth apps list: apps wrapper" 0 out.json .apps '[]' -- "$X" auth apps list --output json
check "whoami: 77 on stderr; register-app template; nothing on stdout" 77 \
  err.json .reason auth-required \
  err.json .next_step.action register-app \
  err.json .next_step.template '<secret-command> | xr auth apps add <name> --client-id <client-id> --client-secret-file -' \
  out.shape empty \
  -- "$X" whoami --output json
check "post --dry-run: dry_run envelope; would_succeed; no creds needed" 0 \
  out.json .status dry_run \
  out.json .would_succeed true \
  out.json .command post \
  -- "$X" post "hi" --dry-run --output json
check "post --dry-run: media_ids echoed" 0 out.json .media_ids '["1","2"]' -- "$X" post "hi" --media-id 1 --media-id 2 --dry-run --output json
check "reply --dry-run" 0 out.json .command reply -- "$X" reply 1585341984679469056 "hi" --dry-run --output json
check "quote --dry-run" 0 out.json .command quote -- "$X" quote 1585341984679469056 "hi" --dry-run --output json
check "block --dry-run; block --dry-run echoes the handle" 0 \
  out.json .command block \
  out.json .target_username @spammer \
  -- "$X" block @spammer --dry-run --output json
check "block --force: invalid-args" 2 err.json .reason invalid-args -- "$X" block @spammer --force --dry-run --output json
check "unblock --dry-run" 0 out.json .command unblock -- "$X" unblock @spammer --dry-run --output json
check "mute --dry-run" 0 out.json .command mute -- "$X" mute @noisy --dry-run --output json
check "unmute --dry-run" 0 out.json .command unmute -- "$X" unmute @noisy --dry-run --output json
check "follow --dry-run" 0 out.json .command follow -- "$X" follow @someone --dry-run --output json
check "dm --dry-run" 0 out.json .command dm -- "$X" dm @bob "hi" --dry-run --output json
check "like --dry-run" 0 out.json .status dry_run -- "$X" like 1585341984679469056 --dry-run --output json
check "delete --dry-run without --force: refused" 1 err.json .reason confirmation-required -- "$X" delete 123 --dry-run --output json
check "delete --force --dry-run: dry_run" 0 out.json .post_id 123 -- "$X" delete 123 --force --dry-run --output json
check "media upload --dry-run: no stat; defaults" 0 \
  out.json .would_succeed true \
  out.json .category amplify_video \
  -- "$X" media upload ./nope.png --dry-run --output json
check "media upload missing file: io exit 5" 5 err.json .reason io -- "$X" media upload ./nope.png --output json
check "blocked ignores --dry-run" 77 err.json .reason auth-required -- "$X" blocked --dry-run --output json
check "search --page: unsupported-pagination" 1 err.json .reason unsupported-pagination -- "$X" search x --page 2 --output json
check "--output toml: clap error, exit 2; no envelope; names the help to read" 2 \
  err "invalid value 'toml'" \
  err '!"reason"' \
  err "Try 'xr whoami --help'." \
  -- "$X" whoami --output toml
check "unknown flag: invalid-args envelope; invalid-args message: no error: prefix; invalid-args message: names the help to read" 2 \
  err.json .reason invalid-args \
  err.json '.message | startswith("unexpected argument")' true \
  err.json ".message | endswith(\"Try 'xr post --help'.\")" true \
  -- "$X" post hi --bogus --output json
check "missing positional: invalid-args envelope" 2 err.json .reason invalid-args -- "$X" post --output json
check "media upload --wait false: invalid-args" 2 err.json .reason invalid-args -- "$X" media upload ./x.png --wait false --output json
check "media upload --wait=false: accepted" 0 out.json .would_succeed true -- "$X" media upload ./nope.png --wait=false --dry-run --output json
check "media upload --wait=0: accepted" 0 out.json .would_succeed true -- "$X" media upload ./nope.png --wait=0 --dry-run --output json
check "media upload --wait=120: accepted" 0 out.json .would_succeed true -- "$X" media upload ./nope.png --wait=120 --dry-run --output json
check "media status --wait false: invalid-args" 2 err.json .reason invalid-args -- "$X" media status 1 --wait false --output json
check "media upload bearer-only: auth-method-mismatch" 2 err.json .available_in_app '["app"]' -- env XURL_TOKEN_STORE="$WORK/bearer.yaml" "$X" media upload "$WORK/tiny.png" --output json
check "unknown command: suggestion; show-help next_step; help of the nearest command" 2 \
  err.json .suggestion whoami \
  err.json .next_step.action show-help \
  err.json .next_step.command 'xr whoami --help' \
  -- "$X" whoam --output json
check "unknown subcommand: nearest in the family" 2 err.json .next_step.command 'xr auth status --help' -- "$X" auth statsu --output json
check "unknown subcommand, nothing close: family help" 2 err.json .next_step.command 'xr auth --help' -- "$X" auth zzzzzz --output json
check "unknown top-level word, nothing close: root help" 2 err.json .next_step.command 'xr --help' -- "$X" zzzzzzzz --output json
check "<typo> --help: unknown-command, exit 2" 2 err.json .reason unknown-command -- "$X" whoam --help --output json
check "<typo> -V: unknown-command, exit 2" 2 err.json .reason unknown-command -- "$X" whoam -V --output json
check "help --help: the help page, exit 0" 0 out 'Print this message or the help' -- "$X" help --help
check "schema --envelope: the eight actions; next_step and the retry keys declared" 0 \
  out.json '[.. | objects | .const? // empty] | index("show-help") != null' true \
  out.json '[.. | objects | .const? // empty] - ["ok", "dry_run", "error"] | unique | length' 8 \
  out.json '[.. | objects | .const? // empty] | (index("resume-wait") != null) and (index("wait-and-retry") != null)' true \
  out.json '[.. | objects | .properties? // empty | has("retry_after_secs") and has("retry_at") and has("media_id")] | any' true \
  out.json '[.oneOf[].properties | has("next_step")] | any' true \
  out.json '[.. | objects | .const? // empty] | index("enroll-app") != null' true \
  -- "$X" schema --envelope --output json
check "bare xr --output json: invalid-args" 2 err.json .reason invalid-args -- "$X" --output json
check "--auth app without bearer: 77; no next_step" 77 \
  err.json .reason auth-required \
  err.json 'has("next_step")' false \
  -- "$X" search x --auth app --output json
check "post --auth app: auth-method-mismatch; supported list" 2 \
  err.json .reason auth-method-mismatch \
  err.json '.supported | index("oauth2") != null' true \
  -- "$X" post x --auth app --output json
check "oauth2 step 1, no app: client-credentials-missing; register-app" 2 \
  err.json .reason client-credentials-missing \
  err.json .next_step.action register-app \
  -- "$X" auth oauth2 --no-browser --step 1 --output json
check "oauth2 step 1 --scopes: the subset plus offline.access" 0 \
  out.json '.auth_url | contains("scope=tweet.read+users.read+offline.access")' true \
  -- env XURL_TOKEN_STORE="$WORK/creds.yaml" "$X" auth oauth2 --no-browser --step 1 --scopes tweet.read,users.read --output json
check "oauth2 step 1 --scopes: unknown scope is validation" 1 \
  err.json .reason validation \
  err.json '.message | contains("Valid scopes:")' true \
  -- env XURL_TOKEN_STORE="$WORK/creds.yaml" "$X" auth oauth2 --no-browser --step 1 --scopes nope.read --output json
check "apps add --client-secret-file -: stdin; sign-in next" 0 \
  out.json .next_step.action sign-in \
  -- bash -c "printf 's3cret\n' | XURL_TOKEN_STORE='$WORK/secrets.yaml' '$X' auth apps add my-app --client-id abcdefgh12345 --client-secret-file - --output json"
check "apps add --client-secret-file -: the secret is stored without its newline" 0 out 'client_secret: s3cret' -- cat "$WORK/secrets.yaml"
printf 'rotated\n' >"$WORK/client-secret.txt"
check "apps update --client-secret-file PATH" 0 out.json .status ok -- env XURL_TOKEN_STORE="$WORK/secrets.yaml" "$X" auth apps update my-app --client-secret-file "$WORK/client-secret.txt" --output json
check "apps update --client-secret-file PATH: stored" 0 out 'client_secret: rotated' -- cat "$WORK/secrets.yaml"
check "--client-secret with --client-secret-file: invalid-args" 2 err.json .reason invalid-args -- env XURL_TOKEN_STORE="$WORK/secrets.yaml" "$X" auth apps add other --client-id x --client-secret y --client-secret-file "$WORK/client-secret.txt" --output json
check "--client-secret-file missing: io exit 5" 5 err.json .reason io -- env XURL_TOKEN_STORE="$WORK/secrets.yaml" "$X" auth apps add other --client-id x --client-secret-file "$WORK/absent.txt" --output json
check "auth app --bearer-token-file -: stdin" 0 out.json .status ok -- bash -c "printf 'filebearer\n' | XURL_TOKEN_STORE='$WORK/secrets.yaml' '$X' auth app --bearer-token-file - --output json"
check "auth app --bearer-token-file -: stored" 0 out 'bearer: filebearer' -- cat "$WORK/secrets.yaml"
printf 'cs\n' >"$WORK/consumer-secret.txt"
printf 'at\n' >"$WORK/access-token.txt"
check "auth oauth1 bare: invalid-args, no prompt" 2 err.json .reason invalid-args -- "$X" auth oauth1 --output json
check "auth oauth1: three secrets from files, one of them stdin" 0 \
  out.json '.message | contains("saved")' true \
  -- bash -c "printf 'ts\n' | XURL_TOKEN_STORE='$WORK/secrets.yaml' '$X' auth oauth1 --consumer-key ck --consumer-secret-file '$WORK/consumer-secret.txt' --access-token-file '$WORK/access-token.txt' --token-secret-file - --output json"
check "two -file flags on stdin: invalid-args" 2 \
  err.json .reason invalid-args \
  -- bash -c "printf 'x\n' | XURL_TOKEN_STORE='$WORK/secrets.yaml' '$X' auth oauth1 --consumer-key ck --consumer-secret-file - --access-token-file - --token-secret-file '$WORK/access-token.txt' --output json"
check "auth oauth1 from files: stored" 0 out 'token_secret: ts' out 'consumer_secret: cs' out 'access_token: at' -- cat "$WORK/secrets.yaml"
check "auth clear without selector: validation" 1 err.json .reason validation -- "$X" auth clear --output json
check "skill install no host: error on STDOUT; known_hosts" 2 \
  out.json .reason missing-host \
  out.json '.known_hosts | index("opencode") != null' true \
  -- "$X" skill install --output json
check "skill install --dry-run: command_preview" 0 out.json '.command_preview | startswith("git clone --depth 1 ")' true -- "$X" skill install claude_code --dry-run --output json
check "skill update --all --dry-run: installations; not-installed" 0 \
  out.json '.installations | length > 0' true \
  out.json '[.installations[].reason] | index("not-installed") != null' true \
  -- "$X" skill update --all --dry-run --output json
check "schema --list: message rows" 0 out.json 'select(.message | startswith("whoami ")) | has("message")' true -- "$X" schema --list --output json
check "schema validate: schema not available; reason validation" 1 \
  err.json '.message | startswith("schema not available")' true \
  err.json .reason validation \
  -- "$X" schema validate --output json
check "schema bogus: reason validation, not unknown-command; lists valid names" 1 \
  err.json .reason validation \
  err.json '.message | contains("broadcasts-moderators-list")' true \
  -- "$X" schema bogus --output json
check "schema broadcasts-moderators-add: moderator_user_ids" 0 out.json '[.. | objects | .properties? // empty | has("moderator_user_ids")] | any' true -- "$X" schema broadcasts-moderators-add --output json
check "schema dm: dm_event_id" 0 out.json '[.. | objects | .properties? // empty | has("dm_event_id")] | any' true -- "$X" schema dm --output json
check "schema block: positional" 0 out.json '[.. | objects | .properties? // empty | has("blocking")] | any' true -- "$X" schema block --output json
check "validate --schema block" 0 out.json .valid true -- bash -c "printf '%s' '{\"data\":{\"blocking\":true}}' | '$X' validate --schema block --output json"
check "validate unknown schema; validate unknown schema: known_schemas" 1 \
  err.json .reason unknown-schema \
  err.json '.known_schemas | index("post") != null' true \
  -- bash -c "printf '{}' | '$X' validate --schema tweet --output json"
check "validate --schema moderators: needs moderator_user_ids" 1 err.json '.message | contains("moderator_user_ids")' true -- bash -c "printf '%s' '{\"data\":[]}' | '$X' validate --schema moderators --output json"
check "validate missing file: io exit 1" 1 err.json .reason io -- "$X" validate ./nope.json --schema post --output json
check "version: xr <semver>" 0 out 'xr 4.' -- "$X" version
check "version --verbose: names xdk-rs" 0 out '(xdk-rs ' -- "$X" version --verbose
check "version --output json: version key; xdk_rs key; no status key" 0 \
  out.json '.version | startswith("4.")' true \
  out.json 'has("xdk_rs")' true \
  out.json 'has("status")' false \
  -- "$X" version --output json
check "version --output yaml" 0 out 'xdk_rs: ' -- "$X" version --output yaml
check "version envelope validation rejects it" 1 err.json .reason validation-failed -- bash -c "'$X' version --output json | '$X' validate --schema envelope --output json"
check "examples: muted list" 0 out 'xr muted -n 100 --output jsonl' -- "$X" examples
check "--help: env index and exit codes; env index and exit codes" 0 \
  out 'ENVIRONMENT VARIABLES:' \
  out 'EXIT CODES:' \
  -- "$X" --help
check "broadcasts moderators add --dry-run; broadcasts moderators add --dry-run echoes handle" 0 \
  out.json .command broadcasts-moderators-add \
  out.json .target_username @helper \
  -- "$X" broadcasts moderators add @helper --dry-run --output json
check "broadcasts moderators add --force: invalid-args" 2 err.json .reason invalid-args -- "$X" broadcasts moderators add @helper --force --dry-run --output json
check "broadcasts moderators remove --dry-run" 0 out.json .command broadcasts-moderators-remove -- "$X" broadcasts moderators remove @helper --dry-run --output json
check "broadcasts moderators list ignores --dry-run" 77 err.json .reason auth-required -- "$X" broadcasts moderators list --dry-run --output json
check "closed port: network-error exit 5" 5 err.json .reason network-error -- env XURL_TOKEN_STORE="$WORK/bearer.yaml" "$X" search x --auth app --output json
check "closed port: URL containing 429 is still network-error" 5 err.json .reason network-error -- env XURL_TOKEN_STORE="$WORK/bearer.yaml" "$X" /2/tweets/429 --auth app --output json
check "--auth oauth2 with creds, no token: 77; sign-in" 77 \
  err.json .reason auth-required \
  err.json .next_step.action sign-in \
  -- env XURL_TOKEN_STORE="$WORK/creds.yaml" "$X" --auth oauth2 whoami --output json
check "post --dry-run empty body: reason, exit 0" 0 out.json .reason empty-body -- "$X" post "" --dry-run --output json
check "post empty body live: validation exit 1" 1 err.json .message empty-body -- "$X" post "" --output json

LONG_ALT=$(printf 'a%.0s' $(seq 1001))
check "media alt-text --dry-run; media alt-text --dry-run: echoes text" 0 \
  out.json .command media-alt-text \
  out.json .text 'A dog' \
  -- "$X" media alt-text 1585341984679469056 "A dog" --dry-run --output json
check "media alt-text --dry-run: 1000 chars pass" 0 out.json .would_succeed true -- "$X" media alt-text 1 "${LONG_ALT:1}" --dry-run --output json
check "media alt-text --dry-run: 1001 chars refused, exit 0; refusal is would_succeed false" 0 \
  out.json .reason alt-text-too-long \
  out.json .would_succeed false \
  -- "$X" media alt-text 1 "$LONG_ALT" --dry-run --output json
check "media alt-text --dry-run: invalid-media-id" 0 out.json .reason invalid-media-id -- "$X" media alt-text abc "A dog" --dry-run --output json
check "media alt-text --dry-run: empty-alt-text" 0 out.json .reason empty-alt-text -- "$X" media alt-text 1 "  " --dry-run --output json
check "media alt-text live bad id: validation before auth" 1 err.json .message invalid-media-id -- "$X" media alt-text abc "A dog" --output json
check "media alt-text --force: invalid-args" 2 err.json .reason invalid-args -- "$X" media alt-text 1 "A dog" --force --dry-run --output json
check "media alt-text --auth app: auth-method-mismatch" 2 err.json .reason auth-method-mismatch -- "$X" media alt-text 1 "A dog" --auth app --output json
check "media alt-text no creds: 77" 77 err.json .reason auth-required -- "$X" media alt-text 1 "A dog" --output json
check "media subtitles add --dry-run" 0 out.json .command media-subtitles-add -- "$X" media subtitles add 1 2 --language en --name English --dry-run --output json
check "media subtitles add --dry-run: default category" 0 out.json .category amplify_video -- "$X" media subtitles add 1 2 --language en --dry-run --output json
check "media subtitles add --dry-run: invalid-language-code" 0 out.json .reason invalid-language-code -- "$X" media subtitles add 1 2 --language eng --dry-run --output json
check "media subtitles add --dry-run: subtitles id checked" 0 out.json .reason invalid-media-id -- "$X" media subtitles add 1 subs --language en --dry-run --output json
check "media subtitles add without --language: invalid-args" 2 err.json .reason invalid-args -- "$X" media subtitles add 1 2 --dry-run --output json
check "media subtitles add --category tweet_image: invalid-args" 2 err.json .reason invalid-args -- "$X" media subtitles add 1 2 --language en --category tweet_image --dry-run --output json
check "media subtitles remove --dry-run" 0 out.json .command media-subtitles-remove -- "$X" media subtitles remove 1 --language en --dry-run --output json
check "media subtitles remove --force: invalid-args" 2 err.json .reason invalid-args -- "$X" media subtitles remove 1 --language en --force --dry-run --output json
check "media upload --category subtitles --dry-run" 0 out.json .category subtitles -- "$X" media upload ./captions.srt --media-type text/srt --category subtitles --dry-run --output json
check "schema media-upload: schema not available" 1 err.json '.message | startswith("schema not available")' true -- "$X" schema media-upload --output json
check "schema skill-install: legacy_install_dir declared" 0 out.json '.properties | has("legacy_install_dir")' true -- "$X" schema skill-install --output json
check "validate --help: lists the schema names" 0 out 'alt-text' -- "$X" validate --help
check "validate auto-detects alt-text" 0 out.json .schema alt-text -- bash -c "printf '%s' '{\"data\":{\"id\":\"1\",\"associated_metadata\":{}}}' | '$X' validate --output json"
check "validate auto-detects subtitles" 0 out.json .schema subtitles -- bash -c "printf '%s' '{\"data\":{\"id\":\"1\",\"associated_subtitles\":{}}}' | '$X' validate --output json"
check "--raw on a subcommand usage error: compact" 2 \
  err.shape compact \
  err.json .exit_code 2 \
  -- "$X" post --output json --raw
check "XURL_RAW on a subcommand usage error: compact" 2 \
  err.shape compact \
  err.json .exit_code 2 \
  -- env XURL_RAW=true "$X" post --output json
check "XURL_JSON on a subcommand usage error: envelope" 2 err.json .reason unknown-command -- env XURL_JSON=true "$X" auth zzz

check "skill install: XURL_SKILL_HOME stands in for ~" 0 out.json .install_dir "$WORK/home/.claude/skills/xurl-rs" -- "$X" skill install claude_code --dry-run --output json
check "skill install codex: ~/.agents/skills; skill install codex, no old copy: no legacy_install_dir" 0 \
  out.json .install_dir "$WORK/home/.agents/skills/xurl-rs" \
  out.json 'has("legacy_install_dir")' false \
  -- "$X" skill install codex --dry-run --output json
check "skill install: CLAUDE_CONFIG_DIR wins over XURL_SKILL_HOME" 0 out.json .install_dir "$WORK/cc/skills/xurl-rs" -- env CLAUDE_CONFIG_DIR="$WORK/cc" "$X" skill install claude_code --dry-run --output json
check "skill install: KIRO_HOME" 0 out.json .install_dir "$WORK/kh/skills/xurl-rs" -- env KIRO_HOME="$WORK/kh" "$X" skill install kiro --dry-run --output json
check "skill install: OPENCODE_CONFIG_DIR" 0 out.json .install_dir "$WORK/oc/skills/xurl-rs" -- env OPENCODE_CONFIG_DIR="$WORK/oc" "$X" skill install opencode --dry-run --output json
xdg_config_home_rows() {
  check "skill install opencode: XURL_SKILL_HOME outranks XDG_CONFIG_HOME" 0 out.json .install_dir "$WORK/home/.config/opencode/skills/xurl-rs" -- env XDG_CONFIG_HOME="$WORK/xdg" "$X" skill install opencode --dry-run --output json
  check "skill install opencode: XDG_CONFIG_HOME without XURL_SKILL_HOME" 0 out.json .install_dir "$WORK/xdg/opencode/skills/xurl-rs" -- env -u XURL_SKILL_HOME XDG_CONFIG_HOME="$WORK/xdg" "$X" skill install opencode --dry-run --output json
}
xdg_config_home_rows
mkdir -p "$WORK/home/.codex/skills/xurl-rs"
check "skill install codex: legacy_install_dir names the old copy" 0 out.json .legacy_install_dir "$WORK/home/.codex/skills/xurl-rs" -- "$X" skill install codex --dry-run --output json
check "skill install codex text: the note names skill update" 0 out 'xr skill update codex' -- "$X" skill install codex --dry-run
check "skill update --all: an old codex copy counts as installed" 0 out.json '.installations[] | select(.host == "codex") | .status' dry_run -- "$X" skill update --all --dry-run --output json

# --- Group 2: staged user token, stub API (every success path) -----------

cat >"$WORK/user.yaml" <<'EOF'
apps:
  demo:
    client_id: abcdefgh12345
    client_secret: shh
    default_user: alice
    oauth2_tokens:
      alice:
        type: oauth2
        oauth2:
          access_token: fakeaccess
          refresh_token: fakerefresh
          expiration_time: 9999999999
    bearer_token:
      type: bearer
      bearer: fakebearer
default_app: demo
EOF
export XURL_TOKEN_STORE="$WORK/user.yaml"
export API_BASE_URL="http://127.0.0.1:$STUB_PORT"

PYTHONDONTWRITEBYTECODE=1 python3 -B "$ROOT/tests/stub-api.py" "$STUB_PORT" "$REQUEST_LOG" &
STUB_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  # `run`, in contract-lib.sh, sets _exit.
  # shellcheck disable=SC2154
  if run "$X" whoami --output json && [ "$_exit" = 0 ]; then break; fi
  sleep 0.3
done

printf '\n# Group 2: staged user token, stub API\n'
check "auth status: per-app fields; oauth2_users; bearer_source; no token values" 0 \
  out.json '.apps[0].client_id_hint' abcdefgh \
  out.json '.apps[0].oauth2_users' '["alice"]' \
  out.json '.apps[0].bearer_source' store \
  out.json '[.. | strings | select(contains("fakeaccess"))] | length' 0 \
  -- "$X" auth status --output json
check "whoami: the X API document; NO status key on success" 0 \
  out.json .data.username alice \
  out.json 'has("status")' false \
  -- "$X" whoami --output json
check "whoami --raw: compact" 0 \
  out.shape compact \
  out.json .data.id 42 \
  -- "$X" whoami --output json --raw
check "whoami text mode piped: JSON" 0 out.json .data.username alice -- "$X" whoami
check "search: data + meta, no status; search: no status key; search default page size 10; search does not resolve /2/users/me; typed search: sends post.fields" 0 \
  out.json .meta.next_token T2 \
  out.json 'has("status")' false \
  log 'max_results=10' \
  log '!/2/users/me' \
  log 'post.fields=' \
  -- "$X" search x --output json
check "search --output jsonl: whole document, pretty; NOT one record per line" 0 \
  out.json .meta.next_token T2 \
  out.shape pretty \
  -- "$X" search x --output jsonl
check "search --output ndjson: whole document, compact" 0 \
  out.shape compact \
  out.json '.data[0].id' 1 \
  -- "$X" search x --output ndjson
check "search --output json --raw: compact" 0 \
  out.shape compact \
  out.json '.data[0].id' 1 \
  -- "$X" search x --output json --raw
check "per-record lines come from jaq" 0 \
  out.shape compact \
  out.json .username u \
  -- bash -c "'$X' search x --output json | jaq -c '.data[]?' 2>/dev/null || '$X' search x --output json | jq -c '.data[]?'"
check "stream --output jsonl: one chunk per line" 0 \
  out.shape lines \
  out.json 'select(.data.id == "s2") | .data.text' two \
  -- "$X" /2/tweets/search/stream --auth app --output jsonl --timeout 5
check "stream --output json: no banners" 0 out.shape lines -- "$X" /2/tweets/search/stream --auth app --output json --timeout 5
check "search -n 3 floors at 10" 0 log 'max_results=10' -- "$X" search x -n 3 --output json
check "search -n 500 clamps to 100" 0 log 'max_results=100' -- "$X" search x -n 500 --output json
check "timeline -n 3 honored" 0 log 'max_results=3' -- "$X" timeline -n 3 --output json
check "timeline --limit 3" 0 log 'max_results=3' -- "$X" timeline --limit 3 --output json
check "-n wins over --limit" 0 log 'max_results=7' -- "$X" timeline --limit 3 -n 7 --output json
check "--limit 500 clamps to 100" 0 log 'max_results=100' -- "$X" following --limit 500 --output json
check "search --cursor threads pagination_token" 0 log 'pagination_token=abc' -- "$X" search x --cursor abc --output json
check "timeline --cursor" 0 log 'reverse_chronological?' -- "$X" timeline --cursor abc --output json
check "mentions --cursor" 0 log '/mentions?' -- "$X" mentions --cursor abc --output json
check "bookmarks --cursor" 0 log '/bookmarks?' -- "$X" bookmarks --cursor abc --output json
check "likes --cursor" 0 log '/liked_tweets?' -- "$X" likes --cursor abc --output json
check "following --cursor" 0 log '/following?' -- "$X" following --cursor abc --output json
check "followers --cursor" 0 log '/followers?' -- "$X" followers --cursor abc --output json
check "dms --cursor" 0 log '/2/dm_events?' -- "$X" dms --cursor abc --output json
check "blocked --cursor: /blocking + token" 0 log 'blocking?max_results=5&user.fields=created_at%2Cdescription%2Cpublic_metrics%2Cverified&pagination_token=abc' -- "$X" blocked --cursor abc -n 5 --output json
check "muted --after: /muting + token" 0 log 'pagination_token=abc' -- "$X" muted --after abc --output json
check "muted resolves /2/users/me first" 0 log '/2/users/me' -- "$X" muted --output json
check "user @handle: @ stripped in lookup" 0 log '/2/users/by/username/streamsoup_promo?' -- "$X" user @streamsoup_promo --output json
check "reply <url>: id extracted" 0 log '"in_reply_to_tweet_id":"1585341984679469056"' -- "$X" reply "https://x.com/u/status/1585341984679469056" "hi" --output json
check "quote <url>: id extracted" 0 log '"quote_tweet_id":"1585341984679469056"' -- "$X" quote "https://x.com/u/status/1585341984679469056" "hi" --output json
check "read <url>: id extracted" 0 log '/2/tweets/1585341984679469056?' -- "$X" read "https://x.com/u/status/1585341984679469056" --output json
check "post: 201 body; typed post: edit_history_post_ids; typed post: no legacy edit_history_tweet_ids" 0 \
  out.json .data.id 777 \
  out.json '.data.edit_history_post_ids' '["777"]' \
  out.json '.data | has("edit_history_tweet_ids")' false \
  -- "$X" post "hello" --output json
check "block: lookup then POST /blocking" 0 log '"path": "/2/users/42/blocking"' -- "$X" block @spammer --output json
check "unblock: DELETE /blocking/<target>" 0 log '/2/users/42/blocking/7' -- "$X" unblock spammer --output json
check "delete --force: DELETE /2/tweets/<id>" 0 log '"path": "/2/tweets/123"' -- "$X" delete 123 --force --output json
check "HTTP 429, no reset named: rate-limited exit 3; no next_step, no retry keys" 3 \
  err.json .reason rate-limited \
  err.json 'has("next_step")' false \
  err.json 'has("retry_after_secs")' false \
  err.json 'has("retry_at")' false \
  -- "$X" /2/ratelimit --output json
check "HTTP 429 naming its reset: retry keys; wait-and-retry with docs and no command" 3 \
  err.json .reason rate-limited \
  err.json '.retry_after_secs > 0 and .retry_after_secs <= 600' true \
  err.json '.retry_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' true \
  err.json .next_step.action wait-and-retry \
  err.json '.next_step.docs | startswith("https://")' true \
  err.json '.next_step | has("command")' false \
  -- "$X" /2/ratelimitreset --output json
check "HTTP 429 naming its reset, text: one retry line on stderr" 3 err 'Rate limited. Retry in ' -- "$X" /2/ratelimitreset
check "HTTP 429 whose reset has passed: retry_after_secs is 0" 3 err.json .retry_after_secs 0 -- "$X" /2/ratelimitpast --output json
check "--wait-on-rate-limit: waits out a near reset and retries once, silently" 0 \
  out.json .meta.result_count 1 \
  err.shape empty \
  -- "$X" --wait-on-rate-limit /2/ratelimitonce/flag --output json
check "--wait-on-rate-limit: the request went out twice" 0 out 2 -- bash -c "'$X' --wait-on-rate-limit /2/ratelimitonce/count --output json >/dev/null && grep -c ratelimitonce/count '$REQUEST_LOG'"
check "XURL_WAIT_ON_RATE_LIMIT=1: same" 0 out.json .meta.result_count 1 -- env XURL_WAIT_ON_RATE_LIMIT=1 "$X" /2/ratelimitonce/env --output json
check "--wait-on-rate-limit: a reset past --rate-limit-max-wait fails at once" 3 \
  err.json .next_step.action wait-and-retry \
  -- "$X" --wait-on-rate-limit /2/ratelimitreset --output json
check "--rate-limit-max-wait 0: no wait fits" 3 err.json .reason rate-limited -- "$X" --wait-on-rate-limit --rate-limit-max-wait 0 /2/ratelimitonce/nowait --output json
check "--wait-on-rate-limit: a 429 naming no reset fails at once" 3 err.json 'has("next_step")' false -- "$X" --wait-on-rate-limit /2/ratelimit --output json
check "media status: one read, processing state" 0 out.json .data.processing_info.state succeeded -- "$X" media status 123 --output json
check "media status: still processing reads as success" 0 out.json .data.processing_info.check_after_secs 1 -- "$X" media status 9001 --output json
check "media status --wait=1 past its deadline: processing-timeout; resume-wait for twice as long" 1 \
  err.json .reason processing-timeout \
  err.json .media_id 9001 \
  err.json .next_step.action resume-wait \
  err.json .next_step.command 'xr media status 9001 --wait=2' \
  -- "$X" media status 9001 --wait=1 --output json
check "processing-timeout, text: the resume command on stderr" 1 err 'Run: xr media status 9001 --wait=2' -- "$X" media status 9001 --wait=1
check "the resume-wait command runs as given, and doubles again" 1 \
  err.json .next_step.command 'xr media status 9001 --wait=4' \
  -- bash -c "cmd=\$('$X' media status 9001 --wait=1 --output json 2>&1 >/dev/null | '$CONTRACT_JQ' -r .next_step.command); '$X' \${cmd#xr } --output json"
check "media status --wait: a finished job returns it" 0 out.json .data.processing_info.state succeeded -- "$X" media status 123 --wait --output json
printf x >"$WORK/tiny.mp4"
printf x >"$WORK/tiny.gif"
check "media upload video: waits by default; one document with FINALIZE's fields and the final state" 0 \
  out.json .data.id m1 \
  out.json .data.expires_after_secs 3600 \
  out.json .data.processing_info.state succeeded \
  -- "$X" media upload "$WORK/tiny.mp4" --media-type video/mp4 --category tweet_video --output json
check "media upload --verbose: still one document under a structured format" 0 \
  out.json .data.processing_info.state succeeded \
  -- "$X" media upload "$WORK/tiny.mp4" --media-type video/mp4 --category tweet_video --output json --verbose
check "media upload video --wait=1 past its deadline: FINALIZE document on stdout; processing-timeout on stderr" 1 \
  out.json .data.id 9001 \
  err.json .reason processing-timeout \
  err.json .media_id 9001 \
  err.json .next_step.command 'xr media status 9001 --wait=2' \
  -- "$X" media upload "$WORK/tiny.mp4" --media-type video/mp4 --category dm_video --wait=1 --output json
check "media upload video --wait=false: one document, no status read" 0 \
  out '["9001",0]' \
  -- bash -c "id=\$('$X' media upload '$WORK/tiny.mp4' --media-type video/mp4 --category dm_video --wait=false --output json | '$CONTRACT_JQ' -r .data.id); printf '[\"%s\",%s]' \"\$id\" \"\$(grep -c STATUS '$REQUEST_LOG')\""
check "media upload video --wait=0: no status read" 0 \
  out 0 \
  -- bash -c "'$X' media upload '$WORK/tiny.mp4' --media-type video/mp4 --category dm_video --wait=0 --output json >/dev/null; grep -c STATUS '$REQUEST_LOG' || true"
check "media upload GIF X reports as ready: no status read" 0 \
  out 0 \
  -- bash -c "'$X' media upload '$WORK/tiny.gif' --media-type image/gif --category tweet_gif --output json >/dev/null; grep -c STATUS '$REQUEST_LOG' || true"
check "media upload GIF X reports as still processing: waited for; no state left once X reports none" 0 \
  out.json .data.id 9002 \
  out.json '.data | has("processing_info")' false \
  log 'command=STATUS&media_id=9002' \
  -- "$X" media upload "$WORK/tiny.gif" --media-type image/gif --category dm_gif --output json
check "media upload --wait=false on media still processing: FINALIZE's pending state, unread" 0 \
  out.json .data.processing_info.state pending \
  -- "$X" media upload "$WORK/tiny.gif" --media-type image/gif --category dm_gif --wait=false --output json
check "HTTP 404: not-found exit 4" 4 err.json .reason not-found -- "$X" /2/missing --output json
check "HTTP 401: auth-required exit 77; no next_step" 77 \
  err.json .reason auth-required \
  err.json 'has("next_step")' false \
  -- "$X" /2/unauthorized --output json
check "HTTP 403: forbidden exit 1; HTTP 403 bare: no next_step" 1 \
  err.json .reason forbidden \
  err.json 'has("next_step")' false \
  -- "$X" /2/forbidden --output json
check "HTTP 403 enrollment: forbidden; enroll-app next_step; docs URL" 1 \
  err.json .reason forbidden \
  err.json .next_step.action enroll-app \
  err.json '.next_step.docs | endswith("#x-platform-enrollment")' true \
  -- "$X" /2/notenrolled --output json
check "HTTP 400: invalid-request exit 1" 1 err.json .reason invalid-request -- "$X" /2/badrequest --output json
check "HTTP 422: invalid-request exit 1; HTTP refusal: problem document in message" 1 \
  err.json .reason invalid-request \
  err.json '.message | contains("Unprocessable Entity")' true \
  -- "$X" /2/unprocessable --output json
check "HTTP 500: server-error exit 1" 1 err.json .reason server-error -- "$X" /2/servererror --output json
check "HTTP 418: api-error exit 1" 1 err.json .reason api-error -- "$X" /2/teapot --output json
check "dm: send confirmation document; POST /2/dm_conversations/with/<id>/messages" 0 \
  out.json .data.dm_event_id e1 \
  log '/2/dm_conversations/with/7/messages' \
  -- "$X" dm @bob "hi" --output json
check "validate dm: send confirmation" 0 out.json .valid true -- bash -c "'$X' dm @bob hi --output json | '$X' validate --schema dm --output json"
check "broadcasts moderators list: GET path; no /2/users/me; user list, no status" 0 \
  log '"path": "/2/broadcasts/chat/moderators?' \
  log '!/2/users/me' \
  out.json 'has("status")' false \
  -- "$X" broadcasts moderators list --output json
check "broadcasts moderators list: --cursor not threaded" 0 log '!pagination_token' -- "$X" broadcasts moderators list --cursor abc --output json
check "broadcasts moderators list: --limit not threaded" 0 log '!max_results' -- "$X" broadcasts moderators list --limit 5 --output json
check "broadcasts moderators list: no -n flag" 2 err.json .reason invalid-args -- "$X" broadcasts moderators list -n 5 --output json
check "validate users: moderators list page" 0 out.json .valid true -- bash -c "'$X' broadcasts moderators list --output json | '$X' validate --schema users --output json"
check "broadcasts moderators add: lookup then POST; user_id body; moderator_user_ids" 0 \
  log '"path": "/2/broadcasts/chat/moderators"' \
  log '{"user_id":"7"}' \
  out.json .data.moderator_user_ids '["7"]' \
  -- "$X" broadcasts moderators add @helper --output json
check "broadcasts moderators remove: DELETE /<user_id>" 0 log '/2/broadcasts/chat/moderators/7' -- "$X" broadcasts moderators remove helper --output json
check "validate moderators: add response" 0 out.json .valid true -- bash -c "'$X' broadcasts moderators add @helper --output json | '$X' validate --schema moderators --output json"
check "raw GET: no status key" 0 out.json 'has("status")' false -- "$X" /2/users/me --output json
check "media upload: v2 initialize" 0 log '/2/media/upload/initialize' -- "$X" media upload "$WORK/tiny.png" --media-type image/png --category tweet_image --output json
check "media upload: category sent" 0 log '"media_category":"tweet_image"' -- bash -c "'$X' media upload '$WORK/tiny.png' --media-type image/png --category tweet_image --output json"
check "usage credits: /2/usage/credits" 1 log '/2/usage/credits' -- "$X" usage credits --output json
check "validate posts: search response" 0 out.json .valid true -- bash -c "'$X' search x --output json | '$X' validate --schema posts --output json"
check "validate user: whoami response" 0 out.json .valid true -- bash -c "'$X' whoami --output json | '$X' validate --schema user --output json"
check "validate envelope REJECTS a success" 1 err.json .reason validation-failed -- bash -c "'$X' search x --output json | '$X' validate --schema envelope --output json"
check "validate envelope accepts an error" 0 out.json .valid true -- bash -c "'$X' /2/missing --output json 2>&1 | '$X' validate --schema envelope --output json"
check "validate envelope accepts a dry_run" 0 out.json .valid true -- bash -c "'$X' post hi --dry-run --output json | '$X' validate --schema envelope --output json"
check "--verbose text: request line on stderr; no response body on stderr" 0 \
  err '> GET' \
  err '!"username"' \
  -- "$X" whoami --verbose
check "--verbose json: diagnostics suppressed" 0 err '!> GET' -- "$X" whoami --output json --verbose
check "typed read: retweet_count reads as repost_count; omitted counter prints 0; omitted optional field stays absent" 0 \
  out.json .data.public_metrics.repost_count 3 \
  out.json .data.public_metrics.like_count 0 \
  out.json '.data | has("created_at")' false \
  -- "$X" read 123 --output json
check "raw mode: legacy keys as sent; omitted counter stays absent" 0 \
  out.json '.data.edit_history_tweet_ids' '["777"]' \
  out.json '.data.public_metrics | has("like_count")' false \
  -- "$X" /2/tweets/123 --output json
check "raw mode: --cursor not threaded" 0 log '!pagination_token' -- "$X" '/2/tweets/search/recent?query=x' --cursor abc --output json
check "raw mode: --limit not threaded" 0 log '!max_results' -- "$X" '/2/tweets/search/recent?query=x' --limit 5 --output json
check "env bearer, empty store: auth status lists no app" 0 out.json .apps '[]' -- env XURL_TOKEN_STORE="$WORK/empty.yaml" XURL_BEARER_TOKEN=fakebearer "$X" auth status --output json
check "env bearer, empty store: search uses it" 0 out.json .meta.next_token T2 -- env XURL_TOKEN_STORE="$WORK/empty.yaml" XURL_BEARER_TOKEN=fakebearer "$X" search x --output json
check "--verbose text: legacy-vocabulary note" 0 err 'info: X sent edit_history_tweet_ids; read as edit_history_post_ids' -- "$X" read 123 --verbose
check "--verbose json: no vocabulary note" 0 err '!info: X sent' -- "$X" read 123 --verbose --output json
check "--verbose --quiet: no vocabulary note" 0 err '!info: X sent' -- "$X" read 123 --verbose --quiet
check "spec-marked stream: firehose streams without -s" 0 \
  out.shape lines \
  out.json 'select(.data.id == "s2") | .data.text' two \
  -- "$X" /2/likes/firehose/stream --auth app --output json --timeout 5
check "auth default <app> <user>: one document naming both" 0 \
  out.json .status ok \
  out.json .message 'Default app set to "demo" and default user to "alice"' \
  -- "$X" auth default demo alice --output json
check "auth default <app> <unknown user>: token-store; nothing on stdout" 77 \
  err.json .reason token-store \
  out.shape empty \
  -- "$X" auth default demo nobody --output json
check "auth default <unknown app> <user>: token-store" 77 err.json .reason token-store -- "$X" auth default nope alice --output json
check "media alt-text: POST /2/media/metadata; body nests metadata.alt_text.text; the API document; no status key" 0 \
  log '"path": "/2/media/metadata"' \
  log '{"id":"1585341984679469056","metadata":{"alt_text":{"text":"A dog"}}}' \
  out.json .data.associated_metadata.alt_text.text 'A dog' \
  out.json 'has("status")' false \
  -- "$X" media alt-text 1585341984679469056 "A dog" --output json
check "media alt-text live bad input: no request sent; message names the check" 1 \
  log '!/2/media/metadata' \
  err.json .message alt-text-too-long \
  -- "$X" media alt-text 1 "$LONG_ALT" --output json
check "validate alt-text: alt-text response" 0 out.json .valid true -- bash -c "'$X' media alt-text 1 'A dog' --output json | '$X' validate --schema alt-text --output json"
check "media subtitles add: POST /2/media/subtitles; language upper-cased, category wire name" 0 \
  log '"path": "/2/media/subtitles"' \
  log '{"id":"1","media_category":"AmplifyVideo","subtitles":{"id":"2","language_code":"EN","display_name":"English"}}' \
  -- "$X" media subtitles add 1 2 --language en --name English --output json
check "media subtitles add --category tweet_video: TweetVideo" 0 log '"media_category":"TweetVideo"' -- "$X" media subtitles add 1 2 --language en --category tweet_video --output json
check "media subtitles add: the API document" 0 out.json '.data.associated_subtitles.subtitles[0].language_code' EN -- "$X" media subtitles add 1 2 --language en --output json
check "validate subtitles: add response" 0 out.json .valid true -- bash -c "'$X' media subtitles add 1 2 --language en --output json | '$X' validate --schema subtitles --output json"
check "media subtitles remove: DELETE /2/media/subtitles; JSON body names the track; deleted document" 0 \
  log '{"method": "DELETE", "path": "/2/media/subtitles"}' \
  log '{"id":"1","media_category":"AmplifyVideo","language_code":"EN"}' \
  out.json .data.deleted true \
  -- "$X" media subtitles remove 1 --language en --output json
check "validate delete: subtitles remove response" 0 out.json .valid true -- bash -c "'$X' media subtitles remove 1 --language en --output json | '$X' validate --schema delete --output json"
check "raw DELETE -d: body sent" 0 log 'body: {"connection_ids":["1"]}' -- "$X" -X DELETE /2/connections -d '{"connection_ids":["1"]}' --output json

printf '\n# Group 3: bundled scripts against the real binary\n'
check "paginate.sh: streams statusless pages; follows next_token; cap message" 0 \
  out.shape lines \
  out.json .id $'1\n1' \
  log 'pagination_token=T2' \
  err 'stopped after 2 pages' \
  -- "$ROOT/scripts/paginate.sh" --max-pages 2 -- "$X" search x
check "paginate.sh: third page carries the advanced cursor" 0 log 'pagination_token=T3' -- "$ROOT/scripts/paginate.sh" --max-pages 3 -- "$X" search x
check "paginate.sh: blocked" 0 out.json .username u -- "$ROOT/scripts/paginate.sh" --max-pages 1 -- "$X" blocked -n 5
check "paginate.sh: 429 passes exit 3 through" 3 err 'reason=rate-limited (exit 3)' -- "$ROOT/scripts/paginate.sh" -- "$X" /2/ratelimit
check "dry-run-gate.sh: post goes live; dry_run envelope on stderr" 0 \
  out.json .data.id 777 \
  err '"status": "dry_run"' \
  -- "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" post "hello"
check "dry-run-gate.sh: read op refused" 2 err 'READ op' -- "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" whoami
check "dry-run-gate.sh: delete without --force" 1 err 'pass --force' -- "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" delete 123
check "dry-run-gate.sh: delete --force goes live" 0 log '"path": "/2/tweets/123"' -- "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" delete 123 --force
check "dry-run-gate.sh: block goes live" 0 log '"path": "/2/users/42/blocking"' -- "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" block @spammer
check "dry-run-gate.sh: moderators add goes live" 0 log '"path": "/2/broadcasts/chat/moderators"' -- "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" broadcasts moderators add @helper
check "dry-run-gate.sh: alt-text goes live" 0 log '"path": "/2/media/metadata"' -- "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" media alt-text 1 "A dog"
check "dry-run-gate.sh: subtitles remove goes live" 0 log '"path": "/2/media/subtitles"' -- "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" media subtitles remove 1 --language en
check "dry-run-gate.sh: dash-leading text after -- goes live" 0 log '{"id":"1","metadata":{"alt_text":{"text":"-5C on the dial"}}}' -- "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" media alt-text 1 -- "-5C on the dial"
check "media alt-text: dash-leading text needs --" 2 err.json .reason invalid-args -- "$X" media alt-text 1 "-5C on the dial" --dry-run --output json
check "dry-run-gate.sh: XURL_DRY_RUN set: refused before the preflight" 2 err 'XURL_DRY_RUN is set' -- env XURL_DRY_RUN=true "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" post "hello"
check "dry-run-gate.sh: XURL_JSON set: still goes live" 0 log '"path": "/2/tweets"' -- env XURL_JSON=true "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" post "hello"
check "paginate.sh: XURL_JSONL set: still streams" 0 out.json .id 1 -- env XURL_JSONL=true "$ROOT/scripts/paginate.sh" --max-pages 1 -- "$X" search x
check "XURL_JSON beside --output: invalid-args" 2 err.json '.message | contains("cannot be used with")' true -- env XURL_JSON=true "$X" whoami --output json
check "XURL_DRY_RUN: the live form answers a dry_run envelope" 0 out.json .status dry_run -- env XURL_DRY_RUN=true "$X" post "hello" --output json
check "dry-run-gate.sh: refused preflight names its reason" 1 err 'reason=alt-text-too-long' -- "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" media alt-text 1 "$LONG_ALT"
check "paginate.sh: moderators list stops on a repeated cursor; moderators list streams the page once before stopping" 1 \
  err 'answered the cursor it was fetched with' \
  out.shape lines \
  out.json .username $'u\nu' \
  -- "$ROOT/scripts/paginate.sh" --max-pages 5 -- "$X" broadcasts moderators list

printf '\n'
if [ "$FAILED" -gt 0 ]; then
  printf '%d checks passed, %d failed (%d assertions)\n' "$PASSED" "$FAILED" "$ASSERTIONS" >&2
  exit 1
fi
printf '%d checks passed (%d assertions)\n' "$PASSED" "$ASSERTIONS"
