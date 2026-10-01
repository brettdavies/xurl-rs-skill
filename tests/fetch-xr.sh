#!/usr/bin/env bash
# tests/fetch-xr.sh: download the `xr` release asset for this machine, check
# it against the release's sha256sum.txt, unpack it into a cache directory
# outside the repo, and print the binary's absolute path. A second call for
# the same tag prints the cached path without downloading.
#
# Usage:
#     XR_BIN=$(bash tests/fetch-xr.sh v4.2.0)
#
# Cache: ${XR_CACHE_DIR:-${XDG_CACHE_HOME:-~/.cache}/xurl-rs-skill}/<tag>/
#
# Requires: gh, tar, sha256sum or shasum

set -euo pipefail

TAG=${1:?usage: fetch-xr.sh <release tag, such as v4.2.0>}

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) TARGET=x86_64-unknown-linux-gnu ;;
  Linux-aarch64 | Linux-arm64) TARGET=aarch64-unknown-linux-gnu ;;
  Darwin-x86_64) TARGET=x86_64-apple-darwin ;;
  Darwin-arm64) TARGET=aarch64-apple-darwin ;;
  *)
    printf 'fetch-xr.sh: no release asset for %s-%s\n' "$(uname -s)" "$(uname -m)" >&2
    exit 2
    ;;
esac

ASSET="xurl-rs-$TARGET.tar.gz"
DIR="${XR_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/xurl-rs-skill}/$TAG"
BIN="$DIR/xurl-rs-$TARGET/xr"

if [ ! -x "$BIN" ]; then
  mkdir -p "$DIR"
  gh release download "$TAG" -R brettdavies/xurl-rs -p "$ASSET" -p sha256sum.txt -D "$DIR" --clobber >&2
  if command -v sha256sum >/dev/null 2>&1; then
    SUM=(sha256sum -c -)
  else
    SUM=(shasum -a 256 -c -)
  fi
  # sha256sum.txt names files as `./<asset>`; match the asset either way.
  (cd "$DIR" && awk -v a="$ASSET" '{f = $2; sub(/^\*/, "", f); sub(/^\.\//, "", f)} f == a' sha256sum.txt \
    | "${SUM[@]}") >&2
  tar -xzf "$DIR/$ASSET" -C "$DIR"
fi

printf '%s\n' "$BIN"
