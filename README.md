# Claudex-5h-Window-Roller

Keeps your **Claude Code** and **Codex CLI** 5-hour usage windows continuously
rolling on Windows, so you start your day already partway through a window —
the next reset happens during your work day, not right when you sit down.

Toasts you if a rollover fails (auth expired, rate-limited, etc.).

**One PowerShell file. No Python. No third-party modules. No admin.**

## Desktop app

This repo also includes an Electron control panel for install, uninstall,
enable, disable, tray monitoring, and notification preferences.

```bash
npm install
npm run dev
```

Build app artifacts:

```bash
npm run build
```

Package a Windows installer:

```bash
npm run dist
```

The app is Windows-capable first. macOS and Linux launch paths are kept behind a
platform adapter and currently show unsupported roller operations.

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

You should see something like:

```
Detected installations:
  * claude  Claude Code (2.1.138)         C:\Users\rober\AppData\Roaming\Claude\claude-code\2.1.138\claude.exe
    claude  VS Code Insiders extension    C:\Users\rober\.vscode-insiders\extensions\anthropic.claude-code-2.1.142-win32-x64\resources\native-binary\claude.exe
    claude  WSL (Ubuntu)                  /home/rober/.local/bin/claude
  * codex   PATH                          C:\Users\rober\AppData\Local\Programs\OpenAI\Codex\bin\codex.exe
    codex   WSL (Ubuntu)                  /mnt/c/Users/rober/.codex/bin/wsl/codex
    claude  Claude Desktop (Store/MSIX)   C:\Program Files\WindowsApps\Claude_1.7196.0.0_x64_...\app\Claude.exe
    (GUI app — not used for pinging; quota is shared with claude CLI)

Window state:
  claude  4h12m left  (ping in 4h10m)  via Claude Code (2.1.138)
  codex   2h47m left  (ping in 2h46m)  via PATH
```

A `*` marks the install used for actual pings (Windows CLIs are preferred over
WSL — no WSL boot overhead). The 5-hour quota is per-account, so pinging via
*any* working CLI advances the window everywhere (Claude Desktop, VS Code
extension, WSL, etc.).

### Automatic failover

If an install fails or hangs twice in a row, the script skips it (marked `x`
in `-Status`) and tries the next install in the priority list. After 60 minutes
the failed install is given another chance — useful when failures are
transient (auth blip, sandbox config change). Per-CLI timeouts:

| Tool | Timeout | Why |
|---|---|---|
| claude | 30s | Headless `-p` prompt is fast (~5s typically) |
| codex  | 120s | Codex sessions load skills, hooks and MCPs; can take 60-90s before responding |

### What gets detected

For each tool, in priority order:

1. **PATH** — `Get-Command claude` / `Get-Command codex`
2. **Anthropic / OpenAI installers**
   - Claude: `%APPDATA%\Claude\claude-code\<version>\claude.exe`
   - Codex: `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin\codex.exe`
3. **VS Code extension native binaries** (`anthropic.claude-code-*\resources\native-binary\claude.exe`)
4. **Global package managers** — `%APPDATA%\npm\<tool>.cmd`, `%USERPROFILE%\.bun\bin\<tool>.exe`, `%LOCALAPPDATA%\pnpm\<tool>.cmd`
5. **WSL distros** — `wsl -d <distro> -- command -v <tool>` (skips `docker-desktop`)

**Logs are read from every source** — Windows-side `~/.claude/projects/` plus
every WSL distro's `\\wsl.localhost\<distro>\home\*\.claude\projects\` —
so the window inference stays accurate no matter where you actually use the CLI.

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
.\claudex-roller.ps1 -Enable     # re-enable roller ticks
.\claudex-roller.ps1 -Disable    # disable roller ticks without uninstalling
.\claudex-roller.ps1 -JsonStatus # print machine-readable status for the app
```

## License

MIT — see [LICENSE](LICENSE).
