<#
.SYNOPSIS
    Claudex 5h Window Roller — keep Claude Code & Codex CLI 5-hour usage
    windows continuously rolling on Windows.

.DESCRIPTION
    Single PowerShell script. No Python. No third-party modules.

    Once per minute (via Scheduled Task) it reads each CLI's local log,
    figures out when the current 5h window opened, and ~90s before the
    window would close fires a tiny `ping` so the next 5h block opens
    seamlessly. Shows a Windows toast if a ping fails.

.PARAMETER Install
    Drop the script into %USERPROFILE%\.claudex-5h-window-roller, register
    the scheduled task, start it. Default action.

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
    [Parameter(ParameterSetName='Tick')]      [switch]$Tick
)

$ErrorActionPreference = 'Stop'

# ---------- constants ----------

$Script:WindowMinutes  = 300        # 5h
$Script:PingLeadSec    = 90
$Script:PingTimeoutSec = 30
$Script:PauseRegex     = '(rate limit|usage limit|unauthorized|quota exceeded|exceeded your)'
$Script:DebounceMinutes = 4

$Script:TaskName       = 'Claudex5hWindowRoller'
$Script:StateDir       = Join-Path $env:USERPROFILE '.claudex-5h-window-roller'
$Script:LogFile        = Join-Path $Script:StateDir 'service.log'
$Script:StateFile      = Join-Path $Script:StateDir 'state.json'
$Script:InstalledScript = Join-Path $Script:StateDir 'claudex-roller.ps1'

$Script:ClaudeProjects = Join-Path $env:USERPROFILE '.claude\projects'
$Script:CodexHistory   = Join-Path $env:USERPROFILE '.codex\history.jsonl'

$Script:RawScriptUrl = 'https://raw.githubusercontent.com/rriordan/Claudex-5h-Window-Roller/main/claudex-roller.ps1'

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

# ---------- log readers ----------

function Get-ClaudeUserTimestamps {
    if (-not (Test-Path $Script:ClaudeProjects)) { return ,@() }
    $cutoff = (Get-Date).ToUniversalTime().AddHours(-24)
    $result = New-Object System.Collections.Generic.List[datetime]
    Get-ChildItem -Path $Script:ClaudeProjects -Filter *.jsonl -Recurse -ErrorAction SilentlyContinue |
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
    return ,($result | Sort-Object)
}

function Get-CodexTimestamps {
    if (-not (Test-Path $Script:CodexHistory)) { return ,@() }
    $cutoff = (Get-Date).ToUniversalTime().AddHours(-24)
    $result = New-Object System.Collections.Generic.List[datetime]
    Get-Content -Path $Script:CodexHistory -Tail 1000 -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not $_) { return }
        $row = $null
        try { $row = $_ | ConvertFrom-Json -ErrorAction Stop } catch { return }
        if ($null -eq $row.ts) { return }
        try {
            $dt = [datetime]::new(1970,1,1,0,0,0,[DateTimeKind]::Utc).AddSeconds([long]$row.ts)
        } catch { return }
        if ($dt -ge $cutoff) { [void]$result.Add($dt) }
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

# ---------- executable resolution ----------

function Resolve-CliExecutable {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    if ($Name -eq 'claude') {
        $base = Join-Path $env:APPDATA 'Claude\claude-code'
        if (Test-Path $base) {
            $latest = Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending | Select-Object -First 1
            if ($latest) {
                $exe = Join-Path $latest.FullName 'claude.exe'
                if (Test-Path $exe) { return $exe }
            }
        }
    }
    return $null
}

# ---------- ping ----------

function Invoke-CliPing {
    param([string[]]$Cmd)
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $procArgs = if ($Cmd.Count -gt 1) { $Cmd[1..($Cmd.Count - 1)] } else { @() }
        $proc = Start-Process -FilePath $Cmd[0] -ArgumentList $procArgs `
            -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile `
            -WindowStyle Hidden -PassThru
        if (-not $proc.WaitForExit($Script:PingTimeoutSec * 1000)) {
            try { $proc.Kill() } catch {}
            return @{ ok = $false; reason = "timeout after $($Script:PingTimeoutSec)s" }
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
    } catch {
        # Toasts are best-effort; never fail a tick on a missing toast.
    }
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
    $State | ConvertTo-Json | Set-Content -Path $Script:StateFile -Encoding utf8
}

# ---------- format ----------

function Format-Duration {
    param([timespan]$Td)
    $totalSec = [int]$Td.TotalSeconds
    if ($totalSec -lt 0) {
        $absMin = [math]::Floor([math]::Abs($Td.TotalSeconds) / 60)
        return "-${absMin}m"
    }
    $h = [int][math]::Floor($totalSec / 3600)
    $m = [int][math]::Floor(($totalSec % 3600) / 60)
    if ($h -gt 0) { return ('{0}h{1:D2}m' -f $h, $m) }
    return "${m}m"
}

# ---------- cli catalog ----------

