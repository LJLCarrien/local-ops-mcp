$ErrorActionPreference = 'Stop'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('local-ops-config-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null

function Assert-True($Condition, $Message) {
    if (-not $Condition) { throw $Message }
}

try {
    $fixtureScripts = Join-Path $fixtureRoot 'scripts'
    New-Item -ItemType Directory -Path $fixtureScripts | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'first-time-setup.ps1') -Destination $fixtureScripts
    Set-Content -LiteralPath (Join-Path $fixtureScripts 'tunnel-client.ps1') -Value 'function Resolve-TunnelClient { return "unused-test-client" }'
    Set-Content -LiteralPath (Join-Path $fixtureScripts 'setup-tunnel.ps1') -Value 'param($ConfigPath, $TunnelClient); $global:LocalOpsTestInitializedConfig = $ConfigPath; $global:LASTEXITCODE = 0'
    Set-Content -LiteralPath (Join-Path $fixtureScripts 'run-tunnel.ps1') -Value 'throw "The test must not start a real tunnel."'

    function Test-Wizard([bool]$External) {
        $targetConfig = if ($External) { Join-Path $fixtureRoot 'external config\personal.psd1' } else { Join-Path $fixtureRoot 'config\local-ops.psd1' }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetConfig) | Out-Null
        $escapedWorkspace = $fixtureRoot.Replace("'", "''")
        $escapedNode = (Join-Path $env:SystemRoot 'System32\cmd.exe').Replace("'", "''")
        Set-Content -LiteralPath $targetConfig -Value "@{ WorkspaceRoot = '$escapedWorkspace'; TunnelId = 'tunnel_test'; Profile = 'config-test'; NodePath = '$escapedNode' }"
        function Read-Host([string]$Prompt) {
            if ($Prompt -like 'Start Local Ops Tunnel*') { return 'n' }
            return ''
        }
        $global:LocalOpsTestInitializedConfig = $null
        $parameters = @{}
        if ($External) { $parameters.ConfigPath = $targetConfig }
        & (Join-Path $fixtureScripts 'first-time-setup.ps1') @parameters
        Assert-True ($global:LocalOpsTestInitializedConfig -eq $targetConfig) 'Wizard did not initialize with the selected config.'
        $saved = Import-PowerShellDataFile -LiteralPath $targetConfig
        Assert-True ($saved.Profile -eq 'config-test') 'Wizard did not read the existing selected config.'
        if ($External) {
            Assert-True (-not (Test-Path (Join-Path $fixtureRoot 'config\local-ops.psd1'))) 'External config unexpectedly created a default config.'
        }
        return $targetConfig
    }

    $externalConfig = Test-Wizard $true
    $null = Test-Wizard $false

    foreach ($choice in @('1', '2', '3')) {
        & {
            param($MenuChoice, $SelectedConfig, $LauncherPath)
            function Read-Host { return $MenuChoice }
            function Start-Process($FilePath, $ArgumentList, $WindowStyle) {
                $global:LocalOpsTestLaunchedArguments = $ArgumentList
            }
            $global:LocalOpsTestLaunchedArguments = $null
            & $LauncherPath -ConfigPath $SelectedConfig
            $arguments = $global:LocalOpsTestLaunchedArguments
            $index = [array]::IndexOf($arguments, '-ConfigPath')
            Assert-True ($index -ge 0) 'Launcher omitted ConfigPath.'
            Assert-True ($arguments[$index + 1] -eq ('"' + $SelectedConfig + '"')) 'Launcher did not preserve a config path containing spaces.'
            Assert-True (($arguments -contains '-Reinitialize') -eq ($MenuChoice -eq '3')) 'Launcher changed reinitialization behavior.'
        } $choice $externalConfig (Join-Path $PSScriptRoot 'launcher.ps1')
    }
    Write-Host 'Config path tests passed (default wizard, external wizard, all launcher actions).'
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedFixture.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path.' }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
