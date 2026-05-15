# Removes the Claudex5hWindowRoller scheduled task. Leaves logs/state behind
# at %USERPROFILE%\.claudex-5h-window-roller\ — delete that folder yourself if
# you want a clean removal.

$ErrorActionPreference = "Stop"
$TaskName = "Claudex5hWindowRoller"

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed scheduled task '$TaskName'." -ForegroundColor Green
} else {
    Write-Host "Task '$TaskName' not found."
}
