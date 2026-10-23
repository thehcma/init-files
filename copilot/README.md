# copilot/ — Copilot CLI personal guidelines

Canonical `~/.copilot/copilot-instructions.md`, the user-level instructions file the Copilot CLI loads each session (personal guidelines that apply to every project, e.g. how to report times). The rest of `~/.copilot/` (settings, sessions, logs, caches) is local runtime state or managed elsewhere and is **not** touched here. The repo-level `.github/copilot-instructions.md` is a separate file.

| Path | Role |
| --- | --- |
| `copilot/copilot-instructions.md` | Canonical personal guidelines, deployed via symlink. |
| `~/.copilot/copilot-instructions.md` | Symlink → this file (created by `./provision_init_files` or `refresh_copilot_instructions`). |

## Deploy

```bash
./provision_init_files          # symlinks ~/.copilot/copilot-instructions.md -> this dir
# later, to repair drift:
refresh_copilot_instructions
```

`provision_init_files` **backs up** an existing regular-file `~/.copilot/copilot-instructions.md` (to `~/.copilot/copilot-instructions.md.bak.<timestamp>`, plus a copy under `~/.local/state/init-files/copilot-backup/`) before replacing it with the symlink.

## Drift detection

Daily `refresh_init_files -q` detects a missing/wrong `~/.copilot/copilot-instructions.md` symlink and offers to repair it via `refresh_copilot_instructions` (or `refresh_init_files` when other deployables also drifted). `init_files_doctor` reports the symlink status read-only.

Edit `copilot/copilot-instructions.md` in the clone; the `~/.copilot/` path is a symlink into it.
