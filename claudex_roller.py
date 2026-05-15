"""Claudex-5h-Window-Roller: keep Claude Code and Codex CLI 5-hour usage windows rolling.

Runs as a background service. For each enabled CLI it tails the local session
log to figure out when the current 5-hour window opened, fires a tiny `ping`
prompt ~90s before the window would close to immediately open the next one,
and shows a Windows toast if the auto-ping fails or a window expires without
successfully rolling over.

Usage:
    pythonw claudex_roller.py                 # background service (Task Scheduler)
    python  claudex_roller.py --once          # one polling cycle, then exit
    python  claudex_roller.py --dry-run       # don't fire pings, don't toast
    python  claudex_roller.py --status        # print current window state, then exit
    python  claudex_roller.py --force-ping claude   # fire one ping for <cli>, then exit
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import subprocess
import sys
import time
import tomllib
from dataclasses import dataclass
from datetime import datetime, time as dtime, timedelta, timezone
from pathlib import Path

WINDOW = timedelta(hours=5)
# Must be > POLL_SECONDS plus expected ping duration, otherwise the window can
# close between polls or mid-ping. 90s = one poll cycle of slack + 30s for the
# ping itself to complete.
PING_LEAD = timedelta(seconds=90)
POLL_SECONDS = 60
PING_TIMEOUT_SECONDS = 30
PAUSE_PHRASES = ("rate limit", "usage limit", "unauthorized", "quota exceeded", "exceeded your")

# On Windows, hide the console window that would otherwise flash when the
# service (running under pythonw) spawns claude.exe / codex.exe as children.
_SUBPROCESS_FLAGS = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0

# Home dir is USERPROFILE on Windows, HOME elsewhere. Falling back to HOME
# also lets the tests import this module on non-Windows CI.
_HOME = Path(os.environ.get("USERPROFILE") or os.environ.get("HOME") or ".")
STATE_DIR = _HOME / ".claudex-5h-window-roller"
LOG_FILE = STATE_DIR / "service.log"
CONFIG_FILE = STATE_DIR / "config.toml"


# ---------- config ----------

@dataclass
class CliConfig:
    name: str
    enabled: bool
    ping_command: list[str]
    log_source: str  # "claude" | "codex"


@dataclass
class Config:
    clis: list[CliConfig]
    quiet_start: dtime | None
    quiet_end: dtime | None
    toast_on_pause: bool
    toast_on_rollover: bool


def _parse_hhmm(s: str | None) -> dtime | None:
    if not s:
        return None
    h, m = s.split(":")
    return dtime(int(h), int(m))


def load_config() -> Config:
    if CONFIG_FILE.exists():
        with open(CONFIG_FILE, "rb") as f:
            raw = tomllib.load(f)
    else:
        raw = {}

    def cli(name: str, default_cmd: list[str], source: str) -> CliConfig:
        section = raw.get(name, {})
        return CliConfig(
            name=name,
            enabled=section.get("enabled", True),
            ping_command=section.get("ping_command", default_cmd),
            log_source=source,
        )

    sched = raw.get("schedule", {})
    notif = raw.get("notifications", {})
    return Config(
        clis=[
            cli("claude", ["claude", "-p", "ping"], "claude"),
            cli("codex", ["codex", "exec", "ping"], "codex"),
        ],
        quiet_start=_parse_hhmm(sched.get("quiet_start")),
        quiet_end=_parse_hhmm(sched.get("quiet_end")),
        toast_on_pause=notif.get("toast_on_pause", True),
        toast_on_rollover=notif.get("toast_on_rollover", False),
    )


# ---------- log readers ----------

CLAUDE_PROJECTS = _HOME / ".claude" / "projects"
CODEX_HISTORY = _HOME / ".codex" / "history.jsonl"


def _tail_lines(path: Path, n: int = 200) -> list[str]:
    """Read last ~n lines of a text file without slurping the whole thing."""
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
    """All user-message timestamps from recently-modified Claude project JSONLs.

    We only care about timestamps in roughly the last 24h — enough to find the
    start of the currently-open 5h window, with margin.
    """
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
    """Find the start of the currently-open 5h window from recent timestamps.

    Walk forward through timestamps. A new window opens at the first timestamp
    after a gap >= 5h (or at the first timestamp ever seen). The currently-open
    window's start is the *last* such opener — provided we're still inside it.
    """
    if not timestamps:
        return None
    window_start = timestamps[0]
    for ts in timestamps[1:]:
        if ts - window_start >= WINDOW:
            window_start = ts
    if now - window_start >= WINDOW:
        return None  # window already closed; nothing open
    return window_start


# ---------- window state ----------

@dataclass
class CliState:
    window_start: datetime | None = None
    last_seen_ts: datetime | None = None
    last_ping_at: datetime | None = None
    last_ping_outcome: str | None = None  # "rolled" | "paused:<reason>" | None


def update_window(state: CliState, timestamps: list[datetime], now: datetime) -> None:
    """Recompute window_start by inferring the open window from recent log activity."""
    inferred = infer_window_start(timestamps, now)
    state.window_start = inferred
    state.last_seen_ts = timestamps[-1] if timestamps else None


def window_end(state: CliState) -> datetime | None:
    if state.window_start is None:
        return None
    return state.window_start + WINDOW


# ---------- ping + toast ----------

def fire_ping(cli: CliConfig) -> tuple[bool, str]:
    """Returns (rolled_ok, reason). reason is short, human-readable."""
    try:
        proc = subprocess.run(
            cli.ping_command,
            capture_output=True,
            text=True,
            timeout=PING_TIMEOUT_SECONDS,
            shell=False,
            creationflags=_SUBPROCESS_FLAGS,
            encoding="utf-8",
            errors="replace",
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
        logging.warning("winotify not installed; would toast: %s — %s", title, body)
        return
    try:
        Notification(app_id="Claudex5hWindowRoller", title=title, msg=body).show()
    except Exception as e:  # noqa: BLE001
        logging.warning("toast failed: %s", e)


# ---------- main loop ----------

def in_quiet_hours(cfg: Config, now: datetime) -> bool:
    if cfg.quiet_start is None or cfg.quiet_end is None:
        return False
    t = now.astimezone().time()
    qs, qe = cfg.quiet_start, cfg.quiet_end
    if qs <= qe:
        return qs <= t < qe
    return t >= qs or t < qe  # wraps midnight


def tick(cfg: Config, states: dict[str, CliState], *, dry_run: bool) -> None:
    now = datetime.now(timezone.utc)
    quiet = in_quiet_hours(cfg, now)
    for cli in cfg.clis:
        if not cli.enabled:
            continue
        st = states.setdefault(cli.name, CliState())
        timestamps = recent_timestamps(cli.log_source)
        update_window(st, timestamps, now)
        end = window_end(st)
        observed = timestamps[-1] if timestamps else None
        logging.info(
            "[%s] last=%s window_start=%s window_end=%s quiet=%s",
            cli.name,
            observed.isoformat() if observed else "—",
            st.window_start.isoformat() if st.window_start else "—",
            end.isoformat() if end else "—",
            quiet,
        )
        if quiet:
            continue
        should_ping = (
            end is None  # no window open yet — open one
            or now >= end - PING_LEAD
        )
        if not should_ping:
            continue
        # Debounce: don't ping more than once per 4 minutes per CLI.
        if st.last_ping_at and (now - st.last_ping_at) < timedelta(minutes=4):
            continue
        if dry_run:
            logging.info("[%s] DRY-RUN: would fire ping %s", cli.name, cli.ping_command)
            continue
        logging.info("[%s] firing ping: %s", cli.name, cli.ping_command)
        st.last_ping_at = now
        ok, reason = fire_ping(cli)
        st.last_ping_outcome = "rolled" if ok else f"paused:{reason}"
        if ok:
            logging.info("[%s] rollover ok", cli.name)
            if cfg.toast_on_rollover:
                toast("Window rolled", f"{cli.name}: new 5h window opened")
        else:
            logging.warning("[%s] PAUSED: %s", cli.name, reason)
            if cfg.toast_on_pause:
                toast(f"Window paused: {cli.name}", reason)


def setup_logging() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    handlers: list[logging.Handler] = [
        logging.FileHandler(LOG_FILE, encoding="utf-8"),
    ]
    if sys.stdout and sys.stdout.isatty():
        handlers.append(logging.StreamHandler(sys.stdout))
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        handlers=handlers,
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--once", action="store_true", help="run one cycle and exit")
    ap.add_argument("--dry-run", action="store_true", help="don't actually ping or toast")
    ap.add_argument("--force-ping", metavar="CLI", help="fire one ping for <cli> and exit")
    ap.add_argument("--status", action="store_true", help="print current window state and exit")
    args = ap.parse_args()

    setup_logging()
    cfg = load_config()

    if args.status:
        now = datetime.now(timezone.utc)
        for cli in cfg.clis:
            timestamps = recent_timestamps(cli.log_source)
            start = infer_window_start(timestamps, now)
            if start is None:
                print(f"[{cli.name}] enabled={cli.enabled}  window: closed (no activity in last 5h)")
                continue
            end = start + WINDOW
            remaining = end - now
            until_ping = remaining - PING_LEAD
            mins = int(until_ping.total_seconds() // 60)
            print(
                f"[{cli.name}] enabled={cli.enabled}  "
                f"window_start={start.astimezone().isoformat(timespec='seconds')}  "
                f"window_end={end.astimezone().isoformat(timespec='seconds')}  "
                f"ping_in={mins}m"
            )
        return 0

    logging.info("Claudex-5h-Window-Roller starting (clis=%s, dry_run=%s)",
                 [c.name for c in cfg.clis if c.enabled], args.dry_run)

    if args.force_ping:
        target = next((c for c in cfg.clis if c.name == args.force_ping), None)
        if not target:
            logging.error("unknown CLI: %s", args.force_ping)
            return 2
        ok, reason = fire_ping(target)
        if ok:
            toast(f"Window rolled: {target.name}", "forced ping ok")
            logging.info("forced ping ok")
        else:
            toast(f"Window paused: {target.name}", reason)
            logging.warning("forced ping failed: %s", reason)
        return 0 if ok else 1

    states: dict[str, CliState] = {}
    if args.once:
        tick(cfg, states, dry_run=args.dry_run)
        return 0

    while True:
        try:
            tick(cfg, states, dry_run=args.dry_run)
        except Exception:  # noqa: BLE001
            logging.exception("tick failed")
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    sys.exit(main())
