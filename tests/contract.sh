#!/usr/bin/env bash
# tests/contract.sh: run the invocations this bundle documents against a
# real `xr` binary and assert the exit code, the stream, and a substring of
# the body. Every claim in SKILL.md, references/, and templates/ about what
# the binary emits has a row here; a refresh of the bundle starts by running
# this against the target build.
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

_stdout=""
_stderr=""
_exit=0

run() {
  local stderr_file="$WORK/stderr"
  _stdout=$("$@" 2>"$stderr_file" </dev/null) && _exit=0 || _exit=$?
  _stderr=$(cat "$stderr_file")
}

# check LABEL EXPECTED_EXIT STREAM NEEDLE [STREAM NEEDLE]... -- cmd...
#   Runs cmd once and asserts its exit code and every STREAM/NEEDLE pair.
#   STREAM is out, err, or log (the stub request log). NEEDLE is a fixed
#   string that must appear there; prefix it with '!' to require absence.
check() {
  local label=$1 want_exit=$2
  shift 2
  local pairs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    pairs+=("$1" "$2")
    shift 2
  done
  shift
  : >"$REQUEST_LOG"
  run "$@"
  local ok=1 i stream needle hay
  if [ "$_exit" != "$want_exit" ]; then
    printf '    expected exit %s, got %s\n' "$want_exit" "$_exit" >&2
    ok=0
  fi
  for ((i = 0; i < ${#pairs[@]}; i += 2)); do
    stream=${pairs[i]}
    needle=${pairs[i + 1]}
    ASSERTIONS=$((ASSERTIONS + 1))
    case "$stream" in
      out) hay=$_stdout ;;
      err) hay=$_stderr ;;
      log) hay=$(cat "$REQUEST_LOG" 2>/dev/null) ;;
    esac
    if [ "${needle#!}" != "$needle" ]; then
      if grep -qF -- "${needle#!}" <<<"$hay"; then
        printf '    %s unexpectedly contains: %s\n' "$stream" "${needle#!}" >&2
        ok=0
      fi
    elif ! grep -qF -- "$needle" <<<"$hay"; then
      printf '    %s missing: %s\n' "$stream" "$needle" >&2
      ok=0
    fi
  done
  if [ "$ok" = 1 ]; then
    PASSED=$((PASSED + 1))
    printf 'PASS %s\n' "$label"
  else
    FAILED=$((FAILED + 1))
    printf 'FAIL %s\n' "$label"
    printf '    stdout: %s\n' "$(head -c 300 <<<"$_stdout" | tr '\n' ' ')" >&2
    printf '    stderr: %s\n' "$(head -c 300 <<<"$_stderr" | tr '\n' ' ')" >&2
  fi
}

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
  out '"apps": []' \
  out '"status": "ok"' \
  -- "$X" auth status --output json
check "auth apps list: apps wrapper" 0 out '"apps": []' -- "$X" auth apps list --output json
check "whoami: 77 on stderr; register-app template; nothing on stdout" 77 \
  err '"reason": "auth-required"' \
  err '"action": "register-app"' \
  out '!"status"' \
  -- "$X" whoami --output json
check "post --dry-run: dry_run envelope; would_succeed; no creds needed" 0 \
  out '"status": "dry_run"' \
  out '"would_succeed": true' \
  out '"command": "post"' \
  -- "$X" post "hi" --dry-run --output json
check "post --dry-run: media_ids echoed" 0 out '"2"' -- "$X" post "hi" --media-id 1 --media-id 2 --dry-run --output json
check "reply --dry-run" 0 out '"command": "reply"' -- "$X" reply 1585341984679469056 "hi" --dry-run --output json
check "quote --dry-run" 0 out '"command": "quote"' -- "$X" quote 1585341984679469056 "hi" --dry-run --output json
check "block --dry-run; block --dry-run echoes the handle" 0 \
  out '"command": "block"' \
  out '"target_username": "@spammer"' \
  -- "$X" block @spammer --dry-run --output json
