#!/usr/bin/env python3
"""Pin iTerm2 badge geometry to a small, near-center label.

iTerm badges are always anchored top-right. Size is controlled by *global*
advanced prefs (defaults: width 0.5, height 0.2 of the session — huge).
Profile "Badge Max Width" alone does not override that for many builds.

Also writes matching profile keys for the Edit-badge UI.
"""
from __future__ import annotations

import plistlib
import subprocess
import sys
from pathlib import Path

DOMAIN = "com.googlecode.iterm2"

# Fractions of session size (advanced prefs). Keep tiny — glyphs *fill* the box.
# Margins are POINTS from the top-right anchor (not fractions). Large values
# (e.g. 400) push the badge off-screen — keep modest.
ADV = {
    "badgeMaxWidthFraction": 0.05,
    "badgeMaxHeightFraction": 0.03,
    "badgeRightMargin": 16,
    "badgeTopMargin": 6,
    "badgeFont": "Menlo",
    "badgeFontIsBold": False,
}

# Profile keys (Prefs → Profiles → General → Badge → Edit…)
# These margins are fractions of the session (0–1), unlike advanced prefs.
PROFILE = {
    "Badge Text": "",  # dynamic via OSC while agent runs only
    "Badge Max Width": 0.05,
    "Badge Max Height": 0.03,
    "Badge Right Margin": 0.02,
    "Badge Top Margin": 0.02,
}


def advanced_ok() -> bool:
    for key, value in ADV.items():
        try:
            out = subprocess.check_output(
                ["defaults", "read", DOMAIN, key], text=True
            ).strip()
        except Exception:
            return False
        if isinstance(value, bool):
            if out.lower() not in (("1", "true", "yes") if value else ("0", "false", "no")):
                return False
        elif isinstance(value, float):
            try:
                if abs(float(out) - value) > 1e-6:
                    return False
            except ValueError:
                return False
        else:
            if out != str(value):
                return False
    return True


def defaults_write() -> None:
    for key, value in ADV.items():
        if isinstance(value, bool):
            subprocess.run(
                ["defaults", "write", DOMAIN, key, "-bool", "YES" if value else "NO"],
                check=False,
            )
        elif isinstance(value, int):
            subprocess.run(
                ["defaults", "write", DOMAIN, key, "-int", str(value)],
                check=False,
            )
        elif isinstance(value, float):
            subprocess.run(
                ["defaults", "write", DOMAIN, key, "-float", str(value)],
                check=False,
            )
        else:
            subprocess.run(
                ["defaults", "write", DOMAIN, key, "-string", str(value)],
                check=False,
            )


def patch_profile_plist(path: Path) -> int:
    if not path.is_file():
        return 0
    data = plistlib.loads(path.read_bytes())
    n = 0
    for bookmark in data.get("New Bookmarks") or []:
        if isinstance(bookmark, dict):
            bookmark.update(PROFILE)
            n += 1
    path.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_XML))
    return n


def patch_live_bookmarks() -> int:
    tmp = Path("/tmp/iterm2-badge-geom.plist")
    rc = subprocess.run(
        ["defaults", "export", DOMAIN, str(tmp)],
        check=False,
        capture_output=True,
    )
    if rc.returncode != 0 or not tmp.is_file():
        return 0
    n = patch_profile_plist(tmp)
    subprocess.run(["defaults", "import", DOMAIN, str(tmp)], check=False)
    return n


def main(argv: list[str]) -> int:
    if "-h" in argv or "--help" in argv:
        print(
            "usage: ensure_iterm_badge.py [--curated PATH] [-q|--quiet]\n"
            "  Writes small/centered-ish iTerm badge advanced prefs + profile keys.",
            file=sys.stderr,
        )
        return 0
    quiet = "--quiet" in argv or "-q" in argv
    curated = None
    if "--curated" in argv:
        i = argv.index("--curated")
        if i + 1 >= len(argv):
            print("ensure_iterm_badge: --curated requires a path", file=sys.stderr)
            return 2
        curated = Path(argv[i + 1])
    if advanced_ok() and curated is None:
        if not quiet:
            print("ensure_iterm_badge: already set", file=sys.stderr)
        return 0
    defaults_write()
    n_live = patch_live_bookmarks()
    n_cur = patch_profile_plist(curated) if curated else 0
    if not quiet:
        print(
            f"ensure_iterm_badge: advanced prefs set; "
            f"profiles updated live={n_live} curated={n_cur}",
            file=sys.stderr,
        )
        print(
            "ensure_iterm_badge: fully quit iTerm (Cmd-Q) and reopen for geometry to apply",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
