# Interactive shell UX

How init-files configures interactive bash: history, completion, shell options, and optional fzf. Behavior lives in [`bashrc`](../bashrc); this page is the human-readable map.

Platform rules (brew only on modern macOS, never on older macOS) still apply — see [AGENTS.md](../AGENTS.md) and [README.md](../README.md).

### Prompt / user badge

Classic PS1 (and starship) highlight `$USER` when it is **not** on the quiet-prompt allowlist — yellow-on-red so shared-host / wrong-account mistakes are obvious.

| Knob | Role |
| --- | --- |
| `INIT_FILES_DEFAULT_USERS` | Space-separated allowlist (primary). Loaded from private config `init-files/default-users.env` when present; env override wins. Empty/unset → no alt-user highlighting. |
| Private `bashrc.local` | Optional personal aliases/helpers from `~/.local/share/config/init-files/bashrc.local` (sourced after the public alias block). |
| `INIT_FILES_DEFAULT_USER` | Legacy singular: **merged** into the allowlist (does not replace). |
| `INIT_FILES_ALT_USER` | Set by bashrc to `$USER` when not allowlisted; unset otherwise. Starship keys off this. |

Membership is decided once in bashrc (`_init_is_default_user`); starship does not re-parse the list.

### Emergency startup bypasses

If an interactive shell hangs on tool checks or the daily refresh:

```bash
INIT_FILES_SKIP_TOOL_CHECK=1 source ~/.bashrc
INIT_FILES_SKIP_DAILY_REFRESH=1 source ~/.bashrc
```

### Starship (`prompt_fancy`)

`prompt_fancy` enables Starship and remembers it per host (`fancy-prompt.<hostname>`). If starship is missing on an interactive TTY, it **offers to install** for this OS:

| Tier | Install path |
| --- | --- |
| Modern macOS | `brew install starship` |
| Debian/Ubuntu (when packaged) | `sudo apt install starship` |
| Fedora/Rocky (when packaged) | `sudo dnf install starship` |
| Else | `install_starship` → upstream script into `~/.local/bin` |

`prompt_fancy -q` (login restore) never prompts; it prints a short hint instead. Disable with `prompt_plain`.

When **starship is already on PATH** (or otherwise resolvable) but fancy is off for this host, interactive TTYs **explain** `prompt_fancy` and offer to enable it about weekly (`last-fancy-prompt-offer`). Skip with `INIT_FILES_SKIP_FANCY_PROMPT_OFFER=1`. Missing starship is not nagged here — run `prompt_fancy` yourself to get the install offer.

Glyphs (`❯`, ``) need a **Nerd Font** in the terminal that draws them:

| Where you type | Font |
| --- | --- |
| SSH from Mac iTerm | Already Meslo LGS Nerd Font on the Mac — nothing to do on Ubuntu |
| macOS Terminal.app | Install Meslo into `~/Library/Fonts`, run `terminal/install` (or `refresh_init_files`) — sets **Basic** profile to Meslo LGS Nerd Font Mono 15 |
| Ubuntu GUI terminal (GNOME Terminal, Terminator, …) | Install Meslo into `~/.local/share/fonts`, `fc-cache -f`, then pick **MesloLGS Nerd Font Mono** in the profile |
| Raw Linux VT (`Ctrl+Alt+F*`) | Limited PSF fonts — Nerd glyphs will not render reliably; use a GUI terminal or SSH from iTerm |

Each iTerm pane title bar embeds the status bar (no extra row on splits): **left** is the Cursor Agent short session id while `agent` is running (`user.agentsession`; cleared when it exits), **right** is `local` or the hop hostname after `cssh` / `cesh` / `cmsh` (`user.hostlabel` — remote shells use the same host label as PS1 / `_init_host_label`, i.e. macOS ComputerName). Cmd-Q / reopen iTerm after `refresh_iterm_settings` if an existing window still has the old chrome.

```bash
# Ubuntu GUI terminal — same family as iTerm (see also vim/README.md)
mkdir -p ~/.local/share/fonts
curl -fsSL -o /tmp/Meslo.zip \
  https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip
unzip -o /tmp/Meslo.zip -d ~/.local/share/fonts/MesloLGS
fc-cache -f
fc-list | grep -i Meslo
```

