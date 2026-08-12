# AGENTS.md — init-files

Guidance for agents maintaining this repo. Generic shell tooling here is prepared for a **public** repo; user-specific material (house SSH, pubkeys, primary-user allowlist) lives in a **private config overlay** (`~/.local/share/config`, URL prompted / `INIT_FILES_CONFIG_REPO`).

Human-oriented install/refresh steps live in [README.md](README.md). Platform isolation details also live in [.cursor/rules/platform-isolation.mdc](.cursor/rules/platform-isolation.mdc) (`alwaysApply`). Tool-path contract: [.cursor/rules/tool-path-consistency.mdc](.cursor/rules/tool-path-consistency.mdc) (`alwaysApply`) + shared [`lib/tool_path`](lib/tool_path) / [`lib/host_paths`](lib/host_paths). Error handling: [.cursor/rules/error-handling.mdc](.cursor/rules/error-handling.mdc) (`alwaysApply`) + [`lib/error`](lib/error) for standalone scripts. Interactive input: [.cursor/rules/interactive-input.mdc](.cursor/rules/interactive-input.mdc) (`alwaysApply`) + [`lib/interactive_input`](lib/interactive_input) for `bt` / `cache_ssh`. That tool-path rule also covers **admin vs non-admin** modern-macOS installs (MDM handoff via `print_brew_admin_copy_paste`). Prefer updating **both** this file and those rules when isolation or tool-path policy changes. Bash scripts in this repo do **not** use a `.sh` suffix — see [.cursor/rules/no-sh-extension.mdc](.cursor/rules/no-sh-extension.mdc).

---

## What this repo is

Canonical interactive **bash** init for multiple hosts:

| Host (examples) | OS tier |
| --- | --- |
| modern macOS host | Darwin 25+ / macOS 26+ — Homebrew OK |
| older macOS host | Darwin 21.6+ and &lt; 25 — **no brew recommendations** |
| Linux host | Ubuntu / Rocky through 8.10 |

Tracked content is shared. Host-specific absolute tool paths are **generated on each machine** and are not committed.

---

## Repo map

