#!/usr/bin/env python3
"""Merge curated Mos (com.caldis.Mos) per-app scroll overrides.

Mos stores its per-app list under the ``applications`` UserDefaults key as a
``Data`` blob holding a UTF-8 JSON array of ``Application`` objects. In its
default blocklist mode (``allowlist`` = false) an app in that list is *not*
skipped — it just carries per-app overrides, and with ``inherit`` = true those
overrides resolve to the global settings. So the only way to stop Mos smoothing
one app is an entry with ``inherit`` = false and a full ``scroll`` block whose
``smooth`` is false.

This helper expands each curated entry ({path, displayName, smooth}) into that
full object, mirroring the live *global* scroll fields so the app keeps global
feel (direction, dead zone) and only loses smoothing. Merge is by ``path``
(upsert): existing entries for other apps are left untouched.
"""

from __future__ import annotations

import copy
import json
import plistlib
import sys
from pathlib import Path
from typing import Any

DOMAIN = "com.caldis.Mos"
APPLICATIONS_KEY = "applications"

# Per-app scroll fields Mos's synthesized Codable requires (all non-optional
# stored properties of OPTIONS_SCROLL_DEFAULT). Mirrored from the live global
# value of the same name; class default is the fallback when the global prefs
# domain has no explicit value yet.
SCROLL_FIELDS: dict[str, Any] = {
    "smooth": True,
    "reverse": True,
    "reverseVertical": True,
    "reverseHorizontal": True,
    "step": 33.6,
    "speed": 2.70,
    "duration": 4.35,
    "deadZone": 1.00,
    "smoothSimTrackpad": False,
    "smoothVertical": True,
    "smoothHorizontal": True,
}
_BOOL_FIELDS = {k for k, v in SCROLL_FIELDS.items() if isinstance(v, bool)}


def _coerce(key: str, value: Any) -> Any:
    default = SCROLL_FIELDS[key]
    if key in _BOOL_FIELDS:
        return bool(value)
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def scroll_block(existing: dict[str, Any], *, smooth: bool) -> dict[str, Any]:
    """Full per-app scroll dict: live global values, with smoothing forced."""
    block = {
        key: _coerce(key, existing.get(key, default))
        for key, default in SCROLL_FIELDS.items()
    }
    block["smooth"] = smooth
    if not smooth:
        # Belt and suspenders: the axis toggles only matter when smooth is on,
        # but keep them consistent so a future Mos can't re-enable via an axis.
        block["smoothVertical"] = False
        block["smoothHorizontal"] = False
    return block


def application_entry(
    existing: dict[str, Any], curated: dict[str, Any]
) -> dict[str, Any]:
    path = str(curated.get("path") or "").strip()
    if not path:
        raise SystemExit("mos/_prefs: curated application entry missing 'path'")
    smooth = bool(curated.get("smooth", False))
    entry: dict[str, Any] = {"path": path, "inherit": False}
    display_name = str(curated.get("displayName") or "").strip()
    if display_name:
        entry["displayName"] = display_name
    entry["scroll"] = scroll_block(existing, smooth=smooth)
    return entry


def load_applications(existing: dict[str, Any]) -> list[dict[str, Any]]:
    raw = existing.get(APPLICATIONS_KEY)
    if raw is None:
        return []
    if isinstance(raw, (bytes, bytearray)):
        text = bytes(raw).decode("utf-8")
    elif isinstance(raw, str):
        text = raw
    else:
        return []
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return []
    return [x for x in data if isinstance(x, dict)]


def dump_applications(apps: list[dict[str, Any]]) -> bytes:
    return json.dumps(apps, separators=(",", ":")).encode("utf-8")


def load_curated(path: Path) -> list[dict[str, Any]]:
    with path.open(encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise SystemExit(f"expected object JSON at {path}")
    apps = data.get("applications")
    if not isinstance(apps, list):
        raise SystemExit(f"settings missing 'applications' array: {path}")
    return [x for x in apps if isinstance(x, dict)]


def merged_applications(
    existing: dict[str, Any], curated: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    apps = load_applications(existing)
    index = {a.get("path"): i for i, a in enumerate(apps) if a.get("path")}
    for entry in curated:
        built = application_entry(existing, entry)
        pos = index.get(built["path"])
        if pos is None:
            index[built["path"]] = len(apps)
            apps.append(built)
        else:
            apps[pos] = built
    return apps


def merge(existing: dict[str, Any], curated: list[dict[str, Any]]) -> dict[str, Any]:
    out = copy.deepcopy(existing)
    out[APPLICATIONS_KEY] = dump_applications(merged_applications(existing, curated))
    return out


def is_applied(existing: dict[str, Any], curated: list[dict[str, Any]]) -> bool:
    return load_applications(existing) == merged_applications(existing, curated)


def load_plist(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    with path.open("rb") as fh:
        data = plistlib.load(fh)
    if not isinstance(data, dict):
        raise SystemExit(f"expected dict plist at {path}")
    return data


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(f"usage: {argv[0]} merge|equal|paths ...", file=sys.stderr)
        return 2
    cmd = argv[1]
    if cmd == "merge":
        if len(argv) != 5:
            print(
                f"usage: {argv[0]} merge EXISTING.plist SETTINGS.json OUT.plist",
                file=sys.stderr,
            )
            return 2
        existing = load_plist(Path(argv[2]))
        curated = load_curated(Path(argv[3]))
        out = merge(existing, curated)
        with Path(argv[4]).open("wb") as fh:
            plistlib.dump(out, fh, fmt=plistlib.FMT_XML, sort_keys=True)
        return 0
    if cmd == "equal":
        if len(argv) != 4:
            print(
                f"usage: {argv[0]} equal EXISTING.plist SETTINGS.json",
                file=sys.stderr,
            )
            return 2
        existing = load_plist(Path(argv[2]))
        curated = load_curated(Path(argv[3]))
        return 0 if is_applied(existing, curated) else 1
    if cmd == "paths":
        if len(argv) != 3:
            print(f"usage: {argv[0]} paths SETTINGS.json", file=sys.stderr)
            return 2
        for entry in load_curated(Path(argv[2])):
            path = str(entry.get("path") or "").strip()
            if path:
                print(path)
        return 0
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
