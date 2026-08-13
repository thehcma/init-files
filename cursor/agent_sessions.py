#!/usr/bin/env python3
"""List / name / resolve Cursor Agent CLI sessions for resume after a dead terminal.

Chats live under ~/.cursor/chats/<project>/<session_id>/. Multiple concurrent
sessions on one host are disambiguated by cwd, optional user name, and the
latest prompt text — not by \"most recent\" alone.
"""
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path


def state_dir() -> Path:
    xdg = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    return Path(xdg) / "init-files"


def chats_root() -> Path:
    return Path.home() / ".cursor" / "chats"


def names_path() -> Path:
    return state_dir() / "agent-session-names.json"


def load_names() -> dict[str, dict]:
    path = names_path()
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text())
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def save_names(data: dict[str, dict]) -> None:
    path = names_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


def clip(text: str, n: int = 72) -> str:
    text = " ".join((text or "").split())
    if len(text) <= n:
        return text
    return text[: n - 1] + "…"


def fit(text: str, width: int) -> str:
    """Clip to width and left-pad so fzf columns align in a monospace font."""
    text = " ".join((text or "").split())
    if width <= 0:
        return ""
    if len(text) > width:
        if width == 1:
            return text[:1]
        return text[: width - 1] + "…"
    return text.ljust(width)


# Fixed fzf column widths (pane label · time · cwd · last prompt).
FZF_LABEL_W = 36
FZF_TIME_W = 16
FZF_CWD_W = 32
FZF_PROMPT_W = 44


def session_label(row: dict) -> str:
    """Friendly name: user label, else Cursor auto title (pane / statusline)."""
    user = (row.get("name") or "").strip()
    if user:
        return user
    title = (row.get("title") or "").strip()
    if title:
        return title
    return ""


def pane_style_label(row: dict) -> str:
    """Match iTerm agentsession / tab chrome: short id, or short:name."""
    sid = row.get("id") or ""
    short = sid[:8] if sid else "?"
    label = session_label(row)
    if label:
        return f"{short}:{label}"
    return short


def load_prompts(session_dir: Path) -> list[str]:
    hist = session_dir / "prompt_history.json"
    if not hist.is_file():
        return []
    try:
        data = json.loads(hist.read_text())
    except Exception:
        return []
    if not isinstance(data, list):
        return []
    return [str(x) for x in data if isinstance(x, str) and x.strip()]


def iter_sessions() -> list[dict]:
    root = chats_root()
    if not root.is_dir():
        return []
    names = load_names()
    rows: list[dict] = []
    for meta in root.glob("*/*/meta.json"):
        try:
            d = json.loads(meta.read_text())
        except Exception:
            continue
        sid = meta.parent.name
        prompts = load_prompts(meta.parent)
        # prompt_history is newest-first in practice.
        latest = prompts[0] if prompts else ""
        first = prompts[-1] if prompts else ""
        name_meta = names.get(sid) or {}
        rows.append(
            {
                "id": sid,
                "updated_ms": int(d.get("updatedAtMs") or 0),
                "created_ms": int(d.get("createdAtMs") or 0),
                "title": d.get("title") or "",
                "cwd": d.get("cwd") or "",
                "name": name_meta.get("name") or d.get("session_name") or "",
                "latest": latest,
                "first": first,
                "tty": name_meta.get("tty") or "",
                "iterm": name_meta.get("iterm") or "",
                "host": name_meta.get("host") or "",
            }
        )
    # Same chat UUID can appear under multiple project hashes; keep newest.
    by_id: dict[str, dict] = {}
    for row in rows:
        prev = by_id.get(row["id"])
        if prev is None or int(row["updated_ms"]) >= int(prev["updated_ms"]):
            by_id[row["id"]] = row
    rows = list(by_id.values())
    rows.sort(key=lambda r: r["updated_ms"], reverse=True)
    return rows


def fmt_time(ms: int) -> str:
    if not ms:
        return "?"
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(ms / 1000.0))


