#!/usr/bin/env python3
"""Curate and merge iTerm2 prefs (font/colors/keyboard/mouse only)."""

from __future__ import annotations

import os
import plistlib
import re
import sys
from pathlib import Path
from typing import Any

# Top-level keys that carry look-and-feel or input. Everything else (window
# frames, Sparkle, NoSync*, AI, …) is dropped on export.
TOP_LEVEL_KEEP = frozenset(
    {
        "Default Bookmark Guid",
        "New Bookmarks",
        "PointerActions",
        "FocusFollowsMouse",
        "ApplePressAndHoldEnabled",
        "HapticFeedbackForEsc",
        "SoundForEsc",
        "VisualIndicatorForEsc",
    }
)

# Within each profile (bookmark), drop keys that only describe session geometry
# or launch command — not fonts/colors/keys/mouse.
PROFILE_DROP = frozenset(
    {
        "Rows",
        "Columns",
        "Command",
        "Custom Command",
        "Custom Directory",
        "Working Directory",
        "Shortcut",
        "Tags",
        "Bound Name",
        "Initial Text",
    }
)

DOMAIN = "com.googlecode.iterm2"
FONT_RE = re.compile(r"^(.+?)\s+(\d+(?:\.\d+)?)$")
VERSION_RE = re.compile(r"\d+")


def parse_version(text: str) -> tuple[int, ...]:
    parts = [int(x) for x in VERSION_RE.findall(text or "")]
    return tuple(parts[:4])


def version_cmp(a: str, b: str) -> int:
    """Return -1 if a<b, 0 if equal/unparseable pair, 1 if a>b."""
    ta, tb = parse_version(a), parse_version(b)
    if not ta or not tb:
        return 0
    # Pad to equal length.
    n = max(len(ta), len(tb))
    ta = ta + (0,) * (n - len(ta))
    tb = tb + (0,) * (n - len(tb))
    if ta < tb:
        return -1
    if ta > tb:
        return 1
    return 0


