#!/usr/bin/env bash
# tests/run.sh: fixture-driven tests for scripts/dry-run-gate.sh and
# scripts/paginate.sh. Each test sets up a stub `xr` on PATH (fixtures/bin/xr),
# invokes the script, and asserts on exit code + stdout/stderr substrings.
#
# The stub writes a body with exit 0 to stdout and a body with a non-zero
# exit to stderr, which is how the real binary splits success documents
# from error envelopes. Bodies below mirror what `xr` emits: API-backed
# successes carry no `status` key; local verbs carry `status: "ok"`.
#
# Run from any working directory:
#     bash tests/run.sh

# Fixtures store JSON envelopes verbatim in shell variables. The quotes and
# braces are part of the literal content, not shell syntax, so shellcheck's
# default "use an array" suggestion doesn't apply here.
# shellcheck disable=SC2089,SC2090

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PASSED=0
FAILED=0

# --- Scaffolding -----------------------------------------------------------

_stdout=""
_stderr=""
_exit=0

reset_stub() {
  unset XR_STUB_DRYRUN_BODY XR_STUB_DRYRUN_EXIT \
    XR_STUB_LIVE_BODY XR_STUB_LIVE_EXIT \
    XR_STUB_PAGES_BODIES XR_STUB_PAGES_EXITS \
    XR_STUB_ERROR_ON_STDOUT
  XR_STUB_PAGE_COUNTER=$(mktemp)
  export XR_STUB_PAGE_COUNTER
}

cleanup_stub() {
  [ -n "${XR_STUB_PAGE_COUNTER:-}" ] && rm -f "$XR_STUB_PAGE_COUNTER"
  unset XR_STUB_PAGE_COUNTER
}

run_script() {
  local stderr_file
  stderr_file=$(mktemp)
  _stdout=$(PATH="$ROOT/fixtures/bin:$PATH" "$@" 2>"$stderr_file" </dev/null) && _exit=0 || _exit=$?
  _stderr=$(cat "$stderr_file")
  rm -f "$stderr_file"
}

assert_exit() {
  if [ "$_exit" = "$1" ]; then return 0; fi
  printf '    expected exit %s, got %s\n' "$1" "$_exit" >&2
  return 1
}

assert_stderr_contains() {
  if grep -qF -- "$1" <<<"$_stderr"; then return 0; fi
  printf '    stderr missing: %s\n' "$1" >&2
  printf '    actual stderr:\n%s\n' "$_stderr" | sed 's/^/      /' >&2
  return 1
}

assert_stdout_contains() {
  if grep -qF -- "$1" <<<"$_stdout"; then return 0; fi
  printf '    stdout missing: %s\n' "$1" >&2
  printf '    actual stdout:\n%s\n' "$_stdout" | sed 's/^/      /' >&2
  return 1
}

assert_stdout_empty() {
  if [ -z "$_stdout" ]; then return 0; fi
  printf '    stdout expected empty, got:\n%s\n' "$_stdout" | sed 's/^/      /' >&2
  return 1
}

assert_stderr_not_contains() {
  if ! grep -qF -- "$1" <<<"$_stderr"; then return 0; fi
  printf '    stderr unexpectedly contains: %s\n' "$1" >&2
  return 1
}

run_test() {
  local name=$1
  reset_stub
  if "$name"; then
    PASSED=$((PASSED + 1))
    printf 'PASS %s\n' "$name"
  else
    FAILED=$((FAILED + 1))
    printf 'FAIL %s\n' "$name"
  fi
  cleanup_stub
}

# --- dry-run-gate tests ----------------------------------------------------

test_gate__accept_clean() {
  XR_STUB_DRYRUN_BODY='{"status":"dry_run","would_succeed":true,"exit_code":0,"command":"post","body":"test"}'
  XR_STUB_LIVE_BODY='{"data":{"id":"1234567890","text":"test"}}'
  export XR_STUB_DRYRUN_BODY XR_STUB_LIVE_BODY

  run_script "$ROOT/scripts/dry-run-gate.sh" --yes -- xr post "test"

  assert_exit 0 || return 1
  assert_stderr_contains "dry-run OK" || return 1
  assert_stderr_contains "running live" || return 1
  assert_stdout_contains '"id":"1234567890"' || return 1
}

