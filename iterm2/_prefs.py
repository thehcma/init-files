#!/usr/bin/env python3
"""Curate and merge iTerm2 prefs (font/colors/keyboard/mouse only)."""

from __future__ import annotations

import copy
import math
import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

# Preferred new-window grid when the main display is at least as large as the
# authoring monitor (visibleFrame points). Smaller displays get ~1/4 usable area.
PREFERRED_COLUMNS = 300
PREFERRED_ROWS = 80
# Authoring Mac visibleFrame (points), from NSScreen.mainScreen.visibleFrame.
MIN_PREFERRED_VISIBLE = (3008.0, 1662.0)
# Window chrome outside the character grid (title / tabs / pane status / scroll).
GEOMETRY_CHROME_WIDTH = 24.0
GEOMETRY_CHROME_HEIGHT = 88.0
GEOMETRY_MIN_COLUMNS = 60
GEOMETRY_MIN_ROWS = 20
# Override probe for tests: INIT_FILES_ITERM_VISIBLE_FRAME=WxH (points).

# Top-level keys that carry look-and-feel or input. Everything else (window
# frames, Sparkle, NoSync*, AI, …) is dropped on export.
TOP_LEVEL_KEEP = frozenset(
    {
        "AllowClipboardAccess",
        "Default Bookmark Guid",
        "New Bookmarks",
        "PointerActions",
        "FocusFollowsMouse",
        "ApplePressAndHoldEnabled",
        "HapticFeedbackForEsc",
        "SoundForEsc",
        "VisualIndicatorForEsc",
        "SeparateStatusBarsPerPane",
        "ShowPaneTitles",
        "ShowPaneTitlesEvenIfOnlyOnePane",
        "StatusBarPosition",
        # When true (iTerm default), Cmd-N reuses last-closed window size and
        # ignores profile Columns/Rows — keep false so adaptive grid applies.
        "RememberWindowPositions",
    }
)

