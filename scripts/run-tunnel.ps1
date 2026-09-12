param(
    [string]$WorkspaceRoot,
    [string]$Profile,
    [string]$HealthListenAddr,
    [string]$ProxyUrl,
    [string]$TunnelClient,
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\local-ops.psd1')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tunnel-client.ps1')
. (Join-Path $PSScriptRoot 'profile-state.ps1')
$config = @{}
if (Test-Path -LiteralPath $ConfigPath) {
    $config = Import-PowerShellDataFile -LiteralPath $ConfigPath
}

if (-not $PSBoundParameters.ContainsKey('WorkspaceRoot')) { $WorkspaceRoot = $config.WorkspaceRoot }
if (-not $PSBoundParameters.ContainsKey('Profile')) { $Profile = $config.Profile }
if (-not $PSBoundParameters.ContainsKey('HealthListenAddr')) { $HealthListenAddr = $config.HealthListenAddr }
if (-not $PSBoundParameters.ContainsKey('ProxyUrl')) { $ProxyUrl = $config.ProxyUrl }

if (-not $WorkspaceRoot) { throw "WorkspaceRoot is missing. Set it in '$ConfigPath' or pass -WorkspaceRoot." }
if (-not $Profile) { $Profile = 'local-ops' }
if (-not $HealthListenAddr) { $HealthListenAddr = '127.0.0.1:8080' }
if (-not (Test-LocalOpsHealthListenAddress -Address $HealthListenAddr)) {
    throw "HealthListenAddr must be a loopback address such as 127.0.0.1:0 or 127.0.0.1:8081."
}

$workspace = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$client = Resolve-TunnelClient -ExplicitPath $TunnelClient

$conflicts = @(Get-LocalOpsProfileConflicts -ConfigPath $ConfigPath -Profile $Profile -TunnelId $config.TunnelId)
if ($conflicts.Count) { throw "Profile is shared by different Tunnels ($($conflicts -join ', ')). Use Edit configuration to choose an independent Profile." }
$binding = Get-LocalOpsProfileState -Profile $Profile -TunnelId $config.TunnelId -TunnelClient $client
if ($binding.Code -eq 'Missing') {
    $initialize = Read-Host 'This Profile needs initialization. Initialize the selected configuration now? [y/N]'
    if ($initialize -notmatch '^[Yy]$') { return }
    & (Join-Path $PSScriptRoot 'setup-tunnel.ps1') -ConfigPath $ConfigPath -WorkspaceRoot $WorkspaceRoot -Profile $Profile -ProxyUrl $ProxyUrl -TunnelClient $client
    $binding = Get-LocalOpsProfileState -Profile $Profile -TunnelId $config.TunnelId -TunnelClient $client
}
if ($binding.Code -ne 'Ready') { throw $binding.Message }

if (-not $env:CONTROL_PLANE_API_KEY) {
    $secureKey = Read-Host 'Runtime API key' -AsSecureString
    $keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    try {
        $env:CONTROL_PLANE_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer)
    }
}

$env:LOCAL_OPS_ROOT = $workspace
$env:LOCAL_OPS_GIT_READ = if ($null -eq $config.GitRead) { 'true' } else { $config.GitRead.ToString().ToLowerInvariant() }
$env:LOCAL_OPS_GIT_WRITE = if ($null -eq $config.GitWrite) { 'true' } else { $config.GitWrite.ToString().ToLowerInvariant() }
$env:LOCAL_OPS_GIT_REMOTE = if ($null -eq $config.GitRemote) { 'false' } else { $config.GitRemote.ToString().ToLowerInvariant() }
$env:LOCAL_OPS_GIT_FETCH = if ($null -eq $config.GitFetch) { 'true' } else { $config.GitFetch.ToString().ToLowerInvariant() }
$env:LOCAL_OPS_GIT_PULL = if ($null -eq $config.GitPull) { 'false' } else { $config.GitPull.ToString().ToLowerInvariant() }
$env:LOCAL_OPS_GIT_PUSH = if ($null -eq $config.GitPush) { 'false' } else { $config.GitPush.ToString().ToLowerInvariant() }
if ($ProxyUrl) {
    $env:TUNNEL_CLIENT_HTTP_PROXY = $ProxyUrl
    $env:CONTROL_PLANE_HTTP_PROXY = $ProxyUrl
} else {
    Remove-Item Env:TUNNEL_CLIENT_HTTP_PROXY -ErrorAction SilentlyContinue
    Remove-Item Env:CONTROL_PLANE_HTTP_PROXY -ErrorAction SilentlyContinue
}
& $client run --profile-file $binding.Path --control-plane.tunnel-id $config.TunnelId --health.listen-addr $HealthListenAddr
exit $LASTEXITCODE
