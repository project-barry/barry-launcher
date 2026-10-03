#!/bin/bash
# uninstall.sh: remove Barry Launcher completely and give the bottom screen
# back to what had it before.
#
#   ./uninstall.sh [--purge | --keep-data] [--prefix DIR] [--yes]
#   barry-launcher uninstall [same options]   (works without this repo)
#
# Always removes: the services, the program files, the command, the menu
# entry, the udev rule and InputPlumber override it wrote (sudo), its logs
# and runtime files. Turns Armada's bottom-screen session back on (and
# starts it, if Game Mode is running) when Barry Launcher had turned it off.
#
# Your data: settings, dashboard skins, the browser's and Discord's profiles
# (logins, history) and Dino's best score. Asked about when run in a
# terminal; --purge deletes it, --keep-data keeps it. Kept without a
# terminal to ask in.
#
#   --prefix DIR   where it was installed, if the install record is gone
#                  (default ~/.local)
#   --yes          do not ask; with neither --purge nor --keep-data, keep data
set -euo pipefail

main() {
  local data_mode="" prefix="" assume_yes=0
  while (( $# )); do
    case "$1" in
      --purge) data_mode=purge ;;
      --keep-data) data_mode=keep ;;
      --prefix) prefix=${2:?}; shift ;;
      --yes|-y) assume_yes=1 ;;
      -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) die "unknown option $1 (see --help)" ;;
    esac
    shift
  done
  (( EUID != 0 )) || die "run this as the user Barry Launcher was installed for, not as root"

  local config_home=${XDG_CONFIG_HOME:-$HOME/.config}
  local data_home=${XDG_DATA_HOME:-$HOME/.local/share}
  local cache_home=${XDG_CACHE_HOME:-$HOME/.cache}
  local conf_dir=$config_home/barry_launcher
  local unit_dir=$config_home/systemd/user
  local manifest=$conf_dir/installed
  local units=(barry_launcher.service barry_launcher_inputd.service)
  local armada_unit=armada-bottom-screen.service

  # What was installed: the record, or else the default places.
  local user_paths=() root_paths=() dirs=() restore_armada=0 session_unit=""
  if [[ -f "$manifest" ]]; then
    local kind value
    while read -r kind value; do
      case "$kind" in
        user) user_paths+=("$value") ;;
        root) root_paths+=("$value") ;;
        armada) restore_armada=1 ;;
        "#"*) ;;
        session) session_unit=$value ;;
        dir) dirs+=("$value") ;;
      esac
    done < "$manifest"
    [[ -f "$conf_dir/armada-bottom-screen-was-enabled" ]] && restore_armada=1  # older installs
  else
    prefix=${prefix:-$HOME/.local}
    say "no install record; removing from the default places (prefix $prefix)"
    user_paths=("$prefix/lib/barry_launcher" "$prefix/bin/barry-launcher" "$prefix/bin/barry-app"
                "${units[@]/#/$unit_dir/}" "$data_home/applications/barry_launcher_desktop.desktop")
    [[ -e /etc/udev/rules.d/70-barry-launcher.rules ]] && root_paths+=(/etc/udev/rules.d/70-barry-launcher.rules)
    if grep -qsF "# installed by Barry Launcher's install.sh" /etc/inputplumber/devices.d/50-ayn_thor.yaml; then
      root_paths+=(/etc/inputplumber/devices.d/50-ayn_thor.yaml)
    fi
  fi

  local data_paths=()
  for p in "$conf_dir" "$data_home/barry_launcher"; do
    [[ -e "$p" ]] && data_paths+=("$p")
  done
  local dino_conf=""
  dino_conf=$(grep -lsx '\[dino\]' "$config_home"/QtProject/*.conf | head -1 || true)

  # Decide about the data before changing anything.
  if [[ -z "$data_mode" ]]; then
    if (( assume_yes )) || [[ ! -t 0 ]]; then
      data_mode=keep
    elif (( ${#data_paths[@]} )) || [[ -n "$dino_conf" ]]; then
      echo "Barry Launcher keeps your data here:"
      for p in "${data_paths[@]}"; do echo "  $p ($(du -sh "$p" 2>/dev/null | cut -f1))"; done
      [[ -n "$dino_conf" ]] && echo "  Dino's best score, in $dino_conf"
      echo "This includes the browser's and Discord's logins and history."
      local answer
      read -r -p "Delete it too? [y/N] " answer
      [[ "$answer" == [yY]* ]] && data_mode=purge || data_mode=keep
    fi
  fi

  say "stopping Barry Launcher"
  systemctl --user disable --now "${units[@]}" 2>/dev/null || true
  systemctl --user reset-failed "${units[@]}" 2>/dev/null || true
  # Links left in *.wants folders (if the unit files were deleted by hand),
  # and those folders once empty.
  local link
  while read -r link; do
    [[ -n "$link" ]] || continue
    rm -f -- "$link"
    rmdir -- "$(dirname "$link")" 2>/dev/null || true
  done < <(find "$unit_dir" -path '*.wants/barry_launcher*' -type l 2>/dev/null)
  # systemctl disable leaves the (now empty) folders its enable made.
  local w
  for w in ${session_unit:+"$unit_dir/$session_unit.wants"} "$unit_dir/default.target.wants" \
    "$unit_dir/gamescope-session.target.wants" "$unit_dir/gamescope-session-plus@steam.service.wants"; do
    rmdir -- "$w" 2>/dev/null || true
  done

  say "removing program files"
  for p in "${user_paths[@]}"; do
    # Never your data, even if an older install record lists it.
    [[ "${p%/}" == "$conf_dir" || "${p%/}" == "$data_home/barry_launcher" ]] && continue
    [[ -n "$p" && "$p" == *barry* ]] && rm -rf -- "$p"
  done
  rm -rf -- "$cache_home/barry_launcher" "/run/user/$(id -u)/barry_launcher"
  systemctl --user daemon-reload 2>/dev/null || true

  if (( ${#root_paths[@]} )); then
    say "removing system files (sudo): ${root_paths[*]}"
    sudo rm -f -- "${root_paths[@]}"
    sudo udevadm control --reload 2>/dev/null || true
    sudo udevadm trigger --action=change --subsystem-match=input --subsystem-match=misc 2>/dev/null || true
  fi

  # Armada: its bottom-screen session back, as it was before the install.
  if systemctl --user cat "$armada_unit" >/dev/null 2>&1; then
    if (( restore_armada )); then
      say "turning Armada's bottom-screen session back on"
      systemctl --user enable "$armada_unit" || warn "could not enable $armada_unit"
      if [[ -n "$session_unit" ]] && systemctl --user is-active --quiet "$session_unit"; then
        systemctl --user start "$armada_unit" || warn "could not start $armada_unit; it starts with Game Mode"
      fi
    elif ! systemctl --user is-enabled --quiet "$armada_unit" 2>/dev/null; then
      echo "  Armada's bottom-screen session is off; it was off before Barry Launcher, or the"
      echo "  record of it is gone. Turn it on in Armada's Decky plugin, or:"
      echo "    systemctl --user enable --now $armada_unit"
    fi
  fi

  if [[ "$data_mode" == purge ]]; then
    say "deleting your Barry Launcher data"
    rm -rf -- "${data_paths[@]}"
    if [[ -n "$dino_conf" ]]; then
      python3 - "$dino_conf" <<'PY'
import os, sys
path = sys.argv[1]
out, skip = [], False
for line in open(path, encoding="utf-8"):
    s = line.strip()
    if s.startswith("[") and s.endswith("]"):
        skip = s == "[dino]"
    if not skip:
        out.append(line)
text = "".join(out).strip()
if text:
    open(path, "w", encoding="utf-8").write(text + "\n")
else:
    os.remove(path)
PY
    fi
  else
    rm -f -- "$manifest" "$conf_dir/armada-bottom-screen-was-enabled"
    if (( ${#data_paths[@]} )) || [[ -n "$dino_conf" ]]; then
      echo "  Your data was kept: ${data_paths[*]}${dino_conf:+ (and [dino] in $dino_conf)}"
      echo "  Delete it later with: rm -rf ${data_paths[*]}"
    fi
  fi

  # Folders the install created, deepest first, if nothing else is in them.
  local d
  while read -r d; do
    [[ -n "$d" ]] && rmdir -- "$d" 2>/dev/null || true
  done < <(printf '%s\n' "${dirs[@]+"${dirs[@]}"}" | awk '{print length, $0}' | sort -rn | cut -d' ' -f2-)

  if command -v flatpak >/dev/null && flatpak info --user org.signal.Signal >/dev/null 2>&1; then
    echo "  Signal (Flatpak) is still installed; Barry Launcher may have installed it. To remove it:"
    echo "    flatpak uninstall --user --delete-data org.signal.Signal"
  fi
  local ip_removed=0
  for p in "${root_paths[@]}"; do [[ "$p" == *inputplumber* ]] && ip_removed=1; done
  echo "Barry Launcher is uninstalled."
  (( ip_removed )) && echo "Reboot so InputPlumber takes the AYN button back."
  return 0
}

die() { echo "uninstall: $*" >&2; exit 1; }
warn() { echo "  ! $*" >&2; }
say() { echo "== $*"; }

# All in a function: this file may be the installed copy, which deletes
# itself partway through.
main "$@"
exit
