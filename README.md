# Claudex-5h-Window-Roller

Keeps the **Claude Code** and **Codex CLI** 5-hour usage windows continuously
rolling on Windows, so you start your day already partway through a window —
the next reset happens during your work day, not right when you sit down.

Toasts you if a rollover fails (auth expired, rate-limited, etc.).

![tests](https://github.com/rriordan/Claudex-5h-Window-Roller/actions/workflows/test.yml/badge.svg)

## How it works

Every 60s the service reads the latest timestamps from each CLI's local
session log:

- **Claude Code:** `%USERPROFILE%\.claude\projects\**\*.jsonl` (`type:"user"` rows)
- **Codex CLI:** `%USERPROFILE%\.codex\history.jsonl`

It walks back through those timestamps, finds the start of the currently-open
5h window (the most recent message after a ≥5h gap), and ~90s before the
window would close fires a tiny headless prompt (`claude -p "ping"` /
`codex exec "ping"`) so the next 5h block opens seamlessly. If the ping
fails or returns a rate-limit / auth error you get a Windows toast.

## Install

Requires Python 3.11+ and `claude` / `codex` on `PATH`.

```powershell
git clone https://github.com/rriordan/Claudex-5h-Window-Roller.git
cd Claudex-5h-Window-Roller
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

That's it — `install.ps1` installs dependencies, registers a Scheduled Task
that runs at every logon, and starts it. No admin prompt needed; the task
runs as the current user at limited run level.

### Verify

```powershell
python .\claudex_roller.py --status        # prints each CLI's window state
notepad $env:USERPROFILE\.claudex-5h-window-roller\service.log
```

### Configure (optional)

Defaults are fine for most people. To override, drop a config at
`%USERPROFILE%\.claudex-5h-window-roller\config.toml` — see [config.example.toml](config.example.toml).

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall_task.ps1
```

## Tests

```powershell
python -m unittest test_claudex_roller.py -v
```

## Notes & limits

- **Cost:** each ping consumes the smallest possible slice of your Claude Code
  / Codex subscription quota — not API credits, and negligible in practice
  (one extremely short prompt per 5h per CLI).
- **PC must be on.** The task is configured *not* to wake the machine, so if
  your computer is asleep the window won't roll. (That's usually fine — if
  it's asleep you weren't using Claude/Codex anyway.)
- **Quiet hours defeat the purpose overnight.** The config supports
  `quiet_start` / `quiet_end` to suppress auto-pings during a time range, but
  if you set quiet hours overnight the window will lapse by morning and the
  whole point of this tool is lost. Leave them unset unless you have a
  specific reason.
- **Claude.ai web** is out of scope — there's no local log to read.

## License

MIT — see [LICENSE](LICENSE).
