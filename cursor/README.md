# Cursor Agent CLI helpers

| Path | Role |
| --- | --- |
| `statusline` | Agent UI status line + records session; sets **iTerm tab title** to short id |
| `agent_sessions.py` | List / name / resolve sessions for unambiguous resume |
| `ensure_model_auto.py` | Reset CLI default model to Auto, force `editor.vimMode`, wire `statusLine` |

## The problem

If three `agent` sessions run on the same remote host and a terminal dies, “most recent” is ambiguous. The starter shell never had `CURSOR_CONVERSATION_ID`. After reconnect you get a new tty, so tty alone cannot match.

Many panes are **SSH into other boxes**. The corner iTerm badge is easy to mis-associate across splits; the **tab/window title** (OSC 0/1/2) is what travels cleanly over SSH and is what we use as the primary identifier.

## How we disambiguate

1. **While alive** — iTerm **tab title** (OSC) and the **left side of the pane status bar** (`user.agentsession`) show the short id (`2e376153`, or `2e376153:name` if named). No corner badge (stale badges are cleared). When `agent` exits, both are cleared so the pane returns to host-only chrome (`user.hostlabel`). (When the status bar is embedded in the pane title, iTerm hides the title label — the status-bar slot is required while the agent runs.)
2. **Name them** — `name_agent_session jerico-dns` or start with `agent --name jerico-dns` (name appears in the title and resume lists).
3. **After death** — `agent_sessions` / `resume_agent_session` (ids stay in the on-disk session list even after the pane chrome is cleared).

Default model is **Auto**, and vim keybindings are **on**. Before every chat launch, `agent` runs `cursor/ensure_model_auto.py`, which resets `~/.cursor/cli-config.json` if an in-chat `/model` switch drifted it away from Auto, re-enables `editor.vimMode` if it was turned off, **ensures `statusLine` points at `cursor/statusline`**, then passes `--model auto` (unless you already passed `--model …`).

```bash
python3 ~/.local/share/init-files/cursor/ensure_model_auto.py --check
# auto
# vim:on
# statusLine:on
agent about   # Model should be Auto; input uses vim bindings
```

`resume_agent_session` with no args **refuses** to guess.

## Wire status line (per machine)

`ensure_model_auto` keeps this in `~/.cursor/cli-config.json` automatically. Manual form:

```json
"statusLine": {
  "type": "command",
  "command": "~/.local/share/init-files/cursor/statusline",
  "padding": 2
}
```

Restart `agent` after changing the config (or after a fresh `ensure_model_auto` fix on a host that never had `statusLine`).

On remote hosts, the clone path must exist (`~/.local/share/init-files`); `refresh_init_files` / `bootstrap_host` there so the statusline script and `agent` wrapper are available.

## Commands

```bash
# Start a new chat already labeled (recommended):
agent --name jerico-dns
agent -N jerico-vim "fix the title id"

# Or name later (from an agent tool shell, or pass the id):
name_agent_session jerico-dns
name_agent_session jerico-dns 2e376153-a303-42f6-bb85-5aada143b657

agent_sessions                         # rich list
agent_sessions dns                     # filter by prompt/name/cwd/id

# Resume via fzf (named sessions listed first):
resume_agent_session                   # fzf picker
resume_agent_session --named           # fzf, named only
resume_agent_session jerico-vim        # by name
resume_agent_session 2                 # by list index
resume_agent_session 2e376153-a303-…   # by id / unique prefix
```

State (host-local, not in git): `~/.local/state/init-files/agent-session-names.json`
