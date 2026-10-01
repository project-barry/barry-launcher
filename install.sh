#!/bin/bash
# install.sh: install Barry Launcher for the user who plays in Game Mode.
#
#   ./install.sh [--prefix DIR] [--session-unit UNIT] [--no-root] [--no-enable]
#   ./install.sh --uninstall [...]   same as ./uninstall.sh [...]
#
# Run it as that user, not as root; it asks for sudo for the few system
# files (a udev rule, and on the AYN Thor an InputPlumber override). Files
# go under DIR (~/.local), user units under ~/.config/systemd/user, so a
# read-only /usr (SteamOS, Armada) is fine and OS updates keep them. The
# files keep pb-os's paths in the repo; the installed copies get these:
# /usr/lib/barry_launcher -> DIR/lib/barry_launcher, /usr/share/barry_launcher
# -> DIR/lib/barry_launcher/share, /run/sm8550-thor/{overlay,home} ->
# /run/user/UID/barry_launcher/{overlay,home}. (Not DIR/share/barry_launcher:
# with DIR ~/.local that is where Barry Launcher keeps your data.)
#
#   --prefix DIR         where lib/ share/ bin/ go (default ~/.local)
#   --session-unit UNIT  the Game Mode unit to start with (found otherwise:
#                        gamescope-session-plus@steam.service on Armada,
#                        gamescope-session.target on SteamOS)
#   --no-root            skip the sudo steps (the button then needs other
#                        access, see README)
#   --no-enable          install, but do not enable or start anything
#   --uninstall          remove Barry Launcher (see uninstall.sh --help)
#
# Running it again updates an install; it never leaves an older copy behind.
set -euo pipefail

SRC=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
if [[ "${1:-}" == --uninstall ]]; then
  shift
  exec "$SRC/uninstall.sh" "$@"
fi
PREFIX=$HOME/.local
SESSION_UNIT=
ROOT_STEPS=1
ENABLE=1

die() { echo "install.sh: $*" >&2; exit 1; }
warn() { echo "  ! $*" >&2; }
say() { echo "== $*"; }

while (( $# )); do
  case "$1" in
    --prefix) PREFIX=${2:?}; shift ;;
    --session-unit) SESSION_UNIT=${2:?}; shift ;;
    --no-root) ROOT_STEPS=0 ;;
    --no-enable) ENABLE=0 ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option $1 (see --help)" ;;
  esac
  shift
done

