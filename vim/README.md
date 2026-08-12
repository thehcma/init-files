# Vim config (cross-platform)

Canonical **Vim 9** config with [vim-plug](https://github.com/junegunn/vim-plug): airline statusline (git branch), Nerd Font glyphs, gitgutter, fugitive.

| Path | Role |
| --- | --- |
| `vimrc` | **One** tracked config for terminal vim (`v`) and MacVim/gvim (`vi`) |
| `~/.vimrc` | Symlink → this file (created by `./provision_init_files` or `refresh_vimrc`) |
| `~/.gvimrc` | **Not used** — backed up and removed so it cannot override `vimrc` |
| `~/.vim/autoload/plug.vim` | vim-plug (downloaded; not in git) |
| `~/.vim/plugged/` | Plugins (host-local; not in git) |
| `~/.vimrc.bak.<timestamp>` / `~/.gvimrc.bak.<timestamp>` | Backups of previous configs |
| `~/.local/state/init-files/vim-backup/` | Second copy of those backups |

GUI-only bits (e.g. `guifont`) live in the same `vimrc`, applied on `GUIEnter`. There is no separate tracked `gvimrc`.

Neovim is out of scope for v1.

## Install / refresh

```bash
# First time on a host (also run by a normal ./provision_init_files):
~/.local/share/init-files/provision_init_files

# Later — repair symlink, bootstrap plug if needed, PlugInstall + PlugUpdate:
refresh_vimrc
# optional: refresh_vimrc --fetch    # git fetch origin main first
# optional: refresh_vimrc --no-plugins
```

`./provision_init_files` **backs up** any existing regular-file `~/.vimrc` before replacing it with the symlink, **retires** `~/.gvimrc` the same way (one-file model), then bootstraps vim-plug and runs headless `PlugInstall` (warns and continues if that fails). `refresh_vimrc` fails loudly if plugin sync fails.

Daily `refresh_init_files -q` detects a missing/wrong `~/.vimrc` symlink or a leftover `~/.gvimrc` and offers `refresh_vimrc` (or `refresh_init_files` when other deployables also drifted).

## Fonts

Airline / devicons need a **Nerd Font** in the terminal (and MacVim `guifont`). Missing glyphs usually show as `?`. This fleet already uses Meslo LGS Nerd Font for iTerm.

Quick check (should look like branch/triangle icons, not `?`):

```bash
printf 'powerline: \ue0a0 \ue0b0 \ue0b2\n'
```

| Where you run vim | Font |
| --- | --- |
| iTerm (`v` / terminal vim) | Profile → Text → **MesloLGS Nerd Font Mono** (or `MesloLGSNFM-Regular`) |
| Cursor / VS Code integrated terminal | `"terminal.integrated.fontFamily": "MesloLGS Nerd Font Mono"` |
| MacVim (`vi` — GUI window) | `guifont` in the same `vimrc` (on `GUIEnter`); no separate `~/.gvimrc` |

| Tier | Hint |
| --- | --- |
| Modern macOS (Darwin ≥ 25) | `~/.local/share/init-files/iterm2/install_meslo_nerd_font` (Meslo.zip → ~/Library/Fonts; no sudo) |
| Older macOS | same helper (**no brew**) |
| Linux | same helper → `~/.local/share/fonts/MesloLGS` + `fc-cache` |
| Linux | Same zip → `~/.local/share/fonts` && `fc-cache -f` |

## Plugin set

- vim-airline + everforest theme — mode / file / **git branch**
- vim-devicons — glyphs
- vim-gitgutter — gutter signs
- vim-fugitive — `:Git` (`<leader>g`)
- vim-surround, vim-commentary
- preservim/vim-markdown — syntax + conceal (`conceallevel=2` on markdown)
- iamcco/markdown-preview.nvim — browser live preview (`<leader>m` / `:MarkdownPreview`; needs `node` via nvm)
- fzf.vim when `fzf` is on PATH (`<leader>f` / `b` / `/`)

Leader is space. `<leader>h` clears search highlight.
