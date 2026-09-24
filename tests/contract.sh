#!/usr/bin/env bash
# tests/contract.sh: run the invocations this bundle documents against a
# real `xr` binary and assert the exit code, the stream, and a substring of
# the body. Every claim in SKILL.md, references/, and templates/ about what
# the binary emits has a row here; a refresh of the bundle starts by running
# this against the target build.
#
# Hermetic: HOME and XURL_TOKEN_STORE point at a scratch directory, the
# failure group talks to a closed port, and the success group talks to
# tests/stub-api.py (standard-library Python) whose request log the harness
# reads back. No live X API call is made and nothing under the real ~/.xurl
# or ~/.claude is touched.
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

WORK=$(mktemp -d)
trap 'kill "${STUB_PID:-}" 2>/dev/null; rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home"
export HOME="$WORK/home"
export NO_COLOR=1
unset XURL_OUTPUT XURL_JSON XURL_JSONL XURL_DRY_RUN XURL_APP XURL_LIMIT XURL_CURSOR XURL_BEARER_TOKEN 2>/dev/null || true

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

# check LABEL EXPECTED_EXIT STREAM NEEDLE -- cmd...
#   STREAM is out, err, or log (the stub request log). NEEDLE is a fixed
#   string that must appear there; prefix it with '!' to require absence.
check() {
  local label=$1 want_exit=$2 stream=$3 needle=$4
  shift 4
  [ "${1:-}" = "--" ] && shift
  : >"$REQUEST_LOG"
  run "$@"
  local hay ok=1
  case "$stream" in
    out) hay=$_stdout ;;
    err) hay=$_stderr ;;
    log) hay=$(cat "$REQUEST_LOG" 2>/dev/null) ;;
  esac
  if [ "$_exit" != "$want_exit" ]; then
    printf '    expected exit %s, got %s\n' "$want_exit" "$_exit" >&2
    ok=0
  fi
  if [ "${needle#!}" != "$needle" ]; then
    if grep -qF -- "${needle#!}" <<<"$hay"; then
      printf '    %s unexpectedly contains: %s\n' "$stream" "${needle#!}" >&2
      ok=0
    fi
  elif ! grep -qF -- "$needle" <<<"$hay"; then
    printf '    %s missing: %s\n' "$stream" "$needle" >&2
    ok=0
  fi
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
check "auth status: apps wrapper, empty" 0 out '"apps": []' -- "$X" auth status --output json
check "auth status: status ok" 0 out '"status": "ok"' -- "$X" auth status --output json
check "auth apps list: apps wrapper" 0 out '"apps": []' -- "$X" auth apps list --output json
check "whoami: 77 on stderr" 77 err '"reason": "auth-required"' -- "$X" whoami --output json
check "whoami: register-app template" 77 err '"action": "register-app"' -- "$X" whoami --output json
check "whoami: nothing on stdout" 77 out '!"status"' -- "$X" whoami --output json
check "post --dry-run: dry_run envelope" 0 out '"status": "dry_run"' -- "$X" post "hi" --dry-run --output json
check "post --dry-run: would_succeed" 0 out '"would_succeed": true' -- "$X" post "hi" --dry-run --output json
check "post --dry-run: no creds needed" 0 out '"command": "post"' -- "$X" post "hi" --dry-run --output json
check "post --dry-run: media_ids echoed" 0 out '"2"' -- "$X" post "hi" --media-id 1 --media-id 2 --dry-run --output json
check "reply --dry-run" 0 out '"command": "reply"' -- "$X" reply 1585341984679469056 "hi" --dry-run --output json
check "quote --dry-run" 0 out '"command": "quote"' -- "$X" quote 1585341984679469056 "hi" --dry-run --output json
check "block --dry-run" 0 out '"command": "block"' -- "$X" block @spammer --dry-run --output json
check "block --dry-run echoes the handle" 0 out '"target_username": "@spammer"' -- "$X" block @spammer --dry-run --output json
check "block --force: invalid-args" 2 err '"reason": "invalid-args"' -- "$X" block @spammer --force --dry-run --output json
check "unblock --dry-run" 0 out '"command": "unblock"' -- "$X" unblock @spammer --dry-run --output json
check "mute --dry-run" 0 out '"command": "mute"' -- "$X" mute @noisy --dry-run --output json
check "unmute --dry-run" 0 out '"command": "unmute"' -- "$X" unmute @noisy --dry-run --output json
check "follow --dry-run" 0 out '"command": "follow"' -- "$X" follow @someone --dry-run --output json
check "dm --dry-run" 0 out '"command": "dm"' -- "$X" dm @bob "hi" --dry-run --output json
check "like --dry-run" 0 out '"status": "dry_run"' -- "$X" like 1585341984679469056 --dry-run --output json
check "delete --dry-run without --force: refused" 1 err '"reason": "confirmation-required"' -- "$X" delete 123 --dry-run --output json
check "delete --force --dry-run: dry_run" 0 out '"post_id": "123"' -- "$X" delete 123 --force --dry-run --output json
check "media upload --dry-run: no stat" 0 out '"would_succeed": true' -- "$X" media upload ./nope.png --dry-run --output json
check "media upload --dry-run: defaults" 0 out '"category": "amplify_video"' -- "$X" media upload ./nope.png --dry-run --output json
check "media upload missing file: io exit 5" 5 err '"reason": "io"' -- "$X" media upload ./nope.png --output json
check "blocked ignores --dry-run" 77 err '"reason": "auth-required"' -- "$X" blocked --dry-run --output json
check "search --page: unsupported-pagination" 1 err '"reason": "unsupported-pagination"' -- "$X" search x --page 2 --output json
check "--output toml: clap error, exit 2" 2 err "invalid value 'toml'" -- "$X" whoami --output toml
check "--output toml: no envelope" 2 err '!"reason"' -- "$X" whoami --output toml
check "unknown flag: invalid-args envelope" 2 err '"reason": "invalid-args"' -- "$X" post hi --bogus --output json
check "missing positional: invalid-args envelope" 2 err '"reason": "invalid-args"' -- "$X" post --output json
check "media upload --wait false: invalid-args" 2 err '"reason": "invalid-args"' -- "$X" media upload ./x.png --wait false --output json
check "media upload bearer-only: auth-method-mismatch" 2 err '"available_in_app"' -- env XURL_TOKEN_STORE="$WORK/bearer.yaml" "$X" media upload "$WORK/tiny.png" --output json
check "unknown command: suggestion" 2 err '"suggestion": "whoami"' -- "$X" whoam --output json
check "bare xr --output json: invalid-args" 2 err '"reason": "invalid-args"' -- "$X" --output json
check "--auth app without bearer: 77" 77 err '"reason": "auth-required"' -- "$X" search x --auth app --output json
check "--auth app without bearer: no next_step" 77 err '!next_step' -- "$X" search x --auth app --output json
check "post --auth app: auth-method-mismatch" 2 err '"reason": "auth-method-mismatch"' -- "$X" post x --auth app --output json
check "post --auth app: supported list" 2 err '"oauth2"' -- "$X" post x --auth app --output json
check "oauth2 step 1, no app: client-credentials-missing" 2 err '"reason": "client-credentials-missing"' -- "$X" auth oauth2 --no-browser --step 1 --output json
check "oauth2 step 1, no app: register-app" 2 err '"action": "register-app"' -- "$X" auth oauth2 --no-browser --step 1 --output json
check "auth clear without selector: validation" 1 err '"reason": "validation"' -- "$X" auth clear --output json
check "skill install no host: error on STDOUT" 2 out '"reason": "missing-host"' -- "$X" skill install --output json
check "skill install no host: known_hosts" 2 out '"opencode"' -- "$X" skill install --output json
check "skill install --dry-run: command_preview" 0 out 'git clone --depth 1' -- "$X" skill install claude_code --dry-run --output json
check "skill update --all --dry-run: installations" 0 out '"installations"' -- "$X" skill update --all --dry-run --output json
check "skill update --all --dry-run: not-installed" 0 out '"not-installed"' -- "$X" skill update --all --dry-run --output json
check "schema --list: message rows" 0 out '"message"' -- "$X" schema --list --output json
check "schema --list: block" 0 out 'block ApiResponse<BlockingResult>' -- bash -c "'$X' schema --list | awk '{print \$1, \$2}'"
check "schema --list: muted" 0 out 'muted ApiResponse<Vec<User>>' -- bash -c "'$X' schema --list | awk '{print \$1, \$2}'"
check "schema --list: broadcasts-moderators-add" 0 out 'broadcasts-moderators-add ApiResponse<ChatModeratorsResult>' -- bash -c "'$X' schema --list | awk '{print \$1, \$2}'"
check "schema --list: broadcasts-moderators-list" 0 out 'broadcasts-moderators-list ApiResponse<Vec<User>>' -- bash -c "'$X' schema --list | awk '{print \$1, \$2}'"
check "schema --list: dm is the send confirmation" 0 out 'dm ApiResponse<DmSentResult>' -- bash -c "'$X' schema --list | awk '{print \$1, \$2}'"
check "schema validate: schema not available" 1 err 'schema not available' -- "$X" schema validate --output json
check "schema validate: reason validation" 1 err '"reason": "validation"' -- "$X" schema validate --output json
check "schema version: schema not available" 1 err 'schema not available' -- "$X" schema version --output json
check "schema completions: schema not available" 1 err 'schema not available' -- "$X" schema completions --output json
check "schema bogus: reason validation, not unknown-command" 1 err '!unknown-command' -- "$X" schema bogus --output json
check "schema bogus: lists valid names" 1 err 'broadcasts-moderators-list' -- "$X" schema bogus --output json
check "schema broadcasts-moderators-add: moderator_user_ids" 0 out 'moderator_user_ids' -- "$X" schema broadcasts-moderators-add --output json
check "schema dm: dm_event_id" 0 out 'dm_event_id' -- "$X" schema dm --output json
check "schema block: positional" 0 out 'blocking' -- "$X" schema block --output json
check "schema --envelope: next_step declared" 0 out 'next_step' -- "$X" schema --envelope --output json
check "schema --envelope: enroll-app" 0 out 'enroll-app' -- "$X" schema --envelope --output json
check "validate --schema block" 0 out '"valid": true' -- bash -c "printf '%s' '{\"data\":{\"blocking\":true}}' | '$X' validate --schema block --output json"
check "validate unknown schema" 1 err '"reason": "unknown-schema"' -- bash -c "printf '{}' | '$X' validate --schema tweet --output json"
check "validate known_schemas lists block" 1 err '"block"' -- bash -c "printf '{}' | '$X' validate --schema tweet --output json"
check "validate known_schemas lists moderators" 1 err '"moderators"' -- bash -c "printf '{}' | '$X' validate --schema tweet --output json"
check "validate known_schemas lists dm-event" 1 err '"dm-event"' -- bash -c "printf '{}' | '$X' validate --schema tweet --output json"
check "validate --help names moderators" 0 out 'moderators' -- "$X" validate --help
check "validate --help names dm-event" 0 out 'dm-event' -- "$X" validate --help
check "validate --schema moderators: needs moderator_user_ids" 1 err 'moderator_user_ids' -- bash -c "printf '%s' '{\"data\":[]}' | '$X' validate --schema moderators --output json"
check "validate missing file: io exit 1" 1 err '"reason": "io"' -- "$X" validate ./nope.json --schema post --output json
check "version: xr <semver>" 0 out 'xr 4.' -- "$X" version
check "version --verbose: names xdk-rs" 0 out '(xdk-rs ' -- "$X" version --verbose
check "version --output json: version key" 0 out '"version": "4.' -- "$X" version --output json
check "version --output json: xdk_rs key" 0 out '"xdk_rs"' -- "$X" version --output json
check "version --output json: no status key" 0 out '!"status"' -- "$X" version --output json
check "version --output yaml" 0 out 'xdk_rs: ' -- "$X" version --output yaml
check "version envelope validation rejects it" 1 err '"reason": "validation-failed"' -- bash -c "'$X' version --output json | '$X' validate --schema envelope --output json"
check "examples: block pair" 0 out 'xr unblock @spammer --output json' -- "$X" examples
check "examples: muted list" 0 out 'xr muted -n 100 --output jsonl' -- "$X" examples
check "examples: usage credits" 0 out 'xr usage credits --output json' -- "$X" examples
check "examples: BROADCASTS section" 0 out 'BROADCASTS:' -- "$X" examples
check "examples: TOOLING section" 0 out 'TOOLING:' -- "$X" examples
check "examples: moderators add" 0 out 'xr broadcasts moderators add @helper' -- "$X" examples
check "examples: version --output json" 0 out 'xr version --output json' -- "$X" examples
check "examples: 150+ lines" 0 out 'ok' -- bash -c "[ \$('$X' examples | wc -l) -ge 150 ] && echo ok"
check "--help: blocked command" 0 out 'blocked      List users you have blocked' -- "$X" --help
check "--help: EXIT CODES section" 0 out 'EXIT CODES:' -- "$X" --help
check "--help: 5 is network error" 0 out '5    network error' -- "$X" --help
check "--help: broadcasts command" 0 out 'broadcasts   Broadcast chat moderation' -- "$X" --help
check "broadcasts moderators add --dry-run" 0 out '"command": "broadcasts-moderators-add"' -- "$X" broadcasts moderators add @helper --dry-run --output json
check "broadcasts moderators add --dry-run echoes handle" 0 out '"target_username": "@helper"' -- "$X" broadcasts moderators add @helper --dry-run --output json
check "broadcasts moderators add --force: invalid-args" 2 err '"reason": "invalid-args"' -- "$X" broadcasts moderators add @helper --force --dry-run --output json
check "broadcasts moderators remove --dry-run" 0 out '"command": "broadcasts-moderators-remove"' -- "$X" broadcasts moderators remove @helper --dry-run --output json
check "broadcasts moderators list ignores --dry-run" 77 err '"reason": "auth-required"' -- "$X" broadcasts moderators list --dry-run --output json
check "closed port: network-error exit 5" 5 err '"reason": "network-error"' -- env XURL_TOKEN_STORE="$WORK/bearer.yaml" "$X" search x --auth app --output json
check "closed port: URL containing 429 is still network-error" 5 err '"reason": "network-error"' -- env XURL_TOKEN_STORE="$WORK/bearer.yaml" "$X" /2/tweets/429 --auth app --output json
check "--auth oauth2 with creds, no token: 77" 77 err '"reason": "auth-required"' -- env XURL_TOKEN_STORE="$WORK/creds.yaml" "$X" --auth oauth2 whoami --output json
check "--auth oauth2 with creds, no token: sign-in" 77 err '"action": "sign-in"' -- env XURL_TOKEN_STORE="$WORK/creds.yaml" "$X" --auth oauth2 whoami --output json
check "block --help: USERNAME positional" 0 out '<USERNAME>' -- "$X" block --help
check "usage --help: credits subcommand" 0 out 'credits' -- "$X" usage --help
check "schema count is 42" 0 out '42' -- bash -c "'$X' schema --list | wc -l"

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
check "auth status: per-app fields" 0 out '"client_id_hint": "abcdefgh"' -- "$X" auth status --output json
check "auth status: oauth2_users" 0 out '"alice"' -- "$X" auth status --output json
check "auth status: bearer_source" 0 out '"bearer_source": "store"' -- "$X" auth status --output json
check "auth status: no token values" 0 out '!fakeaccess' -- "$X" auth status --output json
check "whoami: raw API document" 0 out '"username": "alice"' -- "$X" whoami --output json
check "whoami: NO status key on success" 0 out '!"status"' -- "$X" whoami --output json
check "whoami --raw: compact" 0 out '{"data":{"id":"42"' -- "$X" whoami --output json --raw
check "whoami text mode piped: JSON" 0 out '"username": "alice"' -- "$X" whoami
check "search: data + meta, no status" 0 out '"next_token": "T2"' -- "$X" search x --output json
check "search: no status key" 0 out '!"status"' -- "$X" search x --output json
check "search --output jsonl: whole document, pretty" 0 out '"next_token": "T2"' -- "$X" search x --output jsonl
check "search --output jsonl: NOT one record per line" 0 out '!{"id":"1","name":"U"' -- "$X" search x --output jsonl
check "search --output ndjson: whole document, compact" 0 out '{"data":[{"id":"1"' -- "$X" search x --output ndjson
check "search --output json --raw: compact" 0 out '{"data":[{"id":"1"' -- "$X" search x --output json --raw
check "per-record lines come from jaq" 0 out '{"id":"1","name":"U","text":"hi","username":"u"}' -- bash -c "'$X' search x --output json | jaq -c '.data[]?' 2>/dev/null || '$X' search x --output json | jq -c '.data[]?'"
check "stream --output jsonl: one chunk per line" 0 out '{"data":{"id":"s2","text":"two"}}' -- "$X" /2/tweets/search/stream --auth app --output jsonl --timeout 5
check "stream --output json: no banners" 0 out '!Streaming response started' -- "$X" /2/tweets/search/stream --auth app --output json --timeout 5
check "search default page size 10" 0 log 'max_results=10' -- "$X" search x --output json
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
check "search does not resolve /2/users/me" 0 log '!/2/users/me' -- "$X" search x --output json
check "user @handle: @ stripped in lookup" 0 log '/2/users/by/username/streamsoup_promo?' -- "$X" user @streamsoup_promo --output json
check "reply <url>: id extracted" 0 log '"in_reply_to_tweet_id":"1585341984679469056"' -- "$X" reply "https://x.com/u/status/1585341984679469056" "hi" --output json
check "quote <url>: id extracted" 0 log '"quote_tweet_id":"1585341984679469056"' -- "$X" quote "https://x.com/u/status/1585341984679469056" "hi" --output json
check "read <url>: id extracted" 0 log '/2/tweets/1585341984679469056?' -- "$X" read "https://x.com/u/status/1585341984679469056" --output json
check "post: 201 body" 0 out '"id": "777"' -- "$X" post "hello" --output json
check "block: lookup then POST /blocking" 0 log '"path": "/2/users/42/blocking"' -- "$X" block @spammer --output json
check "unblock: DELETE /blocking/<target>" 0 log '/2/users/42/blocking/7' -- "$X" unblock spammer --output json
check "delete --force: DELETE /2/tweets/<id>" 0 log '"path": "/2/tweets/123"' -- "$X" delete 123 --force --output json
check "HTTP 429: rate-limited exit 3" 3 err '"reason": "rate-limited"' -- "$X" /2/ratelimit --output json
check "HTTP 429: no next_step" 3 err '!next_step' -- "$X" /2/ratelimit --output json
check "HTTP 404: not-found exit 4" 4 err '"reason": "not-found"' -- "$X" /2/missing --output json
check "HTTP 401: auth-required exit 77" 77 err '"reason": "auth-required"' -- "$X" /2/unauthorized --output json
check "HTTP 401: no next_step" 77 err '!next_step' -- "$X" /2/unauthorized --output json
check "HTTP 403: forbidden exit 1" 1 err '"reason": "forbidden"' -- "$X" /2/forbidden --output json
check "HTTP 403 bare: no next_step" 1 err '!next_step' -- "$X" /2/forbidden --output json
check "HTTP 403 enrollment: forbidden" 1 err '"reason": "forbidden"' -- "$X" /2/notenrolled --output json
check "HTTP 403 enrollment: enroll-app next_step" 1 err '"action": "enroll-app"' -- "$X" /2/notenrolled --output json
check "HTTP 403 enrollment: docs URL" 1 err 'x-platform-enrollment' -- "$X" /2/notenrolled --output json
check "HTTP 400: invalid-request exit 1" 1 err '"reason": "invalid-request"' -- "$X" /2/badrequest --output json
check "HTTP 422: invalid-request exit 1" 1 err '"reason": "invalid-request"' -- "$X" /2/unprocessable --output json
check "HTTP 500: server-error exit 1" 1 err '"reason": "server-error"' -- "$X" /2/servererror --output json
check "HTTP 418: api-error exit 1" 1 err '"reason": "api-error"' -- "$X" /2/teapot --output json
check "HTTP refusal: problem document in message" 1 err 'Unprocessable Entity' -- "$X" /2/unprocessable --output json
check "dm: send confirmation document" 0 out '"dm_event_id": "e1"' -- "$X" dm @bob "hi" --output json
check "dm: POST /2/dm_conversations/with/<id>/messages" 0 log '/2/dm_conversations/with/7/messages' -- "$X" dm @bob "hi" --output json
check "validate dm: send confirmation" 0 out '"valid": true' -- bash -c "'$X' dm @bob hi --output json | '$X' validate --schema dm --output json"
check "broadcasts moderators list: GET path" 0 log '"path": "/2/broadcasts/chat/moderators?' -- "$X" broadcasts moderators list --output json
check "broadcasts moderators list: no /2/users/me" 0 log '!/2/users/me' -- "$X" broadcasts moderators list --output json
check "broadcasts moderators list: --cursor not threaded" 0 log '!pagination_token' -- "$X" broadcasts moderators list --cursor abc --output json
check "broadcasts moderators list: --limit not threaded" 0 log '!max_results' -- "$X" broadcasts moderators list --limit 5 --output json
check "broadcasts moderators list: no -n flag" 2 err '"reason": "invalid-args"' -- "$X" broadcasts moderators list -n 5 --output json
check "broadcasts moderators list: user list, no status" 0 out '!"status"' -- "$X" broadcasts moderators list --output json
check "validate users: moderators list page" 0 out '"valid": true' -- bash -c "'$X' broadcasts moderators list --output json | '$X' validate --schema users --output json"
check "broadcasts moderators add: lookup then POST" 0 log '"path": "/2/broadcasts/chat/moderators"' -- "$X" broadcasts moderators add @helper --output json
check "broadcasts moderators add: user_id body" 0 log '{"user_id":"7"}' -- "$X" broadcasts moderators add @helper --output json
check "broadcasts moderators add: moderator_user_ids" 0 out '"moderator_user_ids"' -- "$X" broadcasts moderators add @helper --output json
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
check "--verbose text: request line on stderr" 0 err '> GET' -- "$X" whoami --verbose
check "--verbose json: diagnostics suppressed" 0 err '!> GET' -- "$X" whoami --output json --verbose
check "auth default <app> <user>: two documents" 0 out 'Default user set to' -- "$X" auth default demo alice --output json

