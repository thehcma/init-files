# House + GitHub SSH materials

User-specific SSH materials live in a **private config overlay** (not this repo):

| Overlay file | Installed to |
| --- | --- |
| `.ssh/authorized_keys.house` | Merged into `~/.ssh/authorized_keys` |
| `.ssh/config.house` | `~/.ssh/config.d/init-files-house.conf` |
| `.ssh/config.github` | Parsed → `~/.ssh/config.d/init-files-github.conf` |

Default clone path: `~/.local/share/config`. Git URL is **prompted interactively** (or set via `INIT_FILES_CONFIG_REPO`) and remembered in `~/.config/init-files/config-repo`. Init-files never hardcodes a private overlay remote.

`provision_init_files` / `bootstrap_host` **flag** a missing or incomplete overlay (`ERROR` + fix steps), then interactively offer clone / re-check until the three `.ssh` files are present (or you explicitly skip for a generic install). Quiet (`-q`) prints the same error + steps and exits the overlay step without pretending success.

Primary-user allowlist (`INIT_FILES_DEFAULT_USERS`) is optional: `config/init-files/default-users.env` in the overlay. Personal aliases/helpers are optional: `config/init-files/bashrc.local` (sourced by interactive bashrc when present).

## Public init-files goal

Generic init-files content is prepared for a **public** repo so bootstrap works via `curl` without GitHub auth for the dotfiles themselves. House topology, pubkeys, and personal usernames stay only in your private overlay.

## Bootstrap (no prior clone)

```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/init-files/main/bootstrap_host \
  -o /tmp/bootstrap_host
chmod +x /tmp/bootstrap_host
/tmp/bootstrap_host
source ~/.bashrc
```

Guided **gh auth login (HTTPS)** is the default; `--key-from HOST` copies a house key for inter-host SSH. When prompted, supply your private config overlay URL if you use house SSH materials.