check "block --force: invalid-args" 2 err '"reason": "invalid-args"' -- "$X" block @spammer --force --dry-run --output json
check "unblock --dry-run" 0 out '"command": "unblock"' -- "$X" unblock @spammer --dry-run --output json
check "mute --dry-run" 0 out '"command": "mute"' -- "$X" mute @noisy --dry-run --output json
check "unmute --dry-run" 0 out '"command": "unmute"' -- "$X" unmute @noisy --dry-run --output json
check "follow --dry-run" 0 out '"command": "follow"' -- "$X" follow @someone --dry-run --output json
check "dm --dry-run" 0 out '"command": "dm"' -- "$X" dm @bob "hi" --dry-run --output json
check "like --dry-run" 0 out '"status": "dry_run"' -- "$X" like 1585341984679469056 --dry-run --output json
check "delete --dry-run without --force: refused" 1 err '"reason": "confirmation-required"' -- "$X" delete 123 --dry-run --output json
check "delete --force --dry-run: dry_run" 0 out '"post_id": "123"' -- "$X" delete 123 --force --dry-run --output json
check "media upload --dry-run: no stat; defaults" 0 \
  out '"would_succeed": true' \
  out '"category": "amplify_video"' \
  -- "$X" media upload ./nope.png --dry-run --output json
check "media upload missing file: io exit 5" 5 err '"reason": "io"' -- "$X" media upload ./nope.png --output json
check "blocked ignores --dry-run" 77 err '"reason": "auth-required"' -- "$X" blocked --dry-run --output json
check "search --page: unsupported-pagination" 1 err '"reason": "unsupported-pagination"' -- "$X" search x --page 2 --output json
check "--output toml: clap error, exit 2; no envelope; names the help to read" 2 \
  err "invalid value 'toml'" \
  err '!"reason"' \
  err "Try 'xr whoami --help'." \
  -- "$X" whoami --output toml
check "unknown flag: invalid-args envelope; invalid-args message: no error: prefix; invalid-args message: names the help to read" 2 \
  err '"reason": "invalid-args"' \
  err '"message": "unexpected argument' \
  err "Try 'xr post --help'." \
  -- "$X" post hi --bogus --output json
check "missing positional: invalid-args envelope" 2 err '"reason": "invalid-args"' -- "$X" post --output json
check "media upload --wait false: invalid-args" 2 err '"reason": "invalid-args"' -- "$X" media upload ./x.png --wait false --output json
check "media upload bearer-only: auth-method-mismatch" 2 err '"available_in_app"' -- env XURL_TOKEN_STORE="$WORK/bearer.yaml" "$X" media upload "$WORK/tiny.png" --output json
check "unknown command: suggestion; show-help next_step; help of the nearest command" 2 \
  err '"suggestion": "whoami"' \
  err '"action": "show-help"' \
  err '"command": "xr whoami --help"' \
  -- "$X" whoam --output json
check "unknown subcommand: nearest in the family" 2 err '"command": "xr auth status --help"' -- "$X" auth statsu --output json
check "unknown subcommand, nothing close: family help" 2 err '"command": "xr auth --help"' -- "$X" auth zzzzzz --output json
check "unknown top-level word, nothing close: root help" 2 err '"command": "xr --help"' -- "$X" zzzzzzzz --output json
check "<typo> --help: unknown-command, exit 2" 2 err '"reason": "unknown-command"' -- "$X" whoam --help --output json
check "<typo> -V: unknown-command, exit 2" 2 err '"reason": "unknown-command"' -- "$X" whoam -V --output json
check "help --help: the help page, exit 0" 0 out 'Print this message or the help' -- "$X" help --help
check "schema --envelope: show-help declared; next_step declared; enroll-app" 0 \
  out 'show-help' \
  out 'next_step' \
  out 'enroll-app' \
  -- "$X" schema --envelope --output json
check "bare xr --output json: invalid-args" 2 err '"reason": "invalid-args"' -- "$X" --output json
check "--auth app without bearer: 77; no next_step" 77 \
  err '"reason": "auth-required"' \
  err '!next_step' \
  -- "$X" search x --auth app --output json
check "post --auth app: auth-method-mismatch; supported list" 2 \
  err '"reason": "auth-method-mismatch"' \
  err '"oauth2"' \
  -- "$X" post x --auth app --output json
check "oauth2 step 1, no app: client-credentials-missing; register-app" 2 \
  err '"reason": "client-credentials-missing"' \
  err '"action": "register-app"' \
  -- "$X" auth oauth2 --no-browser --step 1 --output json
check "auth clear without selector: validation" 1 err '"reason": "validation"' -- "$X" auth clear --output json
check "skill install no host: error on STDOUT; known_hosts" 2 \
  out '"reason": "missing-host"' \
  out '"opencode"' \
  -- "$X" skill install --output json