function Get-Clis {
    $catalog = @(
        @{ name = 'claude'; defaultCmd = @('claude', '-p', 'ping');                            log = 'claude' }
        @{ name = 'codex';  defaultCmd = @('codex',  'exec', '--skip-git-repo-check', 'ping'); log = 'codex'  }
    )
    foreach ($def in $catalog) {
        $resolved = Resolve-CliExecutable $def.name
        if ($resolved) {
            $cmd = @($resolved) + $def.defaultCmd[1..($def.defaultCmd.Count - 1)]
        } else {
            $cmd = $def.defaultCmd
        }
        [pscustomobject]@{
            name      = $def.name
            cmd       = $cmd
            log       = $def.log
            installed = [bool]$resolved
        }
    }
}

# ---------- modes ----------

function Invoke-Tick {
    New-Item -ItemType Directory -Force -Path $Script:StateDir | Out-Null
    $state = Get-RollerState
    $now = (Get-Date).ToUniversalTime()
    foreach ($cli in (Get-Clis)) {
        if (-not $cli.installed) { continue }
        $timestamps = if ($cli.log -eq 'claude') { Get-ClaudeUserTimestamps } else { Get-CodexTimestamps }
        $start = Get-WindowStart -Timestamps $timestamps -Now $now
        if ($null -eq $start) {
            $end = $now
            $statusMsg = 'no open window'
        } else {
            $end = $start.AddMinutes($Script:WindowMinutes)
            $statusMsg = "$(Format-Duration ($end - $now)) left"
        }
        $shouldPing = ($now -ge $end.AddSeconds(-$Script:PingLeadSec))
        $lastKey = "$($cli.name)_last_ping"
        $lastPing = $state.PSObject.Properties[$lastKey].Value
        if ($shouldPing -and $lastPing) {
            try {
                $lastDt = [datetime]::Parse($lastPing, $null,
                    [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
                    [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                if (($now - $lastDt).TotalMinutes -lt $Script:DebounceMinutes) {
                    $shouldPing = $false
                }
            } catch {}
        }
        if (-not $shouldPing) {
            Write-RollerLog -Cli $cli.name -Message $statusMsg
            continue
        }
        Write-RollerLog -Cli $cli.name -Message "$statusMsg  -> rolling..."
        $state | Add-Member -NotePropertyName $lastKey -NotePropertyValue $now.ToString('o') -Force
        $r = Invoke-CliPing -Cmd $cli.cmd
        if ($r.ok) {
            Write-RollerLog -Cli $cli.name -Message 'OK rolled'
        } else {
            Write-RollerLog -Cli $cli.name -Message "FAIL paused: $($r.reason)" -Warn
            Show-Toast -Title "Window paused: $($cli.name)" -Body $r.reason
        }
    }
    Save-RollerState -State $state
}

function Show-Status {
    $now = (Get-Date).ToUniversalTime()
    foreach ($cli in (Get-Clis)) {
        if (-not $cli.installed) {
            Write-Host ("{0,-6}  not installed (skipped)" -f $cli.name)
            continue
        }
        $timestamps = if ($cli.log -eq 'claude') { Get-ClaudeUserTimestamps } else { Get-CodexTimestamps }
        $start = Get-WindowStart -Timestamps $timestamps -Now $now
        if ($null -eq $start) {
            Write-Host ("{0,-6}  window closed (no recent activity)" -f $cli.name)
            continue
        }
        $end = $start.AddMinutes($Script:WindowMinutes)
        $left = $end - $now
        $pingIn = $left - [timespan]::FromSeconds($Script:PingLeadSec)
        Write-Host ("{0,-6}  {1} left  (ping in {2})  ->  {3}" -f $cli.name, (Format-Duration $left), (Format-Duration $pingIn), $cli.cmd[0])
    }
}

function Invoke-Install {
    Write-Host "[1/3] Installing script to $Script:StateDir..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $Script:StateDir | Out-Null
    if ($PSCommandPath -and (Test-Path $PSCommandPath) -and ($PSCommandPath -ne $Script:InstalledScript)) {
        Copy-Item -Path $PSCommandPath -Destination $Script:InstalledScript -Force
        Write-Host "      copied from $PSCommandPath"
    } elseif (-not (Test-Path $Script:InstalledScript)) {
        Write-Host "      downloading from $Script:RawScriptUrl"
        Invoke-WebRequest -Uri $Script:RawScriptUrl -OutFile $Script:InstalledScript -UseBasicParsing
    }

    Write-Host "[2/3] Registering scheduled task..." -ForegroundColor Cyan
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Script:InstalledScript`" -Tick"
    $logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $repeatTemplate = New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes 1) `
        -RepetitionDuration ([timespan]::FromDays(3650))
    $logonTrigger.Repetition = $repeatTemplate.Repetition
    $settings = New-ScheduledTaskSettingsSet `
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

function Invoke-Uninstall {
    if (Get-ScheduledTask -TaskName $Script:TaskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $Script:TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $Script:TaskName -Confirm:$false
        Write-Host "Removed scheduled task '$Script:TaskName'." -ForegroundColor Green
    } else {
        Write-Host "Task '$Script:TaskName' not found."
    }
    Write-Host "State/logs at $Script:StateDir left intact — delete that folder for a clean removal."
}

# ---------- dispatch ----------

if     ($Tick)      { Invoke-Tick }
elseif ($Status)    { Show-Status }
elseif ($Uninstall) { Invoke-Uninstall }
else                { Invoke-Install }
