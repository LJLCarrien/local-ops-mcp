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
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'local-config.ps1') -Destination $fixtureScripts
    Set-Content -LiteralPath (Join-Path $fixtureScripts 'tunnel-client.ps1') -Value 'function Resolve-TunnelClient { return "unused-test-client" }'
    Set-Content -LiteralPath (Join-Path $fixtureScripts 'setup-tunnel.ps1') -Value 'param($ConfigPath, $TunnelClient); $global:LocalOpsTestInitializedConfig = $ConfigPath; $global:LASTEXITCODE = 0'
    Set-Content -LiteralPath (Join-Path $fixtureScripts 'run-tunnel.ps1') -Value 'throw "The test must not start a real tunnel."'

    function Test-Wizard([bool]$External) {
        $targetConfig = if ($External) { Join-Path $fixtureRoot 'external config\personal.psd1' } else { Join-Path $fixtureRoot 'config\local-ops.psd1' }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetConfig) | Out-Null
        $escapedWorkspace = $fixtureRoot.Replace("'", "''")
        $escapedNode = (Join-Path $env:SystemRoot 'System32\cmd.exe').Replace("'", "''")
        Set-Content -LiteralPath $targetConfig -Value "@{ WorkspaceRoot = '$escapedWorkspace'; TunnelId = 'tunnel_test'; Profile = 'config-test'; NodePath = '$escapedNode'; GitRead = `$false; GitWrite = `$false; GitRemote = `$true; GitFetch = `$false; GitPull = `$true; GitPush = `$true; ProxyUrl = 'https://proxy.example.invalid:443'; Extra = @{ Name = 'keep me' } } # Keep this comment"
        $originalHash = (Get-FileHash -LiteralPath $targetConfig).Hash
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
        Assert-True (-not $saved.GitRead -and -not $saved.GitWrite -and $saved.GitRemote -and -not $saved.GitFetch -and $saved.GitPull -and $saved.GitPush) 'Wizard reset Git permissions.'
        Assert-True ($saved.ProxyUrl -eq 'https://proxy.example.invalid:443') 'Wizard reset existing proxy URL.'
        Assert-True ($saved.Extra.Name -eq 'keep me') 'Wizard lost an unknown field.'
        Assert-True ((Get-Content -LiteralPath $targetConfig -Raw).Contains('# Keep this comment')) 'Wizard lost comments.'
        $backup = @(Get-ChildItem -LiteralPath (Split-Path $targetConfig) -Filter '*.bak')
        Assert-True ($backup.Count -eq 1 -and (Get-FileHash -LiteralPath $backup[0].FullName).Hash -eq $originalHash) 'Original backup is missing or changed.'
        if ($External) {
            Assert-True (-not (Test-Path (Join-Path $fixtureRoot 'config\local-ops.psd1'))) 'External config unexpectedly created a default config.'
        }
        return $targetConfig
    }

    $externalConfig = Test-Wizard $true
    $null = Test-Wizard $false

    & {
        function Read-Host { return '' }
        Set-Content -LiteralPath (Join-Path $fixtureScripts 'tunnel-client.ps1') -Value 'function Resolve-TunnelClient { throw "Edit-only mode must not need a client." }'
        $global:LocalOpsTestInitializedConfig = $null
        & (Join-Path $fixtureScripts 'first-time-setup.ps1') -ConfigPath $externalConfig -EditOnly
        Assert-True ($null -eq $global:LocalOpsTestInitializedConfig) 'Edit-only mode initialized a Tunnel.'
    }
    . (Join-Path $PSScriptRoot 'local-config.ps1')
    $newConfig = Join-Path $fixtureRoot 'new.psd1'
    Save-LocalOpsConfiguration -Path $newConfig -Updates @{ WorkspaceRoot = "folder's name"; Profile = 'new-profile' }
    $created = Import-PowerShellDataFile -LiteralPath $newConfig
    Assert-True ($created.WorkspaceRoot -eq "folder's name" -and $created.GitRead -and -not $created.GitRemote) 'New defaults or string escaping failed.'
    $invalidConfig = Join-Path $fixtureRoot 'invalid.psd1'
    Set-Content -LiteralPath $invalidConfig -Value '@{ broken = '
    $invalidHash = (Get-FileHash -LiteralPath $invalidConfig).Hash
    $rejected = $false
    try { Save-LocalOpsConfiguration -Path $invalidConfig -Updates @{ Profile = 'new' } } catch { $rejected = $true }
    Assert-True ($rejected -and (Get-FileHash -LiteralPath $invalidConfig).Hash -eq $invalidHash) 'Invalid config was overwritten.'

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
