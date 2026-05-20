<#
.SYNOPSIS
    Claudex 5h Window Roller - keep Claude Code & Codex CLI 5-hour usage
    windows continuously rolling on Windows.

.DESCRIPTION
    Single PowerShell script. No Python. No third-party modules.

    Once per minute (via Scheduled Task) it reads each CLI's local log,
    figures out when the current 5h window opened, and ~90s before the
    window would close resumes the dedicated roller chat session to send
    a tiny `ping`, keeping the next 5h block seamlessly open.
    Shows a Windows toast if a ping fails.

.PARAMETER Install
    Scan for installed CLIs (asks the user if one isn't found), drop the
    script into %USERPROFILE%\.claudex-5h-window-roller, register the
    scheduled task, and start it.

.PARAMETER Uninstall
    Unregister the scheduled task. Leaves logs/state intact.

.PARAMETER Status
    Print each CLI's current window state and exit.

.PARAMETER Tick
    Internal: run one polling cycle. Invoked by the scheduled task.

.EXAMPLE
    # One-click install from GitHub:
    irm https://raw.githubusercontent.com/rriordan/Claudex-5h-Window-Roller/main/claudex-roller.ps1 | iex

.EXAMPLE
    .\claudex-roller.ps1 -Status
#>
[CmdletBinding(DefaultParameterSetName='Install')]
param(
    [Parameter(ParameterSetName='Install')]   [switch]$Install,
    [Parameter(ParameterSetName='Uninstall')] [switch]$Uninstall,
    [Parameter(ParameterSetName='Status')]    [switch]$Status,
    [Parameter(ParameterSetName='Tick')]      [switch]$Tick,
    [Parameter(ParameterSetName='Enable')]    [switch]$Enable,
    [Parameter(ParameterSetName='Disable')]   [switch]$Disable,
    [Parameter(ParameterSetName='JsonStatus')] [switch]$JsonStatus
)

$ErrorActionPreference = 'Stop'

# ---------- constants ----------

$Script:WindowMinutes  = 300        # 5h
$Script:PingLeadSec    = 90
$Script:PauseRegex     = '(rate limit|usage limit|unauthorized|quota exceeded|exceeded your)'
$Script:DebounceMinutes = 4

# Per-CLI ping timeouts. Codex sessions load skills/hooks/MCPs and can take
# 60-90s before the model responds; claude pings are typically <10s.
$Script:PingTimeoutSec = @{
    'claude' = 30
    'codex'  = 120
}

# Fallback chain controls.
$Script:MaxConsecFailures   = 2      # skip a source after this many consecutive failures
$Script:FailureRetryMinutes = 60     # retry a failed source after this much time has passed

$Script:TaskName        = 'Claudex5hWindowRoller'
$Script:StateDir        = Join-Path $env:USERPROFILE '.claudex-5h-window-roller'
$Script:LogFile         = Join-Path $Script:StateDir 'service.log'
$Script:StateFile       = Join-Path $Script:StateDir 'state.json'
$Script:InstalledScript = Join-Path $Script:StateDir 'claudex-roller.ps1'

$Script:WslExe      = 'C:\Windows\System32\wsl.exe'
$Script:RawScriptUrl = 'https://raw.githubusercontent.com/rriordan/Claudex-5h-Window-Roller/main/claudex-roller.ps1'

# Cache WSL distro list for the duration of a single tick (script restarts each tick).
$Script:WslDistroCache = $null

# ---------- logging ----------

function Write-RollerLog {
    param([string]$Cli = '', [string]$Message, [switch]$Warn)
    $line = "{0}  {1,-6}  {2}" -f (Get-Date -Format 'HH:mm:ss'), $Cli, $Message
    try {
        New-Item -ItemType Directory -Force -Path $Script:StateDir | Out-Null
        Add-Content -Path $Script:LogFile -Value $line -Encoding utf8
    } catch {}
    if ($Host.UI.RawUI -and -not [Console]::IsOutputRedirected) {
        if ($Warn) { Write-Host $line -ForegroundColor Yellow } else { Write-Host $line }
    }
}

# ---------- WSL discovery ----------

function Get-WslDistros {
    if ($null -ne $Script:WslDistroCache) { return $Script:WslDistroCache }
    if (-not (Test-Path $Script:WslExe)) { $Script:WslDistroCache = @(); return @() }
    $names = @()
    $prev = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        $raw = & $Script:WslExe --list --quiet 2>$null
        if ($raw) {
            $names = @($raw | ForEach-Object { ($_ -replace "`0","").Trim() } |
                Where-Object { $_ -and $_ -notmatch '^docker-desktop' })
        }
    } catch {} finally {
        [Console]::OutputEncoding = $prev
    }
    $Script:WslDistroCache = $names
    return $names
}