def cmd_list(argv: list[str]) -> int:
    limit = 20
    query = ""
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("-n", "--limit") and i + 1 < len(argv):
            limit = int(argv[i + 1])
            i += 2
            continue
        if a in ("-q", "--query") and i + 1 < len(argv):
            query = argv[i + 1].lower()
            i += 2
            continue
        if a.isdigit() and query == "" and limit == 20:
            limit = int(a)
            i += 1
            continue
        if not a.startswith("-") and not query:
            query = a.lower()
            i += 1
            continue
        print(f"usage: agent_sessions.py list [--limit N] [--query TEXT]", file=sys.stderr)
        return 2
    rows = iter_sessions()
    if query:
        rows = [
            r
            for r in rows
            if query in (r["id"] or "").lower()
            or query in (r["name"] or "").lower()
            or query in (r["title"] or "").lower()
            or query in (r["cwd"] or "").lower()
            or query in (r["latest"] or "").lower()
            or query in (r["first"] or "").lower()
        ]
    rows = rows[:limit]
    if not rows:
        print("(no sessions found)")
        return 0
    print(
        "Pick by #, full id, or name. Do not rely on \"most recent\" when several "
        "sessions share a host/cwd."
    )
    print()
    for idx, r in enumerate(rows, 1):
        label = session_label(r) or "-"
        print(
            f"{idx:3d}  {fmt_time(r['updated_ms'])}  {pane_style_label(r)}\n"
            f"     id:   {r['id']}\n"
            f"     name: {label}\n"
            f"     cwd:  {r['cwd'] or '-'}\n"
            f"     last: {clip(r['latest'], 88) or '-'}"
        )
        extra = []
        if r.get("host"):
            extra.append(f"host={r['host']}")
        if r.get("tty"):
            extra.append(f"tty={r['tty']}")
        if r.get("iterm"):
            extra.append(f"iterm={clip(r['iterm'], 24)}")
        if extra:
            print(f"     meta: {', '.join(extra)}")
        print()
    return 0


def fzf_display(row: dict) -> str:
    """Fixed-width columns matching the resume_agent_session fzf header."""
    parts = [
        fit(pane_style_label(row), FZF_LABEL_W),
        fit(fmt_time(int(row.get("updated_ms") or 0)), FZF_TIME_W),
        fit(row.get("cwd") or "-", FZF_CWD_W),
        fit(row.get("latest") or "-", FZF_PROMPT_W),
    ]
    return "  ".join(parts).replace("\t", " ")


def fzf_header() -> str:
    """Same fixed widths as fzf_display so the fzf --header lines up."""
    return "  ".join(
        [
            fit("label", FZF_LABEL_W),
            fit("updated", FZF_TIME_W),
            fit("cwd", FZF_CWD_W),
            fit("last prompt", FZF_PROMPT_W),
        ]
    )


def cmd_fzf(argv: list[str]) -> int:
    """Emit TSV lines for fzf: id<TAB>display (pane-style label first)."""
    named_only = "--named" in argv
    rows = iter_sessions()
    if named_only:
        # User-assigned names only (--name / name_agent_session), not auto titles.
        rows = [r for r in rows if (r.get("name") or "").strip()]
    # Named sessions first, then by recency (already sorted by updated).
    rows.sort(
        key=lambda r: (0 if (r.get("name") or "").strip() else 1, -int(r.get("updated_ms") or 0))
    )
    for r in rows:
        print(f"{r['id']}\t{fzf_display(r)}")
    return 0


def cmd_fzf_header(_argv: list[str]) -> int:
    print(fzf_header())
    return 0


