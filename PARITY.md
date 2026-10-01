# Keeping in step with pb-os

The built-in Barry Launcher in pb-os is the main version. This repo must
match it, apart from the portable changes.

## How it is laid out

- `tools/pb-os-map.txt`: the pb-os files this repo takes, and where they go
  here.
- `PB_OS_COMMIT`: the pb-os commit they were taken from.
- `patches/portable.patch`: every difference between those files and `usr/`
  here, including the files only this repo has (`barry_launcher_env`,
  `barry_launcher_buttond`, `barry-launcher`).
- `tools/pb-os-watch.txt`: pb-os files this repo does not take, but whose
  behaviour it copies by hand. For example, `barry_launcher_buttond` copies
  the AYN-button part of `sm8550-thor-backlightd`.

The patch is kept small on purpose:
- **Untouched:** the QML (except `Desktop.qml`), `barry_launcher_shelld`,
  `barry_launcher_inputd`, the dashboard script and the desktop entry are
  byte-for-byte pb-os's.
- **Paths:** pb-os's paths (`/usr/lib/barry_launcher`,
  `/usr/share/barry_launcher`, `/run/sm8550-thor/{overlay,home}`) stay in
  the files. `install.sh` rewrites them in the installed copies.
- **`qml6`:** `barry_launcher_env` puts a `qml6` link on PATH where the
  runner has another name.

New pb-os code that uses those paths, or `qml6`, therefore needs no patch
change.

## Commands

All of them look for pb-os in `../SteamOS-ARM-SM8650`; set `PB_OS=/path` to
point elsewhere. Run them on Linux or macOS.

```sh
tools/check-parity.sh [REF]     # are we in step with pb-os REF (default main)?
tools/sync-from-pb-os.sh [REF]  # take pb-os REF's files, re-apply the patch
tools/make-patch.sh             # after editing usr/ here: rewrite the patch
```

`check-parity.sh` does two things:
1. **Checks the patch:** usr/ must equal pb-os at `PB_OS_COMMIT` plus the
   patch. If not, run `make-patch.sh`.
2. **Lists newer pb-os commits** to the taken files (sync them) and to the
   watched files (port by hand). It also notes uncommitted pb-os changes,
   which don't count until they are committed.

It exits 0 when in step, 1 when the patch is off, and 2 when pb-os has
something newer.

## Updating after a pb-os change

1. Commit the change in pb-os.
2. Here, run `tools/sync-from-pb-os.sh main`.
3. **If a hunk no longer fits**, it is left as a `.rej` file next to its file
   in `usr/`. Make that change by hand, delete the `.rej`, and run
   `tools/make-patch.sh`.
4. Check whether any newer commit touches a watched file (`check-parity.sh`
   lists them). If one is Barry-related, port it by hand. Example: a change
   to the AYN button's timing in `sm8550-thor-backlightd` goes into
   `barry_launcher_buttond`.
5. `git diff`, then `tools/check-parity.sh` should report everything in step.
   Commit `usr/`, `PB_OS_COMMIT` and `patches/` together, naming the pb-os
   commit in the message.

## Changing the portable version

Edit `usr/` here, run `tools/make-patch.sh`, and commit both. Barry Launcher
changes that matter on pb-os too belong in pb-os first; sync them over from
there.