(( EUID != 0 )) || die "run this as the user who plays in Game Mode, not as root"
# Folders this install creates, so uninstall.sh can remove them again (once
# empty); make_dir records them in the install record once it exists.
NEW_DIRS=()
make_dir() {
  local d=$1 missing=()
  while [[ ! -e "$d" ]]; do missing=("$d" "${missing[@]+"${missing[@]}"}"); d=$(dirname "$d"); done
  mkdir -p "$1"
  NEW_DIRS+=("${missing[@]+"${missing[@]}"}")
  if [[ -f "${MANIFEST:-}" ]]; then
    for d in "${missing[@]+"${missing[@]}"}"; do echo "dir $d" >> "$MANIFEST"; done
  fi
}
PREFIX=${PREFIX/#\~/$HOME}
make_dir "$PREFIX"
PREFIX=$(cd "$PREFIX" && pwd)
[[ "$PREFIX" != *[[:space:]]* ]] || die "the prefix may not contain spaces: $PREFIX"

CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
UNIT_DIR=$CONFIG_HOME/systemd/user
CONF_DIR=$CONFIG_HOME/barry_launcher
APPS_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/applications
LIBDIR=$PREFIX/lib/barry_launcher
MANIFEST=$CONF_DIR/installed
UDEV_RULE=/etc/udev/rules.d/70-barry-launcher.rules
IP_SRC=/usr/share/inputplumber/devices/50-ayn_thor.yaml
IP_DST=/etc/inputplumber/devices.d/50-ayn_thor.yaml
IP_TOOL=ip-thor-without-ayn-key.py
ARMADA_UNIT=armada-bottom-screen.service
IP_MARK="# installed by Barry Launcher's install.sh"
UNITS=(barry_launcher.service barry_launcher_inputd.service)
STATE_DIR=/run/user/$(id -u)/barry_launcher  # = barry_launcher_env's
# Your data (Firefox profiles, skins, settings): never removed here.
DATA_DIRS=("${XDG_DATA_HOME:-$HOME/.local/share}/barry_launcher" "$CONF_DIR")
is_data() { local d; for d in "${DATA_DIRS[@]}"; do [[ "${1%/}" == "${d%/}" ]] && return 0; done; return 1; }

unit_exists() { systemctl --user cat "$1" >/dev/null 2>&1; }

# --- checks ------------------------------------------------------------------
say "checking what Barry Launcher needs"
for cmd in python3 xdotool xprop gamescope; do
  command -v "$cmd" >/dev/null || warn "$cmd is missing"
done
command -v firefox >/dev/null || warn "firefox is missing: the Browser and Discord tiles will not start"
command -v flatpak >/dev/null || warn "flatpak is missing: the Signal tile will not start"
python3 -c 'import gi; gi.require_version("Atspi", "2.0"); from gi.repository import Atspi' 2>/dev/null \
  || warn "python3 AT-SPI bindings (gi, Atspi 2.0) are missing: the keyboard will not follow text fields"
qml=
for q in qml6 qml-qt6 /usr/lib/qt6/bin/qml /usr/lib64/qt6/bin/qml; do
  command -v "$q" >/dev/null 2>&1 && { qml=$q; break; }
done
[[ -n "$qml" ]] || warn "no Qt 6 qml runner (qml6 / qml-qt6): nothing will draw; set BARRY_QML if it is elsewhere"
if command -v gamescope >/dev/null && ! gamescope --help 2>&1 | grep -q -- --drm-lease-client; then
  warn "this gamescope cannot take a DRM lease (--drm-lease-client): Barry Launcher cannot use the bottom screen"
fi
if pgrep -x gamescope >/dev/null 2>&1 && ! pgrep -a gamescope 2>/dev/null | grep -q -- --lease-connector; then
  warn "Game Mode's gamescope is running without --lease-connector: the bottom screen is not lent out"
fi

if [[ -z "$SESSION_UNIT" ]]; then
  if unit_exists gamescope-session-plus@steam.service; then
    SESSION_UNIT=gamescope-session-plus@steam.service
  elif unit_exists gamescope-session.target; then
    SESSION_UNIT=gamescope-session.target
  else
    die "cannot tell which unit starts Game Mode; pass --session-unit UNIT"
  fi
fi
echo "  Game Mode unit: $SESSION_UNIT"

# --- files -------------------------------------------------------------------
# An earlier install: its files go (wherever they were), its record of what
# to restore on uninstall stays.
carry=()
if [[ -f "$MANIFEST" ]]; then
  say "replacing the earlier install"
  old_dirs=()
  while read -r kind value; do
    case "$kind" in
      user) [[ "$value" == *barry* ]] && ! is_data "$value" && rm -rf -- "$value" ;;
      armada) carry+=("armada $value") ;;
      dir) old_dirs+=("$value") ;;
    esac
  done < "$MANIFEST"
  # Its folders: gone if now empty (another prefix), else still ours.
  while read -r d; do
    [[ -n "$d" ]] || continue
    rmdir -- "$d" 2>/dev/null || carry+=("dir $d")
  done < <(printf '%s\n' "${old_dirs[@]+"${old_dirs[@]}"}" | awk '{print length, $0}' | sort -rn | cut -d' ' -f2-)
