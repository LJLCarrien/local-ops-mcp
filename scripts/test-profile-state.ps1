$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'profile-state.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('local-ops-profile-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$savedEnvironment = @{}
foreach ($name in @('LOCAL_OPS_TEST_PROFILE_DIR','CONTROL_PLANE_API_KEY','TUNNEL_CLIENT_CONFIG','TUNNEL_CLIENT_PROFILE_FILE','LOCAL_OPS_ROOT','LOCAL_OPS_GIT_READ','LOCAL_OPS_GIT_WRITE','LOCAL_OPS_GIT_REMOTE','LOCAL_OPS_GIT_FETCH','LOCAL_OPS_GIT_PULL','LOCAL_OPS_GIT_PUSH','TUNNEL_CLIENT_HTTP_PROXY','CONTROL_PLANE_HTTP_PROXY')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
}
function Assert-True($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Write-Registry($Entries) { ConvertTo-Json -InputObject @($Entries) -Compress | Set-Content -LiteralPath (Join-Path $fixture 'registry.json') }
function Assert-Rejected([scriptblock]$Action) {
    $rejected = $false
    try { & $Action } catch { $rejected = $true }
    Assert-True $rejected 'Expected operation to be rejected.'
}
try {
    $env:LOCAL_OPS_TEST_PROFILE_DIR = $fixture
    $env:CONTROL_PLANE_API_KEY = 'test-only-placeholder'
    Remove-Item Env:TUNNEL_CLIENT_CONFIG,Env:TUNNEL_CLIENT_PROFILE_FILE -ErrorAction SilentlyContinue
    $fake = Join-Path $fixture 'fake-client.ps1'
    Set-Content -LiteralPath $fake -Value @'
$root = $env:LOCAL_OPS_TEST_PROFILE_DIR
function Value-After($Name) { $i = [array]::IndexOf($script:invocation, $Name); if ($i -lt 0) { throw "Missing $Name" }; return $script:invocation[$i+1] }
$script:invocation = @($args)
switch ($args[0]) {
    'profiles' { Get-Content -LiteralPath (Join-Path $root 'registry.json') -Raw }
    'init' {
        $profile = Value-After '--profile'; $id = Value-After '--tunnel-id'
        $yaml = Join-Path $root ($profile + '.yaml')
        Set-Content -LiteralPath $yaml -Value "control_plane:`n  tunnel_id: $id"
        $decoded = Get-Content -LiteralPath (Join-Path $root 'registry.json') -Raw | ConvertFrom-Json
        $items = @($decoded | Where-Object { $_.name -ne $profile })
        $items += @{ name = $profile; path = $yaml }
        ConvertTo-Json -InputObject @($items) -Compress | Set-Content -LiteralPath (Join-Path $root 'registry.json')
        Add-Content -LiteralPath (Join-Path $root 'initializations.txt') -Value $profile
    }
    'doctor' { }
    'run' { @{ args = @($args); workspace = $env:LOCAL_OPS_ROOT; write = $env:LOCAL_OPS_GIT_WRITE } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'run.json') }
    default { throw 'Unexpected fake client command.' }
}
$global:LASTEXITCODE = 0
'@
    Write-Registry @()
    Assert-True ((Get-LocalOpsProfileState -Profile 'test' -TunnelId 'tunnel_one' -TunnelClient $fake).Code -eq 'Missing') 'Missing profile was not detected.'
    $yaml = Join-Path $fixture 'test.yaml'
    Write-Registry @(@{ name = 'test'; path = $yaml })
    foreach ($literal in @('tunnel_one', '"tunnel_one"', "'tunnel_one' # comment")) {
        Set-Content -LiteralPath $yaml -Value "control_plane:`n  tunnel_id: $literal`nmcp:`n  commands: []"
        Assert-True ((Get-LocalOpsProfileState -Profile 'test' -TunnelId 'tunnel_one' -TunnelClient $fake).Code -eq 'Ready') 'Literal binding was not recognized.'
        Assert-True ((Get-LocalOpsProfileState -Profile 'test' -TunnelId 'tunnel_other' -TunnelClient $fake).Code -eq 'Mismatch') 'Wrong Tunnel was accepted.'
    }
    foreach ($unsupported in @(
        "control_plane:`n  tunnel_id: tunnel_one`n  tunnel_id: tunnel_other",
        "control_plane:`n  tunnel_id: tunnel_one`n  'tunnel_id': tunnel_other",
        "control_plane:`n  tunnel_id: tunnel_one`ncontrol_plane:`n  tunnel_id: tunnel_other",
        "control_plane: {tunnel_id: tunnel_one}",
        "control_plane:`n  <<: *shared`n  tunnel_id: tunnel_one",
        "---`ncontrol_plane:`n  tunnel_id: tunnel_one"
    )) {
        Set-Content -LiteralPath $yaml -Value $unsupported
        Assert-True ((Get-LocalOpsProfileState -Profile 'test' -TunnelId 'tunnel_one' -TunnelClient $fake).Code -eq 'Unknown') 'Ambiguous YAML was accepted.'
    }
    Set-Content -LiteralPath (Join-Path $fixture 'registry.json') -Value '{"error":"not a list"}'
    Assert-True ((Get-LocalOpsProfileState -Profile 'test' -TunnelId 'tunnel_one' -TunnelClient $fake).Code -eq 'Unknown') 'Unusable client output was accepted.'
    Write-Registry @(@{ name = 'test'; path = $yaml })
    Set-Content -LiteralPath $yaml -Value "control_plane:`n  tunnel_id: tunnel_one"
    Write-Registry @(@{ name = 'test'; path = $yaml }, @{ name = 'second'; path = $yaml })
    Assert-True ((Get-LocalOpsProfileState -Profile 'test' -TunnelId 'tunnel_one' -TunnelClient $fake).Code -eq 'Ready') 'Multiple profile entries were not decoded correctly.'
    $env:TUNNEL_CLIENT_CONFIG = 'override.yaml'
    Assert-True ((Get-LocalOpsProfileState -Profile 'test' -TunnelId 'tunnel_one' -TunnelClient $fake).Code -eq 'Unknown') 'Environment override was ignored.'
    Remove-Item Env:TUNNEL_CLIENT_CONFIG

    $configPath = Join-Path $fixture 'selected.psd1'
    $escaped = $fixture.Replace("'", "''")
    $node = (Join-Path $env:SystemRoot 'System32\cmd.exe').Replace("'", "''")
    Set-Content -LiteralPath $configPath -Value "@{ WorkspaceRoot = '$escaped'; Profile = 'test'; TunnelId = 'tunnel_one'; NodePath = '$node'; GitWrite = `$false }"
    $configHash = (Get-FileHash -LiteralPath $configPath).Hash
    Assert-True ((Get-LocalOpsConfigurationState -ConfigPath $configPath -TunnelClient $fake).Code -eq 'Ready') 'Configuration status was not ready.'
    & (Join-Path $PSScriptRoot 'run-tunnel.ps1') -ConfigPath $configPath -TunnelClient $fake
    $run = Get-Content -LiteralPath (Join-Path $fixture 'run.json') -Raw | ConvertFrom-Json
    Assert-True ($run.workspace -eq $fixture -and $run.write -eq 'false') 'Run lost selected workspace or permissions.'
    Assert-True (($run.args -contains $yaml) -and ($run.args -contains '--control-plane.tunnel-id') -and ($run.args -contains 'tunnel_one')) 'Run did not pin the verified binding.'
    Remove-Item -LiteralPath (Join-Path $fixture 'run.json')
    Set-Content -LiteralPath $yaml -Value "control_plane:`n  tunnel_id: tunnel_other"
    Assert-Rejected { & (Join-Path $PSScriptRoot 'run-tunnel.ps1') -ConfigPath $configPath -TunnelClient $fake }
    Assert-Rejected { & (Join-Path $PSScriptRoot 'setup-tunnel.ps1') -ConfigPath $configPath -TunnelClient $fake }
    Assert-True (-not (Test-Path (Join-Path $fixture 'run.json'))) 'Mismatched profile was run.'
    Assert-True (-not (Test-Path (Join-Path $fixture 'initializations.txt'))) 'Mismatched profile was overwritten.'

    Write-Registry @()
    & {
        function Read-Host { return 'n' }
        & (Join-Path $PSScriptRoot 'run-tunnel.ps1') -ConfigPath $configPath -TunnelClient $fake
    }
    Assert-True (-not (Test-Path (Join-Path $fixture 'run.json'))) 'Declined initialization still ran.'
    & {
        function Read-Host { return 'y' }
        & (Join-Path $PSScriptRoot 'run-tunnel.ps1') -ConfigPath $configPath -TunnelClient $fake
    }
    Assert-True (Test-Path (Join-Path $fixture 'run.json')) 'Accepted initialization did not run.'
    $yamlHash = (Get-FileHash -LiteralPath $yaml).Hash
    & (Join-Path $PSScriptRoot 'setup-tunnel.ps1') -ConfigPath $configPath -TunnelClient $fake
    $backups = @(Get-ChildItem -LiteralPath $fixture -Filter '*.yaml.*.bak')
    Assert-True ($backups.Count -eq 1 -and (Get-FileHash $backups[0].FullName).Hash -eq $yamlHash) 'Profile backup did not preserve original.'
    Assert-True ((Get-FileHash $configPath).Hash -eq $configHash) 'Initialization rewrote selected config.'

    Set-Content -LiteralPath (Join-Path $fixture 'other.psd1') -Value "@{ Profile = 'test'; TunnelId = 'tunnel_other' }"
    Assert-True ((Get-LocalOpsConfigurationState -ConfigPath $configPath -TunnelClient $fake).Code -eq 'Conflict') 'Shared Profile was not flagged.'
    Assert-Rejected { & (Join-Path $PSScriptRoot 'run-tunnel.ps1') -ConfigPath $configPath -TunnelClient $fake }
    Assert-Rejected { & (Join-Path $PSScriptRoot 'setup-tunnel.ps1') -ConfigPath $configPath -TunnelClient $fake }
    $defaultOne = Get-LocalOpsDefaultProfile -ConfigPath 'one.psd1'
    $defaultTwo = Get-LocalOpsDefaultProfile -ConfigPath 'two.psd1'
    Assert-True ($defaultOne -ne $defaultTwo -and $defaultOne -cmatch '^[a-z0-9][a-z0-9_-]{0,63}$') 'Default profiles are not distinct valid names.'
    Assert-True ((Get-LocalOpsDefaultProfile -ConfigPath '_workspace.psd1') -cmatch '^[a-z0-9][a-z0-9_-]{0,63}$') 'Leading underscore produced an invalid profile.'
    Assert-True ((Get-LocalOpsDefaultProfile -ConfigPath 'same.psd1' -TunnelId 'tunnel_one') -ne (Get-LocalOpsDefaultProfile -ConfigPath 'same.psd1' -TunnelId 'tunnel_two')) 'Different Tunnels got the same default profile.'
    Write-Host 'Profile state, startup guards, initialization, and backup tests passed.'
} finally {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name]) }
    $resolved = [IO.Path]::GetFullPath($fixture)
    $prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