check "skill install --dry-run: command_preview" 0 out 'git clone --depth 1' -- "$X" skill install claude_code --dry-run --output json
check "skill update --all --dry-run: installations; not-installed" 0 \
  out '"installations"' \
  out '"not-installed"' \
  -- "$X" skill update --all --dry-run --output json
check "schema --list: message rows" 0 out '"message"' -- "$X" schema --list --output json
check "schema validate: schema not available; reason validation" 1 \
  err 'schema not available' \
  err '"reason": "validation"' \
  -- "$X" schema validate --output json
check "schema bogus: reason validation, not unknown-command; lists valid names" 1 \
  err '!unknown-command' \
  err 'broadcasts-moderators-list' \
  -- "$X" schema bogus --output json
check "schema broadcasts-moderators-add: moderator_user_ids" 0 out 'moderator_user_ids' -- "$X" schema broadcasts-moderators-add --output json
check "schema dm: dm_event_id" 0 out 'dm_event_id' -- "$X" schema dm --output json
check "schema block: positional" 0 out 'blocking' -- "$X" schema block --output json
check "validate --schema block" 0 out '"valid": true' -- bash -c "printf '%s' '{\"data\":{\"blocking\":true}}' | '$X' validate --schema block --output json"
check "validate unknown schema; validate unknown schema: known_schemas" 1 \
  err '"reason": "unknown-schema"' \
  err '"known_schemas"' \
  -- bash -c "printf '{}' | '$X' validate --schema tweet --output json"
check "validate --schema moderators: needs moderator_user_ids" 1 err 'moderator_user_ids' -- bash -c "printf '%s' '{\"data\":[]}' | '$X' validate --schema moderators --output json"
check "validate missing file: io exit 1" 1 err '"reason": "io"' -- "$X" validate ./nope.json --schema post --output json
check "version: xr <semver>" 0 out 'xr 4.' -- "$X" version
check "version --verbose: names xdk-rs" 0 out '(xdk-rs ' -- "$X" version --verbose
check "version --output json: version key; xdk_rs key; no status key" 0 \
  out '"version": "4.' \
  out '"xdk_rs"' \
  out '!"status"' \
  -- "$X" version --output json
check "version --output yaml" 0 out 'xdk_rs: ' -- "$X" version --output yaml
check "version envelope validation rejects it" 1 err '"reason": "validation-failed"' -- bash -c "'$X' version --output json | '$X' validate --schema envelope --output json"
check "examples: muted list" 0 out 'xr muted -n 100 --output jsonl' -- "$X" examples
check "--help: env index and exit codes; env index and exit codes" 0 \
  out 'ENVIRONMENT VARIABLES:' \
  out 'EXIT CODES:' \
  -- "$X" --help
check "broadcasts moderators add --dry-run; broadcasts moderators add --dry-run echoes handle" 0 \
  out '"command": "broadcasts-moderators-add"' \
  out '"target_username": "@helper"' \
  -- "$X" broadcasts moderators add @helper --dry-run --output json
check "broadcasts moderators add --force: invalid-args" 2 err '"reason": "invalid-args"' -- "$X" broadcasts moderators add @helper --force --dry-run --output json
check "broadcasts moderators remove --dry-run" 0 out '"command": "broadcasts-moderators-remove"' -- "$X" broadcasts moderators remove @helper --dry-run --output json
check "broadcasts moderators list ignores --dry-run" 77 err '"reason": "auth-required"' -- "$X" broadcasts moderators list --dry-run --output json
check "closed port: network-error exit 5" 5 err '"reason": "network-error"' -- env XURL_TOKEN_STORE="$WORK/bearer.yaml" "$X" search x --auth app --output json
check "closed port: URL containing 429 is still network-error" 5 err '"reason": "network-error"' -- env XURL_TOKEN_STORE="$WORK/bearer.yaml" "$X" /2/tweets/429 --auth app --output json
check "--auth oauth2 with creds, no token: 77; sign-in" 77 \
  err '"reason": "auth-required"' \
  err '"action": "sign-in"' \
  -- env XURL_TOKEN_STORE="$WORK/creds.yaml" "$X" --auth oauth2 whoami --output json
check "post --dry-run empty body: reason, exit 0" 0 out '"reason": "empty-body"' -- "$X" post "" --dry-run --output json
check "post empty body live: validation exit 1" 1 err '"message": "empty-body"' -- "$X" post "" --output json