function Get-WslHomeDirs {
    param([string]$Distro)
    $roots = @()
    foreach ($basePart in @('home', 'root')) {
        $path = "\\wsl.localhost\$Distro\$basePart"
        if ($basePart -eq 'root') {
            if (Test-Path $path -ErrorAction SilentlyContinue) { $roots += $path }
        } else {
            if (Test-Path $path -ErrorAction SilentlyContinue) {
                Get-ChildItem $path -Directory -ErrorAction SilentlyContinue |
                    ForEach-Object { $roots += $_.FullName }
            }
        }
    }
    return $roots
}

# ---------- log sources ----------

function Get-ClaudeLogRoots {
    $roots = @()
    $win = Join-Path $env:USERPROFILE '.claude\projects'
    if (Test-Path $win) { $roots += $win }
    foreach ($distro in (Get-WslDistros)) {
        foreach ($homeDir in (Get-WslHomeDirs $distro)) {
            $p = Join-Path $homeDir '.claude\projects'
            if (Test-Path $p -ErrorAction SilentlyContinue) { $roots += $p }
        }
    }
    return $roots
}

function Get-CodexLogFiles {
    $files = @()
    $win = Join-Path $env:USERPROFILE '.codex\history.jsonl'
    if (Test-Path $win) { $files += $win }
    foreach ($distro in (Get-WslDistros)) {
        foreach ($homeDir in (Get-WslHomeDirs $distro)) {
            $p = Join-Path $homeDir '.codex\history.jsonl'
            if (Test-Path $p -ErrorAction SilentlyContinue) { $files += $p }
        }
    }
    return $files
}

# ---------- log readers ----------

function Get-ClaudeUserTimestamps {
    $cutoff = (Get-Date).ToUniversalTime().AddHours(-24)
    $result = New-Object System.Collections.Generic.List[datetime]
    foreach ($root in (Get-ClaudeLogRoots)) {
        Get-ChildItem -Path $root -Filter *.jsonl -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -ge $cutoff } |
            ForEach-Object {
                Get-Content -Path $_.FullName -Tail 500 -ErrorAction SilentlyContinue | ForEach-Object {
                    if (-not $_) { return }
                    $row = $null
                    try { $row = $_ | ConvertFrom-Json -ErrorAction Stop } catch { return }
                    if ($row.type -ne 'user' -or -not $row.timestamp) { return }
                    try {
                        $dt = [datetime]::Parse(
                            $row.timestamp, $null,
                            [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
                            [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                    } catch { return }
                    if ($dt -ge $cutoff) { [void]$result.Add($dt) }
                }
            }
    }
    return ,($result | Sort-Object)
}

function Get-CodexTimestamps {
    $cutoff = (Get-Date).ToUniversalTime().AddHours(-24)
    $result = New-Object System.Collections.Generic.List[datetime]
    foreach ($file in (Get-CodexLogFiles)) {
        Get-Content -Path $file -Tail 1000 -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $_) { return }
            $row = $null
            try { $row = $_ | ConvertFrom-Json -ErrorAction Stop } catch { return }
            if ($null -eq $row.ts) { return }
            try {
                $dt = [datetime]::new(1970,1,1,0,0,0,[DateTimeKind]::Utc).AddSeconds([long]$row.ts)
            } catch { return }
            if ($dt -ge $cutoff) { [void]$result.Add($dt) }
        }
    }
    return ,($result | Sort-Object)
}

# ---------- window inference ----------

function Get-WindowStart {
    param([datetime[]]$Timestamps, [datetime]$Now)
    if (-not $Timestamps -or $Timestamps.Count -eq 0) { return $null }
    $windowStart = $Timestamps[0]
    for ($i = 1; $i -lt $Timestamps.Count; $i++) {
        $ts = $Timestamps[$i]
        if (($ts - $windowStart).TotalMinutes -ge $Script:WindowMinutes) {
            $windowStart = $ts
        }
    }
    if (($Now - $windowStart).TotalMinutes -ge $Script:WindowMinutes) { return $null }
    return $windowStart
}

# ---------- session ID tracking (claude only) ----------

function Get-LatestClaudeSessionId {
    param([datetime]$AfterUtc)
    # The newest .jsonl file in Claude's project dirs modified after $AfterUtc
    # carries the session UUID as its filename (BaseName).
    $best      = $null
    $afterLocal = $AfterUtc.ToLocalTime()
    foreach ($root in (Get-ClaudeLogRoots)) {
        Get-ChildItem -Path $root -Filter '*.jsonl' -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt $afterLocal } |
            ForEach-Object {
                if (-not $best -or $_.LastWriteTime -gt $best.LastWriteTime) { $best = $_ }
            }
    }
    if ($best) { return $best.BaseName }
    return $null
}