# Within each profile (bookmark), drop keys that only describe session geometry
# or launch command — not fonts/colors/keys/mouse.
PROFILE_DROP = frozenset(
    {
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
    out = {k: v for k, v in profile.items() if k not in PROFILE_DROP}
    # Host-adaptive Columns/Rows are applied only at merge time. Export always
    # stores the preferred max so small-display installs do not poison the repo.
    if "Columns" in out or "Rows" in out:
        out["Columns"] = PREFERRED_COLUMNS
        out["Rows"] = PREFERRED_ROWS
    return out


def merge(existing: dict[str, Any], curated: dict[str, Any]) -> dict[str, Any]:
    merged = dict(existing)
    for key, value in curated.items():
        if key == "New Bookmarks" and isinstance(value, list):
            merged[key] = [
                copy.deepcopy(p) if isinstance(p, dict) else p for p in value
            ]
        else:
            merged[key] = value
    apply_adaptive_geometry(merged)
    # Drop remembered frames so a full quit does not resurrect old pixel sizes
    # ahead of profile Columns/Rows (see RememberWindowPositions).
    for key in list(merged):
        if str(key).startswith("NSWindow Frame iTerm Window"):
            del merged[key]
    merged.pop("NoSyncSavedWindowPositions", None)
    return merged


def font_point_size(font_spec: str) -> float:
    match = FONT_RE.match((font_spec or "").strip())
    if match:
        try:
            return float(match.group(2))
        except ValueError:
            return 12.0
    return 12.0


def visible_frame_points() -> tuple[float, float] | None:
    """Main-screen usable size in points (excludes menu bar / Dock)."""
    override = (os.environ.get("INIT_FILES_ITERM_VISIBLE_FRAME") or "").strip()
    if override:
        try:
            width_s, height_s = override.lower().split("x", 1)
            width, height = float(width_s), float(height_s)
            if width > 0 and height > 0:
                return width, height
        except ValueError:
            pass
        return None
    if sys.platform != "darwin":
        return None
    script = (
        'ObjC.import("AppKit");'
        "var f=$.NSScreen.mainScreen.visibleFrame;"
        'f.size.width+" "+f.size.height;'
    )
    try:
        out = subprocess.check_output(
            ["osascript", "-l", "JavaScript", "-e", script],
            text=True,
            timeout=5,
            stderr=subprocess.DEVNULL,
        ).strip()
        width_s, height_s = out.split()
        width, height = float(width_s), float(height_s)
        if width > 0 and height > 0:
            return width, height
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    return None


def _jxa_cell_metrics(postscript_name: str, point_size: float) -> tuple[float, float] | None:
    """Return (advance_width, line_height) in points via AppKit, or None."""
    if sys.platform != "darwin" or point_size <= 0:
        return None
    # Escape for JXA single-quoted string.
    safe = postscript_name.replace("\\", "\\\\").replace("'", "\\'")
    script = (
        "ObjC.import('AppKit');"
        f"var font=$.NSFont['fontWithName:size:']('{safe}', {point_size});"
        "if(!font){'';}else{"
        "var adv=font.maximumAdvancement;"
        "var h=font.ascender-font.descender+font.leading;"
        "adv.width+' '+h;"
        "}"
    )
    try:
        out = subprocess.check_output(
            ["osascript", "-l", "JavaScript", "-e", script],
            text=True,
            timeout=5,
            stderr=subprocess.DEVNULL,
        ).strip()
        if not out:
            return None
        width_s, height_s = out.split()
        width, height = float(width_s), float(height_s)
        if width > 0 and height > 0:
            return width, height
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    return None


def cell_size_points(
    font_spec: str,
    *,
    horizontal_spacing: float = 1.0,
    vertical_spacing: float = 1.0,
) -> tuple[float, float]:
    """Estimate one character cell in points (width, height)."""
    point_size = font_point_size(font_spec)
    family = font_family(font_spec)
    measured = _jxa_cell_metrics(family, point_size)
    if measured is not None:
        cell_w, cell_h = measured
    else:
        # Menlo / Meslo-ish monospace fallbacks (calibrated on Meslo 15).
        cell_w = point_size * 0.602
        cell_h = point_size * 1.262
    h_space = horizontal_spacing if horizontal_spacing > 0 else 1.0
    v_space = vertical_spacing if vertical_spacing > 0 else 1.0
    return cell_w * h_space, cell_h * v_space


def _profile_spacing(profile: dict[str, Any], key: str) -> float:
    raw = profile.get(key, 1.0)
    try:
        value = float(raw)
    except (TypeError, ValueError):
        return 1.0
    return value if value > 0 else 1.0


def compute_adaptive_grid(
    preferred_cols: int,
    preferred_rows: int,
    font_spec: str,
    *,
    horizontal_spacing: float = 1.0,
    vertical_spacing: float = 1.0,
    visible: tuple[float, float] | None = None,
) -> tuple[int, int, str]:
    """Return (columns, rows, mode) for a new iTerm window on this display.

    mode is ``preferred`` when the main screen is at least MIN_PREFERRED_VISIBLE,
    ``quarter`` when sized to ~1/4 usable area, or ``preferred-fallback`` when
    the screen size cannot be probed.
    """
    pref_c = max(1, int(preferred_cols))
    pref_r = max(1, int(preferred_rows))
    if visible is None:
        visible = visible_frame_points()
    if visible is None:
        return pref_c, pref_r, "preferred-fallback"

    usable_w, usable_h = visible
    min_w, min_h = MIN_PREFERRED_VISIBLE
    if usable_w + 0.5 >= min_w and usable_h + 0.5 >= min_h:
        return pref_c, pref_r, "preferred"

    cell_w, cell_h = cell_size_points(
        font_spec,
        horizontal_spacing=horizontal_spacing,
        vertical_spacing=vertical_spacing,
    )
    if cell_w <= 0 or cell_h <= 0:
        return pref_c, pref_r, "preferred-fallback"

    # Half width × half height ≈ one quarter of usable area.
    target_w = usable_w * 0.5
    target_h = usable_h * 0.5
    cols = int(math.floor((target_w - GEOMETRY_CHROME_WIDTH) / cell_w))
    rows = int(math.floor((target_h - GEOMETRY_CHROME_HEIGHT) / cell_h))
    max_cols = int(math.floor((usable_w - GEOMETRY_CHROME_WIDTH) / cell_w))
    max_rows = int(math.floor((usable_h - GEOMETRY_CHROME_HEIGHT) / cell_h))
    cols = max(GEOMETRY_MIN_COLUMNS, min(pref_c, cols, max_cols))
    rows = max(GEOMETRY_MIN_ROWS, min(pref_r, rows, max_rows))
    return cols, rows, "quarter"


def apply_adaptive_geometry(prefs: dict[str, Any]) -> None:
    """Rewrite Columns/Rows on bookmarks that declare a grid."""
    bookmarks = prefs.get("New Bookmarks")
    if not isinstance(bookmarks, list):
        return
    for profile in bookmarks:
        if not isinstance(profile, dict):
            continue
        if "Columns" not in profile and "Rows" not in profile:
            continue
        try:
            pref_c = int(profile.get("Columns", PREFERRED_COLUMNS))
        except (TypeError, ValueError):
            pref_c = PREFERRED_COLUMNS
        try:
            pref_r = int(profile.get("Rows", PREFERRED_ROWS))
        except (TypeError, ValueError):
            pref_r = PREFERRED_ROWS
        font_spec = profile.get("Normal Font")
        if not isinstance(font_spec, str) or not font_spec.strip():
            font_spec = "MesloLGSNFM-Regular 15"
        cols, rows, _mode = compute_adaptive_grid(
            pref_c,
            pref_r,
            font_spec.strip(),
            horizontal_spacing=_profile_spacing(profile, "Horizontal Spacing"),
            vertical_spacing=_profile_spacing(profile, "Vertical Spacing"),
        )
        profile["Columns"] = cols
        profile["Rows"] = rows


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
            f"usage: {argv[0]} curate|merge|fonts|check-fonts|equal|geometry|"
            "write-meta|version-note ...",
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
    if cmd == "geometry":
        # geometry [CURATED.plist] — print cols rows mode usableWxH font
        if len(argv) not in (2, 3):
            print(f"usage: {argv[0]} geometry [CURATED.plist]", file=sys.stderr)
            return 2
        font_spec = "MesloLGSNFM-Regular 15"
        pref_c, pref_r = PREFERRED_COLUMNS, PREFERRED_ROWS
        h_space, v_space = 1.0, 1.0
        if len(argv) == 3:
            curated = load_plist(Path(argv[2]))
            bookmarks = curated.get("New Bookmarks") or []
            if isinstance(bookmarks, list):
                for profile in bookmarks:
                    if not isinstance(profile, dict):
                        continue
                    if "Columns" not in profile and "Rows" not in profile:
                        continue
                    try:
                        pref_c = int(profile.get("Columns", pref_c))
                    except (TypeError, ValueError):
                        pass
                    try:
                        pref_r = int(profile.get("Rows", pref_r))
                    except (TypeError, ValueError):
                        pass
                    normal = profile.get("Normal Font")
                    if isinstance(normal, str) and normal.strip():
                        font_spec = normal.strip()
                    h_space = _profile_spacing(profile, "Horizontal Spacing")
                    v_space = _profile_spacing(profile, "Vertical Spacing")
                    break
        visible = visible_frame_points()
        cols, rows, mode = compute_adaptive_grid(
            pref_c,
            pref_r,
            font_spec,
            horizontal_spacing=h_space,
            vertical_spacing=v_space,
            visible=visible,
        )
        if visible is None:
            usable = "unknown"
        else:
            usable = f"{visible[0]:.0f}x{visible[1]:.0f}"
        print(f"{cols}x{rows}\t{mode}\tusable={usable}\tfont={font_spec}")
        return 0
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
