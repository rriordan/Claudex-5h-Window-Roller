# Registers Claudex5hWindowRoller as a Scheduled Task that runs at logon.
# Does NOT require an elevated prompt — the task is registered for the current
# user only, with Limited run level.

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script    = Join-Path $ScriptDir "claudex_roller.py"

# Prefer pythonw.exe (no console window) — fall back to python.exe.
$Pythonw = (Get-Command pythonw.exe -ErrorAction SilentlyContinue).Source
if (-not $Pythonw) {
    $Pythonw = (Get-Command python.exe -ErrorAction Stop).Source
    Write-Warning "pythonw.exe not found; using python.exe (a console window will appear)."
}

$TaskName = "Claudex5hWindowRoller"

$Action   = New-ScheduledTaskAction -Execute $Pythonw -Argument "`"$Script`""
$Trigger  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask `
    -TaskName   $TaskName `
    -Action     $Action `
    -Trigger    $Trigger `
    -Settings   $Settings `
    -Principal  $Principal `
    -Description "Keeps Claude Code and Codex 5-hour usage windows rolling." | Out-Null

Write-Host "Registered scheduled task '$TaskName'."
Write-Host "Start it now with:  Start-ScheduledTask -TaskName $TaskName"
