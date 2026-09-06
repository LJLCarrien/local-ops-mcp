param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\local-ops.psd1')
)

$ErrorActionPreference = 'Stop'

$configurationPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigPath)
$zhFirstTimeSetup = -join [char[]](0x9996, 0x6B21, 0x914D, 0x7F6E)
$zhStart = -join [char[]](0x542F, 0x52A8)
$zhReinitialize = -join [char[]](0x91CD, 0x65B0, 0x521D, 0x59CB, 0x5316, 0x914D, 0x7F6E)
$zhQuit = -join [char[]](0x9000, 0x51FA)
$zhChooseAction = -join [char[]](0x8BF7, 0x9009, 0x62E9, 0x64CD, 0x4F5C)

function Start-LocalOpsPowerShell {
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$ScriptName,

        [string[]]$ScriptArguments = @()
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Local Ops script was not found: '$scriptPath'"
    }

    $quotedScriptPath = '"' + $scriptPath + '"'
    $argumentList = @(
        '-NoLogo',
        '-NoProfile',
        '-NoExit',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $quotedScriptPath,
        '-ConfigPath',
        ('"' + $configurationPath + '"')
    ) + $ScriptArguments
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WindowStyle Normal

    Write-Host "Started: $Title" -ForegroundColor Green
}

function Confirm-LocalConfiguration {
    if (Test-Path -LiteralPath $configurationPath -PathType Leaf) {
        return $true
    }

    Write-Host ''
    Write-Host 'Local configuration was not found:' -ForegroundColor Yellow
    Write-Host "  $configurationPath"
    Write-Host 'Run Local-Ops.bat again and choose 1 for first-time setup.'
    return $false
}

Write-Host ''
Write-Host 'Local Ops' -ForegroundColor Cyan
Write-Host '========='
Write-Host "[1] $zhFirstTimeSetup / First-time setup"
Write-Host "[2] $zhStart Tunnel / Start Tunnel"
Write-Host "[3] $zhReinitialize / Reinitialize configuration"
Write-Host "[Q] $zhQuit / Quit"
Write-Host ''

$selection = (Read-Host "$zhChooseAction / Choose an action [1/2/3/Q]").Trim()

switch ($selection) {
    '1' {
        Start-LocalOpsPowerShell -Title 'First-time setup' -ScriptName 'first-time-setup.ps1'
    }
    '2' {
        if (Confirm-LocalConfiguration) {
            Start-LocalOpsPowerShell -Title 'Start Tunnel' -ScriptName 'run-tunnel.ps1'
        }
    }
    '3' {
        if (Confirm-LocalConfiguration) {
            Start-LocalOpsPowerShell -Title 'Reinitialize configuration' -ScriptName 'first-time-setup.ps1' -ScriptArguments '-Reinitialize'
        }
    }
    { $_ -in @('q', 'Q') } {
        exit 0
    }
    default {
        Write-Host 'Invalid selection.' -ForegroundColor Yellow
        exit 1
    }
}