def curate(raw: dict[str, Any]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for key in TOP_LEVEL_KEEP:
        if key not in raw:
            continue
        value = raw[key]
        if key == "New Bookmarks" and isinstance(value, list):
            out[key] = [curate_profile(p) for p in value if isinstance(p, dict)]
        else:
            out[key] = value
    return out


def curate_profile(profile: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in profile.items() if k not in PROFILE_DROP}


def merge(existing: dict[str, Any], curated: dict[str, Any]) -> dict[str, Any]:
    merged = dict(existing)
    for key, value in curated.items():
        merged[key] = value
    return merged


def profile_fonts(curated: dict[str, Any]) -> list[str]:
    """All font specs mentioned in profiles (including unused non-ASCII)."""
    fonts: list[str] = []
    for _family, spec, _hint in iter_required_fonts(curated, include_unused_non_ascii=True):
        fonts.append(spec)
    return fonts


def _truthy(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "y", "on"}
    return False


def iter_required_fonts(
    curated: dict[str, Any],
    *,
    include_unused_non_ascii: bool = False,
) -> list[tuple[str, str, str]]:
    """Return (family, spec, hint_key) for fonts the profiles actually need."""
    out: list[tuple[str, str, str]] = []
    seen: set[str] = set()
    bookmarks = curated.get("New Bookmarks") or []
    if not isinstance(bookmarks, list):
        return out

    for profile in bookmarks:
        if not isinstance(profile, dict):
            continue
        specs: list[str] = []
        normal = profile.get("Normal Font")
        if isinstance(normal, str) and normal.strip():
            specs.append(normal.strip())
        if include_unused_non_ascii or _truthy(profile.get("Use Non-ASCII Font")):
            non_ascii = profile.get("Non Ascii Font")
            if isinstance(non_ascii, str) and non_ascii.strip():
                specs.append(non_ascii.strip())
        for spec in specs:
            family = font_family(spec)
            if family in seen:
                continue
            seen.add(family)
            out.append((family, spec, font_hint_key(family)))
    return out


def font_family(font_spec: str) -> str:
    match = FONT_RE.match(font_spec.strip())
    if match:
        return match.group(1)
    return font_spec.strip()


def font_hint_key(family: str) -> str:
    """Classify a PostScript/family name for install-hint selection."""
    compact = family.replace(" ", "").lower()
    if compact.startswith("meslo") and (
        "nf" in compact or "nerd" in compact or "nfm" in compact or "nfp" in compact
    ):
        return "meslo-nerd"
    if compact.startswith("meslo"):
        return "meslo"
    # Common Apple-provided monospace faces.
    if (
        compact in {"monaco", "menlo", "menlo-regular", "sfmono-regular", "sfmonoregular", "andalemono"}
        or compact.startswith("sfmono")
        or compact.startswith("menlo")
    ):
        return "system"
    return "unknown"


def _nerd_font_filename_stems(postscript_name: str) -> list[str]:
    """Map iTerm PostScript names like MesloLGSNFM-Regular to file stems."""
    name = postscript_name.replace(" ", "")
    stems = [name, postscript_name]
    # Longest NF* token only — replacing NF inside NFM yields a bogus stem
    # (MesloLGSNerdFontM-Regular) that never matches on-disk files.
    match = re.search(r"NF(?:M|P)?", name)
    if match:
        abbr = match.group(0)
        expanded = {"NFM": "NerdFontMono", "NFP": "NerdFontPropo", "NF": "NerdFont"}[abbr]
        stems.append(name[: match.start()] + expanded + name[match.end() :])
    return stems


def _homebrew_font_cask_dirs() -> list[Path]:
    """Meslo-related Homebrew Caskroom version dirs (Apple Silicon / Intel).

    Prefix order matches lib/host_paths init_files_homebrew_prefix probes
    (/opt/homebrew, /usr/local, ~/homebrew) — keep in sync.
    """
    out: list[Path] = []
    cask_names = ("font-meslo-lg-nerd-font", "font-meslo-lg")
    for prefix in (Path("/opt/homebrew"), Path("/usr/local"), Path.home() / "homebrew"):
        for cask_name in cask_names:
            cask_dir = prefix / "Caskroom" / cask_name
            if not cask_dir.is_dir():
                continue
            for child in cask_dir.iterdir():
                if child.is_dir() and child.name != ".metadata":
                    out.append(child)
    return out


def font_is_installed(postscript_name: str) -> bool:
    """Return True if postscript_name appears installed (files or system_profiler)."""
    if not postscript_name:
        return False

    home = Path.home()
    dirs = [
        home / "Library" / "Fonts",
        Path("/Library/Fonts"),
        Path("/System/Library/Fonts"),
        Path("/System/Library/Fonts/Supplemental"),
        *_homebrew_font_cask_dirs(),
    ]
    stems = {s.lower() for s in _nerd_font_filename_stems(postscript_name)}
    needle = postscript_name.replace(" ", "").lower()
    for directory in dirs:
        if not directory.is_dir():
            continue
        try:
            entries = list(directory.iterdir())
        except OSError:
            continue
        for path in entries:
            # Skip dirs and unreadable files (e.g. Caskroom symlinks into
            # another account's ~/Library/Fonts).
            try:
                if not path.is_file() or not os.access(path, os.R_OK):
                    continue
            except OSError:
                continue
            stem = path.stem.replace(" ", "").lower()
            if stem in stems or needle == stem or needle in stem:
                return True

    # Slower fallback: match PostScript name from system_profiler XML.
    try:
        import plistlib
        import subprocess

        raw = subprocess.check_output(
            ["system_profiler", "SPFontsDataType", "-xml"],
            stderr=subprocess.DEVNULL,
        )
        data = plistlib.loads(raw)
    except (OSError, subprocess.CalledProcessError, plistlib.InvalidFileException):
        return False

    target = postscript_name.lower()

    def walk(node: Any) -> bool:
        if isinstance(node, dict):
            for key, value in node.items():
                if isinstance(key, str) and key.lower() == target:
                    return True
                if walk(value):
                    return True
        elif isinstance(node, list):
            for item in node:
                if walk(item):
                    return True
        return False

    return walk(data)


def load_plist(path: Path) -> dict[str, Any]:
    with path.open("rb") as fh:
        data = plistlib.load(fh)
    if not isinstance(data, dict):
        raise SystemExit(f"expected dict plist at {path}")
    return data


def write_xml_plist(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as fh:
        plistlib.dump(data, fh, fmt=plistlib.FMT_XML, sort_keys=True)


def write_meta(path: Path, data: dict[str, Any]) -> None:
    import json

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, sort_keys=True)
        fh.write("\n")


def load_meta(path: Path) -> dict[str, Any]:
    import json

    if not path.is_file():
        return {}
    with path.open(encoding="utf-8") as fh:
        data = json.load(fh)
    return data if isinstance(data, dict) else {}


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(
            f"usage: {argv[0]} curate|merge|fonts|check-fonts|equal|write-meta|version-note ...",
            file=sys.stderr,
        )
        return 2
    cmd = argv[1]
    if cmd == "curate":
        if len(argv) != 4:
            print(f"usage: {argv[0]} curate IN.plist OUT.plist", file=sys.stderr)
            return 2
        curated = curate(load_plist(Path(argv[2])))
        write_xml_plist(Path(argv[3]), curated)
        return 0
    if cmd == "merge":
        if len(argv) != 5:
            print(
                f"usage: {argv[0]} merge EXISTING.plist CURATED.plist OUT.plist",
                file=sys.stderr,
            )
            return 2
        existing_path = Path(argv[2])
        existing = load_plist(existing_path) if existing_path.is_file() else {}
        curated = load_plist(Path(argv[3]))
        write_xml_plist(Path(argv[4]), merge(existing, curated))
        return 0
    if cmd == "fonts":
        if len(argv) != 3:
            print(f"usage: {argv[0]} fonts CURATED.plist", file=sys.stderr)
            return 2
        for family, spec, hint_key in iter_required_fonts(load_plist(Path(argv[2]))):
            print(f"{family}\t{spec}\t{hint_key}")
        return 0
    if cmd == "check-fonts":
        if len(argv) != 3:
            print(f"usage: {argv[0]} check-fonts CURATED.plist", file=sys.stderr)
            return 2
        missing = 0
        for family, spec, hint_key in iter_required_fonts(load_plist(Path(argv[2]))):
            if font_is_installed(family):
                print(f"ok\t{family}\t{spec}\t{hint_key}")
            else:
                print(f"missing\t{family}\t{spec}\t{hint_key}")
                missing = 1
        return missing
    if cmd == "equal":
        if len(argv) != 4:
            print(f"usage: {argv[0]} equal A.plist B.plist", file=sys.stderr)
            return 2
        a = load_plist(Path(argv[2]))
        b = load_plist(Path(argv[3]))
        return 0 if a == b else 1
    if cmd == "write-meta":
        # write-meta OUT.json iterm_version [host]
        if len(argv) not in (4, 5):
            print(
                f"usage: {argv[0]} write-meta OUT.json ITERM_VERSION [HOST]",
                file=sys.stderr,
            )
            return 2
        import time

        payload = {
            "iterm_version": argv[3],
            "exported_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        if len(argv) == 5 and argv[4]:
            payload["host"] = argv[4]
        write_meta(Path(argv[2]), payload)
        return 0
    if cmd == "version-note":
        # version-note META.json LOCAL_VERSION
        # prints soft note lines; exit 0 always (soft). exit 3 if meta missing.
        if len(argv) != 4:
            print(
                f"usage: {argv[0]} version-note META.json LOCAL_VERSION",
                file=sys.stderr,
            )
            return 2
        meta = load_meta(Path(argv[2]))
        exported = str(meta.get("iterm_version") or "").strip()
        local = str(argv[3] or "").strip()
        if not exported:
            return 3
        host = str(meta.get("host") or "").strip()
        if not local:
            print(f"exported_from\t{exported}\tlocal\tunknown\trelation\tunknown")
            if host:
                print(f"export_host\t{host}")
            return 0
        rel = version_cmp(local, exported)
        if rel == 0 and local == exported:
            relation = "equal"
        elif rel == 0:
            relation = "equal"
        elif rel < 0:
            relation = "older"
        else:
            relation = "newer"
        print(f"exported_from\t{exported}\tlocal\t{local}\trelation\t{relation}")
        if host:
            print(f"export_host\t{host}")
        return 0
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
