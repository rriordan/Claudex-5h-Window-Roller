$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$scriptPath = Join-Path $repoRoot 'claudex-roller.ps1'

$output = & $scriptPath -JsonStatus
$json = $output | ConvertFrom-Json

if ($null -eq $json.installed) { throw 'JsonStatus missing installed' }
if ($null -eq $json.enabled) { throw 'JsonStatus missing enabled' }
if ($null -eq $json.taskName) { throw 'JsonStatus missing taskName' }
if ($null -eq $json.windowMinutes) { throw 'JsonStatus missing windowMinutes' }
if ($null -eq $json.clients) { throw 'JsonStatus missing clients' }

foreach ($client in $json.clients) {
    if ($null -ne $client.activeSource -and $client.activeSource -is [array]) {
        throw "JsonStatus activeSource must be a scalar for $($client.name)"
    }
}

Write-Host 'jsonStatus smoke test passed'
