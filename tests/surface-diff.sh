#!/usr/bin/env bash
# tests/surface-diff.sh: list the `xr` surface a release adds (+) or removes
# (-): commands, subcommands, flags, enumerated flag values, and response
# schema leaves, as upstream's scripts/check-surface-bump.sh reads them from
# each tag's source tree. Global flags repeated under every command, the
# `help` subcommands, and the leaves of a schema file that is new in full
# are folded away. Env vars, exit codes, and behavior fixes have no
# generated artifact to compare; the release notes carry those.
#
# Usage:
#     bash tests/surface-diff.sh v4.1.1 v4.2.0
#     bash tests/surface-diff.sh --lists old-surface.tsv new-surface.tsv
#
# --lists condenses two surface listings already on disk (the output of
# `check-surface-bump.sh surface <tree>`), with no network.
#
# Requires: python3; for tags also gh, tar, jq

set -euo pipefail

condense() {
  PYTHONDONTWRITEBYTECODE=1 python3 -B - "$1" "$2" <<'PY'
import sys

old = set(open(sys.argv[1]).read().splitlines())
new = set(open(sys.argv[2]).read().splitlines())


def cells(line):
    return line.split("\t")


root_flags = {cells(l)[2].split("=")[0] for l in old | new if l.startswith("cli\txr\t")}
old_schemas = {cells(l)[1] for l in old if l.startswith("schema\t")}
new_schemas = {cells(l)[1] for l in new if l.startswith("schema\t")}

out, folded = [], set()
for sign, lines, known in (("+", sorted(new - old), old_schemas), ("-", sorted(old - new), new_schemas)):
    for line in lines:
        f = cells(line)
        if f[0] == "cli" and len(f) >= 3:
            words = f[1].split()
            if "help" in words or f[2].split("=")[0] in root_flags:
                continue
            out.append(f"{sign} {f[1]} {f[2]}")
        elif f[0] == "schema" and len(f) >= 3:
            if f[1] not in known:
                if (sign, f[1]) not in folded:
                    folded.add((sign, f[1]))
                    out.append(f"{sign} schema file {f[1]}")
            else:
                out.append(f"{sign} {f[1]} {f[2]}")
        else:
            out.append(f"{sign} {line}")

print("\n".join(out) if out else "no surface change")
PY
}

if [ "${1:-}" = "--lists" ]; then
  condense "${2:?old listing}" "${3:?new listing}"
  exit 0
fi

OLD=${1:?usage: surface-diff.sh <old-tag> <new-tag>}
NEW=${2:?usage: surface-diff.sh <old-tag> <new-tag>}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

for tag in "$OLD" "$NEW"; do
  mkdir -p "$WORK/$tag"
  gh api "repos/brettdavies/xurl-rs/tarball/$tag" >"$WORK/$tag.tar.gz"
  tar -xzf "$WORK/$tag.tar.gz" -C "$WORK/$tag" --strip-components=1
done

# One listing script for both trees, so a change in how upstream lists the
# surface cannot read as a change in the surface itself.
LIST="$WORK/$NEW/scripts/check-surface-bump.sh"
if [ ! -f "$LIST" ]; then
  printf 'surface-diff.sh: %s has no scripts/check-surface-bump.sh\n' "$NEW" >&2
  exit 2
fi
bash "$LIST" surface "$WORK/$OLD" >"$WORK/old.tsv"
bash "$LIST" surface "$WORK/$NEW" >"$WORK/new.tsv"
condense "$WORK/old.tsv" "$WORK/new.tsv"
