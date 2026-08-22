#!/usr/bin/env python3
"""Merge curated Terminal.app profile settings (font only for now)."""

from __future__ import annotations

import importlib.util
import json
import plistlib
import sys
from pathlib import Path
from typing import Any

DOMAIN = "com.apple.Terminal"
SETTINGS_KEY = "Window Settings"


def _load_iterm_prefs_module():
    path = Path(__file__).resolve().parent.parent / "iterm2" / "_prefs.py"
    spec = importlib.util.spec_from_file_location("iterm_prefs", path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_settings(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise SystemExit(f"expected object JSON at {path}")
    profiles = data.get("profiles")
    if not isinstance(profiles, dict) or not profiles:
        raise SystemExit(f"settings missing profiles: {path}")
    return data


def font_blob(name: str, size: float) -> bytes:
    payload = {
        "$version": 100000,
        "$archiver": "NSKeyedArchiver",
        "$top": {"root": plistlib.UID(1)},
        "$objects": [
            "$null",
            {
                "NSSize": float(size),
                "NSfFlags": 16,
                "NSName": plistlib.UID(2),
                "$class": plistlib.UID(3),
            },
            name,
            {"$classname": "NSFont", "$classes": ["NSFont", "NSObject"]},
        ],
    }
    return plistlib.dumps(payload, fmt=plistlib.FMT_BINARY)


def merge(existing: dict[str, Any], curated: dict[str, Any]) -> dict[str, Any]:
    merged = dict(existing)
    profiles = merged.setdefault(SETTINGS_KEY, {})
    if not isinstance(profiles, dict):
        profiles = {}
        merged[SETTINGS_KEY] = profiles

    for profile_name, patch in curated.get("profiles", {}).items():
        if not isinstance(patch, dict):
            continue
        profile = profiles.setdefault(profile_name, {})
        if not isinstance(profile, dict):
            profile = {}
            profiles[profile_name] = profile

        font = patch.get("font")
        if isinstance(font, dict):
            name = str(font.get("name") or "").strip()
            try:
                size = float(font.get("size", 15))
            except (TypeError, ValueError):
                size = 15.0
            if name and size > 0:
                profile["Font"] = font_blob(name, size)

        for key, value in patch.items():
            if key == "font":
                continue
            profile[key] = value

    return merged


def iter_required_fonts(curated: dict[str, Any]) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    seen: set[str] = set()
    for patch in curated.get("profiles", {}).values():
        if not isinstance(patch, dict):
            continue
        font = patch.get("font")
        if not isinstance(font, dict):
            continue
        name = str(font.get("name") or "").strip()
        if not name or name in seen:
            continue
        seen.add(name)
        try:
            size = float(font.get("size", 15))
        except (TypeError, ValueError):
            size = 15.0
        out.append((name, f"{name} {size:g}"))
    return out


def check_fonts(curated: dict[str, Any]) -> int:
    iterm = _load_iterm_prefs_module()
    missing = 0
    for family, spec in iter_required_fonts(curated):
        if iterm.font_is_installed(family):
            print(f"ok\t{family}\t{spec}")
        else:
            print(f"missing\t{family}\t{spec}")
            missing = 1
    return missing


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(
            f"usage: {argv[0]} merge|check-fonts IN OUT|SETTINGS.json",
            file=sys.stderr,
        )
        return 2
    cmd = argv[1]
    if cmd == "merge":
        if len(argv) != 5:
            print(
                f"usage: {argv[0]} merge EXISTING.plist SETTINGS.json OUT.plist",
                file=sys.stderr,
            )
            return 2
        existing_path = Path(argv[2])
        existing = (
            plistlib.load(existing_path.open("rb"))
            if existing_path.is_file()
            else {}
        )
        if not isinstance(existing, dict):
            raise SystemExit(f"expected dict plist at {existing_path}")
        curated = load_settings(Path(argv[3]))
        out = merge(existing, curated)
        with Path(argv[4]).open("wb") as fh:
            plistlib.dump(out, fh, fmt=plistlib.FMT_XML, sort_keys=True)
        return 0
    if cmd == "check-fonts":
        if len(argv) != 3:
            print(f"usage: {argv[0]} check-fonts SETTINGS.json", file=sys.stderr)
            return 2
        curated = load_settings(Path(argv[2]))
        return check_fonts(curated)
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
