# Canonical interactive bashrc for macOS (Darwin 21.6+) and Linux
# shellcheck shell=bash
# (Ubuntu, CentOS, Rocky through 8.10). Managed via:
#   https://github.com/thehcma/init-files
#
# Layout on disk:
#   ~/.local/share/init-files     git clone (this file lives here as bashrc)
#   ~/.bashrc                     symlink -> ~/.local/share/init-files/bashrc
#   ~/.config/init-files/tools.<hostname>  host tool paths (NFS-safe)
#
# Install / refresh:
#   ~/.local/share/init-files/provision_init_files [--no-dev|--dev]  # tools + symlinks + ssh
#   refresh_init_files [--no-dev|--dev] [--github-https|--github-ssh] [--no-iterm]
#   refresh_init_files -q                                   # daily: offer pull / deploy repair
#   --no-dev persists under ~/.config/init-files/no-dev.<hostname>
# Daily: tool-version status (once/day) + main move + private config overlay + local deploy drift (offer update).

# File layout inside this script: lexicographically sorted functions,
# environment, aliases, shell options, and initialization.

# Absolute tool paths from `provision_init_files` (see ~/.config/init-files/tools.<hostname>).
# Host scope matches PS1: macOS ComputerName (not Bonjour LocalHostName / hostname -s).
# Bump when provision's record_tool set changes (keep in sync with provision_init_files).
INIT_FILES_TOOLS_REVISION=10
# Defined before tools load so we do not depend on init_tool_scutil.
_init_files_raw_host_label()
{
    local scutil_bin name
    if [[ "${OSTYPE:-}" == darwin* ]]; then
        scutil_bin="$(command -v scutil 2>/dev/null || true)"
        [[ -n "$scutil_bin" ]] || scutil_bin=/usr/sbin/scutil
        if [[ -x "$scutil_bin" ]]; then
            name="$("$scutil_bin" --get ComputerName 2>/dev/null || true)"
            if [[ -n "$name" ]]; then
                printf '%s\n' "$name"
                return 0
            fi
        fi
    fi
    hostname -s 2>/dev/null || hostname 2>/dev/null || echo host
}

_init_files_sanitize_host()
{
    local host="${1:-}"
    host="${host%%.*}"
    host="${host//[^A-Za-z0-9._-]/_}"
    [[ -n "$host" ]] || host="unknown-host"
    printf '%s\n' "$host"
}

init_files_config_dir="${init_files_config_dir:-${XDG_CONFIG_HOME:-$HOME/.config}/init-files}"
init_files_host="$(_init_files_sanitize_host "$(_init_files_raw_host_label)")"
# Exported so ~/.local/bin/pipx shim (non-interactive) can resolve the host tree.
export init_files_host

if [[ -z "${init_files_tools_file:-}" ]]; then
    if [[ -f "$init_files_config_dir/tools.${init_files_host}" ]]; then
        init_files_tools_file="$init_files_config_dir/tools.${init_files_host}"
    elif [[ -f "$init_files_config_dir/tools" ]]; then
        init_files_tools_file="$init_files_config_dir/tools"
    elif [[ -f "$init_files_config_dir/tools.sh" ]]; then
        init_files_tools_file="$init_files_config_dir/tools.sh"
    else
        init_files_tools_file="$init_files_config_dir/tools.${init_files_host}"
    fi
fi
# Shared verification with provision_init_files (clean break: lib/tool_path only).
_init_files_clone_dir="${init_files_dir:-${XDG_DATA_HOME:-$HOME/.local/share}/init-files}"
if [[ -f "${_init_files_clone_dir}/lib/tool_path" ]]; then
    # shellcheck disable=SC1091
    . "${_init_files_clone_dir}/lib/tool_path"
else
    # Incomplete clone — refuse to trust recorded paths without the shared verifier.
    printf 'init-files: missing %s/lib/tool_path (run refresh_init_files)\n' \
        "$_init_files_clone_dir" >&2
fi
if [[ -f "${_init_files_clone_dir}/lib/host_paths" ]]; then
    # shellcheck disable=SC1091
    . "${_init_files_clone_dir}/lib/host_paths"
fi
if [[ -f "${_init_files_clone_dir}/lib/config_paths" ]]; then
    # shellcheck disable=SC1091
    . "${_init_files_clone_dir}/lib/config_paths"
fi
if [[ -f "${_init_files_clone_dir}/lib/tool_version_cache" ]]; then
    # shellcheck disable=SC1091
    . "${_init_files_clone_dir}/lib/tool_version_cache"
fi
if [[ -f "${_init_files_clone_dir}/lib/interactive_input" ]]; then
    # shellcheck disable=SC1091
    . "${_init_files_clone_dir}/lib/interactive_input"
fi
if [[ -f "${_init_files_clone_dir}/lib/history_rotate" ]]; then
    # shellcheck disable=SC1091
    . "${_init_files_clone_dir}/lib/history_rotate"
fi
if [[ -f "${_init_files_clone_dir}/lib/iterm_host_label" ]]; then
    # shellcheck disable=SC1091
    . "${_init_files_clone_dir}/lib/iterm_host_label"
fi
unset _init_files_clone_dir

if [[ -f "$init_files_tools_file" ]]; then
    # shellcheck disable=SC1090
    . "$init_files_tools_file"
fi

# NFS-shared homes may still have a legacy unscoped tools file from another OS
# (e.g. Homebrew paths on Debian). Drop recorded paths that fail the shared
# verifier — no legacy -x-only fallback.
if [[ -f "${init_files_tools_file:-}" ]]; then
    for _init_files_tool_var in $(compgen -v init_tool_ 2>/dev/null); do
        _init_files_tool_val="${!_init_files_tool_var-}"
        [[ -n "$_init_files_tool_val" ]] || continue
        if ! declare -F init_files_verify_tool_path > /dev/null 2>&1 \
            || ! init_files_verify_tool_path "$_init_files_tool_val"; then
            printf -v "$_init_files_tool_var" '%s' ''
        fi
    done
    unset _init_files_tool_var _init_files_tool_val
fi

# Idempotent load: Debian ~/.profile often sources ~/.bashrc, and our login
# hook may also source it. Allow an explicit reload after refresh_init_files via
# INIT_FILES_BASHRC_FORCE=1 (or unset INIT_FILES_BASHRC_LOADED first).
if [[ -n "${INIT_FILES_BASHRC_LOADED:-}" && -z "${INIT_FILES_BASHRC_FORCE:-}" ]]; then
    # This guard is reached when bash sources the file.
    # shellcheck disable=SC2317
    return 0 2>/dev/null || true
fi
INIT_FILES_BASHRC_LOADED=1
unset INIT_FILES_BASHRC_FORCE
# Record which clone revision this shell loaded (refresh_init_files reloads when HEAD moves,
# including when another process already updated the clone on this host).
INIT_FILES_BASHRC_LOADED_SHA=
if [[ -d "${init_files_dir:-${XDG_DATA_HOME:-$HOME/.local/share}/init-files}/.git" ]]; then
    INIT_FILES_BASHRC_LOADED_SHA=$(
        ${init_tool_git:-git} -C "${init_files_dir:-${XDG_DATA_HOME:-$HOME/.local/share}/init-files}" \
            rev-parse HEAD 2>/dev/null || true
    )
fi

: "${init_tool_bash:=}"
: "${init_tool_bat:=}"
: "${init_tool_bc:=}"
: "${init_tool_clear:=}"
: "${init_tool_cmp:=}"
: "${init_tool_colordiff:=}"
: "${init_tool_corepack:=}"
: "${init_tool_curl:=}"
: "${init_tool_et:=}"
: "${init_tool_fzf:=}"
: "${init_tool_gdb:=}"
: "${init_tool_git:=}"
: "${init_tool_google_chrome:=}"
: "${init_tool_gpg:=}"
: "${init_tool_grep:=}"
: "${init_tool_gvim:=}"
: "${init_tool_killall:=}"
: "${init_tool_kwin:=}"
: "${init_tool_launchctl:=}"
: "${init_tool_less:=}"
: "${init_tool_litra:=}"
: "${init_tool_ln:=}"
: "${init_tool_ls:=}"
: "${init_tool_lsb_release:=}"
: "${init_tool_lsd:=}"
: "${init_tool_make:=}"
: "${init_tool_more:=}"
: "${init_tool_mosh:=}"
: "${init_tool_mvim:=}"
: "${init_tool_node:=}"
: "${init_tool_npm:=}"
: "${init_tool_open:=}"
: "${init_tool_osascript:=}"
: "${init_tool_patch:=}"
: "${init_tool_pnpm:=}"
: "${init_tool_python3:=}"
: "${init_tool_rg:=}"
: "${init_tool_rm:=}"
: "${init_tool_rsync:=}"
: "${init_tool_scutil:=}"
: "${init_tool_ssh:=}"
: "${init_tool_ssh_add:=}"
: "${init_tool_ssh_agent:=}"
: "${init_tool_ssh_keygen:=}"
: "${init_tool_system_profiler:=}"
: "${init_tool_terminator:=}"
: "${init_tool_vim:=}"
: "${init_tool_vlc:=}"
: "${init_tool_vncconfig:=}"
: "${init_tool_vncserver:=}"

###### functions

function _cda()
{
    _init_cd_work_complete "${HOME}/work/ai"
}

function _cdb()
{
    _init_cd_work_complete "${HOME}/work/brk-tech"
}

# Dirs that cda/cdb last prepended to PATH (colon-separated); cleared/replaced
# on the next cda/cdb entry (shared so switching trees does not leak PATH).
_init_cd_project_script_path_dirs=

# cda/cdb: when entering a project, prepend that project's scripts/ then
# scripts/dev/ so scripts/dev wins on name clashes. Track dirs in
# _init_cd_project_script_path_dirs so the next jump (or leave) can strip them
# and PATH does not accumulate across projects. See docs/shell-ux.md (cda/cdb).
function _init_cd_project_apply_script_paths()
{
    local project_dir="${1:-}" dir already old_ifs

    if [[ -n "${_init_cd_project_script_path_dirs:-}" ]]; then
        old_ifs="$IFS"
        IFS=':'
        for dir in ${_init_cd_project_script_path_dirs}; do
            _init_path_remove "$dir"
        done
        IFS="$old_ifs"
        _init_cd_project_script_path_dirs=
    fi

    [[ -n "$project_dir" && -d "$project_dir" ]] || return 0

    # Prepend scripts before scripts/dev so scripts/dev wins on name clashes.
    for dir in "$project_dir/scripts" "$project_dir/scripts/dev"; do
        [[ -d "$dir" ]] || continue
        already=0
        case ":$PATH:" in
            *":$dir:"*) already=1 ;;
        esac
        if (( already )); then
            continue
        fi
        PATH="$dir:$PATH"
        if [[ -n "${_init_cd_project_script_path_dirs:-}" ]]; then
            _init_cd_project_script_path_dirs+=":$dir"
        else
            _init_cd_project_script_path_dirs="$dir"
        fi
    done
}

function _init_cd_work_complete()
{
    local cur base="${1:-}"
    cur="${COMP_WORDS[COMP_CWORD]}"
    [[ -n "$base" && -d "$base" ]] || return 0
    # compgen intentionally emits one completion per word.
    # shellcheck disable=SC2207
    COMPREPLY=( $(cd -- "$base" && compgen -d -- "$cur") )
}

# Shared body for cda / cdb (and future ~/work/* jumpers).
# Usage: _init_cd_work_project <cmd> <base> [name]
function _init_cd_work_project()
{
    local cmd="${1:-cd}" base="${2:-}" base_disp target fzf_bin picked query preview_cmd list_bin
    shift 2 || true

    base_disp="$base"
    if [[ -n "${HOME:-}" && "$base" == "$HOME"/* ]]; then
        base_disp="~${base#"$HOME"}"
    elif [[ -n "${HOME:-}" && "$base" == "$HOME" ]]; then
        base_disp='~'
    fi

    case "${1:-}" in
        -h|--help)
            cat <<EOF
Usage: ${cmd} [name]

Change to a project directory under ${base_disp}.

  ${cmd}              fuzzy-pick a project with fzf (falls back to ${base_disp}
                   if fzf is missing or stdin is not a TTY)
  ${cmd} .            cd to ${base_disp}
  ${cmd} <name>       cd to ${base_disp}/<name> when it exists; otherwise open
                   fzf with that string as the initial query

Tab-completes subdirectory names under ${base_disp}.

When entering a project, prepends that project's scripts/ and scripts/dev/
(if present) to PATH. Leaving via ${cmd} (no args or another project), or
switching via a sibling jumper (cda/cdb), removes those entries.
EOF
            return 0
            ;;
    esac

    if [[ -z "$base" || ! -d "$base" ]]; then
        echo "${cmd}: ${base_disp:-<empty>} does not exist" >&2
        return 1
    fi

    if [[ $# -eq 1 && "$1" == "." ]]; then
        _init_cd_project_apply_script_paths
        cd -- "$base" || return
        return
    fi

    if [[ $# -eq 1 && -d "$base/$1" ]]; then
        target="$base/$1"
        cd -- "$target" || return
        _init_cd_project_apply_script_paths "$target"
        return
    fi

    if [[ $# -gt 1 ]]; then
        echo "Usage: ${cmd} [name]" >&2
        return 1
    fi

    # No args, or one unknown name → fzf (query prefilled when a name was given).
    query="${1:-}"
    fzf_bin="${init_tool_fzf:-}"
    [[ -n "$fzf_bin" && -x "$fzf_bin" ]] || fzf_bin="$(command -v fzf 2>/dev/null || true)"

    if [[ -z "$fzf_bin" || ! -x "$fzf_bin" || ! -t 0 ]]; then
        if [[ -n "$query" ]]; then
            echo "${cmd}: no such directory under ${base_disp}: $query" >&2
            return 1
        fi
        _init_cd_project_apply_script_paths
        cd -- "$base" || return
        return
    fi

    preview_cmd='ls -la --color=always {} 2>/dev/null || ls -la {}'
    list_bin="$(command -v lsd 2>/dev/null || true)"
    [[ -n "${init_tool_lsd:-}" && -x "${init_tool_lsd}" ]] && list_bin="$init_tool_lsd"
    if [[ -n "$list_bin" && -x "$list_bin" ]]; then
        preview_cmd="${list_bin} -la --color=always {}"
    fi

    picked="$(
        {
            printf '%s\n' .
            # Include directory symlinks (-type d alone skips them on BSD/GNU find).
            find "$base" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) ! -name '.*' -print \
                | while IFS= read -r path; do
                    [[ -d "$path" ]] || continue
                    printf '%s\n' "${path#"${base}/"}"
                done | LC_ALL=C sort
        } | "$fzf_bin" \
            --height=40% \
            --reverse \
            --prompt="${cmd} > " \
            --header="$base  (enter project; . = this dir)" \
            --preview "cd -- $(printf '%q' "$base") && $preview_cmd" \
            ${query:+--query="$query"}
    )" || true

    [[ -n "$picked" ]] || {
        echo "${cmd}: cancelled" >&2
        return 1
    }

    if [[ "$picked" == "." ]]; then
        _init_cd_project_apply_script_paths
        cd -- "$base" || return
        return
    fi

    target="$base/$picked"
    if [[ ! -d "$target" ]]; then
        echo "${cmd}: no such directory under ${base_disp}: $picked" >&2
        return 1
    fi
    cd -- "$target" || return
    _init_cd_project_apply_script_paths "$target"
}

# True when this shell can reach a graphical display (browser / GUI open).
# macOS: Aqua session (launchctl managername). Linux: accessible Wayland or X11.
function _init_has_display()
{
    local launchctl_bin runtime sock display_num

    if _init_is_darwin; then
        launchctl_bin="${init_tool_launchctl:-}"
        [[ -n "$launchctl_bin" && -x "$launchctl_bin" ]] \
            || launchctl_bin="$(command -v launchctl 2>/dev/null || true)"
        [[ -n "$launchctl_bin" ]] || return 1
        [[ "$("$launchctl_bin" managername 2>/dev/null)" == Aqua ]]
        return
    fi

    runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

    if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        sock="$runtime/$WAYLAND_DISPLAY"
        [[ -S "$sock" || -S "$WAYLAND_DISPLAY" ]]
        return
    fi

    [[ -n "${DISPLAY:-}" ]] || return 1

    # Prefer a live probe when xset is available.
    if command -v xset >/dev/null 2>&1; then
        xset q >/dev/null 2>&1
        return
    fi

    # Fallback: local X11 unix socket (:0, localhost:10.0, …).
    display_num="${DISPLAY##*:}"
    display_num="${display_num%%.*}"
    case "$display_num" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [[ -S "/tmp/.X11-unix/X${display_num}" \
        || -S "${runtime}/.X11-unix/X${display_num}" ]]
}

function _init_host_label()
{
    # Same resolver as init_files_host (macOS ComputerName); display keeps raw label.
    _init_files_raw_host_label
}


function _init_is_darwin()
{
    [[ "${OSTYPE:-}" == darwin* ]]
}

# True when $1 (default: $USER) is on the quiet-prompt allowlist
# (INIT_FILES_DEFAULT_USERS). Used by classic PS1 / INIT_FILES_ALT_USER.
# Callers may optionally check a user other than $USER.
# shellcheck disable=SC2120
function _init_is_default_user()
{
    local u candidate
    u="${1:-${USER:-}}"
    [[ -n "$u" ]] || return 1
    # No allowlist configured (public/generic install) — no alt-user highlighting.
    [[ -n "${INIT_FILES_DEFAULT_USERS:-}" ]] || return 0
    # Intentional word-split of the space-separated allowlist.
    # shellcheck disable=SC2086
    for candidate in ${INIT_FILES_DEFAULT_USERS}; do
        [[ "$u" == "$candidate" ]] && return 0
    done
    return 1
}

function _init_is_rocky_8_1()
{
    local id version_id
    [[ -r /etc/os-release ]] || return 1
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    version_id="${VERSION_ID:-}"
    [[ "$id" == "rocky" && "$version_id" == "8.1" ]]
}

# Push ssh/et/mosh vs "local" into iTerm user.hostlabel (pane status bar, right).
function _init_iterm_report_host_label()
{
    local label

    [[ $- == *i* ]] || return 0
    declare -F init_files_iterm_session_host_label > /dev/null 2>&1 || return 0
    declare -F init_files_iterm_emit_host_label > /dev/null 2>&1 || return 0

    label="$(init_files_iterm_session_host_label)"
    [[ -n "$label" ]] || return 0
    [[ "$label" == "${_init_iterm_host_label_last-}" ]] && return 0
    init_files_iterm_emit_host_label "$label" || return 0
    _init_iterm_host_label_last="$label"
}

# Set the pane label from cssh/cesh/cmsh destination before the hop blocks this shell.
function _init_iterm_mark_hop()
{
    local dest label

    declare -F init_files_iterm_dest_from_args > /dev/null 2>&1 || return 0
    declare -F init_files_iterm_short_label > /dev/null 2>&1 || return 0
    declare -F init_files_iterm_emit_host_label > /dev/null 2>&1 || return 0
    dest="$(init_files_iterm_dest_from_args "$@")" || return 0
    [[ -n "$dest" ]] || return 0
    label="$(init_files_iterm_short_label "$dest")"
    [[ -n "$label" ]] || return 0
    init_files_iterm_emit_host_label "$label" || return 0
    _init_iterm_host_label_last="$label"
}

function _init_iterm_unmark_hop()
{
    _init_iterm_host_label_last=""
    _init_iterm_report_host_label
}

# Source bash-completion when already installed. Never installs packages;
# older macOS must not be nudged toward brew — only load a present file.
function _init_load_bash_completion()
{
    local candidate brew_prefix

    [[ $- == *i* ]] || return 0
    # Already loaded (bash-completion v2 sets this).
    [[ -n "${BASH_COMPLETION_VERSINFO:-}" ]] && return 0

    brew_prefix=
    if type _init_homebrew_prefix > /dev/null 2>&1; then
        brew_prefix="$(_init_homebrew_prefix 2>/dev/null || true)"
    fi

    for candidate in \
        "${BASH_COMPLETION:-}" \
        "${brew_prefix:+$brew_prefix/etc/profile.d/bash_completion.sh}" \
        /usr/share/bash-completion/bash_completion \
        /etc/bash_completion \
        /usr/local/etc/profile.d/bash_completion.sh \
        /usr/local/etc/bash_completion
    do
        [[ -n "$candidate" && -r "$candidate" ]] || continue
        # shellcheck disable=SC1090
        . "$candidate" && return 0
    done
    return 1
}

# True when fzf history integration is actually bound (not merely sourced).
# Empty/failed `eval "$(fzf --bash)"` still exits 0 — we must see Ctrl-R wired
# in vi-insert or emacs before treating load as success. See docs/shell-ux.md.
function _init_fzf_bindings_ready()
{
    type __fzf_history__ > /dev/null 2>&1 || type fzf-history-widget > /dev/null 2>&1 || return 1
    # Confirm Ctrl-R is wired in vi-insert or emacs (bind prints literal \C-r).
    bind -m vi-insert -X 2> /dev/null | grep -q '\\C-r' && return 0
    bind -m emacs-standard -X 2> /dev/null | grep -q '\\C-r' && return 0
    # Older key-bindings use macro inserts instead of -x.
    bind -m vi-insert -P 2> /dev/null | grep -qE '\\C-r.*(fzf|__fzf)' && return 0
    bind -m emacs-standard -P 2> /dev/null | grep -qE '\\C-r.*(fzf|__fzf)' && return 0
    return 1
}

# Resolve init_tool_* or PATH for a short tool name. Prints path or nothing.
function _init_fzf_tool_bin()
{
    local name="$1"
    local var path

    var="init_tool_${name}"
    path="${!var:-}"
    if [[ -n "$path" && -x "$path" ]]; then
        printf '%s' "$path"
        return 0
    fi
    command -v "$name" 2>/dev/null || true
}

# Soft FZF_* defaults. bat/lsd previews when those tools are present (any OS).
# Does not override vars the user already set. Preview opts must be a single
# shell command string (fzf contract) — hence SC2089/SC2090. Debian ships bat
# as batcat. See docs/shell-ux.md (fzf).
function _init_configure_fzf_env()
{
    local bat_bin lsd_bin dir_preview file_preview

    : "${FZF_DEFAULT_OPTS:=--height 40% --layout=reverse --border --info=inline}"

    bat_bin="$(_init_fzf_tool_bin bat)"
    # Debian/Ubuntu often ship the binary as batcat.
    [[ -n "$bat_bin" ]] || bat_bin="$(_init_fzf_tool_bin batcat)"
    lsd_bin="$(_init_fzf_tool_bin lsd)"

    if [[ -n "$lsd_bin" ]]; then
        dir_preview="${lsd_bin} --tree --depth 2 --color=always {}"
    else
        dir_preview='ls -la {}'
    fi

    if [[ -n "$bat_bin" ]]; then
        file_preview="${bat_bin} --style=numbers --color=always --line-range :500 -- {}"
    else
        file_preview='head -n 200 {}'
    fi

    if [[ -z "${FZF_CTRL_T_OPTS:-}" ]]; then
        # fzf requires this preview as one shell command string.
        # shellcheck disable=SC2089
        FZF_CTRL_T_OPTS="--preview 'if [[ -d {} ]]; then ${dir_preview}; else ${file_preview}; fi'"
        # The quoted command is intentionally exported literally.
        # shellcheck disable=SC2090
        export FZF_CTRL_T_OPTS
    fi
    if [[ -z "${FZF_ALT_C_OPTS:-}" ]]; then
        # fzf requires this preview as one shell command string.
        # shellcheck disable=SC2089
        FZF_ALT_C_OPTS="--preview '${dir_preview}'"
        # The quoted command is intentionally exported literally.
        # shellcheck disable=SC2090
        export FZF_ALT_C_OPTS
    fi
}

# Optional fzf keybindings/completion. Fail closed when fzf is missing.
# History search uses bash's in-memory history (already bootstrapped from
# history.all); Ctrl-T / Alt-C use fzf defaults when available.
#
# Load order (why): prefer `fzf --bash` (≥0.48, vi-mode aware). Only accept it
# when _init_fzf_bindings_ready — empty hook must not short-circuit. Else walk
# Homebrew/distro key-bindings.bash locations and require Ctrl-R bound before
# sourcing completion.bash. See docs/shell-ux.md (fzf).
function _init_load_fzf()
{
    local fzf_bin brew_prefix base candidate hook

    [[ $- == *i* ]] || return 0

    fzf_bin="${init_tool_fzf:-}"
    if [[ -z "$fzf_bin" || ! -x "$fzf_bin" ]]; then
        fzf_bin="$(command -v fzf 2>/dev/null || true)"
    fi
    [[ -n "$fzf_bin" && -x "$fzf_bin" ]] || return 1

    _init_configure_fzf_env
    export FZF_DEFAULT_OPTS

    # fzf ≥0.48: single --bash hook (works with vi mode keymaps).
    # Do not treat an empty/failed hook as success (eval "" is exit 0) — fall
    # through to distro key-bindings.bash (EPEL/Fedora share/fzf/shell, etc.).
    if "$fzf_bin" --help 2>&1 | grep -q -- '--bash'; then
        hook="$("$fzf_bin" --bash 2> /dev/null)" || hook=
        if [[ -n "$hook" ]]; then
            eval "$hook" 2> /dev/null || true
            _init_fzf_bindings_ready && return 0
        fi
    fi

    brew_prefix=
    if type _init_homebrew_prefix > /dev/null 2>&1; then
        brew_prefix="$(_init_homebrew_prefix 2>/dev/null || true)"
    fi
    base="$(dirname -- "$(dirname -- "$fzf_bin")")"
    # Prefer fzf --bash when available (above). Older distro packages (e.g.
    # Ubuntu 0.44) ship key-bindings only; Debian/Ubuntu put them under
    # /usr/share/doc/fzf/examples/, Fedora/RHEL/EPEL under share/fzf/shell/.
    for candidate in \
        "${brew_prefix:+$brew_prefix/opt/fzf/shell/key-bindings.bash}" \
        "$base/opt/fzf/shell/key-bindings.bash" \
        "$base/share/fzf/shell/key-bindings.bash" \
        "$base/share/fzf/key-bindings.bash" \
        "$base/shell/key-bindings.bash" \
        /usr/share/doc/fzf/examples/key-bindings.bash \
        /usr/share/fzf/shell/key-bindings.bash \
        /usr/share/fzf/key-bindings.bash \
        "${XDG_DATA_HOME:-$HOME/.local/share}/fzf/shell/key-bindings.bash" \
        "$HOME/.fzf/shell/key-bindings.bash"
    do
        [[ -n "$candidate" && -r "$candidate" ]] || continue
        # shellcheck disable=SC1090
        . "$candidate" 2> /dev/null || continue
        if ! _init_fzf_bindings_ready; then
            continue
        fi
        candidate="${candidate/key-bindings.bash/completion.bash}"
        if [[ -r "$candidate" ]]; then
            # shellcheck disable=SC1090
            . "$candidate" || true
        fi
        return 0
    done
    return 1
}

function _init_load_node_toolchain()
{
    local fnm_bin fnm_dir node_cmd nvm_bin candidate

    # Prefer fnm/nvm (user-local) over any Homebrew npm already on PATH.
    # Prefer fnm when present (fast, no heavy shell hook).
    for fnm_dir in \
        "${XDG_DATA_HOME:-$HOME/.local/share}/fnm" \
        "$HOME/.local/share/fnm"
    do
        fnm_bin=
        if command -v fnm > /dev/null 2>&1; then
            fnm_bin=$(command -v fnm)
        elif [[ -x "$fnm_dir/fnm" ]]; then
            fnm_bin="$fnm_dir/fnm"
        fi
        if [[ -n "$fnm_bin" && -d "$fnm_dir" ]]; then
            export PATH="$fnm_dir:$PATH"
            eval "$("$fnm_bin" env --shell bash)" 2> /dev/null && return 0
        fi
    done

    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        # shellcheck disable=SC1091
        . "$NVM_DIR/nvm.sh"
        # nvm use can report success while Homebrew still wins on a mangled PATH
        # (brew prepended after an earlier load, or "system" current). Always
        # resolve an NVM_DIR node and prepend its bin.
        nvm use default >/dev/null 2>&1 \
            || nvm use --lts >/dev/null 2>&1 \
            || nvm use node >/dev/null 2>&1 \
            || true
        node_cmd="$(command -v node 2>/dev/null || true)"
        if [[ -z "$node_cmd" ]] || _init_path_is_homebrew "$node_cmd"; then
            node_cmd="$(nvm which default 2>/dev/null || true)"
        fi
        if [[ -z "$node_cmd" || ! -x "$node_cmd" ]] || _init_path_is_homebrew "$node_cmd"; then
            node_cmd="$(nvm which current 2>/dev/null || true)"
        fi
        if [[ -z "$node_cmd" || ! -x "$node_cmd" ]] || _init_path_is_homebrew "$node_cmd"; then
            node_cmd=""
            for candidate in "$NVM_DIR"/versions/node/*/bin/node; do
                [[ -x "$candidate" ]] || continue
                node_cmd="$candidate"
            done
        fi
        if [[ -n "$node_cmd" && -x "$node_cmd" ]] && ! _init_path_is_homebrew "$node_cmd"; then
            nvm_bin="$(cd "$(dirname "$node_cmd")" && pwd)"
            _init_path_prepend "$nvm_bin"
            hash -r 2>/dev/null || true
        fi
        return 0
    fi

    # No fnm/nvm — leave whatever npm is already on PATH (e.g. brew fallback).
    command -v npm > /dev/null 2>&1
}

function _init_npm_command()
{
    # Prefer fnm/nvm when installed so brew npm is not returned first.
    if [[ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]] \
        || command -v fnm > /dev/null 2>&1 \
        || [[ -x "${XDG_DATA_HOME:-$HOME/.local/share}/fnm/fnm" ]] \
        || [[ -x "$HOME/.local/share/fnm/fnm" ]]
    then
        _init_load_node_toolchain > /dev/null 2>&1 || true
    fi
    if command -v npm > /dev/null 2>&1; then
        command -v npm
        return 0
    fi
    if [[ -n "${init_tool_npm:-}" && -x "$init_tool_npm" ]]; then
        printf '%s' "$init_tool_npm"
        return 0
    fi
    _init_load_node_toolchain > /dev/null 2>&1 || true
    command -v npm 2> /dev/null || return 1
}

# True when path resolves into Homebrew (Cellar / opt / prefix).
function _init_path_is_homebrew()
{
    local path="$1" resolved brew_prefix

    [[ -n "$path" ]] || return 1
    resolved="$path"
    if [[ -e "$path" ]]; then
        if [[ -n "${init_tool_python3:-}" && -x "${init_tool_python3:-}" ]]; then
            resolved=$("$init_tool_python3" -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path" 2>/dev/null || true)
        fi
        [[ -n "$resolved" ]] || resolved=$(readlink "$path" 2>/dev/null || printf '%s' "$path")
    fi
    case "$path" in
        /opt/homebrew/*|*/homebrew/*|/usr/local/Cellar/*|/usr/local/Homebrew/*|/usr/local/opt/*) return 0 ;;
    esac
    case "$resolved" in
        /opt/homebrew/*|*/homebrew/*|/usr/local/Cellar/*|/usr/local/Homebrew/*|/usr/local/opt/*|*/Cellar/*) return 0 ;;
    esac
    if type _init_homebrew_prefix > /dev/null 2>&1; then
        brew_prefix="$(_init_homebrew_prefix 2>/dev/null || true)"
        if [[ -n "$brew_prefix" && ( "$path" == "$brew_prefix"/* || "$resolved" == "$brew_prefix"/* ) ]]; then
            return 0
        fi
    fi
    return 1
}

# Run npm with its sibling node first on PATH.
# nvm/fnm npm shims use `#!/usr/bin/env node`; with Homebrew ahead on PATH,
# `npm prefix -g` otherwise reports a Cellar prefix and looks "non-user-local".
function _init_npm_exec()
{
    local npm_cmd="$1" dir
    shift
    [[ -n "$npm_cmd" && -x "$npm_cmd" ]] || return 1
    dir="$(cd "$(dirname "$npm_cmd")" && pwd)" || return 1
    PATH="$dir:$PATH" "$npm_cmd" "$@"
}

# True when npm's global prefix is writable by this user (safe for npm -g).
function _init_npm_global_prefix_writable()
{
    local npm_cmd="$1" prefix

    [[ -n "$npm_cmd" && -x "$npm_cmd" ]] || return 1
    # Reject Homebrew npm before invoking it (avoids Cellar prefix noise).
    if _init_path_is_homebrew "$npm_cmd"; then
        return 1
    fi
    prefix="$(_init_npm_exec "$npm_cmd" prefix -g 2>/dev/null || true)"
    [[ -n "$prefix" ]] || return 1
    # Homebrew prefixes are never treated as user-local even if somehow writable.
    if _init_path_is_homebrew "$prefix"; then
        return 1
    fi
    [[ -w "$prefix" ]] || [[ -d "$prefix" && -w "$(dirname "$prefix")" ]] || return 1
    return 0
}

# Print path to a user-local npm only (nvm/fnm/~/.local). Fails for brew npm.
function _init_user_npm_command()
{
    local npm_cmd candidate

    _init_load_node_toolchain > /dev/null 2>&1 || true
    hash -r 2>/dev/null || true
    npm_cmd="$(command -v npm 2>/dev/null || true)"
    if [[ -n "$npm_cmd" ]] && ! _init_path_is_homebrew "$npm_cmd" \
        && _init_npm_global_prefix_writable "$npm_cmd"
    then
        printf '%s' "$npm_cmd"
        return 0
    fi
    # Fallback: any nvm Node npm even if PATH still prefers brew.
    # Prefer higher version dirs last so glob order does not matter much;
    # first writable match is enough for update_npm / update_gt.
    for candidate in "${NVM_DIR:-$HOME/.nvm}"/versions/node/*/bin/npm; do
        [[ -x "$candidate" ]] || continue
        if _init_npm_global_prefix_writable "$candidate"; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

# Print path to user-local corepack (alongside user npm). Skip Homebrew.
function _init_user_corepack_command()
{
    local npm_cmd corepack_cmd dir

    npm_cmd="$(_init_user_npm_command 2>/dev/null || true)"
    if [[ -n "$npm_cmd" ]]; then
        dir="$(cd "$(dirname "$npm_cmd")" && pwd)"
        if [[ -x "$dir/corepack" ]]; then
            printf '%s' "$dir/corepack"
            return 0
        fi
    fi
    _init_load_node_toolchain > /dev/null 2>&1 || true
    corepack_cmd="$(command -v corepack 2>/dev/null || true)"
    if [[ -n "$corepack_cmd" ]] && ! _init_path_is_homebrew "$corepack_cmd"; then
        # Prefer home-owned corepack (nvm).
        case "$corepack_cmd" in
            "$HOME"/*|${NVM_DIR:-$HOME/.nvm}/*) printf '%s' "$corepack_cmd"; return 0 ;;
        esac
        if [[ -w "$(dirname "$corepack_cmd")" ]]; then
            printf '%s' "$corepack_cmd"
            return 0
        fi
    fi
    return 1
}

function _init_node_toolchain_helper()
{
    local dir helper
    dir="${init_files_dir:-${XDG_DATA_HOME:-$HOME/.local/share}/init-files}"
    helper="$dir/install_node_toolchain"
    if [[ -x "$helper" ]]; then
        printf '%s' "$helper"
        return 0
    fi
    return 1
}

# Ensure nvm/fnm Node is available with a writable npm global prefix.
# Offers install_node_toolchain on a TTY when user-local npm is missing.
function _init_ensure_user_node_toolchain()
{
    local helper npm_cmd

    if npm_cmd="$(_init_user_npm_command 2>/dev/null)"; then
        printf '%s' "$npm_cmd"
        return 0
    fi

    helper="$(_init_node_toolchain_helper 2>/dev/null || true)"
    if [[ -n "$helper" && -x "$helper" ]]; then
        if [[ -t 0 && -t 2 ]]; then
            if "$helper"; then
                _init_load_node_toolchain > /dev/null 2>&1 || true
                hash -r
                if npm_cmd="$(_init_user_npm_command 2>/dev/null)"; then
                    printf '%s' "$npm_cmd"
                    return 0
                fi
            fi
        else
            printf 'Run: %s   # then: hash -r && update_npm\n' "$helper" >&2
        fi
    fi

    npm_bootstrap_instructions
    return 1
}

function _init_path_prepend()
{
    local dir="$1"
    [[ -d "$dir" ]] || return 1
    _init_path_remove "$dir"
    PATH="$dir:$PATH"
}

function _init_path_remove()
{
    local dir="$1"
    [[ -n "$dir" ]] || return 0
    PATH=":$PATH:"
    PATH="${PATH//:$dir:/:}"
    PATH="${PATH#:}"
    PATH="${PATH%:}"
}

function _init_relative_age()
{
    local epoch="$1" now delta

    [[ "$epoch" =~ ^[0-9]+$ ]] || {
        printf 'unknown age'
        return 0
    }
    now=$(date +%s)
    delta=$((now - epoch))
    if (( delta < 0 )); then
        delta=$((-delta))
        printf 'in %s' "$(_init_relative_age_span "$delta")"
        return 0
    fi
    if (( delta < 45 )); then
        printf 'just now'
        return 0
    fi
    printf '%s ago' "$(_init_relative_age_span "$delta")"
}

function _init_relative_age_span()
{
    local delta="$1" n

    if (( delta < 90 )); then
        printf '1 minute'
    elif (( delta < 3600 )); then
        n=$((delta / 60))
        printf '%d minutes' "$n"
    elif (( delta < 5400 )); then
        printf '1 hour'
    elif (( delta < 86400 )); then
        n=$((delta / 3600))
        printf '%d hours' "$n"
    elif (( delta < 172800 )); then
        printf '1 day'
    elif (( delta < 86400 * 45 )); then
        n=$((delta / 86400))
        printf '%d days' "$n"
    elif (( delta < 86400 * 60 )); then
        printf '1 month'
    elif (( delta < 86400 * 365 )); then
        n=$((delta / (86400 * 30)))
        printf '%d months' "$n"
    elif (( delta < 86400 * 365 * 2 )); then
        printf '1 year'
    else
        n=$((delta / (86400 * 365)))
        printf '%d years' "$n"
    fi
}

function add_bash_tool_update_notice()
{
    local bash_path current_version kind reachable_latest

    bash_path="$1"
    current_version="$(normalize_version "$2")"
    reachable_latest="$(normalize_version "$3")"

    kind="$(bash_upgrade_kind "$current_version" "$reachable_latest" "$bash_path" 2> /dev/null || true)"

    case "$kind" in
        package-manager)
            add_tool_update_notice bash "$bash_path" "$2" "$3" auto
            ;;
        upstream-only|platform-capped)
            ;;
        unknown)
            add_tool_update_notice bash "$bash_path" "$2" "$3"
            ;;
    esac
}

function add_git_tool_update_notice()
{
    local current_version git_path kind upstream_latest

    git_path="$1"
    current_version="$(normalize_version "$2")"
    upstream_latest="$(normalize_version "$3")"

    kind="$(git_upgrade_kind "$current_version" "$upstream_latest" "$git_path" 2> /dev/null || true)"

    case "$kind" in
        package-manager)
            # macOS Homebrew and Linux distro upgrades that can actually apply.
            add_tool_update_notice git "$git_path" "$2" "$3" auto
            ;;
        upstream-only)
            # Status line already explains the manual gap; avoid a duplicate
            # [tool updates] entry that suggests a no-op update_git.
            ;;
        unknown)
            add_tool_update_notice git "$git_path" "$2" "$3"
            ;;
    esac
}

function add_pipx_tool_update_notice()
{
    local pipx_path pipx_current pipx_latest reset tone

    pipx_path="$1"
    pipx_current="$2"
    pipx_latest="$3"

    case "$(pipx_runtime_status 2> /dev/null || true)" in
        python-too-old)
            local pyver

            reset=
            tone=
            pyver=$("$init_tool_python3" --version 2> /dev/null | awk '{print $2}')
            if [[ -n "$tool_status_use_color" ]]; then
                tone=$'\033[33m'
                reset=$'\033[0m'
            fi
            tool_update_messages+=$(printf '%s  pipx: requires Python %s (this host: %s); cannot install or run pipx 1.12+%s' \
                "$tone" "$(pipx_required_python_label)" "$pyver" "$reset")$'\n'
            tool_update_messages+=$(printf '%s    use a newer python3, or: export tool_host_tag=<dir-under-~/.local/opt/pipx> before update_pipx%s\n' \
                "$tone" "$reset")$'\n'
            ;;
        broken|no-python)
            reset=
            tone=
            if [[ -n "$tool_status_use_color" ]]; then
                tone=$'\033[33m'
                reset=$'\033[0m'
            fi
            tool_update_messages+=$(printf '%s  pipx: install present but not runnable on this host (%s)%s\n' \
                "$tone" "$(pipx_runtime_status 2> /dev/null || true)" "$reset")
            tool_update_messages+=$(printf '%s    try: update_pipx  (after fixing python3)%s\n' "$tone" "$reset")$'\n'
            ;;
        ok)
            add_tool_update_notice pipx "$pipx_path" "$pipx_current" "$pipx_latest" auto
            ;;
        *)
            if [[ -n "$pipx_latest" ]]; then
                add_tool_update_notice pipx "$pipx_path" "$pipx_current" "$pipx_latest" auto
            fi
            ;;
    esac
}

function add_tool_update_notice()
{
    local red reset tool_name tool_path current_version latest_version update_command upgrade_tier

    tool_name="$1"
    tool_path="${2:-}"
    current_version="$3"
    latest_version="$4"
    upgrade_tier="${5:-auto}"

    if version_lt "$current_version" "$latest_version"; then
        red=
        reset=
        if [[ -n "$tool_status_use_color" ]]; then
            red=$'\033[31m'
            reset=$'\033[0m'
        fi
        update_command="$(tool_update_command "$tool_name" "$tool_path")" || update_command=
        tool_update_messages+=$(printf '%s  %s: installed %s, latest %s%s' "$red" "$tool_name" "$current_version" "$latest_version" "$reset")
        if [[ -n "$update_command" ]]; then
            tool_update_messages+=$(printf '\n%s    suggested command: %s%s' "$red" "$update_command" "$reset")
        fi
        tool_update_messages+=$'\n'
        _tool_version_note_pending "$tool_name" "$current_version" "$latest_version" "$tool_path"
    elif [[ -n "$tool_path" && -z "$(normalize_version "$current_version")" && -n "$(normalize_version "$latest_version")" ]]; then
        red=
        reset=
        if [[ -n "$tool_status_use_color" ]]; then
            red=$'\033[31m'
            reset=$'\033[0m'
        fi
        update_command="$(tool_update_command "$tool_name" "$tool_path")" || update_command=
        tool_update_messages+=$(printf '%s  %s: installed (unknown), latest %s%s' "$red" "$tool_name" "$latest_version" "$reset")
        if [[ -n "$update_command" ]]; then
            tool_update_messages+=$(printf '\n%s    suggested command: %s%s' "$red" "$update_command" "$reset")
        fi
        tool_update_messages+=$'\n'
    fi
}

# Record a tool that has an actionable/outdated installed version for the
# pending-updates sidecar (fast-path drift detection after out-of-band upgrades).
_tool_version_note_pending()
{
    local tool_name="$1"
    local current_version latest_version tool_path _pending_row

    current_version="$(normalize_version "$2")"
    latest_version="$(normalize_version "$3")"
    tool_path="${4:-}"

    [[ -n "$current_version" && -n "$latest_version" ]] || return 0
    version_lt "$current_version" "$latest_version" || return 0
    # Skip duplicate rows for the same tool (status + updates paths).
    case $'\n'"${tool_pending_updates_tsv:-}" in
        *$'\n'"${tool_name}"$'\t'*) return 0 ;;
    esac
    # printf -v keeps the trailing newline (command substitution would strip it).
    printf -v _pending_row '%s\t%s\t%s\n' "$tool_name" "$current_version" "$tool_path"
    tool_pending_updates_tsv+="$_pending_row"
}

# Cheap live installed version for pending-updates drift checks (no network).
tool_live_installed_version()
{
    local tool_name="$1"
    local tool_path="${2:-}"

    case "$tool_name" in
        bash)
            [[ -n "$tool_path" && -x "$tool_path" ]] || tool_path="${BASH:-}"
            bash_current_version "$tool_path"
            ;;
        git)
            [[ -n "$tool_path" && -x "$tool_path" ]] || tool_path="${init_tool_git:-}"
            [[ -n "$tool_path" && -x "$tool_path" ]] || return 0
            "$tool_path" --version 2>/dev/null | awk 'NR == 1 { print $3 }'
            ;;
        gh)
            if [[ -n "$tool_path" && -x "$tool_path" ]]; then
                "$tool_path" --version 2>/dev/null | awk 'NR == 1 { print $3 }'
            else
                command -v gh >/dev/null 2>&1 || return 0
                gh --version 2>/dev/null | awk 'NR == 1 { print $3 }'
            fi
            ;;
        gh-stack)
            gh_stack_current_version 2>/dev/null || true
            ;;
        gt)
            if [[ -n "$tool_path" && -x "$tool_path" ]]; then
                "$tool_path" --version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+)+' | head -n 1
            else
                command -v gt >/dev/null 2>&1 || return 0
                gt --version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+)+' | head -n 1
            fi
            ;;
        npm|npx)
            if [[ -n "$tool_path" && -x "$tool_path" ]]; then
                "$tool_path" --version 2>/dev/null
            else
                command -v "$tool_name" >/dev/null 2>&1 || return 0
                "$tool_name" --version 2>/dev/null
            fi
            ;;
        pipx)
            # Prefer the shared parser (handles "1.2.3" vs "pipx 1.2.3").
            if declare -F pipx_current_version > /dev/null 2>&1; then
                pipx_current_version "$tool_path" 2>/dev/null || true
            else
                {
                    [[ -n "$tool_path" && -x "$tool_path" ]] && "$tool_path" --version
                    command -v pipx >/dev/null 2>&1 && pipx --version
                } 2>/dev/null | awk 'match($0, /[0-9]+(\.[0-9]+)+/) { print substr($0, RSTART, RLENGTH); exit }'
            fi
            ;;
        pnpm)
            if [[ -n "$tool_path" && -x "$tool_path" ]]; then
                "$tool_path" --version 2>/dev/null
            else
                command -v pnpm >/dev/null 2>&1 || return 0
                pnpm --version 2>/dev/null
            fi
            ;;
        uv)
            if [[ -n "$tool_path" && -x "$tool_path" ]]; then
                "$tool_path" --version 2>/dev/null | awk 'match($0, /[0-9]+(\.[0-9]+)+/) { print substr($0, RSTART, RLENGTH); exit }'
            else
                command -v uv >/dev/null 2>&1 || return 0
                uv --version 2>/dev/null | awk 'match($0, /[0-9]+(\.[0-9]+)+/) { print substr($0, RSTART, RLENGTH); exit }'
            fi
            ;;
        *)
            return 0
            ;;
    esac
}

# True when pending-updates sidecar lists a tool whose live installed version
# no longer matches the recorded (stale) installed version.
tool_version_pending_drifted()
{
    local pending_file="${1:-}"
    local tool ver path live

    [[ -n "$pending_file" && -r "$pending_file" ]] || return 1
    while IFS=$'\t' read -r tool ver path || [[ -n "$tool" ]]; do
        [[ -z "$tool" || "$tool" == \#* ]] && continue
        live="$(tool_live_installed_version "$tool" "$path" 2>/dev/null || true)"
        live="$(normalize_version "$live")"
        ver="$(normalize_version "$ver")"
        [[ -n "$ver" ]] || continue
        # Drift when live differs from the recorded outdated install (admin /
        # out-of-band upgrade), or the binary disappeared.
        if [[ -z "$live" ]] || ! versions_equal "$live" "$ver"; then
            return 0
        fi
    done < "$pending_file"
    return 1
}

function applypatch()
{
    "$init_tool_patch" -p0 -l --ignore-whitespace < "$@"
}


function bt()
{
    local attach_pid="" prog

    if [[ -z "${init_tool_gdb:-}" || ! -x "$init_tool_gdb" ]]; then
        echo "bt: gdb not found (run provision_init_files / brew install gdb)" >&2
        return 1
    fi

    if [[ "${1-}" == '-h' || "${1-}" == '--help' ]]; then
        cat <<'EOF' >&2
Usage: bt [--] program [args...]
       bt -p PID

Run program under gdb and dump a full backtrace to gdb.bt, or attach to PID.
EOF
        return 0
    fi

    if [[ "${1-}" == '-p' ]]; then
        attach_pid="${2-}"
        if [[ -z "$attach_pid" || ! "$attach_pid" =~ ^[0-9]+$ ]]; then
            echo "bt: -p requires a numeric PID" >&2
            return 1
        fi
        shift 2
        if [[ $# -gt 0 ]]; then
            echo "bt: do not mix -p PID with program args" >&2
            return 1
        fi
        echo 0 | "$init_tool_gdb" -batch-silent \
            -ex "set logging overwrite on" \
            -ex "set logging file gdb.bt" \
            -ex "set logging on" \
            -ex "set pagination off" \
            -ex "handle SIG33 pass nostop noprint" \
            -ex "echo backtrace:\n" \
            -ex "backtrace full" \
            -ex "echo \n\nregisters:\n" \
            -ex "info registers" \
            -ex "echo \n\ncurrent instructions:\n" \
            -ex "x/16i \$pc" \
            -ex "echo \n\nthreads backtrace:\n" \
            -ex "thread apply all backtrace" \
            -ex "set logging off" \
            -ex "quit" \
            --pid "$attach_pid"
        return
    fi

    if [[ "${1-}" == '--' ]]; then
        shift
    fi
    if [[ $# -lt 1 ]]; then
        echo "bt: usage: bt [--] program [args...]  or  bt -p PID" >&2
        return 1
    fi
    prog="$1"
    if ! declare -F init_files_bt_program_ok > /dev/null 2>&1 \
        || ! init_files_bt_program_ok "$prog"; then
        echo "bt: program must be an existing executable file: $prog" >&2
        return 1
    fi

    echo 0 | "$init_tool_gdb" -batch-silent \
        -ex "run" \
        -ex "set logging overwrite on" \
        -ex "set logging file gdb.bt" \
        -ex "set logging on" \
        -ex "set pagination off" \
        -ex "handle SIG33 pass nostop noprint" \
        -ex "echo backtrace:\n" \
        -ex "backtrace full" \
        -ex "echo \n\nregisters:\n" \
        -ex "info registers" \
        -ex "echo \n\ncurrent instructions:\n" \
        -ex "x/16i \$pc" \
        -ex "echo \n\nthreads backtrace:\n" \
        -ex "thread apply all backtrace" \
        -ex "set logging off" \
        -ex "quit" \
        --args "$@"
}

function bun()
{
    local script=""
    local pipx_bin="${HOME}/.local/bin/bunnify"
    local checkout="${HOME}/work/ai/bunnify/scripts/bunnify"

    # pipx (PIPX_BIN_DIR) first; checkout is a local-dev fallback only.
    if [[ -x "$pipx_bin" ]]; then
        script="$pipx_bin"
    elif [[ -x "$checkout" ]]; then
        script="$checkout"
    else
        echo "bun: bunnify not found (try: pipx install bunnify)" >&2
        return 1
    fi
    if ! _init_has_display; then
        if _init_is_darwin; then
            echo "bun: no Aqua display session (GUI login required to open a browser)" >&2
        else
            echo "bun: no accessible display (DISPLAY/WAYLAND_DISPLAY unset or unreachable)" >&2
        fi
        return 1
    fi
    "$script" "$@"
}

function cache_ssh
{
    local refresh=0
    local check_only=0
    local key="${SSH_CACHE_KEY:-}"
    local timeout="${SSH_CACHE_TIMEOUT:-4h}"
    local explicit_key=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--refresh|--recache)
                refresh=1
                shift
                ;;
            -c|--check)
                check_only=1
                shift
                ;;
            -t|--timeout)
                if [[ -z "${2:-}" ]]; then
                    echo "ERROR: cache_ssh: -t requires a timeout (e.g. 1h, 30m, 3600)" >&2
                    return 1
                fi
                timeout="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: cache_ssh [-c|--check] [-r|--refresh] [-t timeout] [keyfile]" >&2
                return 0
                ;;
            -*)
                echo "ERROR: cache_ssh: unknown option: $1" >&2
                return 1
                ;;
            *)
                key="$1"
                explicit_key=1
                shift
                ;;
        esac
    done

    if ! declare -F init_files_ssh_timeout_ok > /dev/null 2>&1 \
        || ! init_files_ssh_timeout_ok "$timeout"; then
        echo "ERROR: cache_ssh: invalid timeout '$timeout' (use e.g. 3600, 30m, 4h, 1d)" >&2
        return 1
    fi

    if [[ $explicit_key -eq 0 && -z "$key" ]]; then
        if declare -F init_files_preferred_ssh_key > /dev/null 2>&1; then
            key="$(init_files_preferred_ssh_key 2>/dev/null || true)"
        fi
    fi

    if [[ -z "$key" || ! -f "$key" ]]; then
        local alt_key=""
        if declare -F init_files_preferred_ssh_keys > /dev/null 2>&1; then
            alt_key="$(init_files_preferred_ssh_keys | head -1 || true)"
        fi
        if [[ (-z "$key" || ! -f "$key") && -n "$alt_key" && -f "$alt_key" ]]; then
            if [[ -n "$key" && ! -f "$key" && "$alt_key" != "$key" ]]; then
                echo "cache_ssh: ${key} missing; using $alt_key" >&2
            fi
            key="$alt_key"
        elif [[ -z "$key" || ! -f "$key" ]]; then
            echo "ERROR: cache_ssh: no usable SSH key found" >&2
            echo "  Set SSH_CACHE_KEY, pass a keyfile, or add IdentityFile entries in the" >&2
            echo "  private config overlay (.ssh/config.github). Prefer: gh auth / HTTPS." >&2
            return 1
        fi
    fi

    if ! declare -F init_files_ssh_key_usable > /dev/null 2>&1 \
        || ! init_files_ssh_key_usable "$key"; then
        echo "ERROR: cache_ssh: refusing key '$key' (need a regular file with mode 600/400; absolute path or under ~/.ssh)" >&2
        return 1
    fi

    local ssh_add_cmd ssh_agent_cmd ssh_keygen_cmd env_file
    ssh_add_cmd="${init_tool_ssh_add:-}"
    if [[ -z "$ssh_add_cmd" || ! -x "$ssh_add_cmd" ]]; then
        ssh_add_cmd="$(command -v ssh-add 2>/dev/null || true)"
    fi
    ssh_agent_cmd="${init_tool_ssh_agent:-}"
    if [[ -z "$ssh_agent_cmd" || ! -x "$ssh_agent_cmd" ]]; then
        ssh_agent_cmd="$(command -v ssh-agent 2>/dev/null || true)"
    fi
    ssh_keygen_cmd="${init_tool_ssh_keygen:-}"
    if [[ -z "$ssh_keygen_cmd" || ! -x "$ssh_keygen_cmd" ]]; then
        ssh_keygen_cmd="$(command -v ssh-keygen 2>/dev/null || true)"
    fi
    if [[ -z "$ssh_add_cmd" ]]; then
        echo "ERROR: cache_ssh: ssh-add not found (run ~/.local/share/init-files/provision_init_files)" >&2
        return 1
    fi

    # Prefer the bashrc-managed env file so a shell without SSH_AUTH_SOCK can
    # still attach to (or start) the Linux agent — bare ssh-add cannot.
    env_file="${ssh_env:-$HOME/.ssh/environment}"
    [[ -n "${ssh_env:-}" ]] || ssh_env="$env_file"

    local agent_rc=0
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        agent_rc=2
    else
        "$ssh_add_cmd" -l &>/dev/null
        agent_rc=$?
    fi

    if [[ $agent_rc -eq 2 ]]; then
        if _init_is_darwin; then
            if [[ -z "$ssh_agent_cmd" ]]; then
                echo "ERROR: cache_ssh: ssh-agent not found" >&2
                return 1
            fi
            eval "$("$ssh_agent_cmd" -s)" > /dev/null
        else
            if [[ -f "$env_file" ]]; then
                # shellcheck disable=SC1090
                . "$env_file" > /dev/null
                "$ssh_add_cmd" -l &>/dev/null
                agent_rc=$?
            fi
            if [[ $agent_rc -eq 2 ]]; then
                if type start_agent > /dev/null 2>&1; then
                    start_agent
                elif [[ -n "$ssh_agent_cmd" ]]; then
                    eval "$("$ssh_agent_cmd" -s)" > /dev/null
                else
                    echo "ERROR: cache_ssh: ssh-agent not found" >&2
                    return 1
                fi
            fi
        fi
    fi

    "$ssh_add_cmd" -l &>/dev/null
    agent_rc=$?
    if [[ $agent_rc -eq 2 ]]; then
        echo "ERROR: cache_ssh: ssh-agent is not available" >&2
        echo "  Start one, then retry: cache_ssh $key" >&2
        return 1
    fi

    local fingerprint
    fingerprint=$("$ssh_keygen_cmd" -lf "$key" 2>/dev/null | awk '{print $2}')
    local key_loaded=0
    if [[ -n "$fingerprint" ]] && "$ssh_add_cmd" -l 2>/dev/null | grep -qF "$fingerprint"; then
        key_loaded=1
    fi

    if [[ $refresh -eq 1 && $key_loaded -eq 1 ]]; then
        echo "Removing cached key before refresh: $key"
        "$ssh_add_cmd" -d "$key" >/dev/null 2>&1
        key_loaded=0
    fi

    if [[ $key_loaded -eq 1 ]]; then
        # --check: quiet success (for cssh / scripts). Interactive cache_ssh still prints.
        if [[ $check_only -eq 1 ]]; then
            return 0
        fi
        echo "SSH key already cached: $key"
        "$ssh_add_cmd" -l
        return 0
    fi

    if [[ $check_only -eq 1 ]]; then
        echo "SSH key not cached (re-cache needed): $key" >&2
        return 1
    fi

    # Fail closed: passphrase must come from this TTY, never Keychain/askpass.
    if [[ ! -t 0 || ! -t 2 ]]; then
        echo "ERROR: cache_ssh: passphrase required; run from an interactive terminal" >&2
        return 1
    fi

    echo "Caching SSH key: $key (timeout: $timeout)"
    # No --apple-use-keychain: that would load the passphrase from Keychain
    # without prompting, which defeats the point of a passphrase-protected key.
    SSH_ASKPASS_REQUIRE=never "$ssh_add_cmd" -t "$timeout" "$key"
}

# Prevent idle/disk/system sleep for a while (macOS caffeinate).
# Display may still blank (-d omitted on purpose).
# Usage: cafe [seconds]   # default 3600; runs in background
# Re-running replaces any prior cafe assertion with the new duration.
function cafe()
{
    _init_is_darwin || { echo "cafe: macOS only" >&2; return 1; }

    local secs="${1:-3600}" state_dir pidfile old_pid comm
    case "$secs" in
        -h|--help)
            cat <<'EOF'
Usage: cafe [seconds]

Prevent macOS idle, disk, and (on AC) system sleep via caffeinate
(default: 3600). Display may still blank. Runs in the background;
kill the printed pid to stop early.

If cafe is already running, the previous assertion is replaced so the
new duration applies from now.
EOF
            return 0
            ;;
        *[!0-9]*|'')
            echo "Usage: cafe [seconds]" >&2
            return 2
            ;;
    esac

    state_dir="${init_files_state_dir:-${XDG_STATE_HOME:-$HOME/.local/state}/init-files}"
    pidfile="$state_dir/cafe.pid"
    mkdir -p "$state_dir" 2>/dev/null || true

    if [[ -f "$pidfile" ]]; then
        old_pid="$(tr -d '[:space:]' <"$pidfile" 2>/dev/null || true)"
        if [[ -n "$old_pid" && "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
            comm="$(ps -p "$old_pid" -o comm= 2>/dev/null || true)"
            comm="${comm##*/}"
            if [[ "$comm" == caffeinate ]]; then
                kill "$old_pid" 2>/dev/null || true
                # Give the old assertion a moment to drop before starting anew.
                sleep 0.1
                echo "cafe: replaced prior assertion (pid $old_pid)"
            fi
        fi
        rm -f "$pidfile" 2>/dev/null || true
    fi

    command caffeinate -ims -t "$secs" &
    printf '%s\n' "$!" >"$pidfile"
    echo "cafe: awake for ${secs}s (pid $!)"
}

function cda()
{
    _init_cd_work_project cda "${HOME}/work/ai" "$@"
}

function cdb()
{
    _init_cd_work_project cdb "${HOME}/work/brk-tech" "$@"
}

function cdr()
{
    local git_common_dir repo_root

    git_common_dir=$("$init_tool_git" rev-parse --path-format=absolute --git-common-dir 2> /dev/null) || {
        echo "cdr: not inside a git repository" >&2
        return 1
    }

    case "$git_common_dir" in
        */.git)
            repo_root="${git_common_dir%/.git}"
            ;;
        *)
            repo_root="$git_common_dir"
            ;;
    esac

    cd "$repo_root" || return
}

function check_npm_tools()
{
    local -n latest_ref="$1"
    local current_version tool_path

    if npm_tools_available; then
        tool_path="$(npm_tools_path)"
        current_version="$(npm_tools_version)"
        # Use cached latest only — do not block shell startup on the registry.
        add_tool_update_notice npm "$tool_path" "$current_version" "$latest_ref"
        tool_status_messages+="$(tool_status_line npm "$tool_path" "$current_version" "$latest_ref")"$'\n'
        [[ -n "$current_version" && -z "$latest_ref" ]] && return 1
        return 0
    fi

    tool_status_messages+="$(tool_status_line npm "" "" "$latest_ref")"$'\n'
    return 0
}

function check_pipx_tool()
{
    local pipx_current pipx_path pipx_runtime

    pipx_runtime="$(pipx_runtime_status 2> /dev/null || true)"
    # Prefer the cached pipx_latest from check_tool_versions; no foreground network.

    case "$pipx_runtime" in
        ok)
            pipx_path="$(pipx_command_path 2> /dev/null || true)"
            pipx_current="$(pipx_current_version "$pipx_path" || true)"
            add_pipx_tool_update_notice "$pipx_path" "$pipx_current" "$pipx_latest"
            tool_status_messages+="$(pipx_tool_status_line "$pipx_path" "$pipx_current" "$pipx_latest")"$'\n'
            ;;
        not-installed)
            tool_status_messages+="$(tool_status_line pipx "" "" "$pipx_latest")"$'\n'
            ;;
        *)
            pipx_path="$(pipx_resolve_host_dir 2> /dev/null)/current/bin/pipx"
            [[ -x "$pipx_path" ]] || pipx_path="${HOME}/.local/bin/pipx"
            add_pipx_tool_update_notice "$pipx_path" "" "$pipx_latest"
            tool_status_messages+="$(pipx_tool_status_line "$pipx_path" "" "$pipx_latest")"$'\n'
            ;;
    esac
}

function check_tool_versions()
{
    local cache_file checked_at current_time gh_cleanup_notice gh_current git_current gt_current lock_dir
    local gh_path git_path gt_path gh_stack_current gh_stack_path
    local bash_current bash_path bash_shell_notice bash_reset bash_shell_hint
    local pipx_current pipx_path pnpm_current pnpm_path uv_current uv_path
    local pending_tool_count
    local no_dev_flag check_stamp report_file rebuild report
    local cache_mtime report_mtime
    local pending_file

    [[ $- == *i* ]] || return

    # Non-dev hosts should not fetch/compare git/gh/npm/… versions or print
    # install hints for that toolchain.
    if type _init_files_is_no_dev_host > /dev/null 2>&1 && _init_files_is_no_dev_host; then
        return 0
    fi
    # Fallback before init vars are set (should not happen in normal interactive load).
    no_dev_flag="${init_files_no_dev_flag:-${XDG_CONFIG_HOME:-$HOME/.config}/init-files/no-dev.${init_files_host:-$(hostname -s 2>/dev/null || echo host)}}"
    if [[ -f "$no_dev_flag" ]]; then
        return 0
    fi

    cache_file="$tool_version_cache"
    check_stamp="${tool_version_state_dir}/last-check"
    report_file="${tool_version_state_dir}/last-report"
    pending_file="${tool_version_state_dir}/pending-updates"
    checked_at=
    bash_latest=
    gh_latest=
    gh_stack_latest=
    git_latest=
    gt_latest=
    npm_latest=
    pipx_latest=
    pnpm_latest=
    uv_latest=
    tool_status_use_color=
    tool_update_messages=
    tool_status_messages=
    tool_pending_updates_tsv=
    pending_tool_count=0
    rebuild=0
    report=

    mkdir -p "$tool_version_state_dir" 2>/dev/null || true
    current_time=$(date +%s)

    # Always embed ANSI. This function only runs in interactive shells, and
    # cached reprints via cat must keep color even when stdout was not a TTY
    # while the report was built (common during shell init).
    tool_status_use_color=1

    # Rebuild when: no report, daily stamp expired, or the latest-* cache is
    # newer than the report (background refresh finished after a "pending" print).
    if [[ ! -r "$report_file" ]]; then
        rebuild=1
    elif [[ -r "$check_stamp" ]]; then
        checked_at=$(cat "$check_stamp" 2>/dev/null || echo 0)
        if ! [[ "$checked_at" =~ ^[0-9]+$ ]] || (( current_time - checked_at >= tool_version_max_age_seconds )); then
            rebuild=1
        fi
    else
        rebuild=1
    fi
    if [[ $rebuild -eq 0 && -r "$cache_file" && -r "$report_file" ]]; then
        # Prefer GNU -c (Linux); BSD -f second. GNU `stat -f` is --file-system and
        # still prints to stdout on failure, so BSD-first poisons the || chain.
        cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
        report_mtime=$(stat -c %Y "$report_file" 2>/dev/null || stat -f %m "$report_file" 2>/dev/null || echo 0)
        if [[ "$cache_mtime" =~ ^[0-9]+$ && "$report_mtime" =~ ^[0-9]+$ ]] \
            && (( cache_mtime > report_mtime )); then
            rebuild=1
        fi
    fi
    # Migrate colorless caches written when -t 1 was false at build time.
    if [[ $rebuild -eq 0 && -r "$report_file" ]] \
        && ! grep -a -F $'\033[' "$report_file" >/dev/null 2>&1; then
        rebuild=1
    fi
    # New tool keys (e.g. bash_latest) must rebuild the report — do not keep
    # reprinting a day-old report that omits newly tracked tools.
    if [[ $rebuild -eq 0 ]] && ! tool_version_cache_is_complete "$cache_file"; then
        rebuild=1
    fi
    # Use $'\033' (real ESC), not \x1b — macOS/BSD grep rejects \x1b and would
    # force a rebuild (and rewrite last-check) on every interactive shell.
    if [[ $rebuild -eq 0 && -r "$report_file" ]] \
        && ! grep -a -E $'^(\033\\[[0-9;]*m)?[[:space:]]*bash:' "$report_file" >/dev/null 2>&1; then
        rebuild=1
    fi
    # Out-of-band upgrades (admin apt/brew): pending-updates sidecar records
    # installed versions at report time; cheap live probes force rebuild when
    # any drifted (issue #40). Absent sidecar → unchanged fast path.
    if [[ $rebuild -eq 0 && -r "$pending_file" ]] \
        && tool_version_pending_drifted "$pending_file"; then
        rebuild=1
    fi

    if [[ $rebuild -eq 0 ]]; then
        cat "$report_file"
        tool_version_check_schedule_lines
        if type _init_files_warn_tools_reinstall_if_needed > /dev/null 2>&1; then
            _init_files_warn_tools_reinstall_if_needed broken
        fi
        return 0
    fi

    checked_at=
    if [[ -r "$cache_file" ]]; then
        # shellcheck disable=SC1090
        . "$cache_file"
    fi

    # Refresh latest-* in the background when the cache is missing, stale, or
    # missing keys (e.g. after adding a newly tracked tool like gh-stack).
    # disown: avoid bash printing "[N]+ Done" over the prompt.
    # refresh_tool_version_cache locks only around the atomic latest write (#26).
    if [[ -z "$checked_at" ]] || ! [[ "$checked_at" =~ ^[0-9]+$ ]] \
        || (( current_time - checked_at >= tool_version_max_age_seconds )) \
        || ! tool_version_cache_is_complete "$cache_file"; then
        (
            refresh_tool_version_cache
        ) >/dev/null 2>&1 &
        disown $! 2>/dev/null || true
    fi

    # Report the interactive shell in use (iTerm / login shell), not a
    # platform-preferred binary that may differ (Apple /bin/bash vs Homebrew).
    if [[ -n "${BASH:-}" && -x "${BASH:-}" ]]; then
        bash_path="$BASH"
    elif [[ -n "$init_tool_bash" && -x "$init_tool_bash" ]]; then
        bash_path="$init_tool_bash"
    else
        bash_path="$(command -v bash 2>/dev/null || true)"
    fi
    if [[ -n "$bash_path" && -x "$bash_path" ]]; then
        bash_current="$(bash_current_version "$bash_path")"
        # Fast local fallback when cache has no bash_latest yet. Must not block
        # startup (dnf/yum metadata refresh can hang); timeout is inside the helper.
        if [[ -z "$bash_latest" ]]; then
            bash_latest="$(fetch_bash_latest_distro 2> /dev/null || true)"
        fi
        add_bash_tool_update_notice "$bash_path" "$bash_current" "$bash_latest"
        tool_status_messages+="$(bash_tool_status_line "$bash_path" "$bash_current" "$bash_latest")"$'\n'
        if [[ -n "$bash_current" && -z "$bash_latest" ]]; then
            pending_tool_count=$((pending_tool_count + 1))
        fi
        # Modern macOS only: tip when this process is a stale Cellar path after
        # brew upgrade bash (preferred init_tool_bash is the current brew bash).
        # Older macOS never prefers Homebrew — do not nag to chsh toward Apple
        # /bin/bash or print brew upgrade steps.
        if type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos \
            && [[ -n "${BASH:-}" && -n "$init_tool_bash" && -x "$init_tool_bash" ]] \
            && ! bash_paths_equivalent "$BASH" "$init_tool_bash"
        then
            bash_shell_notice=
            bash_reset=
            if [[ -n "$tool_status_use_color" ]]; then
                bash_shell_notice=$'\033[33m'
                bash_reset=$'\033[0m'
            fi
            tool_update_messages+="$(printf '%s  bash: this shell is %s (%s); preferred is %s (%s)%s' \
                "$bash_shell_notice" \
                "$BASH" \
                "${BASH_VERSION%%(*}" \
                "$init_tool_bash" \
                "$(bash_current_version "$init_tool_bash")" \
                "$bash_reset")"$'\n'
            # Preserve trailing newlines from the multi-line hint.
            bash_shell_hint="$(bash_login_shell_setup_hint "$init_tool_bash" "$bash_shell_notice" "$bash_reset"; printf x)"
            tool_update_messages+="${bash_shell_hint%x}"
        fi
    else
        tool_status_messages+="$(tool_status_line bash "" "" "$bash_latest")"$'\n'
    fi

    if [[ -n "$init_tool_git" && -x "$init_tool_git" ]]; then
        git_path="$init_tool_git"
        git_current=$("$init_tool_git" --version 2> /dev/null | awk 'NR == 1 { print $3 }' || true)
        # Fast local fallback when upstream cache is empty (same idea as bash).
        if [[ -z "$git_latest" ]]; then
            git_latest="$(fetch_git_latest_distro 2> /dev/null || true)"
        fi
        add_git_tool_update_notice "$git_path" "$git_current" "$git_latest"
        tool_status_messages+="$(git_tool_status_line "$git_path" "$git_current" "$git_latest")"$'\n'
        if [[ -n "$git_current" && -z "$git_latest" ]]; then
            pending_tool_count=$((pending_tool_count + 1))
        fi
    else
        tool_status_messages+="$(tool_status_line git "" "" "$git_latest")"$'\n'
    fi

    if command -v gh > /dev/null 2>&1; then
        gh_path=$(command -v gh)
        gh_current=$(gh --version 2> /dev/null | awk 'NR == 1 { print $3 }' || true)
        if [[ -z "$gh_latest" ]]; then
            gh_latest="$(fetch_gh_latest_distro 2> /dev/null || true)"
        fi
        add_tool_update_notice gh "$gh_path" "$gh_current" "$gh_latest"
        tool_status_messages+="$(tool_status_line gh "$gh_path" "$gh_current" "$gh_latest")"$'\n'
        if [[ -n "$gh_current" && -z "$gh_latest" ]]; then
            pending_tool_count=$((pending_tool_count + 1))
        fi
        gh_cleanup_notice="$(detect_gh_cleanup_notice || true)"
        if [[ -n "$gh_cleanup_notice" ]]; then
            tool_update_messages+="$gh_cleanup_notice"$'\n'
        fi
    else
        tool_status_messages+="$(tool_status_line gh "" "" "$gh_latest")"$'\n'
    fi

    # gh-stack is a gh extension (never a PATH binary). Only report when gh
    # exists; missing stays optional yellow, not red "not found on PATH".
    if command -v gh > /dev/null 2>&1; then
        gh_stack_path="$(gh_stack_extension_path 2> /dev/null || true)"
        gh_stack_current="$(gh_stack_current_version 2> /dev/null || true)"
        if [[ -n "$gh_stack_current" || -n "$gh_stack_path" ]]; then
            [[ -n "$gh_stack_current" ]] || gh_stack_current=present
            if [[ "$gh_stack_current" != "present" ]]; then
                add_tool_update_notice gh-stack "${gh_stack_path:-gh-stack}" "$gh_stack_current" "$gh_stack_latest"
            fi
            tool_status_messages+="$(gh_stack_tool_status_line "$gh_stack_path" "$gh_stack_current" "$gh_stack_latest")"$'\n'
            if [[ -z "$gh_stack_latest" ]]; then
                pending_tool_count=$((pending_tool_count + 1))
            fi
        else
            tool_status_messages+="$(gh_stack_tool_status_line "" "" "$gh_stack_latest")"$'\n'
        fi
    fi

    if command -v gt > /dev/null 2>&1; then
        gt_path=$(command -v gt)
        gt_current=$(gt --version 2> /dev/null | grep -Eo '[0-9]+(\.[0-9]+)+' | head -n 1 || true)
        add_tool_update_notice gt "$gt_path" "$gt_current" "$gt_latest"
        tool_status_messages+="$(tool_status_line gt "$gt_path" "$gt_current" "$gt_latest")"$'\n'
        if [[ -n "$gt_current" && -z "$gt_latest" ]]; then
            pending_tool_count=$((pending_tool_count + 1))
        fi
    else
        tool_status_messages+="$(tool_status_line gt "" "" "$gt_latest")"$'\n'
    fi

    check_npm_tools npm_latest || pending_tool_count=$((pending_tool_count + 1))

    check_pipx_tool

    if command -v pnpm > /dev/null 2>&1; then
        pnpm_path=$(command -v pnpm)
        pnpm_current=$(pnpm --version 2> /dev/null || true)
        add_tool_update_notice pnpm "$pnpm_path" "$pnpm_current" "$pnpm_latest"
        tool_status_messages+="$(tool_status_line pnpm "$pnpm_path" "$pnpm_current" "$pnpm_latest")"$'\n'
        if [[ -n "$pnpm_current" && -z "$pnpm_latest" ]]; then
            pending_tool_count=$((pending_tool_count + 1))
        fi
    else
        tool_status_messages+="$(tool_status_line pnpm "" "" "$pnpm_latest")"$'\n'
    fi

    if command -v uv > /dev/null 2>&1; then
        uv_path=$(command -v uv)
        uv_current=$(uv --version 2> /dev/null | awk 'NR == 1 { print $2 }' || true)
        add_tool_update_notice uv "$uv_path" "$uv_current" "$uv_latest"
        tool_status_messages+="$(tool_status_line uv "$uv_path" "$uv_current" "$uv_latest")"$'\n'
        if [[ -n "$uv_current" && -z "$uv_latest" ]]; then
            pending_tool_count=$((pending_tool_count + 1))
        fi
    else
        tool_status_messages+="$(tool_status_line uv "" "" "$uv_latest")"$'\n'
    fi

    # Optional interactive helpers: show install hints when missing (platform-isolated).
    # On modern macOS bash-completion is required (provision); still report status here.
    tool_status_messages+="$(fzf_tool_status_line)"$'\n'
    tool_status_messages+="$(bash_completion_status_line)"$'\n'

    report=
    if [[ -n "$tool_status_messages" ]]; then
        report+=$'\n'"[tool versions]"$'\n'"$tool_status_messages"$'\n'
    fi
    if [[ -n "$tool_update_messages" ]]; then
        report+=$'\n'"[tool updates]"$'\n'"$tool_update_messages"$'\n'
    fi

    # Only stamp / cache a completed report when we have latest-* data.
    # A pending-only print is not locked in for the day, so the next shell
    # rebuilds after the background cache fill.
    # Atomic write + short lock so concurrent shells never tear last-report /
    # last-check (issue #26). If the lock is busy, skip caching (still print).
    lock_dir="${tool_version_state_dir}.lock"
    if declare -F init_files_mkdir_lock > /dev/null 2>&1 \
        && declare -F init_files_atomic_write > /dev/null 2>&1 \
        && init_files_mkdir_lock "$lock_dir"; then
        if [[ $pending_tool_count -eq 0 ]]; then
            printf '%s' "$report" | init_files_atomic_write "$report_file" || true
            printf '%s\n' "$current_time" | init_files_atomic_write "$check_stamp" || true
            if [[ -n "${tool_pending_updates_tsv:-}" ]]; then
                {
                    printf '# tool\tinstalled\tpath\n'
                    printf '%s' "$tool_pending_updates_tsv"
                } | init_files_atomic_write "$pending_file" || true
            else
                rm -f "$pending_file" 2>/dev/null || true
            fi
        else
            rm -f "$report_file" "$pending_file" 2>/dev/null || true
        fi
        init_files_mkdir_unlock "$lock_dir"
    fi
    printf '%s' "$report"
    tool_version_check_schedule_lines "$pending_tool_count"
    if type _init_files_warn_tools_reinstall_if_needed > /dev/null 2>&1; then
        _init_files_warn_tools_reinstall_if_needed broken
    fi
}

# Unique SSH destinations: Host aliases from ~/.ssh/config (+ config.d) and
# cleartext names from ~/.ssh/known_hosts[2]. Hashed known_hosts lines are skipped.
function _init_ssh_hosts()
{
    local f
    local -a config_files=() known_files=()

    [[ -r "${HOME}/.ssh/config" ]] && config_files+=("${HOME}/.ssh/config")
    if [[ -d "${HOME}/.ssh/config.d" ]]; then
        for f in "${HOME}/.ssh/config.d"/*.conf; do
            [[ -r "$f" ]] && config_files+=("$f")
        done
    fi
    [[ -r "${HOME}/.ssh/known_hosts" ]] && known_files+=("${HOME}/.ssh/known_hosts")
    [[ -r "${HOME}/.ssh/known_hosts2" ]] && known_files+=("${HOME}/.ssh/known_hosts2")

    {
        if ((${#config_files[@]})); then
            # BSD/macOS awk: no IGNORECASE; skip pattern/negation tokens.
            awk '
                tolower($1) == "host" {
                    for (i = 2; i <= NF; i++) {
                        if ($i ~ /[*?]/ || substr($i, 1, 1) == "!") continue
                        print $i
                    }
                }
            ' "${config_files[@]}"
        fi
        if ((${#known_files[@]})); then
            # Marker + keytype + key…; host field may be comma-separated or [host]:port.
            awk '
                /^[[:space:]]*(#|$)/ { next }
                $1 ~ /^\|/ { next }
                {
                    n = split($1, hosts, ",")
                    for (i = 1; i <= n; i++) {
                        h = hosts[i]
                        if (h ~ /^\[[^]]+\]:[0-9]+$/) {
                            sub(/^\[/, "", h)
                            sub(/\]:[0-9]+$/, "", h)
                        }
                        if (h == "" || h ~ /[*?]/) continue
                        print h
                    }
                }
            ' "${known_files[@]}"
        fi
    } | LC_ALL=C sort -u
}

# Fuzzy-pick an SSH host. Prints the selection; optional initial query.
# Usage: _init_ssh_fzf_pick_host <prompt-label> [query]
function _init_ssh_fzf_pick_host()
{
    local prompt_label="${1:-ssh}" query="${2:-}" fzf_bin picked
    local host_count=0

    fzf_bin="${init_tool_fzf:-}"
    [[ -n "$fzf_bin" && -x "$fzf_bin" ]] || fzf_bin="$(command -v fzf 2>/dev/null || true)"
    if [[ -z "$fzf_bin" || ! -x "$fzf_bin" ]]; then
        echo "ERROR: ${prompt_label}: fzf not found — pass a hostname, or install fzf" >&2
        return 1
    fi
    if [[ ! -t 0 ]]; then
        echo "ERROR: ${prompt_label}: need a hostname (stdin is not a TTY for fzf)" >&2
        return 1
    fi

    host_count="$(_init_ssh_hosts | grep -c . || true)"
    if [[ "${host_count:-0}" -eq 0 ]]; then
        echo "ERROR: ${prompt_label}: no hosts in ~/.ssh/config, config.d, or known_hosts" >&2
        return 1
    fi

    picked="$(
        _init_ssh_hosts | "$fzf_bin" \
            --height=40% \
            --reverse \
            --prompt="${prompt_label} > " \
            --header='SSH hosts (config + known_hosts)  (enter to connect)' \
            ${query:+--query="$query"}
    )" || true

    [[ -n "$picked" ]] || {
        echo "${prompt_label}: cancelled" >&2
        return 1
    }
    printf '%s\n' "$picked"
}

# Tab-complete hostnames for cssh/cmsh/cesh from the same list as the fzf picker.
function _init_ssh_host_complete()
{
    local cur="${COMP_WORDS[COMP_CWORD]}"
    [[ "$cur" == -* ]] && return 0
    # Intentional word-split of hostnames into COMPREPLY.
    # shellcheck disable=SC2207
    COMPREPLY=( $(compgen -W "$(_init_ssh_hosts)" -- "$cur") )
}

# Point cssh/cmsh/cesh at ssh/mosh completers when present; else use _init_ssh_hosts.
function _init_bind_cssh_cmsh_completion()
{
    local line

    if type __load_completion > /dev/null 2>&1; then
        __load_completion ssh 2>/dev/null || true
        __load_completion mosh 2>/dev/null || true
    fi

    if line="$(complete -p ssh 2>/dev/null)"; then
        eval "${line% *} cssh"
        eval "${line% *} cesh"
    else
        complete -o default -F _init_ssh_host_complete cssh
        complete -o default -F _init_ssh_host_complete cesh
    fi

    if line="$(complete -p mosh 2>/dev/null)"; then
        eval "${line% *} cmsh"
    elif line="$(complete -p ssh 2>/dev/null)"; then
        eval "${line% *} cmsh"
    else
        complete -o default -F _init_ssh_host_complete cmsh
    fi
}

# Eternal Terminal with automatic preferred-key re-cache when the agent lifetime expired.
# Does not shadow the et binary — use cesh explicitly for interactive hops.
function cesh()
{
    local et_bin ssh_bin ssh_dir host rc
    local -a args=()

    case "${1:-}" in
        -h|--help)
            cat <<'EOF'
Usage: cesh [et-args...]

Like et (Eternal Terminal), but ensures the preferred passphrase SSH key is loaded
in ssh-agent first. If the key is missing or its cache_ssh lifetime expired,
runs cache_ssh (prompts on a TTY), then invokes et with the same arguments.

With no arguments on a TTY, fuzzy-picks a host from ~/.ssh/config
(config.d) and cleartext ~/.ssh/known_hosts via fzf, then connects.

ET bootstraps over ssh, then keeps a reconnectable session (sleep/IP changes
like mosh) while staying a normal remote pty — CSI-u / Shift+Enter work.
Requires etserver on the remote (default port 2022).

Does not replace the et command — use cesh for interactive hops.

Examples:
  cesh                 # fzf host picker
  cesh other-host
  cesh --macserver mac-host   # Mac remotes with etterminal under /usr/local/bin
EOF
            return 0
            ;;
    esac

    # Quiet check; only prompt when the key is not in the agent.
    if ! cache_ssh -c 2>/dev/null; then
        cache_ssh || return $?
    fi

    if [[ $# -eq 0 ]]; then
        host="$(_init_ssh_fzf_pick_host cesh)" || return $?
        args=("$host")
    else
        args=("$@")
    fi

    et_bin="${init_tool_et:-}"
    if [[ -z "$et_bin" || ! -x "$et_bin" ]]; then
        et_bin="$(command -v et 2>/dev/null || true)"
    fi
    if [[ -z "$et_bin" || ! -x "$et_bin" ]]; then
        echo "ERROR: cesh: et not found (install Eternal Terminal, then run ~/.local/share/init-files/provision_init_files)" >&2
        return 1
    fi

    # Prefer provisioned ssh on PATH for ET's ssh bootstrap (et has no --ssh=).
    ssh_bin="${init_tool_ssh:-}"
    if [[ -z "$ssh_bin" || ! -x "$ssh_bin" ]]; then
        ssh_bin="$(command -v ssh 2>/dev/null || true)"
    fi
    _init_iterm_mark_hop "${args[@]}"
    if [[ -n "$ssh_bin" && -x "$ssh_bin" ]]; then
        ssh_dir="$(dirname -- "$ssh_bin")"
        PATH="${ssh_dir}${PATH:+:$PATH}" "$et_bin" "${args[@]}"
        rc=$?
        _init_iterm_unmark_hop
        return "$rc"
    fi

    "$et_bin" "${args[@]}"
    rc=$?
    _init_iterm_unmark_hop
    return "$rc"
}

# mosh with automatic preferred-key re-cache when the agent lifetime has expired.
# Does not shadow the mosh binary — use cmsh explicitly for interactive hops.
function cmsh()
{
    local mosh_bin ssh_bin arg has_ssh_opt=0 host rc
    local -a args=()

    case "${1:-}" in
        -h|--help)
            cat <<'EOF'
Usage: cmsh [mosh-args...]

Like mosh, but ensures the preferred passphrase SSH key is loaded in ssh-agent first.
If the key is missing or its cache_ssh lifetime expired, runs cache_ssh
(prompts on a TTY), then invokes mosh with the same arguments.

With no arguments on a TTY, fuzzy-picks a host from ~/.ssh/config
(config.d) and cleartext ~/.ssh/known_hosts via fzf, then connects.

Mosh still bootstraps over ssh, so the same preferred key / agent flow as cssh
applies. Survives laptop sleep and IP changes better than plain ssh.
Requires mosh-server on the remote host.

Does not replace the mosh command — use cmsh for interactive hops.

Examples:
  cmsh              # fzf host picker
  cmsh other-host
  cmsh mac-host
EOF
            return 0
            ;;
    esac

    # Quiet check; only prompt when the key is not in the agent.
    if ! cache_ssh -c 2>/dev/null; then
        cache_ssh || return $?
    fi

    if [[ $# -eq 0 ]]; then
        host="$(_init_ssh_fzf_pick_host cmsh)" || return $?
        args=("$host")
    else
        args=("$@")
    fi

    mosh_bin="${init_tool_mosh:-}"
    if [[ -z "$mosh_bin" || ! -x "$mosh_bin" ]]; then
        mosh_bin="$(command -v mosh 2>/dev/null || true)"
    fi
    if [[ -z "$mosh_bin" || ! -x "$mosh_bin" ]]; then
        echo "ERROR: cmsh: mosh not found (install mosh, then run ~/.local/share/init-files/provision_init_files)" >&2
        return 1
    fi

    for arg in "${args[@]}"; do
        case "$arg" in
            --ssh|--ssh=*)
                has_ssh_opt=1
                break
                ;;
        esac
    done

    # Prefer provisioned ssh for the login handshake (mosh default is bare "ssh").
    _init_iterm_mark_hop "${args[@]}"
    if [[ "$has_ssh_opt" -eq 0 ]]; then
        ssh_bin="${init_tool_ssh:-}"
        if [[ -z "$ssh_bin" || ! -x "$ssh_bin" ]]; then
            ssh_bin="$(command -v ssh 2>/dev/null || true)"
        fi
        if [[ -n "$ssh_bin" && -x "$ssh_bin" ]]; then
            "$mosh_bin" --ssh="$ssh_bin" "${args[@]}"
            rc=$?
            _init_iterm_unmark_hop
            return "$rc"
        fi
    fi

    "$mosh_bin" "${args[@]}"
    rc=$?
    _init_iterm_unmark_hop
    return "$rc"
}

function createpatch()
{
    local fn
    fn="$HOME/backup/$(basename "$(pwd)")-$(date +%Y%m%d%H%M%S).svndiff"
    svn diff --diff-cmd /usr/bin/diff -x "-r -u --new-file" > "$fn"
    echo "created $fn"
    cp "$fn" "$HOME/backup/latestpatch.svndiff"
}

function cryptcat()
{
    local target

    case "${1:-}" in
        -h|--help|"")
            cat <<'EOF'
Usage: cryptcat <name>

Decrypt <name>.crypt to stdout (no extract).
Example: cryptcat /tmp/foo   # reads /tmp/foo.crypt
EOF
            [[ -n "${1:-}" ]]
            return
            ;;
        -*)
            echo "ERROR: cryptcat: unknown option: $1" >&2
            return 1
            ;;
    esac

    target="${1%.crypt}"
    gpg_symmetric --decrypt -- "${target}.crypt"
}

# ssh with automatic preferred-key re-cache when the agent lifetime has expired.
# Does not shadow the ssh binary — use cssh explicitly for interactive hops.
function cssh()
{
    local ssh_bin host rc
    local -a args=()

    case "${1:-}" in
        -h|--help)
            cat <<'EOF'
Usage: cssh [ssh-args...]

Like ssh, but ensures the preferred passphrase SSH key is loaded in ssh-agent first.
If the key is missing or its cache_ssh lifetime expired, runs cache_ssh
(prompts on a TTY), then invokes ssh with the same arguments.

With no arguments on a TTY, fuzzy-picks a host from ~/.ssh/config
(config.d) and cleartext ~/.ssh/known_hosts via fzf, then connects.

Does not replace the ssh command — scripts and BatchMode keep using plain ssh.

Examples:
  cssh              # fzf host picker
  cssh other-host
  cssh -t mac-host
EOF
            return 0
            ;;
    esac

    # Quiet check; only prompt when the key is not in the agent.
    if ! cache_ssh -c 2>/dev/null; then
        cache_ssh || return $?
    fi

    if [[ $# -eq 0 ]]; then
        host="$(_init_ssh_fzf_pick_host cssh)" || return $?
        args=("$host")
    else
        args=("$@")
    fi

    ssh_bin="${init_tool_ssh:-}"
    if [[ -z "$ssh_bin" || ! -x "$ssh_bin" ]]; then
        ssh_bin="$(command -v ssh 2>/dev/null || true)"
    fi
    if [[ -z "$ssh_bin" || ! -x "$ssh_bin" ]]; then
        echo "ERROR: cssh: ssh not found (run ~/.local/share/init-files/provision_init_files)" >&2
        return 1
    fi

    _init_iterm_mark_hop "${args[@]}"
    "$ssh_bin" "${args[@]}"
    rc=$?
    _init_iterm_unmark_hop
    return "$rc"
}

function decrypt()
{
    local target target_dir target_base extract_dir restored

    case "${1:-}" in
        -h|--help|"")
            cat <<'EOF'
Usage: decrypt <name>

Decrypt <name>.crypt, restore <name> in place, and remove the temporary .tar.
Example: decrypt /tmp/foo   # reads /tmp/foo.crypt, restores /tmp/foo
EOF
            [[ -n "${1:-}" ]]
            return
            ;;
        -*)
            echo "ERROR: decrypt: unknown option: $1" >&2
            return 1
            ;;
    esac

    target="${1%.crypt}"
    target_dir=$(dirname -- "$target")
    target_base=$(basename -- "$target")

    gpg_symmetric --output "${target}.tar" --decrypt -- "${target}.crypt"
    if [[ "$?" -ne 0 ]]; then
        echo "ERROR: failure decrypting '${target}.crypt' -- missing file or incorrect password" >&2
        return 1
    fi

    extract_dir=$(mktemp -d "${TMPDIR:-/tmp}/decrypt.XXXXXX") || {
        echo "ERROR: could not create temporary extract directory" >&2
        /bin/rm -f "${target}.tar"
        return 1
    }

    if ! tar -C "$extract_dir" -xf "${target}.tar"; then
        echo "ERROR: failure extracting '${target}.tar'" >&2
        /bin/rm -rf "$extract_dir" "${target}.tar"
        return 1
    fi

    if [[ -e "$extract_dir/$target_base" ]]; then
        restored="$extract_dir/$target_base"
    elif [[ "$target" == /* && -e "$extract_dir$target" ]]; then
        restored="$extract_dir$target"
    elif [[ -e "$extract_dir/${target#/}" ]]; then
        restored="$extract_dir/${target#/}"
    else
        echo "ERROR: decrypted archive did not contain '$target_base'" >&2
        /bin/rm -rf "$extract_dir" "${target}.tar"
        return 1
    fi

    mkdir -p -- "$target_dir" || {
        /bin/rm -rf "$extract_dir" "${target}.tar"
        return 1
    }
    /bin/rm -rf -- "$target"
    if ! mv -- "$restored" "$target"; then
        echo "ERROR: could not restore '$target'" >&2
        /bin/rm -rf "$extract_dir" "${target}.tar"
        return 1
    fi

    /bin/rm -rf -- "$extract_dir" "${target}.tar"
}

function detect_gh_cleanup_notice()
{
    local gh_path package_name local_gh

    # macOS installs via Homebrew; local ~/.local/bin/gh is a Linux fallback only.
    [[ "$OSTYPE" == "darwin"* ]] && return 0

    local_gh="$HOME/.local/bin/gh"
    [[ -x "$local_gh" ]] || return 0

    while IFS= read -r gh_path; do
        [[ -n "$gh_path" ]] || continue
        [[ "$gh_path" == "$HOME/.local/"* ]] && continue

        package_name=
        if command -v dpkg-query > /dev/null 2>&1; then
            package_name=$(dpkg-query --search "$gh_path" 2> /dev/null | awk -F': ' 'NR == 1 { print $1 }')
            if [[ -n "$package_name" ]]; then
                printf '  gh cleanup: %s is still installed from apt at %s\n' "$package_name" "$gh_path"
                printf '    cleanup: ask an admin to run sudo apt remove %s\n' "$package_name"
                return
            fi
        fi

        if command -v rpm > /dev/null 2>&1; then
            package_name=$(rpm -qf "$gh_path" 2> /dev/null || true)
            if [[ -n "$package_name" && "$package_name" != "file $gh_path is not owned by any package" ]]; then
                if command -v dnf > /dev/null 2>&1; then
                    printf '  gh cleanup: %s is still installed from rpm at %s\n' "$package_name" "$gh_path"
                    printf '    cleanup: ask an admin to run sudo dnf remove %s\n' "$package_name"
                else
                    printf '  gh cleanup: %s is still installed from rpm at %s\n' "$package_name" "$gh_path"
                    printf '    cleanup: ask an admin to run sudo yum remove %s\n' "$package_name"
                fi
                return
            fi
        fi

        printf '  gh cleanup: non-local gh still present at %s\n' "$gh_path"
        printf '    cleanup: remove it if you want ~/.local/bin/gh to be the only gh on this box\n'
        return
    done < <(type -ap gh 2> /dev/null | awk '!seen[$0]++')

    return 0
}

function bash_completion_install_hint()
{
    if _init_is_darwin && type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos; then
        printf 'brew install bash-completion@2'
        return 0
    fi
    if _init_is_darwin; then
        printf 'install bash-completion without Homebrew (e.g. copy into ~/.local); brew not recommended on this macOS'
        return 0
    fi
    if command -v apt-get > /dev/null 2>&1 || command -v apt > /dev/null 2>&1; then
        printf 'sudo apt install bash-completion'
        return 0
    fi
    if command -v dnf > /dev/null 2>&1; then
        printf 'sudo dnf install bash-completion'
        return 0
    fi
    if command -v yum > /dev/null 2>&1; then
        printf 'sudo yum install bash-completion'
        return 0
    fi
    printf 'install bash-completion via your OS package manager'
}

function bash_completion_is_available()
{
    local candidate brew_prefix

    [[ -n "${BASH_COMPLETION_VERSINFO:-}" ]] && return 0

    brew_prefix=
    if type _init_homebrew_prefix > /dev/null 2>&1; then
        brew_prefix="$(_init_homebrew_prefix 2>/dev/null || true)"
    fi
    for candidate in \
        "${brew_prefix:+$brew_prefix/etc/profile.d/bash_completion.sh}" \
        /usr/share/bash-completion/bash_completion \
        /etc/bash_completion \
        /usr/local/etc/profile.d/bash_completion.sh \
        /usr/local/etc/bash_completion
    do
        [[ -n "$candidate" && -r "$candidate" ]] && return 0
    done
    return 1
}

function bash_completion_status_line()
{
    local green red reset tone ver yellow

    green=
    red=
    yellow=
    reset=
    tone=
    if [[ -n "$tool_status_use_color" ]]; then
        green=$'\033[32m'
        red=$'\033[31m'
        yellow=$'\033[33m'
        reset=$'\033[0m'
    fi

    if bash_completion_is_available; then
        if [[ -n "${BASH_COMPLETION_VERSINFO:-}" ]]; then
            ver=$(IFS=.; echo "${BASH_COMPLETION_VERSINFO[*]}")
        else
            ver="present"
        fi
        printf '%s  bash-completion: installed %s, status: available%s' "$green" "$ver" "$reset"
        return 0
    fi

    # Modern macOS: required via brew — red like other missing required tools.
    # Elsewhere: optional helper — yellow.
    if _init_is_darwin && type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos; then
        tone="$red"
    else
        tone="$yellow"
    fi
    [[ -n "$tone" ]] || tone="$red"
    printf '%s  bash-completion: not installed%s' "$tone" "$reset"
    printf '\n%s    install: %s%s' "$tone" "$(bash_completion_install_hint)" "$reset"
}

function bash_brew_cellar_path()
{
    local bash_path

    bash_path="${1:-${init_tool_bash:-}}"
    if [[ -z "$bash_path" ]] && command -v brew > /dev/null 2>&1; then
        bash_path="$(brew --prefix 2> /dev/null)/bin/bash"
    fi
    [[ -n "$bash_path" && -e "$bash_path" ]] || return 1

    if [[ -n "${init_tool_python3:-}" && -x "$init_tool_python3" ]]; then
        "$init_tool_python3" -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$bash_path" 2> /dev/null
        return
    fi
    readlink -f "$bash_path" 2> /dev/null || printf '%s' "$bash_path"
}

function bash_current_version()
{
    local bash_path

    bash_path="${1:-}"
    if [[ -z "$bash_path" || ! -x "$bash_path" ]]; then
        printf '%s' "${BASH_VERSION%%(*}"
        return 0
    fi
    "$bash_path" --version 2> /dev/null | awk 'NR == 1 {
        if (match($0, /[0-9]+(\.[0-9]+)+/)) {
            print substr($0, RSTART, RLENGTH)
            exit
        }
    }'
}

function bash_is_apple_system_path()
{
    local bash_path resolved_bash_path

    bash_path="${1:-}"
    [[ -n "$bash_path" ]] || return 1

    case "$bash_path" in
        /bin/bash|/usr/bin/bash)
            return 0
            ;;
    esac

    # Homebrew Cellar / opt paths are never Apple system bash.
    if bash_is_versioned_cellar_path "$bash_path"; then
        return 1
    fi
    case "$bash_path" in
        */Cellar/bash/*|*/opt/bash/*|/opt/homebrew/*|*/homebrew/*)
            return 1
            ;;
    esac

    if [[ -n "${init_tool_python3:-}" && -x "$init_tool_python3" ]]; then
        resolved_bash_path=$("$init_tool_python3" -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$bash_path" 2> /dev/null || true)
    fi
    [[ -n "$resolved_bash_path" ]] || resolved_bash_path=$(readlink "$bash_path" 2> /dev/null || printf '%s' "$bash_path")

    case "$resolved_bash_path" in
        /bin/bash|/usr/bin/bash)
            return 0
            ;;
        */Cellar/bash/*|*/opt/bash/*|/opt/homebrew/*|*/homebrew/*)
            return 1
            ;;
    esac
    return 1
}

function bash_is_versioned_cellar_path()
{
    local bash_path

    bash_path="${1:-}"
    [[ -n "$bash_path" ]] || return 1
    # Homebrew versioned binary, e.g. .../Cellar/bash/5.3.15/bin/bash
    [[ "$bash_path" == */Cellar/bash/*/bin/bash ]]
}

function bash_login_shell_setup_hint()
{
    local preferred cellar prefix suffix

    preferred="${1:-${init_tool_bash:-}}"
    prefix="${2:-}"
    suffix="${3:-}"

    if [[ -z "$preferred" ]] && command -v brew > /dev/null 2>&1; then
        preferred="$(brew --prefix 2> /dev/null)/bin/bash"
    fi
    [[ -n "$preferred" ]] || return 0

    # Brew Cellar /etc/shells + chsh steps are modern-macOS only.
    if _init_is_darwin && type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos; then
        # macOS chpass(1) warns when a shell "is not a regular file" (symlink).
        # Homebrew's bin shim is a symlink into Cellar; on this host /etc/shells
        # and UserShell use the Cellar realpath. After each bash upgrade the
        # versioned path changes — re-add it and chsh again.
        cellar="$(bash_brew_cellar_path "$preferred" 2> /dev/null || true)"
        [[ -n "$cellar" ]] || cellar="$preferred"

        printf '%s    tip: after upgrading bash on macOS, refresh formulae then register the Cellar binary as the login shell:%s\n' \
            "$prefix" "$suffix"
        printf '%s      1. brew update && brew upgrade bash%s\n' "$prefix" "$suffix"
        printf '%s      2. sudo edit /etc/shells and add the new Cellar path (chpass wants a regular file, not the brew bin symlink):%s\n' \
            "$prefix" "$suffix"
        printf '%s         %s%s\n' "$prefix" "$cellar" "$suffix"
        printf '%s         (or: grep -qxF %s /etc/shells || echo %s | sudo tee -a /etc/shells)%s\n' \
            "$prefix" "$cellar" "$cellar" "$suffix"
        printf '%s      3. chsh -s %s%s\n' "$prefix" "$cellar" "$suffix"
        printf '%s      4. reopen the terminal (Default login shell)%s\n' "$prefix" "$suffix"
        printf '%s    note: /opt/homebrew/bin/bash is only a symlink; guides that chsh to it often fail or warn on macOS%s\n' \
            "$prefix" "$suffix"
    elif ! _init_is_darwin; then
        printf '%s    tip: point the login shell at %s (e.g. chsh)%s\n' \
            "$prefix" "$preferred" "$suffix"
    fi
}

function bash_package_name()
{
    local bash_path

    bash_path="${1:-${init_tool_bash:-}}"
    [[ -n "$bash_path" ]] || return 1

    if command -v rpm > /dev/null 2>&1; then
        rpm -qf "$bash_path" 2> /dev/null | head -n 1
        return 0
    fi

    if command -v dpkg-query > /dev/null 2>&1; then
        dpkg-query --search "$bash_path" 2> /dev/null | awk -F': ' 'NR == 1 { print $1; exit }'
        return 0
    fi

    return 1
}

function bash_paths_equivalent()
{
    local left right left_real right_real

    left="${1:-}"
    right="${2:-}"
    [[ -n "$left" && -n "$right" ]] || return 1
    [[ "$left" == "$right" ]] && return 0
    [[ -e "$left" && -e "$right" ]] || return 1

    if [[ -n "${init_tool_python3:-}" && -x "$init_tool_python3" ]]; then
        "$init_tool_python3" -c 'import os,sys; raise SystemExit(0 if os.path.samefile(sys.argv[1], sys.argv[2]) else 1)' \
            "$left" "$right" 2> /dev/null
        return
    fi

    left_real=$(readlink -f "$left" 2> /dev/null || printf '%s' "$left")
    right_real=$(readlink -f "$right" 2> /dev/null || printf '%s' "$right")
    [[ "$left_real" == "$right_real" ]]
}

function bash_tool_status_line()
{
    local bash_path current_version distro_latest kind latest_label latest_version

    bash_path="$1"
    current_version="$(normalize_version "$2")"
    latest_version="$(normalize_version "$3")"
    kind="$(bash_upgrade_kind "$current_version" "$latest_version" "$bash_path" 2> /dev/null || true)"
    distro_latest="$(normalize_version "$(fetch_bash_latest_distro 2> /dev/null || true)")"

    if [[ -n "$latest_version" ]]; then
        latest_label="$latest_version"
    else
        latest_label=""
    fi

    case "$kind" in
        package-manager)
            tool_status_line bash "$bash_path" "$2" "$latest_label" auto
            ;;
        platform-capped)
            # Show current as the platform max so we do not imply a brew upgrade.
            tool_status_line bash "$bash_path" "$2" "$2" auto
            printf '\n    note: Apple /bin/bash is frozen at 3.2.x on this macOS tier (Homebrew bash not used)'
            ;;
        upstream-only)
            tool_status_line bash "$bash_path" "$2" "$latest_label" blocked
            if [[ -n "$distro_latest" ]]; then
                printf '\n    note: distro repos offer %s (already current there)' "$distro_latest"
            fi
            printf '\n    next step: install a newer bash from upstream (manual)'
            ;;
        up-to-date)
            # When current >= reachable latest (e.g. bash 5.3.9 vs apt Candidate
            # normalizing to 5.3), show up to date — do not pass mismatched
            # versions into tool_status_line (that prints "ahead of latest").
            tool_status_line bash "$bash_path" "$2" "$2" auto
            ;;
        *)
            tool_status_line bash "$bash_path" "$2" "$latest_label"
            ;;
    esac
}

function bash_upgrade_kind()
{
    local bash_path current_version distro_latest reachable_latest strategy_name

    current_version="$(normalize_version "$1")"
    reachable_latest="$(normalize_version "$2")"
    bash_path="${3:-}"

    [[ -n "$current_version" ]] || return 1

    strategy_name="$(detect_bash_update_strategy "$bash_path" 2> /dev/null | awk -F '\t' 'NR == 1 { print $1 }')"

    case "$strategy_name" in
        apple-frozen)
            printf 'platform-capped'
            return 0
            ;;
    esac

    if [[ -z "$reachable_latest" ]]; then
        printf 'unknown'
        return 0
    fi

    if versions_equal "$current_version" "$reachable_latest" \
        || ! version_lt "$current_version" "$reachable_latest"; then
        printf 'up-to-date'
        return 0
    fi

    case "$strategy_name" in
        brew)
            printf 'package-manager'
            return 0
            ;;
        dnf|yum|apt)
            distro_latest="$(normalize_version "$(fetch_bash_latest_distro 2> /dev/null || true)")"
            if [[ -n "$distro_latest" ]] && version_lt "$current_version" "$distro_latest"; then
                printf 'package-manager'
                return 0
            fi
            printf 'upstream-only'
            return 0
            ;;
        *)
            printf 'upstream-only'
            return 0
            ;;
    esac
}

function detect_bash_update_strategy()
{
    local bash_path brew_prefix package_name resolved_bash_path

    bash_path="${1:-${init_tool_bash:-}}"
    [[ -n "$bash_path" ]] || return 1

    # Older macOS: never recommend Homebrew. Apple system bash is frozen;
    # a pre-existing Homebrew/other bash is reported but upgrade is manual.
    if _init_is_darwin && type _init_is_modern_macos > /dev/null 2>&1 && ! _init_is_modern_macos; then
        if bash_is_apple_system_path "$bash_path"; then
            printf 'apple-frozen\tbash'
        else
            printf 'upstream-only\tbash'
        fi
        return 0
    fi

    if _init_is_darwin && type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos \
        && command -v brew > /dev/null 2>&1
    then
        brew_prefix="$(brew --prefix 2> /dev/null || true)"
        if command -v "$init_tool_python3" > /dev/null 2>&1; then
            resolved_bash_path=$("$init_tool_python3" -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$bash_path" 2> /dev/null || true)
        fi
        [[ -n "$resolved_bash_path" ]] || resolved_bash_path=$(readlink "$bash_path" 2> /dev/null || printf '%s' "$bash_path")
        if [[ -n "$brew_prefix" && ( "$bash_path" == "$brew_prefix"/* || "$resolved_bash_path" == "$brew_prefix"/* || "$resolved_bash_path" == */Cellar/bash/* ) ]] \
            || _init_brew_formula_present bash
        then
            printf 'brew\tbash'
            return 0
        fi
    fi

    package_name="$(bash_package_name "$bash_path" 2> /dev/null || true)"
    if [[ -z "$package_name" || "$package_name" == *"not owned"* ]]; then
        printf 'upstream-only\tbash'
        return 0
    fi

    if command -v dnf > /dev/null 2>&1; then
        printf 'dnf\t%s' "$package_name"
        return 0
    fi

    if command -v yum > /dev/null 2>&1; then
        printf 'yum\t%s' "$package_name"
        return 0
    fi

    if command -v apt-get > /dev/null 2>&1 || command -v apt > /dev/null 2>&1; then
        printf 'apt\t%s' "$package_name"
        return 0
    fi

    printf 'upstream-only\tbash'
}

# True when a Homebrew formula appears installed/linked. Path check only —
# never `brew list` (Cellar walks hang and block interactive shells).
function _init_brew_formula_present()
{
    local name="$1"
    local prefix

    [[ -n "$name" ]] || return 1
    if type _init_homebrew_prefix > /dev/null 2>&1; then
        prefix="$(_init_homebrew_prefix 2>/dev/null || true)"
    fi
    if [[ -z "$prefix" ]] && command -v brew > /dev/null 2>&1; then
        prefix="$(brew --prefix 2>/dev/null || true)"
    fi
    [[ -n "$prefix" ]] || return 1
    [[ -e "$prefix/opt/$name" || -d "$prefix/Cellar/$name" ]]
}

# True when this macOS account is in the admin group (or root).
# Homebrew installs (bash, fonts, …) may need an admin; Node uses nvm (no sudo).
function _init_is_macos_admin()
{
    local user

    _init_is_darwin || return 1
    [[ "$(id -u)" -eq 0 ]] && return 0
    user="$(id -un 2>/dev/null || true)"
    [[ -n "$user" ]] || return 1
    if command -v dseditgroup >/dev/null 2>&1; then
        dseditgroup -o checkmember -m "$user" admin >/dev/null 2>&1 && return 0
        return 1
    fi
    id -Gn 2>/dev/null | grep -qw admin
}

# Multi-line admin cut-paste for tools that need Homebrew on modern macOS.
# Auto-detects admin: prints nothing for admins (caller shows normal install cmds)
# and nothing for user-local tools (nvm Node). Used by check_tool_versions.
function tool_admin_install_steps()
{
    local tool_name="$1"
    local formula="" clone_dir

    _init_is_darwin || return 1
    type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos || return 1
    # Admin accounts get direct brew/update_* hints — not this handoff.
    _init_is_macos_admin && return 1

    case "$tool_name" in
        npm|npx|gt|pnpm)
            return 1
            ;;
        bash)
            formula=bash
            ;;
        bash-completion)
            formula='bash-completion@2'
            ;;
        fzf)
            formula=fzf
            ;;
        git)
            formula=git
            ;;
        gh)
            formula=gh
            ;;
        *)
            return 1
            ;;
    esac

    clone_dir="${init_files_dir:-${XDG_DATA_HOME:-$HOME/.local/share}/init-files}"
    printf 'ask an admin (MDM): brew install %s' "$formula"
    printf '\n    (or run %s/provision_init_files for a forwardable handoff block)' "$clone_dir"
}

# If this modern-macOS account cannot brew-install, print a one-formula handoff and fail.
# Returns 0 when brew may proceed (admin, or not modern macOS).
function _init_brew_admin_or_handoff()
{
    local formula="$1"
    local clone_dir

    type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos || return 0
    _init_is_macos_admin && return 0

    clone_dir="${init_files_dir:-${XDG_DATA_HOME:-$HOME/.local/share}/init-files}"
    printf 'This account is not a macOS admin (MDM). Forward to IT:\n' >&2
    printf '  brew install %s\n' "$formula" >&2
    printf 'Then re-run (as yourself): %s/provision_init_files\n' "$clone_dir" >&2
    return 1
}

# True when the current user is in a typical sudo-capable group (Linux + macOS names).
function _init_user_in_sudo_group()
{
    local groups

    groups="$(id -nG 2>/dev/null || true)"
    [[ -n "$groups" ]] || return 1
    # Ubuntu: sudo; Rocky/RHEL: wheel; macOS: admin (harmless on Darwin for this helper).
    [[ " $groups " == *" sudo "* || " $groups " == *" wheel "* || " $groups " == *" admin "* ]]
}

# True when elevating needs no password prompt (root or NOPASSWD sudo).
function _init_can_sudo_nopasswd()
{
    [[ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]] && return 0
    command -v sudo > /dev/null 2>&1 || return 1
    sudo -n true > /dev/null 2>&1
}

# Before Linux package-manager upgrades that need sudo: allow root / NOPASSWD /
# sudoers-group (interactive password OK); otherwise print a forwardable handoff
# and return 1 without invoking sudo. No-op (return 0) on Darwin.
# Args: exact upgrade command line(s) for the admin to copy-paste; optional
# follow-up hint (default: update_git).
function _init_linux_sudo_or_handoff()
{
    local upgrade_command="${1:-}"
    local follow_up="${2:-update_git}"

    _init_is_darwin && return 0
    [[ -n "$upgrade_command" ]] || return 1

    _init_can_sudo_nopasswd && return 0
    _init_user_in_sudo_group && return 0

    printf 'This account cannot use sudo. Forward to an admin:\n' >&2
    printf '  %s\n' "$upgrade_command" >&2
    printf 'Then re-run (as yourself): %s\n' "$follow_up" >&2
    return 1
}

# True when this Linux account can run sudo upgrades (nopasswd or sudo/wheel group).
# Used by suggested-command hints; Darwin always "can" (brew path is separate).
function _init_linux_can_sudo_upgrade()
{
    _init_is_darwin && return 0
    _init_can_sudo_nopasswd && return 0
    _init_user_in_sudo_group && return 0
    return 1
}

function detect_git_update_strategy()
{
    local git_path package_name brew_prefix resolved_git_path

    git_path="${1:-$init_tool_git}"
    [[ -n "$git_path" ]] || return 1

    # Homebrew upgrades only on modern macOS (Darwin 25+). Older macOS never
    # recommends brew even if a Homebrew git happens to be on PATH.
    if _init_is_darwin && type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos \
        && command -v brew > /dev/null 2>&1
    then
        brew_prefix="$(brew --prefix 2> /dev/null || true)"
        if command -v "$init_tool_python3" > /dev/null 2>&1; then
            resolved_git_path=$("$init_tool_python3" -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$git_path" 2> /dev/null || true)
        fi
        [[ -n "$resolved_git_path" ]] || resolved_git_path=$(readlink "$git_path" 2> /dev/null || printf '%s' "$git_path")
        if [[ -n "$brew_prefix" && ( "$git_path" == "$brew_prefix"/* || "$resolved_git_path" == "$brew_prefix"/* || "$resolved_git_path" == */Cellar/git/* ) ]] \
            || _init_brew_formula_present git
        then
            printf 'brew\tgit'
            return 0
        fi
    fi

    package_name="$(git_package_name "$git_path" 2> /dev/null || true)"
    if [[ -z "$package_name" || "$package_name" == *"not owned"* ]]; then
        printf 'upstream-source\tgit'
        return 0
    fi

    if command -v dnf > /dev/null 2>&1; then
        printf 'dnf\t%s' "$package_name"
        return 0
    fi

    if command -v yum > /dev/null 2>&1; then
        printf 'yum\t%s' "$package_name"
        return 0
    fi

    if command -v apt-get > /dev/null 2>&1 || command -v apt > /dev/null 2>&1; then
        printf 'apt\t%s' "$package_name"
        return 0
    fi

    printf 'upstream-source\tgit'
}

function detect_pipx_update_strategy()
{
    local package_name pipx_path python_scripts_pipx resolved_pipx_path user_base user_scripts_pipx

    pipx_path="${1:-$(pipx_command_path 2> /dev/null || true)}"
    [[ -n "$pipx_path" ]] || return 1
    resolved_pipx_path=$(readlink -f "$pipx_path" 2> /dev/null || printf '%s' "$pipx_path")

    if _init_is_darwin && type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos \
        && command -v brew > /dev/null 2>&1
    then
        if _init_brew_formula_present pipx; then
            printf 'brew\tpipx'
            return 0
        fi
    fi

    if command -v dpkg-query > /dev/null 2>&1; then
        package_name=$(dpkg-query --search "$pipx_path" 2> /dev/null | awk -F': ' 'NR == 1 { print $1 }')
        if [[ -n "$package_name" ]]; then
            printf 'apt\t%s' "$package_name"
            return 0
        fi
    fi

    if command -v rpm > /dev/null 2>&1; then
        package_name=$(rpm -qf "$pipx_path" 2> /dev/null || true)
        if [[ -n "$package_name" && "$package_name" != "file $pipx_path is not owned by any package" ]]; then
            if command -v dnf > /dev/null 2>&1; then
                printf 'dnf\t%s' "$package_name"
            else
                printf 'yum\t%s' "$package_name"
            fi
            return 0
        fi
    fi

    if command -v "$init_tool_python3" > /dev/null 2>&1; then
        python_scripts_pipx=$(
            "$init_tool_python3" - <<'PY'
import os
import sysconfig

print(os.path.realpath(os.path.join(sysconfig.get_path("scripts"), "pipx")))
PY
        ) || python_scripts_pipx=

        user_base=$(
            "$init_tool_python3" - <<'PY'
import site

print(site.USER_BASE)
PY
        ) || user_base=

        user_scripts_pipx=
        if [[ -n "$user_base" ]]; then
            user_scripts_pipx=$(readlink -f "$user_base/bin/pipx" 2> /dev/null || printf '%s' "$user_base/bin/pipx")
        fi

        if [[ -n "$user_scripts_pipx" ]] \
            && [[ "$resolved_pipx_path" == "$user_scripts_pipx" ]] \
            && "$init_tool_python3" -m pip show pipx > /dev/null 2>&1; then
            printf 'pip-user\tpipx'
            return 0
        fi

        if [[ -n "$python_scripts_pipx" ]] \
            && [[ "$resolved_pipx_path" == "$python_scripts_pipx" ]] \
            && "$init_tool_python3" -m pip show pipx > /dev/null 2>&1; then
            printf 'pip\tpipx'
            return 0
        fi
    fi

    printf 'manual\tpipx'
}

function detect_uv_update_strategy()
{
    local uv_path package_name resolved_uv_path python_scripts_uv

    uv_path="${1:-$(command -v uv 2> /dev/null || true)}"
    [[ -n "$uv_path" ]] || return 1
    resolved_uv_path=$(readlink -f "$uv_path" 2> /dev/null || printf '%s' "$uv_path")

    if _init_is_darwin && type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos \
        && command -v brew > /dev/null 2>&1
    then
        if _init_brew_formula_present uv; then
            printf 'brew\tuv'
            return 0
        fi
    fi

    if [[ "$resolved_uv_path" == *"/pipx/venvs/"*"/bin/uv" ]]; then
        # The default pipx path is required here.
        # shellcheck disable=SC2119
        if ! pipx_is_usable; then
            printf 'pipx-bootstrap\tuv'
        elif pipx_venv_missing_pip "$resolved_uv_path"; then
            printf 'pipx-reinstall\tuv'
        else
            printf 'pipx\tuv'
        fi
        return 0
    fi

    # The default pipx path is required here.
    # shellcheck disable=SC2119
    if pipx_is_usable; then
        if pipx list 2> /dev/null | grep -Eq '^[[:space:]]*package uv '; then
            printf 'pipx\tuv'
            return 0
        fi
    fi

    if command -v "$init_tool_python3" > /dev/null 2>&1; then
        python_scripts_uv=$(
            "$init_tool_python3" - <<'PY'
import os
import sysconfig

print(os.path.realpath(os.path.join(sysconfig.get_path("scripts"), "uv")))
PY
        ) || python_scripts_uv=
        if [[ -n "$python_scripts_uv" ]] \
            && [[ "$resolved_uv_path" == "$python_scripts_uv" ]] \
            && "$init_tool_python3" -m pip show uv > /dev/null 2>&1; then
            printf 'pip\tuv'
            return 0
        fi
    fi

    if command -v dpkg-query > /dev/null 2>&1; then
        package_name=$(dpkg-query --search "$uv_path" 2> /dev/null | awk -F': ' 'NR == 1 { print $1 }')
        if [[ -n "$package_name" ]]; then
            printf 'apt\t%s' "$package_name"
            return 0
        fi
    fi

    if command -v rpm > /dev/null 2>&1; then
        package_name=$(rpm -qf "$uv_path" 2> /dev/null || true)
        if [[ -n "$package_name" && "$package_name" != "file $uv_path is not owned by any package" ]]; then
            if command -v dnf > /dev/null 2>&1; then
                printf 'dnf\t%s' "$package_name"
            else
                printf 'yum\t%s' "$package_name"
            fi
            return 0
        fi
    fi

    printf 'self\tuv'
}

function encrypt()
{
    local target target_dir target_base

    case "${1:-}" in
        -h|--help|"")
            cat <<'EOF'
Usage: encrypt <name>

Tar <name>, encrypt to <name>.crypt (AES256), and remove the original and .tar.
Example: encrypt /tmp/foo   # writes /tmp/foo.crypt
EOF
            [[ -n "${1:-}" ]]
            return
            ;;
        -*)
            echo "ERROR: encrypt: unknown option: $1" >&2
            return 1
            ;;
    esac

    target="${1%.crypt}"
    target="${target%.tar}"
    target_dir=$(dirname -- "$target")
    target_base=$(basename -- "$target")

    if [[ ! -e "$target" ]]; then
        echo "ERROR: encrypt: '$target' does not exist" >&2
        return 1
    fi

    tar -C "$target_dir" -cf "${target}.tar" "$target_base"
    if [[ "$?" -ne 0 ]]; then
        echo "ERROR: failure tar'ring '${target}' -- original file left behind" >&2
        return 1
    fi
    gpg_symmetric --output "${target}.crypt" --symmetric --cipher-algo AES256 -- "${target}.tar"
    if [[ "$?" -ne 0 ]]; then
        echo "ERROR: failure encrypting '${target}.tar' -- original and tar file left behind" >&2
        return 1
    fi
    /bin/rm -rf -- "$target" "${target}.tar"
}

function fetch_bash_latest()
{
    local brew_ver distro_ver upstream_ver

    # Modern macOS: Homebrew formula is the reachable latest.
    if _init_is_darwin && type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos; then
        brew_ver="$(fetch_bash_latest_brew 2> /dev/null || true)"
        if [[ -n "$brew_ver" ]]; then
            printf '%s\n' "$brew_ver"
            return 0
        fi
    fi

    # Prefer GNU upstream when reachable; fall back to distro candidate so Linux
    # hosts never stay on "latest check pending" when gnu.org is slow/blocked.
    upstream_ver="$(fetch_bash_latest_upstream 2> /dev/null || true)"
    distro_ver="$(fetch_bash_latest_distro 2> /dev/null || true)"
    if [[ -n "$upstream_ver" ]]; then
        printf '%s\n' "$upstream_ver"
        return 0
    fi
    if [[ -n "$distro_ver" ]]; then
        printf '%s\n' "$distro_ver"
        return 0
    fi
    return 1
}

function fetch_bash_latest_brew()
{
    local brew_bin

    _init_is_darwin || return 1
    type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos || return 1
    command -v brew > /dev/null 2>&1 || return 1
    [[ -n "${init_tool_python3:-}" && -x "$init_tool_python3" ]] || return 1

    brew_bin=$(command -v brew)
    "$brew_bin" info --json=v2 bash 2> /dev/null \
        | "$init_tool_python3" -c 'import json,sys; d=json.load(sys.stdin); print(d["formulae"][0]["versions"]["stable"])' 2> /dev/null
}

function fetch_apt_policy_candidate()
{
    local pkg raw
    local timeout_cmd=()

    pkg="$1"
    [[ -n "$pkg" ]] || return 1
    command -v apt-cache > /dev/null 2>&1 || return 1

    # apt-cache is usually instant; still bound it so a wedged dpkg never hangs
    # interactive shells / tool-version rebuilds.
    if command -v timeout > /dev/null 2>&1; then
        timeout_cmd=(timeout 5)
    fi

    raw=$("${timeout_cmd[@]}" apt-cache policy "$pkg" 2> /dev/null | awk '/Candidate:/ { print $2; exit }')
    [[ -n "$raw" && "$raw" != "(none)" ]] || return 1
    printf '%s\n' "$raw"
}

function fetch_distro_package_version()
{
    local pkg raw
    local timeout_cmd=()

    pkg="$1"
    [[ -n "$pkg" ]] || return 1

    if command -v apt-cache > /dev/null 2>&1; then
        fetch_apt_policy_candidate "$pkg"
        return $?
    fi

    # dnf/yum metadata refresh can block for minutes; never hang shell startup.
    if command -v timeout > /dev/null 2>&1; then
        timeout_cmd=(timeout 5)
    fi

    if command -v dnf > /dev/null 2>&1; then
        raw=$("${timeout_cmd[@]}" dnf info "$pkg" 2> /dev/null | awk '/^Version/ { print $3; exit }')
        [[ -n "$raw" ]] || return 1
        printf '%s\n' "$raw"
        return 0
    fi

    if command -v yum > /dev/null 2>&1; then
        raw=$("${timeout_cmd[@]}" yum info "$pkg" 2> /dev/null | awk '/^Version/ { print $3; exit }')
        [[ -n "$raw" ]] || return 1
        printf '%s\n' "$raw"
        return 0
    fi

    return 1
}

function fetch_bash_latest_distro()
{
    fetch_distro_package_version bash
}

function fetch_bash_latest_upstream()
{
    local curl_cmd url ver

    [[ -n "${init_tool_python3:-}" && -x "$init_tool_python3" ]] || return 1

    curl_cmd="$init_tool_curl"
    [[ -n "$curl_cmd" && -x "$curl_cmd" ]] || return 1

    # Prefer mirrors; ftp.gnu.org is often slow or blocked on some Linux hosts.
    for url in \
        https://ftpmirror.gnu.org/gnu/bash/ \
        https://ftp.gnu.org/gnu/bash/
    do
        ver=$(
            "$curl_cmd" --silent --show-error --fail --location --max-time 12 \
                "$url" 2> /dev/null \
                | "$init_tool_python3" -c '
import re, sys
html = sys.stdin.read()
vers = re.findall(r"bash-(\d+\.\d+(?:\.\d+)?)\.tar\.gz", html)
def key(v):
    parts = [int(p) for p in v.split(".")]
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts)
print(max(vers, key=key) if vers else "")
' 2> /dev/null
        ) || ver=
        if [[ -n "$ver" ]]; then
            printf '%s\n' "$ver"
            return 0
        fi
    done
    return 1
}

function fetch_git_latest()
{
    fetch_git_latest_upstream
}

function fetch_git_latest_distro()
{
    fetch_distro_package_version git
}

function fetch_gh_latest_distro()
{
    fetch_distro_package_version gh
}

function fetch_git_latest_upstream()
{
    local curl_cmd tags_json

    [[ -n "${init_tool_python3:-}" && -x "$init_tool_python3" ]] || return 1

    curl_cmd="$init_tool_curl"
    [[ -n "$curl_cmd" && -x "$curl_cmd" ]] || return 1

    # git/git has no GitHub "latest release" (releases/latest -> 404); tags are authoritative.
    tags_json=$(
        "$curl_cmd" --silent --show-error --fail --location --max-time 10 \
            -H 'Accept: application/vnd.github+json' \
            -H 'User-Agent: init-files-tool-version-check' \
            'https://api.github.com/repos/git/git/tags?per_page=100' 2> /dev/null
    ) || return 1

    printf '%s' "$tags_json" | "$init_tool_python3" -c '
import json
import re
import sys

def parse_version(tag_name):
    name = (tag_name or "").lstrip("v")
    if re.search(r"(rc|beta|preview)", name, re.I):
        return None
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", name)
    if not match:
        return None
    return tuple(int(x) for x in match.groups())

try:
    tags = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    sys.exit(1)

best = None
for tag in tags:
    version = parse_version(tag.get("name", ""))
    if version and (best is None or version > best):
        best = version

if best is None:
    sys.exit(1)

print(".".join(str(x) for x in best))
'
}

function fetch_latest_tool_version()
{
    local curl_cmd tool_name

    tool_name="$1"

    [[ -n "${init_tool_python3:-}" && -x "$init_tool_python3" ]] || return

    curl_cmd="$init_tool_curl"
    [[ -n "$curl_cmd" && -x "$curl_cmd" ]] || return

    case "$tool_name" in
        git)
            fetch_git_latest_upstream
            ;;
        gh)
            "$curl_cmd" --silent --show-error --fail --location --max-time 5 https://api.github.com/repos/cli/cli/releases/latest 2> /dev/null \
                | "$init_tool_python3" -c 'import json, sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))' 2> /dev/null
            ;;
        gh-stack)
            "$curl_cmd" --silent --show-error --fail --location --max-time 5 https://api.github.com/repos/github/gh-stack/releases/latest 2> /dev/null \
                | "$init_tool_python3" -c 'import json, sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))' 2> /dev/null
            ;;
        gt)
            "$curl_cmd" --silent --show-error --fail --location --max-time 5 https://registry.npmjs.org/@withgraphite/graphite-cli/latest 2> /dev/null \
                | "$init_tool_python3" -c 'import json, sys; print(json.load(sys.stdin)["version"])' 2> /dev/null
            ;;
        npm|npx)
            "$curl_cmd" --silent --show-error --fail --location --max-time 5 https://registry.npmjs.org/npm/latest 2> /dev/null \
                | "$init_tool_python3" -c 'import json, sys; print(json.load(sys.stdin)["version"])' 2> /dev/null
            ;;
        pipx)
            "$curl_cmd" --silent --show-error --fail --location --max-time 5 https://pypi.org/pypi/pipx/json 2> /dev/null \
                | "$init_tool_python3" -c 'import json, sys; print(json.load(sys.stdin)["info"]["version"])' 2> /dev/null
            ;;
        pnpm)
            "$curl_cmd" --silent --show-error --fail --location --max-time 5 https://registry.npmjs.org/pnpm/latest 2> /dev/null \
                | "$init_tool_python3" -c 'import json, sys; print(json.load(sys.stdin)["version"])' 2> /dev/null
            ;;
        uv)
            fetch_uv_latest
            ;;
    esac
}

function fetch_uv_latest()
{
    local brew_ver github_ver strategy_name

    # Brew-managed uv on modern macOS: Homebrew formula is the reachable latest.
    # PyPI can ship ahead of the bottle; do not suggest a no-op `brew upgrade uv`.
    strategy_name="$(detect_uv_update_strategy 2> /dev/null | awk -F '\t' 'NR == 1 { print $1 }')"
    if [[ "$strategy_name" == "brew" ]]; then
        brew_ver="$(fetch_uv_latest_brew 2> /dev/null || true)"
        if [[ -n "$brew_ver" ]]; then
            printf '%s\n' "$brew_ver"
            return 0
        fi
        return 1
    fi

    # Standalone installs: `uv self update` pulls GitHub releases. PyPI can lead
    # briefly and make the suggested self-update look broken.
    if [[ "$strategy_name" == "self" ]]; then
        github_ver="$(fetch_uv_latest_github 2> /dev/null || true)"
        if [[ -n "$github_ver" ]]; then
            printf '%s\n' "$github_ver"
            return 0
        fi
    fi

    fetch_uv_latest_pypi
}

function fetch_uv_latest_brew()
{
    local brew_bin

    _init_is_darwin || return 1
    type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos || return 1
    command -v brew > /dev/null 2>&1 || return 1
    [[ -n "${init_tool_python3:-}" && -x "$init_tool_python3" ]] || return 1

    brew_bin=$(command -v brew)
    "$brew_bin" info --json=v2 uv 2> /dev/null \
        | "$init_tool_python3" -c 'import json,sys; d=json.load(sys.stdin); print(d["formulae"][0]["versions"]["stable"])' 2> /dev/null
}

function fetch_uv_latest_github()
{
    local curl_cmd

    [[ -n "${init_tool_python3:-}" && -x "$init_tool_python3" ]] || return 1

    curl_cmd="$init_tool_curl"
    [[ -n "$curl_cmd" && -x "$curl_cmd" ]] || return 1

    "$curl_cmd" --silent --show-error --fail --location --max-time 5 \
        https://api.github.com/repos/astral-sh/uv/releases/latest 2> /dev/null \
        | "$init_tool_python3" -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))' 2> /dev/null
}

function fetch_uv_latest_pypi()
{
    local curl_cmd

    [[ -n "${init_tool_python3:-}" && -x "$init_tool_python3" ]] || return 1

    curl_cmd="$init_tool_curl"
    [[ -n "$curl_cmd" && -x "$curl_cmd" ]] || return 1

    "$curl_cmd" --silent --show-error --fail --location --max-time 5 https://pypi.org/pypi/uv/json 2> /dev/null \
        | "$init_tool_python3" -c 'import json, sys; print(json.load(sys.stdin)["info"]["version"])' 2> /dev/null
}

# Interactive ripgrep → fzf (find-in-files). Optional bat/batcat preview.
# Usage: fif [initial-query]
# Enter opens the match in $EDITOR (or vim) at the line; Ctrl-C cancels.
function fif()
{
    local rg_bin fzf_bin bat_bin editor selection file line preview_cmd
    local -a rg_args

    rg_bin="${init_tool_rg:-}"
    [[ -n "$rg_bin" && -x "$rg_bin" ]] || rg_bin="$(command -v rg 2>/dev/null || true)"
    fzf_bin="${init_tool_fzf:-}"
    [[ -n "$fzf_bin" && -x "$fzf_bin" ]] || fzf_bin="$(command -v fzf 2>/dev/null || true)"

    if [[ -z "$rg_bin" || ! -x "$rg_bin" ]]; then
        printf 'fif: ripgrep (rg) not found\n' >&2
        if type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos; then
            printf '  install: brew install ripgrep && ./provision_init_files\n' >&2
        elif ! _init_is_darwin; then
            printf '  install: sudo apt install ripgrep   # or: sudo dnf install ripgrep\n' >&2
            printf '           then: ./provision_init_files\n' >&2
        fi
        return 1
    fi
    if [[ -z "$fzf_bin" || ! -x "$fzf_bin" ]]; then
        printf 'fif: fzf not found\n' >&2
        return 1
    fi

    preview_cmd='sed -n "1,200p" {1} 2>/dev/null || true'
    bat_bin="$(_init_fzf_tool_bin bat)"
    [[ -n "$bat_bin" ]] || bat_bin="$(_init_fzf_tool_bin batcat)"
    if [[ -n "$bat_bin" ]]; then
        preview_cmd="${bat_bin} --style=numbers --color=always --highlight-line {2} -- {1}"
    fi

    editor="${EDITOR:-}"
    if [[ -z "$editor" ]]; then
        if [[ -n "${init_tool_vim:-}" && -x "${init_tool_vim}" ]]; then
            editor="$init_tool_vim"
        else
            editor="$(command -v vim 2>/dev/null || command -v vi 2>/dev/null || true)"
        fi
    fi

    if (($# < 1)); then
        printf 'fif: usage: fif <query>\n' >&2
        return 2
    fi

    rg_args=(--column --line-number --no-heading --color=always --smart-case)
    selection="$(
        "$rg_bin" "${rg_args[@]}" -- "$*" 2>/dev/null \
            | "$fzf_bin" --ansi \
                --delimiter : \
                --preview "$preview_cmd" \
                --preview-window 'up,60%,border-bottom,+{2}+3/3,~3' \
                --prompt 'fif > '
    )" || true
    [[ -n "$selection" ]] || return 1

    file="${selection%%:*}"
    line="${selection#*:}"
    line="${line%%:*}"
    [[ -n "$file" ]] || return 1

    if [[ -n "$editor" ]]; then
        if [[ -n "$line" && "$line" != "$selection" ]]; then
            "$editor" "+${line}" -- "$file"
        else
            "$editor" -- "$file"
        fi
    else
        printf '%s\n' "$selection"
    fi
}

function fzf_install_hint()
{
    if _init_is_darwin && type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos; then
        printf 'brew install fzf'
        return 0
    fi
    if _init_is_darwin; then
        printf 'install fzf from GitHub releases into ~/.local (do not use Homebrew on this macOS)'
        return 0
    fi
    if command -v apt-get > /dev/null 2>&1 || command -v apt > /dev/null 2>&1; then
        printf 'sudo apt install fzf'
        return 0
    fi
    if command -v dnf > /dev/null 2>&1; then
        printf 'sudo dnf install fzf'
        return 0
    fi
    if command -v yum > /dev/null 2>&1; then
        printf 'sudo yum install fzf'
        return 0
    fi
    printf 'install fzf via your OS package manager or GitHub releases into ~/.local'
}

function fzf_tool_status_line()
{
    local fzf_bin fzf_current green red reset tone yellow

    green=
    red=
    yellow=
    reset=
    tone=
    if [[ -n "$tool_status_use_color" ]]; then
        green=$'\033[32m'
        red=$'\033[31m'
        yellow=$'\033[33m'
        reset=$'\033[0m'
    fi

    fzf_bin="${init_tool_fzf:-}"
    if [[ -z "$fzf_bin" || ! -x "$fzf_bin" ]]; then
        fzf_bin="$(command -v fzf 2>/dev/null || true)"
    fi
    # Common package locations if PATH is minimal during early checks.
    if [[ -z "$fzf_bin" || ! -x "$fzf_bin" ]]; then
        for fzf_bin in /usr/bin/fzf /usr/local/bin/fzf "$HOME/.local/bin/fzf"; do
            [[ -x "$fzf_bin" ]] && break
            fzf_bin=
        done
    fi

    if [[ -n "$fzf_bin" && -x "$fzf_bin" ]]; then
        fzf_current=$("$fzf_bin" --version 2> /dev/null | awk 'NR == 1 { print $1 }' || true)
        printf '%s  fzf: installed %s, status: available, path: %s%s' \
            "$green" "${fzf_current:-?}" "$fzf_bin" "$reset"
        return 0
    fi

    # Optional helper — yellow, not "installed - / not found on PATH".
    tone="$yellow"
    [[ -n "$tone" ]] || tone="$red"
    printf '%s  fzf: not installed%s' "$tone" "$reset"
    printf '\n%s    install: %s%s' "$tone" "$(fzf_install_hint)" "$reset"
}

function gbn()
{
    local sha

    branchName=$("$init_tool_git" rev-parse --abbrev-ref HEAD 2> /dev/null)
    export branchName
    if [ "$branchName" != "" ]; then
        export CSCOPE_DB=$HOME/.cscope/foo$branchName.cscope.out
        # Rocky 8.1: keep prompt light (no commit id / no tool-version checks)
        if _init_is_rocky_8_1; then
            echo "|$branchName "
            return
        fi
        sha=$("$init_tool_git" rev-parse --short HEAD 2> /dev/null)
        if [[ -n "$sha" ]]; then
            echo "|$branchName|$sha "
        else
            echo "|$branchName "
        fi
    fi
}

function gch()
{
    "$init_tool_git" checkout "$@"
    resetgr
}

function gd2()
{
    echo "branch ($1) has these commits and ($2) does not"
    "$init_tool_git" log "$2..$1" --no-merges --format='%h | Author:%an | Date:%ad | %s' --date=local
}

function gh_stack_current_version()
{
    local line version path

    # Prefer metadata that does not execute the extension (avoids network
    # update-notifier probes during interactive shell startup).
    if command -v gh > /dev/null 2>&1; then
        # Non-TTY list is tab-separated: NAME<TAB>REPO<TAB>VERSION
        # Be liberal: older/TTY/spaced variants and empty VERSION columns exist.
        version=$(
            gh extension list 2> /dev/null \
                | awk '
                    BEGIN { FS = "\t" }
                    {
                        line = $0
                        # Collapse to fields on tabs or runs of spaces.
                        n = split(line, a, /[\t]+|[[:space:]]{2,}/)
                        repo = ""
                        ver = ""
                        for (i = 1; i <= n; i++) {
                            if (a[i] ~ /(^|\/)gh-stack$/) {
                                repo = a[i]
                                if (i + 1 <= n) {
                                    ver = a[i + 1]
                                }
                                break
                            }
                        }
                        if (repo == "" && line ~ /gh-stack/) {
                            # Last resort: line mentions gh-stack; take last token as ver.
                            n = split(line, b, /[[:space:]]+/)
                            for (i = 1; i <= n; i++) {
                                if (b[i] ~ /gh-stack/) {
                                    repo = b[i]
                                    if (i < n) {
                                        ver = b[n]
                                    }
                                    break
                                }
                            }
                        }
                        if (repo != "") {
                            sub(/^v/, "", ver)
                            print ver
                            exit
                        }
                    }
                '
        )
        # Non-empty version from the list wins.
        if [[ -n "$version" ]]; then
            printf '%s' "$version"
            return 0
        fi
    fi

    # Manifest next to the binary (no gh exec / no network).
    path="$(gh_stack_extension_path 2> /dev/null || true)"
    if [[ -n "$path" ]]; then
        version="$(gh_stack_version_from_manifest "$path" 2> /dev/null || true)"
        if [[ -n "$version" ]]; then
            printf '%s' "$version"
            return 0
        fi
    fi

    # Last resort: run the extension with update checks disabled.
    if command -v gh > /dev/null 2>&1; then
        version=$(
            GH_NO_EXTENSION_UPDATE_NOTIFIER=1 gh stack --version 2> /dev/null \
                | awk '
                    NR == 1 {
                        if (match($0, /[0-9]+(\.[0-9]+)+/)) {
                            print substr($0, RSTART, RLENGTH)
                            exit
                        }
                    }
                '
        )
        if [[ -n "$version" ]]; then
            printf '%s' "$version"
            return 0
        fi
    fi

    # Binary present but version unknown — still "installed" for status.
    if [[ -n "$path" ]]; then
        printf 'present'
        return 0
    fi

    return 1
}

function gh_stack_version_from_manifest()
{
    local binary_path manifest version

    binary_path="$1"
    [[ -n "$binary_path" ]] || return 1
    manifest="$(dirname "$binary_path")/manifest.yml"
    [[ -r "$manifest" ]] || return 1

    version=$(
        awk '
            /^[[:space:]]*tag:[[:space:]]*/ {
                v = $2
                sub(/\r$/, "", v)
                sub(/^v/, "", v)
                print v
                exit
            }
        ' "$manifest"
    )
    [[ -n "$version" ]] || return 1
    printf '%s' "$version"
}

function gh_stack_extension_path()
{
    local candidate data_root

    data_root="${XDG_DATA_HOME:-$HOME/.local/share}"
    for candidate in \
        "$data_root/gh/extensions/gh-stack/gh-stack" \
        "$HOME/.local/share/gh/extensions/gh-stack/gh-stack" \
        "$HOME/.config/gh/extensions/gh-stack/gh-stack"
    do
        if [[ -x "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

function gh_stack_tool_status_line()
{
    local current_version green latest_version path red reset tone yellow

    path="${1:-}"
    current_version="$(normalize_version "$2")"
    # "present" is a sentinel from gh_stack_current_version when the binary
    # exists but no semver was found — do not treat as missing.
    if [[ -z "$current_version" && "$2" == "present" ]]; then
        current_version="present"
    fi
    latest_version="$(normalize_version "$3")"
    green=
    red=
    yellow=
    reset=
    tone=

    if [[ -n "$tool_status_use_color" ]]; then
        green=$'\033[32m'
        red=$'\033[31m'
        yellow=$'\033[33m'
        reset=$'\033[0m'
    fi

    if [[ -z "$current_version" && -z "$path" ]]; then
        # Optional gh extension — yellow, not "installed - / not found on PATH".
        tone="$yellow"
        [[ -n "$tone" ]] || tone="$red"
        if [[ -n "$latest_version" ]]; then
            printf '%s  gh-stack: not installed (latest %s)%s' "$tone" "$latest_version" "$reset"
        else
            printf '%s  gh-stack: not installed%s' "$tone" "$reset"
        fi
        printf '\n%s    install: %s%s' "$tone" "$(tool_install_command gh-stack)" "$reset"
        return 0
    fi

    if [[ -z "$current_version" ]]; then
        current_version="present"
    fi

    # Installed: reuse shared version compare; path is the extension binary.
    if [[ "$current_version" == "present" ]]; then
        # Bypass normalize_version empty path in tool_status_line.
        if [[ -n "$latest_version" ]]; then
            printf '%s  gh-stack: installed present, latest %s, status: version check unavailable, path: %s%s' \
                "$yellow" "$latest_version" "${path:-gh extension}" "$reset"
        else
            printf '%s  gh-stack: installed present, latest -, status: version check unavailable, path: %s%s' \
                "$yellow" "${path:-gh extension}" "$reset"
        fi
        return 0
    fi

    tool_status_line gh-stack "${path:-gh extension}" "$current_version" "$latest_version"
}

function git_package_manager_command()
{
    local package_name strategy

    strategy="$(detect_git_update_strategy "$1" 2> /dev/null || true)"
    [[ -n "$strategy" ]] || return 1
    package_name="${strategy#*$'\t'}"

    case "${strategy%%$'\t'*}" in
        brew)
            printf 'brew upgrade %s' "$package_name"
            ;;
        dnf)
            printf 'sudo dnf upgrade %s' "$package_name"
            ;;
        yum)
            printf 'sudo yum update %s' "$package_name"
            ;;
        apt)
            printf 'sudo apt update && sudo apt install --only-upgrade %s' "$package_name"
            ;;
        *)
            return 1
            ;;
    esac
}

function git_package_name()
{
    local git_path

    git_path="${1:-$init_tool_git}"
    [[ -n "$git_path" ]] || return 1

    if command -v rpm > /dev/null 2>&1; then
        rpm -qf "$git_path" 2> /dev/null | head -n 1
        return 0
    fi

    if command -v dpkg-query > /dev/null 2>&1; then
        dpkg-query --search "$git_path" 2> /dev/null | awk -F': ' 'NR == 1 { print $1; exit }'
        return 0
    fi

    return 1
}

function git_suggested_command()
{
    local git_path upgrade_command

    # Used for package-manager upgrades (Homebrew on macOS, apt/dnf when newer).
    # upstream-only / blocked paths must not call this — they have no auto fix.
    # On Linux without sudo, print the admin copy-paste instead of update_git.
    git_path="${1:-${init_tool_git:-}}"
    if ! _init_is_darwin && ! _init_linux_can_sudo_upgrade; then
        upgrade_command="$(git_package_manager_command "$git_path" 2> /dev/null || true)"
        if [[ -n "$upgrade_command" && "$upgrade_command" == sudo\ * ]]; then
            printf 'ask an admin: %s' "$upgrade_command"
            return 0
        fi
    fi
    printf 'update_git'
}

function git_install_source_label()
{
    local git_path version_line

    git_path="${1:-$init_tool_git}"
    version_line=$("$git_path" --version 2> /dev/null || true)

    if _init_is_darwin; then
        if [[ "$git_path" == /usr/bin/git ]] || [[ "$version_line" == *"Apple Git"* ]]; then
            printf 'Apple Git (Xcode Command Line Tools)'
            return 0
        fi
        if type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos; then
            printf 'macOS (not Homebrew-managed git)'
            return 0
        fi
        printf 'macOS (system/Xcode path; Homebrew not used on this OS tier)'
        return 0
    fi

    if git_package_name "$git_path" > /dev/null 2>&1; then
        printf 'distro package'
        return 0
    fi

    printf 'not managed by rpm/apt/dpkg'
    return 0
}

function git_tool_status_line()
{
    local current_version distro_latest git_path kind latest_label latest_version upgrade_tier

    git_path="$1"
    current_version="$(normalize_version "$2")"
    latest_version="$(normalize_version "$3")"
    kind="$(git_upgrade_kind "$current_version" "$latest_version" "$git_path" 2> /dev/null || true)"
    distro_latest="$(normalize_version "$(fetch_git_latest_distro 2> /dev/null || true)")"

    if [[ -n "$latest_version" ]]; then
        latest_label="$latest_version"
    else
        latest_label=""
    fi

    case "$kind" in
        package-manager)
            tool_status_line git "$git_path" "$2" "$latest_label" auto
            ;;
        upstream-only)
            tool_status_line git "$git_path" "$2" "$latest_label" blocked
            if [[ -n "$distro_latest" ]]; then
                printf '\n    note: distro repos offer %s (already current there)' "$distro_latest"
            fi
            if _init_is_darwin; then
                printf '\n    note: %s' "$(git_install_source_label "$git_path")"
            fi
            # Guidance only — not an install/upgrade command.
            printf '\n    next step: update_git_upstream'
            ;;
        up-to-date)
            tool_status_line git "$git_path" "$2" "$2" auto
            ;;
        *)
            tool_status_line git "$git_path" "$2" "$latest_label"
            ;;
    esac
}

function git_upgrade_kind()
{
    local current_version distro_latest git_path strategy_name upstream_latest

    current_version="$(normalize_version "$1")"
    upstream_latest="$(normalize_version "$2")"
    git_path="${3:-}"

    [[ -n "$current_version" ]] || return 1

    if [[ -z "$upstream_latest" ]]; then
        printf 'unknown'
        return 0
    fi

    if versions_equal "$current_version" "$upstream_latest" \
        || ! version_lt "$current_version" "$upstream_latest"; then
        printf 'up-to-date'
        return 0
    fi

    strategy_name="$(detect_git_update_strategy "$git_path" 2> /dev/null | awk -F '\t' 'NR == 1 { print $1 }')"
    distro_latest="$(normalize_version "$(fetch_git_latest_distro 2> /dev/null || true)")"

    case "$strategy_name" in
        brew)
            printf 'package-manager'
            return 0
            ;;
        dnf|yum|apt)
            if [[ -n "$distro_latest" ]] && version_lt "$current_version" "$distro_latest"; then
                printf 'package-manager'
                return 0
            fi
            printf 'upstream-only'
            return 0
            ;;
        *)
            printf 'upstream-only'
            return 0
            ;;
    esac
}

function gitin()
{
    "$init_tool_git" fetch origin master
    gd2 FETCH_HEAD "$(parse_git_branch)"
}

function gitout()
{
    "$init_tool_git" fetch origin master
    gd2 "$(parse_git_branch)" FETCH_HEAD
}

# Always prompt; never reuse a cached symmetric passphrase across files.
function gpg_symmetric()
{
    "$init_tool_gpg" --pinentry-mode ask --no-symkey-cache "$@"
}

# After background rotate rewrites archives smaller, refresh EOF offsets so
# history_append_since does not bail forever on current_size > offset.
# Also seeds bash_history_last_rotate_seen from last-rotate.
function _init_history_maybe_refresh_rotate_offsets()
{
    local stamp seen

    stamp="${bash_history_dir:-${XDG_STATE_HOME:-$HOME/.local/state}/bash}/last-rotate"
    [[ -f "$stamp" ]] || return 0
    seen=$(cat "$stamp" 2>/dev/null || true)
    [[ -n "$seen" ]] || return 0
    [[ "$seen" == "${bash_history_last_rotate_seen:-}" ]] && return 0

    if [[ -n "${bash_history_archive:-}" && -r "$bash_history_archive" ]]; then
        bash_history_archive_bytes=$(wc -c < "$bash_history_archive") || bash_history_archive_bytes=0
    else
        bash_history_archive_bytes=0
    fi
    if [[ -n "${bash_history_legacy_file:-}" && -r "$bash_history_legacy_file" ]]; then
        bash_history_legacy_bytes=$(wc -c < "$bash_history_legacy_file") || bash_history_legacy_bytes=0
    else
        bash_history_legacy_bytes=0
    fi
    bash_history_last_rotate_seen="$seen"
}

function history_append_since()
{
    local target="$1"
    local offset="${2:-0}"
    local current_size

    bash_history_append_result="$offset"

    # Require a live *session* HISTFILE. Never tail ~/.bash_history or history.all
    # onto themselves/each other (that hung shells and grew files to tens of GB).
    [[ -n "$target" && -n "$HISTFILE" && -r "$HISTFILE" ]] || return
    if [[ "$HISTFILE" -ef "$target" ]] 2>/dev/null \
        || [[ "$HISTFILE" == "$target" ]] \
        || [[ -n "${bash_history_archive:-}" && ( "$HISTFILE" -ef "$bash_history_archive" || "$HISTFILE" == "$bash_history_archive" ) ]] \
        || [[ -n "${bash_history_legacy_file:-}" && ( "$HISTFILE" -ef "$bash_history_legacy_file" || "$HISTFILE" == "$bash_history_legacy_file" ) ]] \
        || [[ -n "${bash_history_dir:-}" && "$HISTFILE" != "$bash_history_dir"/history.* ]]
    then
        return 1
    fi

    # Skip archive/legacy appends while rotate holds the lock (rewrite via mv).
    if [[ -n "${bash_history_dir:-}" && -d "${bash_history_dir}/rotate.lock" ]]; then
        return 0
    fi

    current_size=$(wc -c < "$HISTFILE") || return
    (( current_size > offset )) || return
    # Session files should stay small; refuse runaway copies.
    if (( current_size > 10 * 1024 * 1024 )); then
        printf 'init-files: refusing history append from oversized HISTFILE (%s bytes): %s\n' \
            "$current_size" "$HISTFILE" >&2
        return 1
    fi

    mkdir -p "$(dirname -- "$target")" 2>/dev/null || true
    # Prefer system tail; avoid long copies if anything slips past the guards.
    command tail -c +"$((offset + 1))" "$HISTFILE" >> "$target" || return
    bash_history_append_result="$current_size"
}

function history_bootstrap()
{
    [[ -n "$bash_history_bootstrapped" ]] && return
    bash_history_bootstrapped=1

    if [[ -r "$bash_history_legacy_file" ]]; then
        builtin history -r "$bash_history_legacy_file"
    fi

    if [[ -r "$bash_history_archive" ]]; then
        builtin history -r "$bash_history_archive"
    fi

    # New bytes only: offsets start at EOF so we never re-copy existing archives
    # into themselves via a mis-set HISTFILE.
    if [[ -r "$bash_history_archive" ]]; then
        bash_history_archive_bytes=$(wc -c < "$bash_history_archive") || bash_history_archive_bytes=0
    fi
    if [[ -r "$bash_history_legacy_file" ]]; then
        bash_history_legacy_bytes=$(wc -c < "$bash_history_legacy_file") || bash_history_legacy_bytes=0
    fi
    # Align with current last-rotate so the first history_sync does not treat an
    # existing stamp as a just-completed rewrite.
    if [[ -f "${bash_history_dir}/last-rotate" ]]; then
        bash_history_last_rotate_seen=$(cat "${bash_history_dir}/last-rotate" 2>/dev/null || true)
    fi
}

function history_finalize()
{
    history_sync
    _init_history_maybe_refresh_rotate_offsets
    history_append_since "$bash_history_legacy_file" "$bash_history_legacy_bytes"
    bash_history_legacy_bytes="$bash_history_append_result"
    # Quiet daily rotate if due — never block EXIT on rewrite.
    if declare -F _init_maybe_schedule_history_rotate > /dev/null 2>&1; then
        _init_maybe_schedule_history_rotate
    fi
}

function history_sync()
{
    builtin history -a
    _init_history_maybe_refresh_rotate_offsets
    history_append_since "$bash_history_archive" "$bash_history_archive_bytes"
    bash_history_archive_bytes="$bash_history_append_result"
}

# Manual or background: dedupe/cap history.all + ~/.bash_history; prune session files.
# -q: no TTY progress; failures append to rotate.log. Never call from history_sync.
function rotate_bash_history()
{
    local quiet=0 hist_dir archive legacy lock_dir stamp log_file rc=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -q|--quiet) quiet=1; shift ;;
            -h|--help)
                cat <<'EOF' >&2
Usage: rotate_bash_history [-q|--quiet]

Dedupe and cap history.all (and ~/.bash_history) to the last ~50k unique
commands / 8 MiB; prune old session HISTFILEs. Safe to run while shells are
open (sync skips appends under rotate.lock, then refreshes EOF offsets from
last-rotate). New tabs see the shrunk archive after source ~/.bashrc or a
new shell.
EOF
                return 0
                ;;
            *)
                echo "rotate_bash_history: unknown option: $1" >&2
                return 1
                ;;
        esac
    done

    hist_dir="${bash_history_dir:-${XDG_STATE_HOME:-$HOME/.local/state}/bash}"
    archive="${bash_history_archive:-$hist_dir/history.all}"
    legacy="${bash_history_legacy_file:-$HOME/.bash_history}"
    lock_dir="${hist_dir}/rotate.lock"
    stamp="${hist_dir}/last-rotate"
    log_file="${hist_dir}/rotate.log"
    mkdir -p "$hist_dir" 2>/dev/null || true

    if ! declare -F init_files_mkdir_lock > /dev/null 2>&1 \
        || ! declare -F init_files_history_rewrite_bounded > /dev/null 2>&1; then
        [[ $quiet -eq 1 ]] || echo "rotate_bash_history: helpers missing (refresh_init_files)" >&2
        return 1
    fi

    if ! init_files_mkdir_lock "$lock_dir" 900; then
        [[ $quiet -eq 1 ]] || echo "rotate_bash_history: lock busy; try later" >&2
        return 1
    fi

    [[ $quiet -eq 1 ]] || echo "rotate_bash_history: rewriting archives…" >&2

    _rotate_one()
    {
        local src="$1"
        local label="$2"
        local out

        [[ -f "$src" ]] || return 0
        out="${src}.rotating.tmp.$$"
        if ! init_files_history_rewrite_bounded "$src" "$out"; then
            rm -f "$out" 2>/dev/null || true
            printf '%s: rewrite failed for %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" "$label" >> "$log_file" 2>/dev/null || true
            return 1
        fi
        if ! mv -f "$out" "$src"; then
            rm -f "$out" 2>/dev/null || true
            printf '%s: replace failed for %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" "$label" >> "$log_file" 2>/dev/null || true
            return 1
        fi
        return 0
    }

    _rotate_one "$archive" "history.all" || rc=1
    if [[ -f "$legacy" ]]; then
        _rotate_one "$legacy" "bash_history" || rc=1
    fi

    if declare -F init_files_history_prune_sessions > /dev/null 2>&1; then
        init_files_history_prune_sessions "$hist_dir" || true
    fi

    # Cap rotate.log (~64 KiB).
    if [[ -f "$log_file" ]]; then
        local log_size
        log_size=$(wc -c < "$log_file" 2>/dev/null || echo 0)
        if [[ "$log_size" =~ ^[0-9]+$ ]] && (( log_size > 65536 )); then
            command tail -c 32768 "$log_file" > "${log_file}.tmp" 2>/dev/null \
                && mv -f "${log_file}.tmp" "$log_file" 2>/dev/null \
                || rm -f "${log_file}.tmp" 2>/dev/null || true
        fi
    fi

    if [[ $rc -eq 0 ]]; then
        date +%s > "$stamp" 2>/dev/null || true
        [[ $quiet -eq 1 ]] || echo "rotate_bash_history: done" >&2
    else
        [[ $quiet -eq 1 ]] || echo "rotate_bash_history: completed with errors (see $log_file)" >&2
    fi

    init_files_mkdir_unlock "$lock_dir"
    unset -f _rotate_one 2>/dev/null || true
    return "$rc"
}

# After interactive init (or EXIT): if daily stamp due and archive soft-oversize,
# start a background quiet rotate. Never blocks; never runs on history_sync.
function _init_maybe_schedule_history_rotate()
{
    local hist_dir archive legacy stamp now age lock_dir log_file

    [[ $- == *i* ]] || return 0
    declare -F rotate_bash_history > /dev/null 2>&1 || return 0
    declare -F init_files_history_soft_oversize > /dev/null 2>&1 || return 0

    hist_dir="${bash_history_dir:-${XDG_STATE_HOME:-$HOME/.local/state}/bash}"
    archive="${bash_history_archive:-$hist_dir/history.all}"
    legacy="${bash_history_legacy_file:-$HOME/.bash_history}"
    stamp="${hist_dir}/last-rotate"
    lock_dir="${hist_dir}/rotate.lock"
    log_file="${hist_dir}/rotate.log"
    mkdir -p "$hist_dir" 2>/dev/null || true

    now=$(date +%s 2>/dev/null || echo 0)
    [[ "$now" =~ ^[0-9]+$ ]] || return 0
    if [[ -f "$stamp" ]]; then
        age=$(tr -d '[:space:]' < "$stamp" 2>/dev/null || echo 0)
        if [[ "$age" =~ ^[0-9]+$ ]] && (( now >= age && (now - age) < 86400 )); then
            return 0
        fi
    fi

    # Soft threshold on archive or legacy.
    if ! init_files_history_soft_oversize "$archive" \
        && ! init_files_history_soft_oversize "$legacy"; then
        # Still advance stamp so we do not re-check every shell when small.
        date +%s > "$stamp" 2>/dev/null || true
        return 0
    fi

    # Skip if lock already held (rotate in progress).
    if [[ -d "$lock_dir" ]]; then
        return 0
    fi

    (
        rotate_bash_history -q >>"$log_file" 2>&1
    ) &
    disown 2>/dev/null || true
}

function host_tag()
{
    local host_tag

    # Explicit override for unusual layouts (rare).
    if [[ -n "${tool_host_tag:-}" ]]; then
        host_tag="${tool_host_tag}"
        host_tag="${host_tag//[^[:alnum:]._-]/-}"
    elif [[ -n "${init_files_host:-}" ]]; then
        # Same key as tools.* / prefs / PS1 (macOS ComputerName, Linux short name).
        host_tag="${init_files_host}"
    else
        host_tag="$(_init_files_sanitize_host "$(_init_files_raw_host_label)")"
    fi

    [[ -n "$host_tag" ]] || host_tag='unknown-host'
    printf '%s' "$host_tag"
}

# List (or --apply remove) NFS leftover prefs / pipx trees not for this host.
# Keeps current init_files_host plus hosts listed in ~/.config/init-files/nfs-hosts
# (one hostname per line) or passed via --keep HOST.
function init_files_cleanup_orphans()
{
    local apply=0 cfg_dir pipx_root entry base host
    local -a keep_hosts=() orphans=()
    local nfs_hosts_file

    cfg_dir="${init_files_config_dir:-${XDG_CONFIG_HOME:-$HOME/.config}/init-files}"
    pipx_root="${HOME}/.local/opt/pipx"
    nfs_hosts_file="${cfg_dir}/nfs-hosts"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --apply) apply=1; shift ;;
            --keep)
                [[ -n "${2:-}" ]] || { printf 'init_files_cleanup_orphans: --keep needs HOST\n' >&2; return 1; }
                keep_hosts+=("$2")
                shift 2
                ;;
            -h|--help)
                cat <<'EOF'
Usage: init_files_cleanup_orphans [--apply] [--keep HOST]...

List preference files and pipx trees whose host key is not the current
init_files_host (and not listed in ~/.config/init-files/nfs-hosts or --keep).

  --apply   remove listed orphans (prefs files and entire pipx/<host> dirs)
  --keep H  treat H as a live host (repeatable)

Does nothing destructive without --apply.
EOF
                return 0
                ;;
            *)
                printf 'init_files_cleanup_orphans: unknown option: %s\n' "$1" >&2
                return 1
                ;;
        esac
    done

    keep_hosts+=("${init_files_host:-}")
    if [[ -r "$nfs_hosts_file" ]]; then
        while IFS= read -r host || [[ -n "$host" ]]; do
            [[ -n "$host" && "$host" != \#* ]] || continue
            keep_hosts+=("$host")
        done < "$nfs_hosts_file"
    fi

    _init_files_orphan_is_kept()
    {
        local candidate="$1" k
        for k in "${keep_hosts[@]}"; do
            [[ -n "$k" && "$candidate" == "$k" ]] && return 0
        done
        return 1
    }

    for prefix in no-dev github-https github-ssh fancy-prompt tools; do
        for entry in "$cfg_dir"/"${prefix}".*; do
            [[ -e "$entry" ]] || continue
            base="${entry##*/}"
            host="${base#"${prefix}."}"
            [[ -n "$host" && "$host" != "$base" ]] || continue
            _init_files_orphan_is_kept "$host" && continue
            orphans+=("$entry")
        done
    done

    # Legacy unscoped tools (still loaded as fallback, but orphan-ish on NFS).
    if [[ -f "$cfg_dir/tools" && -n "${init_files_host:-}" && -f "$cfg_dir/tools.${init_files_host}" ]]; then
        orphans+=("$cfg_dir/tools")
    fi

    if [[ -d "$pipx_root" ]]; then
        for entry in "$pipx_root"/*; do
            [[ -d "$entry" ]] || continue
            host="$(basename "$entry")"
            _init_files_orphan_is_kept "$host" && continue
            orphans+=("$entry")
        done
    fi

    if [[ ${#orphans[@]} -eq 0 ]]; then
        printf 'init_files_cleanup_orphans: no orphans (kept: %s)\n' "${keep_hosts[*]}"
        return 0
    fi

    printf 'Orphans (not in keep set: %s):\n' "${keep_hosts[*]}"
    for entry in "${orphans[@]}"; do
        printf '  %s\n' "$entry"
    done

    if [[ $apply -eq 0 ]]; then
        printf 'Dry run only. Re-run with --apply to remove.\n'
        return 0
    fi

    for entry in "${orphans[@]}"; do
        if [[ -d "$entry" ]]; then
            rm -rf "$entry" && printf 'Removed dir  %s\n' "$entry"
        else
            rm -f "$entry" && printf 'Removed file %s\n' "$entry"
        fi
    done
}

# Deploy sanity check (read-only unless noted). See GitHub issue #15.
function init_files_doctor()
{
    local fail=0 warn=0
    local link_target head_sha remote_sha tools_file preferred_key
    local clone_dir="${init_files_dir:-${XDG_DATA_HOME:-$HOME/.local/share}/init-files}"
    local cfg="${init_files_config_dir:-${XDG_CONFIG_HOME:-$HOME/.config}/init-files}"
    local git_bin="${init_tool_git:-$(command -v git 2>/dev/null || true)}"
    local wrapper

    _doc_ok() { printf 'OK    %s\n' "$*"; }
    _doc_warn() { printf 'WARN  %s\n' "$*"; warn=$((warn + 1)); }
    _doc_fail() { printf 'FAIL  %s\n' "$*"; fail=$((fail + 1)); }

    printf '=== init_files_doctor (%s) user=%s ===\n' "${init_files_host:-?}" "${USER:-?}"

    # 1) bashrc symlink
    if [[ -L "${HOME}/.bashrc" ]]; then
        link_target=$(readlink "${HOME}/.bashrc" 2>/dev/null || true)
        if [[ "$link_target" == "${clone_dir}/bashrc" ]]; then
            _doc_ok "bashrc -> $link_target"
        else
            _doc_fail "bashrc symlink is $link_target (expected ${clone_dir}/bashrc); run: ./provision_init_files or refresh_init_files"
        fi
    else
        _doc_fail "$HOME/.bashrc is not a symlink; run: ${clone_dir}/provision_init_files"
    fi

    # 2) clone HEAD (offline-friendly; no fetch)
    if [[ -d "$clone_dir/.git" && -n "$git_bin" && -x "$git_bin" ]]; then
        head_sha=$("$git_bin" -C "$clone_dir" rev-parse --short HEAD 2>/dev/null || echo '?')
        remote_sha=$("$git_bin" -C "$clone_dir" rev-parse --short origin/main 2>/dev/null || true)
        if [[ -n "$remote_sha" && "$head_sha" != "$remote_sha" && "$head_sha" != '?' ]]; then
            _doc_warn "clone HEAD $head_sha != origin/main $remote_sha (cached); run: refresh_init_files"
        else
            _doc_ok "clone HEAD $head_sha${remote_sha:+ (origin/main $remote_sha)}"
        fi
    else
        _doc_fail "missing clone at $clone_dir"
    fi

    # 3) private config overlay (shared SSH)
    if declare -F init_files_private_config_complete > /dev/null 2>&1; then
        if init_files_private_config_complete; then
            _doc_ok "private config overlay ready ($(init_files_private_config_dir))"
            if declare -F init_files_private_config_url_drifted > /dev/null 2>&1 \
                && init_files_private_config_url_drifted; then
                _doc_warn "private config remembered URL != clone origin; fix remote or config-repo pref"
            fi
            if declare -F init_files_private_config_behind_cached > /dev/null 2>&1 \
                && init_files_private_config_behind_cached; then
                _doc_warn "private config HEAD behind origin/main (cached); run: git -C $(init_files_private_config_dir) pull --ff-only && provision_init_files"
            fi
        elif declare -F init_files_private_config_present > /dev/null 2>&1 \
            && init_files_private_config_present; then
            _doc_warn "private config incomplete ($(init_files_private_config_dir)); run provision_init_files (interactive) to fix"
        else
            _doc_warn "private config missing ($(init_files_private_config_dir)); set INIT_FILES_CONFIG_REPO or run provision interactively"
        fi
    elif declare -F init_files_private_config_present > /dev/null 2>&1; then
        _doc_warn "private config helpers outdated; run refresh_init_files"
    else
        _doc_warn "private config helpers missing (lib/config_paths); run refresh_init_files"
    fi

    # 4) preferred / GitHub keys + agent (paths from overlay when available)
    preferred_key=
    if declare -F init_files_github_identity_files_from_template > /dev/null 2>&1; then
        if declare -F init_files_config_ssh_github_config_path > /dev/null 2>&1; then
            preferred_key="$(init_files_github_identity_files_from_template "$(init_files_config_ssh_github_config_path 2>/dev/null || true)" | head -1 || true)"
        elif declare -F init_files_config_ssh_dir > /dev/null 2>&1; then
            preferred_key="$(init_files_github_identity_files_from_template "$(init_files_config_ssh_dir)/config.github" | head -1 || true)"
        fi
    fi
    if [[ -n "$preferred_key" && -f "$preferred_key" ]]; then
        _doc_ok "preferred SSH key present (${preferred_key/#$HOME/~})"
    elif [[ -n "$preferred_key" ]]; then
        _doc_warn "preferred SSH key missing ($preferred_key)"
    else
        _doc_warn "no overlay config.github IdentityFiles on disk (optional for HTTPS-only hosts)"
    fi
    if type cache_ssh > /dev/null 2>&1; then
        if cache_ssh -c 2>/dev/null; then
            _doc_ok "cache_ssh: key cached in agent"
        else
            _doc_warn "cache_ssh: key not in agent (run: cache_ssh)"
        fi
    fi

    # 5) GitHub transport
    if [[ -f "${init_files_github_https_flag:-$cfg/github-https.${init_files_host}}" ]]; then
        _doc_ok "GitHub transport: HTTPS flag (${init_files_host})"
    elif [[ -f "${init_files_github_ssh_flag:-$cfg/github-ssh.${init_files_host}}" ]]; then
        _doc_ok "GitHub transport: SSH flag (${init_files_host})"
    else
        if [[ -n "$git_bin" ]] && [[ "$("$git_bin" config --global --get 'url.git@github.com:.insteadof' 2>/dev/null || true)" == "https://github.com/" ]]; then
            _doc_ok "GitHub transport: insteadOf SSH (no per-host flag)"
        else
            _doc_warn "GitHub transport: no insteadOf and no github-https flag"
        fi
    fi

    # 6) tools file + recorded paths
    tools_file="${init_files_tools_file:-$cfg/tools.${init_files_host}}"
    if [[ -f "$tools_file" ]]; then
        _doc_ok "tools file $tools_file"
        if type _init_files_tools_reinstall_reasons > /dev/null 2>&1; then
            local tools_reasons
            tools_reasons="$(_init_files_tools_reinstall_reasons 2>/dev/null || true)"
            if [[ -n "$tools_reasons" ]]; then
                _doc_warn "tools need reinstall — run: ${clone_dir}/provision_init_files"
                while IFS= read -r line || [[ -n "$line" ]]; do
                    [[ -n "$line" ]] && _doc_warn "  $line"
                done <<< "$tools_reasons"
            fi
        fi
    else
        _doc_fail "missing $tools_file; run: ${clone_dir}/provision_init_files"
    fi

    # 6) pipx wrapper
    if type rewrite_stale_pipx_wrappers > /dev/null 2>&1; then
        migrate_pipx_host_layout quiet 2>/dev/null || true
    fi
    wrapper=
    if type pipx_host_dir > /dev/null 2>&1; then
        wrapper="$(pipx_host_dir 2>/dev/null)/current/bin/pipx"
    fi
    if [[ -n "$wrapper" && -f "$wrapper" ]]; then
        if grep -qE '\$\{?init_tool_python3\}?' "$wrapper" 2>/dev/null; then
            _doc_fail "stale pipx wrapper (unbound init_tool_python3): $wrapper — run: rewrite_stale_pipx_wrappers or update_pipx"
        else
            _doc_ok "pipx wrapper $wrapper"
        fi
    else
        _doc_warn "no host pipx under ~/.local/opt/pipx/$(host_tag 2>/dev/null || echo '?') (optional)"
    fi

    # 7) OS tier
    if type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos; then
        _doc_ok "OS tier: modern macOS (Homebrew OK)"
    elif type _init_is_darwin > /dev/null 2>&1 && _init_is_darwin; then
        _doc_ok "OS tier: older macOS (no brew recommendations)"
    elif type _init_is_rocky_8_1 > /dev/null 2>&1 && _init_is_rocky_8_1; then
        _doc_ok "OS tier: Rocky 8.1 (tool-version checks skipped)"
    else
        _doc_ok "OS tier: Linux (non-Rocky-8.1 or unknown)"
    fi

    # 8) vimrc / gvimrc
    if [[ -f "${clone_dir}/vim/vimrc" ]]; then
        if [[ -L "${HOME}/.vimrc" ]]; then
            link_target=$(readlink "${HOME}/.vimrc" 2>/dev/null || true)
            if [[ "$link_target" == "${clone_dir}/vim/vimrc" ]]; then
                _doc_ok "vimrc -> $link_target"
            else
                _doc_warn "vimrc symlink is $link_target (expected ${clone_dir}/vim/vimrc); run: refresh_vimrc"
            fi
        else
            _doc_warn "$HOME/.vimrc not a symlink to clone; run: refresh_vimrc"
        fi
        if [[ -e "${HOME}/.gvimrc" || -L "${HOME}/.gvimrc" ]]; then
            _doc_warn "$HOME/.gvimrc present (should be retired); run: refresh_vimrc"
        fi
    fi

    # 9) login-shell bashrc hook
    if type _init_files_login_hook_ok > /dev/null 2>&1; then
        if _init_files_login_hook_ok; then
            _doc_ok "login shell sources ~/.bashrc (init-files hook)"
        else
            _doc_warn "login profile missing init-files bashrc hook; run: ${clone_dir}/provision_init_files"
        fi
    fi

    # 10) curated iTerm prefs (Darwin)
    if type _init_is_darwin > /dev/null 2>&1 && _init_is_darwin \
        && type _init_files_iterm_curated_drift > /dev/null 2>&1; then
        if [[ -f "${clone_dir}/iterm2/com.googlecode.iterm2.plist" ]]; then
            _init_files_iterm_curated_drift
            case $? in
                0) _doc_warn "iTerm curated prefs differ from clone; run: refresh_iterm_settings" ;;
                1) _doc_ok "iTerm curated prefs match clone" ;;
            esac
        fi
    fi

    if type _init_files_is_no_dev_host > /dev/null 2>&1 && _init_files_is_no_dev_host; then
        _doc_ok "mode: --no-dev (toolchain checks softened)"
    fi

    printf '%s\n' "--- summary: ${fail} fail, ${warn} warn ---"
    if [[ $fail -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Install Starship to ~/.local/bin (Linux / older macOS). Creates the bin dir first.
# On modern macOS, prompt_fancy / callers should prefer brew; this still works as fallback.
function install_starship()
{
    local bin_dir="${HOME}/.local/bin"
    local curl_bin

    if _init_is_darwin && type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos; then
        if command -v brew > /dev/null 2>&1; then
            printf 'install_starship: on modern macOS prefer: brew install starship\n' >&2
            return 1
        fi
    fi

    mkdir -p "$bin_dir" || {
        printf 'install_starship: cannot create %s\n' "$bin_dir" >&2
        return 1
    }

    curl_bin="${init_tool_curl:-}"
    [[ -n "$curl_bin" && -x "$curl_bin" ]] || curl_bin="$(command -v curl 2>/dev/null || true)"
    [[ -n "$curl_bin" && -x "$curl_bin" ]] || {
        printf 'install_starship: curl not found\n' >&2
        return 1
    }

    "$curl_bin" -sS https://starship.rs/install.sh | sh -s -- -b "$bin_dir" -y || return 1

    if [[ -x "${bin_dir}/starship" ]]; then
        printf 'install_starship: installed %s\n' "${bin_dir}/starship"
        hash -r 2>/dev/null || true
        return 0
    fi
    printf 'install_starship: install finished but %s/starship missing\n' "$bin_dir" >&2
    return 1
}

# Y/n for interactive helpers (default yes). No prompt when non-TTY → no.
function _init_prompt_yn()
{
    local prompt="$1"
    local reply

    if [[ ! -t 0 || ! -t 2 ]]; then
        return 1
    fi
    printf '%s ' "$prompt" >&2
    read -r reply || reply=n
    case "$reply" in
        ''|y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

# Install starship using the path appropriate for this OS/host.
# Returns 0 when starship is on PATH afterward.
function _init_offer_install_starship()
{
    local brew_bin

    if _init_is_darwin && type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos; then
        brew_bin="$(command -v brew 2>/dev/null || true)"
        if [[ -z "$brew_bin" || ! -x "$brew_bin" ]]; then
            printf 'prompt_fancy: Homebrew is required for starship on modern macOS\n' >&2
            printf '  install Homebrew, then: brew install starship\n' >&2
            return 1
        fi
        printf 'prompt_fancy: installing starship via Homebrew…\n' >&2
        "$brew_bin" install starship || return 1
        hash -r 2>/dev/null || true
        return 0
    fi

    if ! _init_is_darwin && command -v apt-get > /dev/null 2>&1; then
        if apt-cache show starship > /dev/null 2>&1; then
            printf 'prompt_fancy: installing starship via apt…\n' >&2
            sudo apt-get update && sudo apt-get install -y starship || return 1
            hash -r 2>/dev/null || true
            return 0
        fi
    fi

    if ! _init_is_darwin && command -v dnf > /dev/null 2>&1; then
        if dnf info starship > /dev/null 2>&1; then
            printf 'prompt_fancy: installing starship via dnf…\n' >&2
            sudo dnf install -y starship || return 1
            hash -r 2>/dev/null || true
            return 0
        fi
    fi

    printf 'prompt_fancy: installing starship to ~/.local/bin (upstream install.sh)…\n' >&2
    install_starship
}

# Prefer lsd, else recorded/PATH ls. Prints absolute-or-PATH binary or nothing.
function _init_list_bin()
{
    local bin

    bin="${init_tool_lsd:-}"
    if [[ -n "$bin" && -x "$bin" ]]; then
        printf '%s' "$bin"
        return 0
    fi
    bin="$(command -v lsd 2>/dev/null || true)"
    if [[ -n "$bin" && -x "$bin" ]]; then
        printf '%s' "$bin"
        return 0
    fi
    bin="${init_tool_ls:-}"
    if [[ -n "$bin" && -x "$bin" ]]; then
        printf '%s' "$bin"
        return 0
    fi
    command -v ls 2>/dev/null || true
}

function _init_list_is_lsd()
{
    local bin="$1" base

    [[ -n "$bin" ]] || return 1
    base="${bin##*/}"
    [[ "$base" == lsd ]]
}

# Directories only (colored when using lsd).
function lld()
{
    local list_bin grep_bin e nullglob_was_set=0
    local -a dirs=()

    list_bin="$(_init_list_bin)"
    [[ -n "$list_bin" ]] || return 1

    if _init_list_is_lsd "$list_bin"; then
        if (($# > 0)); then
            for e in "$@"; do
                [[ -d "$e" ]] || continue
                dirs+=("$e")
            done
        else
            shopt -q nullglob && nullglob_was_set=1
            shopt -s nullglob
            for e in * .[!.]* ..?*; do
                [[ -d "$e" ]] || continue
                dirs+=("$e")
            done
            [[ $nullglob_was_set -eq 1 ]] || shopt -u nullglob
        fi
        ((${#dirs[@]} > 0)) || return 0
        "$list_bin" -ahl -d --color=always -- "${dirs[@]}"
        return
    fi

    grep_bin="${init_tool_grep:-}"
    [[ -n "$grep_bin" && -x "$grep_bin" ]] || grep_bin="$(command -v grep 2>/dev/null || true)"
    [[ -n "$grep_bin" ]] || return 1
    "$list_bin" -ahl "$@" | "$grep_bin" ^d
}

# Long listing through a pager (force color for lsd / GNU ls; less -R when available).
function llm()
{
    local list_bin pager_bin

    list_bin="$(_init_list_bin)"
    [[ -n "$list_bin" ]] || return 1

    pager_bin="${init_tool_less:-}"
    [[ -n "$pager_bin" && -x "$pager_bin" ]] || pager_bin="$(command -v less 2>/dev/null || true)"
    if [[ -n "$pager_bin" ]]; then
        if _init_list_is_lsd "$list_bin"; then
            "$list_bin" -ahl --color=always -- "$@" | "$pager_bin" -R
        elif "$list_bin" --version >/dev/null 2>&1; then
            "$list_bin" --color=always -ahl --time-style=full-iso -- "$@" | "$pager_bin" -R
        else
            "$list_bin" -ahl -- "$@" | "$pager_bin" -R
        fi
        return
    fi

    pager_bin="${init_tool_more:-}"
    [[ -n "$pager_bin" && -x "$pager_bin" ]] || pager_bin="$(command -v more 2>/dev/null || true)"
    [[ -n "$pager_bin" ]] || return 1
    if _init_list_is_lsd "$list_bin"; then
        "$list_bin" -ahl --color=always -- "$@" | "$pager_bin"
    elif "$list_bin" --version >/dev/null 2>&1; then
        "$list_bin" --color=always -ahl --time-style=full-iso -- "$@" | "$pager_bin"
    else
        "$list_bin" -ahl -- "$@" | "$pager_bin"
    fi
}

function live_fetch_if_ahead()
{
    local tool_name current_version cached_latest live lock_dir

    tool_name="$1"
    current_version="$2"
    cached_latest="$3"

    if [[ -n "$current_version" && -n "$cached_latest" ]] \
        && version_lt "$cached_latest" "$current_version"; then
        live="$(fetch_latest_tool_version "$tool_name" 2>/dev/null || true)"
        if [[ -n "$live" ]]; then
            (
                refresh_tool_version_cache
            ) >/dev/null 2>&1 &
            disown $! 2>/dev/null || true
            printf '%s' "$live"
            return
        fi
    fi
    printf '%s' "$cached_latest"
}

function mk()
{
    time "$init_tool_make" 2>&1 | tee build.log
}

function mkt()
{
    time "$init_tool_make" test 2>&1 | tee build.log
}

function normalize_version()
{
    local version

    version="$1"

    if [[ "$version" =~ ([0-9]+([.][0-9]+)+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return
    fi

    version="${version//$'\r'/}"
    version="${version//$'\n'/}"
    version="${version//$'\t'/}"
    version="${version// /}"
    version="${version#v}"

    printf '%s' "$version"
}

function npm_bootstrap_instructions()
{
    local helper

    # Printed when update_npm (and friends) cannot find a user-local npm/nvm yet.
    helper="$(_init_node_toolchain_helper 2>/dev/null || true)"
    if [[ -n "$helper" ]]; then
        cat >&2 <<EOF
Need nvm + Node LTS under ~/.nvm, then retry:

  $helper
  hash -r
  update_npm

Optional next: update_pnpm / update_gt
EOF
        return 0
    fi

    cat >&2 <<'EOF'
  # 1) Install nvm. PROFILE=/dev/null is required: ~/.bashrc is a symlink
  #    into init-files, and the nvm installer must not append to it.
  #    (Pin may lag; see https://github.com/nvm-sh/nvm/releases)
  PROFILE=/dev/null bash -c \
    'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.6/install.sh | bash'

  # 2) Load nvm in this shell (new shells are handled by bashrc).
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"

  # 3) Install Node (includes npm + corepack), then refresh.
  nvm install --lts
  hash -r
  update_npm

Optional next: update_pnpm / update_gt
EOF
}

function npm_tools_available()
{
    _init_user_npm_command > /dev/null 2>&1 \
        || command -v npm > /dev/null 2>&1 \
        || command -v npx > /dev/null 2>&1
}

function npm_tools_path()
{
    local user_npm
    user_npm="$(_init_user_npm_command 2>/dev/null || true)"
    if [[ -n "$user_npm" ]]; then
        printf '%s' "$user_npm"
        return 0
    fi
    command -v npm 2> /dev/null || command -v npx 2> /dev/null || true
}

function npm_tools_version()
{
    local npm_cmd
    npm_cmd="$(npm_tools_path)"
    if [[ -n "$npm_cmd" && -x "$npm_cmd" ]]; then
        if type _init_npm_exec > /dev/null 2>&1; then
            _init_npm_exec "$npm_cmd" --version 2> /dev/null || true
        else
            "$npm_cmd" --version 2> /dev/null || true
        fi
        return 0
    fi
    npm --version 2> /dev/null || npx --version 2> /dev/null || true
}

function parse_git_branch()
{
    "$init_tool_git" branch --no-color 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/'
}

function pip_bootstrap_instructions()
{
    local py

    py="${init_tool_python3:-python3}"
    printf 'python3 pip is not available (%s -m pip).\n' "$py" >&2
    printf 'update_pipx needs the pip module to bootstrap pipx under ~/.local/opt/pipx.\n' >&2

    if _init_is_darwin && type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos; then
        cat >&2 <<EOF
On modern macOS, install/repair Homebrew Python (includes pip), then retry:

  brew install python
  hash -r
  update_pipx
  pipx install uv
EOF
        return 0
    fi

    if _init_is_darwin; then
        cat >&2 <<EOF
On this macOS tier, install pip for the system/Xcode python3 (no Homebrew), then retry:

  "$py" -m ensurepip --upgrade
  # if ensurepip is missing, use get-pip.py from https://bootstrap.pypa.io/get-pip.py
  update_pipx
  pipx install uv
EOF
        return 0
    fi

    if command -v apt-get > /dev/null 2>&1; then
        cat >&2 <<EOF
On Debian/Ubuntu, install pip (and venv), then retry:

  sudo apt update
  sudo apt install -y python3-pip python3-venv
  hash -r
  update_pipx
  pipx install uv

Note: distro "pipx" packages are optional; update_pipx installs a host-local pipx under ~/.local.
EOF
        return 0
    fi

    if command -v dnf > /dev/null 2>&1; then
        cat >&2 <<EOF
On Fedora/Rocky/RHEL, install pip, then retry:

  sudo dnf install -y python3-pip python3-devel
  hash -r
  update_pipx
  pipx install uv
EOF
        return 0
    fi

    if command -v yum > /dev/null 2>&1; then
        cat >&2 <<EOF
On yum-based Linux, install pip, then retry:

  sudo yum install -y python3-pip
  hash -r
  update_pipx
  pipx install uv
EOF
        return 0
    fi

    cat >&2 <<EOF
Install pip for "$py", then retry:

  "$py" -m ensurepip --upgrade
  # or: curl -sS https://bootstrap.pypa.io/get-pip.py | "$py"
  update_pipx
  pipx install uv
EOF
}

function pip_supports_install_flag()
{
    local flag

    flag="$1"
    command -v "$init_tool_python3" > /dev/null 2>&1 || return 1
    "$init_tool_python3" -m pip install --help 2> /dev/null | grep -q -- "$flag"
}

function pipx()
{
    local pipx_path

    pipx_path="$(pipx_command_path 2> /dev/null || true)"
    if [[ -n "$pipx_path" ]]; then
        # Pass init_tool_python3 for older host wrappers that still exec
        # env -u PIP_PREFIX "$init_tool_python3" (not baked in at install time).
        # Without it, the child sees an empty interpreter → env: '': No such file.
        PIPX_HOME="$HOME/.local/share/pipx" PIPX_BIN_DIR="$HOME/.local/bin" \
            init_tool_python3="${init_tool_python3:-}" \
            env -u PIP_PREFIX "$pipx_path" "$@"
        return
    fi

    printf 'pipx is not installed for host %s; run update_pipx\n' "$(host_tag)" >&2
    return 1
}

function pipx_binary_usable()
{
    local pipx_path site_dir

    pipx_path="$1"
    [[ -n "$pipx_path" && -x "$pipx_path" ]] || return 1

    site_dir="$(dirname "$(dirname "$pipx_path")")/site"
    if pipx_metadata_version "$site_dir" > /dev/null 2>&1; then
        return 0
    fi

    if ! python3_meets_minimum; then
        return 1
    fi

    PIPX_HOME="$HOME/.local/share/pipx" PIPX_BIN_DIR="$HOME/.local/bin" \
        init_tool_python3="${init_tool_python3:-}" \
        env -u PIP_PREFIX "$pipx_path" --version > /dev/null 2>&1
}

function pipx_command_path()
{
    local host_pipx_path path_pipx resolved_dir tag_name

    resolved_dir="$(pipx_resolve_host_dir 2> /dev/null || true)"
    if [[ -n "$resolved_dir" ]]; then
        host_pipx_path="$resolved_dir/current/bin/pipx"
        if pipx_binary_usable "$host_pipx_path"; then
            printf '%s' "$host_pipx_path"
            return 0
        fi
    fi

    while IFS= read -r path_pipx; do
        [[ -n "$path_pipx" && -x "$path_pipx" ]] || continue
        pipx_binary_usable "$path_pipx" || continue
        printf '%s' "$path_pipx"
        return 0
    done < <(find "$HOME/.local/opt/pipx" -path '*/current/bin/pipx' 2> /dev/null | sort -r)

    return 1
}

function pipx_current_version()
{
    local host_pipx_path resolved_pipx_path tool_path version

    tool_path="${1:-}"
    if [[ -z "$tool_path" || "$tool_path" == pipx || ! -x "$tool_path" ]]; then
        tool_path="$(pipx_command_path 2> /dev/null || true)"
    fi

    version="$(pipx_metadata_version 2> /dev/null || true)"
    if [[ -n "$version" ]]; then
        printf '%s' "$version"
        return 0
    fi

    version="$(pipx_layout_version 2> /dev/null || true)"
    if [[ -n "$version" ]]; then
        printf '%s' "$version"
        return 0
    fi

    [[ -n "$tool_path" ]] || return 1

    if [[ -x "$tool_path" ]]; then
        version=$(
            PIPX_HOME="$HOME/.local/share/pipx" PIPX_BIN_DIR="$HOME/.local/bin" \
                init_tool_python3="${init_tool_python3:-}" \
                env -u PIP_PREFIX "$tool_path" --version 2> /dev/null \
                | awk 'match($0, /[0-9]+(\.[0-9]+)+/) { print substr($0, RSTART, RLENGTH); exit }'
        )
        if [[ -n "$version" ]]; then
            printf '%s' "$version"
            return 0
        fi

        version=$(
            PIPX_HOME="$HOME/.local/share/pipx" PIPX_BIN_DIR="$HOME/.local/bin" \
                PYTHONPATH="$(pipx_host_dir)/current/site" \
                env -u PIP_PREFIX "$init_tool_python3" -m pipx --version 2> /dev/null \
                | awk 'match($0, /[0-9]+(\.[0-9]+)+/) { print substr($0, RSTART, RLENGTH); exit }'
        )
        if [[ -n "$version" ]]; then
            printf '%s' "$version"
            return 0
        fi
    fi

    resolved_pipx_path=$(readlink -f "$tool_path" 2> /dev/null || printf '%s' "$tool_path")
    if [[ "$resolved_pipx_path" =~ /[.]local/opt/pipx-([^/]+)/bin/pipx$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    host_pipx_path="$(pipx_host_dir)/current/bin/pipx"
    resolved_pipx_path=$(readlink -f "$host_pipx_path" 2> /dev/null || true)
    if [[ "$resolved_pipx_path" =~ /[.]local/opt/pipx/[^/]+/([^/]+)/bin/pipx$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

function pipx_host_dir()
{
    local resolved_dir

    # Prefer an existing usable tree (canonical or legacy hostname tags).
    resolved_dir="$(pipx_resolve_host_dir 2> /dev/null || true)"
    if [[ -n "$resolved_dir" ]]; then
        printf '%s' "$resolved_dir"
        return 0
    fi

    # New installs land under the unified host key (same as tools.* / prefs).
    printf '%s/.local/opt/pipx/%s' "$HOME" "$(host_tag)"
}

# Callers may optionally override the discovered pipx path.
# shellcheck disable=SC2120
function pipx_is_usable()
{
    local pipx_path

    pipx_path="${1:-$(pipx_command_path 2> /dev/null || true)}"
    [[ -n "$pipx_path" ]] || return 1

    pipx_binary_usable "$pipx_path"
}

function pipx_layout_version()
{
    local current_root version_label

    current_root=$(readlink -f "$(pipx_host_dir)/current" 2> /dev/null || true)
    [[ -n "$current_root" ]] || return 1

    version_label=$(basename "$current_root")
    if [[ "$version_label" =~ ^[0-9] ]]; then
        printf '%s' "$version_label"
        return 0
    fi

    return 1
}

function pipx_metadata_version()
{
    local site_dir

    site_dir="${1:-$(pipx_host_dir)/current/site}"
    [[ -d "$site_dir" ]] || return 1

    PYTHONPATH="$site_dir" "$init_tool_python3" - <<'PY' 2> /dev/null
import sys

try:
    import importlib.metadata as metadata
except ImportError:
    try:
        import importlib_metadata as metadata
    except ImportError:
        metadata = None

if metadata is not None:
    try:
        print(metadata.version("pipx"))
        sys.exit(0)
    except Exception:
        pass

import pkg_resources

print(pkg_resources.get_distribution("pipx").version)
PY
}

function pipx_required_python_label()
{
    printf '3.10+'
}

function pipx_resolve_host_dir()
{
    local candidate_dir host_dir tag_name
    local -a tags=()

    # Canonical first (init_files_host), then legacy FQDN/short for migration.
    tags+=("$(host_tag)")
    [[ -n "${init_files_host:-}" ]] && tags+=("$init_files_host")
    tags+=("$(hostname -f 2> /dev/null || true)")
    tags+=("$(hostname -s 2> /dev/null || true)")
    if [[ "${OSTYPE:-}" == darwin* ]]; then
        tags+=("$(scutil --get LocalHostName 2>/dev/null || true)")
    fi

    for tag_name in "${tags[@]}"; do
        [[ -n "$tag_name" ]] || continue
        tag_name="${tag_name//[^[:alnum:]._-]/-}"
        candidate_dir="$HOME/.local/opt/pipx/$tag_name"
        if [[ -x "$candidate_dir/current/bin/pipx" ]]; then
            printf '%s' "$candidate_dir"
            return 0
        fi
    done

    for host_dir in "$HOME/.local/opt/pipx"/*; do
        [[ -d "$host_dir/current/bin" && -x "$host_dir/current/bin/pipx" ]] || continue
        printf '%s' "$host_dir"
        return 0
    done

    return 1
}

# Move legacy pipx trees (hostname -f / -s / LocalHostName) onto init_files_host.
function migrate_pipx_host_layout()
{
    local canonical src tag ver newest
    local -a legacy_tags=()
    local quiet_migrate="${1:-}"

    canonical="$HOME/.local/opt/pipx/$(host_tag)"

    # Repair broken current → old FQDN path after a partial rename.
    if [[ -L "$canonical/current" && ! -e "$canonical/current" ]]; then
        newest=
        for ver in "$canonical"/*; do
            [[ -d "$ver" && "$(basename "$ver")" != current ]] || continue
            [[ -x "$ver/bin/pipx" ]] || continue
            newest="$ver"
        done
        if [[ -n "$newest" ]]; then
            ln -sfn "$newest" "$canonical/current" 2>/dev/null || true
            [[ -n "$quiet_migrate" ]] || printf 'Repaired pipx current -> %s\n' "$newest"
        fi
    fi

    if [[ -x "$canonical/current/bin/pipx" ]]; then
        return 0
    fi

    legacy_tags+=("$(hostname -f 2> /dev/null || true)")
    legacy_tags+=("$(hostname -s 2> /dev/null || true)")
    if [[ "${OSTYPE:-}" == darwin* ]]; then
        legacy_tags+=("$(scutil --get LocalHostName 2>/dev/null || true)")
    fi

    for tag in "${legacy_tags[@]}"; do
        [[ -n "$tag" ]] || continue
        tag="${tag//[^[:alnum:]._-]/-}"
        src="$HOME/.local/opt/pipx/$tag"
        [[ "$src" != "$canonical" ]] || continue
        [[ -x "$src/current/bin/pipx" || -d "$src" ]] || continue
        mkdir -p "$HOME/.local/opt/pipx" || return 1
        if [[ -e "$canonical" ]]; then
            # Merge: copy version dirs from legacy if canonical lacks a working current.
            if [[ ! -x "$canonical/current/bin/pipx" ]]; then
                for ver in "$src"/*; do
                    [[ -d "$ver" && "$(basename "$ver")" != current ]] || continue
                    [[ -e "$canonical/$(basename "$ver")" ]] && continue
                    mv "$ver" "$canonical/" 2>/dev/null || true
                done
                newest=
                for ver in "$canonical"/*; do
                    [[ -d "$ver" && "$(basename "$ver")" != current ]] || continue
                    [[ -x "$ver/bin/pipx" ]] || continue
                    newest="$ver"
                done
                if [[ -n "$newest" ]]; then
                    ln -sfn "$newest" "$canonical/current" 2>/dev/null || true
                    [[ -n "$quiet_migrate" ]] || printf 'Merged pipx from %s into %s\n' "$(basename "$src")" "$(basename "$canonical")"
                    return 0
                fi
            fi
            [[ -n "$quiet_migrate" ]] || printf 'migrate_pipx_host_layout: %s exists; leave %s in place\n' "$canonical" "$src" >&2
            continue
        fi
        if mv "$src" "$canonical" 2>/dev/null; then
            # Fix current if it still points at the old absolute path.
            if [[ -L "$canonical/current" ]]; then
                newest=$(readlink "$canonical/current" 2>/dev/null || true)
                if [[ "$newest" == *"/pipx/${tag}/"* ]] || [[ ! -e "$canonical/current" ]]; then
                    for ver in "$canonical"/*; do
                        [[ -d "$ver" && "$(basename "$ver")" != current ]] || continue
                        [[ -x "$ver/bin/pipx" ]] || continue
                        ln -sfn "$ver" "$canonical/current" 2>/dev/null || true
                    done
                fi
            fi
            [[ -n "$quiet_migrate" ]] || printf 'Migrated pipx %s -> %s\n' "$(basename "$src")" "$(basename "$canonical")"
            return 0
        fi
    done
    return 0
}

# Rebake host pipx wrappers that still expand $init_tool_python3 / bare python3.
function rewrite_stale_pipx_wrappers()
{
    local py wrapper shim quiet_rw="${1:-}"

    py="${init_tool_python3:-}"
    [[ -n "$py" && -x "$py" ]] || return 0

    migrate_pipx_host_layout quiet 2>/dev/null || true

    wrapper="$(pipx_host_dir 2>/dev/null)/current/bin/pipx"
    if [[ -f "$wrapper" ]]; then
        if grep -qE '\$\{?init_tool_python3\}?|exec env -u PIP_PREFIX python3 ' "$wrapper" 2>/dev/null; then
            cat > "$wrapper" <<EOF || return 1
#!/usr/bin/env bash
set -e

script_dir="\$(cd -- "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
site_dir="\${script_dir%/bin}/site"

export PYTHONPATH="\${site_dir}\${PYTHONPATH:+:\$PYTHONPATH}"
export PIPX_HOME="\$HOME/.local/share/pipx"
export PIPX_BIN_DIR="\$HOME/.local/bin"

exec env -u PIP_PREFIX $(printf '%q' "$py") -m pipx "\$@"
EOF
            chmod 775 "$wrapper" || true
            [[ -n "$quiet_rw" ]] || printf 'Rewrote stale pipx wrapper: %s\n' "$wrapper"
        fi
    fi

    shim="$HOME/.local/bin/pipx"
    if [[ -f "$shim" ]] && grep -qE 'hostname -f|hostname -s' "$shim" 2>/dev/null \
        && ! grep -q 'init_files_host\|host_tag' "$shim" 2>/dev/null; then
        # Old shim only probed FQDN/short; refresh resolution order on next update_pipx.
        # Soft note only — full shim rewrite happens in update_pipx.
        [[ -n "$quiet_rw" ]] || printf 'Note: ~/.local/bin/pipx shim is legacy; run update_pipx to refresh\n' >&2
    fi

    return 0
}

function pipx_runtime_status()
{
    local pipx_path

    if ! command -v "$init_tool_python3" > /dev/null 2>&1; then
        printf 'no-python'
        return 0
    fi

    if ! python3_meets_minimum; then
        printf 'python-too-old'
        return 0
    fi

    pipx_path="$(pipx_command_path 2> /dev/null || true)"
    if [[ -n "$pipx_path" ]]; then
        printf 'ok'
        return 0
    fi

    if find "$HOME/.local/opt/pipx" -path '*/current/bin/pipx' 2> /dev/null | grep -q .; then
        printf 'broken'
        return 0
    fi

    printf 'not-installed'
}

function pipx_tool_status_line()
{
    local pipx_current pipx_latest pipx_path reset runtime_status tone yellow

    pipx_path="$1"
    pipx_current="$2"
    pipx_latest="$3"
    runtime_status="$(pipx_runtime_status 2> /dev/null || true)"
    yellow=
    reset=
    if [[ -n "$tool_status_use_color" ]]; then
        yellow=$'\033[33m'
        reset=$'\033[0m'
    fi

    case "$runtime_status" in
        python-too-old)
            printf '%s  pipx: installed ?, latest %s, status: requires Python %s (host has %s), path: %s%s' \
                "$yellow" "$(normalize_version "$pipx_latest")" "$(pipx_required_python_label)" \
                "$("$init_tool_python3" --version 2> /dev/null | awk '{print $2}' || printf unknown)" "$pipx_path" "$reset"
            printf '\n%s    cannot upgrade until python3 >= 3.10 is default for update_pipx%s\n' "$yellow" "$reset"
            ;;
        broken)
            printf '%s  pipx: installed ?, latest %s, status: broken (install not runnable on this host), path: %s%s' \
                "$yellow" "$(normalize_version "$pipx_latest")" "$pipx_path" "$reset"
            printf '\n%s    run: update_pipx  (needs Python %s)%s\n' "$yellow" "$(pipx_required_python_label)" "$reset"
            ;;
        no-python)
            printf '%s  pipx: installed -, latest %s, status: python3 not found, path: %s%s' \
                "$yellow" "$(normalize_version "$pipx_latest")" "$pipx_path" "$reset"
            ;;
        not-installed)
            tool_status_line pipx "" "" "$pipx_latest"
            ;;
        *)
            tool_status_line pipx "$pipx_path" "$pipx_current" "$pipx_latest" auto
            ;;
    esac
}

function pipx_update_command()
{
    printf 'update_pipx'
}

function pipx_venv_missing_pip()
{
    local resolved_tool_path venv_dir venv_python

    resolved_tool_path="${1:-}"
    [[ -n "$resolved_tool_path" ]] || return 1
    [[ "$resolved_tool_path" == *"/pipx/venvs/"*"/bin/"* ]] || return 1

    venv_dir="${resolved_tool_path%/bin/*}"
    venv_python="$venv_dir/bin/python"
    [[ -x "$venv_python" ]] || return 1

    "$venv_python" -m pip --version > /dev/null 2>&1 || return 0
    return 1
}

function corepack_command_path()
{
    local pnpm_path resolved_pnpm_path candidate user_corepack

    # Prefer user-local corepack (nvm) — never Homebrew (often not writable).
    user_corepack="$(_init_user_corepack_command 2>/dev/null || true)"
    if [[ -n "$user_corepack" ]]; then
        printf '%s\n' "$user_corepack"
        return 0
    fi

    pnpm_path="${1:-$(command -v pnpm 2> /dev/null || true)}"
    if [[ -n "$pnpm_path" ]]; then
        if command -v "$init_tool_python3" > /dev/null 2>&1; then
            resolved_pnpm_path=$("$init_tool_python3" -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$pnpm_path" 2> /dev/null || true)
        fi
        [[ -n "$resolved_pnpm_path" ]] || resolved_pnpm_path=$(readlink "$pnpm_path" 2> /dev/null || printf '%s' "$pnpm_path")

        case "$resolved_pnpm_path" in
            */.nvm/*|*/fnm/*)
                candidate="${resolved_pnpm_path%%/libexec/*}/bin/corepack"
                # nvm layout: .../versions/node/vX/bin/pnpm via corepack
                if [[ -x "${pnpm_path%/*}/corepack" ]]; then
                    printf '%s\n' "${pnpm_path%/*}/corepack"
                    return 0
                fi
                ;;
            */Cellar/corepack/*)
                # Homebrew corepack — only if somehow user-writable (rare).
                candidate="${resolved_pnpm_path%%/libexec/*}/bin/corepack"
                if [[ -x "$candidate" ]] && ! _init_path_is_homebrew "$candidate"; then
                    printf '%s\n' "$candidate"
                    return 0
                fi
                ;;
        esac
    fi

    if [[ -n "${init_tool_corepack:-}" && -x "$init_tool_corepack" ]] \
        && ! _init_path_is_homebrew "$init_tool_corepack"
    then
        printf '%s\n' "$init_tool_corepack"
        return 0
    fi

    candidate=$(command -v corepack 2> /dev/null || true)
    if [[ -n "$candidate" && -x "$candidate" ]] && ! _init_path_is_homebrew "$candidate"; then
        printf '%s\n' "$candidate"
        return 0
    fi

    return 1
}

# Callers may optionally override the discovered pnpm path.
# shellcheck disable=SC2120
function pnpm_update_command()
{
    local pnpm_path corepack_path npm_cmd

    pnpm_path="${1:-$(command -v pnpm 2> /dev/null || true)}"

    if pnpm_uses_corepack "$pnpm_path"; then
        corepack_path="$(corepack_command_path "$pnpm_path" 2> /dev/null || true)"
        if [[ -n "$corepack_path" ]]; then
            printf '%s prepare pnpm@latest --activate' "$corepack_path"
            return 0
        fi
    fi

    npm_cmd="$(_init_user_npm_command 2>/dev/null || true)"
    if [[ -n "$npm_cmd" ]]; then
        printf "PATH=%q:\$PATH %q install --global pnpm@latest" \
            "$(cd "$(dirname "$npm_cmd")" && pwd)" "$npm_cmd"
        return 0
    fi

    return 1
}

function pnpm_uses_corepack()
{
    local pnpm_path resolved_pnpm_path

    pnpm_path="${1:-$(command -v pnpm 2> /dev/null || true)}"
    [[ -n "$pnpm_path" ]] || return 1
    if command -v "$init_tool_python3" > /dev/null 2>&1; then
        resolved_pnpm_path=$("$init_tool_python3" -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$pnpm_path" 2> /dev/null || true)
    fi
    [[ -n "$resolved_pnpm_path" ]] || resolved_pnpm_path=$(readlink "$pnpm_path" 2> /dev/null || printf '%s' "$pnpm_path")
    [[ "$resolved_pnpm_path" == *"/corepack/"*"/pnpm.js" || "$resolved_pnpm_path" == *"/corepack/dist/pnpm.js" ]]
}

function python3_has_pip()
{
    command -v "$init_tool_python3" > /dev/null 2>&1 || return 1
    "$init_tool_python3" -m pip --version > /dev/null 2>&1
}

function python3_meets_minimum()
{
    local major minor

    command -v "$init_tool_python3" > /dev/null 2>&1 || return 1
    major=$("$init_tool_python3" -c 'import sys; print(sys.version_info[0])' 2> /dev/null || printf 0)
    minor=$("$init_tool_python3" -c 'import sys; print(sys.version_info[1])' 2> /dev/null || printf 0)
    (( major > 3 || (major == 3 && minor >= 10) ))
}

# Resolve starship even when login PATH is incomplete (e.g. brew not yet visible).
function _init_resolve_starship()
{
    local candidate brew_prefix
    for candidate in \
        "$(command -v starship 2>/dev/null || true)" \
        "${HOME}/.local/bin/starship" \
        /usr/local/bin/starship
    do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    if type _init_homebrew_prefix > /dev/null 2>&1; then
        brew_prefix="$(_init_homebrew_prefix 2>/dev/null || true)"
        if [[ -n "$brew_prefix" ]]; then
            candidate="$(init_files_prefix_bin "$brew_prefix" starship 2>/dev/null || true)"
            if [[ -n "$candidate" && -x "$candidate" ]]; then
                printf '%s\n' "$candidate"
                return 0
            fi
        fi
    fi
    return 1
}

# Drop starship_precmd tokens from a PROMPT_COMMAND string (reload can leave
# history_sync;starship_precmd, which breaks after unset -f starship_precmd).
function _init_prompt_strip_starship_precmd()
{
    local pc="${1-}" dsemi=$';;'
    pc="${pc//starship_precmd/}"
    while [[ "$pc" == *"$dsemi"* ]]; do
        pc="${pc//"$dsemi"/;}"
    done
    pc="${pc##;}"
    pc="${pc%%;}"
    printf '%s' "$pc"
}

function _init_prompt_ensure_history_sync()
{
    local pc="${1-}"
    if [[ -z "$pc" ]]; then
        printf 'history_sync'
    elif [[ ";${pc};" == *";history_sync;"* ]]; then
        printf '%s' "$pc"
    else
        printf 'history_sync;%s' "$pc"
    fi
}

function _init_prompt_ensure_session_hooks()
{
    local pc
    pc="$(_init_prompt_ensure_history_sync "${1-}")"
    if [[ ";${pc};" == *";_init_iterm_report_host_label;"* ]]; then
        printf '%s' "$pc"
    else
        printf '%s;%s' "$pc" '_init_iterm_report_host_label'
    fi
}

# Unwrap Starship's PROMPT_COMMAND / DEBUG / functions without changing PS1.
# Safe to call before re-init (refresh_init_files reload) or when switching to plain.
function _init_prompt_unwrap_starship()
{
    local restored=""

    if [[ -n "${STARSHIP_PROMPT_COMMAND-}" ]]; then
        restored="$STARSHIP_PROMPT_COMMAND"
    elif [[ -n "${_init_prompt_saved_prompt_command+x}" ]]; then
        restored="${_init_prompt_saved_prompt_command-}"
    else
        restored="${PROMPT_COMMAND-}"
    fi
    restored="$(_init_prompt_strip_starship_precmd "$restored")"
    PROMPT_COMMAND="$(_init_prompt_ensure_session_hooks "$restored")"

    if [[ -n "${_init_prompt_saved_debug_trap:-}" ]]; then
        eval "$_init_prompt_saved_debug_trap"
    else
        trap - DEBUG 2>/dev/null || true
    fi

    PS0="${_init_prompt_saved_ps0-}"
    PS2="${_init_prompt_saved_ps2:-${PS2:-"> "}}"

    unset STARSHIP_PROMPT_COMMAND STARSHIP_SESSION_KEY STARSHIP_SHELL \
        STARSHIP_START_TIME STARSHIP_PREEXEC_READY STARSHIP_CMD_STATUS \
        STARSHIP_DURATION STARSHIP_END_TIME STARSHIP_DEBUG_TRAP \
        STARSHIP_PIPE_STATUS
    unset -f starship_precmd starship_preexec starship_preexec_all \
        starship_preexec_ps0 _starship_set_return 2>/dev/null || true
    unset _init_prompt_saved_prompt_command _init_prompt_saved_debug_trap \
        _init_prompt_saved_ps0 _init_prompt_saved_ps1 _init_prompt_saved_ps2
}

function prompt_fancy()
{
    local quiet=0 starship_bin starship_config flag_path

    case "${1:-}" in
        -q|--quiet) quiet=1 ;;
        -h|--help)
            cat <<'EOF'
Usage: prompt_fancy [-q|--quiet]

Enable Starship prompt and remember it for the next login on this host
(~/.config/init-files/fancy-prompt.<hostname>). Uses init-files/starship.toml.
If starship is missing and this is an interactive TTY, offers to install it
for this OS (brew on modern macOS; apt/dnf when packaged; else install_starship).
Disable (and forget) with: prompt_plain
EOF
            return 0
            ;;
    esac

    starship_bin="$(_init_resolve_starship 2>/dev/null || true)"
    if [[ -z "$starship_bin" ]]; then
        if [[ $quiet -eq 1 ]]; then
            # Login restore: no interactive install; leave a short hint.
            printf 'prompt_fancy: starship not found\n' >&2
            if _init_is_darwin && type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos; then
                printf '  install: brew install starship && prompt_fancy\n' >&2
            else
                printf '  install: prompt_fancy   # interactive; or install_starship\n' >&2
            fi
            return 1
        fi

        printf 'prompt_fancy: starship not found\n' >&2
        if _init_is_darwin && type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos; then
            printf '  needed: brew install starship\n' >&2
        elif ! _init_is_darwin && command -v apt-get > /dev/null 2>&1 \
            && apt-cache show starship > /dev/null 2>&1
        then
            printf '  needed: sudo apt install starship\n' >&2
        elif ! _init_is_darwin && command -v dnf > /dev/null 2>&1 \
            && dnf info starship > /dev/null 2>&1
        then
            printf '  needed: sudo dnf install starship\n' >&2
        else
            printf '  needed: install_starship  (upstream → ~/.local/bin)\n' >&2
        fi

        if ! _init_prompt_yn "Install starship for this host now? [Y/n]"; then
            printf 'prompt_fancy: skipped install\n' >&2
            return 1
        fi
        _init_offer_install_starship || return 1
        starship_bin="$(_init_resolve_starship 2>/dev/null || true)"
        if [[ -z "$starship_bin" ]]; then
            printf 'prompt_fancy: starship still not found after install\n' >&2
            return 1
        fi
    fi

    # Same host label as classic PS1 (macOS ComputerName via _init_host_label).
    if [[ -z "${computer_name:-}" ]]; then
        computer_name=$(_init_host_label)
    fi
    export INIT_FILES_HOST_LABEL="$computer_name"

    starship_config="${init_files_dir:-${XDG_DATA_HOME:-$HOME/.local/share}/init-files}/starship.toml"
    if [[ -f "$starship_config" ]]; then
        if [[ -z "${_init_prompt_saved_starship_config+x}" ]]; then
            _init_prompt_saved_starship_config="${STARSHIP_CONFIG-}"
            _init_prompt_saved_starship_config_set=1
        fi
        export STARSHIP_CONFIG="$starship_config"
    fi

    mkdir -p "${init_files_config_dir:-$HOME/.config/init-files}" 2>/dev/null || true
    flag_path="${init_files_fancy_prompt_flag:-$HOME/.config/init-files/fancy-prompt.${init_files_host:-host}}"
    printf '1\n' > "$flag_path" 2>/dev/null || true

    # Already cleanly enabled (avoid pointless unwrap/re-init).
    if [[ "${_init_prompt_mode:-}" == fancy ]] \
        && type starship_precmd > /dev/null 2>&1 \
        && [[ "${PROMPT_COMMAND-}" == "starship_precmd" ]]; then
        [[ $quiet -eq 1 ]] || printf 'prompt_fancy: already enabled\n'
        return 0
    fi

    # Drop leftover Starship hooks (e.g. after refresh_init_files reload) so we
    # save a clean PROMPT_COMMAND and starship can re-wrap it.
    if [[ "${PROMPT_COMMAND-}" == *starship_precmd* ]] || type starship_precmd > /dev/null 2>&1; then
        _init_prompt_unwrap_starship
        _init_prompt_mode=plain
    fi

    _init_prompt_saved_ps1="${PS1-}"
    _init_prompt_saved_ps0="${PS0-}"
    _init_prompt_saved_ps2="${PS2-}"
    _init_prompt_saved_prompt_command="$(_init_prompt_strip_starship_precmd "${PROMPT_COMMAND-}")"
    _init_prompt_saved_debug_trap="$(trap -p DEBUG 2>/dev/null || true)"

    # shellcheck disable=SC1090
    eval "$("$starship_bin" init bash)"
    _init_prompt_mode=fancy
    [[ $quiet -eq 1 ]] || printf 'prompt_fancy: enabled (remembered for next login on %s)\n' "${init_files_host:-host}"
}

function prompt_plain()
{
    local quiet=0

    case "${1:-}" in
        -q|--quiet) quiet=1 ;;
        -h|--help)
            cat <<'EOF'
Usage: prompt_plain [-q|--quiet]

Restore the classic init-files bash prompt and forget fancy for this host
(next login stays plain). Re-enable with: prompt_fancy
EOF
            return 0
            ;;
    esac

    rm -f "${init_files_fancy_prompt_flag:-$HOME/.config/init-files/fancy-prompt.${init_files_host:-host}}" 2>/dev/null || true

    # Always tear down Starship hooks. Setting PS1 alone is not enough —
    # starship_precmd in PROMPT_COMMAND rewrites PS1 before the next prompt.
    _init_prompt_unwrap_starship

    if [[ -n "${_init_prompt_plain_ps1:-}" ]]; then
        PS1="$_init_prompt_plain_ps1"
    fi

    if [[ -n "${_init_prompt_saved_starship_config_set:-}" ]]; then
        if [[ -n "${_init_prompt_saved_starship_config:-}" ]]; then
            export STARSHIP_CONFIG="$_init_prompt_saved_starship_config"
        else
            unset STARSHIP_CONFIG
        fi
        unset _init_prompt_saved_starship_config _init_prompt_saved_starship_config_set
    elif [[ "${STARSHIP_CONFIG:-}" == */init-files/starship.toml ]]; then
        unset STARSHIP_CONFIG
    fi

    _init_prompt_mode=plain
    [[ $quiet -eq 1 ]] || printf 'prompt_plain: classic init-files prompt\n'
}

# Reasons that tools.<host> should be rewritten via ./provision_init_files (stdout, one per line).
# Empty output means recorded paths look fine (file present; listed binaries executable;
# tools revision matches this bashrc).
# Arg: "broken" = missing file / non-executable paths / revision mismatch only;
# "all" (default) also cheap staleness (tools file ≫60d old and a common binary is newer).
_init_files_tools_reinstall_reasons()
{
    local mode="${1:-all}"
    local tools_file line var val rev
    local -a missing=()
    local tools_mtime now age_days probe probe_mtime brew_prefix
    local m
    local -a probes=()

    tools_file="${init_files_tools_file:-${XDG_CONFIG_HOME:-$HOME/.config}/init-files/tools.${init_files_host:-host}}"
    if [[ ! -f "$tools_file" ]]; then
        printf 'missing tools file (%s)\n' "$tools_file"
        return 0
    fi

    rev=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            init_files_tools_revision=*)
                rev="${line#init_files_tools_revision=}"
                rev="${rev%%#*}"
                rev="${rev//[[:space:]]/}"
                ;;
            init_tool_*=*)
                [[ "$line" == \#* ]] && continue
                var="${line%%=*}"
                # Values are written with printf %q — decode that form (trusted local file).
                val="${line#*=}"
                eval "val=${val}" 2>/dev/null || continue
                [[ -n "$val" ]] || continue
                if ! declare -F init_files_verify_tool_path > /dev/null 2>&1 \
                    || ! init_files_verify_tool_path "$val"; then
                    missing+=("${var}=${val}")
                fi
                ;;
        esac
    done < "$tools_file"

    if [[ -z "$rev" ]]; then
        printf 'tools file missing init_files_tools_revision (run provision_init_files)\n'
    elif [[ "$rev" != "${INIT_FILES_TOOLS_REVISION:-}" ]]; then
        printf 'tools revision %s != bashrc %s (tooling requirements changed)\n' \
            "$rev" "${INIT_FILES_TOOLS_REVISION:-?}"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        printf 'recorded tool path(s) missing or not executable:\n'
        for m in "${missing[@]}"; do
            printf '  %s\n' "$m"
        done
    fi

    [[ "$mode" == broken ]] && return 0

    # Cheap staleness: tools file older than ~60 days and a common binary is newer.
    now=$(date +%s 2>/dev/null || echo 0)
    # Prefer GNU -c (Linux); BSD -f second — see check_tool_versions mtime note.
    tools_mtime=$(stat -c %Y "$tools_file" 2>/dev/null || stat -f %m "$tools_file" 2>/dev/null || echo 0)
    if [[ "$now" =~ ^[0-9]+$ && "$tools_mtime" =~ ^[0-9]+$ ]] && (( now > tools_mtime )); then
        age_days=$(( (now - tools_mtime) / 86400 ))
        if (( age_days >= 60 )); then
            brew_prefix=""
            if type _init_homebrew_prefix > /dev/null 2>&1; then
                brew_prefix="$(_init_homebrew_prefix 2>/dev/null || true)"
            fi
            probes=()
            if [[ -n "$brew_prefix" ]] && declare -F init_files_prefix_bin > /dev/null 2>&1; then
                probe="$(init_files_prefix_bin "$brew_prefix" git 2>/dev/null || true)"
                [[ -n "$probe" ]] && probes+=("$probe")
            fi
            probes+=(/usr/local/bin/git /usr/bin/git)
            for probe in "${probes[@]}"; do
                [[ -n "$probe" && -x "$probe" ]] || continue
                probe_mtime=$(stat -c %Y "$probe" 2>/dev/null || stat -f %m "$probe" 2>/dev/null || echo 0)
                if [[ "$probe_mtime" =~ ^[0-9]+$ ]] && (( probe_mtime > tools_mtime )); then
                    printf 'tools file is %sd old and %s is newer — OS/tool move likely\n' "$age_days" "$probe"
                    break
                fi
            done
        fi
    fi
}

# True when login profile already sources ~/.bashrc via init-files marker
# (or resolves to the clone bashrc). Mirrors provision_init_files logic.
_init_files_login_hook_ok()
{
    local marker_begin='# >>> init-files >>>'
    local target target_real bashrc_real

    if [[ -e "${HOME}/.bash_profile" ]]; then
        target="${HOME}/.bash_profile"
    elif [[ -e "${HOME}/.bash_login" ]]; then
        target="${HOME}/.bash_login"
    elif [[ -e "${HOME}/.profile" ]]; then
        target="${HOME}/.profile"
    else
        return 1
    fi

    bashrc_real="${HOME}/.bashrc"
    if [[ -L "${HOME}/.bashrc" ]]; then
        bashrc_real=$(readlink "${HOME}/.bashrc" 2>/dev/null || true)
        [[ "$bashrc_real" == /* ]] || bashrc_real="${init_files_dir:-${XDG_DATA_HOME:-$HOME/.local/share}/init-files}/bashrc"
    fi

    if [[ -L "$target" ]]; then
        target_real=$(readlink "$target" 2>/dev/null || true)
        if [[ -n "$target_real" ]]; then
            [[ "$target_real" == /* ]] || target_real="$(cd "$(dirname "$target")" && pwd)/$target_real"
            if [[ "$target_real" == "$bashrc_real" || "$target_real" == "${HOME}/.bashrc" \
                || "$target_real" == *"init-files/bashrc" ]]; then
                return 0
            fi
        fi
    fi

    [[ -f "$target" ]] || return 1
    grep -Fq "$marker_begin" "$target" 2>/dev/null
}

# Compare live curated iTerm prefs to the clone plist.
# Exit 0 = drifted, 1 = match, 2 = skip (not Darwin / missing tools / no domain).
_init_files_iterm_curated_drift()
{
    local clone_dir dir py live_tmp plist

    type _init_is_darwin > /dev/null 2>&1 && _init_is_darwin || return 2

    clone_dir="${init_files_dir:-${XDG_DATA_HOME:-$HOME/.local/share}/init-files}"
    dir="${clone_dir}/iterm2"
    plist="${dir}/com.googlecode.iterm2.plist"
    [[ -f "$plist" && -f "$dir/_prefs.py" ]] || return 2

    py="$(_init_iterm2_python 2>/dev/null)" || return 2
    [[ -n "$py" ]] || return 2

    live_tmp="$(mktemp -t iterm2-drift-live.XXXXXX 2>/dev/null)" || return 2
    if ! _init_iterm2_live_curated "$live_tmp" 2>/dev/null; then
        rm -f "$live_tmp"
        return 2
    fi
    if "$py" "$dir/_prefs.py" equal "$live_tmp" "$plist" 2>/dev/null; then
        rm -f "$live_tmp"
        return 1
    fi
    rm -f "$live_tmp"
    return 0
}

# Print one drift reason per line (stdout). Empty = no drift.
# Covers bashrc/vimrc/login hook/iTerm curated prefs + broken tool paths.
_init_files_deploy_drift_reasons()
{
    local clone_dir="${init_files_dir:-${XDG_DATA_HOME:-$HOME/.local/share}/init-files}"
    local link_target expected
    local tools_reasons
    local iterm_rc

    expected="${clone_dir}/bashrc"
    if [[ -L "${HOME}/.bashrc" ]]; then
        link_target=$(readlink "${HOME}/.bashrc" 2>/dev/null || true)
        if [[ "$link_target" != "$expected" ]]; then
            printf 'bashrc symlink is %s (expected %s)\n' "$link_target" "$expected"
        fi
    else
        printf '%s/.bashrc is not a symlink to %s\n' "$HOME" "$expected"
    fi

    if [[ -f "${clone_dir}/vim/vimrc" ]]; then
        expected="${clone_dir}/vim/vimrc"
        if [[ -L "${HOME}/.vimrc" ]]; then
            link_target=$(readlink "${HOME}/.vimrc" 2>/dev/null || true)
            if [[ "$link_target" != "$expected" ]]; then
                printf 'vimrc symlink is %s (expected %s)\n' "$link_target" "$expected"
            fi
        elif [[ -e "${HOME}/.vimrc" ]]; then
            printf '%s/.vimrc is not a symlink (expected -> %s)\n' "$HOME" "$expected"
        else
            printf '%s/.vimrc missing (expected symlink -> %s)\n' "$HOME" "$expected"
        fi
        if [[ -e "${HOME}/.gvimrc" || -L "${HOME}/.gvimrc" ]]; then
            printf '%s/.gvimrc still present (should be retired for one-file vimrc)\n' "$HOME"
        fi
    fi

    if ! _init_files_login_hook_ok; then
        printf 'login profile missing init-files bashrc hook (~/.bash_profile / ~/.profile)\n'
    fi

    if type _init_files_iterm_curated_drift > /dev/null 2>&1; then
        _init_files_iterm_curated_drift
        iterm_rc=$?
        if [[ $iterm_rc -eq 0 ]]; then
            printf 'iTerm curated prefs differ from clone (font/colors/keys)\n'
        fi
    fi

    if type _init_files_tools_reinstall_reasons > /dev/null 2>&1; then
        tools_reasons="$(_init_files_tools_reinstall_reasons broken 2>/dev/null || true)"
        if [[ -n "$tools_reasons" ]]; then
            printf '%s\n' "$tools_reasons"
        fi
    fi
}

# Probe origin/main SHA for git dir $1 (optional git binary $2). Prints SHA; returns 1 if empty.
# Uses HTTPS helper or BatchMode SSH based on this host’s GitHub transport.
_init_files_probe_origin_main()
{
    local dir="${1:-}" git_bin="${2:-}" remote_head

    [[ -n "$dir" && -d "$dir/.git" ]] || return 1
    if [[ -z "$git_bin" || ! -x "$git_bin" ]]; then
        git_bin="${init_tool_git:-}"
        if [[ -z "$git_bin" || ! -x "$git_bin" ]]; then
            git_bin="$(command -v git 2>/dev/null || true)"
        fi
    fi
    [[ -n "$git_bin" && -x "$git_bin" ]] || return 1

    if type _init_files_is_github_https_host > /dev/null 2>&1 && _init_files_is_github_https_host; then
        remote_head=$(
            _init_files_git_https "$git_bin" -C "$dir" ls-remote --heads origin main 2>/dev/null \
                | awk '{ print $1; exit }'
        )
    else
        remote_head=$(
            GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1" \
                "$git_bin" -C "$dir" ls-remote --heads origin main 2>/dev/null \
                | awk '{ print $1; exit }'
        )
    fi
    [[ -n "$remote_head" ]] || return 1
    printf '%s\n' "$remote_head"
}

# Flag a failed daily remote check. On a TTY, offer retry (return 0 = retry; may run cache_ssh).
# $1 = human label (e.g. init-files, private config).
_init_files_offer_remote_check_retry()
{
    local label="${1:-remote}"
    local reply

    echo "init-files: could not reach ${label} origin/main (offline, auth, or network)." >&2
    if type _init_files_is_github_https_host > /dev/null 2>&1 && _init_files_is_github_https_host; then
        echo "  Hint: check gh auth / credential helper, then retry." >&2
    else
        echo "  Hint: run cache_ssh (BatchMode needs a loaded key), then retry." >&2
    fi
    if [[ -t 0 && -t 2 ]]; then
        printf 'Retry %s remote check now? [Y/n] ' "$label" >&2
        read -r reply || reply=n
        case "$reply" in
            ''|y|Y|yes|YES)
                if ! type _init_files_is_github_https_host > /dev/null 2>&1 \
                    || ! _init_files_is_github_https_host; then
                    if type cache_ssh > /dev/null 2>&1 && ! cache_ssh -c 2>/dev/null; then
                        cache_ssh || true
                    fi
                fi
                return 0
                ;;
            *)
                echo "Skipped ${label} update check." >&2
                return 1
                ;;
        esac
    fi
    echo "  Later: fix network/auth, then refresh_init_files (or a new interactive shell after the daily stamp)." >&2
    return 1
}

# Daily quiet path: private config overlay URL drift or origin/main moved.
# Suggests pull (and provision to re-merge SSH) — never auto-applies.
_init_files_offer_private_config_update()
{
    local dir origin preferred np no git_bin local_head remote_head
    local local_short remote_short reply drifted=0 behind=0

    declare -F init_files_private_config_dir > /dev/null 2>&1 || return 0
    dir="$(init_files_private_config_dir)"
    [[ -d "$dir/.git" ]] || return 0

    git_bin="${init_tool_git:-}"
    if [[ -z "$git_bin" || ! -x "$git_bin" ]]; then
        git_bin="$(command -v git 2>/dev/null || true)"
    fi
    [[ -n "$git_bin" && -x "$git_bin" ]] || return 0

    if declare -F init_files_private_config_url_drifted > /dev/null 2>&1 \
        && init_files_private_config_url_drifted; then
        drifted=1
        preferred="$(init_files_config_repo_url 2>/dev/null || true)"
        origin="$(init_files_private_config_origin_url 2>/dev/null || true)"
        np="$(init_files_normalize_git_repo_url "$preferred")"
        no="$(init_files_normalize_git_repo_url "$origin")"
        echo "init-files: private config URL differs from clone origin." >&2
        echo "  remembered/env: $preferred" >&2
        echo "  clone origin:   $origin" >&2
        echo "  (normalized: $np vs $no)" >&2
        echo "  Fix: git -C ${dir} remote set-url origin \"$preferred\"" >&2
        echo "       # or update ~/.config/init-files/config-repo / INIT_FILES_CONFIG_REPO" >&2
    fi

    remote_head="$(_init_files_probe_origin_main "$dir" "$git_bin" 2>/dev/null || true)"
    while [[ -z "$remote_head" ]]; do
        if _init_files_offer_remote_check_retry 'private config'; then
            remote_head="$(_init_files_probe_origin_main "$dir" "$git_bin" 2>/dev/null || true)"
            continue
        fi
        break
    done
    if [[ -z "$remote_head" ]]; then
        [[ $drifted -eq 1 ]]
        return 0
    fi

    local_head="$("$git_bin" -C "$dir" rev-parse HEAD 2>/dev/null || true)"
    if [[ -n "$local_head" && "$local_head" != "$remote_head" ]]; then
        behind=1
        local_short="$("$git_bin" -C "$dir" rev-parse --short HEAD 2>/dev/null || echo '?')"
        remote_short=$(printf '%.7s' "$remote_head")
        echo "init-files: private config main has moved (local $local_short → $remote_short)." >&2
        if [[ -t 0 && -t 2 ]]; then
            printf 'Pull private config now? [Y/n] ' >&2
            read -r reply || reply=n
            case "$reply" in
                ''|y|Y|yes|YES)
                    if declare -F init_files_pull_private_config > /dev/null 2>&1; then
                        if init_files_pull_private_config; then
                            echo "Pulled ${dir/#$HOME/~}. Re-merge SSH materials:" >&2
                            echo "  ${init_files_dir:-$HOME/.local/share/init-files}/provision_init_files" >&2
                            if [[ -t 0 && -t 2 ]]; then
                                printf 'Run provision_init_files now? [Y/n] ' >&2
                                read -r reply || reply=n
                                case "$reply" in
                                    ''|y|Y|yes|YES)
                                        "${init_files_dir:-$HOME/.local/share/init-files}/provision_init_files" || true
                                        ;;
                                    *) echo "Skipped provision." >&2 ;;
                                esac
                            fi
                        else
                            echo "Pull failed. Check auth / remote URL, then:" >&2
                            echo "  git -C ${dir} pull --ff-only" >&2
                        fi
                    else
                        echo "Run: git -C ${dir} pull --ff-only" >&2
                        echo "Then: ${init_files_dir:-$HOME/.local/share/init-files}/provision_init_files" >&2
                    fi
                    ;;
                *)
                    echo "Skipped. Later: git -C ${dir} pull --ff-only && provision_init_files" >&2
                    ;;
            esac
        else
            echo "Run: git -C ${dir} pull --ff-only && provision_init_files" >&2
        fi
    fi

    [[ $drifted -eq 1 || $behind -eq 1 ]]
    return 0
}

# Daily quiet path: when local deploy drifted, offer a repair (TTY) or print a hint.
_init_files_offer_deploy_repairs()
{
    local reasons
    local need_bashrc=0 need_vim=0 need_iterm=0 need_login=0 need_tools=0
    local repair_cmd reply
    local no_dev=0

    reasons="$(_init_files_deploy_drift_reasons 2>/dev/null || true)"
    [[ -n "$reasons" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] || continue
        # Escape leading ~ so bash case does not tilde-expand the pattern.
        case "$line" in
            bashrc\ *|\~/.bashrc\ *) need_bashrc=1 ;;
            vimrc\ *|\~/.vimrc\ *|\~/.gvimrc\ *) need_vim=1 ;;
            iTerm\ *) need_iterm=1 ;;
            login\ *) need_login=1 ;;
            *) need_tools=1 ;;
        esac
    done <<< "$reasons"

    if type _init_files_is_no_dev_host > /dev/null 2>&1 && _init_files_is_no_dev_host; then
        no_dev=1
    fi

    # Prefer the narrowest fix when only one subsystem drifted.
    if [[ $need_bashrc -eq 0 && $need_login -eq 0 && $need_tools -eq 0 \
        && $need_vim -eq 1 && $need_iterm -eq 0 ]]; then
        repair_cmd='refresh_vimrc'
    elif [[ $need_bashrc -eq 0 && $need_login -eq 0 && $need_tools -eq 0 \
        && $need_vim -eq 0 && $need_iterm -eq 1 ]]; then
        repair_cmd='refresh_iterm_settings'
    elif [[ $no_dev -eq 1 ]]; then
        repair_cmd='refresh_init_files --no-dev'
    else
        repair_cmd='refresh_init_files'
    fi

    printf 'init-files: local deploy differs from canonical:\n' >&2
    printf '%s\n' "$reasons" | sed 's/^/  /' >&2

    if [[ -t 0 && -t 2 ]]; then
        printf 'Repair now with %s? [Y/n] ' "$repair_cmd" >&2
        read -r reply || reply=n
        case "$reply" in
            ''|y|Y|yes|YES)
                case "$repair_cmd" in
                    refresh_vimrc)
                        # Interactive repair uses default options.
                        # shellcheck disable=SC2119
                        refresh_vimrc
                        ;;
                    refresh_iterm_settings)
                        # Interactive repair uses default options.
                        # shellcheck disable=SC2119
                        refresh_iterm_settings
                        ;;
                    'refresh_init_files --no-dev') refresh_init_files --no-dev ;;
                    *) refresh_init_files ;;
                esac
                return $?
                ;;
            *)
                printf 'Skipped. Run: %s\n' "$repair_cmd" >&2
                ;;
        esac
    else
        printf 'Run: %s\n' "$repair_cmd" >&2
    fi
    return 0
}

# Print a hard-to-miss tip when ./provision_init_files should be re-run for tool paths.
# Arg: same as _init_files_tools_reinstall_reasons ("all" | "broken").
_init_files_warn_tools_reinstall_if_needed()
{
    local mode="${1:-all}"
    local reasons clone_dir
    reasons="$(_init_files_tools_reinstall_reasons "$mode" 2>/dev/null || true)"
    [[ -n "$reasons" ]] || return 0
    clone_dir="${init_files_dir:-${XDG_DATA_HOME:-$HOME/.local/share}/init-files}"
    printf 'init-files: tool paths look stale or broken:\n' >&2
    printf '%s\n' "$reasons" | sed 's/^/  /' >&2
    printf '  Fix: %s/provision_init_files && source ~/.bashrc\n' "$clone_dir" >&2
    printf '  (or: refresh_init_files — pulls main and always provisions)\n' >&2
}

function refresh_init_files()
{
    local force=1
    local quiet=0
    local no_dev=0
    local dev_mode_explicit=0
    local github_https=0
    local github_transport_explicit=0
    local skip_iterm=0
    local iterm_flag_explicit=0
    local now last remote_url src dest current previous_head new_head new_head_short previous_head_short
    local provision_cmd provision_args
    local no_dev_flag github_https_flag github_ssh_flag
    local tools_file="${init_files_tools_file:-${XDG_CONFIG_HOME:-$HOME/.config}/init-files/tools.${init_files_host:-$(hostname -s 2>/dev/null || echo host)}}"
    local needs_reload=0
    local remote_head local_short remote_short
    local reply fetch_err fetch_err_file fetch_ok

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force) force=1; shift ;;
            -q|--quiet) quiet=1; force=0; shift ;;
            --no-dev) no_dev=1; dev_mode_explicit=1; shift ;;
            --dev) no_dev=0; dev_mode_explicit=1; shift ;;
            --github-https) github_https=1; github_transport_explicit=1; shift ;;
            --github-ssh) github_https=0; github_transport_explicit=1; shift ;;
            --iterm) skip_iterm=0; iterm_flag_explicit=1; shift ;;
            --no-iterm) skip_iterm=1; iterm_flag_explicit=1; shift ;;
            -h|--help)
                echo "Usage: refresh_init_files [-f|--force] [-q|--quiet] [--no-dev|--dev]" >&2
                echo "                     [--github-https|--github-ssh] [--iterm|--no-iterm]" >&2
                echo "  Default / -f: pull init-files main into $init_files_dir," >&2
                echo "  ensure ~/.bashrc is a symlink, always run provision_init_files" >&2
                echo "  (tools, ssh, vimrc), merge curated iTerm2 prefs on macOS," >&2
                echo "  and reload ~/.bashrc in this shell." >&2
                echo "  -q        daily check: if origin/main moved, offer to update;" >&2
                echo "            also private config overlay (URL drift / main moved);" >&2
                echo "            also detect local deploy drift (bashrc/vim/iTerm/" >&2
                echo "            login hook/tools) and offer repair (no auto-apply)." >&2
                echo "            Failed ls-remote is flagged; TTY offers retry" >&2
                echo "            (may run cache_ssh). Continues overlay/drift checks." >&2
                echo "            Does not apply iTerm prefs unless you accept." >&2
                echo "  --no-dev  after pull, provision --no-dev and remember THIS" >&2
                echo "            host as non-dev (no-dev.<hostname>; NFS-safe)." >&2
                echo "  --dev     after pull, full provision; clear this host's non-dev mode." >&2
                echo "  --github-https  remember HTTPS for GitHub on THIS host; clear" >&2
                echo "            https→ssh insteadOf; re-run provision." >&2
                echo "  --github-ssh    remember SSH (insteadOf) for THIS host; re-run" >&2
                echo "            provision. Without this, gh auth auto-prefers HTTPS." >&2
                echo "  --iterm   after provision, merge curated iTerm2 prefs (macOS;" >&2
                echo "            default on Darwin when not -q)." >&2
                echo "  --no-iterm  skip curated iTerm2 prefs merge on macOS." >&2
                echo "  Plain refresh keeps remembered non-dev / transport prefs." >&2
                return 0
                ;;
            *)
                echo "ERROR: refresh_init_files: unknown option: $1" >&2
                return 1
                ;;
        esac
    done

    # Remembered per-host mode (default when neither --dev nor --no-dev given).
    if type _init_files_migrate_no_dev_flag > /dev/null 2>&1; then
        _init_files_migrate_no_dev_flag
        no_dev_flag="$init_files_no_dev_flag"
    else
        no_dev_flag="${init_files_no_dev_flag:-${XDG_CONFIG_HOME:-$HOME/.config}/init-files/no-dev.${init_files_host:-$(hostname -s 2>/dev/null || echo host)}}"
    fi
    if [[ $dev_mode_explicit -eq 0 && -f "$no_dev_flag" ]]; then
        no_dev=1
    fi

    github_https_flag="${init_files_github_https_flag:-${XDG_CONFIG_HOME:-$HOME/.config}/init-files/github-https.${init_files_host:-host}}"
    github_ssh_flag="${init_files_github_ssh_flag:-${XDG_CONFIG_HOME:-$HOME/.config}/init-files/github-ssh.${init_files_host:-host}}"
    if [[ $github_transport_explicit -eq 1 ]]; then
        mkdir -p "$(dirname "$github_https_flag")" 2>/dev/null || true
        if [[ $github_https -eq 1 ]]; then
            printf '1\n' > "$github_https_flag" || true
            rm -f "$github_ssh_flag" 2>/dev/null || true
        else
            rm -f "$github_https_flag" 2>/dev/null || true
            printf '1\n' > "$github_ssh_flag" || true
        fi
    elif [[ -f "$github_https_flag" ]]; then
        github_https=1
    elif [[ -f "$github_ssh_flag" ]]; then
        github_https=0
    elif type _init_files_gh_authenticated > /dev/null 2>&1 && _init_files_gh_authenticated; then
        github_https=1
    fi

    # Match insteadOf / origin URL to this host before any fetch.
    if type _init_files_apply_github_transport > /dev/null 2>&1; then
        _init_files_apply_github_transport
    fi

    # Prefer provision-recorded git; fall back to PATH (NFS legacy tools / pre-provision).
    if [[ -z "${init_tool_git:-}" || ! -x "$init_tool_git" ]]; then
        init_tool_git="$(command -v git 2>/dev/null || true)"
    fi
    [[ -n "${init_tool_git:-}" && -x "$init_tool_git" ]] || {
        [[ $quiet -eq 1 ]] || echo "refresh_init_files: git not available (run provision_init_files)" >&2
        return 1
    }

    mkdir -p "$init_files_state_dir" || return 1
    now=$(date +%s)

    # Quiet daily path: compare local HEAD to origin/main; when behind, offer
    # to pull (interactive prompt) or print a hint (non-TTY).
    if [[ $quiet -eq 1 && $force -eq 0 && $dev_mode_explicit -eq 0 && $github_transport_explicit -eq 0 && $iterm_flag_explicit -eq 0 ]]; then
        if [[ -r "$init_files_check_stamp" ]]; then
            last=$(cat "$init_files_check_stamp" 2>/dev/null || echo 0)
            if [[ "$last" =~ ^[0-9]+$ ]] && (( now - last < init_files_max_age_seconds )); then
                return 0
            fi
        fi
        printf '%s\n' "$now" > "$init_files_check_stamp"

        if [[ ! -d "$init_files_dir/.git" ]]; then
            echo "init-files: clone missing at $init_files_dir" >&2
            if [[ -t 0 && -t 2 ]]; then
                printf 'Clone/update now with refresh_init_files? [Y/n] ' >&2
                read -r reply || reply=n
                case "$reply" in
                    ''|y|Y|yes|YES) refresh_init_files; return $? ;;
                    *) echo "Skipped. Run: refresh_init_files" >&2 ;;
                esac
            else
                echo "Run: refresh_init_files" >&2
            fi
            return 0
        fi

        previous_head=$("$init_tool_git" -C "$init_files_dir" rev-parse HEAD 2>/dev/null || true)
        # BatchMode: never block startup on passphrase / host-key prompts.
        # HTTPS hosts use credential helper / gh; SSH hosts need a loaded key.
        remote_head="$(_init_files_probe_origin_main "$init_files_dir" "$init_tool_git" 2>/dev/null || true)"
        while [[ -z "$remote_head" ]]; do
            if _init_files_offer_remote_check_retry 'init-files'; then
                remote_head="$(_init_files_probe_origin_main "$init_files_dir" "$init_tool_git" 2>/dev/null || true)"
                continue
            fi
            break
        done
        if [[ -n "$remote_head" && -n "$previous_head" && "$previous_head" != "$remote_head" ]]; then
            local_short=$("$init_tool_git" -C "$init_files_dir" rev-parse --short HEAD 2>/dev/null || echo "?")
            remote_short=$(printf '%.7s' "$remote_head")
            echo "init-files: main has moved (local $local_short → $remote_short)." >&2
            if [[ $no_dev -eq 1 ]]; then
                echo "  (this host is in remembered --no-dev mode)" >&2
            fi
            if [[ $github_https -eq 1 ]]; then
                echo "  (this host uses remembered GitHub HTTPS)" >&2
            fi
            if [[ -t 0 && -t 2 ]]; then
                printf 'Update now? [Y/n] ' >&2
                read -r reply || reply=n
                case "$reply" in
                    ''|y|Y|yes|YES)
                        if [[ $no_dev -eq 1 ]]; then
                            refresh_init_files --no-dev
                        else
                            refresh_init_files
                        fi
                        return $?
                        ;;
                    *)
                        echo "Skipped. Run refresh_init_files later to update." >&2
                        ;;
                esac
            else
                if [[ $no_dev -eq 1 ]]; then
                    echo "Run: refresh_init_files --no-dev" >&2
                else
                    echo "Run: refresh_init_files" >&2
                fi
            fi
        fi
        # Daily -q: private config overlay moved or URL drifted (even if init-files
        # remote check failed — do not skip the overlay probe).
        if type _init_files_offer_private_config_update > /dev/null 2>&1; then
            _init_files_offer_private_config_update || true
        fi
        # Daily -q: offer repair when bashrc/vim/iTerm/login/tools drifted locally.
        if type _init_files_offer_deploy_repairs > /dev/null 2>&1; then
            _init_files_offer_deploy_repairs
        elif type _init_files_warn_tools_reinstall_if_needed > /dev/null 2>&1; then
            _init_files_warn_tools_reinstall_if_needed broken
        fi
        return 0
    fi

    previous_head=
    if [[ -d "$init_files_dir/.git" ]]; then
        previous_head=$("$init_tool_git" -C "$init_files_dir" rev-parse HEAD 2>/dev/null || true)
    fi

    if [[ ! -d "$init_files_dir/.git" ]]; then
        mkdir -p "$(dirname "$init_files_dir")" || return 1
        if [[ $github_https -eq 1 ]]; then
            if ! _init_files_git_https "$init_tool_git" clone --depth 1 --branch main "$init_files_repo" "$init_files_dir" >/dev/null 2>&1; then
                if [[ $quiet -eq 0 ]]; then
                    echo "refresh_init_files: failed to clone $init_files_repo" >&2
                    echo "  Fix credentials, then retry: gh auth login && refresh_init_files --github-https" >&2
                fi
                return 1
            fi
        else
            if ! "$init_tool_git" clone --depth 1 --branch main "$init_files_repo" "$init_files_dir" >/dev/null 2>&1; then
                if [[ $quiet -eq 0 ]]; then
                    if type _init_files_print_github_ssh_auth_help > /dev/null 2>&1; then
                        _init_files_print_github_ssh_auth_help refresh_init_files
                    else
                        echo "refresh_init_files: failed to clone $init_files_repo" >&2
                    fi
                fi
                return 1
            fi
        fi
    else
        # Use configured URL (not insteadOf-rewritten get-url).
        remote_url=$("$init_tool_git" -C "$init_files_dir" config --get remote.origin.url 2>/dev/null || true)
        if [[ -n "$remote_url" && "$remote_url" != "$init_files_repo" ]]; then
            "$init_tool_git" -C "$init_files_dir" remote set-url origin "$init_files_repo" >/dev/null 2>&1 || true
        fi
        fetch_err_file="${TMPDIR:-/tmp}/init-files-fetch.err.$$"
        if [[ $github_https -eq 1 ]]; then
            fetch_ok=0
            if _init_files_git_https "$init_tool_git" -C "$init_files_dir" fetch --quiet origin main 2>"$fetch_err_file"; then
                fetch_ok=1
            elif type _init_files_ensure_github_https_creds > /dev/null 2>&1; then
                # Helper may be missing/stale; re-point at gh and retry once.
                git config --global --unset-all credential.https://github.com.helper 2>/dev/null || true
                _init_files_ensure_github_https_creds
                : > "$fetch_err_file"
                if _init_files_git_https "$init_tool_git" -C "$init_files_dir" fetch --quiet origin main 2>"$fetch_err_file"; then
                    fetch_ok=1
                fi
            fi
        else
            fetch_ok=0
            if "$init_tool_git" -C "$init_files_dir" fetch --quiet origin main 2>"$fetch_err_file"; then
                fetch_ok=1
            fi
        fi
        if [[ $fetch_ok -eq 0 ]]; then
            fetch_err=$(cat "$fetch_err_file" 2>/dev/null || true)
            rm -f "$fetch_err_file" 2>/dev/null || true
            if [[ $quiet -eq 0 ]]; then
                if printf '%s' "$fetch_err" | command grep -qiE 'permission denied|publickey|could not read from remote|authentication failed|401|403|terminal prompts disabled'; then
                    if [[ $github_https -eq 1 ]]; then
                        echo "refresh_init_files: git fetch failed (GitHub HTTPS auth)." >&2
                        echo "  Fix credentials, then retry:" >&2
                        echo "    gh auth login" >&2
                        echo "    ~/.local/share/init-files/provision_init_files --github-https" >&2
                        echo "    refresh_init_files" >&2
                    elif type _init_files_print_github_ssh_auth_help > /dev/null 2>&1; then
                        _init_files_print_github_ssh_auth_help refresh_init_files
                    else
                        echo "refresh_init_files: git fetch failed (GitHub SSH auth)." >&2
                        echo "  Load the passphrase key, then retry:" >&2
                        echo "    cache_ssh" >&2
                        echo "    refresh_init_files" >&2
                    fi
                elif printf '%s' "$fetch_err" | command grep -qiE 'could not resolve|network|timed out|offline|nodename'; then
                    echo "refresh_init_files: fetch failed (network/offline); keeping current clone" >&2
                else
                    echo "refresh_init_files: fetch failed; keeping current clone" >&2
                    [[ -n "$fetch_err" ]] && printf '%s\n' "$fetch_err" | command sed 's/^/  /' >&2
                fi
            fi
            printf '%s\n' "$now" > "$init_files_check_stamp"
            return 1
        fi
        rm -f "$fetch_err_file" 2>/dev/null || true
        if ! "$init_tool_git" -C "$init_files_dir" merge --ff-only --quiet FETCH_HEAD 2>/dev/null; then
            "$init_tool_git" -C "$init_files_dir" reset --hard origin/main >/dev/null 2>&1 || {
                [[ $quiet -eq 1 ]] || echo "refresh_init_files: failed to update local clone" >&2
                return 1
            }
        fi
    fi

    printf '%s\n' "$now" > "$init_files_check_stamp"

    src="$init_files_dir/$init_files_bashrc_src"
    dest="${HOME}/.bashrc"
    if [[ ! -f "$src" ]]; then
        [[ $quiet -eq 1 ]] || echo "refresh_init_files: missing $src" >&2
        return 1
    fi

    # Ensure ~/.bashrc points at the clone (no copy). Editing ~/.bashrc edits the repo file.
    if [[ -L "$dest" ]]; then
        current=$(readlink "$dest" 2>/dev/null || true)
        if [[ "$current" != "$src" ]]; then
            rm -f "$dest" || return 1
            ln -s "$src" "$dest" || return 1
            [[ $quiet -eq 1 ]] || echo "refresh_init_files: repaired ~/.bashrc -> $src"
        fi
    elif [[ -e "$dest" ]]; then
        if [[ ! -f "$dest" ]]; then
            [[ $quiet -eq 1 ]] || echo "refresh_init_files: $dest exists and is not a file/symlink" >&2
            return 1
        fi
        # Migrate leftover copies from the old install model.
        cp -p "$dest" "${dest}.bak.$(date +%Y%m%d-%H%M%S)" || return 1
        rm -f "$dest" || return 1
        ln -s "$src" "$dest" || return 1
        [[ $quiet -eq 1 ]] || echo "refresh_init_files: replaced ~/.bashrc copy with symlink -> $src"
    else
        ln -s "$src" "$dest" || return 1
        [[ $quiet -eq 1 ]] || echo "refresh_init_files: linked ~/.bashrc -> $src"
    fi

    new_head=$("$init_tool_git" -C "$init_files_dir" rev-parse HEAD 2>/dev/null || true)
    new_head_short=$("$init_tool_git" -C "$init_files_dir" rev-parse --short HEAD 2>/dev/null || true)
    previous_head_short=
    if [[ -n "$previous_head" ]]; then
        previous_head_short=$("$init_tool_git" -C "$init_files_dir" rev-parse --short "$previous_head" 2>/dev/null || printf '%.7s' "$previous_head")
    fi
    if [[ $quiet -eq 0 ]]; then
        local tone reset commit_subject commit_date commit_epoch commit_age
        tone=
        reset=
        if [[ -t 1 ]]; then
            reset=$'\033[0m'
        fi
        commit_subject=
        commit_date=
        commit_epoch=
        commit_age=
        if [[ -n "$new_head" ]]; then
            {
                IFS= read -r commit_subject
                IFS= read -r commit_date
                IFS= read -r commit_epoch
            } < <("$init_tool_git" -C "$init_files_dir" log -1 --format=$'%s\n%ci\n%ct' "$new_head" 2>/dev/null)
            commit_age=$(_init_relative_age "$commit_epoch")
        fi
        if [[ -n "$previous_head" && -n "$new_head" && "$previous_head" != "$new_head" ]]; then
            [[ -t 1 ]] && tone=$'\033[33m'  # yellow: pulled an update
            printf '%srefresh_init_files: updated init-files %s → %s%s\n' \
                "$tone" "$previous_head_short" "$new_head_short" "$reset"
        elif [[ -n "$new_head_short" ]]; then
            [[ -t 1 ]] && tone=$'\033[32m'  # green: already current
            printf '%srefresh_init_files: init-files at %s (already current)%s\n' "$tone" "$new_head_short" "$reset"
        fi
        if [[ -n "$commit_subject" ]]; then
            printf '  %s\n' "$commit_subject"
        fi
        if [[ -n "$commit_date" ]]; then
            if [[ -n "$commit_age" ]]; then
                printf '  %s (%s)\n' "$commit_date" "$commit_age"
            else
                printf '  %s\n' "$commit_date"
            fi
        fi
    fi

    # Always provision after pull/clone: tools, ssh materials, vimrc, login hook.
    needs_reload=0
    if [[ -n "$previous_head" && -n "$new_head" && "$previous_head" != "$new_head" ]]; then
        needs_reload=1
    fi
    # Also reload when this shell is still on an older sourced revision (e.g. the
    # clone was updated in-place by a commit/push on the same host).
    if [[ -n "$new_head" && "$new_head" != "${INIT_FILES_BASHRC_LOADED_SHA:-}" ]]; then
        needs_reload=1
    fi

    provision_cmd="$init_files_dir/provision_init_files"
    if [[ ! -x "$provision_cmd" ]]; then
        [[ $quiet -eq 1 ]] || echo "refresh_init_files: missing $provision_cmd" >&2
        return 1
    fi
    provision_args=()
    # Keep provision interactive on a TTY so modern-macOS brew Y/n offers work,
    # even when refresh itself was started via -q (daily path after Update now?).
    if [[ $quiet -eq 1 && ! ( -t 0 && -t 2 ) ]]; then
        provision_args+=(-q)
    fi
    if [[ $no_dev -eq 1 ]]; then
        provision_args+=(--no-dev)
    else
        provision_args+=(--dev)
    fi
    if [[ $github_transport_explicit -eq 1 ]]; then
        if [[ $github_https -eq 1 ]]; then
            provision_args+=(--github-https)
        else
            provision_args+=(--github-ssh)
        fi
    elif [[ -f "$github_https_flag" ]]; then
        provision_args+=(--github-https)
    elif [[ -f "$github_ssh_flag" ]]; then
        provision_args+=(--github-ssh)
    elif [[ $github_https -eq 1 ]]; then
        # gh-authenticated auto-prefer (no remembered flag yet)
        provision_args+=(--github-https)
    fi
    if [[ $skip_iterm -eq 1 ]]; then
        provision_args+=(--no-iterm)
    fi
    [[ $quiet -eq 1 ]] || echo "refresh_init_files: running ${provision_cmd##*/} ${provision_args[*]}"
    if [[ $quiet -eq 0 && $no_dev -eq 1 && $dev_mode_explicit -eq 0 ]]; then
        echo "refresh_init_files: using remembered --no-dev mode for this host"
    fi
    if [[ $quiet -eq 0 && $github_https -eq 1 && $github_transport_explicit -eq 0 ]]; then
        if [[ -f "$github_https_flag" ]]; then
            echo "refresh_init_files: using remembered GitHub HTTPS for this host"
        else
            echo "refresh_init_files: gh authenticated — preferring GitHub HTTPS for this host"
        fi
    fi
    if ! "$provision_cmd" "${provision_args[@]}"; then
        [[ $quiet -eq 1 ]] || echo "refresh_init_files: provision failed" >&2
        return 1
    fi
    needs_reload=1

    # macOS: merge curated iTerm prefs by default (not under -q; --no-iterm skips).
    if [[ $quiet -eq 0 && $skip_iterm -eq 0 ]] \
        && type _init_is_darwin > /dev/null 2>&1 && _init_is_darwin
    then
        if type refresh_iterm_settings > /dev/null 2>&1; then
            echo "refresh_init_files: refreshing iTerm2 settings"
            # Refresh uses default options here.
            # shellcheck disable=SC2119
            if ! refresh_iterm_settings; then
                echo "refresh_init_files: iTerm2 refresh failed" >&2
                return 1
            fi
        else
            echo "refresh_init_files: iTerm refresh skipped (refresh_iterm_settings unavailable)" >&2
        fi
    fi

    # Pick up new bashrc / tools in this shell (avoids a manual source after
    # refresh). Guard prevents recursion when bashrc's daily -q calls us.
    if [[ $needs_reload -eq 1 && $- == *i* && -z "${_init_files_in_refresh_reload:-}" ]]; then
        _init_files_in_refresh_reload=1
        INIT_FILES_BASHRC_FORCE=1
        # The deployed bashrc path is runtime-generated.
        # shellcheck disable=SC1091
        if . "${HOME}/.bashrc"; then
            [[ $quiet -eq 1 ]] || echo "refresh_init_files: reloaded ~/.bashrc in this shell"
        fi
        unset _init_files_in_refresh_reload
    fi

    return 0
}

# --- iTerm2 curated prefs (macOS only): export / upload / refresh ---------------

function _init_iterm2_dir()
{
    local dir="${init_files_dir:-${XDG_DATA_HOME:-$HOME/.local/share}/init-files}/iterm2"
    printf '%s' "$dir"
}

function _init_iterm2_require()
{
    local dir

    if ! type _init_is_darwin > /dev/null 2>&1 || ! _init_is_darwin; then
        printf '%s: macOS only\n' "${1:-iterm2}" >&2
        return 1
    fi

    dir="$(_init_iterm2_dir)"
    if [[ ! -x "$dir/export" || ! -x "$dir/install" || ! -x "$dir/test" || ! -f "$dir/_prefs.py" ]]; then
        printf '%s: missing iterm2 scripts under %s (refresh_init_files?)\n' "${1:-iterm2}" "$dir" >&2
        return 1
    fi
    return 0
}

function _init_iterm2_git()
{
    if [[ -n "${init_tool_git:-}" && -x "${init_tool_git:-}" ]]; then
        printf '%s' "$init_tool_git"
        return 0
    fi
    command -v git 2>/dev/null || return 1
}

function _init_iterm2_python()
{
    if [[ -n "${init_tool_python3:-}" && -x "${init_tool_python3:-}" ]]; then
        printf '%s' "$init_tool_python3"
        return 0
    fi
    command -v python3 2>/dev/null || return 1
}

function _init_iterm2_git_run()
{
    local git_bin="$1" dir="$2" url
    shift 2

    url="$("$git_bin" -C "$dir" remote get-url origin 2>/dev/null || true)"
    if [[ "$url" == https://* ]] && type _init_files_git_https > /dev/null 2>&1; then
        _init_files_git_https "$git_bin" -C "$dir" "$@"
        return $?
    fi
    GIT_TERMINAL_PROMPT=0 "$git_bin" -C "$dir" "$@"
}

function _init_iterm2_live_curated()
{
    # Write live curated prefs to $1 (path).
    local out="$1"
    local dir py tmp_raw

    dir="$(_init_iterm2_dir)"
    py="$(_init_iterm2_python)" || return 1
    tmp_raw="$(mktemp -t iterm2-live-raw.XXXXXX)" || return 1
    if ! defaults export com.googlecode.iterm2 "$tmp_raw" 2>/dev/null; then
        rm -f "$tmp_raw"
        printf 'cannot export com.googlecode.iterm2 (launch iTerm once?)\n' >&2
        return 1
    fi
    if ! "$py" "$dir/_prefs.py" curate "$tmp_raw" "$out"; then
        rm -f "$tmp_raw"
        return 1
    fi
    rm -f "$tmp_raw"
    return 0
}

function export_iterm_settings()
{
    _init_iterm2_require export_iterm_settings || return 1
    "$(_init_iterm2_dir)/export"
}

function test_iterm_settings()
{
    local dir repo_dir git_bin remote_plist remote_meta
    local use_origin=1 rc=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --local)
                use_origin=0
                shift
                ;;
            -h|--help)
                cat <<'EOF'
Usage: test_iterm_settings [--local]

Backup live iTerm2 prefs, apply curated prefs from origin/main (or --local
clone files), verify fonts/app/merge. On failure, restore the backup. Soft
iTerm version mismatch only warns.
EOF
                return 0
                ;;
            *)
                printf 'test_iterm_settings: unknown option: %s\n' "$1" >&2
                return 1
                ;;
        esac
    done

    _init_iterm2_require test_iterm_settings || return 1

    dir="$(_init_iterm2_dir)"
    repo_dir="$(cd "$dir/.." && pwd)"

    if [[ $use_origin -eq 1 ]]; then
        git_bin="$(_init_iterm2_git)" || {
            printf 'test_iterm_settings: git not found (pass --local to use clone files)\n' >&2
            return 1
        }
        if [[ ! -d "$repo_dir/.git" ]]; then
            printf 'test_iterm_settings: %s is not a git clone (pass --local)\n' "$repo_dir" >&2
            return 1
        fi
        if ! _init_iterm2_git_run "$git_bin" "$repo_dir" fetch --quiet origin main; then
            printf 'test_iterm_settings: git fetch failed (pass --local to skip)\n' >&2
            if type _init_files_print_github_ssh_auth_help > /dev/null 2>&1; then
                _init_files_print_github_ssh_auth_help test_iterm_settings
            fi
            return 1
        fi
        remote_plist="$(mktemp -t iterm2-test-remote.XXXXXX)" || return 1
        remote_meta="$(mktemp -t iterm2-test-meta.XXXXXX)" || {
            rm -f "$remote_plist"
            return 1
        }
        if ! "$git_bin" -C "$repo_dir" show "origin/main:iterm2/com.googlecode.iterm2.plist" \
            > "$remote_plist" 2>/dev/null; then
            rm -f "$remote_plist" "$remote_meta"
            printf 'test_iterm_settings: iterm2 prefs not on origin/main yet\n' >&2
            return 1
        fi
        if "$git_bin" -C "$repo_dir" show "origin/main:iterm2/meta.json" \
            > "$remote_meta" 2>/dev/null; then
            "$dir/test" --plist "$remote_plist" --meta "$remote_meta"
            rc=$?
        else
            rm -f "$remote_meta"
            remote_meta=
            "$dir/test" --plist "$remote_plist"
            rc=$?
        fi
        rm -f "$remote_plist" ${remote_meta:+"$remote_meta"}
        return "$rc"
    fi

    "$dir/test"
}

# This interactive helper has optional flags.
# shellcheck disable=SC2120
function refresh_iterm_settings()
{
    local dir repo_dir git_bin py live_tmp remote_tmp
    local force=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force) force=1; shift ;;
            -h|--help)
                cat <<'EOF'
Usage: refresh_iterm_settings [-f|--force]

Fetch origin/main's curated iTerm2 prefs and merge them into this Mac when
live curated settings differ. Refuses if you have a local uncommitted export
unless -f is passed. Always checks for Meslo LG Nerd Font and, on a TTY,
offers `iterm2/install_meslo_nerd_font` (Meslo.zip → ~/Library/Fonts, no sudo).
EOF
                return 0
                ;;
            *)
                printf 'refresh_iterm_settings: unknown option: %s\n' "$1" >&2
                return 1
                ;;
        esac
    done

    _init_iterm2_require refresh_iterm_settings || return 1

    dir="$(_init_iterm2_dir)"
    repo_dir="$(cd "$dir/.." && pwd)"
    git_bin="$(_init_iterm2_git)" || {
        printf 'refresh_iterm_settings: git not found\n' >&2
        return 1
    }
    py="$(_init_iterm2_python)" || {
        printf 'refresh_iterm_settings: python3 not found\n' >&2
        return 1
    }

    if [[ ! -d "$repo_dir/.git" ]]; then
        printf 'refresh_iterm_settings: %s is not a git clone\n' "$repo_dir" >&2
        return 1
    fi

    if [[ $force -eq 0 ]] \
        && ! "$git_bin" -C "$repo_dir" diff --quiet -- "iterm2/com.googlecode.iterm2.plist" 2>/dev/null; then
        printf 'refresh_iterm_settings: uncommitted local export of iterm2 prefs\n' >&2
        printf '  upload with upload_iterm_settings, or discard, or pass -f\n' >&2
        return 1
    fi

    if ! _init_iterm2_git_run "$git_bin" "$repo_dir" fetch --quiet origin main; then
        printf 'refresh_iterm_settings: git fetch failed\n' >&2
        if type _init_files_print_github_ssh_auth_help > /dev/null 2>&1; then
            _init_files_print_github_ssh_auth_help refresh_iterm_settings
        fi
        return 1
    fi

    remote_tmp="$(mktemp -t iterm2-remote.XXXXXX)" || return 1
    live_tmp="$(mktemp -t iterm2-live.XXXXXX)" || {
        rm -f "$remote_tmp"
        return 1
    }

    if ! "$git_bin" -C "$repo_dir" show "origin/main:iterm2/com.googlecode.iterm2.plist" \
        > "$remote_tmp" 2>/dev/null; then
        rm -f "$remote_tmp" "$live_tmp"
        printf 'refresh_iterm_settings: iterm2 prefs not on origin/main yet\n' >&2
        return 1
    fi

    if ! _init_iterm2_live_curated "$live_tmp"; then
        rm -f "$remote_tmp" "$live_tmp"
        return 1
    fi

    if "$py" "$dir/_prefs.py" equal "$live_tmp" "$remote_tmp"; then
        rm -f "$live_tmp"
        # Prefs already match — still offer Meslo Nerd Font if missing.
        "$dir/install" --ensure-fonts "$remote_tmp" || true
        rm -f "$remote_tmp"
        printf 'refresh_iterm_settings: live curated prefs already match origin/main\n'
        return 0
    fi

    # Install from the fetched blob — do not dirty the clone working tree.
    # install also offers user-local Meslo.zip when the profile font is missing.
    "$dir/install" "$remote_tmp"
    rm -f "$remote_tmp" "$live_tmp"
}

function upload_iterm_settings()
{
    local dir repo_dir git_bin py plist meta live_tmp
    local dirty=0 ahead=0

    _init_iterm2_require upload_iterm_settings || return 1

    dir="$(_init_iterm2_dir)"
    repo_dir="$(cd "$dir/.." && pwd)"
    plist="$dir/com.googlecode.iterm2.plist"
    meta="$dir/meta.json"
    git_bin="$(_init_iterm2_git)" || {
        printf 'upload_iterm_settings: git not found\n' >&2
        return 1
    }
    py="$(_init_iterm2_python)" || {
        printf 'upload_iterm_settings: python3 not found\n' >&2
        return 1
    }

    if [[ ! -d "$repo_dir/.git" ]]; then
        printf 'upload_iterm_settings: %s is not a git clone\n' "$repo_dir" >&2
        return 1
    fi
    if [[ ! -f "$plist" ]]; then
        printf 'upload_iterm_settings: missing %s (run export_iterm_settings first)\n' "$plist" >&2
        return 1
    fi

    live_tmp="$(mktemp -t iterm2-live.XXXXXX)" || return 1
    if _init_iterm2_live_curated "$live_tmp"; then
        if ! "$py" "$dir/_prefs.py" equal "$live_tmp" "$plist"; then
            printf 'upload_iterm_settings: live prefs differ from %s\n' "$plist" >&2
            printf '  run export_iterm_settings first, then upload again\n' >&2
            rm -f "$live_tmp"
            return 1
        fi
    fi
    rm -f "$live_tmp"

    if ! "$git_bin" -C "$repo_dir" diff --quiet -- \
            "iterm2/com.googlecode.iterm2.plist" "iterm2/meta.json" 2>/dev/null \
        || ! "$git_bin" -C "$repo_dir" diff --cached --quiet -- \
            "iterm2/com.googlecode.iterm2.plist" "iterm2/meta.json" 2>/dev/null; then
        dirty=1
    fi
    # Untracked meta.json counts as something to upload.
    if [[ -f "$meta" ]] \
        && ! "$git_bin" -C "$repo_dir" ls-files --error-unmatch -- "iterm2/meta.json" \
            >/dev/null 2>&1; then
        dirty=1
    fi

    # Ensure origin/main exists for ahead-count.
    _init_iterm2_git_run "$git_bin" "$repo_dir" fetch --quiet origin main 2>/dev/null || true
    if "$git_bin" -C "$repo_dir" rev-parse --verify origin/main >/dev/null 2>&1; then
        ahead="$("$git_bin" -C "$repo_dir" rev-list --count origin/main..HEAD 2>/dev/null || echo 0)"
    else
        ahead=0
    fi
    [[ "$ahead" =~ ^[0-9]+$ ]] || ahead=0

    if [[ $dirty -eq 0 && $ahead -eq 0 ]]; then
        printf 'upload_iterm_settings: nothing to upload\n'
        return 0
    fi

    if [[ $dirty -eq 1 ]]; then
        "$git_bin" -C "$repo_dir" add -- "iterm2/com.googlecode.iterm2.plist" || return 1
        [[ -f "$meta" ]] && "$git_bin" -C "$repo_dir" add -- "iterm2/meta.json"
        if ! "$git_bin" -C "$repo_dir" diff --cached --quiet -- \
            "iterm2/com.googlecode.iterm2.plist" "iterm2/meta.json"; then
            "$git_bin" -C "$repo_dir" commit -m "$(cat <<'EOF'
Update curated iTerm2 prefs (font/colors/keys/mouse).

EOF
)" || return 1
            printf 'upload_iterm_settings: committed iterm2 prefs\n'
        fi
    fi

    if ! _init_iterm2_git_run "$git_bin" "$repo_dir" push origin HEAD; then
        printf 'upload_iterm_settings: git push failed\n' >&2
        if type _init_files_print_github_ssh_auth_help > /dev/null 2>&1; then
            _init_files_print_github_ssh_auth_help upload_iterm_settings
        fi
        return 1
    fi
    printf 'upload_iterm_settings: pushed to origin\n'
}

# This interactive helper has optional flags.
# shellcheck disable=SC2120
function refresh_vimrc()
{
    local repo_dir vimrc_src vimrc_dest plug_path plug_url vim_bin curl_bin
    local backup_dir stamp current backup origin_url
    local update_plugins=1
    local fetch_repo=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-plugins)
                update_plugins=0
                shift
                ;;
            --fetch)
                fetch_repo=1
                shift
                ;;
            -h|--help)
                cat <<'EOF'
Usage: refresh_vimrc [--fetch] [--no-plugins]

Repair ~/.vimrc symlink into init-files, retire ~/.gvimrc (backed up; one-file
model), bootstrap vim-plug if needed, and run headless PlugInstall + PlugUpdate.
Backs up a non-canonical ~/.vimrc / ~/.gvimrc to ~/.vimrc.bak.<timestamp> /
~/.gvimrc.bak.<timestamp> and ~/.local/state/init-files/vim-backup/.

  --fetch       git fetch origin main (does not reset local commits)
  --no-plugins  skip PlugInstall/Update
EOF
                return 0
                ;;
            *)
                printf 'refresh_vimrc: unknown option: %s\n' "$1" >&2
                return 1
                ;;
        esac
    done

    repo_dir="${init_files_dir:-${XDG_DATA_HOME:-$HOME/.local/share}/init-files}"
    vimrc_src="$repo_dir/vim/vimrc"
    vimrc_dest="${HOME}/.vimrc"
    gvimrc_dest="${HOME}/.gvimrc"
    plug_path="${HOME}/.vim/autoload/plug.vim"
    plug_url='https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
    backup_dir="${XDG_STATE_HOME:-$HOME/.local/state}/init-files/vim-backup"

    if [[ ! -f "$vimrc_src" ]]; then
        printf 'refresh_vimrc: missing %s (refresh_init_files first?)\n' "$vimrc_src" >&2
        return 1
    fi

    if [[ $fetch_repo -eq 1 ]]; then
        if [[ -n "${init_tool_git:-}" && -x "${init_tool_git}" && -d "$repo_dir/.git" ]]; then
            if type _init_files_git_https > /dev/null 2>&1; then
                origin_url="$("$init_tool_git" -C "$repo_dir" remote get-url origin 2>/dev/null || true)"
                if [[ "$origin_url" == https://* ]]; then
                    _init_files_git_https "$init_tool_git" -C "$repo_dir" fetch --quiet origin main 2>/dev/null \
                        || printf 'refresh_vimrc: warning: git fetch failed\n' >&2
                else
                    GIT_TERMINAL_PROMPT=0 "$init_tool_git" -C "$repo_dir" fetch --quiet origin main 2>/dev/null \
                        || printf 'refresh_vimrc: warning: git fetch failed\n' >&2
                fi
            else
                "$init_tool_git" -C "$repo_dir" fetch --quiet origin main 2>/dev/null \
                    || printf 'refresh_vimrc: warning: git fetch failed\n' >&2
            fi
        fi
    fi

    # Symlink repair + backup of any previous user vimrc.
    if [[ -L "$vimrc_dest" ]]; then
        current=$(readlink "$vimrc_dest" 2>/dev/null || true)
        if [[ "$current" != "$vimrc_src" ]]; then
            stamp="$(date +%Y%m%d-%H%M%S)"
            mkdir -p "$backup_dir" 2>/dev/null || true
            printf '%s\n' "$current" > "${vimrc_dest}.bak.${stamp}.linktarget"
            printf '%s\n' "$current" > "${backup_dir}/vimrc.${stamp}.linktarget" 2>/dev/null || true
            rm -f "$vimrc_dest" || return 1
            ln -s "$vimrc_src" "$vimrc_dest" || return 1
            printf 'refresh_vimrc: repaired ~/.vimrc symlink -> %s\n' "$vimrc_src"
        fi
    elif [[ -f "$vimrc_dest" ]]; then
        stamp="$(date +%Y%m%d-%H%M%S)"
        backup="${vimrc_dest}.bak.${stamp}"
        mkdir -p "$backup_dir" 2>/dev/null || true
        cp -p "$vimrc_dest" "$backup" || return 1
        cp -p "$vimrc_dest" "${backup_dir}/vimrc.${stamp}" 2>/dev/null || true
        rm -f "$vimrc_dest" || return 1
        ln -s "$vimrc_src" "$vimrc_dest" || return 1
        printf 'refresh_vimrc: backed up previous ~/.vimrc -> %s\n' "$backup"
        printf 'refresh_vimrc: linked ~/.vimrc -> %s\n' "$vimrc_src"
    elif [[ ! -e "$vimrc_dest" ]]; then
        ln -s "$vimrc_src" "$vimrc_dest" || return 1
        printf 'refresh_vimrc: linked ~/.vimrc -> %s\n' "$vimrc_src"
    else
        printf 'refresh_vimrc: ~/.vimrc exists and is not a file/symlink\n' >&2
        return 1
    fi

    # One-file model: GUI settings are in vim/vimrc. Retire ~/.gvimrc so it
    # cannot override (MacVim loads it after vimrc).
    if [[ -e "$gvimrc_dest" || -L "$gvimrc_dest" ]]; then
        stamp="$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir" 2>/dev/null || true
        if [[ -L "$gvimrc_dest" ]]; then
            current=$(readlink "$gvimrc_dest" 2>/dev/null || true)
            printf '%s\n' "$current" > "${gvimrc_dest}.bak.${stamp}.linktarget"
            printf '%s\n' "$current" > "${backup_dir}/gvimrc.${stamp}.linktarget" 2>/dev/null || true
            rm -f "$gvimrc_dest" || return 1
            printf 'refresh_vimrc: retired ~/.gvimrc symlink (was -> %s)\n' "$current"
        elif [[ -f "$gvimrc_dest" ]]; then
            cp -p "$gvimrc_dest" "${gvimrc_dest}.bak.${stamp}" || return 1
            cp -p "$gvimrc_dest" "${backup_dir}/gvimrc.${stamp}" 2>/dev/null || true
            rm -f "$gvimrc_dest" || return 1
            printf 'refresh_vimrc: retired ~/.gvimrc -> %s\n' "${gvimrc_dest}.bak.${stamp}"
        else
            printf 'refresh_vimrc: ~/.gvimrc exists and is not a file/symlink\n' >&2
            return 1
        fi
    fi

    if [[ ! -f "$plug_path" ]]; then
        curl_bin="$(command -v curl 2>/dev/null || true)"
        [[ -n "$curl_bin" ]] || {
            printf 'refresh_vimrc: curl required to bootstrap vim-plug\n' >&2
            return 1
        }
        mkdir -p "$(dirname "$plug_path")" || return 1
        if ! "$curl_bin" -fsSL --connect-timeout 10 --max-time 60 -o "$plug_path" "$plug_url"; then
            printf 'refresh_vimrc: failed to download vim-plug\n' >&2
            rm -f "$plug_path"
            return 1
        fi
        printf 'refresh_vimrc: installed vim-plug\n'
    fi

    mkdir -p "${HOME}/.vim/plugged" "${HOME}/.vim/undo" 2>/dev/null || true

    if [[ $update_plugins -eq 1 ]]; then
        if [[ -n "${init_tool_vim:-}" && -x "${init_tool_vim}" ]]; then
            vim_bin="$init_tool_vim"
        else
            vim_bin="$(command -v vim 2>/dev/null || true)"
        fi
        [[ -n "$vim_bin" ]] || {
            printf 'refresh_vimrc: vim not found\n' >&2
            return 1
        }
        # Prefer --not-a-term when available (Vim 8.2+) to avoid TTY plugin UI.
        if ! "$vim_bin" -n --not-a-term -u "$vimrc_dest" \
            +PlugInstall +PlugUpdate +qall </dev/null >/dev/null 2>&1 \
            && ! "$vim_bin" -n -u "$vimrc_dest" \
            +PlugInstall +PlugUpdate +qall </dev/null >/dev/null 2>&1; then
            printf 'refresh_vimrc: PlugInstall/Update failed\n' >&2
            return 1
        fi
        printf 'refresh_vimrc: plugins installed/updated\n'
    fi

    # Soft font hint (same tiers as iterm2/install).
    if type _init_is_darwin > /dev/null 2>&1 && _init_is_darwin; then
        if type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos; then
            printf 'refresh_vimrc: note: glyphs need a Nerd Font — run iterm2/install_meslo_nerd_font (Meslo.zip → ~/Library/Fonts)\n'
        else
            printf 'refresh_vimrc: note: glyphs need Meslo Nerd Font in ~/Library/Fonts (no brew on this macOS tier)\n'
        fi
    else
        printf 'refresh_vimrc: note: glyphs need Meslo Nerd Font under ~/.local/share/fonts\n'
    fi
    printf 'refresh_vimrc: open a file in a git repo to confirm airline branch + gitgutter\n'
}

# --- Cursor Agent session recovery -------------------------------------------
# Parent shell that starts `agent` never sees CURSOR_CONVERSATION_ID. After a
# dead iTerm/SSH tab, disambiguate via agent_sessions (prompt + name + cwd) —
# never assume "most recent" when several sessions share a host.

# Force Auto + vim for every chat launch. In-chat /model switches rewrite
# ~/.cursor/cli-config.json; we reset that file before starting so the next
# session cannot inherit gpt-5.2 (etc.) or a disabled vimMode. Explicit
# --model on the CLI still wins.
# Optional: agent --name my-label …  (names the session once it gets an id)
# This helper accepts optional forwarded CLI arguments.
# shellcheck disable=SC2120
function _init_files_ensure_agent_model_auto()
{
    local py script
    py="$(command -v python3 2>/dev/null || true)"
    script="${init_files_dir:-${XDG_DATA_HOME:-$HOME/.local/share}/init-files}/cursor/ensure_model_auto.py"
    [[ -n "$py" && -f "$script" ]] || return 0
    "$py" "$script" "$@"
}

function _init_files_agent_pending_name_file()
{
    printf '%s' "${init_files_state_dir:-${XDG_STATE_HOME:-$HOME/.local/state}/init-files}/agent-session-pending-name"
}

function _init_files_set_agent_pending_name()
{
    local name="$1"
    local f
    f="$(_init_files_agent_pending_name_file)"
    mkdir -p "$(dirname "$f")" 2>/dev/null || true
    printf '%s\n' "$name" >"$f"
}

function _init_files_consume_agent_pending_name()
{
    local f name id
    f="$(_init_files_agent_pending_name_file)"
    [[ -f "$f" ]] || return 0
    name="$(tr -d '\r\n' <"$f")"
    rm -f "$f" 2>/dev/null || true
    [[ -n "$name" ]] || return 0
    id="${CURSOR_CONVERSATION_ID:-}"
    [[ -n "$id" ]] || return 0
    if type name_agent_session > /dev/null 2>&1; then
        name_agent_session "$name" "$id" >/dev/null 2>&1 || true
    fi
}

function agent()
{
    local bin a has_model=0 is_chat=1
    local -a args=()
    local pending_name=""
    bin="$(type -P agent 2>/dev/null || true)"
    [[ -n "$bin" ]] || {
        printf 'agent: Cursor agent CLI not found on PATH\n' >&2
        return 127
    }

    # Parse our --name / -N (not passed through to the CLI).
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name|-N)
                if [[ $# -lt 2 || -z "${2:-}" ]]; then
                    printf 'agent: %s requires a label\n' "$1" >&2
                    return 2
                fi
                pending_name="$2"
                shift 2
                ;;
            --name=*|-N=*)
                pending_name="${1#*=}"
                [[ -n "$pending_name" ]] || {
                    printf 'agent: --name requires a label\n' >&2
                    return 2
                }
                shift
                ;;
            --)
                shift
                args+=("$@")
                set --
                break
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done
    set -- "${args[@]}"

    case "${1:-}" in
        ls|models|login|logout|mcp|plugin|worker|status|whoami|about|update|\
        generate-rule|rule|install-shell-integration|\
        uninstall-shell-integration|help)
            "$bin" "$@"
            return
            ;;
        create-chat)
            # Reset config without forwarding agent arguments.
            # shellcheck disable=SC2119
            _init_files_ensure_agent_model_auto
            [[ -n "$pending_name" ]] && _init_files_set_agent_pending_name "$pending_name"
            "$bin" "$@"
            return
            ;;
        resume)
            # Reset config without forwarding agent arguments.
            # shellcheck disable=SC2119
            _init_files_ensure_agent_model_auto
            [[ -n "$pending_name" ]] && _init_files_set_agent_pending_name "$pending_name"
            "$bin" --model auto "$@"
            return
            ;;
        agent)
            shift
            ;;
    esac
    for a in "$@"; do
        case "$a" in
            --model|--model=*|--list-models)
                has_model=1
                ;;
            --help|-h|--version|-v)
                is_chat=0
                ;;
        esac
    done
    if [[ $is_chat -eq 1 ]]; then
        # Reset config without forwarding agent arguments.
        # shellcheck disable=SC2119
        _init_files_ensure_agent_model_auto
        [[ -n "$pending_name" ]] && _init_files_set_agent_pending_name "$pending_name"
    fi
    local rc=0
    if [[ $is_chat -eq 1 && $has_model -eq 0 ]]; then
        "$bin" --model auto "$@"
        rc=$?
    else
        "$bin" "$@"
        rc=$?
    fi
    if [[ $is_chat -eq 1 ]] && type clear_agent_iterm_badge > /dev/null 2>&1; then
        clear_agent_iterm_badge
    fi
    return "$rc"
}

function _init_files_agent_sessions_py()
{
    local repo_dir
    repo_dir="${init_files_dir:-${XDG_DATA_HOME:-$HOME/.local/share}/init-files}"
    printf '%s' "$repo_dir/cursor/agent_sessions.py"
}

function _init_files_agent_sessions_state_dir()
{
    printf '%s' "${init_files_state_dir:-${XDG_STATE_HOME:-$HOME/.local/state}/init-files}"
}

# Callers may optionally choose a starting process.
# shellcheck disable=SC2120
function _init_files_find_iterm_tty()
{
    # Only the tty for THIS process tree (this iTerm session). Never broadcast
    # to other agents/tabs.
    local pid="${1:-$$}" tty ppid path
    local i=0
    while [[ -n "$pid" && "$pid" -gt 1 && $i -lt 16 ]]; do
        tty="$(ps -o tty= -p "$pid" 2>/dev/null | tr -d '[:space:]')"
        if [[ -n "$tty" && "$tty" != "??" ]]; then
            path="/dev/$tty"
            if [[ -w "$path" ]]; then
                printf '%s' "$path"
                return 0
            fi
        fi
        ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d '[:space:]')"
        [[ -z "$ppid" || "$ppid" == "$pid" ]] && break
        pid="$ppid"
        i=$((i + 1))
    done
    return 1
}

function clear_agent_iterm_badge()
{
    # Clear any leftover corner badge (we no longer set one). Leave tab title.
    local ttydev b64
    command -v base64 >/dev/null 2>&1 || return 0
    ttydev="$(tty 2>/dev/null || true)"
    if [[ -z "$ttydev" || "$ttydev" == "not a tty" ]]; then
        ttydev="$(_init_files_find_iterm_tty 2>/dev/null || true)"
    fi
    [[ -n "$ttydev" && -w "$ttydev" ]] || return 0
    b64="$(printf '' | base64 | tr -d '\n')"
    printf '\033]1337;SetBadgeFormat=%s\007' "$b64" >"$ttydev" 2>/dev/null || true
}

function set_agent_iterm_badge()
{
    # Tab/window title only (OSC 0/1/2) — no corner badge. Works through SSH.
    local id="${1:-${CURSOR_CONVERSATION_ID:-}}"
    local short ttydev own label b64
    [[ -n "$id" ]] || return 0
    # Only while an agent chat is actually running in this tree.
    [[ -n "${CURSOR_AGENT:-}${CURSOR_CONVERSATION_ID:-}" ]] || return 0
    short="${id:0:8}"
    label="$short"
    ttydev="$(_init_files_find_iterm_tty 2>/dev/null || true)"
    if [[ -z "$ttydev" ]]; then
        own="$(ps -o tty= -p $$ 2>/dev/null | tr -d '[:space:]')"
        if [[ -n "$own" && "$own" != "??" && -w /dev/tty ]]; then
            ttydev=/dev/tty
        fi
    fi
    [[ -n "$ttydev" && -w "$ttydev" ]] || return 0
    printf '\033]0;%s\007' "$label" >"$ttydev" 2>/dev/null || true
    printf '\033]1;%s\007' "$label" >"$ttydev" 2>/dev/null || true
    printf '\033]2;%s\007' "$label" >"$ttydev" 2>/dev/null || true
    # Clear stale red badge from older init-files.
    if command -v base64 >/dev/null 2>&1; then
        b64="$(printf '' | base64 | tr -d '\n')"
        printf '\033]1337;SetBadgeFormat=%s\007' "$b64" >"$ttydev" 2>/dev/null || true
    fi
}


function _init_files_record_agent_session()
{
    local id="${1:-${CURSOR_CONVERSATION_ID:-}}"
    local cwd_val="${2:-${PWD:-}}"
    local py script

    [[ -n "$id" ]] || return 0
    py="$(command -v python3 2>/dev/null || true)"
    script="$(_init_files_agent_sessions_py)"
    [[ -n "$py" && -f "$script" ]] || return 0
    INIT_FILES_RECORD_HOST="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)" \
        "$py" "$script" record "$id" "$cwd_val" >/dev/null 2>&1 || true
    if type _init_files_consume_agent_pending_name > /dev/null 2>&1; then
        _init_files_consume_agent_pending_name
    fi
    if type set_agent_iterm_badge > /dev/null 2>&1; then
        set_agent_iterm_badge "$id"
    fi
}

function agent_sessions()
{
    local py script
    py="$(command -v python3 2>/dev/null || true)"
    script="$(_init_files_agent_sessions_py)"
    [[ -n "$py" && -f "$script" ]] || {
        printf 'agent_sessions: need python3 and %s\n' "$script" >&2
        return 1
    }
    "$py" "$script" list "$@"
}

function name_agent_session()
{
    local py script
    py="$(command -v python3 2>/dev/null || true)"
    script="$(_init_files_agent_sessions_py)"
    [[ -n "$py" && -f "$script" ]] || {
        printf 'name_agent_session: need python3 and %s\n' "$script" >&2
        return 1
    }
    "$py" "$script" name "$@"
}

function resume_agent_session()
{
    local target="${1:-}"
    local agent_bin id py script fzf_bin picked named_only=0
    local -a fzf_args=()

    agent_bin="$(type -P agent 2>/dev/null || true)"
    [[ -n "$agent_bin" ]] || {
        printf 'resume_agent_session: agent CLI not found on PATH\n' >&2
        return 1
    }
    py="$(command -v python3 2>/dev/null || true)"
    script="$(_init_files_agent_sessions_py)"
    [[ -n "$py" && -f "$script" ]] || {
        printf 'resume_agent_session: need python3 and %s\n' "$script" >&2
        return 1
    }

    # resume_agent_session [--named] [name|#|id]
    if [[ "$target" == "--named" ]]; then
        named_only=1
        target="${2:-}"
    fi

    if [[ -z "$target" ]]; then
        fzf_bin="$(command -v fzf 2>/dev/null || true)"
        [[ -n "${init_tool_fzf:-}" && -x "${init_tool_fzf}" ]] && fzf_bin="$init_tool_fzf"
        if [[ -z "$fzf_bin" ]]; then
            printf 'resume_agent_session: fzf not found — pass a name/# /id, or install fzf\n' >&2
            printf '  run: agent_sessions\n' >&2
            return 1
        fi
        [[ $named_only -eq 1 ]] && fzf_args+=(--named)
        picked="$(
            "$py" "$script" fzf "${fzf_args[@]}" \
                | "$fzf_bin" \
                    --height=40% \
                    --reverse \
                    --delimiter=$'\t' \
                    --with-nth=2.. \
                    --prompt='agent session > ' \
                    --header='name · updated · cwd · last prompt  (enter to resume)' \
                | cut -f1
        )"
        [[ -n "$picked" ]] || {
            printf 'resume_agent_session: cancelled\n' >&2
            return 1
        }
        id="$picked"
    else
        id="$("$py" "$script" resolve "$target")" || return 1
    fi

    if type _init_files_ensure_agent_model_auto > /dev/null 2>&1; then
        _init_files_ensure_agent_model_auto
    fi
    printf 'resume_agent_session: agent --model auto --resume=%s\n' "$id"
    exec "$agent_bin" --model auto --resume="$id"
}

function invalidate_tool_version_cache()
{
    # Drop the daily report/stamp so the next check_tool_versions rebuilds
    # against current installed versions. Keep latest-* (upstream) cache.
    local lock_dir

    [[ -n "${tool_version_state_dir:-}" ]] || return 0
    lock_dir="${tool_version_state_dir}.lock"
    if declare -F init_files_mkdir_lock > /dev/null 2>&1 \
        && init_files_mkdir_lock "$lock_dir"; then
        rm -f \
            "${tool_version_state_dir}/last-check" \
            "${tool_version_state_dir}/last-report" \
            "${tool_version_state_dir}/pending-updates" \
            2>/dev/null || true
        init_files_mkdir_unlock "$lock_dir"
    else
        rm -f \
            "${tool_version_state_dir}/last-check" \
            "${tool_version_state_dir}/last-report" \
            "${tool_version_state_dir}/pending-updates" \
            2>/dev/null || true
    fi
}

function tool_version_cache_is_complete()
{
    local cache_file="$1" key

    [[ -r "$cache_file" ]] || return 1
    for key in \
        checked_at \
        bash_latest \
        gh_latest \
        gh_stack_latest \
        git_latest \
        gt_latest \
        npm_latest \
        pipx_latest \
        pnpm_latest \
        uv_latest
    do
        grep -q "^${key}=" "$cache_file" 2>/dev/null || return 1
    done
    return 0
}

# Refresh tool_version_cache ("latest") used by check_tool_versions.
#
# Why: interactive shells reprint a cached status; this rebuilds at most about
# daily without blocking every prompt on network. Fetches run unlocked; only the
# short publish of `latest` takes init_files_mkdir_lock + atomic write (#26 /
# lib/tool_version_cache) so concurrent shells do not tear the file. Distro
# fallbacks when GitHub/npm/PyPI are blocked avoid perpetual "pending". Missing
# curl/python3 → soft return (status degrades; shell still loads). See
# docs/shell-ux.md (check_tool_versions).
function refresh_tool_version_cache()
{
    local cache_dir cache_file bash_latest gh_latest gh_stack_latest git_latest gt_latest npm_latest pipx_latest pnpm_latest uv_latest
    local curl_cmd body lock_dir

    [[ -n "${init_tool_python3:-}" && -x "$init_tool_python3" ]] || return

    curl_cmd="$init_tool_curl"
    [[ -n "$curl_cmd" && -x "$curl_cmd" ]] || return

    cache_dir="$tool_version_state_dir"
    cache_file="$tool_version_cache"
    lock_dir="${tool_version_state_dir}.lock"

    mkdir -p "$cache_dir" || return

    bash_latest=$(fetch_bash_latest 2> /dev/null || true)

    gh_latest=$(
        "$curl_cmd" --silent --show-error --fail --location --max-time 5 https://api.github.com/repos/cli/cli/releases/latest 2> /dev/null \
            | "$init_tool_python3" -c 'import json, sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))' 2> /dev/null
    ) || gh_latest=
    # Distro candidate when GitHub API is blocked/slow — avoids perpetual "pending".
    if [[ -z "$gh_latest" ]]; then
        gh_latest=$(fetch_gh_latest_distro 2> /dev/null || true)
    fi

    gh_stack_latest=$(
        "$curl_cmd" --silent --show-error --fail --location --max-time 5 https://api.github.com/repos/github/gh-stack/releases/latest 2> /dev/null \
            | "$init_tool_python3" -c 'import json, sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))' 2> /dev/null
    ) || gh_stack_latest=

    git_latest=$(fetch_git_latest_upstream 2> /dev/null || true)
    if [[ -z "$git_latest" ]]; then
        git_latest=$(fetch_git_latest_distro 2> /dev/null || true)
    fi
    gt_latest=$(
        "$curl_cmd" --silent --show-error --fail --location --max-time 5 https://registry.npmjs.org/@withgraphite/graphite-cli/latest 2> /dev/null \
            | "$init_tool_python3" -c 'import json, sys; print(json.load(sys.stdin)["version"])' 2> /dev/null
    ) || gt_latest=

    npm_latest=$(
        "$curl_cmd" --silent --show-error --fail --location --max-time 5 https://registry.npmjs.org/npm/latest 2> /dev/null \
            | "$init_tool_python3" -c 'import json, sys; print(json.load(sys.stdin)["version"])' 2> /dev/null
    ) || npm_latest=

    pipx_latest=$(
        "$curl_cmd" --silent --show-error --fail --location --max-time 5 https://pypi.org/pypi/pipx/json 2> /dev/null \
            | "$init_tool_python3" -c 'import json, sys; print(json.load(sys.stdin)["info"]["version"])' 2> /dev/null
    ) || pipx_latest=

    pnpm_latest=$(
        "$curl_cmd" --silent --show-error --fail --location --max-time 5 https://registry.npmjs.org/pnpm/latest 2> /dev/null \
            | "$init_tool_python3" -c 'import json, sys; print(json.load(sys.stdin)["version"])' 2> /dev/null
    ) || pnpm_latest=

    uv_latest=$(fetch_uv_latest 2> /dev/null || true)

    body=$(
        printf 'checked_at=%s\n' "$(date +%s)"
        printf 'bash_latest=%s\n' "$bash_latest"
        printf 'gh_latest=%s\n' "$gh_latest"
        printf 'gh_stack_latest=%s\n' "$gh_stack_latest"
        printf 'git_latest=%s\n' "$git_latest"
        printf 'gt_latest=%s\n' "$gt_latest"
        printf 'npm_latest=%s\n' "$npm_latest"
        printf 'pipx_latest=%s\n' "$pipx_latest"
        printf 'pnpm_latest=%s\n' "$pnpm_latest"
        printf 'uv_latest=%s\n' "$uv_latest"
    ) || return

    # Lock only the short publish step (network work stays outside the lock).
    if declare -F init_files_mkdir_lock > /dev/null 2>&1 \
        && declare -F init_files_atomic_write > /dev/null 2>&1; then
        if init_files_mkdir_lock "$lock_dir"; then
            printf '%s' "$body" | init_files_atomic_write "$cache_file" || true
            init_files_mkdir_unlock "$lock_dir"
        else
            # Another publisher holds the lock; skip — next refresh will retry.
            return 0
        fi
    else
        printf '%s' "$body" > "${cache_file}.tmp.$$" || return
        mv -f "${cache_file}.tmp.$$" "$cache_file"
    fi
}

function resetcs()
{
    branchName=$("$init_tool_git" rev-parse --abbrev-ref HEAD 2> /dev/null)
    export branchName
    if [ "$branchName" != "" ]; then
        export CSCOPE_DB=$HOME/.cscope/$branchName.cscope.out
    fi
}

function resetgr()
{
    branchName=$("$init_tool_git" rev-parse --abbrev-ref HEAD 2> /dev/null)
    branchRootDir=$("$init_tool_git" rev-parse --show-toplevel 2> /dev/null)
    export branchName branchRootDir
}

function run()
{
    local number_of_repetitions="$1"
    local i timestamp rc
    shift
    for ((i = 1; i <= number_of_repetitions; i++)); do
        timestamp=$(date)
        echo "$timestamp --- trial #$i/$number_of_repetitions ------------------------------------------------"
        "$@"
        rc=$?
        if ((rc != 0)); then
            printf '\nERROR: iteration %s of %s: %s failed\n' \
                "$i" "$number_of_repetitions" "$*" >&2
            break
        fi
    done
}

function rune()
{
    local number_of_repetitions="$1"
    local expected_error_code i timestamp rc
    shift
    expected_error_code="$1"
    shift
    for ((i = 1; i <= number_of_repetitions; i++)); do
        timestamp=$(date)
        echo "$timestamp --- trial #$i/$number_of_repetitions ------------------------------------------------"
        "$@"
        rc=$?
        if [[ "$rc" != "$expected_error_code" ]]; then
            printf '\nERROR: iteration %s of %s: %s failed with unexpected error code %s\n' \
                "$i" "$number_of_repetitions" "$*" "$rc" >&2
            break
        fi
    done
}

function runi()
{
    local number_of_repetitions="$1"
    local i timestamp
    shift
    for ((i = 1; i <= number_of_repetitions; i++)); do
        timestamp=$(date)
        echo "$timestamp --- trial #$i/$number_of_repetitions ------------------------------------------------"
    done
}

function tool_install_command()
{
    local tool_name tool_path helper

    tool_name="$1"
    tool_path="${2:-}"

    case "$tool_name" in
        bash)
            printf 'update_bash'
            ;;
        bash-completion)
            bash_completion_install_hint
            ;;
        fzf)
            fzf_install_hint
            ;;
        git)
            git_suggested_command "${tool_path:-${init_tool_git:-}}"
            ;;
        gh)
            printf 'update_gh'
            ;;
        gh-stack)
            if command -v gh > /dev/null 2>&1; then
                printf 'update_gh_stack'
            else
                printf 'update_gh && update_gh_stack'
            fi
            ;;
        gt)
            if command -v npm > /dev/null 2>&1 || [[ -n "${init_tool_npm:-}" && -x "${init_tool_npm:-}" ]]; then
                printf 'update_gt'
            else
                printf 'update_npm && update_gt'
            fi
            ;;
        npm|npx)
            helper="$(_init_node_toolchain_helper 2>/dev/null || true)"
            if [[ -n "$helper" ]]; then
                printf '%s && update_npm' "$helper"
            else
                printf 'update_npm'
            fi
            ;;
        pipx)
            printf 'update_pipx'
            ;;
        pnpm)
            if command -v npm > /dev/null 2>&1 \
                || [[ -n "${init_tool_npm:-}" && -x "${init_tool_npm:-}" ]] \
                || [[ -n "${init_tool_corepack:-}" && -x "${init_tool_corepack:-}" ]]
            then
                printf 'update_pnpm'
            else
                helper="$(_init_node_toolchain_helper 2>/dev/null || true)"
                if [[ -n "$helper" ]]; then
                    printf '%s && update_pnpm' "$helper"
                else
                    printf 'update_npm && update_pnpm'
                fi
            fi
            ;;
        uv)
            # Install detection uses the default pipx path.
            # shellcheck disable=SC2119
            if pipx_is_usable; then
                printf 'pipx install uv'
            else
                printf 'update_pipx && pipx install uv'
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

function tool_status_line()
{
    local green install_command red reset tool_name tool_path tone upgrade_tier update_command yellow
    local current_version latest_version admin_steps

    tool_name="$1"
    tool_path="$2"
    current_version="$(normalize_version "$3")"
    latest_version="$(normalize_version "$4")"
    upgrade_tier="${5:-}"
    green=
    red=
    yellow=
    reset=
    tone=
    admin_steps=

    if [[ -n "$tool_status_use_color" ]]; then
        green=$'\033[32m'
        red=$'\033[31m'
        yellow=$'\033[33m'
        reset=$'\033[0m'
    fi

    if [[ -z "$tool_path" ]]; then
        install_command="$(tool_install_command "$tool_name" "$tool_path" 2> /dev/null || true)"
        if [[ -n "$latest_version" ]]; then
            printf '%s  %s: installed -, latest %s, status: not found on PATH%s' "$red" "$tool_name" "$latest_version" "$reset"
        else
            printf '%s  %s: installed -, latest -, status: not found on PATH%s' "$red" "$tool_name" "$reset"
        fi
        # npm/gt/pnpm: nvm-first (user-local); no Homebrew admin cut-paste.
        admin_steps="$(tool_admin_install_steps "$tool_name" 2>/dev/null || true)"
        if [[ -n "$admin_steps" ]]; then
            printf '\n%s    %s%s' "$red" "$admin_steps" "$reset"
        elif [[ -n "$install_command" ]]; then
            printf '\n%s    install: %s%s' "$red" "$install_command" "$reset"
        fi
    elif [[ -z "$current_version" ]]; then
        if [[ -n "$latest_version" ]]; then
            printf '  %s: installed ?, latest %s, status: version check unavailable, path: %s' "$tool_name" "$latest_version" "$tool_path"
        else
            printf '  %s: installed ?, latest -, status: version check unavailable, path: %s' "$tool_name" "$tool_path"
        fi
    elif [[ -z "$latest_version" ]]; then
        printf '%s  %s: installed %s, latest -, status: latest check pending, path: %s%s' \
            "$yellow" "$tool_name" "$current_version" "$tool_path" "$reset"
    elif versions_equal "$current_version" "$latest_version"; then
        printf '%s  %s: installed %s, latest %s, status: up to date, path: %s%s' "$green" "$tool_name" "$current_version" "$latest_version" "$tool_path" "$reset"
    elif version_lt "$current_version" "$latest_version"; then
        _tool_version_note_pending "$tool_name" "$current_version" "$latest_version" "$tool_path"
        if [[ "$upgrade_tier" == "blocked" ]]; then
            # Manual / upstream-only (typical Linux distro lag). Do not suggest
            # update_git — that path cannot apply a newer package. macOS brew
            # upgrades use upgrade_tier=auto below instead.
            tone="$yellow"
            printf '%s  %s: installed %s, latest %s, status: update available (manual upgrade required), path: %s%s' \
                "$tone" "$tool_name" "$current_version" "$latest_version" "$tool_path" "$reset"
        else
            tone="$red"
            update_command="$(tool_update_command "$tool_name" "$tool_path" 2> /dev/null || true)"
            printf '%s  %s: installed %s, latest %s, status: update available, path: %s%s' \
                "$tone" "$tool_name" "$current_version" "$latest_version" "$tool_path" "$reset"
            if [[ -n "$update_command" ]]; then
                printf '\n%s    suggested command: %s%s' "$tone" "$update_command" "$reset"
            fi
        fi
    else
        # current > tracked latest (distro Candidate truncated, or newer than
        # last upstream probe) — treat as current, not an error state.
        printf '%s  %s: installed %s, latest %s, status: up to date, path: %s%s' \
            "$green" "$tool_name" "$current_version" "$current_version" "$tool_path" "$reset"
    fi
}

function tool_update_command()
{
    local tool_name tool_path

    tool_name="$1"
    tool_path="${2:-}"

    case "$tool_name" in
        bash)
            printf 'update_bash'
            ;;
        git)
            git_suggested_command "${tool_path:-${init_tool_git:-}}"
            ;;
        gh)
            printf 'update_gh'
            ;;
        gh-stack)
            printf 'update_gh_stack'
            ;;
        gt)
            printf 'update_gt'
            ;;
        npm|npx)
            printf 'update_npm'
            ;;
        pipx)
            pipx_update_command "$tool_path"
            ;;
        pnpm)
            printf 'update_pnpm'
            ;;
        uv)
            # Always update_uv (invalidates the daily report). Raw strategy
            # commands like `uv self update` leave a stale "update available".
            printf 'update_uv'
            ;;
        *)
            return 1
            ;;
    esac
}

# Upgrade all tools listed in pending-updates (or reprint hints). Single entry
# point for issue #40 — runs the same update_* / admin-handoff paths as per-tool
# helpers, then invalidates the daily report so out-of-band upgrades clear nags.
function update_tools()
{
    local pending_file tool ver path live rc=0 ran=0 skipped=0 tool_rc hint
    local -a admin_hints=()

    if [[ "${1:-}" == '-h' || "${1:-}" == '--help' ]]; then
        cat <<'EOF' >&2
Usage: update_tools

Upgrade every tool currently recorded as outdated in the tool-version
pending-updates sidecar (written by check_tool_versions). Uses the same
per-tool helpers (update_git, update_bash, …) and OS-tier / admin-handoff
rules. Always invalidates the daily report when finished.

If an admin already upgraded packages out-of-band (live newer than the
recorded pending version), those tools are skipped and the next
check_tool_versions rebuild clears their nags.
EOF
        return 0
    fi

    pending_file="${tool_version_state_dir:-}/pending-updates"
    if [[ -z "${tool_version_state_dir:-}" || ! -r "$pending_file" ]]; then
        printf 'update_tools: no pending updates (run check_tool_versions first, or nothing is outdated).\n' >&2
        return 0
    fi

    while IFS=$'\t' read -r tool ver path || [[ -n "$tool" ]]; do
        [[ -z "$tool" || "$tool" == \#* ]] && continue
        live="$(tool_live_installed_version "$tool" "$path" 2>/dev/null || true)"
        live="$(normalize_version "$live")"
        ver="$(normalize_version "$ver")"
        # Skip only when live is newer than the recorded outdated install
        # (out-of-band upgrade). Downgrades / PATH switches still try update_*.
        if [[ -n "$live" && -n "$ver" ]] && version_lt "$ver" "$live"; then
            printf 'update_tools: %s already %s (was %s); skipping\n' "$tool" "$live" "$ver"
            skipped=$((skipped + 1))
            continue
        fi

        printf 'update_tools: upgrading %s …\n' "$tool"
        ran=$((ran + 1))
        tool_rc=0
        case "$tool" in
            bash) update_bash || tool_rc=1 ;;
            git) update_git || tool_rc=1 ;;
            gh) update_gh || tool_rc=1 ;;
            gh-stack) update_gh_stack || tool_rc=1 ;;
            gt) update_gt || tool_rc=1 ;;
            npm|npx) update_npm || tool_rc=1 ;;
            pipx) update_pipx || tool_rc=1 ;;
            pnpm) update_pnpm || tool_rc=1 ;;
            uv)
                # Optional path arg; PATH lookup is intentional.
                # shellcheck disable=SC2119
                update_uv || tool_rc=1
                ;;
            *)
                printf 'update_tools: no updater for %s\n' "$tool" >&2
                tool_rc=1
                ;;
        esac
        if [[ $tool_rc -ne 0 ]]; then
            rc=1
            hint="$(tool_update_command "$tool" "$path" 2>/dev/null || true)"
            if [[ "$hint" == ask\ an\ admin* ]]; then
                admin_hints+=("$hint")
            fi
        fi
    done < "$pending_file"

    invalidate_tool_version_cache

    if ((${#admin_hints[@]})); then
        printf '\nupdate_tools: forward to an admin (then re-run update_tools / check_tool_versions):\n' >&2
        local h
        for h in "${admin_hints[@]}"; do
            printf '  %s\n' "$h" >&2
        done
    fi
    printf 'update_tools: done (ran=%s skipped=%s). Next interactive shell rebuilds the tool report.\n' \
        "$ran" "$skipped"
    return "$rc"
}

function tool_version_check_schedule_lines()
{
    local checked_at checked_fmt next_at next_fmt pending stamp

    pending="${1:-0}"
    stamp="${tool_version_state_dir}/last-check"
    checked_at=

    if [[ -r "$stamp" ]]; then
        checked_at=$(cat "$stamp" 2>/dev/null || true)
    fi
    if [[ -z "$checked_at" || ! "$checked_at" =~ ^[0-9]+$ ]] && [[ -r "$tool_version_cache" ]]; then
        # Fallback: cache write time from the last upstream latest-* fetch.
        checked_at=$(awk -F= '$1 == "checked_at" { print $2; exit }' "$tool_version_cache" 2>/dev/null || true)
    fi

    checked_fmt=
    if [[ "$checked_at" =~ ^[0-9]+$ ]]; then
        checked_fmt=$(date -d "@$checked_at" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null \
            || date -r "$checked_at" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null \
            || printf '%s' "$checked_at")
    fi

    if [[ -n "$checked_fmt" ]]; then
        printf '  last checked: %s\n' "$checked_fmt"
    else
        printf '  last checked: never\n'
    fi

    if [[ "$pending" =~ ^[0-9]+$ ]] && (( pending > 0 )); then
        printf '  next check: pending (fetching latest versions)\n'
        return 0
    fi

    if [[ "$checked_at" =~ ^[0-9]+$ ]]; then
        next_at=$((checked_at + tool_version_max_age_seconds))
        next_fmt=$(date -d "@$next_at" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null \
            || date -r "$next_at" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null \
            || printf '%s' "$next_at")
        printf '  next check: %s\n' "$next_fmt"
    else
        printf '  next check: soon\n'
    fi
}

function update_bash()
{
    local package_name strategy_name

    invalidate_tool_version_cache

    # Older macOS: never brew — Apple bash is frozen; other installs are manual.
    if _init_is_darwin && type _init_is_modern_macos > /dev/null 2>&1 && ! _init_is_modern_macos; then
        if bash_is_apple_system_path "${init_tool_bash:-${BASH:-}}"; then
            printf 'Apple /bin/bash is frozen at 3.2.x on this macOS tier; cannot upgrade via Homebrew\n' >&2
        else
            printf 'Homebrew bash upgrades are not supported on this macOS tier; update manually if needed\n' >&2
        fi
        return 1
    fi

    if _init_is_darwin && type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos; then
        _init_brew_admin_or_handoff bash || return 1
        if ! command -v brew > /dev/null 2>&1; then
            printf 'Homebrew is required to install/upgrade bash on modern macOS\n' >&2
            return 1
        fi
        # Formulae lag PyPI-style "latest" until `brew update` refreshes the tap.
        brew update || return
        # Prefer path check over `brew list` (Cellar walks can hang).
        if _init_brew_formula_present bash; then
            brew upgrade bash || return
        else
            brew install bash || return
        fi
        hash -r
        command -v bash > /dev/null 2>&1 || {
            printf 'bash installed but not on PATH; check Homebrew bin is in PATH\n' >&2
            return 1
        }
        bash --version | head -n 1
        # Always print the macOS Cellar /etc/shells + chsh steps after brew
        # install/upgrade — the versioned path usually changed.
        bash_login_shell_setup_hint "${init_tool_bash:-}"
        return 0
    fi

    strategy_name="$(detect_bash_update_strategy "${init_tool_bash:-}" 2> /dev/null | awk -F '\t' 'NR == 1 { print $1 }')"
    package_name="$(detect_bash_update_strategy "${init_tool_bash:-}" 2> /dev/null | awk -F '\t' 'NR == 1 { print $2 }')"
    [[ -n "$package_name" ]] || package_name=bash

    case "$strategy_name" in
        dnf)
            _init_linux_sudo_or_handoff "sudo dnf upgrade -y $package_name" update_bash || return 1
            sudo dnf upgrade -y "$package_name" || return
            ;;
        yum)
            _init_linux_sudo_or_handoff "sudo yum update -y $package_name" update_bash || return 1
            sudo yum update -y "$package_name" || return
            ;;
        apt)
            _init_linux_sudo_or_handoff \
                "sudo apt-get update && sudo apt-get install -y --only-upgrade $package_name" \
                update_bash || return 1
            sudo apt-get update && sudo apt-get install -y --only-upgrade "$package_name" || return
            ;;
        *)
            printf 'No package-manager upgrade path for bash on this host (manual / upstream-only)\n' >&2
            return 1
            ;;
    esac

    hash -r
    bash --version | head -n 1
}

function update_gh()
{
    local arch version tmp_dir archive extracted_dir install_dir old_install os_slug

    invalidate_tool_version_cache

    # Modern macOS: Homebrew owns gh.
    if _init_is_darwin && type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos; then
        _init_brew_admin_or_handoff gh || return 1
        if ! command -v brew > /dev/null 2>&1; then
            printf 'Homebrew is required to install gh on modern macOS\n' >&2
            return 1
        fi
        if _init_brew_formula_present gh; then
            brew upgrade gh || return
        else
            brew install gh || return
        fi
        hash -r
        command -v gh > /dev/null 2>&1 || {
            printf 'gh installed but not on PATH; check Homebrew bin is in PATH\n' >&2
            return 1
        }
        gh --version
        return
    fi

    case "$(uname -m)" in
        x86_64)
            arch="amd64"
            ;;
        aarch64|arm64)
            arch="arm64"
            ;;
        *)
            printf 'Unsupported gh architecture: %s\n' "$(uname -m)" >&2
            return 1
            ;;
    esac

    if _init_is_darwin; then
        os_slug="macOS"
    else
        os_slug="linux"
    fi

    command -v "$init_tool_python3" > /dev/null 2>&1 || {
        printf 'python3 is required to install gh\n' >&2
        return 1
    }
    if _init_is_darwin; then
        command -v unzip > /dev/null 2>&1 || {
            printf 'unzip is required to install gh on macOS\n' >&2
            return 1
        }
    else
        command -v tar > /dev/null 2>&1 || {
            printf 'tar is required to install gh\n' >&2
            return 1
        }
    fi

    version=$(
        "$init_tool_python3" - <<'PY'
import json
import urllib.request

with urllib.request.urlopen("https://api.github.com/repos/cli/cli/releases/latest", timeout=10) as response:
    print(json.load(response)["tag_name"].lstrip("v"))
PY
    ) || return

    tmp_dir=$(mktemp -d) || return
    if _init_is_darwin; then
        archive="$tmp_dir/gh.zip"
    else
        archive="$tmp_dir/gh.tar.gz"
    fi
    install_dir="$HOME/.local/opt/gh-$version"

    if ! "$init_tool_python3" - "$version" "$arch" "$archive" "$os_slug" <<'PY'
import pathlib
import sys
import urllib.request

version, arch, archive, os_slug = sys.argv[1:]
if os_slug == "macOS":
    url = f"https://github.com/cli/cli/releases/download/v{version}/gh_{version}_macOS_{arch}.zip"
else:
    url = f"https://github.com/cli/cli/releases/download/v{version}/gh_{version}_linux_{arch}.tar.gz"
pathlib.Path(archive).parent.mkdir(parents=True, exist_ok=True)
with urllib.request.urlopen(url, timeout=60) as response:
    pathlib.Path(archive).write_bytes(response.read())
PY
    then
        rm -rf "$tmp_dir"
        return
    fi

    mkdir -p "$HOME/.local/bin" "$HOME/.local/opt" || {
        rm -rf "$tmp_dir"
        return
    }

    if _init_is_darwin; then
        unzip -q "$archive" -d "$tmp_dir" || {
            rm -rf "$tmp_dir"
            return
        }
        extracted_dir="$tmp_dir/gh_${version}_macOS_${arch}"
    else
        tar -xzf "$archive" -C "$tmp_dir" || {
            rm -rf "$tmp_dir"
            return
        }
        extracted_dir="$tmp_dir/gh_${version}_linux_${arch}"
    fi

    rm -rf "$install_dir"
    mv "$extracted_dir" "$install_dir" || {
        rm -rf "$tmp_dir"
        return
    }

    ln -sfn "$install_dir/bin/gh" "$HOME/.local/bin/gh" || {
        rm -rf "$tmp_dir"
        return
    }

    for old_install in "$HOME"/.local/opt/gh-*; do
        [[ -d "$old_install" && "$old_install" != "$install_dir" ]] || continue
        rm -rf "$old_install"
    done

    rm -rf "$tmp_dir"
    hash -r
    # Prefer the freshly installed binary when brew/gh still shadows PATH.
    if [[ -x "$HOME/.local/bin/gh" ]]; then
        "$HOME/.local/bin/gh" --version
    else
        gh --version
    fi
}

function update_gh_stack()
{
    invalidate_tool_version_cache

    command -v gh > /dev/null 2>&1 || {
        printf 'gh is required for gh-stack; try: %s\n' \
            "$(tool_install_command gh 2> /dev/null || printf 'update_gh')" >&2
        return 1
    }

    if gh_stack_extension_path > /dev/null 2>&1 \
        || gh_stack_current_version > /dev/null 2>&1
    then
        # Name is the short extension command ("stack"), not the repo slug.
        gh extension upgrade stack || gh extension upgrade gh-stack || return
    else
        gh extension install github/gh-stack || return
    fi

    GH_NO_EXTENSION_UPDATE_NOTIFIER=1 gh stack --version 2> /dev/null \
        || gh extension list 2> /dev/null | awk '/gh-stack/ { print; exit }'
}

function update_git()
{
    local git_path kind upgrade_command

    invalidate_tool_version_cache

    git_path="$init_tool_git"
    kind="$(git_upgrade_kind \
        "$("$init_tool_git" --version 2> /dev/null | awk 'NR == 1 { print $3 }')" \
        "$(fetch_git_latest_upstream 2> /dev/null || true)" \
        "$git_path" 2> /dev/null || true)"

    case "$kind" in
        package-manager)
            upgrade_command="$(git_package_manager_command "$git_path" 2> /dev/null || true)"
            if [[ -z "$upgrade_command" ]]; then
                update_git_upstream
                return 1
            fi
            if [[ "$upgrade_command" == brew\ * ]]; then
                _init_brew_admin_or_handoff git || return 1
            fi
            if [[ "$upgrade_command" == sudo\ * ]]; then
                _init_linux_sudo_or_handoff "$upgrade_command" update_git || return 1
            fi
            eval "$upgrade_command" || return
            ;;
        upstream-only)
            update_git_upstream
            return 1
            ;;
        up-to-date)
            printf 'git is already at or ahead of the latest known upstream release.\n'
            "$init_tool_git" --version
            return 0
            ;;
        *)
            printf 'Could not determine how to upgrade git on this host; try update_git_upstream for guidance.\n' >&2
            update_git_upstream
            return 1
            ;;
    esac

    hash -r
    "$init_tool_git" --version
}

function update_git_upstream()
{
    local distro_latest git_path source_label upstream_latest version_line

    git_path="${init_tool_git:-}"
    upstream_latest="$(fetch_git_latest_upstream 2> /dev/null || true)"
    distro_latest="$(fetch_git_latest_distro 2> /dev/null || true)"
    version_line=$("$git_path" --version 2> /dev/null || printf unknown)
    source_label="$(git_install_source_label "$git_path")"

    printf 'git cannot be upgraded automatically on this host.\n' >&2
    printf '  installed: %s\n' "$(printf '%s\n' "$version_line" | awk 'NR == 1 { print $3 }')" >&2
    if [[ -n "$upstream_latest" ]]; then
        printf '  latest upstream: %s\n' "$upstream_latest" >&2
    fi
    if [[ -n "$distro_latest" ]]; then
        printf '  latest from distro repos: %s\n' "$distro_latest" >&2
    fi
    printf '  install source: %s\n' "$source_label" >&2

    if _init_is_darwin; then
        if [[ "$source_label" == *"Apple Git"* ]] || [[ "$source_label" == *"Command Line Tools"* ]]; then
            printf '  next step: install a newer Xcode Command Line Tools / macOS update when Apple ships one\n' >&2
            if type _init_is_modern_macos > /dev/null 2>&1 && ! _init_is_modern_macos; then
                printf '            (Homebrew is not recommended on this macOS tier)\n' >&2
            fi
        elif type _init_is_modern_macos > /dev/null 2>&1 && _init_is_modern_macos; then
            printf '  next step: use Homebrew git on modern macOS (brew install git / update_git)\n' >&2
        else
            printf '  next step: stay on system/Xcode git; Homebrew is not recommended on this macOS tier\n' >&2
        fi
        return 1
    fi

    if git_package_name "$git_path" > /dev/null 2>&1; then
        printf '  package manager: already at or ahead of the distro package\n' >&2
    fi
    printf '  next step: build from https://github.com/git/git/releases or ask an admin for a newer package/repo\n' >&2
    return 1
}

function update_gt()
{
    local npm_cmd

    invalidate_tool_version_cache

    npm_cmd="$(_init_ensure_user_node_toolchain)" || return 1
    _init_npm_exec "$npm_cmd" install --global @withgraphite/graphite-cli@latest || return
    hash -r
    command -v gt > /dev/null 2>&1 && gt --version
}

function update_npm()
{
    local npm_cmd

    invalidate_tool_version_cache

    # User-local npm only (nvm/fnm). Never `npm -g` into Homebrew (EACCES).
    npm_cmd="$(_init_ensure_user_node_toolchain)" || return 1
    _init_npm_exec "$npm_cmd" install --global npm@latest || return
    hash -r
    # Prefer the user-local binary after upgrade.
    _init_load_node_toolchain > /dev/null 2>&1 || true
    hash -r
    # Report the same user-local npm we upgraded (not a Homebrew shadow).
    if [[ -x "$npm_cmd" ]]; then
        _init_npm_exec "$npm_cmd" --version
        printf '%s\n' "$npm_cmd"
    else
        npm --version
        command -v npm
    fi
}

function update_corepack()
{
    local corepack_cmd npm_cmd

    invalidate_tool_version_cache

    npm_cmd="$(_init_ensure_user_node_toolchain)" || return 1
    corepack_cmd="$(_init_user_corepack_command 2>/dev/null || true)"
    if [[ -z "$corepack_cmd" ]]; then
        # Node LTS ships corepack next to npm under nvm.
        if [[ -x "$(dirname "$npm_cmd")/corepack" ]]; then
            corepack_cmd="$(dirname "$npm_cmd")/corepack"
        fi
    fi
    [[ -n "$corepack_cmd" && -x "$corepack_cmd" ]] || {
        printf 'corepack not found next to user-local npm (%s)\n' "$npm_cmd" >&2
        printf 'Try: install_node_toolchain && hash -r\n' >&2
        return 1
    }
    "$corepack_cmd" enable || return
    hash -r
    "$corepack_cmd" --version 2>/dev/null || true
    command -v corepack
}

function update_pnpm()
{
    local update_command npm_cmd

    invalidate_tool_version_cache

    npm_cmd="$(_init_ensure_user_node_toolchain)" || return 1
    # Ensure corepack shims are enabled under the user-local Node.
    if type update_corepack > /dev/null 2>&1; then
        update_corepack >/dev/null 2>&1 || true
    fi

    # Update detection uses the pnpm found on PATH.
    # shellcheck disable=SC2119
    update_command="$(pnpm_update_command 2> /dev/null || true)"
    [[ -n "$update_command" ]] || {
        printf 'pnpm cannot be updated yet (user-local npm/corepack missing).\n' >&2
        npm_bootstrap_instructions
        return 1
    }

    eval "$update_command" || return

    hash -r
    pnpm --version
}

function update_pipx()
{
    local current_link install_dir installed_version old_install package_spec pipx_host_dir tmp_dir

    invalidate_tool_version_cache

    command -v "$init_tool_python3" > /dev/null 2>&1 || {
        printf 'python3 is required to install pipx\n' >&2
        return 1
    }

    if ! python3_meets_minimum; then
        printf 'pipx 1.12+ requires Python %s; this host has %s\n' \
            "$(pipx_required_python_label)" "$("$init_tool_python3" --version 2> /dev/null || printf unknown)" >&2
        printf 'Install Python 3.10+ (modules, pyenv, etc.) and make it the python3 used by update_pipx.\n' >&2
        return 1
    fi

    if ! python3_has_pip; then
        # Debian/Ubuntu often ship python3 without the pip module.
        if "$init_tool_python3" -m ensurepip --upgrade > /dev/null 2>&1 \
            && python3_has_pip
        then
            printf 'Bootstrapped pip via ensurepip for %s\n' "$init_tool_python3" >&2
        else
            pip_bootstrap_instructions
            return 1
        fi
    fi

    migrate_pipx_host_layout 2>/dev/null || true
    # If only the wrapper is stale, rebake without a full reinstall.
    rewrite_stale_pipx_wrappers 2>/dev/null || true

    tmp_dir=$(mktemp -d) || return

    package_spec="pipx"
    installed_version="$(fetch_latest_tool_version pipx || true)"
    if [[ -n "$installed_version" ]]; then
        package_spec="pipx==$installed_version"
    fi

    install_dir="$tmp_dir/install"
    mkdir -p "$install_dir/site" "$install_dir/bin" || {
        rm -rf "$tmp_dir"
        return 1
    }

    {
        local -a pip_install_args

        pip_install_args=(--upgrade --target "$install_dir/site")
        if pip_supports_install_flag --no-warn-script-location; then
            pip_install_args+=(--no-warn-script-location)
        fi
        env -u PIP_PREFIX "$init_tool_python3" -m pip install "${pip_install_args[@]}" "$package_spec"
    } || {
        rm -rf "$tmp_dir"
        if ! python3_has_pip; then
            pip_bootstrap_instructions
        else
            printf 'pip install of pipx failed for %s\n' "$init_tool_python3" >&2
        fi
        return 1
    }

    # Bake the absolute interpreter into the wrapper. A bare $init_tool_python3
    # reference fails at runtime (that var is not exported into the script).
    cat > "$install_dir/bin/pipx" <<EOF || {
#!/usr/bin/env bash
set -e

script_dir="\$(cd -- "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
site_dir="\${script_dir%/bin}/site"

export PYTHONPATH="\${site_dir}\${PYTHONPATH:+:\$PYTHONPATH}"
export PIPX_HOME="\$HOME/.local/share/pipx"
export PIPX_BIN_DIR="\$HOME/.local/bin"

exec env -u PIP_PREFIX $(printf '%q' "$init_tool_python3") -m pipx "\$@"
EOF
        rm -rf "$tmp_dir"
        return 1
    }

    chmod 775 "$install_dir/bin/pipx" || {
        rm -rf "$tmp_dir"
        return 1
    }

    installed_version="$(PIP_PREFIX='' PYTHONPATH="$install_dir/site" pipx_metadata_version "$install_dir/site" 2> /dev/null || true)"
    [[ -n "$installed_version" ]] || {
        rm -rf "$tmp_dir"
        printf 'Unable to determine installed pipx version\n' >&2
        return 1
    }

    pipx_host_dir="$(pipx_host_dir)"
    current_link="$pipx_host_dir/current"
    mkdir -p "$HOME/.local/bin" "$HOME/.local/opt" "$pipx_host_dir" || {
        rm -rf "$tmp_dir"
        return 1
    }

    rm -rf "${pipx_host_dir:?}/$installed_version"
    mv "$install_dir" "$pipx_host_dir/$installed_version" || {
        rm -rf "$tmp_dir"
        return 1
    }

    install_dir="$pipx_host_dir/$installed_version"
    current_link="$pipx_host_dir/current"

    ln -sfn "$install_dir" "$current_link" || {
        rm -rf "$tmp_dir"
        return 1
    }

    if rm -f "$HOME/.local/bin/pipx" 2> /dev/null; then
        cat > "$HOME/.local/bin/pipx" <<'EOF' || {
#!/usr/bin/env bash
set -e

resolve_pipx_target()
{
    local candidate host_tag tag_dir
    local -a tags=()

    # Same host key as tools.* / prefs when available (exported by bashrc).
    tags+=("${tool_host_tag:-}")
    tags+=("${init_files_host:-}")
    tags+=("$(hostname -s 2> /dev/null || true)")
    tags+=("$(hostname -f 2> /dev/null || true)")
    tags+=("$(hostname 2> /dev/null || true)")

    for host_tag in "${tags[@]}"; do
        [[ -n "$host_tag" ]] || continue
        host_tag="${host_tag%%.*}"
        host_tag="${host_tag//[^[:alnum:]._-]/-}"
        candidate="$HOME/.local/opt/pipx/$host_tag/current/bin/pipx"
        [[ -x "$candidate" ]] && {
            printf '%s' "$candidate"
            return 0
        }
    done

    for tag_dir in "$HOME/.local/opt/pipx"/*; do
        candidate="$tag_dir/current/bin/pipx"
        [[ -x "$candidate" ]] && {
            printf '%s' "$candidate"
            return 0
        }
    done

    return 1
}

target="$(resolve_pipx_target 2> /dev/null || true)"
if [[ -z "$target" ]]; then
    printf 'pipx is not installed for this host; run update_pipx\n' >&2
    exit 1
fi

PIPX_HOME="$HOME/.local/share/pipx" PIPX_BIN_DIR="$HOME/.local/bin" exec env -u PIP_PREFIX "$target" "$@"
EOF
            rm -rf "$tmp_dir"
            return 1
        }

        chmod 775 "$HOME/.local/bin/pipx" || {
            rm -rf "$tmp_dir"
            return 1
        }
    fi

    for old_install in "$pipx_host_dir"/*; do
        [[ -d "$old_install" && "$old_install" != "$install_dir" ]] || continue
        [[ "$(basename "$old_install")" == "current" ]] && continue
        rm -rf "$old_install"
    done

    rm -rf "$tmp_dir"

    hash -r
    printf '%s\n' "$installed_version"
}

# Upgrade uv via brew / pipx / pip / package manager / self-update.
# Optional $1 = path to uv (default: command -v uv).
# shellcheck disable=SC2120
function update_uv()
{
    local package_name strategy tool_path

    invalidate_tool_version_cache

    tool_path="${1:-$(command -v uv 2> /dev/null || true)}"
    [[ -n "$tool_path" ]] || {
        printf 'uv is not on PATH\n' >&2
        return 1
    }

    strategy="$(detect_uv_update_strategy "$tool_path")" || return
    package_name="${strategy#*$'\t'}"

    case "${strategy%%$'\t'*}" in
        brew)
            brew upgrade "$package_name"
            ;;
        pipx-bootstrap)
            update_pipx && pipx upgrade "$package_name"
            ;;
        pipx-reinstall)
            pipx reinstall "$package_name"
            ;;
        pipx)
            pipx upgrade "$package_name"
            ;;
        pip)
            "$init_tool_python3" -m pip install --upgrade "$package_name"
            ;;
        apt)
            sudo apt update && sudo apt install --only-upgrade "$package_name"
            ;;
        dnf)
            sudo dnf upgrade "$package_name"
            ;;
        yum)
            sudo yum update "$package_name"
            ;;
        *)
            uv self update
            ;;
    esac

    hash -r
    uv --version
}

function uv_update_command()
{
    local package_name strategy tool_path

    tool_path="${1:-}"
    strategy="$(detect_uv_update_strategy "$tool_path" 2> /dev/null || true)"
    [[ -n "$strategy" ]] || strategy=$'self\tuv'
    package_name="${strategy#*$'\t'}"

    case "${strategy%%$'\t'*}" in
        brew)
            printf 'brew upgrade %s' "$package_name"
            ;;
        pipx-bootstrap)
            printf 'update_pipx && pipx upgrade %s' "$package_name"
            ;;
        pipx-reinstall)
            printf 'pipx reinstall %s' "$package_name"
            ;;
        pipx)
            printf 'pipx upgrade %s' "$package_name"
            ;;
        pip)
            printf "\"\$init_tool_python3\" -m pip install --upgrade %s" "$package_name"
            ;;
        apt)
            printf 'sudo apt update && sudo apt install --only-upgrade %s' "$package_name"
            ;;
        dnf)
            printf 'sudo dnf upgrade %s' "$package_name"
            ;;
        yum)
            printf 'sudo yum update %s' "$package_name"
            ;;
        *)
            printf 'uv self update'
            ;;
    esac
}

function v()
{
    # In-terminal vim (all platforms).
    local editor="${vimcl:-${init_tool_vim:-vim}}"
    "$editor" "$@"
}

function version_lt()
{
    local current_version latest_version

    current_version="$(normalize_version "$1")"
    latest_version="$(normalize_version "$2")"

    [[ -n "$current_version" && -n "$latest_version" && "$current_version" != "$latest_version" ]] || return 1
    [[ "$(printf '%s\n%s\n' "$current_version" "$latest_version" | sort -V | head -n 1)" == "$current_version" ]]
}

function versions_equal()
{
    local current_version latest_version

    current_version="$(normalize_version "$1")"
    latest_version="$(normalize_version "$2")"

    [[ -n "$current_version" && -n "$latest_version" && "$current_version" == "$latest_version" ]]
}

# MacVim's mvim wrapper always injects -g, so `mvim --serverlist` becomes
# `Vim -g --serverlist` and can hang against a running MacVim (-MMNoWindow).
# Prefer Contents/MacOS/Vim for --version / --serverlist / --remote-*.
function _init_vim_rpc_bin()
{
    local bin="${1:-}" link resolved dir rpc
    [[ -n "$bin" && -x "$bin" ]] || return 1
    resolved="$bin"
    if [[ -L "$resolved" ]]; then
        link="$(readlink "$resolved" 2>/dev/null || true)"
        if [[ -n "$link" ]]; then
            if [[ "$link" == /* ]]; then
                resolved="$link"
            else
                resolved="$(dirname -- "$resolved")/$link"
            fi
        fi
    fi
    dir="$(dirname -- "$resolved")"
    if [[ -x "${dir}/../MacOS/Vim" ]]; then
        rpc="$(cd "${dir}/../MacOS" && pwd)/Vim"
        [[ -x "$rpc" ]] && { printf '%s\n' "$rpc"; return 0; }
    fi
    printf '%s\n' "$bin"
}

# True when bin is a Vim front that accepts --servername / --remote-*.
function _init_vim_has_clientserver()
{
    local rpc
    rpc="$(_init_vim_rpc_bin "${1:-}" 2>/dev/null || true)"
    [[ -n "$rpc" && -x "$rpc" ]] || return 1
    "$rpc" --version 2>/dev/null | command grep -Fq '+clientserver'
}

function vi()
{
    # GUI / standalone window (MacVim on macOS, gvim on Linux).
    # Use v for in-terminal vim.
    local server="${gvim_servername:-HCMA}"
    local rpc

    if [[ -z "${gvimcl:-}" || ! -x "$gvimcl" ]]; then
        echo "vi: GUI editor not found (install MacVim / gvim). Use v for terminal vim." >&2
        return 1
    fi

    if _init_vim_has_clientserver "$gvimcl"; then
        rpc="$(_init_vim_rpc_bin "$gvimcl")"
        if [[ "$#" -eq 0 ]]; then
            # Untitled window. Do not --remote-send :tabnew — that can target a
            # hidden MacVim (-MMNoWindow) and show nothing. mvim with no files
            # asks the running app (or starts one) for a visible window.
            if _init_is_darwin; then
                "$gvimcl" --servername "$server" -g
            else
                "$gvimcl" --servername "$server"
            fi
            return
        fi
        if "$rpc" --serverlist 2>/dev/null | command grep -Fxiq "$server"; then
            "$rpc" --servername "$server" --remote-tab-silent "$@"
        elif _init_is_darwin; then
            "$gvimcl" --servername "$server" -g "$@"
        else
            "$gvimcl" --servername "$server" "$@"
        fi
        return
    fi

    # GUI binary without clientserver still opens a window.
    "$gvimcl" "$@"
}

if _init_is_darwin; then
###### macOS functions

function _init_darwin_release_major()
{
    local release
    release=$(uname -r 2>/dev/null || echo 0)
    printf '%s\n' "${release%%.*}"
}

function _init_homebrew_prefix()
{
    # Homebrew is only supported on modern macOS (26+ / Darwin 25+).
    # Discovery lives in lib/host_paths.
    if declare -F init_files_homebrew_prefix > /dev/null 2>&1; then
        init_files_homebrew_prefix
        return
    fi
    _init_is_modern_macos || return 1
    if [[ -d /opt/homebrew ]]; then
        printf '%s\n' /opt/homebrew
    elif [[ -d /usr/local/Homebrew || -d /usr/local/opt ]]; then
        printf '%s\n' /usr/local
    elif [[ -d $HOME/homebrew ]]; then
        printf '%s\n' "$HOME/homebrew"
    fi
}

# macOS 26+ (Darwin 25+), matching the current supported Homebrew platform.
function _init_is_modern_macos()
{
    local major
    _init_is_darwin || return 1
    major=$(_init_darwin_release_major)
    [[ "$major" =~ ^[0-9]+$ ]] || return 1
    (( major >= 25 ))
}

function _init_prepend_gnu_unix_tools()
{
    local brew_prefix gnubin_dir ruby_bin

    _init_is_modern_macos || return 0
    brew_prefix=$(_init_homebrew_prefix)
    [[ -n "$brew_prefix" ]] || return 0

    # Prepend each Homebrew gnubin so GNU ls/sed/grep/… shadow BSD tools.
    for gnubin_dir in "$brew_prefix"/opt/*/libexec/gnubin; do
        [[ -d "$gnubin_dir" ]] || continue
        PATH="$gnubin_dir:$PATH"
    done

    if [[ -d "$brew_prefix/bin" ]]; then
        PATH="$brew_prefix/bin:$brew_prefix/sbin:$PATH"
    fi
    ruby_bin="$brew_prefix/opt/ruby/bin"
    if [[ -d "$ruby_bin" ]]; then
        PATH="$ruby_bin:$PATH"
    fi
}

function chrome_brazil_proxy()
{
    _init_is_darwin || { echo "chrome_brazil_proxy: macOS only" >&2; return 1; }
    local port=${1:-1080}
    local ssh_host=${2:-}
    local chrome_data_dir="${HOME}/chrome-brazil-proxy"

    if [[ -z "$ssh_host" ]]; then
        echo "Usage: chrome_brazil_proxy [port] user@host" >&2
        return 1
    fi

    if lsof -i ":${port}" -sTCP:LISTEN >/dev/null 2>&1; then
        if ! lsof -i ":${port}" -sTCP:LISTEN -a -c ssh >/dev/null 2>&1; then
            echo "ERROR: port ${port} is in use by a non-ssh process:" >&2
            lsof -i ":${port}" -sTCP:LISTEN >&2
            return 1
        fi
    else
        "$init_tool_ssh" -D "${port}" -N -f "${ssh_host}"
        if [[ $? -ne 0 ]]; then
            echo "ERROR: failed to start SOCKS5 proxy on port ${port}" >&2
            return 1
        fi
    fi

    /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
        --user-data-dir="${chrome_data_dir}" \
        --proxy-server="socks5://127.0.0.1:${port}" \
        --proxy-bypass-list="localhost;127.0.0.1;<local>" \
        --host-resolver-rules="MAP * ~NOTFOUND , EXCLUDE 127.0.0.1 , EXCLUDE *.local"
}

function chrome_brazil_proxy_stop()
{
    local port=${1:-1080}
    local pid

    if ! lsof -i ":${port}" -sTCP:LISTEN >/dev/null 2>&1; then
        echo "No SOCKS5 proxy listening on port ${port}"
        return 0
    fi

    if ! lsof -i ":${port}" -sTCP:LISTEN -a -c ssh >/dev/null 2>&1; then
        echo "ERROR: port ${port} is in use by a non-ssh process:" >&2
        lsof -i ":${port}" -sTCP:LISTEN >&2
        return 1
    fi

    pid=$(lsof -ti ":${port}" -sTCP:LISTEN -a -c ssh)
    kill "${pid}"
    if [[ $? -ne 0 ]]; then
        echo "ERROR: failed to stop SOCKS5 proxy on port ${port}" >&2
        return 1
    fi

    echo "Stopped SOCKS5 proxy on port ${port} (pid ${pid})"
}

function dvol()
{
    _init_is_darwin || { echo "dvol: macOS only" >&2; return 1; }
    local increment=${1:--20}
    ivol "$increment"
}

function gvol()
{
    _init_is_darwin || { echo "gvol: macOS only" >&2; return 1; }
    "$init_tool_osascript" -e "output volume of (get volume settings)"
}

function ivol()
{
    _init_is_darwin || { echo "ivol: macOS only" >&2; return 1; }
    local increment=${1:-20}
    local current_vol new_vol
    current_vol=$("$init_tool_osascript" -e "output volume of (get volume settings)")
    new_vol=$((current_vol + increment))
    "$init_tool_osascript" -e "set volume output volume $new_vol"
}

# Toggle Logitech Litra light(s) when the litra CLI is provisioned.
if [[ -n "${init_tool_litra:-}" && -x "$init_tool_litra" ]]; then
function lt()
{
    "$init_tool_litra" toggle "$@"
}
fi

function rvi()
{
    local rpc
    _init_is_darwin || { echo "rvi: macOS only" >&2; return 1; }
    if [[ -z "${gvimcl:-}" || ! -x "$gvimcl" ]] || ! _init_vim_has_clientserver "$gvimcl"; then
        echo "rvi: MacVim (mvim with +clientserver) required" >&2
        return 1
    fi
    rpc="$(_init_vim_rpc_bin "$gvimcl")"
    if [[ "$*" = /* ]]; then
        "$rpc" --servername "${gvim_servername:-HCMA}" --remote-send ":split<space>$*<cr>"
    else
        "$rpc" --servername "${gvim_servername:-HCMA}" --remote-send ":split<space>$PWD/$*<cr>"
    fi
}

function rvii()
{
    local rpc
    _init_is_darwin || { echo "rvii: macOS only" >&2; return 1; }
    if [[ -z "${gvimcl:-}" || ! -x "$gvimcl" ]] || ! _init_vim_has_clientserver "$gvimcl"; then
        echo "rvii: MacVim (mvim with +clientserver) required" >&2
        return 1
    fi
    rpc="$(_init_vim_rpc_bin "$gvimcl")"
    if [[ "${*:2}" = /* ]]; then
        "$rpc" --servername "$1" --remote-send ":split<space>${*:2}<cr>"
    else
        "$rpc" --servername "$1" --remote-send ":split<space>$PWD/${*:2}<cr>"
    fi
}

function vol()
{
    _init_is_darwin || { echo "vol: macOS only" >&2; return 1; }
    "$init_tool_osascript" -e "set volume output volume $1"
}

fi

if ! _init_is_darwin; then
###### Linux functions

function start_agent
{
    local agent_cmd add_cmd

    if [[ "$OSTYPE" == "darwin"* ]]; then
        return
    fi

    agent_cmd="${init_tool_ssh_agent:-}"
    if [[ -z "$agent_cmd" || ! -x "$agent_cmd" ]]; then
        agent_cmd="$(command -v ssh-agent 2>/dev/null || true)"
    fi
    add_cmd="${init_tool_ssh_add:-}"
    if [[ -z "$add_cmd" || ! -x "$add_cmd" ]]; then
        add_cmd="$(command -v ssh-add 2>/dev/null || true)"
    fi
    if [[ -z "$agent_cmd" || -z "$add_cmd" ]]; then
        echo "start_agent: ssh-agent/ssh-add not found (run ~/.local/share/init-files/provision_init_files)" >&2
        return 1
    fi

    [[ -n "${ssh_env:-}" ]] || ssh_env="$HOME/.ssh/environment"
    "$agent_cmd" | sed 's/^echo/#echo/' > "${ssh_env}"
    chmod 600 "${ssh_env}"
    # shellcheck disable=SC1090
    . "${ssh_env}" > /dev/null
    "$add_cmd"
}

function startvnc()
{
    "$init_tool_vncserver" -geometry 1920x1080
}

function startvnc2()
{
    "$init_tool_vncserver" -geometry 3840x1080
}

function startvnch()
{
    "$init_tool_vncserver" -geometry 960x540
}

function startvnci2()
{
    "$init_tool_vncserver" -geometry 1280x1024
}

function startvncm()
{
    "$init_tool_vncserver" -geometry 1440x900
}

function startvncuhd()
{
    "$init_tool_vncserver" -geometry 3840x2160
}

function stopvnc()
{
    "$init_tool_vncserver" -kill "$@"
}

fi

###### environment

# editor fronts (absolute paths from install / init_tool_*)
#   v  → terminal vim  (vimcl)
#   vi → GUI window     (gvimcl: MacVim mvim on macOS, gvim on Linux)
vimcl="${init_tool_vim:-vim}"
gvim_servername="HCMA"
if _init_is_darwin; then
    gvimcl=
    if [[ -n "${init_tool_mvim:-}" && -x "$init_tool_mvim" ]]; then
        gvimcl="$init_tool_mvim"
    elif command -v mvim > /dev/null 2>&1; then
        gvimcl=$(command -v mvim)
    elif declare -F init_files_macvim_bin_candidates > /dev/null 2>&1; then
        while IFS= read -r _mvim_c; do
            [[ -n "$_mvim_c" && -x "$_mvim_c" ]] || continue
            gvimcl="$_mvim_c"
            break
        done < <(init_files_macvim_bin_candidates "$(_init_homebrew_prefix 2>/dev/null || true)")
        unset _mvim_c
    fi
else
    if [[ -n "${init_tool_gvim:-}" && -x "$init_tool_gvim" ]]; then
        gvimcl="$init_tool_gvim"
    elif command -v gvim > /dev/null 2>&1; then
        gvimcl=$(command -v gvim)
    else
        gvimcl=
    fi
fi

if ! _init_is_darwin && [[ ! -z "$HOME" ]]; then
    ssh_env="$HOME/.ssh/environment"
fi

# exported variables
export COLORTERM=truecolor
[[ -n "$init_tool_vim" ]] && export EDITOR="$init_tool_vim"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
# Ensure user bin dir exists before PATH (starship/pipx/gh local installs).
mkdir -p "${HOME}/.local/bin" 2>/dev/null || true
export PATH=$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/software/bin:$HOME/scripts/bin:/usr/local/sbin:$PATH
# Optional local checkout: repository-helpers scripts on PATH (scripts/dev wins on clashes).
_init_path_prepend "${HOME}/work/ai/repository-helpers/scripts"
_init_path_prepend "${HOME}/work/ai/repository-helpers/scripts/dev"
export TERM=xterm-256color
export TZ=America/New_York

# init-files refresh config
init_files_bashrc_src="${init_files_bashrc_src:-bashrc}"
init_files_check_stamp="${init_files_check_stamp:-${XDG_STATE_HOME:-$HOME/.local/state}/init-files/last-check}"
init_files_dir="${init_files_dir:-${XDG_DATA_HOME:-$HOME/.local/share}/init-files}"
init_files_max_age_seconds="${init_files_max_age_seconds:-86400}"
init_files_repo="${init_files_repo:-https://github.com/thehcma/init-files.git}"
init_files_repo_https="${init_files_repo_https:-https://github.com/thehcma/init-files.git}"
init_files_repo_ssh="${init_files_repo_ssh:-git@github.com:thehcma/init-files.git}"
init_files_state_dir="${init_files_state_dir:-${XDG_STATE_HOME:-$HOME/.local/state}/init-files}"
init_files_config_dir="${init_files_config_dir:-${XDG_CONFIG_HOME:-$HOME/.config}/init-files}"
# init_files_host may already be set at tools-load time above.
if [[ -z "${init_files_host:-}" ]]; then
    init_files_host="$(_init_files_sanitize_host "$(_init_files_raw_host_label)")"
fi
# Remembered per-host mode (NFS-safe). Legacy unscoped/state paths migrate on use.
init_files_no_dev_flag="${init_files_no_dev_flag:-$init_files_config_dir/no-dev.${init_files_host}}"
init_files_no_dev_flag_unscoped="${init_files_config_dir}/no-dev"
init_files_no_dev_flag_legacy="${init_files_state_dir}/no-dev"
# Remembered GitHub transport (NFS-safe for the flag; ~/.gitconfig is shared).
init_files_github_https_flag="${init_files_github_https_flag:-$init_files_config_dir/github-https.${init_files_host}}"
init_files_github_ssh_flag="${init_files_github_ssh_flag:-$init_files_config_dir/github-ssh.${init_files_host}}"
# Optional Starship (fancy) prompt preference for this host.
init_files_fancy_prompt_flag="${init_files_fancy_prompt_flag:-$init_files_config_dir/fancy-prompt.${init_files_host}}"

_init_files_migrate_no_dev_flag()
{
    if [[ -f "$init_files_no_dev_flag" ]]; then
        return 0
    fi
    mkdir -p "$init_files_config_dir" 2>/dev/null || true
    if [[ -f "$init_files_no_dev_flag_unscoped" ]]; then
        cp "$init_files_no_dev_flag_unscoped" "$init_files_no_dev_flag" 2>/dev/null || true
        rm -f "$init_files_no_dev_flag_unscoped" 2>/dev/null || true
    elif [[ -f "$init_files_no_dev_flag_legacy" ]]; then
        mv "$init_files_no_dev_flag_legacy" "$init_files_no_dev_flag" 2>/dev/null \
            || cp "$init_files_no_dev_flag_legacy" "$init_files_no_dev_flag" 2>/dev/null \
            || true
        rm -f "$init_files_no_dev_flag_legacy" 2>/dev/null || true
    fi
}

_init_files_is_no_dev_host()
{
    _init_files_migrate_no_dev_flag
    [[ -f "$init_files_no_dev_flag" ]]
}

_init_files_gh_authenticated()
{
    local gh_bin
    gh_bin="$(command -v gh 2>/dev/null || true)"
    [[ -n "$gh_bin" && -x "$gh_bin" ]] || return 1
    "$gh_bin" auth status >/dev/null 2>&1
}

# HTTPS when remembered, or when gh is logged in and SSH was not explicitly preferred.
# Auto-detect persists github-https.<host> so later shells skip `gh auth status`.
_init_files_is_github_https_host()
{
    if [[ -f "$init_files_github_https_flag" ]]; then
        return 0
    fi
    if [[ -f "${init_files_github_ssh_flag:-}" ]]; then
        return 1
    fi
    if _init_files_gh_authenticated; then
        mkdir -p "${init_files_config_dir:-$HOME/.config/init-files}" 2>/dev/null || true
        printf '1\n' > "$init_files_github_https_flag" 2>/dev/null || true
        return 0
    fi
    return 1
}


# HTTPS git via gh token header — never prompt for Username.
_init_files_git_https()
{
    local git_bin="$1"
    local token gh_bin basic
    shift
    gh_bin="$(command -v gh 2>/dev/null || true)"
    if [[ -n "$gh_bin" && -x "$gh_bin" ]]; then
        token=$("$gh_bin" auth token 2>/dev/null || true)
        if [[ -n "$token" ]]; then
            basic=$(printf 'x-access-token:%s' "$token" | base64 | tr -d '\n')
            # Clear helpers for this call so a broken osxkeychain/gh helper
            # cannot force an interactive username prompt.
            GIT_TERMINAL_PROMPT=0 "$git_bin" \
                -c credential.helper= \
                -c "http.extraHeader=Authorization: Basic ${basic}" \
                "$@"
            return $?
        fi
    fi
    GIT_TERMINAL_PROMPT=0 "$git_bin" "$@"
    return $?
}


# Preferred GitHub SSH private key on this host (overlay IdentityFile order, then
# generic candidates). OpenSSH 8 / FIPS often needs ed25519 rather than RSA.
_init_files_github_ssh_key()
{
    local key

    if declare -F init_files_preferred_ssh_key > /dev/null 2>&1; then
        key="$(init_files_preferred_ssh_key 2>/dev/null || true)"
        if [[ -n "$key" ]]; then
            printf '%s\n' "$key"
            return 0
        fi
    fi
    printf '%s\n' "${HOME}/.ssh/id_ed25519_github"
}

# Printed when BatchMode git SSH auth fails (no passphrase prompt during git).
_init_files_print_github_ssh_auth_help()
{
    local prefix="${1:-refresh_init_files}"
    local key key_disp

    key="$(_init_files_github_ssh_key)"
    # The tilde is a display-only abbreviated path.
    # shellcheck disable=SC2088
    case "$key" in
        "$HOME"/*) key_disp="~/${key#"$HOME"/}" ;;
        *) key_disp="$key" ;;
    esac

    echo "${prefix}: git failed (GitHub SSH auth)." >&2
    echo "  core.sshCommand uses BatchMode — git will not ask for a passphrase." >&2
    echo "  Bare ssh-add also fails if no agent is running. Prefer HTTPS when possible:" >&2
    echo "    refresh_init_files --github-https" >&2
    echo "  Or cache the preferred SSH key, then retry:" >&2
    if [[ -f "$key" ]]; then
        echo "    cache_ssh ${key_disp}" >&2
    else
        echo "    cache_ssh <path-to-key>   # from overlay .ssh/config.github IdentityFiles" >&2
    fi
    echo "    ssh -T git@github.com" >&2
    echo "    refresh_init_files    # or: git pull --rebase" >&2
}

# Align ~/.gitconfig insteadOf + init-files origin with this host's remembered
# GitHub transport. Safe to call from interactive startup and refresh_init_files.
_init_files_ensure_github_https_creds()
{
    # Point GitHub HTTPS at `gh auth git-credential`. Avoid osxkeychain seeding:
    # get+store triggered repeated Keychain ACL prompts (esp. from Cursor/agent).
    local git_bin="${init_tool_git:-}"
    local gh_bin helper
    local gh_helper='!gh auth git-credential'

    [[ -n "$git_bin" && -x "$git_bin" ]] || git_bin="$(command -v git 2>/dev/null || true)"
    [[ -n "$git_bin" && -x "$git_bin" ]] || return 0
    gh_bin="$(command -v gh 2>/dev/null || true)"
    [[ -n "$gh_bin" && -x "$gh_bin" ]] || return 0
    "$gh_bin" auth status >/dev/null 2>&1 || return 0

    helper=$("$git_bin" config --global --get credential.https://github.com.helper 2>/dev/null || true)
    if [[ "$helper" == "$gh_helper" ]]; then
        return 0
    fi

    "$git_bin" config --global --unset-all credential.https://github.com.helper 2>/dev/null || true
    "$git_bin" config --global --unset-all credential.https://gist.github.com.helper 2>/dev/null || true
    "$git_bin" config --global --add credential.https://github.com.helper '' 2>/dev/null || true
    "$git_bin" config --global --add credential.https://github.com.helper "$gh_helper" 2>/dev/null || true
    "$git_bin" config --global --add credential.https://gist.github.com.helper '' 2>/dev/null || true
    "$git_bin" config --global --add credential.https://gist.github.com.helper "$gh_helper" 2>/dev/null || true
}

_init_files_apply_github_transport()
{
    local git_bin="${init_tool_git:-}"
    local existing configured desired
    local instead_to='git@github.com:'
    local instead_from='https://github.com/'

    [[ -n "$git_bin" && -x "$git_bin" ]] || git_bin="$(command -v git 2>/dev/null || true)"
    [[ -n "$git_bin" && -x "$git_bin" ]] || return 0

    if _init_files_is_github_https_host; then
        existing=$("$git_bin" config --global --get "url.${instead_to}.insteadof" 2>/dev/null || true)
        if [[ -n "$existing" ]]; then
            "$git_bin" config --global --unset-all "url.${instead_to}.insteadOf" 2>/dev/null || true
        fi
        "$git_bin" config --global --unset-all core.sshCommand 2>/dev/null || true
        _init_files_ensure_github_https_creds
        desired="${init_files_repo_https:-$init_files_repo}"
    else
        existing=$("$git_bin" config --global --get "url.${instead_to}.insteadof" 2>/dev/null || true)
        if [[ "$existing" != "$instead_from" ]]; then
            "$git_bin" config --global "url.${instead_to}.insteadOf" "$instead_from" 2>/dev/null || true
        fi
        # Fail fast — never surface passphrase/Cursor askpass during git.
        "$git_bin" config --global core.sshCommand "ssh -o BatchMode=yes -o ConnectTimeout=10" 2>/dev/null || true
        desired="${init_files_repo_https:-$init_files_repo}"
    fi

    if [[ -d "${init_files_dir:-}/.git" && -n "$desired" ]]; then
        configured=$("$git_bin" -C "$init_files_dir" config --get remote.origin.url 2>/dev/null || true)
        if [[ "$configured" != "$desired" ]]; then
            "$git_bin" -C "$init_files_dir" remote set-url origin "$desired" >/dev/null 2>&1 || true
        fi
    fi
}

# tool-version check state (same host key as preference flags / PS1)
tool_version_host="${init_files_host}"
tool_version_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/tool-version-checks/${tool_version_host}"
tool_version_cache="$tool_version_state_dir/latest"
tool_version_max_age_seconds=86400


###### aliases

# Paths come from ~/.config/init-files/tools (written by `provision_init_files`).
# Optional-tool aliases are defined only when that tool was found.
# Tool paths are intentionally baked into aliases when this file is sourced.
# shellcheck disable=SC2139
{

[[ -n "$init_tool_bc" ]] && alias bc="$init_tool_bc -l"
alias brpmoff='printf "\e[?2004l"'
[[ -n "$init_tool_clear" ]] && alias cls="$init_tool_clear"
[[ -n "$init_tool_colordiff" ]] && alias diff="$init_tool_colordiff"
alias gatracking="${init_tool_git} for-each-ref --format='%(refname:short):%(upstream:short)' refs/heads"
alias gc="${init_tool_git} commit"
alias gd="${init_tool_git} diff --cached"
if [[ -n "$init_tool_less" ]]; then
    alias gdp="${init_tool_git} diff --color=always | $init_tool_less -r"
else
    alias gdp="${init_tool_git} diff --color=always"
fi
alias gec="${init_tool_git} config --global --edit"
alias gl="${init_tool_git} log"
alias glscommit="${init_tool_git} diff HEAD --name-only"
alias glsconflict="${init_tool_git} diff --name-only --diff-filter=U"
alias gpull="${init_tool_git} pull origin master"
alias gpullr="${init_tool_git} pull origin \$branchName"
alias gpullu="${init_tool_git} pull origin \$(${init_tool_git} rev-parse --abbrev-ref \$branchName@{u})"
alias gpush="${init_tool_git} push origin \$branchName"
[[ -n "$init_tool_grep" ]] && alias grep="$init_tool_grep --color=always"
alias gs="${init_tool_git} status"
alias gtldir="${init_tool_git} rev-parse --show-toplevel"
alias gtracking="${init_tool_git} rev-parse --abbrev-ref \$branchName@{u}"
alias gwb="${init_tool_git} branch"
if [[ -n "$init_tool_rsync" ]]; then
    alias scpresume="$init_tool_rsync --partial --progress --rsh=$init_tool_ssh"
fi
[[ -n "$init_tool_less" ]] && alias less="$init_tool_less"
# Listing aliases: prefer lsd when recorded/on PATH; else install-recorded ls; else PATH ls.
# Bare `ls` stays the real binary. lld/llm are functions (color-safe; see above).
_init_alias_lsd="${init_tool_lsd:-}"
if [[ -z "$_init_alias_lsd" || ! -x "$_init_alias_lsd" ]]; then
    _init_alias_lsd="$(command -v lsd 2>/dev/null || true)"
fi
_init_alias_ls="${init_tool_ls:-}"
if [[ -z "$_init_alias_ls" || ! -x "$_init_alias_ls" ]]; then
    _init_alias_ls="$(command -v ls 2>/dev/null || true)"
fi
if [[ -n "$_init_alias_lsd" ]]; then
    alias dir="$_init_alias_lsd -la"
    alias ll="$_init_alias_lsd -ahl"
elif [[ -n "$_init_alias_ls" ]]; then
    alias dir="$_init_alias_ls -la"
    if _init_is_darwin && ! _init_is_modern_macos; then
        alias ll="$_init_alias_ls -ahl"
    elif "$_init_alias_ls" --version >/dev/null 2>&1; then
        alias ll="$_init_alias_ls --color=always -ahl --time-style=full-iso"
    else
        alias ll="$_init_alias_ls -ahl"
    fi
fi
unset _init_alias_lsd _init_alias_ls
# Drop stale aliases from older bashrc loads so the functions win.
unalias lld llm 2>/dev/null || true
alias push="${init_tool_git} push"
[[ -n "$init_tool_rm" ]] && alias rm="$init_tool_rm -i"
alias srccount='rwc \*.cpp \*.h \*.y \*.l \*.pl \*.corba \*.java'

if _init_is_darwin; then
###### macOS aliases
if [[ -n "$init_tool_killall" ]]; then
    alias restartaudio="sudo $init_tool_killall coreaudiod"
fi
if [[ -n "$init_tool_launchctl" ]]; then
    alias restartvnc="sudo $init_tool_launchctl unload -w /System/Library/LaunchDaemons/com.apple.screensharing.plist && sudo $init_tool_launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist"
fi
if [[ -n "$init_tool_system_profiler" && -n "$init_tool_grep" ]]; then
    alias screenresolution="$init_tool_system_profiler SPDisplaysDataType | $init_tool_grep Resolution"
fi
fi

if ! _init_is_darwin; then
###### Linux aliases
[[ -n "$init_tool_google_chrome" ]] && alias chrome="$init_tool_google_chrome 2> /dev/null"
[[ -n "$init_tool_kwin" ]] && alias restartkwin="$init_tool_kwin --replace 2>&1 > /dev/null &"
[[ -n "$init_tool_terminator" ]] && alias term="$init_tool_terminator 2> /dev/null&"
[[ -n "$init_tool_lsb_release" ]] && alias version="$init_tool_lsb_release -a"
[[ -n "$init_tool_vncconfig" ]] && alias vncc="$init_tool_vncconfig -poll 10 2>/dev/null &"
fi
}

# Optional personal aliases/helpers from the private config overlay.
if declare -F init_files_source_bashrc_local > /dev/null 2>&1; then
    init_files_source_bashrc_local || true
fi

###### shell options

shopt -s checkwinsize
shopt -s cmdhist
shopt -s histappend
shopt -s lithist
# Bash 4+: recursive ** globs, cd-by-dirname, expand ~ in completion.
# Fail soft on Apple /bin/bash 3.2 and other builds that lack these.
shopt -s globstar 2>/dev/null || true
shopt -s autocd 2>/dev/null || true
shopt -s direxpand 2>/dev/null || true
set -o notify
set -o vi

if [[ $- == *i* ]]; then
    bind '"\C-l": clear-screen' 2>/dev/null || true
    # Readline completion knobs (apply regardless of emacs/vi keymap).
    bind 'set show-all-if-ambiguous on' 2>/dev/null || true
    bind 'set mark-symlinked-directories on' 2>/dev/null || true
    bind 'set completion-ignore-case on' 2>/dev/null || true
fi

HISTCONTROL=ignoredups
HISTFILESIZE=-1
HISTIGNORE='?:??'
HISTTIMEFORMAT='%F %T '
if [[ -f /etc/redhat-release ]] || [[ "$OSTYPE" == "darwin"* ]]; then
    HISTSIZE=
else
    HISTSIZE=-1
fi

###### initialization

# Pinentry needs a tty for passphrase prompts in interactive shells.
if [[ -z "${GPG_TTY:-}" ]]; then
    GPG_TTY=$(tty 2> /dev/null || true)
    [[ -n "$GPG_TTY" ]] && export GPG_TTY
fi

# macOS 26+ (Darwin 25+): Homebrew GNU userland only on modern macOS.
# Older macOS keeps the system (BSD) userland — Homebrew is not supported there.
if _init_is_darwin && _init_is_modern_macos; then
    _init_prepend_gnu_unix_tools
fi

# Activate fnm/nvm when present (preferred over Homebrew node on all tiers).
_init_load_node_toolchain || true

computer_name=$(_init_host_label)
export INIT_FILES_HOST_LABEL="$computer_name"
# Quiet-prompt allowlist (space-separated). Non-matching $USER → yellow-on-red
# badge (classic PS1 + starship via INIT_FILES_ALT_USER).
#   INIT_FILES_DEFAULT_USERS — full allowlist (env override)
#   INIT_FILES_DEFAULT_USER  — legacy singular: merged into the list (never
#                              replaces). To replace entirely, set USERS.
# Default allowlist lives in ~/.local/share/config/init-files/default-users.env
# (private config overlay). Without it, alt-user highlighting is disabled.
init_files_default_users=
if [[ -n "${INIT_FILES_DEFAULT_USERS+x}" ]]; then
    init_files_default_users="$INIT_FILES_DEFAULT_USERS"
elif declare -F init_files_source_default_users_env > /dev/null 2>&1 \
    && init_files_source_default_users_env; then
    init_files_default_users="${INIT_FILES_DEFAULT_USERS:-}"
fi
if [[ -n "${INIT_FILES_DEFAULT_USER:-}" ]]; then
    _init_du_found=0
    # shellcheck disable=SC2086
    for _init_du_c in ${init_files_default_users:-}; do
        if [[ "$_init_du_c" == "$INIT_FILES_DEFAULT_USER" ]]; then
            _init_du_found=1
            break
        fi
    done
    if [[ $_init_du_found -eq 0 ]]; then
        init_files_default_users="${init_files_default_users:+$init_files_default_users }$INIT_FILES_DEFAULT_USER"
    fi
    unset _init_du_found _init_du_c
fi
if [[ -n "$init_files_default_users" ]]; then
    export INIT_FILES_DEFAULT_USERS="$init_files_default_users"
else
    unset INIT_FILES_DEFAULT_USERS 2>/dev/null || true
fi
# Classic PS1: when allowlist is set and $USER is not on it, paint USER loudly.
# shellcheck disable=SC2119
if [[ -n "${INIT_FILES_DEFAULT_USERS:-}" ]] && ! _init_is_default_user; then
    export INIT_FILES_ALT_USER="${USER:-unknown}"
    _init_prompt_plain_ps1="\[\033[01;33;41m\]\u\[\033[00m\]|\[\033[01;32m\]\t|\$computer_name\[\033[00m\]|\[\033[01;33m\]\w\[\033[01;34m\]\$(gbn)\[\033[00m\]> "
else
    unset INIT_FILES_ALT_USER 2>/dev/null || true
    _init_prompt_plain_ps1="\[\033[01;32m\]\t|\$computer_name\[\033[00m\]|\[\033[01;33m\]\w\[\033[01;34m\]\$(gbn)\[\033[00m\]> "
fi
PS1="$_init_prompt_plain_ps1"
_init_prompt_mode=plain
ulimit -c unlimited

# ssh-agent (Linux): attach to ~/.ssh/environment or start a new agent.
# Use ssh-add -l (exit 2 = no agent) instead of grepping ps — more reliable.
if [[ -n "$HOME" && "$OSTYPE" != "darwin"* ]]; then
    _init_ssh_agent_bin="${init_tool_ssh_agent:-}"
    _init_ssh_add_bin="${init_tool_ssh_add:-}"
    if [[ -z "$_init_ssh_agent_bin" || ! -x "$_init_ssh_agent_bin" ]]; then
        _init_ssh_agent_bin="$(command -v ssh-agent 2>/dev/null || true)"
    fi
    if [[ -z "$_init_ssh_add_bin" || ! -x "$_init_ssh_add_bin" ]]; then
        _init_ssh_add_bin="$(command -v ssh-add 2>/dev/null || true)"
    fi
    if [[ -n "$_init_ssh_agent_bin" ]]; then
        [[ -n "${ssh_env:-}" ]] || ssh_env="$HOME/.ssh/environment"
        if [[ -f "$ssh_env" ]]; then
            # shellcheck disable=SC1090
            . "${ssh_env}" > /dev/null
        fi
        _init_ssh_agent_rc=0
        if [[ -z "${SSH_AUTH_SOCK:-}" || -z "$_init_ssh_add_bin" ]]; then
            _init_ssh_agent_rc=2
        else
            "$_init_ssh_add_bin" -l &>/dev/null
            _init_ssh_agent_rc=$?
        fi
        # 2 = cannot connect to agent; 1 = agent up but no keys (OK for now).
        if [[ $_init_ssh_agent_rc -eq 2 ]]; then
            start_agent
        fi
    fi
    unset _init_ssh_agent_bin _init_ssh_add_bin _init_ssh_agent_rc
fi

# history archive — unique per-session HISTFILE; shared history.all append log.
# Reuse HISTFILE across refresh_init_files FORCE reloads only when it is already our
# session file under bash_history_dir. Never keep bash's default ~/.bash_history
# (that caused history_sync to tail tens of GB into history.all and hang).
bash_history_dir="${XDG_STATE_HOME:-$HOME/.local/state}/bash"
mkdir -p "$bash_history_dir"
bash_history_archive="${bash_history_archive:-$bash_history_dir/history.all}"
bash_history_legacy_file="${bash_history_legacy_file:-$HOME/.bash_history}"
if [[ -n "${bash_history_session_ready:-}" \
    && -n "${HISTFILE:-}" \
    && "$HISTFILE" == "$bash_history_dir"/history.* \
    && -e "$HISTFILE" ]]
then
    : # keep live session file + byte offsets
else
    HISTFILE="$bash_history_dir/history.$(hostname -s 2> /dev/null || echo shell).$$.$(date +%Y%m%d%H%M%S)"
    # Truncate/create the session file so bash does not fall back elsewhere.
    : >> "$HISTFILE" 2>/dev/null || true
    bash_history_archive_bytes=0
    bash_history_legacy_bytes=0
    unset bash_history_bootstrapped
    history_bootstrap
    bash_history_session_ready=1
fi
# If a prior fancy session left starship_precmd in PROMPT_COMMAND (reload),
# unwrap before installing history_sync so we never get history_sync;starship_precmd.
if [[ "${PROMPT_COMMAND:-}" == *starship_precmd* ]]; then
    if type _init_prompt_unwrap_starship > /dev/null 2>&1; then
        _init_prompt_unwrap_starship
    else
        PROMPT_COMMAND="${PROMPT_COMMAND//starship_precmd/}"
        PROMPT_COMMAND="${PROMPT_COMMAND##;}"
        PROMPT_COMMAND="${PROMPT_COMMAND%%;}"
        PROMPT_COMMAND="${PROMPT_COMMAND//;;/;}"
    fi
fi
PROMPT_COMMAND="$(_init_prompt_ensure_session_hooks "${PROMPT_COMMAND-}")"
if [[ $- == *i* ]] && declare -F _init_iterm_report_host_label > /dev/null 2>&1; then
    _init_iterm_report_host_label
fi
# Re-install EXIT trap on reload (trap is not cleared by sourcing).
trap 'history_finalize' EXIT

# Quiet daily history rotate/dedupe when archives are soft-oversize (issue #9).
# Never blocks startup; history_sync stays append-only.
if [[ $- == *i* ]] && declare -F _init_maybe_schedule_history_rotate > /dev/null 2>&1; then
    _init_maybe_schedule_history_rotate
fi

# Optional Starship prompt (toggle: prompt_fancy / prompt_plain).
# Preference: ~/.config/init-files/fancy-prompt.<hostname> (set/cleared by the toggles).
if [[ $- == *i* && -f "${init_files_fancy_prompt_flag:-}" ]]; then
    prompt_fancy -q || printf 'init-files: fancy prompt preferred for this host but could not enable\n' >&2
fi

if [[ $- == *i* ]]; then
    # Unify legacy pipx dir names / rebake stale wrappers (no-op when already OK).
    if type migrate_pipx_host_layout > /dev/null 2>&1; then
        migrate_pipx_host_layout quiet 2>/dev/null || true
    fi
    if type rewrite_stale_pipx_wrappers > /dev/null 2>&1; then
        rewrite_stale_pipx_wrappers quiet 2>/dev/null || true
    fi
    # Emergency bypass: INIT_FILES_SKIP_TOOL_CHECK=1 source ~/.bashrc
    if [[ -z "${INIT_FILES_SKIP_TOOL_CHECK:-}" ]] && ! _init_is_rocky_8_1; then
        # Load bash-completion before the report so status shows the version
        # (BASH_COMPLETION_VERSINFO) instead of a bare "present".
        _init_load_bash_completion || true
        check_tool_versions
    else
        _init_load_bash_completion || true
    fi
    _init_load_fzf || true
    complete -o filenames -F _cda cda
    complete -o filenames -F _cdb cdb
    # After fzf (it rebinds ssh); cssh/cmsh/cesh are functions and need an explicit complete.
    if type _init_bind_cssh_cmsh_completion > /dev/null 2>&1; then
        _init_bind_cssh_cmsh_completion
    fi
    # Align GitHub transport with this host's preference before daily check.
    if type _init_files_apply_github_transport > /dev/null 2>&1; then
        _init_files_apply_github_transport
    fi
    # Skip when reloading after refresh_init_files (avoids recursion).
    # Emergency bypass: INIT_FILES_SKIP_DAILY_REFRESH=1 source ~/.bashrc
    if [[ -z "${_init_files_in_refresh_reload:-}" && -z "${INIT_FILES_SKIP_DAILY_REFRESH:-}" ]]; then
        refresh_init_files -q || true
    fi
fi

# Agent tool shells export CURSOR_CONVERSATION_ID — record for later resume even
# if the CLI statusline is not configured on this host.
if [[ -n "${CURSOR_CONVERSATION_ID:-}" ]] && type _init_files_record_agent_session > /dev/null 2>&1; then
    _init_files_record_agent_session "$CURSOR_CONVERSATION_ID" "${PWD:-}"
fi
