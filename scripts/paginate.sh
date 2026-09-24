#!/usr/bin/env bash
# paginate.sh: cursor-paginate any `xr` list-style verb.
#
# Runs the verb with `--output json --quiet`, streams `.data[]?` records as
# compact JSONL on stdout, follows `meta.next_token` until empty or until
# --max-pages is reached. Stops on the first failed page: a non-zero exit
# from xr (its error envelope arrives on stderr and is re-emitted with the
# reason), or a `status: "error"` / `status: "dry_run"` document on stdout.
#
# A successful page is the raw X API document (`data`, `meta`, `includes`,
# `errors`); it carries no `status` key, so the script never requires one.
#
# Usage:
#     scripts/paginate.sh [--max-pages N] [--cursor TOKEN] [--sleep SECS] \
#         -- xr <list-verb> [args...]
#
# Exit codes:
#     0   pagination completed (no more pages, OR --max-pages cap hit)
#     1   a page answered a `status: "error"` or `status: "dry_run"`
#         document on stdout with exit 0, produced no output, or handed
#         back the cursor it was fetched with (a verb that ignores --cursor)
#     2   usage error (missing args, forbidden flag, non-numeric option value)
#     *   xr's own non-zero exit code when a page call failed (the usual
#         path for rate-limited (3), not-found (4), auth-required (77))
#
# Requires: jaq (preferred) or jq

set -euo pipefail

PROG=${0##*/}
MAX_PAGES=20
CURSOR=""
SLEEP_SECS=0
JQ_BIN=""

# shellcheck source=_common.sh disable=SC1091
. "${BASH_SOURCE[0]%/*}/_common.sh"

usage() {
  cat >&2 <<EOF
$PROG: cursor-paginate any xr list-style verb.

Usage:
    $PROG [options] -- xr <list-verb> [args...]

Options:
    --max-pages N    Stop after N pages (default: 20).
    --cursor TOKEN   Start from a specific cursor (resume a prior loop).
    --sleep SECS     Sleep between pages (default: 0; bump on rate-limit risk).
    -h, --help       This help.

Output: compact JSONL (one record per line) on stdout. Diagnostics on stderr.
Exits 1 when a page hands back the cursor it was fetched with: the verb
ignores --cursor (broadcasts moderators list does), so run it bare instead.

The script adds --cursor and --output json itself; do NOT pass --cursor,
--after, --page, --output, --json, --jsonl, or --dry-run in the verb args.

Example:
    $PROG --max-pages 10 -- xr search "rustlang" -n 100
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --max-pages)
      shift
      MAX_PAGES=${1:-}
      if ! [[ "$MAX_PAGES" =~ ^[1-9][0-9]*$ ]]; then
        printf '%s: --max-pages must be a positive integer, got %q.\n' "$PROG" "$MAX_PAGES" >&2
        exit 2
      fi
      shift
      ;;
    --cursor)
      shift
      CURSOR=${1:-}
      if [ -z "$CURSOR" ]; then
        printf '%s: --cursor requires a non-empty value.\n' "$PROG" >&2
        exit 2
      fi
      shift
      ;;
    --sleep)
      shift
      SLEEP_SECS=${1:-}
      if ! [[ "$SLEEP_SECS" =~ ^[0-9]+$ ]]; then
        printf '%s: --sleep must be a non-negative integer, got %q.\n' "$PROG" "$SLEEP_SECS" >&2
        exit 2
      fi
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      printf '%s: unexpected option before "--": %s\n' "$PROG" "$1" >&2
      usage
      exit 2
      ;;
  esac
done

if [ $# -eq 0 ]; then
  printf '%s: missing verb invocation after "--"\n' "$PROG" >&2
  usage
  exit 2
fi

for arg in "$@"; do
  case "$arg" in
    --cursor | --cursor=* | --after | --after=* | --page | --page=*)
      printf '%s: do not pass %s; pass --cursor to the script instead.\n' "$PROG" "$arg" >&2
      exit 2
      ;;
    --output | --output=* | --json | --jsonl | --dry-run | --dry-run=*)
      printf '%s: do not pass %s; the script controls output.\n' "$PROG" "$arg" >&2
      exit 2
      ;;
  esac
