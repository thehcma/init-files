# claude/ — Claude Code CLI settings

Canonical `~/.claude/settings.json` (model, theme, editor mode, attribution —
no secrets, no session/runtime state). The rest of `~/.claude/` (history,
sessions, cache, projects, stats, plugins) is local runtime state and is
**not** tracked here — only `settings.json` is a config worth sharing across
hosts.

| Path | Role |
| --- | --- |
| `claude/settings.json` | Canonical config, deployed via symlink. |
| `~/.claude/settings.json` | Symlink → this file (created by `./provision_init_files` or `refresh_claude_settings`). |

## Deploy

```bash
./provision_init_files          # symlinks ~/.claude/settings.json -> this file
# later, to repair drift:
refresh_claude_settings
```

`provision_init_files` **backs up** any existing regular-file
`~/.claude/settings.json` (to `~/.claude/settings.json.bak.<timestamp>`, plus a
copy under `~/.local/state/init-files/claude-backup/`) before replacing it
with the symlink. It does not touch any other file under `~/.claude/`.

## Drift detection

Daily `refresh_init_files -q` detects a missing/wrong `~/.claude/settings.json`
symlink (same pattern as the `~/.vimrc` check) and offers to repair it via
`refresh_claude_settings` (or `refresh_init_files` when other deployables also
drifted). `init_files_doctor` reports the symlink status read-only.

## iTerm2 status-bar integration (`hooks`)

`hooks.*` wires every Claude Code hook event to
`$HOME/.config/iterm2/cc-status` — iTerm2's own built-in Claude Code
status-bar helper (a symlink iTerm2 manages itself, normally pointing at
`/Applications/iTerm.app/Contents/Resources/utilities/cc-status`). The
command uses `$HOME` rather than a literal `/Users/<name>` path so it stays
portable across accounts/hosts, consistent with the tool-path-consistency
rule. If iTerm2 isn't installed, or that symlink doesn't exist yet, the hook
command just no-ops/fails harmlessly.

iTerm2 sometimes rewrites `~/.claude/settings.json` in place when
(re)installing this integration, which can replace the symlink with a plain
file (breaking the deploy model). `refresh_init_files` / `init_files_doctor`
detect that drift the same way as any other symlink drift and offer to
repair it via `refresh_claude_settings` — repairing restores this same
`hooks` block from the tracked file, so nothing is lost.

## Editing

Edit `claude/settings.json` in the clone (not `~/.claude/settings.json`
directly — it's a symlink into the clone, so editing either path edits the
same file). Commit/push when asked, per [AGENTS.md](../AGENTS.md).