LONG_ALT=$(printf 'a%.0s' $(seq 1001))
check "media alt-text --dry-run; media alt-text --dry-run: echoes text" 0 \
  out '"command": "media-alt-text"' \
  out '"text": "A dog"' \
  -- "$X" media alt-text 1585341984679469056 "A dog" --dry-run --output json
check "media alt-text --dry-run: 1000 chars pass" 0 out '"would_succeed": true' -- "$X" media alt-text 1 "${LONG_ALT:1}" --dry-run --output json
check "media alt-text --dry-run: 1001 chars refused, exit 0; refusal is would_succeed false" 0 \
  out '"reason": "alt-text-too-long"' \
  out '"would_succeed": false' \
  -- "$X" media alt-text 1 "$LONG_ALT" --dry-run --output json
check "media alt-text --dry-run: invalid-media-id" 0 out '"reason": "invalid-media-id"' -- "$X" media alt-text abc "A dog" --dry-run --output json
check "media alt-text --dry-run: empty-alt-text" 0 out '"reason": "empty-alt-text"' -- "$X" media alt-text 1 "  " --dry-run --output json
check "media alt-text live bad id: validation before auth" 1 err '"message": "invalid-media-id"' -- "$X" media alt-text abc "A dog" --output json
check "media alt-text --force: invalid-args" 2 err '"reason": "invalid-args"' -- "$X" media alt-text 1 "A dog" --force --dry-run --output json
check "media alt-text --auth app: auth-method-mismatch" 2 err '"reason": "auth-method-mismatch"' -- "$X" media alt-text 1 "A dog" --auth app --output json
check "media alt-text no creds: 77" 77 err '"reason": "auth-required"' -- "$X" media alt-text 1 "A dog" --output json
check "media subtitles add --dry-run" 0 out '"command": "media-subtitles-add"' -- "$X" media subtitles add 1 2 --language en --name English --dry-run --output json
check "media subtitles add --dry-run: default category" 0 out '"category": "amplify_video"' -- "$X" media subtitles add 1 2 --language en --dry-run --output json
check "media subtitles add --dry-run: invalid-language-code" 0 out '"reason": "invalid-language-code"' -- "$X" media subtitles add 1 2 --language eng --dry-run --output json
check "media subtitles add --dry-run: subtitles id checked" 0 out '"reason": "invalid-media-id"' -- "$X" media subtitles add 1 subs --language en --dry-run --output json
check "media subtitles add without --language: invalid-args" 2 err '"reason": "invalid-args"' -- "$X" media subtitles add 1 2 --dry-run --output json
check "media subtitles add --category tweet_image: invalid-args" 2 err '"reason": "invalid-args"' -- "$X" media subtitles add 1 2 --language en --category tweet_image --dry-run --output json
check "media subtitles remove --dry-run" 0 out '"command": "media-subtitles-remove"' -- "$X" media subtitles remove 1 --language en --dry-run --output json
check "media subtitles remove --force: invalid-args" 2 err '"reason": "invalid-args"' -- "$X" media subtitles remove 1 --language en --force --dry-run --output json
check "media upload --category subtitles --dry-run" 0 out '"category": "subtitles"' -- "$X" media upload ./captions.srt --media-type text/srt --category subtitles --dry-run --output json
check "schema media-upload: schema not available" 1 err 'schema not available' -- "$X" schema media-upload --output json
check "schema skill-install: legacy_install_dir declared" 0 out 'legacy_install_dir' -- "$X" schema skill-install --output json
check "validate --help: lists the schema names" 0 out 'alt-text' -- "$X" validate --help
check "validate auto-detects alt-text" 0 out '"schema": "alt-text"' -- bash -c "printf '%s' '{\"data\":{\"id\":\"1\",\"associated_metadata\":{}}}' | '$X' validate --output json"
check "validate auto-detects subtitles" 0 out '"schema": "subtitles"' -- bash -c "printf '%s' '{\"data\":{\"id\":\"1\",\"associated_subtitles\":{}}}' | '$X' validate --output json"
check "--raw on a subcommand usage error: compact" 2 err '{"exit_code":2,"message":"the following required' -- "$X" post --output json --raw
check "XURL_RAW on a subcommand usage error: compact" 2 err '{"exit_code":2,"message":"the following required' -- env XURL_RAW=true "$X" post --output json
check "XURL_JSON on a subcommand usage error: envelope" 2 err '"reason": "unknown-command"' -- env XURL_JSON=true "$X" auth zzz

