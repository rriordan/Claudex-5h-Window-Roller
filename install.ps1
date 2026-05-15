# One-shot installer: pip install deps, register the Scheduled Task, start it.
# Run from a normal PowerShell prompt — no admin needed.

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "[1/3] Installing Python dependencies..." -ForegroundColor Cyan
python -m pip install --user -r (Join-Path $ScriptDir "requirements.txt")

Write-Host "[2/3] Registering scheduled task..." -ForegroundColor Cyan
& (Join-Path $ScriptDir "install_task.ps1")

Write-Host "[3/3] Starting task..." -ForegroundColor Cyan
Start-ScheduledTask -TaskName Claudex5hWindowRoller

Write-Host ""
Write-Host "Done. Check status anytime with:" -ForegroundColor Green
Write-Host "  python `"$(Join-Path $ScriptDir 'claudex_roller.py')`" --status"
Write-Host "Logs:"
Write-Host "  $env:USERPROFILE\.claudex-5h-window-roller\service.log"