---

## What you can do now (examples)

Everyday wins after these settings land (bash ≥ 4 on modern macOS / Linux; Apple `/bin/bash` 3.2 skips the bash‑4 features safely).

### Recursive globs (`globstar`)

```bash
# All Python tests under the tree (no find pipeline)
rg -n TODO -- **/*_test.py

# Delete build products anywhere below here
rm -rf **/__pycache__ **/*.o

# Open every README in the repo
v **/README.md
```

### Type a directory to enter it (`autocd`)

```bash
# Instead of: cd ~/work/ai/rusty-jack
~/work/ai/rusty-jack

# Or fuzzy-pick under ~/work/ai or ~/work/brk-tech (fzf when available):
cda                 # picker; . = ~/work/ai
cda rusty           # exact match, or fzf with query prefilled
cda .               # always ~/work/ai
cdb                 # picker (any dir under ~/work/brk-tech); . = ~/work/brk-tech
cdb gei<Tab>        # → reference-implementation/…/geico (basename match)
cdb candidate       # exact match, or fzf with query prefilled
cdb .               # always ~/work/brk-tech
```

Implementation: `_init_cd_work_project` / `_init_cd_project_apply_script_paths` in [`bashrc`](../bashrc) — on enter, prepend `scripts/` then `scripts/dev/` (dev wins on clashes); tracked dirs are stripped on the next jump so PATH does not accumulate.

### Smarter Tab completion

```bash
# Case-insensitive: type gith<Tab> → GitHub/ or git-helpers/
# Ambiguous matches list immediately (no double-Tab)
gi<Tab>
# → git  gitin  gitout  …

# With bash-completion@2 installed (modern macOS: brew install bash-completion@2):
git chec<Tab>       # → checkout / check-ignore / …
ssh mee<Tab>        # hostnames from known_hosts / config
```

### Fuzzy find history and files (`fzf`)

```bash
# Ctrl-R — substring search across loaded history (includes history.all bootstrap)
#   prefers matches at the start of a command, then elsewhere in the line
#   type: docker compose   → pick an old invocation that contains that text
#   no substring match     → Enter leaves what you typed on the line to edit/run
#   (character-fuzzy hits are disabled so random letter matches do not win)
#   syntax-error / command-not-found lines are not kept, so they never show up here

# Ctrl-T — insert file paths on the command line
#   vim <Ctrl-T>   → fuzzy-pick a file under cwd
#   (modern macOS: bat / lsd preview when those tools are installed)

# Alt-C (fzf cd into a fuzzy-picked directory; modern macOS: lsd tree preview)
#   Needs Option as Meta/Esc+ (otherwise macOS types ç):
#   iTerm: Profiles → Keys → Left Option key = Esc+  (Right Option can stay Normal for ç)
#   Terminal.app: Settings → Profiles → Keyboard → “Use Option as Meta key”

# fif <query> — ripgrep → fzf find-in-files; Enter opens $EDITOR at the line
#   (modern macOS: bat preview when bat is installed)

# cssh / cmsh / cesh with no args — fzf-pick from SSH config + known_hosts, then connect
#   cssh   # ssh
#   cmsh   # mosh (CSI-u / Shift+Enter do not reach the remote)
#   cesh   # Eternal Terminal (reconnectable; normal pty, CSI-u works)
# Tab completion mirrors ssh (cssh/cesh) / mosh (cmsh) when those completers exist
```

Soft defaults (only if unset / prior init-files Ctrl-R soft defaults): `FZF_DEFAULT_OPTS` height/layout/border; `FZF_CTRL_R_OPTS=--print-query --exact --tiebreak=begin,index` (substring history; unmatched query stays on the line); Ctrl-T / Alt-C previews when `bat`/`lsd` exist. Override in your environment anytime.

### Shared history across tabs

Open two Terminal tabs, run commands in each; both contribute to `history.all`. A **new** tab already has those commands in memory for `Ctrl-R` / fzf — you do not lose the other tab’s history when it exits.

### Know when bash (and friends) need an update

