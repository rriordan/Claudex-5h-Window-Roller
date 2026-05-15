# Claudex-5h-Window-Roller

Keeps your **Claude Code** and **Codex CLI** 5-hour usage windows continuously
rolling on Windows, so you start your day already partway through a window —
the next reset happens during your work day, not right when you sit down.

Toasts you if a rollover fails (auth expired, rate-limited, etc.).

![tests](https://github.com/rriordan/Claudex-5h-Window-Roller/actions/workflows/test.yml/badge.svg)

## One-click install

Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/rriordan/Claudex-5h-Window-Roller/main/install.ps1 | iex
```

That's it. The installer:

1. Drops the script into `%USERPROFILE%\.claudex-5h-window-roller\`
2. Installs the one Python dependency (`winotify`, user scope, no admin)
3. Registers a Scheduled Task that runs at every logon
4. Starts it

Requires Python 3.11+ on PATH. No admin prompt; nothing to configure.

### Verify

```powershell
python "$env:USERPROFILE\.claudex-5h-window-roller\claudex_roller.py" --status
```

You should see something like:

```
claude  4h12m left  (ping in 4h10m)
codex   2h47m left  (ping in 2h46m)
```

Or if a CLI isn't installed:

```
claude  4h12m left  (ping in 4h10m)
codex   not installed (skipped)
```

The service writes a human-readable log:

```
14:23:01  starting — watching: claude, codex
14:23:01  claude  → C:\Users\rober\AppData\Roaming\Claude\claude-code\2.1.138\claude.exe
14:23:01  codex   → C:\Users\rober\AppData\Local\Programs\OpenAI\Codex\bin\codex.EXE
14:23:01  claude  4h12m left
14:23:01  codex   2h47m left
19:09:34  claude  0m left
19:09:34  claude  ✓ rolled
```

Tail it with:

```powershell
Get-Content "$env:USERPROFILE\.claudex-5h-window-roller\service.log" -Wait
```

## Uninstall

```powershell
irm https://raw.githubusercontent.com/rriordan/Claudex-5h-Window-Roller/main/uninstall.ps1 | iex
```

Removes the scheduled task. Logs/state at `~\.claudex-5h-window-roller\` are
left behind — delete the folder yourself if you want a clean slate.

## How it works

Every 60s the service reads the latest timestamps from each CLI's local log:

- **Claude Code:** `%USERPROFILE%\.claude\projects\**\*.jsonl` (`type:"user"` rows)
- **Codex CLI:** `%USERPROFILE%\.codex\history.jsonl`

It walks back through those timestamps, finds the start of the
currently-open 5h window (the most recent message after a ≥5h gap), and ~90s
before the window would close fires a tiny headless prompt
(`claude -p ping` / `codex exec ping`) so the next 5h block opens seamlessly.
If a ping fails or returns a rate-limit / auth error, you get a Windows toast.

## Notes & limits

- **Cost:** each ping is one very short prompt against your Claude Code /
  Codex subscription quota — not API credits. Negligible in practice
  (one prompt per 5h per CLI).
- **PC must be on.** The task does *not* wake the machine. If your computer
  is asleep, the window won't roll — that's usually fine since you weren't
  using Claude/Codex anyway.
- **Claude.ai web** is out of scope — there's no local log to read.

## Run the tests

```powershell
python -m unittest test_claudex_roller -v
```

## License

MIT — see [LICENSE](LICENSE).
