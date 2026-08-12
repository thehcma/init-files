#!/usr/bin/env python3
"""Ensure ~/.cursor/cli-config.json defaults for agent launches.

Resets:
  - default model → Auto (in-chat /model switches rewrite this file)
  - editor.vimMode → true (CLI/UI can turn vim off)
  - statusLine → init-files cursor/statusline (tab title + session record)

Call before every new/resumed chat launch.
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

AUTO_MODEL = {
    "modelId": "default",
    "displayModelId": "auto",
    "displayName": "Auto",
    "displayNameShort": "Auto",
    "aliases": ["auto"],
    "maxMode": False,
}
AUTO_SELECTED = {"modelId": "default", "parameters": []}

# Per-session status line + tab title (must stay wired; Cursor may omit it).
STATUSLINE = {
    "type": "command",
    "command": "~/.local/share/init-files/cursor/statusline",
    "padding": 2,
}


def config_path() -> Path:
    override = os.environ.get("CURSOR_CLI_CONFIG")
    if override:
        return Path(override)
    return Path.home() / ".cursor" / "cli-config.json"


def is_auto(data: dict) -> bool:
    model = data.get("model") or {}
    selected = data.get("selectedModel") or {}
    mid = str(model.get("modelId") or "")
    did = str(model.get("displayModelId") or "")
    smid = str(selected.get("modelId") or "")
    aliases = model.get("aliases") or []
    if not isinstance(aliases, list):
        aliases = []
    autoish = {"default", "auto"}
    return (
        mid in autoish
        and smid in autoish
        and (did in autoish or did == "" or "auto" in [str(a).lower() for a in aliases])
    )


def is_vim(data: dict) -> bool:
    editor = data.get("editor")
    if not isinstance(editor, dict):
        return False
    return editor.get("vimMode") is True


def statusline_ok(data: dict) -> bool:
    """True when statusLine invokes init-files cursor/statusline (no .sh)."""
    sl = data.get("statusLine")
    if not isinstance(sl, dict):
        return False
    if str(sl.get("type") or "") != "command":
        return False
    cmd = str(sl.get("command") or "").replace("~/", "")
    # Require the extensionless path; legacy …/statusline.sh is rewritten.
    return bool(re.search(r"(^|/)init-files/cursor/statusline([\"'\s]|$)", cmd))

def ensure(*, quiet: bool = False) -> int:
    path = config_path()
    if not path.is_file():
        if not quiet:
            print(f"ensure_model_auto: no config at {path}", file=sys.stderr)
        return 0
    try:
        data = json.loads(path.read_text())
    except Exception as exc:
        print(f"ensure_model_auto: cannot read {path}: {exc}", file=sys.stderr)
        return 1
    if not isinstance(data, dict):
        print(f"ensure_model_auto: {path} is not a JSON object", file=sys.stderr)
        return 1

    changed = False
    notes: list[str] = []

    if not is_auto(data):
        prev = (data.get("model") or {}).get("displayModelId") or (
            data.get("model") or {}
        ).get("modelId") or "?"
        data["model"] = dict(AUTO_MODEL)
        data["selectedModel"] = dict(AUTO_SELECTED)
        data["hasChangedDefaultModel"] = False
        hist = data.get("modelSelectionHistory")
        if not isinstance(hist, list):
            hist = []
        data["modelSelectionHistory"] = ["default"] + [x for x in hist if x != "default"]
        changed = True
        notes.append(f"reset CLI default {prev} → Auto")

    if not is_vim(data):
        editor = data.get("editor")
        if not isinstance(editor, dict):
            editor = {}
        editor["vimMode"] = True
        data["editor"] = editor
        changed = True
        notes.append("enabled editor.vimMode")

    if not statusline_ok(data):
        data["statusLine"] = dict(STATUSLINE)
        changed = True
        notes.append("wired statusLine → init-files cursor/statusline")

    if not changed:
        return 0

    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=4) + "\n")
    tmp.replace(path)
    if not quiet:
        for note in notes:
            print(f"ensure_model_auto: {note} ({path})", file=sys.stderr)
    return 0


def main(argv: list[str]) -> int:
    quiet = False
    check_only = False
    for a in argv:
        if a in ("-q", "--quiet"):
            quiet = True
        elif a in ("--check",):
            check_only = True
        elif a in ("-h", "--help"):
            print(
                "usage: ensure_model_auto.py [--check] [-q|--quiet]",
                file=sys.stderr,
            )
            return 0
    path = config_path()
    if check_only:
        if not path.is_file():
            print("missing")
            return 1
        data = json.loads(path.read_text())
        if not isinstance(data, dict):
            print("invalid")
            return 1
        auto_ok = is_auto(data)
        vim_ok = is_vim(data)
        sl_ok = statusline_ok(data)
        mid = ((data.get("model") or {}).get("displayModelId")
               or (data.get("model") or {}).get("modelId") or "?")
        print("auto" if auto_ok else f"drift:{mid}")
        print("vim:on" if vim_ok else "vim:off")
        print("statusLine:on" if sl_ok else "statusLine:off")
        return 0 if (auto_ok and vim_ok and sl_ok) else 1
    return ensure(quiet=quiet)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