test_gate__reject_would_not_succeed() {
  XR_STUB_DRYRUN_BODY='{"status":"dry_run","would_succeed":false,"exit_code":2}'
  export XR_STUB_DRYRUN_BODY

  run_script "$ROOT/scripts/dry-run-gate.sh" --yes -- xr post "bad"

  assert_exit 1 || return 1
  assert_stderr_contains "would NOT succeed" || return 1
  assert_stderr_not_contains "running live" || return 1
}

test_gate__reject_read_op_api_document() {
  # A read op ignores --dry-run and answers the raw API document: no status key.
  XR_STUB_DRYRUN_BODY='{"data":{"id":"42","username":"alice"}}'
  export XR_STUB_DRYRUN_BODY

  run_script "$ROOT/scripts/dry-run-gate.sh" --yes -- xr whoami

  assert_exit 2 || return 1
  assert_stderr_contains "status=absent" || return 1
  assert_stderr_contains "READ op" || return 1
}

test_gate__reject_read_op_local_verb() {
  # Local verbs (validate, auth apps add) answer status: "ok".
  XR_STUB_DRYRUN_BODY='{"status":"ok","schema":"post","valid":true}'
  export XR_STUB_DRYRUN_BODY

  run_script "$ROOT/scripts/dry-run-gate.sh" --yes -- xr validate

  assert_exit 2 || return 1
  assert_stderr_contains "status=ok" || return 1
  assert_stderr_contains "READ op" || return 1
}

test_gate__reject_error_envelope_on_stderr() {
  # The real binary: error envelope on stderr, exit 77.
  XR_STUB_DRYRUN_BODY='{"status":"error","reason":"auth-required","exit_code":77,"next_step":{"action":"sign-in","command":"xr auth oauth2 --no-browser --step 1"}}'
  XR_STUB_DRYRUN_EXIT=77
  export XR_STUB_DRYRUN_BODY XR_STUB_DRYRUN_EXIT

  run_script "$ROOT/scripts/dry-run-gate.sh" --yes -- xr post "x"

  assert_exit 1 || return 1
  assert_stderr_contains "reason=auth-required (exit 77)" || return 1
  assert_stderr_contains '"action":"sign-in"' || return 1
  assert_stderr_not_contains "running live" || return 1
}

test_gate__confirmation_required_names_force() {
  # `xr delete` off a TTY without --force refuses before the dry-run runs.
  XR_STUB_DRYRUN_BODY='{"status":"error","reason":"confirmation-required","exit_code":1,"command":"delete","post_id":"123"}'
  XR_STUB_DRYRUN_EXIT=1
  export XR_STUB_DRYRUN_BODY XR_STUB_DRYRUN_EXIT

  run_script "$ROOT/scripts/dry-run-gate.sh" --yes -- xr delete 123

  assert_exit 1 || return 1
  assert_stderr_contains "reason=confirmation-required" || return 1
  assert_stderr_contains "pass --force" || return 1
}

test_gate__error_envelope_on_stdout() {
  # The `skill` verbs write their error envelope to stdout with exit 0-free
  # semantics inverted: status=error at exit 0 is still a refusal.
  XR_STUB_DRYRUN_BODY='{"status":"error","reason":"missing-host","exit_code":2}'
  export XR_STUB_DRYRUN_BODY

  run_script "$ROOT/scripts/dry-run-gate.sh" --yes -- xr skill install

  assert_exit 1 || return 1
  assert_stderr_contains "reason=missing-host" || return 1
}

test_gate__non_json_stderr_passthrough() {
  # A clap usage error is plain text on stderr, exit 2.
  XR_STUB_DRYRUN_BODY="error: invalid value 'toml' for '--output <OUTPUT>'"
  XR_STUB_DRYRUN_EXIT=2
  export XR_STUB_DRYRUN_BODY XR_STUB_DRYRUN_EXIT

  run_script "$ROOT/scripts/dry-run-gate.sh" --yes -- xr post "x" --bogus

  assert_exit 1 || return 1
  assert_stderr_contains "exited non-zero (2)" || return 1
  assert_stderr_contains "invalid value 'toml'" || return 1
}

