param(
    [string]$WorkspaceRoot,
    [string]$Profile,
    [string]$ProxyUrl,
    [string]$TunnelClient,
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\local-ops.psd1')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tunnel-client.ps1')
$config = @{}
if (Test-Path -LiteralPath $ConfigPath) {
    $config = Import-PowerShellDataFile -LiteralPath $ConfigPath
}

if (-not $PSBoundParameters.ContainsKey('WorkspaceRoot')) { $WorkspaceRoot = $config.WorkspaceRoot }
if (-not $PSBoundParameters.ContainsKey('Profile')) { $Profile = $config.Profile }
if (-not $PSBoundParameters.ContainsKey('ProxyUrl')) { $ProxyUrl = $config.ProxyUrl }

if (-not $WorkspaceRoot) { throw "WorkspaceRoot is missing. Set it in '$ConfigPath' or pass -WorkspaceRoot." }
if (-not $Profile) { $Profile = 'local-ops' }

$workspace = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$client = Resolve-TunnelClient -ExplicitPath $TunnelClient

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
& $client run --profile $Profile
exit $LASTEXITCODE
