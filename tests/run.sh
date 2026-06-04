#!/usr/bin/env bash
# tests/run.sh — fixture-driven tests for scripts/dry-run-gate.sh and
# scripts/paginate.sh. Each test sets up a stub `xr` on PATH (fixtures/bin/xr),
# invokes the script, and asserts on exit code + stdout/stderr substrings.
#
# Run from any working directory:
#     bash tests/run.sh

# Fixtures store JSON envelopes verbatim in shell variables. The quotes and
# braces are part of the literal content, not shell syntax — shellcheck's
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
          XR_STUB_LIVE_BODY    XR_STUB_LIVE_EXIT  \
          XR_STUB_PAGES_BODIES
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
    XR_STUB_DRYRUN_BODY='{"status":"dry_run","would_succeed":true,"exit_code":0}'
    XR_STUB_LIVE_BODY='{"status":"ok","data":{"id":"1234567890"}}'
    export XR_STUB_DRYRUN_BODY XR_STUB_LIVE_BODY

    run_script "$ROOT/scripts/dry-run-gate.sh" --yes -- xr post "test"

    assert_exit 0                                              || return 1
    assert_stderr_contains "dry-run OK"                        || return 1
    assert_stderr_contains "running live"                      || return 1
    assert_stdout_contains '"id":"1234567890"'                 || return 1
}

test_gate__reject_would_not_succeed() {
    XR_STUB_DRYRUN_BODY='{"status":"dry_run","would_succeed":false,"exit_code":2}'
    export XR_STUB_DRYRUN_BODY

    run_script "$ROOT/scripts/dry-run-gate.sh" --yes -- xr post "bad"

    assert_exit 1                                              || return 1
    assert_stderr_contains "would NOT succeed"                 || return 1
    assert_stderr_not_contains "running live"                  || return 1
}

test_gate__reject_read_op() {
    # xr returns status=ok because it's a read op that ignores --dry-run.
    XR_STUB_DRYRUN_BODY='{"status":"ok","data":{"id":"abc"}}'
    export XR_STUB_DRYRUN_BODY

    run_script "$ROOT/scripts/dry-run-gate.sh" --yes -- xr whoami

    assert_exit 2                                              || return 1
    assert_stderr_contains "READ op"                           || return 1
}

test_gate__reject_error_envelope() {
    XR_STUB_DRYRUN_BODY='{"status":"error","reason":"auth-required","exit_code":2}'
    export XR_STUB_DRYRUN_BODY

    run_script "$ROOT/scripts/dry-run-gate.sh" --yes -- xr post "x"

    assert_exit 1                                              || return 1
    assert_stderr_contains "reason=auth-required"              || return 1
}

test_gate__reject_forbidden_dry_run_flag() {
    run_script "$ROOT/scripts/dry-run-gate.sh" --yes -- xr post "x" --dry-run

    assert_exit 2                                              || return 1
    assert_stderr_contains "do not pass --dry-run"             || return 1
}

test_gate__reject_forbidden_output_flag() {
    run_script "$ROOT/scripts/dry-run-gate.sh" --yes -- xr post "x" --output json

    assert_exit 2                                              || return 1
    assert_stderr_contains "do not pass --output"              || return 1
}

test_gate__reject_forbidden_json_shorthand() {
    run_script "$ROOT/scripts/dry-run-gate.sh" --yes -- xr post "x" --json

    assert_exit 2                                              || return 1
    assert_stderr_contains "do not pass --json"                || return 1
}

test_gate__refuse_non_tty_without_yes() {
    XR_STUB_DRYRUN_BODY='{"status":"dry_run","would_succeed":true,"exit_code":0}'
    export XR_STUB_DRYRUN_BODY

    # No --yes; stdin is /dev/null (non-TTY); should refuse with exit 3.
    run_script "$ROOT/scripts/dry-run-gate.sh" -- xr post "test"

    assert_exit 3                                              || return 1
    assert_stderr_contains "refusing to run without --yes"     || return 1
}

test_gate__missing_args() {
    run_script "$ROOT/scripts/dry-run-gate.sh" --yes

    assert_exit 2                                              || return 1
    assert_stderr_contains 'missing verb invocation after "--"' || return 1
}