check "skill install: XURL_SKILL_HOME stands in for ~" 0 out "\"install_dir\": \"$WORK/home/.claude/skills/xurl-rs\"" -- "$X" skill install claude_code --dry-run --output json
check "skill install codex: ~/.agents/skills; skill install codex, no old copy: no legacy_install_dir" 0 \
  out "\"install_dir\": \"$WORK/home/.agents/skills/xurl-rs\"" \
  out '!legacy_install_dir' \
  -- "$X" skill install codex --dry-run --output json
check "skill install: CLAUDE_CONFIG_DIR wins over XURL_SKILL_HOME" 0 out "\"install_dir\": \"$WORK/cc/skills/xurl-rs\"" -- env CLAUDE_CONFIG_DIR="$WORK/cc" "$X" skill install claude_code --dry-run --output json
check "skill install: KIRO_HOME" 0 out "\"install_dir\": \"$WORK/kh/skills/xurl-rs\"" -- env KIRO_HOME="$WORK/kh" "$X" skill install kiro --dry-run --output json
check "skill install: OPENCODE_CONFIG_DIR" 0 out "\"install_dir\": \"$WORK/oc/skills/xurl-rs\"" -- env OPENCODE_CONFIG_DIR="$WORK/oc" "$X" skill install opencode --dry-run --output json
xdg_config_home_rows() {
  check "skill install opencode: XURL_SKILL_HOME outranks XDG_CONFIG_HOME" 0 out "\"install_dir\": \"$WORK/home/.config/opencode/skills/xurl-rs\"" -- env XDG_CONFIG_HOME="$WORK/xdg" "$X" skill install opencode --dry-run --output json
  check "skill install opencode: XDG_CONFIG_HOME without XURL_SKILL_HOME" 0 out "\"install_dir\": \"$WORK/xdg/opencode/skills/xurl-rs\"" -- env -u XURL_SKILL_HOME XDG_CONFIG_HOME="$WORK/xdg" "$X" skill install opencode --dry-run --output json
}
xdg_config_home_rows
mkdir -p "$WORK/home/.codex/skills/xurl-rs"
check "skill install codex: legacy_install_dir names the old copy" 0 out "\"legacy_install_dir\": \"$WORK/home/.codex/skills/xurl-rs\"" -- "$X" skill install codex --dry-run --output json
check "skill install codex text: the note names skill update" 0 out 'xr skill update codex' -- "$X" skill install codex --dry-run
check "skill update --all: an old codex copy counts as installed" 0 out 'dry_run' -- bash -c "'$X' skill update --all --dry-run --output json | jaq -r '.installations[] | select(.host == \"codex\") | .status' 2>/dev/null || '$X' skill update --all --dry-run --output json | jq -r '.installations[] | select(.host == \"codex\") | .status'"

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
  if run "$X" whoami --output json && [ "$_exit" = 0 ]; then break; fi
  sleep 0.3
done

printf '\n# Group 2: staged user token, stub API\n'
check "auth status: per-app fields; oauth2_users; bearer_source; no token values" 0 \
  out '"client_id_hint": "abcdefgh"' \
  out '"alice"' \
  out '"bearer_source": "store"' \
  out '!fakeaccess' \
  -- "$X" auth status --output json
check "whoami: the X API document; NO status key on success" 0 \
  out '"username": "alice"' \
  out '!"status"' \
  -- "$X" whoami --output json
check "whoami --raw: compact" 0 out '{"data":{"id":"42"' -- "$X" whoami --output json --raw
check "whoami text mode piped: JSON" 0 out '"username": "alice"' -- "$X" whoami
check "search: data + meta, no status; search: no status key; search default page size 10; search does not resolve /2/users/me; typed search: sends post.fields" 0 \
  out '"next_token": "T2"' \
  out '!"status"' \
  log 'max_results=10' \
  log '!/2/users/me' \
  log 'post.fields=' \
  -- "$X" search x --output json
check "search --output jsonl: whole document, pretty; NOT one record per line" 0 \
  out '"next_token": "T2"' \
  out '!{"id":"1","name":"U"' \
  -- "$X" search x --output jsonl
