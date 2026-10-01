# Barry Launcher

A home screen for the AYN Thor's bottom screen while SteamOS's Game Mode runs
on the top one. This repo is the version you install yourself, for Armada and
other ARM ports of SteamOS.

> [!WARNING]
> **Untested.** This portable version has not run on a device yet. It will be
> tested once a second AYN Thor is available. Until then, expect rough edges,
> and keep a way to undo it (`./install.sh --uninstall`). The tested version
> is the one built into [pb-os](https://github.com/project-barry/pb-os) Thor
> images.

## What it does

- **Home screen** on the bottom screen, with tiles for a browser, Discord
  (web app), Signal (Flatpak, installed on first use), a trackpad and a
  keyboard for the top screen.
- **On-screen keyboard** that pops up when a text field on the bottom screen
  gets focus.
- **Top-screen trackpad and keyboard**, so you can use the Steam UI or a game
  from the bottom screen. A Desktop Mode version is in the applications menu
  (KDE).
- **Performance dashboard**: a short press of the AYN button shows it,
  another hides it. It shows FPS, CPU, GPU, temperatures, fan, power, memory
  and battery, plus quick controls. Skins are plain QML (see
  [the skin guide](usr/share/barry_launcher/dashboard/README.md)).
- **Hold the AYN button** to go back to the home screen from any app.

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
- the Dual Screen Decky plugin (bottom screen on/off, per-screen dimmers,
  Barry's keyboard in place of Steam's)
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
./install.sh --uninstall        # remove it (keeps your settings)
./install.sh --uninstall --purge
barry-launcher config           # the settings in effect (~/.local/bin)
barry-launcher dashboard        # toggle the dashboard without the button
barry-launcher home
journalctl --user -u barry_launcher -u barry_launcher_inputd
```

To update, `git pull` and run `./install.sh` again.

### On Armada

Armada runs Plasma Mobile on the bottom screen (`armada-bottom-screen.service`).
Only one session can hold the bottom screen at a time, so `install.sh`
turns Armada's off, and `--uninstall` turns it back on. Armada's own
bottom-screen switch (in its Decky plugin) turns Plasma Mobile back on. Use
`--uninstall` instead.

### Other devices

The defaults are the AYN Thor's. Barry Launcher only starts where the device
tree matches `BARRY_DEVICE_MATCH` (`ayn,thor`). For another dual-screen
handheld, set the bottom connector, size, orientation, button and device
match in `~/.config/barry_launcher/barry-launcher.conf`, then run
`./install.sh` again so the udev rule follows the button. The layout is drawn
for the Thor's 1240×1080 panel and scales to others.

## License and credits

GPL-2.0, like pb-os, where Barry Launcher was written ([LICENSE](LICENSE)).
`barry_launcher_run_bottom` follows Armada's `armada-run-bottom`
(GPL-2.0-or-later). Built by lavachemist for project-barry.

Written with Claude Code (Anthropic, model Claude Opus 5.5) under the
direction of lavachemist.