test_gate__live_failure_passes_through() {
  XR_STUB_DRYRUN_BODY='{"status":"dry_run","would_succeed":true,"exit_code":0}'
  XR_STUB_LIVE_BODY='{"status":"error","reason":"rate-limited","exit_code":3}'
  XR_STUB_LIVE_EXIT=3
  export XR_STUB_DRYRUN_BODY XR_STUB_LIVE_BODY XR_STUB_LIVE_EXIT

  run_script "$ROOT/scripts/dry-run-gate.sh" --yes -- xr post "x"

  assert_exit 3 || return 1
  assert_stdout_empty || return 1
  assert_stderr_contains '"reason":"rate-limited"' || return 1
}

test_gate__reject_forbidden_dry_run_flag() {
  run_script "$ROOT/scripts/dry-run-gate.sh" --yes -- xr post "x" --dry-run

  assert_exit 2 || return 1
  assert_stderr_contains "do not pass --dry-run" || return 1
}

test_gate__reject_forbidden_output_flag() {
  run_script "$ROOT/scripts/dry-run-gate.sh" --yes -- xr post "x" --output json

  assert_exit 2 || return 1
  assert_stderr_contains "do not pass --output" || return 1
}

test_gate__reject_forbidden_json_shorthand() {
  run_script "$ROOT/scripts/dry-run-gate.sh" --yes -- xr post "x" --json

  assert_exit 2 || return 1
  assert_stderr_contains "do not pass --json" || return 1
}

test_gate__refuse_non_tty_without_yes() {
  XR_STUB_DRYRUN_BODY='{"status":"dry_run","would_succeed":true,"exit_code":0}'
  export XR_STUB_DRYRUN_BODY

  # No --yes; stdin is /dev/null (non-TTY); should refuse with exit 3.
  run_script "$ROOT/scripts/dry-run-gate.sh" -- xr post "test"

  assert_exit 3 || return 1
  assert_stderr_contains "refusing to run without --yes" || return 1
}

test_gate__missing_args() {
  run_script "$ROOT/scripts/dry-run-gate.sh" --yes

  assert_exit 2 || return 1
  assert_stderr_contains 'missing verb invocation after "--"' || return 1
}

# --- paginate tests --------------------------------------------------------

test_paginate__single_page() {
  # A real list response: data + meta, no status key.
  XR_STUB_PAGES_BODIES='{"data":[{"id":"a"},{"id":"b"}],"meta":{"result_count":2}}'
  export XR_STUB_PAGES_BODIES

  run_script "$ROOT/scripts/paginate.sh" -- xr search "rust"

  assert_exit 0 || return 1
  assert_stdout_contains '"id":"a"' || return 1
  assert_stdout_contains '"id":"b"' || return 1
  assert_stderr_contains "last (no next_token)" || return 1
}

test_paginate__multi_page_follows_cursor() {
  # Three pages; first two carry next_token, last doesn't.
  XR_STUB_PAGES_BODIES=$'{"data":[{"id":"p1"}],"meta":{"next_token":"t1"}}\n{"data":[{"id":"p2"}],"meta":{"next_token":"t2"}}\n{"data":[{"id":"p3"}]}'
  export XR_STUB_PAGES_BODIES

  run_script "$ROOT/scripts/paginate.sh" -- xr search "rust"

  assert_exit 0 || return 1
  assert_stdout_contains '"id":"p1"' || return 1
  assert_stdout_contains '"id":"p2"' || return 1
  assert_stdout_contains '"id":"p3"' || return 1
  assert_stderr_contains "page 3 was the last" || return 1
}

test_paginate__empty_page_streams_nothing() {
  XR_STUB_PAGES_BODIES='{"meta":{"result_count":0}}'
  export XR_STUB_PAGES_BODIES

  run_script "$ROOT/scripts/paginate.sh" -- xr mentions

  assert_exit 0 || return 1
  assert_stdout_empty || return 1
  assert_stderr_contains "page 1 was the last" || return 1
}

test_paginate__error_envelope_on_stderr_passes_exit_through() {
  # The real binary: rate-limited envelope on stderr, exit 3.
  XR_STUB_PAGES_BODIES=$'{"data":[{"id":"p1"}],"meta":{"next_token":"t1"}}\n{"status":"error","reason":"rate-limited","exit_code":3}'
  XR_STUB_PAGES_EXITS="0 3"
  export XR_STUB_PAGES_BODIES XR_STUB_PAGES_EXITS

  run_script "$ROOT/scripts/paginate.sh" -- xr search "rust"

  assert_exit 3 || return 1
  assert_stdout_contains '"id":"p1"' || return 1
  assert_stderr_contains "page 2 failed: reason=rate-limited (exit 3)" || return 1
}

