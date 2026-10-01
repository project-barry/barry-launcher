#!/bin/bash
# tools/check-parity.sh [REF]: does this repo still match pb-os?
#
# 1. usr/ must equal pb-os's files at PB_OS_COMMIT plus patches/portable.patch
#    (so every difference from pb-os is in the patch, on purpose).
# 2. Lists pb-os commits after PB_OS_COMMIT, up to REF (default main), that
#    touch the imported files (sync them: tools/sync-from-pb-os.sh REF) or
#    the watched ones (port those by hand; see tools/pb-os-watch.txt).
# Exits 1 if 1 fails, 2 if pb-os has newer changes, 0 when in step.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/tools/lib.sh"
check_pb_os
ref=${1:-main}
commit=$(cat "$ROOT/PB_OS_COMMIT")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
status=0

export_pristine "$commit" "$tmp/a"
if ! (cd "$tmp/a" && git apply -p1 --whitespace=nowarn "$ROOT/patches/portable.patch"); then
  echo "FAIL: patches/portable.patch does not apply to pb-os $(git -C "$PB_OS" rev-parse --short "$commit")"
  exit 1
fi
if diff -r "$tmp/a/usr" "$ROOT/usr" > "$tmp/diff"; then
  echo "ok: usr/ = pb-os $(git -C "$PB_OS" rev-parse --short "$commit") + patches/portable.patch"
else
  echo "FAIL: usr/ has changes that are not in patches/portable.patch (run tools/make-patch.sh):"
  cat "$tmp/diff"
  exit 1
fi

imported=(); watched=()
while read -r p; do imported+=("$p"); done < <(pb_paths)
while read -r p; do watched+=("$p"); done < <(watch_lines)
newer=$(git -C "$PB_OS" log --oneline "$commit..$ref" -- "${imported[@]}")
if [[ -n "$newer" ]]; then
  echo "pb-os has newer changes to imported files (tools/sync-from-pb-os.sh $ref):"
  echo "$newer" | sed 's/^/  /'
  status=2
fi
newer=$(git -C "$PB_OS" log --oneline "$commit..$ref" -- "${watched[@]}")
if [[ -n "$newer" ]]; then
  echo "pb-os has newer changes to watched files (check by hand, see tools/pb-os-watch.txt):"
  echo "$newer" | sed 's/^/  /'
  status=2
fi
dirty=$(git -C "$PB_OS" status --porcelain -- "${imported[@]}" "${watched[@]}")
if [[ -n "$dirty" ]]; then
  echo "note: uncommitted pb-os changes, not counted until committed:"
  echo "$dirty" | sed 's/^/  /'
fi
(( status )) || echo "ok: nothing newer in pb-os $ref"
exit "$status"
