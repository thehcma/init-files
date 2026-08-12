# init-files

Canonical interactive **bash** init for macOS (Darwin 21.6+) and Linux (Ubuntu, CentOS, Rocky through 8.10). Shared via symlink; per-host tool paths are generated locally.

| Read this when… | Go to |
| --- | --- |
| First setup / refresh / install flags | sections below |
| History, Tab completion, `**` globs, fzf, bash upgrades | **[docs/shell-ux.md](docs/shell-ux.md)** |
| iTerm2 font / colors / keys (macOS) | **[iterm2/README.md](iterm2/README.md)** (`export_iterm_settings` / `upload_iterm_settings` / `test_iterm_settings` / `refresh_iterm_settings`) |
| Vim 9 + plugins (cross-platform) | **[vim/README.md](vim/README.md)** (`refresh_vimrc`) |
| Agent / platform-isolation rules | [AGENTS.md](AGENTS.md) |
| House + GitHub SSH materials | [ssh/README.md](ssh/README.md) |

## Contents

- [On-disk layout](#on-disk-layout)
- [Interactive shell (quick taste)](#interactive-shell-quick-taste)
- [Process: first-time installation](#process-first-time-installation)
- [Process: refreshing from GitHub](#process-refreshing-from-github)
- [When to re-run `provision_init_files` vs `refresh_init_files`](#when-to-re-run-provision_init_files-vs-refresh_init_files)
- [Process: migrate an existing host](#process-migrate-an-existing-host-old-copy--symlink)
- [Platform notes](#platform-notes)
- [House SSH](#house-ssh)

---

## On-disk layout

| Path | Role |
| --- | --- |
| `~/.local/share/init-files` | Git clone of this repo (XDG data). Source of truth for `bashrc` / `provision_init_files` / `bootstrap_host`. |
| `~/.bashrc` | **Symlink** → `~/.local/share/init-files/bashrc` |
| `~/.config/init-files/tools.<hostname>` | Absolute tool paths from `provision_init_files` (NFS-safe; legacy `tools` still read) |
| `~/.config/init-files/no-dev.<hostname>` | Presence = **this host** is non-dev (NFS-safe; plain install/refresh keep it) |
| `~/.config/init-files/github-https.<hostname>` | Presence = **this host** uses GitHub HTTPS (no https→ssh `insteadOf`) |
| `~/.config/init-files/github-ssh.<hostname>` | Presence = **this host** prefers SSH even when `gh` is logged in |
| `~/.local/state/init-files/` | Refresh stamp / state (XDG state) |
| `~/.local/state/bash/` | Per-session history + `history.all` archive — see [shell UX](docs/shell-ux.md) |
| `docs/shell-ux.md` (in the clone) | Operator guide: history, completion, globs, fzf, `check_tool_versions` |

Do not put the clone under `~/.config/` — that tree is for host-local config (`tools` only). Shared content lives in `~/.local/share/init-files`.

**`<hostname>` scope key:** same label as the shell prompt **and** pipx layout (`~/.local/opt/pipx/<hostname>/`). On macOS that is **`scutil --get ComputerName`** (not Bonjour `LocalHostName` / `hostname -s`, which can pick up conflict suffixes). On Linux it is the short hostname. `provision_init_files` migrates preference files and pipx trees from legacy names (`LocalHostName`, `hostname -f`/`-s`) onto this key when they differ.

```
~/.bashrc  ──symlink──►  ~/.local/share/init-files/bashrc   (tracked)
                         ~/.local/share/init-files/provision_init_files  (tracked)
                         ~/.local/share/init-files/docs/shell-ux.md
~/.config/init-files/tools.<hostname>                       (generated per host; NFS-safe)
~/.config/init-files/no-dev.<hostname>                      (optional; remembered per host)
~/.config/init-files/github-https.<hostname>                (optional; HTTPS GitHub on this host)
~/.config/init-files/github-ssh.<hostname>                  (optional; force SSH despite gh auth)
~/.config/init-files/nfs-hosts                              (optional; live host list for cleanup)
~/.local/opt/pipx/<hostname>/                               (per-host pipx; same scope key)
~/.local/state/bash/history.all                             (shared command history archive)
```

Editing `~/.bashrc` edits the file in the clone. A successful `refresh_init_files` updates that clone from GitHub; the symlink does not need to be rewritten unless it was replaced by a regular file.

Homebrew-resolved paths are used only on **macOS 26+ (Darwin 25+)**. Older macOS installs use system/Xcode paths only (Homebrew shims are rejected). On those older releases `brew install` is often impractical: many formulae are no longer supported, and dependency builds can take forever — so init-files never recommends brew there even if Homebrew happens to be installed. On modern macOS, interactive `./provision_init_files` can offer to install Homebrew and missing brew packages (required, then optional).

---

## Interactive shell (quick taste)

Full examples and behavior: **[docs/shell-ux.md](docs/shell-ux.md)**.

| Feature | What it feels like |
| --- | --- |
| `globstar` | `rm -rf **/__pycache__` — recursive `**` globs |
| `autocd` | Type a directory name (no `cd`) to enter it |
| Better Tab | Case-insensitive; lists ambiguous matches on first Tab; optional bash-completion |
| fzf (if installed) | `Ctrl-R` fuzzy history, `Ctrl-T` files, `Alt-C` directories; modern macOS: bat/lsd previews + `fif` |
| Shared history | New tabs already know commands from other sessions via `history.all` |
| `check_tool_versions` | Daily status for bash/git/gh/… plus install hints for missing **fzf** / **bash-completion** |
| `init_files_doctor` | One-shot deploy sanity (symlink, tools, pipx, GitHub transport) |

```bash
check_tool_versions          # includes bash on a current report
init_files_doctor            # OK/WARN/FAIL summary
shopt -p globstar autocd     # expect -s on bash ≥ 4
```

Optional shell UX: **modern macOS** Homebrew **bash** + **bash-completion@2** are required (offered by `./provision_init_files`); also `brew install fzf bat lsd ripgrep`. **Linux** `sudo apt install fzf bat lsd ripgrep` (or dnf). Then `./provision_init_files` + new shell. Enables fzf previews (`bat`/`lsd`) and `fif` (rg→fzf). `prompt_fancy` offers to install starship for this OS when missing.

---

## Process: first-time installation

Do this once per host (or after wiping the clone / tools file). Prefer **`gh auth login` (HTTPS)**; use `--key-from` for the house key (house hops) without forcing GitHub SSH; use `--github-ssh` only when HTTPS is unavailable.

### Preferred: public `bootstrap_host` (download, then run)

Private house SSH + user policy stay in a **private config overlay** (`~/.local/share/config`; git URL prompted / `INIT_FILES_CONFIG_REPO`, remembered in `~/.config/init-files/config-repo`). Generic init-files is prepared for a **public** repo so bootstrap works via curl without auth for the dotfiles themselves.

**Exact steps on the new host:**

```bash
# 1) Download (preferred over curl|bash — clearer errors)
curl -fsSL https://raw.githubusercontent.com/OWNER/init-files/main/bootstrap_host \
  -o /tmp/bootstrap_host
chmod +x /tmp/bootstrap_host

# 2) Run — interactive chooser defaults to gh auth (HTTPS)
/tmp/bootstrap_host
# minimal:  /tmp/bootstrap_host --no-dev
# house key only (GitHub stays HTTPS if gh logged in):  /tmp/bootstrap_host --key-from HOST
# force GitHub SSH:  /tmp/bootstrap_host --github-ssh
```

Interactive prompts (when no transport flag / remembered preference):

1. **gh auth login (HTTPS)** — recommended; may offer `brew install gh` on modern macOS, then runs `gh auth login`
2. **SSH — copy house key** from a donor host (prompts for `HOST`, e.g. `user@other-host`) — also selects GitHub SSH; if GitHub rejects house RSA and a personal ed25519 GitHub key is missing, bootstrap falls back to HTTPS when `gh` can authenticate
3. **SSH — key already on this machine**

`--key-from HOST` alone only fetches the house key; GitHub transport still follows `gh` auth / flags / remembered prefs (HTTPS preferred).

When house SSH materials are desired, bootstrap/provision may also prompt for your **private config overlay** git URL (remembered; never hardcoded in this repo).

**3) Only after** the `=== bootstrap_host verify ===` block shows `bashrc: … OK`:

```bash
source ~/.bashrc
```

`source ~/.bashrc` before a successful verify does nothing useful (no symlink yet).

Confirm:

```bash
ls -l ~/.bashrc          # -> …/init-files/bashrc
git -C ~/.local/share/init-files rev-parse --short HEAD
type refresh_init_files
```

If a previous attempt already left the house key on this host and you want SSH:

```bash
/tmp/bootstrap_host --github-ssh      # or choose option 3
# after verify OK:
source ~/.bashrc
```

When you change `bootstrap_host` here, update the public raw URL host so curl bootstrap stays current.

### scp fallback (no curl)

```bash
scp ~/.local/share/init-files/bootstrap_host newhost:/tmp/
# on newhost:
chmod +x /tmp/bootstrap_host
/tmp/bootstrap_host                 # chooser: prefer gh auth
# or: /tmp/bootstrap_host --key-from HOST
# after verify OK:
source ~/.bashrc
```

### Manual fallback (without `bootstrap_host`)

#### 0a. Prefer HTTPS with gh (recommended)

```bash
# modern macOS: brew install gh   # if needed
gh auth login
git clone https://github.com/OWNER/init-files.git ~/.local/share/init-files
~/.local/share/init-files/provision_init_files --github-https
source ~/.bashrc
```

#### 0b. Provision GitHub SSH access (when HTTPS / gh is not an option)

```bash
# On an already-working host (example):
# scp ~/.ssh/<house-or-github-key>{,.pub} newhost:~/.ssh/
# On the new host:
chmod 700 ~/.ssh
chmod 600 ~/.ssh/<private-key>
chmod 644 ~/.ssh/<private-key>.pub
```

Bootstrap git to rewrite HTTPS GitHub URLs to SSH:

```bash
git config --global url."git@github.com:".insteadOf "https://github.com/"
```

Add GitHub’s host key and a `Host github.com` block (`User git`, IdentityFiles for keys that exist). After the clone exists, `./provision_init_files` does this from the private config overlay when present; for the **first** clone you can either:

- run the two commands above, trust github.com on first connect, and ensure `~/.ssh/config` has:

```sshconfig
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github
    IdentityFile ~/.ssh/<house-key>
    IdentitiesOnly yes
```

- or copy overlay `config.github` from another host’s `~/.local/share/config/.ssh/` into `~/.ssh/config.d/` with `Include ~/.ssh/config.d/*.conf` enabled.

Unlock the key and verify:

```bash
# Prefer the IdentityFile that works on this host (ed25519 often needed on OpenSSH 8 / FIPS):
ssh-add -t 4h ~/.ssh/id_ed25519_github 2>/dev/null \
  || ssh-add -t 4h ~/.ssh/<house-key>
ssh -T git@github.com
# success looks like: Hi <user>! You've successfully authenticated...
```

#### 1. Clone the repo

```bash
git clone https://github.com/OWNER/init-files.git ~/.local/share/init-files
# equivalent over SSH once insteadOf is set:
# git clone git@github.com:OWNER/init-files.git ~/.local/share/init-files
```

Requires `git` and network access. For SSH mode, also the GitHub SSH key from step 0b. Prefer HTTPS + `gh auth` when available (step 0a / `bootstrap_host` chooser).

#### 2. Run `provision_init_files`

```bash
~/.local/share/init-files/provision_init_files
```

Flags (also accepted by `bootstrap_host` and forwarded to `provision_init_files`):

| Flag | Meaning |
| --- | --- |
| `-f` / `--force` | Install even if required tools are missing |
| `-q` / `--quiet` | Less status output |
| `--no-dev` | Do not require development tools (`git`, `python3`, `make`, `patch`, `gdb`, `colordiff`); still record them when present. Core tools (`ssh*`, `curl`, `vim`, `gpg`, `cmp`) stay required. **Persists** this host as non-dev. |
| `--dev` | Require development tools again; **clears** the saved non-dev preference. |
| `--github-https` | Use HTTPS for GitHub git (clear https→ssh `insteadOf`). **Persists** for this host (`github-https.<hostname>`). Also auto-selected when `gh` is authenticated and SSH was not remembered. Same flag on `refresh_init_files`. See [Where the flags are available](#where-the-flags-are-available). |
| `--github-ssh` | Use SSH via `insteadOf`. **Persists** as `github-ssh.<hostname>` so gh auth does not flip the host back to HTTPS. Same flag on `refresh_init_files`. |
| `--no-iterm` | On macOS, skip merging curated iTerm2 prefs (default: merge when not `-q`). Same flag on `refresh_init_files`. |
| `--iterm` | Merge curated iTerm2 prefs on macOS (default when not `-q`; kept for compatibility). |
| `-h` / `--help` | Usage |

If neither `--no-dev` nor `--dev` is passed, `provision_init_files` honors a previously saved non-dev preference (so re-running plain `provision_init_files` on a minimal host stays non-dev). Same for `--github-https` / `--github-ssh` and the saved GitHub transport preference. When no transport flag is remembered, **`gh auth status` succeeding prefers HTTPS**.

What `provision_init_files` does, in order:

1. Detects the OS tier (modern macOS / older macOS / Linux).
2. Resolves absolute paths for tools bashrc calls (`gpg`, `vim`, `git`, OpenSSH, `curl`, `python3`, …).
3. Prints OK / missing lines (with install hints). On **modern macOS** with a TTY (not `-q`/`--force`), offers Homebrew bootstrap if needed, then required brew packages, then optional brew packages (two Y/n prompts); rediscovers after installs.
4. Required gaps still abort unless `--force` (or the tool is optional under `--no-dev`).
5. Writes `~/.config/init-files/tools.<hostname>` (shell assignments, not exported; includes `init_files_tools_revision`).
6. Symlinks `~/.bashrc` → `~/.local/share/init-files/bashrc`.
   - If `~/.bashrc` was a regular file, it is backed up once as `~/.bashrc.bak.<timestamp>`.
   - If it already points at the clone, install is a no-op for the link.
7. Merges house SSH materials from private config (`~/.local/share/config/.ssh/`).
8. Installs GitHub SSH snippet from config `.ssh/config.github`, ensures `github.com` known_hosts, and applies this host’s GitHub transport: SSH hosts get  
   `git config --global url."git@github.com:".insteadOf "https://github.com/"`; HTTPS hosts clear that rewrite (warns if the private key is missing only in SSH mode).
9. Persists or clears `no-dev.<hostname>`, `github-https.<hostname>`, and `github-ssh.<hostname>` according to flags / saved preference / gh auth.
10. Ensures `~/.profile` / `~/.bash_profile` sources `~/.bashrc` (login shells).
11. On macOS (not `-q`, not `--no-iterm`): merges curated iTerm2 prefs via `iterm2/install`.
12. On modern macOS (not `-q`): if login shell is not the preferred Homebrew Cellar bash, prints `/etc/shells` + `chsh` steps.

### Dev vs non-dev mode

**Full (default):** development tools are required. Missing `git` / `python3` / `make` / … aborts install (unless `-f`).

**Non-dev (`--no-dev`):** those development tools are **optional** — missing ones do not abort, but are still recorded when present. Core tools (`ssh*`, `curl`, `vim`, `gpg`, `cmp`) stay required.

Preference is **per hostname**, stored as `~/.config/init-files/no-dev.<hostname>` (so NFS-shared homes can mix modes — e.g. one host `--no-dev`, another full). Plain `provision_init_files` / `refresh_init_files` with no mode flag **keep** that host’s mode. Use `--dev` on that host to clear it.

Legacy unscoped `~/.config/init-files/no-dev` or `~/.local/state/init-files/no-dev` is migrated onto the current hostname on first use, then removed so it does not affect other NFS clients.

| Goal | Command |
| --- | --- |
| First setup on a minimal host | `./provision_init_files --no-dev` then `source ~/.bashrc` |
| Switch full install → non-dev | `refresh_init_files --no-dev` then `source ~/.bashrc` |
| Switch non-dev → full install | `refresh_init_files --dev` (or `provision_init_files --dev`) then `source ~/.bashrc` |
| Stay non-dev while pulling updates | plain `refresh_init_files` / `provision_init_files` (remembered mode) |

```bash
# Minimal host (first time, after clone):
~/.local/share/init-files/provision_init_files --no-dev
source ~/.bashrc

# Existing full install → non-dev box:
refresh_init_files --no-dev
source ~/.bashrc

# Non-dev → require the full toolchain again:
refresh_init_files --dev
source ~/.bashrc
```

Confirm mode:

```bash
# macOS: ComputerName (same as PS1). Linux: short hostname.
ls -l ~/.config/init-files/no-dev."${init_files_host:-$(scutil --get ComputerName 2>/dev/null || hostname -s)}"
# exists ⇒ this host is non-dev
# or after provision_init_files: look for "Mode: --no-dev" / "Mode: full install" in the output
```

Without `git`, `refresh_init_files` cannot pull updates until git is available; re-run `provision_init_files` (with `--no-dev` if that is still the intent) once git exists.

### 3. Load the new shell config

```bash
source ~/.bashrc
```

That one `source` is only for the **current** session (install cannot change an already-running shell). New terminals / SSH logins should load automatically.

On Debian/Ubuntu (and other Linux login shells), bash reads `~/.profile` (or `~/.bash_profile` if present), **not** `~/.bashrc`, unless those files source it. `./provision_init_files` appends an init-files hook so login shells load `~/.bashrc` (bashrc is idempotent if sourced twice). If a custom `~/.bash_profile` omitted that, re-run `provision_init_files` after this fix.

`refresh_init_files` reloads `~/.bashrc` in the **current** interactive shell when it updates the clone or re-runs install — you should not need a manual `source` after refresh. A one-time `source ~/.bashrc` is still needed after a bare `./provision_init_files` in an already-running shell.

```bash
ls -l ~/.bashrc
# … -> …/init-files/bashrc

echo "$init_tool_git"
type refresh_init_files
```

Optional: `check_tool_versions` (runs automatically in interactive shells on **full** installs) should match this host’s OS tier — no `brew install` / `brew upgrade` hints on older macOS. Skipped entirely when `~/.config/init-files/no-dev.<hostname>` is present.

---

## Process: refreshing from GitHub

Use this whenever you want the latest `main` (bashrc / provision / rules). Full refresh **always** re-runs `provision_init_files` (tools, ssh, vimrc).

### Manual refresh

```bash
refresh_init_files              # pull + provision + reload this shell
refresh_init_files -q           # daily: offer pull if main / private config moved; repair deploy drift
refresh_init_files --no-dev     # pull, then provision --no-dev (persist non-dev mode)
refresh_init_files --dev        # pull, then full provision (clear non-dev mode)
refresh_init_files --github-https  # pull, remember HTTPS GitHub for this host
refresh_init_files --github-ssh    # pull, remember SSH (insteadOf) for this host
refresh_init_files --no-iterm      # skip curated iTerm2 prefs merge (macOS default: apply)
```

What `refresh_init_files` does (default / `-f`):

1. Clones `init_files_repo` into `init_files_dir` if the clone is missing.
2. Otherwise `git fetch origin main`, then ff-only merge (falls back to `reset --hard origin/main`).
3. Ensures `~/.bashrc` is still a symlink to `$init_files_dir/bashrc` (migrates leftover copies from the old copy-based install).
4. Updates the daily-check stamp under `~/.local/state/init-files/`.
5. Prints `updated … <old> → <new>` (short SHAs) when the clone moved, or `already current` with the HEAD short SHA.
6. **Always** runs `./provision_init_files` with remembered `--no-dev`/`--dev` and GitHub transport flags (tools, ssh materials, vimrc symlink/plugins, login-shell hook; on macOS also iTerm prefs + brew-bash tip when needed).
7. On macOS (not `-q`): runs `refresh_iterm_settings` by default (`--no-iterm` to skip).
8. Reloads `~/.bashrc` in the current interactive shell (no manual `source` needed after refresh).
9. Applies remembered GitHub transport (clears or sets `insteadOf`) before fetch.

On **modern macOS**, interactive `./provision_init_files` (including when started from refresh) may ask:

1. Install Homebrew? (only if `brew` is missing)
2. Install N required Homebrew packages? `[Y/n]` — formulae and casks installed separately, one package at a time; rediscovers before optional
3. Install N optional Homebrew packages? `[Y/n]` — same; a single failure does not abort the rest. (Meslo Nerd Font is **not** a brew cask here — see below.)
4. Missing Meslo for this user? Offer `iterm2/install_meslo_nerd_font` (Meslo.zip → ~/Library/Fonts, no sudo)

If this account is **not** a macOS admin (common on MDM-managed Macs), provision **auto-detects** that and does **not** run brew installs or print `install: brew …` lines. It emits **one** forwardable admin handoff block (host + user identity, Homebrew installer if needed, exact `brew install …` lines). Send that block to IT / an admin; after they finish on **this** Mac, re-run `./provision_init_files` as yourself. Admin accounts only see the interactive brew prompts / direct install hints. Meslo fonts and nvm Node still install without an admin (user-local).

Skipped under `-q` / `--force` / non-TTY / older macOS / Linux for brew offers (non-admin copy-paste still prints on a TTY when brew packages are missing). Default `refresh_init_files` / `refresh_iterm_settings` / `iterm2/install` offer `install_meslo_nerd_font` when the curated profile font is missing.

### Automatic daily checks

Interactive shells, about once per day (`init_files_max_age_seconds` / `tool_version_max_age_seconds`, default 86400):

| Check | Behavior |
| --- | --- |
| Tool versions | Reprint cached diagnostic every shell (with color); rebuild at most once/day, or sooner when the background latest-* cache updates. No `[N]+ Done` job noise. Skipped on `--no-dev` hosts. |
| init-files `main` | `git ls-remote` vs local HEAD; if behind, prompt `Update now? [Y/n]` (TTY) or print `Run: refresh_init_files`. |
| Local deploy drift | Compare this host’s deployables to the clone: `~/.bashrc` / `~/.vimrc` symlinks, retired `~/.gvimrc`, login-profile bashrc hook, broken `tools.<hostname>` paths, and (macOS) curated iTerm prefs vs `iterm2/com.googlecode.iterm2.plist`. If anything differs, prompt `Repair now with …? [Y/n]` (TTY) or print `Run: …`. Narrow fixes use `refresh_vimrc` / `refresh_iterm_settings`; otherwise `refresh_init_files`. Never auto-applies under `-q`. |

Offline / auth failures on the quiet path stay silent.

### Overrides (optional)

| Variable | Default / role |
| --- | --- |
| `init_files_repo` | Override clone URL (default points at this repo’s GitHub remote) |
| `init_files_dir` | `~/.local/share/init-files` |
| `init_files_max_age_seconds` | `86400` (1 day) |
| `init_files_no_dev_flag` | `~/.config/init-files/no-dev.<hostname>` (presence = this host is non-dev) |
| `init_files_github_https_flag` | `~/.config/init-files/github-https.<hostname>` (presence = GitHub HTTPS on this host) |
| `init_files_github_ssh_flag` | `~/.config/init-files/github-ssh.<hostname>` (presence = force SSH despite gh auth) |
| `INIT_FILES_DEFAULT_USERS` | Space-separated quiet-prompt allowlist. **Default:** from `~/.local/share/config/init-files/default-users.env` when config clone present; otherwise unset (no alt-user badge). |
| Private `bashrc.local` | Optional personal aliases/helpers from `~/.local/share/config/init-files/bashrc.local` (sourced after public aliases). |
| `INIT_FILES_DEFAULT_USER` | Legacy singular: **merged** into the allowlist (does not replace). Prefer `INIT_FILES_DEFAULT_USERS` for a full override. |
| `INIT_FILES_ALT_USER` | Set by bashrc when `$USER` is not allowlisted (starship reads this; do not set by hand) |
| `INIT_FILES_SKIP_TOOL_CHECK=1` | Emergency: skip `check_tool_versions` on interactive load (e.g. hung package-manager probe) |
| `INIT_FILES_SKIP_DAILY_REFRESH=1` | Emergency: skip daily `refresh_init_files -q` on interactive load |

---

## When to re-run `provision_init_files` vs `refresh_init_files`

**`refresh_init_files` always provisions** after pull (tools, ssh, vimrc). Use bare `./provision_init_files` when you only need to rewrite tool paths / ssh / vim without a git pull (e.g. right after a Homebrew move on an already-current clone).

| Situation | Command |
| --- | --- |
| First setup on a host | clone + `provision_init_files` (+ optional `--no-dev` / `--github-https`) + `source ~/.bashrc` |
| Minimal host (no git/python/make/…) | `provision_init_files --no-dev` or `refresh_init_files --no-dev` |
| Switch full install → non-dev | `refresh_init_files --no-dev` (persists) |
| Switch non-dev → full install | `refresh_init_files --dev` or `provision_init_files --dev` |
| Prefer GitHub HTTPS on this host | `provision_init_files --github-https` or `refresh_init_files --github-https` |
| Prefer GitHub SSH on this host | `provision_init_files --github-ssh` or `refresh_init_files --github-ssh` |
| New commits on `main` (bashrc / docs / rules) | `refresh_init_files` (provisions + reloads current shell) |
| Moved / upgraded tools (new git, gpg, python, brew Cellar bump, …) | `provision_init_files` or `refresh_init_files` |
| OS upgrade that changes the macOS tier (e.g. into Darwin 25+) | `provision_init_files` or `refresh_init_files`, then validate hints |
| `~/.bashrc` accidentally replaced by a regular file | `provision_init_files` or `refresh_init_files` (both repair the symlink) |
| Merge curated iTerm2 prefs (macOS) | default `refresh_init_files` / `provision_init_files`; skip with `--no-iterm`; or `refresh_iterm_settings` |

Sanity checks: `init_files_doctor` and `check_tool_versions` warn when recorded `init_tool_*` paths are missing.

---

## Process: migrate an existing host (old copy → symlink)

Hosts that still have a **regular-file** `~/.bashrc` (pre-symlink install) should:

1. Ensure GitHub `main` has the symlink-era `provision_init_files` / `bashrc` (push from the authoring machine first).
2. Update the clone: `git -C ~/.local/share/init-files fetch origin main && git -C ~/.local/share/init-files reset --hard origin/main` (or clone if missing).
3. Run `~/.local/share/init-files/provision_init_files` then `source ~/.bashrc`.
4. Confirm `ls -l ~/.bashrc` shows a symlink into the clone.

Agents: follow the fuller checklist in [AGENTS.md](AGENTS.md) (“Migrate an existing host”).

---

## Platform notes

- **Rocky Linux 8.1**: skips development tool version checks and omits the git commit id from the prompt.
- **macOS 26+ (Darwin 25+)**: Homebrew is supported (GNU userland via `*/libexec/gnubin`, brew tool paths in `provision_init_files`). Install with `brew install coreutils gnu-sed grep` (and optionally `findutils gawk gnu-tar`).
- **Older macOS**: system/BSD userland only — Homebrew paths are not used or recommended. Brew is often infeasible here (unsupported formulae, multi-hour from-source dependency builds); prefer Xcode CLT, MacGPG2, app bundles, or `~/.local` GitHub releases.
- **macOS**: MacVim remote tabs, volume helpers, ChromeCast/Globo aliases, `cache_ssh` without Keychain auto-unlock. Linux-only helpers are not defined.
- **Linux**: ssh-agent via `~/.ssh/environment`, VNC server helpers, terminator/kwin aliases. macOS-only helpers are not defined.

See [.cursor/rules/platform-isolation.mdc](.cursor/rules/platform-isolation.mdc) and [AGENTS.md](AGENTS.md) for agent guidance when changing bashrc / install. Interactive shell operator docs: [docs/shell-ux.md](docs/shell-ux.md).

---

## House SSH

House keys are **passphrase-protected** and live on each host under `~/.ssh/` (never in this repo). Identity paths and host aliases come from the private config overlay (`.ssh/config.house`, `.ssh/config.github`). Load with `cache_ssh` before scripted hops. For interactive logins after the agent lifetime expires, use **`cssh`** (`ssh`), **`cmsh`** (`mosh` — sleep/IP roaming; needs `mosh-server`), or **`cesh`** (`et` / Eternal Terminal — reconnectable like mosh but a normal pty so CSI-u / Shift+Enter work; needs `etserver` on the remote). With no arguments, all three fuzzy-pick from SSH config + cleartext **known_hosts** via **fzf** when available. None replace the underlying binaries. Nopassphrase keys are **not** used for house access.

### GitHub transport (HTTPS when gh is logged in, else SSH)

#### Where the flags are available

| Surface | How |
| --- | --- |
| On disk (NFS-safe, per host) | `~/.config/init-files/github-https.<hostname>` — HTTPS preferred |
| | `~/.config/init-files/github-ssh.<hostname>` — SSH opt-out (wins over gh auto-HTTPS) |
| `bootstrap_host` | Interactive chooser (default: `gh auth login`); `--github-https` / `--github-ssh`; `--key-from HOST` fetches house key only (does not force GitHub SSH) |
| `./provision_init_files` | `--github-https` / `--github-ssh` (see [install flags](#process-first-time-installation)) |
| `refresh_init_files` | `--github-https` / `--github-ssh` (same persistence; re-runs `provision_init_files` with the flag) |
| Auto (no flag file yet) | If `gh auth status` succeeds and `github-ssh.<hostname>` is absent → write `github-https.<hostname>` and use HTTPS |

`<hostname>` is the same scope key as `no-dev.<hostname>` / PS1 (macOS **ComputerName**, Linux short hostname). See [On-disk layout](#on-disk-layout).

Confirm on this host:

```bash
ls -l ~/.config/init-files/github-{https,ssh}."${init_files_host:-$(scutil --get ComputerName 2>/dev/null || hostname -s)}"
git config --global --get url.git@github.com:.insteadof   # empty ⇒ HTTPS; https://github.com/ ⇒ SSH rewrite
git config --global --get-regexp 'credential\.https://github.com'   # HTTPS: !gh auth git-credential
```

**Auto HTTPS:** if `gh auth status` succeeds and this host has no `github-ssh.<hostname>` opt-out, install/refresh prefer HTTPS (clear `insteadOf`, point `credential.https://github.com.helper` at `gh auth git-credential`) and remember `github-https.<hostname>`.

**SSH (when gh is not logged in, or with `--github-ssh`):** same house key registered on GitHub + `insteadOf` so documented `https://github.com/…` remotes speak SSH. Prefer `gh auth login` / HTTPS when possible. New hosts without gh:

1. Copy the private key onto the host (never commit it).
2. `git config --global url."git@github.com:".insteadOf "https://github.com/"`
3. `Host github.com` with `User git` + IdentityFiles from private overlay `config.github` (applied by `./provision_init_files` when the overlay is present).
4. `cache_ssh` then `ssh -T git@github.com`.

Then `git clone https://github.com/OWNER/init-files.git …` and `refresh_init_files` use SSH under the hood.

**Force HTTPS** (also happens automatically when gh is logged in, and is the interactive `bootstrap_host` default):

```bash
install --github-https          # or: refresh_init_files --github-https
# remembers ~/.config/init-files/github-https.<hostname>
# clears the https→ssh insteadOf rewrite on this machine
```

**Force SSH** despite gh auth:

```bash
install --github-ssh            # or: refresh_init_files --github-ssh
# remembers ~/.config/init-files/github-ssh.<hostname>
```

Plain later `provision_init_files` / `refresh_init_files` keep remembered prefs (or re-detect gh when neither flag exists).

Note: preference flags are NFS-safe per hostname; the `insteadOf` setting lives in shared `~/.gitconfig`, so the last host to apply transport wins on NFS-shared homes.

### NFS home hygiene

Shared homes correctly keep **per-host** `tools.*` / `no-dev.*` / `github-*.*` / `pipx/<host>/`. Over time, retired names leave leftovers (Bonjour conflict suffixes, legacy unscoped `tools`).

| Keep | Safe to prune (after confirming) |
| --- | --- |
| `*.<current-init_files_host>` for every **live** host | Prefs / pipx dirs for hosts you no longer use |
| `~/.config/init-files/nfs-hosts` (optional allowlist, one host per line) | Legacy unscoped `tools` once `tools.<host>` exists |

```bash
init_files_doctor                 # deploy sanity (symlink, tools, pipx wrapper, …)
init_files_cleanup_orphans        # list orphans (dry run)
# Edit ~/.config/init-files/nfs-hosts with live hostnames, then:
init_files_cleanup_orphans --apply
```

`provision_init_files` / interactive bashrc **migrate** legacy pipx dir names and Bonjour-scoped prefs onto the canonical host key; they never delete foreign hosts’ state. Cleanup is always explicit (`--apply`).

`./provision_init_files` also:

1. **Merges** overlay `authorized_keys.house` into `~/.ssh/authorized_keys` (does not remove other keys).
2. Installs overlay `config.house` → `~/.ssh/config.d/init-files-house.conf`.
3. Installs GitHub snippet from overlay `config.github` → `~/.ssh/config.d/init-files-github.conf`.
4. Ensures `Include ~/.ssh/config.d/*.conf` is at the top of `~/.ssh/config`.
5. Sets or clears the GitHub `insteadOf` rewrite according to this host’s preference.

See [`ssh/README.md`](ssh/README.md). After changing house/GitHub SSH materials in the private overlay: pull the overlay, then on each host `refresh_init_files` / `./provision_init_files`.
