# One-click installer for Claudex-5h-Window-Roller.
#
# Two modes:
#   1. Run from a cloned repo:    .\install.ps1
#   2. Run directly from GitHub:  irm https://raw.githubusercontent.com/rriordan/Claudex-5h-Window-Roller/main/install.ps1 | iex
#
# No admin required. Installs Python deps (user scope), drops claudex_roller.py
# into %USERPROFILE%\.claudex-5h-window-roller\, registers a Scheduled Task
# that runs at every logon, and starts it.

$ErrorActionPreference = "Stop"

$TaskName  = "Claudex5hWindowRoller"
$InstallDir = Join-Path $env:USERPROFILE ".claudex-5h-window-roller"
$ScriptPath = Join-Path $InstallDir "claudex_roller.py"
$RawScriptUrl = "https://raw.githubusercontent.com/rriordan/Claudex-5h-Window-Roller/main/claudex_roller.py"

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

Write-Host "[1/4] Locating claudex_roller.py..." -ForegroundColor Cyan
$LocalScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "claudex_roller.py" -ErrorAction SilentlyContinue
if ($LocalScript -and (Test-Path $LocalScript)) {
    Copy-Item -Path $LocalScript -Destination $ScriptPath -Force
    Write-Host "  copied from repo: $LocalScript"
} else {
    Write-Host "  downloading from GitHub..."
    Invoke-WebRequest -Uri $RawScriptUrl -OutFile $ScriptPath -UseBasicParsing
}

Write-Host "[2/4] Installing Python dependencies (winotify)..." -ForegroundColor Cyan
python -m pip install --user --quiet winotify

Write-Host "[3/4] Registering scheduled task..." -ForegroundColor Cyan
$Pythonw = (Get-Command pythonw.exe -ErrorAction SilentlyContinue).Source
if (-not $Pythonw) {
    $Pythonw = (Get-Command python.exe -ErrorAction Stop).Source
    Write-Warning "pythonw.exe not found; using python.exe (a console window may appear)."
}

$Action   = New-ScheduledTaskAction -Execute $Pythonw -Argument "`"$ScriptPath`""
$Trigger  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger `
    -Settings $Settings -Principal $Principal `
    -Description "Keeps Claude Code and Codex 5h usage windows rolling." | Out-Null

Write-Host "[4/4] Starting task..." -ForegroundColor Cyan
Start-ScheduledTask -TaskName $TaskName

Write-Host ""
Write-Host "Done. Set and forget." -ForegroundColor Green
Write-Host "  status:   python `"$ScriptPath`" --status"
Write-Host "  log:      $InstallDir\service.log"
Write-Host "  uninstall: irm https://raw.githubusercontent.com/rriordan/Claudex-5h-Window-Roller/main/uninstall.ps1 | iex"