```bash
check_tool_versions
# bash: installed 5.3.15, latest 5.3.15, status: up to date, path: /opt/homebrew/bin/bash
# … or on Ubuntu: latest matches apt candidate (not stuck on "pending")
# fzf / bash-completion lines include install: … when missing

update_bash    # modern macOS brew / Linux package manager only — never on older macOS
update_tools   # all currently outdated tools (same OS-tier / admin-handoff rules)
```

If Terminal is still launching Apple `/bin/bash` 3.2, or a **stale** Homebrew Cellar path after `brew upgrade bash`, the tool report prints setup steps: `brew update && brew upgrade bash`, sudo-edit `/etc/shells` to add the **new Cellar** path (`…/Cellar/bash/<ver>/bin/bash`), then `chsh -s` that path. Apple’s `chpass` warns when a shell “is not a regular file”; the brew `bin` shim is a symlink, so macOS login shells typically use the Cellar realpath (and must be updated after each bash formula upgrade).

On Linux, if GNU upstream is unreachable, bash “latest” falls back to the **apt/dnf candidate** so the status line is never stuck on `latest check pending`.

---

## History management

### Layout

| Path | Role |
| --- | --- |
| `${XDG_STATE_HOME:-~/.local/state}/bash/history.<host>.<pid>.<timestamp>` | Per-session `HISTFILE` (unique file each shell) |
| `…/bash/history.all` | Shared append-only archive across sessions |
| `~/.bash_history` | Legacy file: read at bootstrap; also appended on shell exit |

### Flow

1. **`history_bootstrap`** — once per shell, loads legacy then `history.all` into memory (`history -r`), then sets the copy offsets to the current **session `HISTFILE`** size (≈ 0 for a fresh file), so sync only ever appends this session's own new bytes.
2. **`history_sync`** (via `PROMPT_COMMAND`, after `_init_history_scrub`) — `history -a` into the **session** `HISTFILE`, then byte-offset append of new bytes into `history.all`.
3. **`history_finalize`** (EXIT trap) — final sync, then append new session bytes into `~/.bash_history`.

`HISTFILE` is always a new file under `…/bash/history.<host>.<pid>.<timestamp>` (or the same file across a FORCE reload). Bash’s default `~/.bash_history` is never used as `HISTFILE` — using it caused `history_sync` to `tail` multi‑GB files into `history.all` and hang new shells.

The copy offsets (`bash_history_{archive,legacy}_bytes`) are positions **in the session `HISTFILE`**. An earlier bashrc mis-typed them as `history.all` / `~/.bash_history` *file sizes*; once a session's `HISTFILE` grew past that number, `history_append_since` started `tail`-ing from **mid-line** and spliced command fragments (`make insta1782398107`, bare `EOF`) into `history.all`. Fixed; `_init_history_sanitize_offsets` runs once at startup to clamp/snap any stale offset a long-lived shell carried over, and `init_files_history_rewrite_bounded` strips the fragments already in the archives on the next rotate.

Guards in `history_append_since` refuse to copy when `HISTFILE` is the archive/legacy file, equals the target, or is oversized.

### Rotate / dedupe (bounded archive)

Emergency trims after the HISTFILE hang left some hosts with multi‑tens‑of‑MB `history.all` files that were mostly duplicates. Interactive startup must **not** rewrite those files inline.

| Mechanism | Behavior |
| --- | --- |
| Soft schedule | Archive (or `~/.bash_history`) &gt; **16 MiB** or &gt; **100k** lines |
| Hard rewrite | Last **50k unique** commands or ≤ **8 MiB** (last occurrence wins; only `#[0-9]+` HISTTIMEFORMAT lines stay paired); also drops corruption — `word`+digit mashes, bare epoch lines, mid-line `#epoch` splices, control chars, 15+ char runs, orphan `EOF` / `done` / `}` |
| When | At most once per day (`…/bash/last-rotate`): background `rotate_bash_history -q` after interactive init / on EXIT schedule — **never** inside `history_sync` |
| Live shells | Skip archive appends while `rotate.lock` exists; on `last-rotate` change, clamp the session-`HISTFILE` copy offset to `[0, HISTFILE size]` so a later shrink cannot desync it |
| Sessions | Delete `history.<host>.<pid>.*` older than **14** days; keep at most **100** session files |
| Manual | `rotate_bash_history` (progress on stderr); then open a **new tab** or `source ~/.bashrc` so in-memory history reloads the shrunk archive |

