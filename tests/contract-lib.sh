#!/usr/bin/env bash
# tests/contract-lib.sh: the scaffolding tests/contract.sh runs its rows
# with. Not directly executable; sourced by contract.sh, and by tests/run.sh
# to test `check` itself.
#
# The sourcing script sets, before the first `check`:
#     WORK         a scratch directory
#     REQUEST_LOG  the file the stub API appends each request to
#     PASSED FAILED ASSERTIONS   counters, each starting at 0
#
# Exports (in the sourcing script's scope):
#     run CMD...   Runs CMD; sets _stdout, _stderr, and _exit.
#     check ...    One row of the harness; see its own comment.

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