done

if ! pick_jq; then
  print_jq_install_advice "$PROG"
  exit 2
fi

ERR_FILE=$(mktemp)
trap 'rm -f "$ERR_FILE"' EXIT

# Re-emits a failed page's stderr. When it is an error envelope, the reason
# is named first so a caller reading the diagnostics sees it without parsing.
report_failure() {
  local page=$1 ec=$2 reason
  reason=$(envelope_reason "$ERR_FILE" "$JQ_BIN")
  if [ -n "$reason" ]; then
    printf '%s: page %d failed: reason=%s (exit %d).\n' "$PROG" "$page" "$reason" "$ec" >&2
  else
    printf '%s: page %d call exited non-zero (%d).\n' "$PROG" "$page" "$ec" >&2
  fi
  if [ -s "$ERR_FILE" ]; then
    cat "$ERR_FILE" >&2
  fi
}

PAGE=0
while [ "$PAGE" -lt "$MAX_PAGES" ]; do
  PAGE=$((PAGE + 1))

  RESP=""
  EC=0
  : >"$ERR_FILE"
  if [ -n "$CURSOR" ]; then
    RESP=$("$@" --cursor "$CURSOR" --output json --quiet 2>"$ERR_FILE") || EC=$?
  else
    RESP=$("$@" --output json --quiet 2>"$ERR_FILE") || EC=$?
  fi
  if [ "$EC" -ne 0 ]; then
    report_failure "$PAGE" "$EC"
    exit "$EC"
  fi

  if [ -z "$RESP" ]; then
    printf '%s: page %d produced no output.\n' "$PROG" "$PAGE" >&2
    exit 1
  fi

  STATUS=$(printf '%s' "$RESP" | "$JQ_BIN" -r '.status // ""')
  case "$STATUS" in
    "" | ok)
      ;;
    error)
      REASON=$(printf '%s' "$RESP" | "$JQ_BIN" -r '.reason // ""')
      printf '%s: page %d returned status=error (reason=%s).\n' "$PROG" "$PAGE" "$REASON" >&2
      printf '%s\n' "$RESP" >&2
      exit 1
      ;;
    *)
      printf '%s: page %d returned status=%s; expected a list response.\n' "$PROG" "$PAGE" "$STATUS" >&2
      printf '%s\n' "$RESP" >&2
      exit 1
      ;;
  esac

  printf '%s' "$RESP" | "$JQ_BIN" -c '.data[]?'

  PREV_CURSOR=$CURSOR
  CURSOR=$(printf '%s' "$RESP" | "$JQ_BIN" -r '.meta.next_token // ""')
  if [ -z "$CURSOR" ]; then
    printf '%s: page %d was the last (no next_token).\n' "$PROG" "$PAGE" >&2
    exit 0
  fi
  if [ "$CURSOR" = "$PREV_CURSOR" ]; then
    printf '%s: page %d answered the cursor it was fetched with (%s); the verb ignores --cursor, so every further page would repeat this one.\n' \
      "$PROG" "$PAGE" "$CURSOR" >&2
    printf '%s: run the verb directly; the records above are one page, streamed twice.\n' "$PROG" >&2
    exit 1
  fi

  if [ "$SLEEP_SECS" -gt 0 ]; then
    sleep "$SLEEP_SECS"
  fi
done

printf '%s: stopped after %d pages (--max-pages); a next_token still exists.\n' \
  "$PROG" "$PAGE" >&2
printf '%s: resume with: %s --cursor %s -- <same verb invocation>\n' \
  "$PROG" "$PROG" "$CURSOR" >&2