Failures append to `…/bash/rotate.log`. Implementation: [`lib/history_rotate`](../lib/history_rotate) + `rotate_bash_history` in bashrc.

### Rebuild a shredded archive (`rebuild_bash_history`)

Hosts that ran the buggy pre-clamp bashrc for a while have a `history.all` where the mid-line `tail` splice hit **most** entries (`git configull --rebase`, `readlink -f …/bstart-development`) — too pervasive and varied to filter line-by-line. `rebuild_bash_history` reconstructs the archive from the sources the bug never reached:

1. per-session `history.<host>.<pid>.<ts>` files — `history_bootstrap` never reads them, so `history -a` wrote them clean
2. `~/.bash_history` — only lightly damaged
3. any command that **recurs** in `history.all` itself (`--freq N`, default 2 — repeated ≈ real; recovers depth on archives not yet deduped)

All of it runs through the same corruption filter + dedupe + cap. It backs up `history.all` and `~/.bash_history` to `${XDG_DATA_HOME:-~/.local/share}/init-files/history-rescue/<timestamp>/` first. `--dry-run` reports the before/after command counts and changes nothing. Run once per host; then open a new shell. Expect a large shrink (one host went 9.5k → ~430) — the lost lines are the shredded ones.

### `shopt` / `HIST*` related to history

| Setting | Effect |
| --- | --- |
| `histappend` | Append on exit instead of overwriting a shared `HISTFILE` (defense-in-depth; sessions already use unique files) |
| `cmdhist` | Multi-line commands stored as one history entry |
| `lithist` | Multi-line entries keep embedded newlines |
| `HISTCONTROL=ignoredups` | Skip consecutive duplicates |
| `HISTIGNORE='?:??:EOF:done:esac:…'` | Ignore 1-2 char commands and bare block/heredoc terminators |
| `HISTTIMEFORMAT='%F %T '` | Timestamp prefix in history listings |
| `HISTFILESIZE=-1` | Unlimited history file size |
| `HISTSIZE` | Empty on macOS/RHEL-family; `-1` elsewhere (unlimited where supported) |

### Ctrl-R hygiene (`_init_history_scrub`)

Bash adds an interactive line to the history list **before** it parses it, so a syntax error (`for x in`, an unbalanced quote) is remembered forever and `Ctrl-R` keeps surfacing it. `_init_history_scrub` runs as the **first** `PROMPT_COMMAND` hook — before `history_sync` writes anything out — and deletes the entry just added when:

- exit status is **2** and nothing actually executed → shell syntax error (a `DEBUG` trap, `_init_history_preexec`, flags whether a real command ran; a genuine command that merely exited 2 is kept)
- exit status is **127** → command not found (typo)
- the entry is a bare block / heredoc terminator (`EOF`, `done`, `fi`, `}`, …) from a paste or an archive round-trip

Set `INIT_FILES_HISTORY_SCRUB=0` to keep everything. Works in both plain and fancy (starship) prompts — under starship the real status comes from `STARSHIP_CMD_STATUS`, since starship's `eval "$STARSHIP_PROMPT_COMMAND"` has already reset `$?`.

### Searching history

- Built-in: reverse search (`Ctrl-R` in emacs mode; vi mode uses vi search bindings).
- With **fzf** installed: substring history search via fzf’s bash integration (typically `Ctrl-R`), searching **in-memory** history (already seeded from `history.all` at bootstrap). Ranking prefers a match at the start of the command, then elsewhere; with no substring hit, Enter keeps what you typed.

---

## Completion

### Always

- Custom: `cda` → `complete -o filenames -F _cda cda` (top-level only); `cdb` → `complete -o filenames -F _cdb cdb` (any depth; basename or path prefix)
- Custom: `agent` → `_init_files_agent_complete` (wrapper `-N`/`--name` + common CLI flags/commands); `resume_agent_session` → `--named`

### Readline (interactive)