| Path | Role |
| --- | --- |
| `bashrc` | Canonical interactive bashrc (functions, env, aliases, init). Deployed via symlink. |
| `provision_init_files` | Discovers tools for this host, writes `tools`, symlinks `~/.bashrc` / `~/.vimrc`, merges ssh. |
| `bootstrap_host` | Standalone new-host helper (pre-clone SSH/HTTPS → clone → `provision_init_files`). scp-able alone. |
| `install_node_toolchain` | User-local nvm + Node LTS + corepack (no sudo; preferred over Homebrew npm). |
| `README.md` | Install / refresh process for humans. |
| `docs/shell-ux.md` | Interactive shell UX: history, completion, shopt, fzf, bash version. |
| `iterm2/` | Curated iTerm2 prefs (font/colors/keys/mouse); macOS-only export/install — see [iterm2/README.md](iterm2/README.md). Applied by default on Darwin provision / `refresh_init_files` (`--no-iterm` to skip). |
| `vim/` | Canonical Vim 9 + vim-plug config; `~/.vimrc` symlink; `refresh_vimrc` — see [vim/README.md](vim/README.md). |
| `cursor/` | Agent CLI statusline + session-id recorder; `agent_sessions` / `resume_agent_session` — see [cursor/README.md](cursor/README.md). |
| `lib/tool_path` | Sole `init_files_verify_tool_path` (provision + bashrc). Clean break — no legacy dual validators. |
| `lib/host_paths` | Shared Homebrew prefix / brew-bin / MacVim discovery probes (provision + bashrc). No env overrides. |
| `lib/error` | Script-only `init_files_die` / `warn` / `log`. Not sourced from bashrc. |
| `lib/interactive_input` | `bt` / `cache_ssh` path and timeout checks (sourced by bashrc). |
| `lib/history_rotate` | Soft/hard history archive bounds + session prune (issue #9). |
| `lib/github_bootstrap` | Guided GitHub bootstrap for `bootstrap_host` (gh HTTPS + SSH confirm/retry; issue #18 UX). |
| `lib/tool_version_cache` | Atomic write + mkdir lock helpers for tool-version `latest` / `last-report` / `last-check`. |
| `tests/*.test` | Bash unit tests (repository-helpers layout). Run via `bash tests/<name>.test` or CI. |
| `tests/lib/test-assert` | Shared `[PASS]`/`[FAIL]` helpers for tests. |
| `.github/ci/list-shell-files` | All git-tracked files minus an exclusion list (docs/data/ssh/vim/python/…); shared by bash-n / shellcheck. |
| `.github/ci/bash-n` / `.github/ci/shellcheck` | Local + CI entrypoints (`shellcheck -S info`); same file set. |
| `scripts/check` | Local pre-PR runner: bash-n + shellcheck + `tests/*.test` (repository-helpers consumer pattern). |
| `.github/workflows/ci.yml` | Guard + `.github/ci/bash-n` / `.github/ci/shellcheck` / `tests/*.test`. |
| `.cursor/rules/no-sh-extension.mdc` | Always-on: no `.sh` suffix on tracked bash scripts. |
| `AGENTS.md` | This file — long-term agent management. |
| `.cursor/rules/platform-isolation.mdc` | Always-on isolation rules for Cursor. |
| `.cursor/rules/tool-path-consistency.mdc` | Always-on tool-path contract (absolute paths, shared verifier). |
| `.cursor/rules/error-handling.mdc` | Always-on: sourced → return; scripts → `init_files_die` / warn / log. |
| `.cursor/rules/interactive-input.mdc` | Always-on: `bt` / `cache_ssh` validation; no global argv sanitizer. |
| `.gitignore` | Ignores `__pycache__` / `*.pyc` and editor junk. |
| `lib/config_paths` | Private config overlay paths + interactive clone (`INIT_FILES_CONFIG_REPO` / remembered URL → `.ssh/`, `init-files/default-users.env`, optional `init-files/bashrc.local`). |

| `.github/CODEOWNERS` | Ownership (`@thehcma`). |

Do **not** commit user-specific material in this repo — use a **private config overlay**:

- `config/.ssh/` (house hosts, authorized_keys, GitHub IdentityFile template)
- `config/init-files/default-users.env` (`INIT_FILES_DEFAULT_USERS`)
- `config/init-files/bashrc.local` (optional personal aliases / helpers)
- Never hardcode a private overlay git URL in init-files (prompt / env / remembered pref)

Do **not** commit:

- `~/.config/init-files/tools` (or any host tools file)
- Backups like `~/.bashrc.bak.*`
- Machine-local state under `~/.local/state/init-files/`
- Python bytecode (`__pycache__/`, `*.pyc`) — covered by `.gitignore`

---

## Deployment model (every host)

```
~/.local/share/init-files     ← git clone of this repo (target: public)
~/.local/share/config         ← git clone of private config overlay (URL prompted)
~/.bashrc                     ← symlink → ~/.local/share/init-files/bashrc
~/.config/init-files/tools.<hostname>  ← generated by ./provision_init_files (per host; NFS-safe)
~/.config/init-files/config-repo       ← remembered private overlay git URL
```

- Editing `~/.bashrc` edits `bashrc` in the clone.
- `refresh_init_files` pulls `main`, repairs the bashrc symlink, **always** re-runs `provision_init_files` (tools, ssh, vimrc), merges curated iTerm2 prefs on macOS by default (`--no-iterm` to skip; `-q` never applies prefs), then reloads `~/.bashrc` in the current shell.
- Daily quiet check (`refresh_init_files -q`): when `origin/main` has moved, **offer** to update (`Update now? [Y/n]` on a TTY); otherwise print a hint. Also checks the **private config overlay** (remembered URL vs clone origin; `main` moved → offer `git pull --ff-only` then provision). Also detects **local deploy drift** (bashrc/vimrc symlinks, login bashrc hook, broken tools paths, macOS curated iTerm prefs) and offers a repair (`refresh_init_files` / `refresh_vimrc` / `refresh_iterm_settings`) without auto-applying. Does not auto-pull without confirmation.
- `check_tool_versions` reprints a cached diagnostic every interactive shell; rebuilds at most once/day (no blocking network), or sooner when the `pending-updates` sidecar detects an out-of-band install drift. Use `update_tools` to apply all currently outdated upgrades this account can. Skipped on `--no-dev` hosts.
- Clone belongs under **`~/.local/share/init-files`** (XDG data), not under `~/.config/`.
- Non-dev preference: `~/.config/init-files/no-dev.<hostname>` (NFS-safe). Set by `provision_init_files --no-dev` / `refresh_init_files --no-dev`; cleared by `--dev` on that host only. Plain later `provision_init_files` / `refresh_init_files` on that host stay non-dev.
- GitHub HTTPS preference: `~/.config/init-files/github-https.<hostname>` (NFS-safe flag). Set by `provision_init_files --github-https` / `refresh_init_files --github-https`, or auto when `gh` is authenticated. Cleared by `--github-ssh`. Clears https→ssh `insteadOf` on that host. Uses `gh auth git-credential` (not osxkeychain). **Canonical docs:** [README — Where the flags are available](README.md#where-the-flags-are-available).
- GitHub SSH opt-out: `~/.config/init-files/github-ssh.<hostname>`. Set by `provision_init_files --github-ssh` / `refresh_init_files --github-ssh` so gh auth does not flip the host back to HTTPS. Default without gh remains SSH via `insteadOf`.
- Tool paths: `~/.config/init-files/tools.<hostname>` (same NFS reason; legacy unscoped `tools` still loaded if present).
- **Host scope key** matches PS1 **and** `~/.local/opt/pipx/<hostname>/`: macOS `ComputerName` via `scutil` (not Bonjour `LocalHostName`); Linux short hostname. `provision_init_files` migrates `*.<LocalHostName>` / hostname-f/s prefs and pipx trees onto the canonical key when they differ.
- `host_tag()` / pipx layout use the same key (override only via `tool_host_tag` if needed).
- `init_files_doctor` — read-only deploy sanity (bashrc/vimrc symlinks, login hook, iTerm curated prefs on Darwin, HEAD, tools, pipx wrapper, GitHub transport, OS tier).
- `init_files_cleanup_orphans [--apply]` — list/remove NFS leftover prefs and pipx trees; keep set = current host + `~/.config/init-files/nfs-hosts` + `--keep`.
- Stale pipx wrappers (`$init_tool_python3` unbound) are rebaked by `provision_init_files`, `update_pipx`, and interactive bashrc load.

### Dev vs non-dev (per host)

Some hosts are full development boxes; others should not require `git` / `python3` / `make` / `patch` / `gdb` / `colordiff`. Mode is **per host** and persists across refreshes.

| Goal | Command |
| --- | --- |
| Minimal first install | `./provision_init_files --no-dev` |
| Full install → non-dev | `refresh_init_files --no-dev` (pulls, then `provision_init_files --no-dev`, saves preference) |
| Non-dev → full | `refresh_init_files --dev` or `provision_init_files --dev` |
| Stay non-dev on later pulls | plain `refresh_init_files` / `provision_init_files` (remembered `no-dev.<hostname>`) |

Plain `provision_init_files` / `refresh_init_files` with no mode flag **keep** whatever preference is already saved. Do not assume every host is a full toolchain box.

### First-time setup on a host

**Preferred:** public bootstrap (download → run → verify → source). See [README.md](README.md). Interactive `bootstrap_host` prefers **`gh auth login` (HTTPS)**; `--key-from HOST` fetches the house key for house hops without forcing GitHub SSH (HTTPS still wins when `gh` is logged in). GitHub SSH is for when HTTPS is unavailable; if it fails, bootstrap falls back to HTTPS when `gh` can authenticate.

```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/init-files/main/bootstrap_host \
 -o /tmp/bootstrap_host
chmod +x /tmp/bootstrap_host
/tmp/bootstrap_host
# House key (GitHub stays HTTPS if gh logged in):
# /tmp/bootstrap_host --key-from HOST   # e.g. user@other-host
# Wait for "bootstrap_host verify" with bashrc OK, then:
source ~/.bashrc
```

Mirror `bootstrap_host` to the public bootstrap URL when it changes. Manual fallback: `gh auth login` + clone + `provision_init_files --github-https`, or SSH key + `insteadOf` + `cache_ssh` + `ssh -T` + clone + `./provision_init_files`. Private keys are never in the repo.

### Migrate an existing host (copy-based → symlink model)

Use this on any host that still has a regular-file `~/.bashrc` from the old install, or an outdated clone.

**Prerequisite:** the symlink/deploy work must already be on GitHub `main` (push from the machine that authored it). Until then, other hosts cannot pick this up via `refresh_init_files`.

Agent checklist (read this file + [README.md](README.md); then execute on the **current** host only):

1. **Identify the host**
   ```bash
   hostname; uname -a
   ls -l ~/.bashrc
   git -C ~/.local/share/init-files rev-parse --short HEAD 2>/dev/null
   git -C ~/.local/share/init-files status -sb 2>/dev/null
   ```
2. **Update or create the clone**
   - If `~/.local/share/init-files/.git` exists:  
     `git -C ~/.local/share/init-files fetch origin main && git -C ~/.local/share/init-files reset --hard origin/main`  
     (or `refresh_init_files` once a new enough bashrc is already sourced — if the running shell is still the *old* copy-based bashrc, prefer the explicit `git` commands above, then run `provision_init_files`).
   - If missing: clone as in first-time setup.
3. **Run install** (tools + symlink + house SSH materials):
   ```bash
   ~/.local/share/init-files/provision_init_files
   # minimal host without a dev toolchain:
   # ~/.local/share/init-files/provision_init_files --no-dev
   source ~/.bashrc
   ```
   `--no-dev` makes `git` / `python3` / `make` / `patch` / `gdb` / `colordiff` optional (still recorded when present). Core tools stay required. See README.
4. **Verify**
   ```bash
   ls -l ~/.bashrc
   # expect: ~/.bashrc -> .../init-files/bashrc
   readlink ~/.bashrc
   echo "git=$init_tool_git modern=$(_init_is_modern_macos && echo yes || echo no)"
   type refresh_init_files
   check_tool_versions   # interactive shell; hints must match this OS tier
   ```
5. **House + GitHub SSH**
   - Private config overlay at `~/.local/share/config` (or skipped for generic install)
   - `~/.ssh/config.d/init-files-house.conf` and `init-files-github.conf` when overlay materials exist
   - House / GitHub keys present as listed in overlay `config.github`
   - `cache_ssh` then `ssh -T git@github.com` succeeds when using SSH transport
   - House `authorized_keys` contains only passphrase house pubkeys (no nopassphrase keys)
6. **Report back** to the user: hostname, `HEAD` sha, symlink OK/fail, GitHub SSH OK/fail, tool-hint sanity for this tier, any blockers.

Do **not** invent a second clone path. Do **not** copy `bashrc` over `~/.bashrc`. Do **not** push unless asked.

### Refresh bashrc from `main`

```bash
refresh_init_files
# current interactive shell is reloaded automatically when main/provision_init_files changed
```

### Refresh tool paths (after OS/tool moves)

```bash
~/.local/share/init-files/provision_init_files
source ~/.bashrc
```

| Need | Command |
| --- | --- |
| New git commits on `main` | `refresh_init_files` (always provisions) |
| New/moved binaries only | `provision_init_files` (or `refresh_init_files`) |
| Broken / non-symlink `~/.bashrc` | `provision_init_files` or `refresh_init_files` |
| Full install → non-dev host | `refresh_init_files --no-dev` (persists) |
| Non-dev → full install | `refresh_init_files --dev` or `provision_init_files --dev` |

**Agents:** after OS upgrades or Homebrew/tool moves on the current host, run `./provision_init_files` or `refresh_init_files` and confirm `init_files_doctor` / `check_tool_versions`. Plain `refresh_init_files` always rewrites `tools.<hostname>`.

Interactive shells also run `refresh_init_files -q` about daily.

---

## Platform isolation (non-negotiable)

Treat macOS and Linux as separate runtimes. Never let one platform’s install path, tool resolution, or hints leak into the other.

### macOS

| Tier | Gate | Policy |
| --- | --- | --- |
| Modern | `_init_is_modern_macos` (Darwin **≥ 25**) | Homebrew supported for most tools. Prefer brew absolute paths from `provision_init_files`. **Node/npm/pnpm/gt** via nvm/fnm (user-local), not brew. |
| Older | Darwin 21.6+ and **&lt; 25** | System/Xcode (and non-brew `/usr/local` like MacGPG2) only. **Never** suggest `brew install` / `brew upgrade` even if `brew` is on PATH. Many formulae are unsupported or force multi-hour from-source builds. Prefer Xcode CLT, app bundles, MacGPG2, or GitHub releases under `~/.local`. Node via nvm/fnm. |

- **nvm/fnm first** for Node: if `~/.nvm` or fnm is present, load it and prefer it over any Homebrew `node`/`npm` on PATH (all macOS tiers). Bootstrap missing Node with [`install_node_toolchain`](install_node_toolchain) / nvm — never `brew install node` and never `npm -g` into Homebrew (EACCES when brew is owned by another account). Brew node is fallback only when nvm/fnm are absent and read-only.
- `provision_init_files` must reject Homebrew-resolved paths on older macOS (including `/usr/local/bin/*` shims into Cellar).

### Linux

- Support **Ubuntu** and **Rocky** (through 8.10).
- **Rocky 8.1** (`_init_is_rocky_8_1`): skip tool-version checks; omit git commit id in the prompt.
- Distro package currency ≠ upstream: if apt/dnf/yum already current, report **manual / upstream-only** — do **not** suggest a no-op `update_git`.
- Prefer nvm/fnm (or `~/.local`) for Node/npm; same nvm-first policy as macOS.

### Gates to use in code

- `_init_is_darwin`, `_init_is_modern_macos`, `_init_is_rocky_8_1`
- Or explicit `OSTYPE` / `/etc/os-release` checks

Never “detect brew and assume modern macOS” or “detect apt and assume all Linux is the same.”

Mac-only helpers (`osascript`, MacVim, `open`, …) must fail closed on Linux; Linux-only helpers fail closed on macOS.

---

## Error handling

- **Sourced** (`bashrc`, most of `lib/*`): fail with `return` (never `exit` — that ends the interactive shell). See [.cursor/rules/error-handling.mdc](.cursor/rules/error-handling.mdc).
- **Standalone scripts**: use [`lib/error`](lib/error) (`init_files_die` / `init_files_warn` / `init_files_log`). Do not source `lib/error` from bashrc.
- **`bootstrap_host`**: inline `die` with `SYNC: lib/error` so the script stays curl/scp-able before the clone exists.

---

## How bashrc is organized

Inside `bashrc`, keep sections lexicographically sorted where noted in the file:

1. Load `~/.config/init-files/tools` (`init_tool_*`)
2. Functions (sorted)
3. Environment / exports
4. Aliases (OS-gated blocks)
5. Shell options
6. Initialization (prompt, daily `refresh_init_files -q`, `check_tool_versions`, nvm/fnm load, …)

Interactive history / completion / `shopt` / fzf behavior for operators: [docs/shell-ux.md](docs/shell-ux.md).

Conventions:

- Call tools via `"$init_tool_…"` when an absolute path was recorded — not bare `git`/`gpg` when the tools file defines them.
- Path acceptance is shared via `lib/tool_path` (`init_files_verify_tool_path`); never use bare `[[ -x ]]` as the only gate for recorded tools.
- Prefer short **why** comments on non-obvious control flow (locks, OS-tier forks, PATH bookkeeping); operator UX belongs in [docs/shell-ux.md](docs/shell-ux.md), not a narrated bashrc.
- Quiet-prompt usernames: allowlist via `INIT_FILES_DEFAULT_USERS` from private config `init-files/default-users.env` (or env); legacy `INIT_FILES_DEFAULT_USER` merges in. Empty allowlist → no alt-user badge. Non-members get `INIT_FILES_ALT_USER` + yellow-on-red badge. Details: [docs/shell-ux.md](docs/shell-ux.md).
- Personal / house aliases belong in private overlay `init-files/bashrc.local` (sourced after the public alias block), not in this repo’s `bashrc`.
- New `update_*` / `detect_*_strategy` brew branches must be gated with `_init_is_modern_macos`.
- Node/npm/pnpm/gt: nvm/fnm first on all tiers — never add a modern-macOS `brew install node` branch.
- Older macOS `update_gh` (and similar) should use GitHub release → `~/.local`, not brew.
- Do not strip Homebrew from the user’s PATH on older macOS; just do not **record** or **recommend** it.

---

## How `provision_init_files` works

1. Detect OS tier.
2. Resolve candidates → verify executable on this host.
3. On older macOS, reject paths that resolve into Homebrew (`Cellar` / `opt` / `homebrew`).
4. On **modern macOS** (TTY, not `-q`/`--force`): if missing tools have brew hints, offer Homebrew bootstrap (when needed), then **required** packages, then **optional** packages (two Y/n prompts); rediscover after installs.
5. Write `~/.config/init-files/tools.<hostname>` (includes `init_files_tools_revision` + `init_files_tools_names`).
6. Symlink `~/.bashrc` → clone `bashrc` (backup regular files once).
7. Merge house SSH materials from private config overlay (`~/.local/share/config/.ssh/`) when present.
8. Ensure `~/.profile` or `~/.bash_profile` sources `~/.bashrc` (needed for Debian/Ubuntu SSH login shells).
9. On Darwin (not `-q`): merge curated iTerm2 prefs via `iterm2/install` when the plist is present (warn-only on failure).
10. On modern macOS (not `-q`): if preferred Homebrew bash is present and UserShell is not that Cellar binary, print `/etc/shells` + `chsh` setup steps.

`refresh_init_files` detects tools revision mismatch / broken paths at shell startup (doctor / warn tip). Full `refresh_init_files` **always** runs `provision_init_files` after pull. Bump `INIT_FILES_TOOLS_REVISION` in both `provision_init_files` and `bashrc` when the `record_tool` set changes.

Flags: `-f` / `--force`, `-q` / `--quiet`, `--no-dev` / `--dev`, `--github-https` / `--github-ssh` (per-host GitHub transport; also on `refresh_init_files`). See [README — Where the flags are available](README.md#where-the-flags-are-available).

When adding a tool bashrc needs:

1. Add `init_tool_*` default / usage in `bashrc`.
2. Add `record_tool` candidates + hints in `provision_init_files` (modern brew vs older/system vs Linux).
3. Keep path acceptance in `lib/tool_path` (do not fork a second verifier in either caller).
4. Bump `INIT_FILES_TOOLS_REVISION` in `provision_init_files` and `bashrc`.
5. Re-run `provision_init_files` on the current host and confirm `tools` + hints.

---

## Validation checklist (before claiming done)

On the **current** host after changing `bashrc` or `provision_init_files`:

1. `./provision_init_files` (if tool resolution or symlink logic changed) or rely on symlink + `source ~/.bashrc`.
2. Confirm `ls -l ~/.bashrc` is a symlink into the clone.
3. Interactive: `check_tool_versions` — hints must match this OS tier (no brew on older macOS; no fake `update_git` when distro-capped on Linux).
4. Spot-check gates: `_init_is_modern_macos` / `_init_is_darwin` as expected for this machine.
5. If shell sources changed: `scripts/check` (or `bash .github/ci/shellcheck`) — `shellcheck -S info` must be clean on the full inventory.
6. Call out remaining risk on **other** tiers (e.g. “validated on older macOS; still need modern macOS + Linux”).

Known validation matrix:

| Change type | Prefer validating on |
| --- | --- |
| Homebrew / modern macOS paths | Darwin 25+ host |
| Older macOS / no-brew | Darwin 21.x host |
| Linux / nvm / distro git | Ubuntu and Rocky 8.1 if touching that gate |

Do not push unvalidated isolation changes that only worked on one tier without saying so.

---

## Git / release workflow

- Default branch: `main`.
- Commit and push **only when the user asks**.
- After push, other hosts pick up via `refresh_init_files` (or the daily quiet check).
- Local uncommitted work in `~/.local/share/init-files` is the live bashrc (symlink). `refresh_init_files` that resets to `origin/main` **will discard** unpushed commits/edits — commit/push (or stash) before forcing refresh if you care about them.
- Prefer small, reviewable commits: isolation fixes, symlink/deploy mechanics, and feature aliases are easier to validate separately across OSes.

---

## Session handoff across machines

Cursor chats do not sync across hosts. To continue work elsewhere:

1. **Push `main`** when asked (required before other hosts can migrate to new deploy mechanics).
2. On the other host, open a new agent chat and point it at **`AGENTS.md`** (and optionally paste the handoff below).
3. The agent should follow **Migrate an existing host** above (or first-time setup if the clone is missing).

### Pasteable handoff prompt

```text
Read and follow AGENTS.md (and README.md).
This host needs the symlink deploy model: ~/.bashrc → ~/.local/share/init-files/bashrc.

Prereq: prefer gh auth login (HTTPS). For SSH-only hosts: passphrase house key on disk.

If ~/.local/share/init-files is missing:
  curl -fsSL https://raw.githubusercontent.com/OWNER/init-files/main/bootstrap_host -o /tmp/bootstrap_host
  chmod +x /tmp/bootstrap_host
  /tmp/bootstrap_host
  # House key only (GitHub HTTPS if gh logged in):
  # /tmp/bootstrap_host --key-from HOST   # e.g. user@other-host
  # Force GitHub SSH: --github-ssh
  # Wait for verify (bashrc OK), then:
  source ~/.bashrc

If the clone already exists:
1. Fetch/reset the clone at ~/.local/share/init-files to origin/main (or refresh_init_files).
2. Run ~/.local/share/init-files/provision_init_files && source ~/.bashrc
   (or ~/.local/share/init-files/bootstrap_host for a full re-check)
3. Verify symlink, init_tool_*, refresh_init_files, insteadOf, github.com SSH config, and check_tool_versions for THIS OS tier.
4. Optional: private config overlay (prompted URL) for house SSH; passphrase keys only.
5. Report hostname, HEAD, verify results, and any blockers.

Do not push unless I ask. Do not copy bashrc over ~/.bashrc. Prefer gh auth / HTTPS; use SSH when required.
```

Copying transcript UUID dirs is optional secondary context, not a substitute for a pushed `main` and this handoff.

---

## Anti-patterns

- Copying `bashrc` into `~/.bashrc` instead of symlinking (old model — migrate away).
- Suggesting `brew install` / `brew upgrade` on older macOS because brew exists on PATH.
- Recording `/usr/local/bin/git` (Cellar shim) into `tools` on older macOS.
- Suggesting `brew install node` for npm/gt/pnpm (use nvm/fnm instead).
- Skipping nvm/fnm load just because a Homebrew `npm` is already on PATH.
- Suggesting `update_git` when the package manager cannot actually upgrade (Linux distro-capped).
- Changing Linux and macOS behavior with a single ungated PATH heuristic.
- Forking tool-path validation in `bashrc` / `provision_init_files` instead of `lib/tool_path`.
- Adding tracked bash scripts with a `.sh` suffix (see `.cursor/rules/no-sh-extension.mdc`).
- Calling `exit` from sourced bashrc functions (use `return`; scripts use `init_files_die`).
- Building a repo-wide argv sanitizer for interactive helpers (validate `bt` / `cache_ssh` entry points only).
- Committing host `tools` files or secrets.
- Committing `__pycache__` / `*.pyc` (use `.gitignore`).
- Putting private key material or house pubkeys in init-files (use a private config overlay `.ssh/`).
- Hardcoding a private overlay git URL in init-files (prompt / `INIT_FILES_CONFIG_REPO` / remembered pref only).

---

## House + GitHub SSH

Canonical materials under a **private config overlay** → `~/.local/share/config/.ssh/`:

| File | Role |
| --- | --- |
| `authorized_keys.house` | Passphrase house pubkeys every host must accept |
| `config.house` | Host aliases for house machines |
| `config.github` | `Host github.com` IdentityFile order (existing keys only) |

`provision_init_files` / `bootstrap_host` prompt for the overlay git URL when interactive (remembered in `~/.config/init-files/config-repo`), clone it, and verify the three files exist. See [README — House SSH](README.md#house-ssh).

**Policy:** house access uses passphrase-protected keys only. GitHub SSH IdentityFiles come from overlay `config.github` (typically personal ed25519 then house RSA; OpenSSH 8 / FIPS hosts may decline RSA). Never nopassphrase keys. Use `cache_ssh` before BatchMode / `refresh_init_files` fetches on SSH hosts.

**New hosts:** prefer `gh auth login` (HTTPS). Interactive `bootstrap_host` offers that first. `--key-from HOST` copies the house key for house hops and does **not** force GitHub SSH. GitHub SSH (`--github-ssh` / chooser) when HTTPS is unavailable; if SSH verify fails, bootstrap falls back to HTTPS when `gh` can authenticate. When `gh auth status` succeeds, prefer HTTPS automatically (remembered; `gh auth git-credential`). Opt out with `provision_init_files --github-ssh` / `refresh_init_files --github-ssh` (`github-ssh.<hostname>`). Force HTTPS with `--github-https`. Details: [README — Where the flags are available](README.md#where-the-flags-are-available).

---

## Quick commands for agents

```bash
# Where am I?
hostname; uname -r; [[ -f /etc/os-release ]] && . /etc/os-release && echo "$ID $VERSION_ID"

# Deploy state
ls -l ~/.bashrc
git -C ~/.local/share/init-files status -sb
git -C ~/.local/share/init-files log -1 --oneline

# Reinstall tools + symlink
~/.local/share/init-files/provision_init_files

# Local CI parity (bash -n + shellcheck -S info + tests/*.test)
~/.local/share/init-files/scripts/check

# Pull main (destructive to unpushed clone state if reset)
# refresh_init_files
```