check "search --output ndjson: whole document, compact" 0 out '{"data":[{"id":"1"' -- "$X" search x --output ndjson
check "search --output json --raw: compact" 0 out '{"data":[{"id":"1"' -- "$X" search x --output json --raw
check "per-record lines come from jaq" 0 out '{"id":"1","name":"U","text":"hi","username":"u"}' -- bash -c "'$X' search x --output json | jaq -c '.data[]?' 2>/dev/null || '$X' search x --output json | jq -c '.data[]?'"
check "stream --output jsonl: one chunk per line" 0 out '{"data":{"id":"s2","text":"two"}}' -- "$X" /2/tweets/search/stream --auth app --output jsonl --timeout 5
check "stream --output json: no banners" 0 out '!Streaming response started' -- "$X" /2/tweets/search/stream --auth app --output json --timeout 5
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
  out '"id": "777"' \
  out '"edit_history_post_ids"' \
  out '!edit_history_tweet_ids' \
  -- "$X" post "hello" --output json
check "block: lookup then POST /blocking" 0 log '"path": "/2/users/42/blocking"' -- "$X" block @spammer --output json
check "unblock: DELETE /blocking/<target>" 0 log '/2/users/42/blocking/7' -- "$X" unblock spammer --output json
check "delete --force: DELETE /2/tweets/<id>" 0 log '"path": "/2/tweets/123"' -- "$X" delete 123 --force --output json
check "HTTP 429: rate-limited exit 3; no next_step" 3 \
  err '"reason": "rate-limited"' \
  err '!next_step' \
  -- "$X" /2/ratelimit --output json
check "HTTP 404: not-found exit 4" 4 err '"reason": "not-found"' -- "$X" /2/missing --output json
check "HTTP 401: auth-required exit 77; no next_step" 77 \
  err '"reason": "auth-required"' \
  err '!next_step' \
  -- "$X" /2/unauthorized --output json
check "HTTP 403: forbidden exit 1; HTTP 403 bare: no next_step" 1 \
  err '"reason": "forbidden"' \
  err '!next_step' \
  -- "$X" /2/forbidden --output json
check "HTTP 403 enrollment: forbidden; enroll-app next_step; docs URL" 1 \
  err '"reason": "forbidden"' \
  err '"action": "enroll-app"' \
  err 'x-platform-enrollment' \
  -- "$X" /2/notenrolled --output json
check "HTTP 400: invalid-request exit 1" 1 err '"reason": "invalid-request"' -- "$X" /2/badrequest --output json
check "HTTP 422: invalid-request exit 1; HTTP refusal: problem document in message" 1 \
  err '"reason": "invalid-request"' \
  err 'Unprocessable Entity' \
  -- "$X" /2/unprocessable --output json
check "HTTP 500: server-error exit 1" 1 err '"reason": "server-error"' -- "$X" /2/servererror --output json
check "HTTP 418: api-error exit 1" 1 err '"reason": "api-error"' -- "$X" /2/teapot --output json
check "dm: send confirmation document; POST /2/dm_conversations/with/<id>/messages" 0 \
  out '"dm_event_id": "e1"' \
  log '/2/dm_conversations/with/7/messages' \
  -- "$X" dm @bob "hi" --output json
check "validate dm: send confirmation" 0 out '"valid": true' -- bash -c "'$X' dm @bob hi --output json | '$X' validate --schema dm --output json"
check "broadcasts moderators list: GET path; no /2/users/me; user list, no status" 0 \
  log '"path": "/2/broadcasts/chat/moderators?' \
  log '!/2/users/me' \
  out '!"status"' \
  -- "$X" broadcasts moderators list --output json
check "broadcasts moderators list: --cursor not threaded" 0 log '!pagination_token' -- "$X" broadcasts moderators list --cursor abc --output json
check "broadcasts moderators list: --limit not threaded" 0 log '!max_results' -- "$X" broadcasts moderators list --limit 5 --output json
check "broadcasts moderators list: no -n flag" 2 err '"reason": "invalid-args"' -- "$X" broadcasts moderators list -n 5 --output json
check "validate users: moderators list page" 0 out '"valid": true' -- bash -c "'$X' broadcasts moderators list --output json | '$X' validate --schema users --output json"
check "broadcasts moderators add: lookup then POST; user_id body; moderator_user_ids" 0 \
  log '"path": "/2/broadcasts/chat/moderators"' \
  log '{"user_id":"7"}' \
  out '"moderator_user_ids"' \
  -- "$X" broadcasts moderators add @helper --output json