fi
[[ -f "$CONF_DIR/armada-bottom-screen-was-enabled" ]] && carry+=("armada $ARMADA_UNIT")  # older installs
rm -f "$CONF_DIR/armada-bottom-screen-was-enabled"
mkdir -p "$CONF_DIR"  # your data (settings), not a program folder
# The record uninstall.sh works from, written as things are put in place, so
# even a half-finished install can be removed.
{
  echo "# Barry Launcher install record, read by uninstall.sh"
  echo "session $SESSION_UNIT"
  printf '%s\n' "${carry[@]+"${carry[@]}"}" | sort -u | grep . || true
  printf 'dir %s\n' "${NEW_DIRS[@]+"${NEW_DIRS[@]}"}" | grep -v '^dir $' || true
} > "$MANIFEST"
record() { echo "$1 $2" >> "$MANIFEST"; }
for p in "$LIBDIR" "$PREFIX/bin/barry-launcher" \
  "${UNITS[@]/#/$UNIT_DIR/}" "$APPS_DIR/barry_launcher_desktop.desktop"; do
  record user "$p"
done

say "installing into $PREFIX"
for d in "$UNIT_DIR" "$APPS_DIR" "$PREFIX/lib" "$PREFIX/bin"; do make_dir "$d"; done
rm -rf "$LIBDIR"  # replaced whole: no stale files
mkdir -p "$LIBDIR"
cp -R "$SRC/usr/lib/barry_launcher/." "$LIBDIR/"
chmod 0755 "$LIBDIR"/*
cp -R "$SRC/usr/share/barry_launcher" "$LIBDIR/share"
chmod -R u=rwX,go=rX "$LIBDIR/share"
install -m 0755 "$SRC/usr/bin/barry-launcher" "$PREFIX/bin/barry-launcher"
# The uninstaller, so `barry-launcher uninstall` works without this repo.
install -m 0755 "$SRC/uninstall.sh" "$LIBDIR/barry_launcher_uninstall"

for u in "${UNITS[@]}"; do
  install -m 0644 "$SRC/usr/lib/systemd/user/$u" "$UNIT_DIR/$u"
done
install -m 0644 "$SRC/usr/share/applications/barry_launcher_desktop.desktop" \
  "$APPS_DIR/barry_launcher_desktop.desktop"
# pb-os's paths -> this install's (see the top of this file).
python3 - "$LIBDIR" "$LIBDIR/share" "$STATE_DIR" "$SESSION_UNIT" \
  "$LIBDIR" "$APPS_DIR/barry_launcher_desktop.desktop" \
  "${UNITS[@]/#/$UNIT_DIR/}" <<'PY'
import os, sys
lib, share, state, unit, *targets = sys.argv[1:]
subs = [("/usr/lib/barry_launcher", lib), ("/usr/share/barry_launcher", share),
        ("/run/sm8550-thor/overlay", f"{state}/overlay"), ("/run/sm8550-thor/home", f"{state}/home"),
        ("@SESSION_UNIT@", unit)]
files = []
for t in targets:
    if os.path.isdir(t):
        files += [os.path.join(d, f) for d, _, fs in os.walk(t) for f in fs]
    else:
        files.append(t)
for path in files:
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except UnicodeDecodeError:
        continue  # not text
    new = text
    for old, repl in subs:
        new = new.replace(old, repl)
    if new != text:
        mode = os.stat(path).st_mode
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(new)
        os.chmod(path, mode)
PY
if [[ ! -e "$CONF_DIR/barry-launcher.conf" ]]; then
  install -m 0644 "$SRC/barry-launcher.conf.example" "$CONF_DIR/barry-launcher.conf"
fi

# Settings as the services will see them.
eval "$("$LIBDIR/barry_launcher_env" --print | grep -E '^BARRY_(BUTTON_DEVICE|DEVICE_MATCH)=')"
if ! "$LIBDIR/barry_launcher_env" --check; then
  warn "this device does not match BARRY_DEVICE_MATCH=$BARRY_DEVICE_MATCH: the services will not start"
  warn "set BARRY_DEVICE_MATCH in $CONF_DIR/barry-launcher.conf (\"\" = any device)"
fi

# --- system files (sudo) -------------------------------------------------------
if (( ROOT_STEPS )); then
  say "system files (sudo)"
  rules="# Written by Barry Launcher's install.sh.
# The top screen's trackpad and keyboard (barry_launcher_inputd) make uinput
# devices; Steam's own rules usually allow this already.
KERNEL==\"uinput\", SUBSYSTEM==\"misc\", TAG+=\"uaccess\", OPTIONS+=\"static_node=uinput\""
  if [[ -n "$BARRY_BUTTON_DEVICE" ]]; then
    rules+="
# The dashboard button (barry_launcher_buttond), read by the user at the seat.
SUBSYSTEM==\"input\", KERNEL==\"event*\", ATTRS{name}==\"$BARRY_BUTTON_DEVICE\", TAG+=\"uaccess\""
  fi
  record root "$UDEV_RULE"
  printf '%s\n' "$rules" | sudo tee "$UDEV_RULE" >/dev/null
  sudo udevadm control --reload
  sudo udevadm trigger --action=change --subsystem-match=input --subsystem-match=misc

  # The AYN Thor: InputPlumber reads the AYN button too; leave it to Barry.
  if [[ "$BARRY_BUTTON_DEVICE" == gpio-keys-ayn && -f "$IP_SRC" ]] && grep -q 'name: gpio-keys-ayn' "$IP_SRC"; then
    if [[ -e "$IP_DST" ]] && ! grep -qF "$IP_MARK" "$IP_DST"; then
      if grep -q "$IP_TOOL" "$IP_DST"; then
        echo "  InputPlumber already leaves the AYN button alone ($IP_DST)."
      else
        warn "$IP_DST exists and was written by something else; left alone (the AYN button may not reach Barry)"
      fi
    else
      # Marked with the source's checksum: barry-launcher status tells when
      # an OS update changed InputPlumber's file (run install.sh again then).
      tmp=$(mktemp)
      python3 "$LIBDIR/$IP_TOOL" "$IP_SRC" "$tmp"
      printf '%s; source sha256 %s\n' "$IP_MARK" "$(sha256sum "$IP_SRC" | cut -d' ' -f1)" >> "$tmp"
      record root "$IP_DST"
      sudo install -D -m 0644 "$tmp" "$IP_DST"
      rm -f "$tmp"
      echo "  InputPlumber now leaves the AYN button alone (after a reboot)."
    fi
  fi
else
  warn "--no-root: no udev rule; the button needs read access to its /dev/input device"
fi

# --- Armada: one bottom-screen session at a time --------------------------------
if unit_exists "$ARMADA_UNIT" && systemctl --user is-enabled --quiet "$ARMADA_UNIT" 2>/dev/null; then
  say "turning off Armada's bottom-screen session (Plasma Mobile); uninstalling turns it back on"
  record armada "$ARMADA_UNIT"
  systemctl --user disable --now "$ARMADA_UNIT"
fi

# --- enable --------------------------------------------------------------------
systemctl --user daemon-reload
if (( ENABLE )); then
  say "enabling Barry Launcher"
  systemctl --user enable "${UNITS[@]}"
  systemctl --user restart barry_launcher_inputd.service || true
  if systemctl --user is-active --quiet "$SESSION_UNIT"; then
    systemctl --user restart barry_launcher.service || true
  fi
fi

case ":$PATH:" in
  *":$PREFIX/bin:"*) ;;
  *) echo "Note: $PREFIX/bin is not on PATH; the command is $PREFIX/bin/barry-launcher" ;;
esac
cat <<EOF
Done. Barry Launcher starts with Game Mode (or now, if Game Mode is running).
  settings:  $CONF_DIR/barry-launcher.conf
  logs:      journalctl --user -u barry_launcher -u barry_launcher_inputd
  remove:    barry-launcher uninstall   (or $SRC/uninstall.sh)
EOF