test_paginate__error_envelope_on_stdout() {
  XR_STUB_PAGES_BODIES='{"status":"error","reason":"missing-host","exit_code":2}'
  export XR_STUB_PAGES_BODIES

  run_script "$ROOT/scripts/paginate.sh" -- xr skill install

  assert_exit 1 || return 1
  assert_stderr_contains "reason=missing-host" || return 1
}

test_paginate__rejects_dry_run_document() {
  # XURL_DRY_RUN=1 in the environment turns a write verb's page into a dry_run envelope.
  XR_STUB_PAGES_BODIES='{"status":"dry_run","would_succeed":true,"exit_code":0}'
  export XR_STUB_PAGES_BODIES

  run_script "$ROOT/scripts/paginate.sh" -- xr post "x"

  assert_exit 1 || return 1
  assert_stderr_contains "status=dry_run" || return 1
}

test_paginate__stop_at_max_pages() {
  # Two pages, each with next_token; cap at 2 so we stop before the
  # logically-existing page 3.
  XR_STUB_PAGES_BODIES=$'{"data":[{"id":"p1"}],"meta":{"next_token":"t1"}}\n{"data":[{"id":"p2"}],"meta":{"next_token":"t2"}}'
  export XR_STUB_PAGES_BODIES

  run_script "$ROOT/scripts/paginate.sh" --max-pages 2 -- xr search "rust"

  assert_exit 0 || return 1
  assert_stdout_contains '"id":"p1"' || return 1
  assert_stdout_contains '"id":"p2"' || return 1
  assert_stderr_contains "stopped after 2 pages" || return 1
  assert_stderr_contains "resume with" || return 1
}

test_paginate__reject_forbidden_cursor_flag() {
  run_script "$ROOT/scripts/paginate.sh" -- xr search "rust" --cursor TOKEN

  assert_exit 2 || return 1
  assert_stderr_contains "do not pass --cursor" || return 1
}

test_paginate__reject_forbidden_output_flag() {
  run_script "$ROOT/scripts/paginate.sh" -- xr search "rust" --output json

  assert_exit 2 || return 1
  assert_stderr_contains "do not pass --output" || return 1
}

test_paginate__reject_bad_max_pages() {
  run_script "$ROOT/scripts/paginate.sh" --max-pages abc -- xr search "rust"

  assert_exit 2 || return 1
  assert_stderr_contains "--max-pages must be a positive integer" || return 1
}

# --- Run ------------------------------------------------------------------

run_test test_gate__accept_clean
run_test test_gate__reject_would_not_succeed
run_test test_gate__reject_read_op_api_document
run_test test_gate__reject_read_op_local_verb
run_test test_gate__reject_error_envelope_on_stderr
run_test test_gate__confirmation_required_names_force
run_test test_gate__error_envelope_on_stdout
run_test test_gate__non_json_stderr_passthrough
run_test test_gate__live_failure_passes_through
run_test test_gate__reject_forbidden_dry_run_flag
run_test test_gate__reject_forbidden_output_flag
run_test test_gate__reject_forbidden_json_shorthand
run_test test_gate__refuse_non_tty_without_yes
run_test test_gate__missing_args

run_test test_paginate__single_page
run_test test_paginate__multi_page_follows_cursor
run_test test_paginate__empty_page_streams_nothing
run_test test_paginate__error_envelope_on_stderr_passes_exit_through
run_test test_paginate__error_envelope_on_stdout
run_test test_paginate__rejects_dry_run_document
run_test test_paginate__stop_at_max_pages
run_test test_paginate__reject_forbidden_cursor_flag
run_test test_paginate__reject_forbidden_output_flag
run_test test_paginate__reject_bad_max_pages

printf '\n'
if [ "$FAILED" -gt 0 ]; then
  printf '%d passed, %d failed\n' "$PASSED" "$FAILED" >&2
  exit 1
fi
printf '%d passed\n' "$PASSED"
