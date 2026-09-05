# Mos scroll overrides (macOS only)

Curated slice of **[Mos](https://mos.caldis.me/)** (`com.caldis.Mos`) preferences: **per-app scroll overrides** that stop Mos from smoothing terminal emulators.

| Path / command | Role |
| --- | --- |
| `settings.json` | Canonical curated overrides (checked in) — `{path, displayName, smooth}` per app |
| `install` / `mos/install` | Merge curated overrides into `com.caldis.Mos` (backup + Mos relaunch) |
| `_prefs.py` | Expand curated entries into full Mos `Application` objects; merge / compare helpers |

Applied by default on Darwin `provision_init_files` / `refresh_init_files` (alongside iTerm2 + Terminal.app; `--no-iterm` skips all three). Or run `mos/install` directly.

## Why

Mos smooths scroll for every app (blocklist mode, `allowlist` = false). A terminal emulator draws its own content view and, in alt-screen apps (vim / htop / interactive CLIs / the Claude CLI), translates the wheel into arrow-key presses — one text row is the smallest possible step. Mos's interpolated stream of sub-line deltas then collapses into rapid volleys of arrow keys, so the view leaps and settles. Turning Mos smoothing **off for the terminal** lets its own scroll accumulator (e.g. iTerm2's `UseModernScrollWheelAccumulator`) drive line motion directly — bounded lines per notch, evenly paced.

## What is tracked

- `applications` (the per-app list): one entry per curated app, written as
  `inherit` = false + a full `scroll` block. Mos leaves smoothing on for an app
  unless the entry disables it explicitly and stops inheriting global settings.
- `smooth` (and the axis toggles) forced **off**; every other scroll field
  (`reverse`, `deadZone`, `step`, `speed`, …) **mirrored from the live global
  Mos settings** at merge time, so the terminal keeps global feel otherwise.

## What is not tracked

- Global Mos settings (speed / step / duration / smooth / reverse / dead zone,
  hotkeys, button bindings, launch-at-login) — personal tuning, left alone.
- `allowlist` mode, per-app entries for non-terminal apps you add yourself
  (merge is by `path`; unlisted entries are preserved untouched).

## Staleness

The mirrored fields (`reverse`, `deadZone`, …) are snapshotted from global at
install time. They only matter when smoothing is on — which it isn't for these
apps — except `reverse` / `deadZone`. If you change global scroll direction or
dead zone, re-run `mos/install` (or `refresh_init_files`) to re-sync the
terminal entries.

## Apply

```bash
mos/install
# or after editing settings.json:
~/.local/share/init-files/mos/install
```

`mos/install` quits Mos, imports the merged prefs, and relaunches Mos (it
rewrites its own prefs on quit, so a live import would be clobbered). It is a
no-op when Mos is not installed or the overrides are already applied.