check "broadcasts moderators remove: DELETE /<user_id>" 0 log '/2/broadcasts/chat/moderators/7' -- "$X" broadcasts moderators remove helper --output json
check "validate moderators: add response" 0 out '"valid": true' -- bash -c "'$X' broadcasts moderators add @helper --output json | '$X' validate --schema moderators --output json"
check "raw GET: no status key" 0 out '!"status"' -- "$X" /2/users/me --output json
check "media upload: v2 initialize" 0 log '/2/media/upload/initialize' -- "$X" media upload "$WORK/tiny.png" --media-type image/png --category tweet_image --output json
check "media upload: category sent" 0 log '"media_category":"tweet_image"' -- bash -c "'$X' media upload '$WORK/tiny.png' --media-type image/png --category tweet_image --output json"
check "usage credits: /2/usage/credits" 1 log '/2/usage/credits' -- "$X" usage credits --output json
check "validate posts: search response" 0 out '"valid": true' -- bash -c "'$X' search x --output json | '$X' validate --schema posts --output json"
check "validate user: whoami response" 0 out '"valid": true' -- bash -c "'$X' whoami --output json | '$X' validate --schema user --output json"
check "validate envelope REJECTS a success" 1 err '"reason": "validation-failed"' -- bash -c "'$X' search x --output json | '$X' validate --schema envelope --output json"
check "validate envelope accepts an error" 0 out '"valid": true' -- bash -c "'$X' /2/missing --output json 2>&1 | '$X' validate --schema envelope --output json"
check "validate envelope accepts a dry_run" 0 out '"valid": true' -- bash -c "'$X' post hi --dry-run --output json | '$X' validate --schema envelope --output json"
check "--verbose text: request line on stderr; no response body on stderr" 0 \
  err '> GET' \
  err '!"username"' \
  -- "$X" whoami --verbose
check "--verbose json: diagnostics suppressed" 0 err '!> GET' -- "$X" whoami --output json --verbose
check "typed read: retweet_count reads as repost_count; omitted counter prints 0; omitted optional field stays absent" 0 \
  out '"repost_count": 3' \
  out '"like_count": 0' \
  out '!created_at' \
  -- "$X" read 123 --output json
check "raw mode: legacy keys as sent; omitted counter stays absent" 0 \
  out '"edit_history_tweet_ids"' \
  out '!like_count' \
  -- "$X" /2/tweets/123 --output json
check "raw mode: --cursor not threaded" 0 log '!pagination_token' -- "$X" '/2/tweets/search/recent?query=x' --cursor abc --output json
check "raw mode: --limit not threaded" 0 log '!max_results' -- "$X" '/2/tweets/search/recent?query=x' --limit 5 --output json
check "env bearer, empty store: auth status lists no app" 0 out '"apps": []' -- env XURL_TOKEN_STORE="$WORK/empty.yaml" XURL_BEARER_TOKEN=fakebearer "$X" auth status --output json
check "env bearer, empty store: search uses it" 0 out '"next_token"' -- env XURL_TOKEN_STORE="$WORK/empty.yaml" XURL_BEARER_TOKEN=fakebearer "$X" search x --output json
check "--verbose text: legacy-vocabulary note" 0 err 'info: X sent edit_history_tweet_ids; read as edit_history_post_ids' -- "$X" read 123 --verbose
check "--verbose json: no vocabulary note" 0 err '!info: X sent' -- "$X" read 123 --verbose --output json
check "--verbose --quiet: no vocabulary note" 0 err '!info: X sent' -- "$X" read 123 --verbose --quiet
check "spec-marked stream: firehose streams without -s" 0 out '{"data":{"id":"s2","text":"two"}}' -- "$X" /2/likes/firehose/stream --auth app --output json --timeout 5
check "auth default <app> <user>: two documents" 0 out 'Default user set to' -- "$X" auth default demo alice --output json
check "media alt-text: POST /2/media/metadata; body nests metadata.alt_text.text; the API document; no status key" 0 \
  log '"path": "/2/media/metadata"' \
  log '{"id":"1585341984679469056","metadata":{"alt_text":{"text":"A dog"}}}' \
  out '"associated_metadata"' \
  out '!"status"' \
  -- "$X" media alt-text 1585341984679469056 "A dog" --output json
check "media alt-text live bad input: no request sent; message names the check" 1 \
  log '!/2/media/metadata' \
  err '"message": "alt-text-too-long"' \
  -- "$X" media alt-text 1 "$LONG_ALT" --output json
