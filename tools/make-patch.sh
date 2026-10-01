#!/bin/bash
# tools/make-patch.sh: write patches/portable.patch, the difference between
# pb-os's files at PB_OS_COMMIT and this repo's usr/. Run it after changing
# anything under usr/, then commit both.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/tools/lib.sh"
check_pb_os
commit=$(cat "$ROOT/PB_OS_COMMIT")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export_pristine "$commit" "$tmp/a"
mkdir -p "$tmp/b"
cp -R "$ROOT/usr" "$tmp/b/"
mkdir -p "$ROOT/patches"
# --no-prefix: paths read a/usr/... and b/usr/...; applied with -p1.
(cd "$tmp" && git diff --no-index --no-prefix --binary a b) > "$ROOT/patches/portable.patch" || true
echo "patches/portable.patch: $(grep -c '^diff --git' "$ROOT/patches/portable.patch") files differ from pb-os $(git -C "$PB_OS" rev-parse --short "$commit")"