def resolve(target: str) -> str | None:
    rows = iter_sessions()
    if not target:
        return None
    if target.isdigit():
        idx = int(target)
        if 1 <= idx <= len(rows):
            return rows[idx - 1]["id"]
        return None
    # Exact id
    for r in rows:
        if r["id"] == target:
            return r["id"]
    # Unique prefix
    pref = [r for r in rows if r["id"].startswith(target)]
    if len(pref) == 1:
        return pref[0]["id"]
    # Unique name (case-insensitive)
    named = [r for r in rows if (r["name"] or "").lower() == target.lower()]
    if len(named) == 1:
        return named[0]["id"]
    # Unique Cursor title (pane label without user --name)
    titled = [r for r in rows if (r.get("title") or "").lower() == target.lower()]
    if len(titled) == 1:
        return titled[0]["id"]
    # Unique name substring
    named = [r for r in rows if target.lower() in (r["name"] or "").lower()]
    if len(named) == 1:
        return named[0]["id"]
    # Unique title substring
    titled = [r for r in rows if target.lower() in (r.get("title") or "").lower()]
    if len(titled) == 1:
        return titled[0]["id"]
    return None


def cmd_resolve(argv: list[str]) -> int:
    if not argv:
        print("usage: agent_sessions.py resolve <index|id|name>", file=sys.stderr)
        return 2
    sid = resolve(argv[0])
    if not sid:
        print(f"agent_sessions: could not uniquely resolve {argv[0]!r}", file=sys.stderr)
        return 1
    print(sid)
    return 0


def cmd_name(argv: list[str]) -> int:
    if not argv:
        print(
            "usage: agent_sessions.py name <label> [session_id]\n"
            "  session_id defaults to CURSOR_CONVERSATION_ID or agent-session.current",
            file=sys.stderr,
        )
        return 2
    label = argv[0]
    sid = argv[1] if len(argv) > 1 else (
        os.environ.get("CURSOR_CONVERSATION_ID")
        or ""
    ).strip()
    if not sid:
        cur = state_dir() / "agent-session.current"
        if cur.is_file():
            sid = cur.read_text().strip()
    if not sid:
        print("agent_sessions: no session_id (pass one or run inside an agent shell)", file=sys.stderr)
        return 1
    data = load_names()
    entry = dict(data.get(sid) or {})
    entry["name"] = label
    entry["named_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    data[sid] = entry
    save_names(data)
    print(f"named {sid} -> {label!r}")
    return 0


def cmd_record(argv: list[str]) -> int:
    """Upsert sidecar metadata for a live session (tty/iterm/host/cwd)."""
    sid = (argv[0] if argv else os.environ.get("CURSOR_CONVERSATION_ID") or "").strip()
    if not sid:
        return 0
    cwd = argv[1] if len(argv) > 1 else os.environ.get("PWD") or ""
    data = load_names()
    entry = dict(data.get(sid) or {})
    entry["host"] = os.environ.get("INIT_FILES_RECORD_HOST") or (
        os.uname().nodename.split(".")[0] if hasattr(os, "uname") else ""
    )
    entry["cwd"] = cwd or entry.get("cwd") or ""
    entry["tty"] = os.environ.get("SSH_TTY") or ""
    try:
        import subprocess

        tty = subprocess.check_output(["tty"], text=True, stderr=subprocess.DEVNULL).strip()
        if tty:
            entry["tty"] = tty
    except Exception:
        pass
    entry["iterm"] = os.environ.get("ITERM_SESSION_ID") or os.environ.get("TERM_SESSION_ID") or entry.get("iterm") or ""
    entry["seen_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    data[sid] = entry
    save_names(data)
    state_dir().mkdir(parents=True, exist_ok=True)
    (state_dir() / "agent-session.current").write_text(sid + "\n")
    # Per-tty pointer (useful only while the original pts still exists).
    tty = entry.get("tty") or ""
    if tty:
        safe = tty.replace("/", "_")
        (state_dir() / f"agent-session.tty{safe}").write_text(sid + "\n")
    return 0


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(
            "usage: agent_sessions.py list|fzf|fzf-header|resolve|name|record ...",
            file=sys.stderr,
        )
        return 2
    cmd = sys.argv[1]
    argv = sys.argv[2:]
    if cmd == "list":
        return cmd_list(argv)
    if cmd == "fzf":
        return cmd_fzf(argv)
    if cmd == "fzf-header":
        return cmd_fzf_header(argv)
    if cmd == "resolve":
        return cmd_resolve(argv)
    if cmd == "name":
        return cmd_name(argv)
    if cmd == "record":
        return cmd_record(argv)
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
