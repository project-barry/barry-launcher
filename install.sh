#!/bin/bash
# install.sh: install Barry Launcher for the user who plays in Game Mode.
#
#   ./install.sh [--prefix DIR] [--session-unit UNIT] [--no-root] [--no-enable]
#   ./install.sh --uninstall [--purge]
#
# Run it as that user, not as root; it asks for sudo for the few system
# files (a udev rule, and on the AYN Thor an InputPlumber override). Files
# go under DIR (~/.local), user units under ~/.config/systemd/user, so a
# read-only /usr (SteamOS, Armada) is fine and OS updates keep them. The
# files keep pb-os's paths in the repo; the installed copies get these:
# /usr/lib/barry_launcher -> DIR/lib/barry_launcher, /usr/share/barry_launcher
# -> DIR/share/barry_launcher, /run/sm8550-thor/{overlay,home} ->
# /run/user/UID/barry_launcher/{overlay,home}.
#
#   --prefix DIR         where lib/ share/ bin/ go (default ~/.local)
#   --session-unit UNIT  the Game Mode unit to start with (found otherwise:
#                        gamescope-session-plus@steam.service on Armada,
#                        gamescope-session.target on SteamOS)
#   --no-root            skip the sudo steps (the button then needs other
#                        access, see README)
#   --no-enable          install, but do not enable or start anything
#   --uninstall          remove what an earlier install put in place
#   --purge              with --uninstall: also remove your settings
set -euo pipefail

SRC=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
PREFIX=$HOME/.local
SESSION_UNIT=
ROOT_STEPS=1
ENABLE=1
UNINSTALL=0
PURGE=0

die() { echo "install.sh: $*" >&2; exit 1; }
warn() { echo "  ! $*" >&2; }
say() { echo "== $*"; }

while (( $# )); do
  case "$1" in
    --prefix) PREFIX=${2:?}; shift ;;
    --session-unit) SESSION_UNIT=${2:?}; shift ;;
    --no-root) ROOT_STEPS=0 ;;
    --no-enable) ENABLE=0 ;;
    --uninstall) UNINSTALL=1 ;;
    --purge) PURGE=1 ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option $1 (see --help)" ;;
  esac
  shift
done

(( EUID != 0 )) || die "run this as the user who plays in Game Mode, not as root"
PREFIX=$(mkdir -p "$PREFIX" && cd "$PREFIX" && pwd)
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
ARMADA_MARK=$CONF_DIR/armada-bottom-screen-was-enabled
UNITS=(barry_launcher.service barry_launcher_inputd.service)
STATE_DIR=/run/user/$(id -u)/barry_launcher  # = barry_launcher_env's

unit_exists() { systemctl --user cat "$1" >/dev/null 2>&1; }