# ---------- install detection ----------

function Find-ClaudeDesktopMsix {
    $hits = Get-ChildItem 'C:\Program Files\WindowsApps' -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue
    foreach ($h in $hits) {
        $exe = Join-Path $h.FullName 'app\Claude.exe'
        if (Test-Path $exe -ErrorAction SilentlyContinue) { return $exe }
    }
    return $null
}

function Get-CliInstallations {
    # Priority order: WSL first (user preference), then Windows PATH, then
    # tool-specific Windows install dirs, then global package managers.
    param([string]$Name)
    $pingArgs = if ($Name -eq 'claude') { @('-p','ping') } else { @('exec','--skip-git-repo-check','ping') }
    $found = New-Object System.Collections.Generic.List[object]
    $seen  = New-Object System.Collections.Generic.HashSet[string]

    function Add-Found($source, $exe, $kind = 'windows', $distro = $null) {
        if (-not $exe) { return }
        $key = "$kind|$distro|$exe"
        if (-not $seen.Add($key)) { return }
        # baseCmd is everything up to and including the binary - used to build
        # --resume commands without re-appending the ping args.
        $baseCmd = if ($kind -eq 'wsl') {
            @($Script:WslExe, '-d', $distro, '--', $exe)
        } else {
            @($exe)
        }
        $found.Add([pscustomobject]@{
            name    = $Name
            source  = $source
            kind    = $kind
            cmd     = $baseCmd + $pingArgs
            baseCmd = $baseCmd
            distro  = $distro
            exe     = $exe
        })
    }

    # 1. WSL - preferred; probe each distro
    foreach ($distro in (Get-WslDistros)) {
        $wslPath = $null
        try {
            $wslPath = & $Script:WslExe -d $distro -- bash -lc "command -v $Name 2>/dev/null" 2>$null
            if ($wslPath) { $wslPath = ([string]$wslPath).Trim() }
        } catch {}
        if ($wslPath) { Add-Found "WSL ($distro)" $wslPath 'wsl' $distro }
    }

    # 2. Windows PATH
    $pathCmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pathCmd) { Add-Found 'PATH' $pathCmd.Source }

    # 3. Tool-specific Windows install directories
    if ($Name -eq 'claude') {
        # Anthropic installer - %APPDATA%\Claude\claude-code\<version>\claude.exe
        $base = Join-Path $env:APPDATA 'Claude\claude-code'
        if (Test-Path $base) {
            $latest = Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending | Select-Object -First 1
            if ($latest) {
                $exe = Join-Path $latest.FullName 'claude.exe'
                if (Test-Path $exe) { Add-Found "Claude Code ($($latest.Name))" $exe }
            }
        }
        # VS Code / VS Code Insiders extension native binaries
        foreach ($extRoot in @("$env:USERPROFILE\.vscode\extensions",
                               "$env:USERPROFILE\.vscode-insiders\extensions")) {
            if (Test-Path $extRoot) {
                $ext = Get-ChildItem $extRoot -Directory -Filter 'anthropic.claude-code-*' -ErrorAction SilentlyContinue |
                    Sort-Object Name -Descending | Select-Object -First 1
                if ($ext) {
                    $exe = Join-Path $ext.FullName 'resources\native-binary\claude.exe'
                    if (Test-Path $exe) {
                        $label = if ($extRoot -match 'insiders') { 'VS Code Insiders extension' } else { 'VS Code extension' }
                        Add-Found $label $exe
                    }
                }
            }
        }
    } else {
        # Codex Windows installer
        $exe = Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe'
        if (Test-Path $exe) { Add-Found 'OpenAI Codex installer' $exe }
    }

    # 4. Generic package manager locations
    foreach ($p in @(
        @{ src = 'npm global';  path = (Join-Path $env:APPDATA        "npm\$Name.cmd") },
        @{ src = 'bun';         path = (Join-Path $env:USERPROFILE    ".bun\bin\$Name.exe") },
        @{ src = 'pnpm global'; path = (Join-Path $env:LOCALAPPDATA   "pnpm\$Name.cmd") }
    )) {
        if (Test-Path $p.path) { Add-Found $p.src $p.path }
    }

    return ,$found
}

# ---------- ping ----------

function Stop-CliProcessTree {
    param($Process)
    if (-not $Process) { return }
    try { & taskkill.exe /T /F /PID $Process.Id 2>$null | Out-Null } catch {
        try { $Process.Kill() } catch {}
    }
}