| Setting | Effect |
| --- | --- |
| `show-all-if-ambiguous on` | List completions immediately when ambiguous |
| `mark-symlinked-directories on` | Trailing `/` on symlink-to-dir completions |
| `completion-ignore-case on` | Case-insensitive completion |
| `Ctrl-L` | Clear screen (bound explicitly) |

`set -o vi` is on; the `set …` readline options apply regardless of keymap. Tab does **not** cycle via `menu-complete` (lists instead).

### bash-completion (required on modern macOS)

`_init_load_bash_completion` sources a present entrypoint and never installs packages:

- Homebrew `…/etc/profile.d/bash_completion.sh` (when the file exists)
- `/usr/share/bash-completion/bash_completion`
- `/etc/bash_completion`
- `/usr/local/etc/…` variants

`provision_init_files` **requires** `bash-completion@2` on **modern macOS** (`brew install bash-completion@2`). Interactive bashrc loads it **before** `check_tool_versions` so the report shows the real version. On **older macOS**, do not install via Homebrew; only load a file if it is already there. On Linux it remains optional (apt/dnf).

### fzf (optional)

When `fzf` is on PATH / recorded as `init_tool_fzf`, `_init_load_fzf` enables integration:

- Prefer `eval "$(fzf --bash)"` (fzf ≥ 0.48; vi-mode aware)
- Else source `key-bindings.bash` (+ `completion.bash` when present): Homebrew layout, `$prefix/share/fzf/…`, Debian/Ubuntu `/usr/share/doc/fzf/examples/`, or `~/.fzf` / `~/.local`

Typical binds (fzf defaults): **Ctrl-R** history, **Ctrl-T** files, **Alt-C** cd.

On **modern macOS** and **Linux**, `provision_init_files` may offer optional `bat`, `lsd`, and `ripgrep` (Homebrew on modern macOS; apt on Debian/Ubuntu). When present:

- **Ctrl-T** previews files with `bat`/`batcat` (dirs with `lsd`, else `ls`)
- **Alt-C** previews directory trees the same way
- **`fif <query>`** — live ripgrep results in fzf; `bat` preview when available; Enter opens `$EDITOR` / vim at the line

Older macOS keeps plain fzf binds (no brew offers for bat/lsd/rg). `fif` still works wherever `rg` + `fzf` exist. Listing aliases (`ll` / `dir` / `lld` / `llm`) prefer `lsd` when available. When `aria2c` is installed, `aria` provides resumable, persistent, segmented downloads without file preallocation or post-download seeding.

Install hints from `./provision_init_files`:

| Tier | Hint |
| --- | --- |
| Modern macOS | `brew install fzf bat lsd ripgrep` |
| Older macOS | fzf via GitHub release → `~/.local` (**no brew**); bat/lsd/rg not offered |
| Linux | `sudo apt install fzf bat lsd ripgrep` (or dnf); Debian/Ubuntu may provide `bat` as `batcat` |

Implementation pointers in [`bashrc`](../bashrc): `_init_load_fzf` (prefer `fzf --bash`, else distro key-bindings), `_init_fzf_bindings_ready` (Ctrl-R must actually be bound), `_init_configure_fzf_env` / `_init_fzf_wrap_history_keep_query` (Ctrl-R keeps unmatched query), preview strings + `batcat`.

---

## Shell options / interactive behavior

| Option | Notes |
| --- | --- |
| `checkwinsize` | Update `LINES`/`COLUMNS` after each command |
| `cmdhist` / `lithist` / `histappend` | See history above |
| `globstar` | `**` recursive globs (bash ≥ 4; fail-soft on 3.2) |
| `autocd` | Typing a directory name `cd`s into it (bash ≥ 4) |
| `direxpand` | Expand `~` in completions (bash ≥ 4.2) |
| `set -o notify` | Report background job status immediately |
| `set -o vi` | Vi editing mode |

`globstar` / `autocd` / `direxpand` use `shopt -s … 2>/dev/null || true` so Apple `/bin/bash` 3.2 is unaffected.

---

## Bash version

