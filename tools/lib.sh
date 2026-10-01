# Shared by the tools/ scripts. Source it; needs ROOT set to the repo.
set -euo pipefail

PB_OS=${PB_OS:-$ROOT/../SteamOS-ARM-SM8650}

die() { echo "$(basename "$0"): $*" >&2; exit 1; }

check_pb_os() {
  git -C "$PB_OS" rev-parse --git-dir >/dev/null 2>&1 \
    || die "no pb-os checkout at $PB_OS (set PB_OS=/path/to/pb-os)"
}

map_lines() { grep -vE '^\s*(#|$)' "$ROOT/tools/pb-os-map.txt"; }
watch_lines() { grep -vE '^\s*(#|$)' "$ROOT/tools/pb-os-watch.txt"; }
pb_paths() { map_lines | awk '{print $1}'; }

# export_pristine COMMIT OUTDIR: the mapped pb-os files at COMMIT, laid out
# as this repo has them (OUTDIR/usr/...), unpatched.
export_pristine() {
  local commit=$1 out=$2 src dst tmp
  tmp=$(mktemp -d)
  mkdir -p "$out"
  while read -r src dst; do
    git -C "$PB_OS" archive "$commit" -- "$src" | tar -x -C "$tmp"
    mkdir -p "$out/$(dirname "$dst")"
    if [[ -d "$tmp/$src" ]]; then
      mkdir -p "$out/$dst"
      cp -R "$tmp/$src/." "$out/$dst/"
    else
      cp -p "$tmp/$src" "$out/$dst"
    fi
  done < <(map_lines)
  rm -rf "$tmp"
}
