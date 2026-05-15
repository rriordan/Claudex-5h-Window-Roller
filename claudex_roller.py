"""Claudex-5h-Window-Roller: keep Claude Code and Codex CLI 5h windows rolling.

Background service. Once a minute it looks at each CLI's local session log,
figures out when the current 5h window opened, and ~90s before it would close
fires a tiny `ping` so the next 5h window opens seamlessly. Pops a Windows
toast if a ping fails (rate-limited, auth expired, etc.).

Usage:
    pythonw claudex_roller.py          # background service (Task Scheduler)
    python  claudex_roller.py --once   # one cycle, then exit
    python  claudex_roller.py --status # print current window state, then exit
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

WINDOW = timedelta(hours=5)
PING_LEAD = timedelta(seconds=90)
POLL_SECONDS = 60
PING_TIMEOUT_SECONDS = 30
PAUSE_PHRASES = ("rate limit", "usage limit", "unauthorized", "quota exceeded", "exceeded your")

_SUBPROCESS_FLAGS = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0

_HOME = Path(os.environ.get("USERPROFILE") or os.environ.get("HOME") or ".")
STATE_DIR = _HOME / ".claudex-5h-window-roller"
LOG_FILE = STATE_DIR / "service.log"

CLAUDE_PROJECTS = _HOME / ".claude" / "projects"
CODEX_HISTORY = _HOME / ".codex" / "history.jsonl"


@dataclass
class Cli:
    name: str
    ping_command: list[str]
    log_source: str  # "claude" | "codex"


CLIS = [
    Cli("claude", ["claude", "-p", "ping"], "claude"),
    Cli("codex", ["codex", "exec", "--skip-git-repo-check", "ping"], "codex"),
]


def _resolve_executable(name: str) -> str | None:
    """Find an executable on PATH, with fallback to known per-user install dirs."""
    found = shutil.which(name)
    if found:
        return found
    if sys.platform != "win32":
        return None
    # Claude Code desktop installs to %APPDATA%\Claude\claude-code\<version>\claude.exe
    # and doesn't add itself to PATH. Pick the highest-numbered version dir.
    if name == "claude":
        base = Path(os.environ.get("APPDATA", "")) / "Claude" / "claude-code"
        if base.exists():
            versions = sorted(base.iterdir(), key=lambda p: p.name, reverse=True)
            for v in versions:
                exe = v / "claude.exe"
                if exe.exists():
                    return str(exe)
    return None


def _resolve_clis() -> list[Cli]:
    """Return CLIS with ping_command[0] replaced by an absolute path when needed."""
    resolved = []
    for cli in CLIS:
        path = _resolve_executable(cli.ping_command[0])
        if path:
            resolved.append(Cli(cli.name, [path, *cli.ping_command[1:]], cli.log_source))
        else:
            resolved.append(cli)  # keep original; will fail with "command not found" at ping time
    return resolved


# ---------- log readers ----------

def _tail_lines(path: Path, n: int = 200) -> list[str]:
    try:
        size = path.stat().st_size
    except OSError:
        return []
    chunk = min(size, max(n * 400, 8192))
    with open(path, "rb") as f:
        f.seek(size - chunk)
        data = f.read()
    return data.decode("utf-8", errors="replace").splitlines()[-n:]


def recent_claude_user_timestamps() -> list[datetime]:
    if not CLAUDE_PROJECTS.exists():
        return []
    cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
    out: list[datetime] = []
    for jsonl in CLAUDE_PROJECTS.rglob("*.jsonl"):
        try:
            mtime = datetime.fromtimestamp(jsonl.stat().st_mtime, tz=timezone.utc)
        except OSError:
            continue
        if mtime < cutoff:
            continue
        for line in _tail_lines(jsonl, 500):
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if row.get("type") != "user":
                continue
            ts = row.get("timestamp")
            if not ts:
                continue
            try:
                dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
            except ValueError:
                continue
            if dt >= cutoff:
                out.append(dt)
    out.sort()
    return out


def recent_codex_timestamps() -> list[datetime]:
    if not CODEX_HISTORY.exists():
        return []
    cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
    out: list[datetime] = []
    for line in _tail_lines(CODEX_HISTORY, 1000):
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        ts = row.get("ts")
        if ts is None:
            continue
        try:
            dt = datetime.fromtimestamp(int(ts), tz=timezone.utc)
        except (TypeError, ValueError, OSError):
            continue
        if dt >= cutoff:
            out.append(dt)
    out.sort()
    return out


def recent_timestamps(source: str) -> list[datetime]:
    if source == "claude":
        return recent_claude_user_timestamps()
    if source == "codex":
        return recent_codex_timestamps()
    return []


def infer_window_start(timestamps: list[datetime], now: datetime) -> datetime | None:
    """Walk forward; a new window opens at the first timestamp after a ≥5h gap.
    Returns the start of the currently-open window, or None if no window is open."""
    if not timestamps:
        return None
    window_start = timestamps[0]
    for ts in timestamps[1:]:
        if ts - window_start >= WINDOW:
            window_start = ts
    if now - window_start >= WINDOW:
        return None
    return window_start


# ---------- state ----------

@dataclass
class State:
    window_start: datetime | None = None
    last_ping_at: datetime | None = None


# ---------- ping + toast ----------

def fire_ping(cli: Cli) -> tuple[bool, str]:
    try:
        proc = subprocess.run(
            cli.ping_command,
            capture_output=True, text=True, timeout=PING_TIMEOUT_SECONDS, shell=False,
            creationflags=_SUBPROCESS_FLAGS, encoding="utf-8", errors="replace",
        )
    except FileNotFoundError:
        return False, "command not found"
    except subprocess.TimeoutExpired:
        return False, f"timeout after {PING_TIMEOUT_SECONDS}s"
    except OSError as e:
        return False, f"os error: {e}"
    combined = ((proc.stdout or "") + "\n" + (proc.stderr or "")).lower()
    for phrase in PAUSE_PHRASES:
        if phrase in combined:
            return False, phrase
    if proc.returncode != 0:
        snippet = (proc.stderr or proc.stdout or "").strip().splitlines()
        tail = snippet[-1] if snippet else ""
        return False, f"exit {proc.returncode}: {tail[:80]}"
    return True, "ok"


def toast(title: str, body: str) -> None:
    try:
        from winotify import Notification  # type: ignore
    except ImportError:
        return
    try:
        Notification(app_id="Claudex5hWindowRoller", title=title, msg=body).show()
    except Exception as e:  # noqa: BLE001
        logging.warning("toast failed: %s", e)


# ---------- formatting ----------

def _fmt_duration(td: timedelta) -> str:
    s = int(td.total_seconds())
    if s < 0:
        return f"-{_fmt_duration(-td)}"
    h, rem = divmod(s, 3600)
    m, _ = divmod(rem, 60)
    return f"{h}h{m:02d}m" if h else f"{m}m"


# ---------- main loop ----------

def tick(states: dict[str, State], clis: list[Cli], installed: dict[str, bool]) -> None:
    now = datetime.now(timezone.utc)
    for cli in clis:
        if not installed.get(cli.name, False):
            continue
        st = states.setdefault(cli.name, State())
        timestamps = recent_timestamps(cli.log_source)
        st.window_start = infer_window_start(timestamps, now)

        if st.window_start is None:
            logging.info("%-6s  no open window  ↻ rolling now", cli.name)
            end = now  # force a ping below
        else:
            end = st.window_start + WINDOW
            left = end - now
            logging.info("%-6s  %s left", cli.name, _fmt_duration(left))

        if now < end - PING_LEAD:
            continue
        if st.last_ping_at and (now - st.last_ping_at) < timedelta(minutes=4):
            continue
        st.last_ping_at = now
        ok, reason = fire_ping(cli)
        if ok:
            logging.info("%-6s  ✓ rolled", cli.name)
        else:
            logging.warning("%-6s  ✗ paused: %s", cli.name, reason)
            toast(f"Window paused: {cli.name}", reason)


def setup_logging() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    handlers: list[logging.Handler] = [logging.FileHandler(LOG_FILE, encoding="utf-8")]
    if sys.stdout and sys.stdout.isatty():
        handlers.append(logging.StreamHandler(sys.stdout))
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s  %(message)s",
        datefmt="%H:%M:%S",
        handlers=handlers,
    )


def detect_installed(clis: list[Cli]) -> dict[str, bool]:
    return {cli.name: _resolve_executable(cli.ping_command[0]) is not None for cli in clis}


def status() -> int:
    now = datetime.now(timezone.utc)
    clis = _resolve_clis()
    installed = detect_installed(clis)
    for cli in clis:
        if not installed[cli.name]:
            print(f"{cli.name:<6}  not installed (skipped)")
            continue
        start = infer_window_start(recent_timestamps(cli.log_source), now)
        if start is None:
            print(f"{cli.name:<6}  window closed (no recent activity)")
            continue
        end = start + WINDOW
        print(
            f"{cli.name:<6}  {_fmt_duration(end - now)} left  "
            f"(ping in {_fmt_duration(end - now - PING_LEAD)})"
        )
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--once", action="store_true", help="run one cycle and exit")
    ap.add_argument("--status", action="store_true", help="print window state and exit")
    args = ap.parse_args()

    if args.status:
        return status()

    setup_logging()
    clis = _resolve_clis()
    installed = detect_installed(clis)
    active = [name for name, ok in installed.items() if ok]
    skipped = [name for name, ok in installed.items() if not ok]
    logging.info("starting — watching: %s%s",
                 ", ".join(active) or "(none)",
                 f"   skipped (not on PATH): {', '.join(skipped)}" if skipped else "")
    for cli in clis:
        if installed[cli.name]:
            logging.info("%-6s  → %s", cli.name, cli.ping_command[0])
    if not active:
        logging.error("neither claude nor codex found — nothing to do")
        return 1

    states: dict[str, State] = {}
    if args.once:
        tick(states, clis, installed)
        return 0

    while True:
        try:
            tick(states, clis, installed)
        except Exception:  # noqa: BLE001
            logging.exception("tick failed")
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    sys.exit(main())