`provision_init_files` records `init_tool_bash` (Apple `/bin/bash` on older macOS; Homebrew bash on modern). Interactive `check_tool_versions` reports the **running** shell (`$BASH` — what iTerm/login actually uses), with **platform-capped** “latest”:

| Tier | Reachable latest | Upgrade |
| --- | --- | --- |
| Modern macOS | Homebrew `bash` formula | `update_bash` → `brew update && brew upgrade bash`, then add new Cellar path to `/etc/shells` + `chsh` |
| Older macOS + Apple `/bin/bash` | Current `/bin/bash` (Apple-frozen 3.2.x) | No brew; status notes platform cap |
| Older macOS + Homebrew/other bash | GNU upstream (manual) | Never suggest `brew upgrade`; report the shell in use |
| Linux | Distro candidate when newer; else GNU upstream is **manual / upstream-only**. If upstream fetch fails, cache/report fall back to the distro candidate (no perpetual “pending”). | `update_bash` only when the package manager can apply |

On Linux, `update_git` / `update_bash` package-manager paths need `sudo`. If this account is **not** a sudoer (not in `sudo`/`wheel`, and no NOPASSWD), those helpers print a **forwardable admin command** instead of prompting for a password that cannot succeed. Real sudoers (group membership or `sudo -n`) still get the normal interactive upgrade. `check_tool_versions` lists those under **needs admin** in the `[tool updates]` footer (same `ask an admin: sudo …` text).

On **modern macOS** only: if this shell’s `$BASH` differs from preferred `init_tool_bash` (typically a stale Cellar path after `brew upgrade bash`), the tool report prints the Cellar `/etc/shells` + `chsh` steps. Older macOS never nags toward Apple `/bin/bash` or prints brew tips for a Homebrew login shell.

After adding newly tracked tools, an incomplete `latest` cache or a report missing the `bash:` line forces a rebuild (so you are not stuck on a day-old report).

When the report has outdated tools, `check_tool_versions` also writes a small **`pending-updates`** TSV sidecar (`tool`, `installed`, `path`). On later shells the fast path cheaply re-probes those installed versions; if any drifted (admin apt/brew, etc.), the report rebuilds immediately — no 24h wait and no manual `invalidate_tool_version_cache`.

The `[tool updates]` section lists each outdated tool once (no per-tool `suggested command`). At the bottom it splits **this account** (`update_tools`) vs **needs admin** (`ask an admin: …`). On a TTY, the first shell that prints that report offers `Upgrade outdated tools now (…)? [Y/n]` once per daily `last-check` (rebuild **or** cached reprint); further shells only show the footer. Concurrent interactive shells share a **rebuild lock** so only one session runs the check, and an **offer lock** so only one prompts.

```bash
invalidate_tool_version_cache   # optional nudge
check_tool_versions
update_tools                    # upgrade all currently pending tools this account can
```

`update_tools` runs the same per-tool helpers (`update_git`, `update_bash`, …) and admin-handoff rules, then invalidates the daily report. Tools already upgraded out-of-band are skipped.

Implementation: `refresh_tool_version_cache` in [`bashrc`](../bashrc) fetches unlocked then publishes under `lib/tool_version_cache` lock/atomic write (#26). Distro fallbacks avoid perpetual “pending” when upstream APIs fail. Rebuild serialization uses `${tool_version_state_dir}/rebuild.lock` (waiters reuse a just-published report even when a background `latest` refresh bumps cache mtime). The Y/n offer is `_tool_version_maybe_offer_update_tools` (stamp `update-offer-done` keyed to `last-check`; sidecar `pending-self-names` for cached reprints).

---

## Related issues

- [#3](https://github.com/thehcma/init-files/issues/3) bash version tracking  
- [#4](https://github.com/thehcma/init-files/issues/4) globstar / autocd  
- [#5](https://github.com/thehcma/init-files/issues/5) completion / readline  
- [#6](https://github.com/thehcma/init-files/issues/6) histappend / history audit  
- [#7](https://github.com/thehcma/init-files/issues/7) fzf  
- [#8](https://github.com/thehcma/init-files/issues/8) this documentation  
- [#25](https://github.com/thehcma/init-files/issues/25) why-comments for complex helpers (cd-project PATH, fzf load, tool-version cache)  
