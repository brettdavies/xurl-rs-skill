#!/usr/bin/env bash
# dry-run-gate.sh — enforce the dry-run-then-live discipline for `xr` write ops.
#
# Runs the verb with `--dry-run --output json --quiet` first. Refuses to
# proceed unless the envelope reports `status=dry_run`, `would_succeed=true`,
# and `exit_code=0`. Prompts for confirmation on a TTY, or honors `--yes`,
# then re-runs without `--dry-run` so the response envelope lands on stdout.
#
# Usage:
#     scripts/dry-run-gate.sh [--yes] -- xr <write-verb> [args...]
#
# Exit codes:
#     0   live call succeeded (verb's own 0)
#     1   dry-run rejected (would_succeed=false, error envelope, or non-zero
#         exit from the dry-run call itself)
#     2   usage error (missing args, forbidden flag, read-op verb)
#     3   refused (non-TTY without --yes)
#     4   user declined at the prompt
#     *   verb's own non-zero exit code on the live call
#
# Requires: jaq (preferred) or jq

set -euo pipefail

PROG=${0##*/}
ASSUME_YES=0
JQ_BIN=""

# shellcheck source=_common.sh disable=SC1091
. "${BASH_SOURCE[0]%/*}/_common.sh"

usage() {
    cat >&2 <<EOF
$PROG — gate an xr write op behind a mandatory --dry-run preflight.

Usage:
    $PROG [--yes] -- xr <write-verb> [args...]

Options:
    --yes        Skip the interactive confirmation. The caller is responsible
                 for having obtained user confirmation already.
    -h, --help   This help.

The gate adds --dry-run and --output json itself; do NOT pass either in args.

Examples:
    $PROG -- xr post "Shipping today."
    $PROG --yes -- xr reply 1234567890 "Congrats!"
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --yes)
            ASSUME_YES=1
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
        --dry-run|--dry-run=*)
            printf '%s: do not pass --dry-run; the gate adds it for the preflight.\n' "$PROG" >&2
            exit 2
            ;;
        --output|--output=*)
            printf '%s: do not pass --output; the gate forces --output json.\n' "$PROG" >&2
            exit 2
            ;;
        --json|--jsonl)
            printf '%s: do not pass %s; the gate forces --output json.\n' "$PROG" "$arg" >&2
            exit 2
            ;;
    esac
done

if ! pick_jq; then
    print_jq_install_advice "$PROG"
    exit 2
fi

printf '%s: dry-run preflight…\n' "$PROG" >&2

DRY_OUTPUT=""
if ! DRY_OUTPUT=$("$@" --dry-run --output json --quiet); then
    EC=$?
    printf '%s: dry-run call exited non-zero (%d).\n' "$PROG" "$EC" >&2
    if [ -n "$DRY_OUTPUT" ]; then
        printf '%s\n' "$DRY_OUTPUT" >&2
    fi
    exit 1
fi

if [ -z "$DRY_OUTPUT" ]; then
    printf '%s: dry-run produced no output.\n' "$PROG" >&2
    exit 1
fi

STATUS=$(printf '%s' "$DRY_OUTPUT" | "$JQ_BIN" -r '.status // ""')
case "$STATUS" in
    dry_run)
        WOULD=$(printf '%s' "$DRY_OUTPUT" | "$JQ_BIN" -r '.would_succeed')
        EXIT_CODE=$(printf '%s' "$DRY_OUTPUT" | "$JQ_BIN" -r '.exit_code')
        if [ "$WOULD" != "true" ] || [ "$EXIT_CODE" != "0" ]; then
            printf '%s: dry-run says the live call would NOT succeed (would_succeed=%s, exit_code=%s).\n' \
                "$PROG" "$WOULD" "$EXIT_CODE" >&2
            printf '%s\n' "$DRY_OUTPUT" >&2
            exit 1
        fi
        ;;
    ok)
        printf '%s: invocation returned status=ok during dry-run preflight.\n' "$PROG" >&2
        printf '%s: this is a READ op (reads ignore --dry-run). Run it directly.\n' "$PROG" >&2
        exit 2
        ;;
    error)
        REASON=$(printf '%s' "$DRY_OUTPUT" | "$JQ_BIN" -r '.reason // ""')
        printf '%s: dry-run returned error (reason=%s).\n' "$PROG" "$REASON" >&2
        printf '%s\n' "$DRY_OUTPUT" >&2
        exit 1
        ;;
    *)
        printf '%s: unexpected envelope status: "%s".\n' "$PROG" "$STATUS" >&2
        printf '%s\n' "$DRY_OUTPUT" >&2
        exit 1
        ;;
esac

printf '%s: dry-run OK (would_succeed=true, exit_code=0).\n' "$PROG" >&2
printf '%s: dry-run envelope follows on stderr; live response will land on stdout.\n' "$PROG" >&2
printf '%s\n' "$DRY_OUTPUT" >&2

if [ "$ASSUME_YES" != "1" ]; then
    if [ -t 0 ] && [ -t 1 ]; then
        printf '%s: proceed with the LIVE call? [y/N] ' "$PROG" >&2
        REPLY=""
        read -r REPLY </dev/tty
        case "$REPLY" in
            y|Y|yes|YES) ;;
            *)
                printf '%s: declined; not running the live call.\n' "$PROG" >&2
                exit 4
                ;;
        esac
    else
        printf '%s: refusing to run without --yes when not on a TTY.\n' "$PROG" >&2
        exit 3
    fi
fi

printf '%s: running live…\n' "$PROG" >&2
exec "$@" --output json
