# iTerm2 prefs (macOS only)

Curated slice of iTerm2 preferences: **font / size, colors, keyboard map, mouse / pointer**. Window frames, arrangements, and host/session noise are not tracked.

| Path / command | Role |
| --- | --- |
| `com.googlecode.iterm2.plist` | Canonical curated XML (checked in) |
| `meta.json` | Export metadata (iTerm version + host) for soft mismatch notes |
| `export` / `export_iterm_settings` | Live prefs → curated plist + meta |
| `install_meslo_nerd_font` | Download Meslo.zip → current user’s Fonts (no sudo) |
| `test` / `test_iterm_settings` | Apply repo prefs with backup; **revert on failure** |
| `upload_iterm_settings` | Commit + push curated plist/meta when they differ from `origin` |
| `refresh_iterm_settings` | Fetch `origin/main` and merge into live prefs when they differ |
| `_prefs.py` | Curate / merge / compare helpers |

Shell functions are Darwin-only (fail on Linux). Scripts stay runnable under `~/.local/share/init-files/iterm2/`. On macOS, `./provision_init_files` and `refresh_init_files` apply curated prefs by default (`--no-iterm` to skip; daily `-q` never applies). Or run `refresh_iterm_settings` / `iterm2/install` directly.

## What is tracked

- Profiles (`New Bookmarks`): fonts, ANSI/UI colors, `Keyboard Map`, mouse reporting, Option-key sends, etc.
  - **Left Option = Esc+** (so bash/fzf `Alt-C` / `\ec` works). **Right Option = Normal** (keep Option-C → `ç` on the right key).
  - **Shift+Enter** / **Option+Enter** → CSI-u (`[13;2u` / `[13;3u`) so Cursor Agent (and similar TUIs) insert a newline instead of submitting. Without these, iTerm often sends plain Return for Shift+Enter.
  - **Session-initiated window resize allowed** (`Disable Window Resizing` and `Disable Window Resizing by Unfocused Sessions` both false) so apps can resize without the “Allow it?” prompt — including from a split pane or background tab.
  - **Per-pane status bar** (tight packing) embedded in the pane title bar (`SeparateStatusBarsPerPane` + top position; `ShowPaneTitlesEvenIfOnlyOnePane`). Left: `\(user.agentsession)` (Cursor Agent short id from `cursor/statusline`; empty when not in an agent). Right: `\(user.hostlabel)` (`local` or hop hostname from bashrc / `cssh`/`cesh`/`cmsh`). Embedding hides iTerm’s title label — agent id must live in the status bar, not only OSC 0/1/2.
- Daily `refresh_init_files -q` compares live curated prefs to the clone plist and offers `refresh_iterm_settings` when they differ (macOS only; no auto-apply under `-q`).
- Global input: `PointerActions`, `FocusFollowsMouse`, Esc feedback toggles when present
- **Pane title + status bar placement**: `ShowPaneTitles`, `ShowPaneTitlesEvenIfOnlyOnePane`, `SeparateStatusBarsPerPane`, `StatusBarPosition` (top, so the host label sits in the pane title)
- **Applications in terminal may access clipboard** (`AllowClipboardAccess`) so OSC 52 / shell copy-to-clipboard is allowed without a prompt
- `Default Bookmark Guid`
- Soft metadata: iTerm version (+ export host) in `meta.json`

## What is not tracked

- `NSWindow Frame *`, saved arrangements / restore-on-launch
- Sparkle update state, `NoSync*`, AI settings, recents
- Profile launch command / working directory / default Rows×Columns

## Flow: change settings → export → upload

```bash
# Prefer quitting iTerm (Cmd-Q) first so defaults(1) sees a consistent prefs domain.
export_iterm_settings
upload_iterm_settings
```

## Flow: safe try on a new Mac → test (revert if broken)

```bash
test_iterm_settings          # from origin/main
# or: test_iterm_settings --local
```

1. Saves live prefs under `~/.local/state/init-files/iterm2-test/prefs-backup.plist`
2. Merges curated prefs from the repo
3. Soft-notes iTerm version mismatch (does not fail)
4. **Fails and restores** if iTerm.app is missing, required fonts are missing, or the merge did not stick
5. On success: keeps repo prefs (Cmd-Q / reopen iTerm)

## Flow: refresh when you already trust the clone

```bash
refresh_iterm_settings
```

## Font / app / version dependencies

| Check | Behavior |
| --- | --- |
| Required fonts missing | Warning + OS-tier install hint; interactive install/`refresh_iterm_settings` may offer `iterm2/install_meslo_nerd_font` (Meslo.zip → ~/Library/Fonts, no sudo); **`test_iterm_settings` fails and reverts** if still missing |
| iTerm.app missing | Warning + OS-tier install hint; **`test_iterm_settings` fails and reverts** |
| iTerm version ≠ export (`meta.json`) | Soft note only (older/newer); never fails the test |

| Tier | Meslo Nerd Font | iTerm.app |
| --- | --- | --- |
| macOS (any tier) | `iterm2/install_meslo_nerd_font` — Meslo.zip into **this user’s** `~/Library/Fonts` (no sudo; preferred). Avoid `brew install --cask font-meslo-lg-nerd-font` when Homebrew is owned by another account (fonts land in that owner’s Fonts). | Modern: `brew install --cask iterm2`; older: download from [iterm2.com](https://iterm2.com/downloads.html) (**no brew**) |
| Linux | same helper → `~/.local/share/fonts/MesloLGS` + `fc-cache` | n/a |

Profiles currently expect **MesloLGS Nerd Font** (`MesloLGSNFM-Regular`).