check "validate alt-text: alt-text response" 0 out '"valid": true' -- bash -c "'$X' media alt-text 1 'A dog' --output json | '$X' validate --schema alt-text --output json"
check "media subtitles add: POST /2/media/subtitles; language upper-cased, category wire name" 0 \
  log '"path": "/2/media/subtitles"' \
  log '{"id":"1","media_category":"AmplifyVideo","subtitles":{"id":"2","language_code":"EN","display_name":"English"}}' \
  -- "$X" media subtitles add 1 2 --language en --name English --output json
check "media subtitles add --category tweet_video: TweetVideo" 0 log '"media_category":"TweetVideo"' -- "$X" media subtitles add 1 2 --language en --category tweet_video --output json
check "media subtitles add: the API document" 0 out '"associated_subtitles"' -- "$X" media subtitles add 1 2 --language en --output json
check "validate subtitles: add response" 0 out '"valid": true' -- bash -c "'$X' media subtitles add 1 2 --language en --output json | '$X' validate --schema subtitles --output json"
check "media subtitles remove: DELETE /2/media/subtitles; JSON body names the track; deleted document" 0 \
  log '{"method": "DELETE", "path": "/2/media/subtitles"}' \
  log '{"id":"1","media_category":"AmplifyVideo","language_code":"EN"}' \
  out '"deleted": true' \
  -- "$X" media subtitles remove 1 --language en --output json
check "validate delete: subtitles remove response" 0 out '"valid": true' -- bash -c "'$X' media subtitles remove 1 --language en --output json | '$X' validate --schema delete --output json"
check "raw DELETE -d: body sent" 0 log 'body: {"connection_ids":["1"]}' -- "$X" -X DELETE /2/connections -d '{"connection_ids":["1"]}' --output json

printf '\n# Group 3: bundled scripts against the real binary\n'
check "paginate.sh: streams statusless pages; follows next_token; cap message" 0 \
  out '"id":"1"' \
  log 'pagination_token=T2' \
  err 'stopped after 2 pages' \
  -- "$ROOT/scripts/paginate.sh" --max-pages 2 -- "$X" search x
check "paginate.sh: third page carries the advanced cursor" 0 log 'pagination_token=T3' -- "$ROOT/scripts/paginate.sh" --max-pages 3 -- "$X" search x
check "paginate.sh: blocked" 0 out '"username":"u"' -- "$ROOT/scripts/paginate.sh" --max-pages 1 -- "$X" blocked -n 5
check "paginate.sh: 429 passes exit 3 through" 3 err 'reason=rate-limited (exit 3)' -- "$ROOT/scripts/paginate.sh" -- "$X" /2/ratelimit
check "dry-run-gate.sh: post goes live; dry_run envelope on stderr" 0 \
  out '"id": "777"' \
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
check "media alt-text: dash-leading text needs --" 2 err '"reason": "invalid-args"' -- "$X" media alt-text 1 "-5C on the dial" --dry-run --output json
check "dry-run-gate.sh: XURL_DRY_RUN set: refused before the preflight" 2 err 'XURL_DRY_RUN is set' -- env XURL_DRY_RUN=true "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" post "hello"
check "dry-run-gate.sh: XURL_JSON set: still goes live" 0 log '"path": "/2/tweets"' -- env XURL_JSON=true "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" post "hello"
check "paginate.sh: XURL_JSONL set: still streams" 0 out '"id":"1"' -- env XURL_JSONL=true "$ROOT/scripts/paginate.sh" --max-pages 1 -- "$X" search x
check "XURL_JSON beside --output: invalid-args" 2 err 'cannot be used with' -- env XURL_JSON=true "$X" whoami --output json
check "XURL_DRY_RUN: the live form answers a dry_run envelope" 0 out '"status": "dry_run"' -- env XURL_DRY_RUN=true "$X" post "hello" --output json
check "dry-run-gate.sh: refused preflight names its reason" 1 err 'reason=alt-text-too-long' -- "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" media alt-text 1 "$LONG_ALT"
check "paginate.sh: moderators list stops on a repeated cursor; moderators list streams the page once before stopping" 1 \
  err 'answered the cursor it was fetched with' \
  out '"username":"u"' \
  -- "$ROOT/scripts/paginate.sh" --max-pages 5 -- "$X" broadcasts moderators list

printf '\n'
if [ "$FAILED" -gt 0 ]; then
  printf '%d checks passed, %d failed (%d assertions)\n' "$PASSED" "$FAILED" "$ASSERTIONS" >&2
  exit 1
fi
printf '%d checks passed (%d assertions)\n' "$PASSED" "$ASSERTIONS"