# --- paginate tests --------------------------------------------------------

test_paginate__single_page() {
    XR_STUB_PAGES_BODIES='{"status":"ok","data":[{"id":"a"},{"id":"b"}]}'
    export XR_STUB_PAGES_BODIES

    run_script "$ROOT/scripts/paginate.sh" -- xr search "rust"

    assert_exit 0                                              || return 1
    assert_stdout_contains '"id":"a"'                          || return 1
    assert_stdout_contains '"id":"b"'                          || return 1
    assert_stderr_contains "last (no next_token)"              || return 1
}

test_paginate__multi_page_follows_cursor() {
    # Three pages; first two carry next_token, last doesn't.
    XR_STUB_PAGES_BODIES=$'{"status":"ok","data":[{"id":"p1"}],"meta":{"next_token":"t1"}}\n{"status":"ok","data":[{"id":"p2"}],"meta":{"next_token":"t2"}}\n{"status":"ok","data":[{"id":"p3"}]}'
    export XR_STUB_PAGES_BODIES

    run_script "$ROOT/scripts/paginate.sh" -- xr search "rust"

    assert_exit 0                                              || return 1
    assert_stdout_contains '"id":"p1"'                         || return 1
    assert_stdout_contains '"id":"p2"'                         || return 1
    assert_stdout_contains '"id":"p3"'                         || return 1
    assert_stderr_contains "page 3 was the last"               || return 1
}

test_paginate__bail_on_error_envelope() {
    XR_STUB_PAGES_BODIES='{"status":"error","reason":"rate-limited","exit_code":3}'
    export XR_STUB_PAGES_BODIES

    run_script "$ROOT/scripts/paginate.sh" -- xr search "rust"

    assert_exit 1                                              || return 1
    assert_stderr_contains "reason=rate-limited"               || return 1
}

test_paginate__stop_at_max_pages() {
    # Two pages, each with next_token; cap at 2 so we stop before the
    # logically-existing page 3.
    XR_STUB_PAGES_BODIES=$'{"status":"ok","data":[{"id":"p1"}],"meta":{"next_token":"t1"}}\n{"status":"ok","data":[{"id":"p2"}],"meta":{"next_token":"t2"}}'
    export XR_STUB_PAGES_BODIES

    run_script "$ROOT/scripts/paginate.sh" --max-pages 2 -- xr search "rust"

    assert_exit 0                                              || return 1
    assert_stdout_contains '"id":"p1"'                         || return 1
    assert_stdout_contains '"id":"p2"'                         || return 1
    assert_stderr_contains "stopped after 2 pages"             || return 1
    assert_stderr_contains "resume with"                       || return 1
}

test_paginate__reject_forbidden_cursor_flag() {
    run_script "$ROOT/scripts/paginate.sh" -- xr search "rust" --cursor TOKEN

    assert_exit 2                                              || return 1
    assert_stderr_contains "do not pass --cursor"              || return 1
}

test_paginate__reject_forbidden_output_flag() {
    run_script "$ROOT/scripts/paginate.sh" -- xr search "rust" --output json

    assert_exit 2                                              || return 1
    assert_stderr_contains "do not pass --output"              || return 1
}

test_paginate__reject_bad_max_pages() {
    run_script "$ROOT/scripts/paginate.sh" --max-pages abc -- xr search "rust"

    assert_exit 2                                              || return 1
    assert_stderr_contains "--max-pages must be a positive integer" || return 1
}

# --- Run ------------------------------------------------------------------

run_test test_gate__accept_clean
run_test test_gate__reject_would_not_succeed
run_test test_gate__reject_read_op
run_test test_gate__reject_error_envelope
run_test test_gate__reject_forbidden_dry_run_flag
run_test test_gate__reject_forbidden_output_flag
run_test test_gate__reject_forbidden_json_shorthand
run_test test_gate__refuse_non_tty_without_yes
run_test test_gate__missing_args

run_test test_paginate__single_page
run_test test_paginate__multi_page_follows_cursor
run_test test_paginate__bail_on_error_envelope
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
