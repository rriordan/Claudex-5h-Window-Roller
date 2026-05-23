$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptPath = Join-Path $repoRoot 'claudex-roller.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)

if ($errors.Count -gt 0) {
    throw "Failed to parse claudex-roller.ps1: $($errors[0].Message)"
}

$installFunction = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Invoke-Install'
}, $true)

if ($null -eq $installFunction) {
    throw 'Invoke-Install function not found'
}

$requiredCommands = @(
    'Register-ScheduledTask',
    'Start-ScheduledTask'
)

foreach ($commandName in $requiredCommands) {
    $commands = $installFunction.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq $commandName
    }, $true)

    if ($commands.Count -eq 0) {
        throw "$commandName not found in Invoke-Install"
    }

    foreach ($command in $commands) {
        $hasStop = $false
        for ($i = 0; $i -lt $command.CommandElements.Count; $i++) {
            $element = $command.CommandElements[$i]
            if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and
                $element.ParameterName -eq 'ErrorAction') {
                $next = $command.CommandElements[$i + 1]
                if ($null -ne $next -and $next.ToString() -eq 'Stop') {
                    $hasStop = $true
                }
            }
        }

        if (-not $hasStop) {
            throw "$commandName in Invoke-Install must use -ErrorAction Stop"
        }
    }
}

Write-Host 'installErrorHandling smoke test passed'
