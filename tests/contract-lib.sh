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
#     run CMD...       Runs CMD; sets _stdout, _stderr, and _exit.
#     json_shape TEXT  Prints how the JSON in TEXT is laid out.
#     check ...        One row of the harness; see its own comment.
#     CONTRACT_JQ      The JSON tool the assertions run: the caller's own
#                      value, else jaq, else jq; empty when neither is on
#                      PATH, which the sourcing script reports.

_stdout=""
_stderr=""
_exit=0

CONTRACT_JQ=${CONTRACT_JQ:-$(command -v jaq || command -v jq || true)}

run() {
  local stderr_file="$WORK/stderr"
  _stdout=$("$@" 2>"$stderr_file" </dev/null) && _exit=0 || _exit=$?
  _stderr=$(cat "$stderr_file")
}

# json_shape TEXT: how the JSON in TEXT is laid out, in one word.
#     empty    nothing at all
#     compact  one document on one line
#     pretty   one document over several lines
#     lines    several documents, each on a line of its own
#     mixed    anything else, including text that is not JSON
json_shape() {
  local text=$1 compact docs lines
  if [ -z "$text" ]; then
    printf 'empty'
    return
  fi
  if ! compact=$("$CONTRACT_JQ" -c . <<<"$text" 2>/dev/null); then
    printf 'mixed'
    return
  fi
  docs=$(wc -l <<<"$compact")
  lines=$(wc -l <<<"$text")
  if [ "$docs" -eq 1 ] && [ "$lines" -eq 1 ]; then
    printf 'compact'
  elif [ "$docs" -eq 1 ]; then
    printf 'pretty'
  elif [ "$docs" -eq "$lines" ]; then
    printf 'lines'
  else
    printf 'mixed'
  fi
}

# check LABEL EXPECTED_EXIT ASSERTION... -- cmd...
#   Runs cmd once and asserts its exit code and every ASSERTION. STREAM is
#   out, err, or log (the stub request log).
#
#     STREAM NEEDLE           The stream contains the fixed string NEEDLE;
#                             prefix it with '!' to require absence. For text
#                             output and the request log.
#     STREAM.json PATH WANT   The stream is JSON, and the jaq filter PATH
#                             prints WANT: a string without its quotes, an
#                             array or object as compact JSON. Key order and
#                             indentation do not matter, and the value has to
#                             sit at that path. A filter run over several
#                             documents prints one line per result.
#     STREAM.shape SHAPE      The stream's layout is SHAPE, one of the words
#                             json_shape prints.
check() {
  local label=$1 want_exit=$2
  shift 2
  local asserts=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    case "$1" in
      *.json)
        asserts+=("$1" "$2" "$3")
        shift 3
        ;;
      *)
        asserts+=("$1" "$2" "")
        shift 2
        ;;
    esac
  done
  shift
  : >"$REQUEST_LOG"
  run "$@"
  local ok=1 i kind arg want hay got
  if [ "$_exit" != "$want_exit" ]; then
    printf '    expected exit %s, got %s\n' "$want_exit" "$_exit" >&2
    ok=0
  fi
  for ((i = 0; i < ${#asserts[@]}; i += 3)); do
    kind=${asserts[i]}
    arg=${asserts[i + 1]}
    want=${asserts[i + 2]}
    ASSERTIONS=$((ASSERTIONS + 1))
    case "${kind%%.*}" in
      out) hay=$_stdout ;;
      err) hay=$_stderr ;;
      log) hay=$(cat "$REQUEST_LOG" 2>/dev/null) ;;
    esac
    case "$kind" in
      *.json)
        if ! got=$("$CONTRACT_JQ" -rc "$arg" <<<"$hay" 2>/dev/null); then
          printf '    %s is not JSON, or %s does not apply to it\n' "${kind%%.*}" "$arg" >&2
          ok=0
        elif [ "$got" != "$want" ]; then
          printf '    %s %s: expected %s, got %s\n' "${kind%%.*}" "$arg" "$want" "$got" >&2
          ok=0
        fi
        ;;
      *.shape)
        got=$(json_shape "$hay")
        if [ "$got" != "$arg" ]; then
          printf '    %s shape: expected %s, got %s\n' "${kind%%.*}" "$arg" "$got" >&2
          ok=0
        fi
        ;;
      *)
        if [ "${arg#!}" != "$arg" ]; then
          if grep -qF -- "${arg#!}" <<<"$hay"; then
            printf '    %s unexpectedly contains: %s\n' "$kind" "${arg#!}" >&2
            ok=0
          fi
        elif ! grep -qF -- "$arg" <<<"$hay"; then
          printf '    %s missing: %s\n' "$kind" "$arg" >&2
          ok=0
        fi
        ;;
    esac
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
