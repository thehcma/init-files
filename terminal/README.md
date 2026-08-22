# Terminal.app prefs (macOS only)

Curated slice of **Terminal.app** preferences: profile **font** (Meslo LGS Nerd Font Mono 15 on the default **Basic** profile).

| Path / command | Role |
| --- | --- |
| `settings.json` | Canonical curated settings (checked in) |
| `install` / `terminal/install` | Live prefs → merge curated font into `com.apple.Terminal` |
| `_prefs.py` | Merge / font-check helpers |

Applied by default on Darwin `provision_init_files` / `refresh_init_files` (alongside iTerm). Or run `terminal/install` directly.

## What is tracked

- `Window Settings` → **Basic** profile:
  - **Font** Meslo LGS Nerd Font Mono (`MesloLGSNFM-Regular`) **15**
  - **FontAntialias** on

## What is not tracked

- Window frames, colors, keyboard maps, shell path, secure keyboard entry
- Non-Basic profiles (add to `settings.json` if needed)

## Font dependency

Same as iTerm: **Meslo LGS Nerd Font** in `~/Library/Fonts`. `terminal/install` offers `iterm2/install_meslo_nerd_font` when the face is missing.

## Apply

```bash
terminal/install
# or after editing settings.json:
~/.local/share/init-files/terminal/install
```

Quit Terminal (or open a new window) after install.
