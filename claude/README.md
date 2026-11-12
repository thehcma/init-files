# claude/ — Claude Code CLI settings

Canonical `~/.claude/settings.json` (model, theme, editor mode, attribution —
no secrets, no session/runtime state) and `~/.claude/CLAUDE.md` (personal
guidelines that apply to every project, e.g. how to report times). The rest of
`~/.claude/` (history, sessions, cache, projects, stats, plugins) is local
runtime state and is **not** tracked here — only these two files are configs
worth sharing across hosts.

| Path | Role |
| --- | --- |
| `claude/settings.json` | Canonical config, deployed via symlink. |
| `~/.claude/settings.json` | Symlink → this file (created by `./provision_init_files` or `refresh_claude_settings`). |
| `claude/CLAUDE.md` | Canonical personal guidelines, deployed via symlink. Optional: linked only when this file exists in the clone. |
| `~/.claude/CLAUDE.md` | Symlink → this file (same provisioning and repair path as `settings.json`). |

## Deploy

```bash
./provision_init_files          # symlinks ~/.claude/settings.json and CLAUDE.md -> this dir
# later, to repair drift:
refresh_claude_settings
```

`provision_init_files` **backs up** any existing regular-file
`~/.claude/settings.json` or `~/.claude/CLAUDE.md` (to `~/.claude/<name>.bak.<timestamp>`, plus a
copy under `~/.local/state/init-files/claude-backup/`) before replacing it
with the symlink. It does not touch any other file under `~/.claude/`.

## Drift detection

Daily `refresh_init_files -q` detects a missing/wrong `~/.claude/settings.json`
or `~/.claude/CLAUDE.md` symlink (same pattern as the `~/.vimrc` check) and offers to repair it via
`refresh_claude_settings` (or `refresh_init_files` when other deployables also
drifted). `init_files_doctor` reports the symlink status read-only.

## iTerm2 status-bar integration (`hooks`)

`hooks.*` wires every Claude Code hook event to
`$HOME/.config/iterm2/cc-status` — iTerm2's own built-in Claude Code
status-bar helper (a symlink iTerm2 manages itself, normally pointing at
`/Applications/iTerm.app/Contents/Resources/utilities/cc-status`). The
command uses `$HOME` rather than a literal `/Users/<name>` path so it stays
portable across accounts/hosts, consistent with the tool-path-consistency
rule. The command must stay unwrapped (no `uname` guard): iTerm2's health check
rejects commands that run more than cc-status and keeps prompting to
reinstall. On non-Darwin hosts `provision_init_files` creates a no-op
`~/.config/iterm2/cc-status` stub instead.

iTerm2 sometimes rewrites `~/.claude/settings.json` in place when
(re)installing this integration, which can replace the symlink with a plain
file (breaking the deploy model). `refresh_init_files` / `init_files_doctor`
detect that drift the same way as any other symlink drift and offer to
repair it via `refresh_claude_settings` — repairing restores this same
`hooks` block from the tracked file, so nothing is lost.

## Launchers: `claude`, `claude-bhe`, `claude-brk-commons`

Three shell functions in `bashrc` start Claude Code against different backends.
All three forward their arguments and run inside the iTerm2 session wrapper.

| Function | Backend | Environment |
| --- | --- | --- |
| `claude` | Whatever the shell already has | Inherited unchanged. |
| `claude-bhe` | The default (BHE Anthropic tenant) login | Gateway, API-key and model overrides are dropped for the call. |
| `claude-brk-commons` | The BRK Commons LiteLLM gateway | Read from `~/.config/brk-commons/llm-gateway.env` (override the path with `BRK_COMMONS_LLM_GATEWAY_ENV`). |

The gateway env file is local and never tracked. It must be owned by you, not
group/other-writable and use LF line endings. It sets `ANTHROPIC_BASE_URL`,
`ANTHROPIC_AUTH_TOKEN` and the models the gateway serves, for example
`ANTHROPIC_DEFAULT_SONNET_MODEL=claude-sonnet-5.5` and
`ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-haiku-5.5`. The values are set in a
subshell, so nothing leaks into the interactive shell.

### Why the launcher defaults `ANTHROPIC_DEFAULT_OPUS_MODEL`

The gateway serves dotted ids (`claude-opus-5.5`), while Claude Code's built-in
`opus` alias resolves to `claude-opus-5-5`, which the gateway refuses with a
`400 Invalid model name`. `claude-brk-commons` therefore exports
`ANTHROPIC_DEFAULT_OPUS_MODEL=claude-opus-5.5` when the env file does not set
one (a value in the env file always wins). Without it, anything that asks for
`--model opus` through the gateway fails, including
`repository-helpers/scripts/dev/model-review`, which needs a reviewer other
than the Sonnet author.

### `availableModels` and silent model fallback

`claude/settings.json` restricts `availableModels` to `sonnet` and `haiku`
(enforced). `claude --model opus` is then outside the policy and Claude Code
silently answers from its default model instead of failing: on a native login
the "opus" call really runs on Sonnet, and behind the gateway the built-in
default id is refused. A caller that needs a different model must pin it for
that one call, for example
`claude -p --model opus --settings '{"availableModels":["opus"]}'`, which is
what `model-review` does by default. The restriction in `settings.json` stays as
it is for interactive sessions.

## Editing

Edit `claude/settings.json` / `claude/CLAUDE.md` in the clone (not the
`~/.claude/` paths directly — it's a symlink into the clone, so editing either path edits the
same file). Commit/push when asked, per [AGENTS.md](../AGENTS.md).
