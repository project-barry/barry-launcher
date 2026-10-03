# Barry Launcher

A home screen for the AYN Thor's bottom screen while SteamOS's Game Mode runs
on the top one. This repo is the version you install yourself, for Armada and
other ARM ports of SteamOS.

> [!WARNING]
> **Untested.** This portable version has not run on a device yet. It will be
> tested once a second AYN Thor is available. Until then, expect rough edges.
> It removes cleanly at any time with `barry-launcher uninstall` (see
> [Uninstall](#uninstall)). The tested version is the one built into
> [pb-os](https://github.com/project-barry/pb-os) Thor images.

## What it does

- **Home screen** on the bottom screen, with tiles for a browser, Discord
  (web app), Signal (Flatpak, installed on first use), a trackpad and a
  keyboard for the top screen, and Dino.
- **Dino**: an endless runner after Google Chrome's dinosaur game (see
  [credits](#license-and-credits)). Tap to jump; it keeps your best score.
- **On-screen keyboard** that pops up when a text field on the bottom screen
  gets focus.
- **Top-screen trackpad and keyboard**, so you can use the Steam UI or a game
  from the bottom screen. It is one app: a trackpad with keys that slide up
  below it and away again. The Trackpad tile opens it as a full trackpad,
  the Keyboard tile with the keys up, and a trackpad click on a text field
  in an app on the top screen brings the keys up (apps that report focus
  over the accessibility bus, like Firefox; not Steam's own fields or most
  games). A Desktop Mode version is in the applications menu (KDE).
- **Performance dashboard**: a short press of the AYN button shows it,
  another hides it. It shows FPS, CPU, GPU, temperatures, fan, power, memory
  and battery, plus quick controls. Skins are plain QML (see
  [the skin guide](usr/share/barry_launcher/dashboard/README.md)).
- **Hold the AYN button** to go back to the home screen from any app.
- **Apps anyone can make**: a QML app zipped with a small `barry-app.json`
  installs with `barry-app install app.zip` and gets its own tile.
  [barry-launcher-apps](https://github.com/project-barry/barry-launcher-apps)
  has an example and a wiki on making them. (pb-os installs them from its
  Decky plugin too; that plugin isn't part of this repo.)

## How it relates to pb-os

pb-os keeps its own tightly integrated Barry Launcher. This repo follows that
version rather than replacing it: the files are pb-os's, unchanged where
possible, and every difference is in one patch
([`patches/portable.patch`](patches/portable.patch)). `PB_OS_COMMIT` names
the pb-os commit this repo matches. [PARITY.md](PARITY.md) explains how to
check and update it.

What the portable version changes:

| pb-os | here |
|---|---|
| Files in `/usr` (part of the image) | Installed under `~/.local`, so a read-only `/usr` is fine and OS updates keep it |
| Thor values written into the code | A settings file ([`barry-launcher.conf.example`](barry-launcher.conf.example)), with the Thor's values as defaults; on Armada, read from Armada's device profile |
| The AYN button is read by the root `sm8550-thor-backlightd` | Read by `barry_launcher_buttond`, a user process that runs only during Game Mode |
| Fan and lighting quick controls through `sm8550-thor-controlsd` | Used only if that service's socket exists; otherwise the dashboard leaves those controls out |
| Starts with `gamescope-session.target` | Starts with whichever unit runs Game Mode (Armada: `gamescope-session-plus@steam.service`) |

Not included, because in pb-os they belong to other parts of the Thor
support:
- the Barry Launcher Decky plugin (bottom screen on/off, per-screen
  dimmers, Barry's keyboard in place of Steam's, including for trackpad
  clicks on Steam's text fields, and the home screen's app order)
- one brightness slider for both screens
- waking Steam's idle dim when you touch the bottom screen

## Requirements

- **Game Mode lends the bottom screen.** Game Mode's gamescope must be
  started with `--lease-connector <bottom connector>`, and must support
  `--drm-lease-client` (DRM lease patches). Armada and pb-os Thor images do
  this. Other ports need those gamescope patches and session settings first.
- Python 3 with PyGObject and AT-SPI (`gi`, `Atspi 2.0`)
- A Qt 6 `qml` runner with QtQuick (`qml6`, or `qml-qt6` on Fedora/Armada)
- `xdotool`, `xprop`
- Firefox for the browser and Discord tiles; Flatpak for Signal

`install.sh` checks these and warns about anything missing.

## Install

As the user who plays in Game Mode (not root):

```sh
git clone https://github.com/project-barry/barry-launcher.git
cd barry-launcher
./install.sh
```

It asks for `sudo` for two system files:
- **a udev rule:** lets your user read the AYN button and create the
  trackpad's uinput devices
- **an InputPlumber override (AYN Thor only):** InputPlumber stops handling
  the AYN button, so Barry Launcher gets it. Reboot afterwards.

`--no-root` skips both. Barry Launcher starts with Game Mode.

```sh
barry-launcher config           # the settings in effect (in ~/.local/bin)
barry-launcher dashboard        # toggle the dashboard without the button
barry-launcher home
barry-launcher status           # services running? InputPlumber copy current?
journalctl --user -u barry_launcher -u barry_launcher_inputd
```

To update, `git pull` and run `./install.sh` again. It replaces the old copy
completely and keeps your data.

## Uninstall

```sh
barry-launcher uninstall
```

You don't need this repo for that; the command carries its own copy of the
uninstaller. If the command is gone too, run `./uninstall.sh` from a fresh
clone.

It removes everything the install put in place:
- the services, the program files, the `barry-launcher` command and the
  menu entry, plus any folders the install created for them
- the udev rule and the InputPlumber override (with `sudo`). **Reboot
  afterwards** so InputPlumber handles the AYN button again
- logs and runtime files

On Armada, it also turns Armada's own bottom-screen session (Plasma Mobile)
back on, and starts it right away if Game Mode is running. It does this only
if it was on before Barry Launcher was installed.

It then asks whether to delete your data as well:
- your settings and dashboard skins
- the browser's and Discord's profiles, including logins and history
- Dino's best score

To decide up front, pass `--purge` (delete it) or `--keep-data` (keep it).
Without a terminal to ask in, it keeps your data and prints where it is.

Signal is a Flatpak that Barry Launcher may have installed for you. It stays
installed, because you may use it elsewhere; the uninstaller prints the
command to remove it.

### On Armada

Armada runs Plasma Mobile on the bottom screen (`armada-bottom-screen.service`).
Only one session can hold the bottom screen at a time, so `install.sh`
turns Armada's off, and uninstalling turns it back on. Don't use Armada's
own bottom-screen switch (in its Decky plugin) while Barry Launcher is
installed: it would start Plasma Mobile alongside Barry. To go back to
Plasma Mobile, uninstall Barry Launcher.

The InputPlumber override is a copy of Armada's AYN Thor controller file,
minus the AYN button. If an Armada update changes that file, `barry-launcher
status` says so; run `./install.sh` again to refresh the copy, or uninstall
to drop it.

### Other devices

The defaults are the AYN Thor's. Barry Launcher only starts where the device
tree matches `BARRY_DEVICE_MATCH` (`ayn,thor`). For another dual-screen
handheld, set the bottom connector, size, orientation, button and device
match in `~/.config/barry_launcher/barry-launcher.conf`, then run
`./install.sh` again so the udev rule follows the button. The layout is drawn
for the Thor's 1240×1080 panel and scales to others.

## License and credits

GPL-2.0, like pb-os, where Barry Launcher was written ([LICENSE](LICENSE)).
Built by lavachemist for project-barry.

- **Dino** is after Google Chrome's Dinosaur Game (2014), created by
  **Sebastien Gabriel, Alan Bettes and Edward Jung** of Google's Chrome team.
  Its source is in Chromium, BSD-licensed, © The Chromium Authors:
  [components/neterror/resources/dino_game](https://source.chromium.org/chromium/chromium/src/+/main:components/neterror/resources/dino_game/).
  Barry Launcher's version ([`Dino.qml`](usr/share/barry_launcher/shell/Dino.qml))
  is written anew in QML; it has no Chromium code or sprite images.
- `barry_launcher_run_bottom` follows Armada's `armada-run-bottom`
  (GPL-2.0-or-later).
- The Firefox, Discord and Signal outlines in `Icon.qml` come from
  [Tabler Icons](https://github.com/tabler/tabler-icons) (MIT).

Written with Claude Code (Anthropic, model Claude Opus 5.5) under the
direction of lavachemist.
