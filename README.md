# Claudex-5h-Window-Roller

Keeps your **Claude Code** and **Codex CLI** 5-hour usage windows continuously
rolling on Windows, so you start your day already partway through a window —
the next reset happens during your work day, not right when you sit down.

Toasts you if a rollover fails (auth expired, rate-limited, etc.).

**One PowerShell file. No Python. No third-party modules. No admin.**

## One-click install

Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/rriordan/Claudex-5h-Window-Roller/main/claudex-roller.ps1 | iex
```

That's it. The script downloads itself into `%USERPROFILE%\.claudex-5h-window-roller\`,
registers a Scheduled Task that fires once a minute at logon, and starts it.

### Verify

```powershell
& "$env:USERPROFILE\.claudex-5h-window-roller\claudex-roller.ps1" -Status
```

You should see:

```
claude  4h12m left  (ping in 4h10m)  ->  C:\Users\rober\AppData\Roaming\Claude\claude-code\2.1.138\claude.exe
codex   2h47m left  (ping in 2h46m)  ->  C:\Users\rober\AppData\Local\Programs\OpenAI\Codex\bin\codex.EXE
```

Or if a CLI isn't installed:

```
claude  4h12m left  (ping in 4h10m)  ->  ...
codex   not installed (skipped)
```

Tail the log:

```powershell
Get-Content "$env:USERPROFILE\.claudex-5h-window-roller\service.log" -Wait
```

Sample log output:

```
14:23:01  claude  4h12m left
14:23:01  codex   2h47m left
19:09:34  claude  0m left
19:09:34  claude  OK rolled
```

## Uninstall

```powershell
& "$env:USERPROFILE\.claudex-5h-window-roller\claudex-roller.ps1" -Uninstall
```

Removes the scheduled task. Logs/state at `~\.claudex-5h-window-roller\` are
left behind — delete the folder yourself for a clean slate.

## How it works

Every 60s the scheduled task wakes up, runs the script in `-Tick` mode, and
exits. Each tick reads the latest timestamps from each CLI's local log:

- **Claude Code:** `%USERPROFILE%\.claude\projects\**\*.jsonl` (`type:"user"` rows)
- **Codex CLI:** `%USERPROFILE%\.codex\history.jsonl`

It walks back through those timestamps, finds the start of the
currently-open 5h window (the most recent message after a ≥5h gap), and ~90s
before the window would close fires a tiny headless prompt
(`claude -p ping` / `codex exec --skip-git-repo-check ping`) so the next 5h
block opens seamlessly. If a ping fails or returns a rate-limit / auth error,
you get a Windows toast.

There is no background process between ticks — just a one-shot scheduled task.

## Notes & limits

- **Cost:** each ping is one very short prompt against your Claude Code /
  Codex subscription quota — not API credits. Negligible (one prompt per
  5h per CLI).
- **PC must be on.** The task does *not* wake the machine. If your computer
  is asleep, the window won't roll — that's usually fine since you weren't
  using Claude/Codex then anyway.
- **Auto-detects executables.** Works whether `claude` is on PATH or only
  installed via Claude Code desktop (`%APPDATA%\Claude\claude-code\<ver>\claude.exe`).
- **Claude.ai web** is out of scope — no local log to read.

## All flags

```powershell
.\claudex-roller.ps1             # default: install
.\claudex-roller.ps1 -Install    # explicit install
.\claudex-roller.ps1 -Uninstall  # remove scheduled task
.\claudex-roller.ps1 -Status     # print window state
.\claudex-roller.ps1 -Tick       # run one cycle (internal; what the task runs)
```

## License

MIT — see [LICENSE](LICENSE).
