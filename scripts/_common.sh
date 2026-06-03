#!/usr/bin/env bash
# _common.sh — shared helpers for xurl-rs skill scripts.
#
# Not directly executable. Sourced by dry-run-gate.sh and paginate.sh.
#
# Exports (in the sourcing script's scope):
#     pick_jq                       Sets JQ_BIN to "jaq" or "jq". Returns 1 if neither found.
#     print_jq_install_advice PROG  Prints PM-aware install commands on stderr.
#     JQ_BIN                        Set by pick_jq(); consumed by the sourcing script.

# JQ_BIN is set by pick_jq() and read by the sourcing script. Shellcheck only
# sees this file and flags the assignment as unused; this directive silences it.
# shellcheck disable=SC2034

pick_jq() {
    if command -v jaq >/dev/null 2>&1; then
        JQ_BIN=jaq
        return 0
    fi
    if command -v jq >/dev/null 2>&1; then
        JQ_BIN=jq
        return 0
    fi
    return 1
}

print_jq_install_advice() {
    local prog_name=${1:-script}
    printf '%s: jaq (preferred) or jq is required; neither is on PATH.\n\n' "$prog_name" >&2
    printf 'Install one of these (jaq is preferred when both are available):\n\n' >&2

    # Tab-separated rows: pm-command, jaq install, jq install. Empty install
    # means that PM does not ship a packaged build for that tool.
    local rows=(
        $'brew\tbrew install jaq\tbrew install jq'
        $'cargo\tcargo install --locked jaq\t'
        $'pacman\tsudo pacman -S jaq\tsudo pacman -S jq'
        $'dnf\tsudo dnf install jaq\tsudo dnf install jq'
        $'nix-env\tnix-env -iA nixpkgs.jaq\tnix-env -iA nixpkgs.jq'
        $'apt-get\t\tsudo apt-get install jq'
        $'zypper\t\tsudo zypper install jq'
        $'yum\t\tsudo yum install jq'
        $'apk\t\tsudo apk add jq'
        $'port\t\tsudo port install jq'
        $'pkg\t\tpkg install jq'
    )

    local detected=()
    local missing=()
    local row pm jaq_cmd jq_cmd line

    for row in "${rows[@]}"; do
        IFS=$'\t' read -r pm jaq_cmd jq_cmd <<<"$row"
        if [ -n "$jaq_cmd" ] && [ -n "$jq_cmd" ]; then
            line=$(printf '  %-10s  %-32s  OR  %s' "$pm" "$jaq_cmd" "$jq_cmd")
        elif [ -n "$jaq_cmd" ]; then
            line=$(printf '  %-10s  %s' "$pm" "$jaq_cmd")
        else
            line=$(printf '  %-10s  %s' "$pm" "$jq_cmd")
        fi
        if command -v "$pm" >/dev/null 2>&1; then
            detected+=("$line")
        else
            missing+=("$line")
        fi
    done

    if [ ${#detected[@]} -gt 0 ]; then
        printf 'Detected on this system:\n' >&2
        printf '%s\n' "${detected[@]}" >&2
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        if [ ${#detected[@]} -gt 0 ]; then
            printf '\n' >&2
        fi
        printf 'Other options:\n' >&2
        printf '%s\n' "${missing[@]}" >&2
    fi
}
