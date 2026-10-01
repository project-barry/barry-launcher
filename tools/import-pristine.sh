#!/bin/bash
# tools/import-pristine.sh REF: replace usr/ with pb-os's files at REF,
# unpatched, and record the commit. Only for starting over; normal updates
# use tools/sync-from-pb-os.sh, which keeps the portable changes.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/tools/lib.sh"
check_pb_os
commit=$(git -C "$PB_OS" rev-parse "${1:?usage: import-pristine.sh REF}^{commit}")
rm -rf "$ROOT/usr"
export_pristine "$commit" "$ROOT"
echo "$commit" > "$ROOT/PB_OS_COMMIT"
echo "imported pb-os $(git -C "$PB_OS" log -1 --format='%h %s' "$commit")"
