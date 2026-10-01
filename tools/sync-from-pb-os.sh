#!/bin/bash
# tools/sync-from-pb-os.sh [REF]: bring usr/ up to pb-os REF (default main)
# and keep the portable changes: takes pb-os's files at REF, applies
# patches/portable.patch, and replaces usr/ with the result.
#
# If a hunk no longer fits, its .rej file is left next to the file in usr/;
# make the change by hand, delete the .rej, then run tools/make-patch.sh.
# Review with git diff, run tools/check-parity.sh, and commit.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/tools/lib.sh"
check_pb_os
commit=$(git -C "$PB_OS" rev-parse "${1:-main}^{commit}")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export_pristine "$commit" "$tmp/new"
ok=1
(cd "$tmp/new" && git apply -p1 --reject --whitespace=nowarn "$ROOT/patches/portable.patch") || ok=0
rm -rf "$ROOT/usr"
cp -R "$tmp/new/usr" "$ROOT/usr"
echo "$commit" > "$ROOT/PB_OS_COMMIT"
echo "usr/ now follows pb-os $(git -C "$PB_OS" log -1 --format='%h %s' "$commit")"
if (( ok )); then
  "$ROOT/tools/make-patch.sh"
  echo "Review (git diff), test, then commit."
else
  echo "Some hunks did not apply; fix these, delete them, then run tools/make-patch.sh:"
  find "$ROOT/usr" -name '*.rej' | sed 's/^/  /'
  exit 1
fi