printf '\n# Group 3: bundled scripts against the real binary\n'
check "paginate.sh: streams statusless pages" 0 out '"id":"1"' -- "$ROOT/scripts/paginate.sh" --max-pages 2 -- "$X" search x
check "paginate.sh: follows next_token" 0 log 'pagination_token=T2' -- "$ROOT/scripts/paginate.sh" --max-pages 2 -- "$X" search x
check "paginate.sh: third page carries the advanced cursor" 0 log 'pagination_token=T3' -- "$ROOT/scripts/paginate.sh" --max-pages 3 -- "$X" search x
check "paginate.sh: cap message" 0 err 'stopped after 2 pages' -- "$ROOT/scripts/paginate.sh" --max-pages 2 -- "$X" search x
check "paginate.sh: blocked" 0 out '"username":"u"' -- "$ROOT/scripts/paginate.sh" --max-pages 1 -- "$X" blocked -n 5
check "paginate.sh: 429 passes exit 3 through" 3 err 'reason=rate-limited (exit 3)' -- "$ROOT/scripts/paginate.sh" -- "$X" /2/ratelimit
check "dry-run-gate.sh: post goes live" 0 out '"id": "777"' -- "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" post "hello"
check "dry-run-gate.sh: dry_run envelope on stderr" 0 err '"status": "dry_run"' -- "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" post "hello"
check "dry-run-gate.sh: read op refused" 2 err 'READ op' -- "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" whoami
check "dry-run-gate.sh: delete without --force" 1 err 'pass --force' -- "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" delete 123
check "dry-run-gate.sh: delete --force goes live" 0 log '"path": "/2/tweets/123"' -- "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" delete 123 --force
check "dry-run-gate.sh: block goes live" 0 log '"path": "/2/users/42/blocking"' -- "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" block @spammer
check "dry-run-gate.sh: moderators add goes live" 0 log '"path": "/2/broadcasts/chat/moderators"' -- "$ROOT/scripts/dry-run-gate.sh" --yes -- "$X" broadcasts moderators add @helper
check "paginate.sh: moderators list stops on a repeated cursor" 1 err 'answered the cursor it was fetched with' -- "$ROOT/scripts/paginate.sh" --max-pages 5 -- "$X" broadcasts moderators list
check "paginate.sh: moderators list streams the page once before stopping" 1 out '"username":"u"' -- "$ROOT/scripts/paginate.sh" --max-pages 5 -- "$X" broadcasts moderators list

printf '\n'
if [ "$FAILED" -gt 0 ]; then
  printf '%d passed, %d failed\n' "$PASSED" "$FAILED" >&2
  exit 1
fi
printf '%d passed\n' "$PASSED"