function Invoke-CliPing {
    param([string[]]$Cmd, [int]$TimeoutSec = 30)
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $procArgs = if ($Cmd.Count -gt 1) { $Cmd[1..($Cmd.Count - 1)] } else { @() }
        $proc = Start-Process -FilePath $Cmd[0] -ArgumentList $procArgs `
            -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile `
            -WindowStyle Hidden -PassThru
        if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
            try { Stop-CliProcessTree -Process $proc } catch {}
            return @{ ok = $false; reason = "timeout after ${TimeoutSec}s" }
        }
        $out = ((Get-Content $stdoutFile -Raw -ErrorAction SilentlyContinue) + "`n" +
                (Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue))
        if ($out -match $Script:PauseRegex) {
            return @{ ok = $false; reason = $Matches[1] }
        }
        if ($proc.ExitCode -ne 0) {
            $tail = ($out -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 1)
            if ($null -eq $tail) { $tail = '' }
            $snippet = $tail.Substring(0, [Math]::Min(80, $tail.Length))
            return @{ ok = $false; reason = "exit $($proc.ExitCode): $snippet" }
        }
        return @{ ok = $true; reason = 'ok' }
    } catch [System.ComponentModel.Win32Exception] {
        return @{ ok = $false; reason = 'command not found' }
    } catch {
        return @{ ok = $false; reason = "os error: $($_.Exception.Message)" }
    } finally {
        Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
    }
}

# ---------- toast ----------

function Show-Toast {
    param([string]$Title, [string]$Body)
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType=WindowsRuntime]
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $payload = @"
<toast><visual><binding template="ToastText02">
<text id="1">$([System.Security.SecurityElement]::Escape($Title))</text>
<text id="2">$([System.Security.SecurityElement]::Escape($Body))</text>
</binding></visual></toast>
"@
        $xml.LoadXml($payload)
        $toast = New-Object Windows.UI.Notifications.ToastNotification($xml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($Script:TaskName).Show($toast)
    } catch {}
}

# ---------- state ----------

function Get-RollerState {
    if (Test-Path $Script:StateFile) {
        try { return Get-Content $Script:StateFile -Raw -Encoding utf8 | ConvertFrom-Json } catch {}
    }
    return [pscustomobject]@{}
}

function Save-RollerState {
    param($State)
    $State | ConvertTo-Json -Depth 5 | Set-Content -Path $Script:StateFile -Encoding utf8
}

function Get-CliState {
    param($State, [string]$Name)
    $section = $State.PSObject.Properties[$Name].Value
    if (-not $section) {
        $section = [pscustomobject]@{
            last_ping_at     = $null
            ping_session_id  = $null
            source_failures  = [pscustomobject]@{}
        }
        $State | Add-Member -NotePropertyName $Name -NotePropertyValue $section -Force
    }
    if (-not $section.PSObject.Properties['source_failures'].Value) {
        $section | Add-Member -NotePropertyName 'source_failures' -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $section.PSObject.Properties['ping_session_id']) {
        $section | Add-Member -NotePropertyName 'ping_session_id' -NotePropertyValue $null -Force
    }
    return $section
}

function Get-UserDisabled {
    param($State)
    $v = $State.PSObject.Properties['user_disabled'].Value
    if (-not $v) { return @() }
    return @($v)
}

function Get-RollerEnabled {
    param($State)
    $v = $State.PSObject.Properties['roller_enabled'].Value
    if ($null -eq $v) { return $true }
    return [bool]$v
}

function Set-RollerEnabled {
    param($State, [bool]$Enabled)
    $State | Add-Member -NotePropertyName 'roller_enabled' -NotePropertyValue $Enabled -Force
    return $State
}

# ---------- format ----------

function Format-Duration {
    param([timespan]$Td)
    $totalSec = [int]$Td.TotalSeconds
    if ($totalSec -lt 0) {
        return "-$([int][math]::Floor([math]::Abs($Td.TotalSeconds) / 60))m"
    }
    $h = [int][math]::Floor($totalSec / 3600)
    $m = [int][math]::Floor(($totalSec % 3600) / 60)
    if ($h -gt 0) { return ('{0}h{1:D2}m' -f $h, $m) }
    return "${m}m"
}

# ---------- fallback chain helpers ----------