# --- uninstall ---------------------------------------------------------------
if (( UNINSTALL )); then
  [[ -f "$MANIFEST" ]] || die "no install recorded in $MANIFEST"
  say "stopping and disabling Barry Launcher"
  systemctl --user disable --now "${UNITS[@]}" 2>/dev/null || true
  root_files=()
  while read -r kind path; do
    case "$kind" in
      user) rm -rf -- "$path" ;;
      root) root_files+=("$path") ;;
    esac
  done < "$MANIFEST"
  if (( ${#root_files[@]} )); then
    say "removing system files (sudo): ${root_files[*]}"
    sudo rm -f -- "${root_files[@]}"
    sudo udevadm control --reload 2>/dev/null || true
  fi
  systemctl --user daemon-reload
  if [[ -f "$ARMADA_MARK" ]]; then
    say "turning Armada's bottom-screen session back on"
    systemctl --user enable "$ARMADA_UNIT" || warn "could not enable $ARMADA_UNIT"
    rm -f "$ARMADA_MARK"
  fi
  rm -f "$MANIFEST"
  if (( PURGE )); then
    rm -rf "$CONF_DIR" "${XDG_DATA_HOME:-$HOME/.local/share}/barry_launcher"
  else
    echo "Settings kept in $CONF_DIR (--purge removes them)."
  fi
  echo "Done. A reboot puts InputPlumber's AYN-button handling back, if it was changed."
  exit 0
fi

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
say "installing into $PREFIX"
mkdir -p "$CONF_DIR" "$UNIT_DIR" "$APPS_DIR" "$PREFIX/share" "$PREFIX/bin"
rm -rf "$LIBDIR" "$PREFIX/share/barry_launcher"  # replaced whole: no stale files
mkdir -p "$LIBDIR"
cp -R "$SRC/usr/lib/barry_launcher/." "$LIBDIR/"
chmod 0755 "$LIBDIR"/*
cp -R "$SRC/usr/share/barry_launcher" "$PREFIX/share/"
chmod -R u=rwX,go=rX "$PREFIX/share/barry_launcher"
install -m 0755 "$SRC/usr/bin/barry-launcher" "$PREFIX/bin/barry-launcher"

for u in "${UNITS[@]}"; do
  install -m 0644 "$SRC/usr/lib/systemd/user/$u" "$UNIT_DIR/$u"
done
install -m 0644 "$SRC/usr/share/applications/barry_launcher_desktop.desktop" \
  "$APPS_DIR/barry_launcher_desktop.desktop"
# pb-os's paths -> this install's (see the top of this file).
python3 - "$LIBDIR" "$PREFIX/share/barry_launcher" "$STATE_DIR" "$SESSION_UNIT" \
  "$LIBDIR" "$PREFIX/share/barry_launcher" "$APPS_DIR/barry_launcher_desktop.desktop" \
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

{
  echo "user $LIBDIR"
  echo "user $PREFIX/share/barry_launcher"
  echo "user $PREFIX/bin/barry-launcher"
  for u in "${UNITS[@]}"; do echo "user $UNIT_DIR/$u"; done
  echo "user $APPS_DIR/barry_launcher_desktop.desktop"
} > "$MANIFEST.new"

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
  printf '%s\n' "$rules" | sudo tee "$UDEV_RULE" >/dev/null
  sudo udevadm control --reload
  sudo udevadm trigger --action=change --subsystem-match=input --subsystem-match=misc
  echo "root $UDEV_RULE" >> "$MANIFEST.new"

  # The AYN Thor: InputPlumber reads the AYN button too; leave it to Barry.
  if [[ "$BARRY_BUTTON_DEVICE" == gpio-keys-ayn && -f "$IP_SRC" ]] && grep -q 'name: gpio-keys-ayn' "$IP_SRC"; then
    if [[ -e "$IP_DST" ]] && grep -q "$IP_TOOL" "$IP_DST" && ! grep -qx "root $IP_DST" "$MANIFEST" 2>/dev/null; then
      echo "  InputPlumber already leaves the AYN button alone ($IP_DST)."
    elif [[ -e "$IP_DST" ]] && ! grep -q "$IP_TOOL" "$IP_DST"; then
      warn "$IP_DST exists and was written by something else; left alone (the AYN button may not reach Barry)"
    else
      tmp=$(mktemp)
      python3 "$LIBDIR/$IP_TOOL" "$IP_SRC" "$tmp"
      sudo install -D -m 0644 "$tmp" "$IP_DST"
      rm -f "$tmp"
      echo "root $IP_DST" >> "$MANIFEST.new"
      echo "  InputPlumber now leaves the AYN button alone (after a reboot)."
    fi
  fi
else
  warn "--no-root: no udev rule; the button needs read access to its /dev/input device"
fi
mv "$MANIFEST.new" "$MANIFEST"

# --- Armada: one bottom-screen session at a time --------------------------------
if unit_exists "$ARMADA_UNIT" && systemctl --user is-enabled --quiet "$ARMADA_UNIT" 2>/dev/null; then
  say "turning off Armada's bottom-screen session (Plasma Mobile); --uninstall turns it back on"
  systemctl --user disable --now "$ARMADA_UNIT"
  touch "$ARMADA_MARK"
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
  remove:    $SRC/install.sh --uninstall
EOF
