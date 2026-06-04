#!/usr/bin/env bash
# paginate.sh — cursor-paginate any `xr` list-style verb.
#
# Runs the verb with `--output json --quiet`, streams `.data[]?` records as
# compact JSONL on stdout, follows `meta.next_token` until empty or until
# --max-pages is reached. Bails on the first error envelope.
#
# Usage:
#     scripts/paginate.sh [--max-pages N] [--cursor TOKEN] [--sleep SECS] \
#         -- xr <list-verb> [args...]
#
# Exit codes:
#     0   pagination completed (no more pages, OR --max-pages cap hit)
#     1   envelope error (xr returned status=error)
#     2   usage error (missing args, forbidden flag, non-numeric option value)
#     *   xr's own non-zero exit code if the call itself failed
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
$PROG — cursor-paginate any xr list-style verb.

Usage:
    $PROG [options] -- xr <list-verb> [args...]

Options:
    --max-pages N    Stop after N pages (default: 20).
    --cursor TOKEN   Start from a specific cursor (resume a prior loop).
    --sleep SECS     Sleep between pages (default: 0; bump on rate-limit risk).
    -h, --help       This help.

Output: compact JSONL — one record per line — on stdout. Diagnostics on stderr.

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
        -h|--help)
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
        --cursor|--cursor=*|--after|--after=*|--page|--page=*)
            printf '%s: do not pass %s; pass --cursor to the script instead.\n' "$PROG" "$arg" >&2
            exit 2
            ;;
        --output|--output=*|--json|--jsonl|--dry-run|--dry-run=*)
            printf '%s: do not pass %s; the script controls output.\n' "$PROG" "$arg" >&2
            exit 2
            ;;
    esac
done

if ! pick_jq; then
    print_jq_install_advice "$PROG"
    exit 2
fi

PAGE=0
while [ "$PAGE" -lt "$MAX_PAGES" ]; do
    PAGE=$((PAGE + 1))

    RESP=""
    if [ -n "$CURSOR" ]; then
        if ! RESP=$("$@" --cursor "$CURSOR" --output json --quiet); then
            EC=$?
            printf '%s: page %d call exited non-zero (%d).\n' "$PROG" "$PAGE" "$EC" >&2
            if [ -n "$RESP" ]; then
                printf '%s\n' "$RESP" >&2
            fi
            exit "$EC"
        fi
    else
        if ! RESP=$("$@" --output json --quiet); then
            EC=$?
            printf '%s: page %d call exited non-zero (%d).\n' "$PROG" "$PAGE" "$EC" >&2
            if [ -n "$RESP" ]; then
                printf '%s\n' "$RESP" >&2
            fi
            exit "$EC"
        fi
    fi

    if [ -z "$RESP" ]; then
        printf '%s: page %d produced no output.\n' "$PROG" "$PAGE" >&2
        exit 1
    fi

    STATUS=$(printf '%s' "$RESP" | "$JQ_BIN" -r '.status // ""')
    if [ "$STATUS" != "ok" ]; then
        REASON=$(printf '%s' "$RESP" | "$JQ_BIN" -r '.reason // ""')
        printf '%s: page %d returned status=%s (reason=%s).\n' \
            "$PROG" "$PAGE" "$STATUS" "$REASON" >&2
        printf '%s\n' "$RESP" >&2
        exit 1
    fi

    printf '%s' "$RESP" | "$JQ_BIN" -c '.data[]?'

    CURSOR=$(printf '%s' "$RESP" | "$JQ_BIN" -r '.meta.next_token // ""')
    if [ -z "$CURSOR" ]; then
        printf '%s: page %d was the last (no next_token).\n' "$PROG" "$PAGE" >&2
        exit 0
    fi

    if [ "$SLEEP_SECS" -gt 0 ]; then
        sleep "$SLEEP_SECS"
    fi
done

printf '%s: stopped after %d pages (--max-pages); a next_token still exists.\n' \
    "$PROG" "$PAGE" >&2
printf '%s: resume with: %s --cursor %s -- <same verb invocation>\n' \
    "$PROG" "$PROG" "$CURSOR" >&2