function Test-IsoSec {
    param([string]$Iso, [datetime]$Now, [int]$MaxAgeMinutes)
    if (-not $Iso) { return $false }
    try {
        $dt = [datetime]::Parse($Iso, $null,
            [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
            [System.Globalization.DateTimeStyles]::AdjustToUniversal)
        return (($Now - $dt).TotalMinutes -lt $MaxAgeMinutes)
    } catch { return $false }
}

function Select-NextInstall {
    param([object[]]$Installs, $CliState, [datetime]$Now)
    $failures = $CliState.source_failures
    foreach ($install in $Installs) {
        $entry = $failures.PSObject.Properties[$install.source].Value
        if (-not $entry) { return $install }
        $count = [int]($entry.count)
        $stale = -not (Test-IsoSec -Iso $entry.last_failure_at -Now $Now -MaxAgeMinutes $Script:FailureRetryMinutes)
        if ($count -lt $Script:MaxConsecFailures -or $stale) { return $install }
    }
    return $null
}

function Record-PingFailure {
    param($CliState, [string]$Source, [datetime]$Now)
    $existing = $CliState.source_failures.PSObject.Properties[$Source].Value
    $count = if ($existing) { [int]$existing.count + 1 } else { 1 }
    $entry = [pscustomobject]@{ count = $count; last_failure_at = $Now.ToString('o') }
    $CliState.source_failures | Add-Member -NotePropertyName $Source -NotePropertyValue $entry -Force
}

function Record-PingSuccess {
    param($CliState, [string]$Source)
    $existing = $CliState.source_failures.PSObject.Properties[$Source]
    if ($existing) { $CliState.source_failures.PSObject.Properties.Remove($Source) }
}

# ---------- tick ----------

function Invoke-Tick {
    New-Item -ItemType Directory -Force -Path $Script:StateDir | Out-Null
    $state        = Get-RollerState
    if (-not (Get-RollerEnabled -State $state)) {
        Write-RollerLog -Message 'roller disabled; skipping tick'
        return
    }
    $userDisabled = Get-UserDisabled -State $state
    $now          = (Get-Date).ToUniversalTime()

    foreach ($name in @('claude', 'codex')) {
        if ($userDisabled -contains $name) { continue }

        $installs = Get-CliInstallations $name
        if ($installs.Count -eq 0) { continue }

        $cliState = Get-CliState -State $state -Name $name

        # Window state
        $timestamps = if ($name -eq 'claude') { Get-ClaudeUserTimestamps } else { Get-CodexTimestamps }
        $start = Get-WindowStart -Timestamps $timestamps -Now $now
        if ($null -eq $start) {
            $end       = $now
            $statusMsg = 'no open window'
        } else {
            $end       = $start.AddMinutes($Script:WindowMinutes)
            $statusMsg = "$(Format-Duration ($end - $now)) left"
        }

        # Debounce
        $shouldPing = ($now -ge $end.AddSeconds(-$Script:PingLeadSec))
        if ($shouldPing -and (Test-IsoSec -Iso $cliState.last_ping_at -Now $now -MaxAgeMinutes $Script:DebounceMinutes)) {
            $shouldPing = $false
        }
        if (-not $shouldPing) {
            Write-RollerLog -Cli $name -Message $statusMsg
            continue
        }

        # Pick install
        $install = Select-NextInstall -Installs $installs -CliState $cliState -Now $now
        if (-not $install) {
            $install = $installs[0]
            Write-RollerLog -Cli $name -Message "$statusMsg  -> all sources flagged; retrying $($install.source)" -Warn
        } else {
            Write-RollerLog -Cli $name -Message "$statusMsg  -> rolling via $($install.source)..."
        }

        # For claude: reuse the dedicated roller chat session to avoid per-ping
        # session overhead and keep pings in one conversation thread.
        $sessionId = $cliState.ping_session_id
        if ($name -eq 'claude' -and $sessionId) {
            # --resume <id> spliced in after the binary and before -p ping
            $pingCmd = $install.baseCmd + @('--resume', $sessionId, '-p', 'ping')
        } else {
            $pingCmd = $install.cmd
        }

        $cliState.last_ping_at = $now.ToString('o')
        $timeout = $Script:PingTimeoutSec[$name]
        if (-not $timeout) { $timeout = 30 }

        $pingStartedAt = (Get-Date).ToUniversalTime()
        $r = Invoke-CliPing -Cmd $pingCmd -TimeoutSec $timeout

        if ($r.ok) {
            Write-RollerLog -Cli $name -Message "OK rolled via $($install.source)"
            Record-PingSuccess -CliState $cliState -Source $install.source

            # Capture / update session ID for claude so next ping resumes the
            # same conversation thread.
            if ($name -eq 'claude') {
                $sid = Get-LatestClaudeSessionId -AfterUtc $pingStartedAt
                if ($sid) {
                    $cliState | Add-Member -NotePropertyName 'ping_session_id' -NotePropertyValue $sid -Force
                }
            }
        } else {
            # If we were trying to resume a session and it failed, the session
            # may have expired. Clear the stored ID so the next ping starts
            # fresh rather than re-failing on the same dead session.
            if ($name -eq 'claude' -and $sessionId -and $r.reason -match 'exit [0-9]+|not found') {
                Write-RollerLog -Cli $name -Message "session may be expired - clearing ID, will start fresh next ping" -Warn
                $cliState | Add-Member -NotePropertyName 'ping_session_id' -NotePropertyValue $null -Force
                # Don't count as a source failure - blame the stale session, not the install.
            } else {
                Record-PingFailure -CliState $cliState -Source $install.source -Now $now
                $failEntry = $cliState.source_failures.PSObject.Properties[$install.source].Value
                $count = if ($failEntry) { [int]$failEntry.count } else { 1 }
                if ($count -ge $Script:MaxConsecFailures) {
                    Write-RollerLog -Cli $name -Message "FAIL $($install.source): $($r.reason) (will try next source on subsequent tick)" -Warn
                } else {
                    Write-RollerLog -Cli $name -Message "FAIL $($install.source): $($r.reason) (attempt $count/$($Script:MaxConsecFailures))" -Warn
                }
                Show-Toast -Title "Ping failed: $name via $($install.source)" -Body $r.reason
            }
        }
    }
    Save-RollerState -State $state
}

# ---------- status ----------

function Get-RollerJsonStatus {
    $now = (Get-Date).ToUniversalTime()
    $state = Get-RollerState
    $userDisabled = Get-UserDisabled -State $state
    $task = $null
    $taskState = $null
    $installed = $false
    try {
        $task = Get-ScheduledTask -TaskName $Script:TaskName -ErrorAction SilentlyContinue
        if ($task) {
            $installed = $true
            $taskState = [string]$task.State
        }
    } catch {}

    $clients = @()
    foreach ($name in @('claude', 'codex')) {
        $client = [ordered]@{
            name          = $name
            userDisabled  = ($userDisabled -contains $name)
            installed     = $false
            sources       = @()
            activeSource  = $null
            windowStart   = $null
            windowEnd     = $null
            secondsLeft   = $null
            pingInSeconds = $null
            lastPingAt    = $null
            error         = $null
        }

        try {
            if ($client.userDisabled) {
                $clients += [pscustomobject]$client
                continue
            }

            $installs = @(Get-CliInstallations $name)
            $client.installed = ($installs.Count -gt 0)
            $client.sources = @($installs | ForEach-Object { $_.source })

            $cliState = Get-CliState -State $state -Name $name
            if ($cliState.PSObject.Properties['last_ping_at']) {
                $client.lastPingAt = $cliState.last_ping_at
            }

            if ($installs.Count -gt 0) {
                $activeCandidates = @(Select-NextInstall -Installs $installs -CliState $cliState -Now $now)
                $active = if ($activeCandidates.Count -gt 0) { $activeCandidates[0] } else { $installs[0] }
                $client.activeSource = $active.source

                $timestamps = if ($name -eq 'claude') { Get-ClaudeUserTimestamps } else { Get-CodexTimestamps }
                $start = Get-WindowStart -Timestamps $timestamps -Now $now
                if ($null -ne $start) {
                    $end = $start.AddMinutes($Script:WindowMinutes)
                    $left = $end - $now
                    $pingIn = $left - [timespan]::FromSeconds($Script:PingLeadSec)

                    $client.windowStart = $start.ToString('o')
                    $client.windowEnd = $end.ToString('o')
                    $client.secondsLeft = [int][math]::Floor($left.TotalSeconds)
                    $client.pingInSeconds = [int][math]::Floor($pingIn.TotalSeconds)
                }
            }
        } catch {
            $client.error = $_.Exception.Message
        }

        $clients += [pscustomobject]$client
    }

    return [pscustomobject]@{
        taskName        = $Script:TaskName
        installed       = $installed
        enabled         = (Get-RollerEnabled -State $state)
        taskState       = $taskState
        windowMinutes   = $Script:WindowMinutes
        pingLeadSeconds = $Script:PingLeadSec
        stateDir        = $Script:StateDir
        logFile         = $Script:LogFile
        checkedAt       = $now.ToString('o')
        clients         = $clients
    }
}

function Show-JsonStatus {
    Get-RollerJsonStatus | ConvertTo-Json -Depth 8 -Compress
}

function Show-Status {
    $now   = (Get-Date).ToUniversalTime()
    $state = Get-RollerState
    $userDisabled = Get-UserDisabled -State $state

    Write-Host ""
    Write-Host ("Roller: {0}" -f $(if (Get-RollerEnabled -State $state) { 'enabled' } else { 'disabled' })) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Detected installations:" -ForegroundColor Cyan
    foreach ($name in @('claude','codex')) {
        if ($userDisabled -contains $name) {
            Write-Host ("  - {0,-6}  disabled (user said not installed - re-run -Install to reset)" -f $name) -ForegroundColor DarkGray
            continue
        }
        $installs = Get-CliInstallations $name
        if ($installs.Count -eq 0) {
            Write-Host ("  ? {0,-6}  (none found)" -f $name) -ForegroundColor Yellow
            continue
        }
        $cliState = Get-CliState -State $state -Name $name
        $active   = Select-NextInstall -Installs $installs -CliState $cliState -Now $now
        foreach ($install in $installs) {
            $isActive         = $active -and ($install.source -eq $active.source)
            $failEntry        = $cliState.source_failures.PSObject.Properties[$install.source].Value
            $isFailingSkipped = $failEntry -and ([int]$failEntry.count -ge $Script:MaxConsecFailures) -and `
                (Test-IsoSec -Iso $failEntry.last_failure_at -Now $now -MaxAgeMinutes $Script:FailureRetryMinutes)
            $tag    = if ($isFailingSkipped) { 'x' } elseif ($isActive) { '*' } else { ' ' }
            $suffix = if ($failEntry) { "  (failures: $([int]$failEntry.count))" } else { '' }
            Write-Host ("  {0} {1,-6}  {2,-32}  {3}{4}" -f $tag, $name, $install.source, $install.exe, $suffix)
        }
        $sessionId = $cliState.ping_session_id
        if ($sessionId -and $name -eq 'claude') {
            Write-Host ("      roller session: $sessionId") -ForegroundColor DarkGray
        }
    }
    $claudeDesktop = Find-ClaudeDesktopMsix
    if ($claudeDesktop) {
        Write-Host ("    {0,-6}  {1,-32}  {2}" -f 'claude', 'Claude Desktop (Store/MSIX)', $claudeDesktop) -ForegroundColor DarkGray
        Write-Host "    (GUI app - not pingable; quota shared with Claude Code CLI)" -ForegroundColor DarkGray
    }
    Write-Host "  Legend: * active source   x skipped (retry after $($Script:FailureRetryMinutes)m)   - disabled by user" -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "Window state:" -ForegroundColor Cyan
    foreach ($name in @('claude','codex')) {
        if ($userDisabled -contains $name) {
            Write-Host ("  {0,-6}  disabled" -f $name) -ForegroundColor DarkGray
            continue
        }
        $installs = Get-CliInstallations $name
        if ($installs.Count -eq 0) {
            Write-Host ("  {0,-6}  no install found (skipped)" -f $name)
            continue
        }
        $cliState = Get-CliState -State $state -Name $name
        $active   = Select-NextInstall -Installs $installs -CliState $cliState -Now $now
        if (-not $active) { $active = $installs[0] }
        $timestamps = if ($name -eq 'claude') { Get-ClaudeUserTimestamps } else { Get-CodexTimestamps }
        $start = Get-WindowStart -Timestamps $timestamps -Now $now
        if ($null -eq $start) {
            Write-Host ("  {0,-6}  window closed (no recent activity)  via {1}" -f $name, $active.source)
            continue
        }
        $end    = $start.AddMinutes($Script:WindowMinutes)
        $left   = $end - $now
        $pingIn = $left - [timespan]::FromSeconds($Script:PingLeadSec)
        Write-Host ("  {0,-6}  {1} left  (ping in {2})  via {3}" -f $name, (Format-Duration $left), (Format-Duration $pingIn), $active.source)
    }
    Write-Host ""
}

# ---------- install ----------

function Invoke-Install {
    # Step 0: scan for CLIs and ask about anything not found.
    # This runs before the task is registered so user_disabled is persisted
    # into state.json before the first tick fires.
    Write-Host "Scanning for CLI installations..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $Script:StateDir | Out-Null
    $state        = Get-RollerState     # preserve existing user_disabled if reinstalling
    $userDisabled = @(Get-UserDisabled -State $state)

    foreach ($name in @('claude', 'codex')) {
        if ($userDisabled -contains $name) {
            Write-Host ("  {0,-6}  already disabled (skipped)" -f $name) -ForegroundColor DarkGray
            continue
        }
        $installs = Get-CliInstallations $name
        if ($installs.Count -gt 0) {
            Write-Host ("  {0,-6}  found {1} install(s) - using: {2}" -f $name, $installs.Count, $installs[0].source) -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host ("  {0,-6}  not found automatically." -f $name) -ForegroundColor Yellow
            $ans = 'n'
            try { $ans = (Read-Host "         Is $name installed on this machine? [y/N]").Trim().ToLower() } catch {}
            if ($ans -eq 'y' -or $ans -eq 'yes') {
                Write-Host "         Make sure '$name' is on your PATH and re-run install." -ForegroundColor Yellow
            } else {
                Write-Host "         OK - $name will be ignored." -ForegroundColor DarkGray
                $userDisabled += $name
            }
        }
    }

    # Persist updated user_disabled choice.
    $state | Add-Member -NotePropertyName 'user_disabled' -NotePropertyValue $userDisabled -Force
    Save-RollerState -State $state

    Write-Host ""
    Write-Host "[1/3] Installing script to $Script:StateDir..." -ForegroundColor Cyan
    if ($PSCommandPath -and (Test-Path $PSCommandPath) -and ($PSCommandPath -ne $Script:InstalledScript)) {
        Copy-Item -Path $PSCommandPath -Destination $Script:InstalledScript -Force
        Write-Host "      copied from $PSCommandPath"
    } elseif (-not (Test-Path $Script:InstalledScript)) {
        Write-Host "      downloading from $Script:RawScriptUrl"
        Invoke-WebRequest -Uri $Script:RawScriptUrl -OutFile $Script:InstalledScript -UseBasicParsing
    } else {
        Write-Host "      already in place at $Script:InstalledScript"
    }

    Write-Host "[2/3] Registering scheduled task..." -ForegroundColor Cyan
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Script:InstalledScript`" -Tick"
    $logonTrigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $repeatTemplate = New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes 1) `
        -RepetitionDuration ([timespan]::FromDays(3650))
    $logonTrigger.Repetition = $repeatTemplate.Repetition
    $settings  = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

    if (Get-ScheduledTask -TaskName $Script:TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $Script:TaskName -Confirm:$false
    }
    Register-ScheduledTask -TaskName $Script:TaskName -Action $action -Trigger $logonTrigger `
        -Settings $settings -Principal $principal `
        -Description 'Keeps Claude Code and Codex 5h usage windows rolling.' | Out-Null

    Write-Host "[3/3] Starting task..." -ForegroundColor Cyan
    Start-ScheduledTask -TaskName $Script:TaskName

    Write-Host ""
    Write-Host "Done. Set and forget." -ForegroundColor Green
    Write-Host "  status:    powershell -File `"$Script:InstalledScript`" -Status"
    Write-Host "  log:       $Script:LogFile"
    Write-Host "  uninstall: powershell -File `"$Script:InstalledScript`" -Uninstall"
}

# ---------- uninstall ----------

function Invoke-Uninstall {
    if (Get-ScheduledTask -TaskName $Script:TaskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $Script:TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $Script:TaskName -Confirm:$false
        Write-Host "Removed scheduled task '$Script:TaskName'." -ForegroundColor Green
    } else {
        Write-Host "Task '$Script:TaskName' not found."
    }
    Write-Host "State/logs at $Script:StateDir left intact - delete that folder for a clean removal."
}

function Invoke-Enable {
    New-Item -ItemType Directory -Force -Path $Script:StateDir | Out-Null
    $state = Get-RollerState
    Set-RollerEnabled -State $state -Enabled $true | Out-Null
    Save-RollerState -State $state

    if (Get-ScheduledTask -TaskName $Script:TaskName -ErrorAction SilentlyContinue) {
        Enable-ScheduledTask -TaskName $Script:TaskName | Out-Null
        Start-ScheduledTask -TaskName $Script:TaskName -ErrorAction SilentlyContinue
        Write-Host "Enabled roller and started scheduled task '$Script:TaskName'." -ForegroundColor Green
    } else {
        Write-Host "Enabled roller. Scheduled task '$Script:TaskName' is not installed." -ForegroundColor Yellow
    }
}

function Invoke-Disable {
    New-Item -ItemType Directory -Force -Path $Script:StateDir | Out-Null
    $state = Get-RollerState
    Set-RollerEnabled -State $state -Enabled $false | Out-Null
    Save-RollerState -State $state

    if (Get-ScheduledTask -TaskName $Script:TaskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $Script:TaskName -ErrorAction SilentlyContinue
        Disable-ScheduledTask -TaskName $Script:TaskName | Out-Null
        Write-Host "Disabled roller and stopped scheduled task '$Script:TaskName'." -ForegroundColor Green
    } else {
        Write-Host "Disabled roller. Scheduled task '$Script:TaskName' is not installed." -ForegroundColor Yellow
    }
}

# ---------- dispatch ----------

if     ($Tick)       { Invoke-Tick }
elseif ($Status)     { Show-Status }
elseif ($JsonStatus) { Show-JsonStatus }
elseif ($Enable)     { Invoke-Enable }
elseif ($Disable)    { Invoke-Disable }
elseif ($Uninstall)  { Invoke-Uninstall }
else                 { Invoke-Install }
