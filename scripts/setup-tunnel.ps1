param(
    [string]$TunnelId,
    [string]$WorkspaceRoot,
    [string]$Profile,
    [string]$ProxyUrl,
    [string]$TunnelClient,
    [string]$Node,
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\local-ops.psd1')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tunnel-client.ps1')
. (Join-Path $PSScriptRoot 'profile-state.ps1')
$config = @{}
if (Test-Path -LiteralPath $ConfigPath) {
    $config = Import-PowerShellDataFile -LiteralPath $ConfigPath
}

if (-not $PSBoundParameters.ContainsKey('TunnelId')) { $TunnelId = $config.TunnelId }
if (-not $PSBoundParameters.ContainsKey('WorkspaceRoot')) { $WorkspaceRoot = $config.WorkspaceRoot }
if (-not $PSBoundParameters.ContainsKey('Profile')) { $Profile = $config.Profile }
if (-not $PSBoundParameters.ContainsKey('ProxyUrl')) { $ProxyUrl = $config.ProxyUrl }
if (-not $PSBoundParameters.ContainsKey('Node')) { $Node = $config.NodePath }

if (-not $Node) {
    $bundledNode = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
    if (Test-Path -LiteralPath $bundledNode -PathType Leaf) {
        $Node = $bundledNode
    } else {
        $pathNode = Get-Command node.exe -ErrorAction SilentlyContinue
        if ($pathNode) { $Node = $pathNode.Source }
    }
}

if ($TunnelId -notmatch '^tunnel_[A-Za-z0-9]+$') {
    throw "TunnelId is missing or invalid. Set TunnelId in '$ConfigPath' or pass -TunnelId."
}
if (-not $WorkspaceRoot) { throw "WorkspaceRoot is missing. Set it in '$ConfigPath' or pass -WorkspaceRoot." }
if (-not $Profile) { $Profile = 'local-ops' }
if (-not $Node) { throw "Node.js was not found. Install Node.js or Codex, or set NodePath in '$ConfigPath'." }
if ($Node -match '\s') {
    throw "NodePath contains spaces and this tunnel-client version cannot parse it safely: '$Node'. Install Codex or set NodePath in '$ConfigPath' to a Node.js executable located in a path without spaces."
}

$server = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\server.mjs')).Path
$workspace = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$client = Resolve-TunnelClient -ExplicitPath $TunnelClient
$nodeExe = (Resolve-Path -LiteralPath $Node).Path

$conflicts = @(Get-LocalOpsProfileConflicts -ConfigPath $ConfigPath -Profile $Profile -TunnelId $TunnelId)
if ($conflicts.Count) { throw "Profile is shared by different Tunnels ($($conflicts -join ', ')). Edit configuration and choose an independent Profile." }
$binding = Get-LocalOpsProfileState -Profile $Profile -TunnelId $TunnelId -TunnelClient $client
if ($binding.Code -notin @('Ready','Missing')) { throw $binding.Message }
if ($binding.Path) {
    $backup = $binding.Path + '.' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff') + '.' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.bak'
    Copy-Item -LiteralPath $binding.Path -Destination $backup -ErrorAction Stop
    Write-Host "Tunnel profile backup: $backup"
}

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
$nodeCommandPath = $nodeExe.Replace('\', '/')
$serverCommandPath = $server.Replace('\', '/')
$mcpCommand = '{0} {1}' -f $nodeCommandPath, $serverCommandPath

& $client init --sample sample_mcp_stdio_local --profile $Profile --tunnel-id $TunnelId --mcp-command $mcpCommand --force
if ($LASTEXITCODE -ne 0) { throw "tunnel-client init failed with exit code $LASTEXITCODE" }

$initialized = Get-LocalOpsProfileState -Profile $Profile -TunnelId $TunnelId -TunnelClient $client
if ($initialized.Code -ne 'Ready') { throw 'Initialization did not produce the expected Tunnel binding. Check the client profile before starting.' }
& $client doctor --profile-file $initialized.Path --control-plane.tunnel-id $TunnelId --explain
if ($LASTEXITCODE -ne 0) { throw "tunnel-client doctor failed with exit code $LASTEXITCODE" }

Write-Host "Tunnel profile '$Profile' is configured for workspace '$workspace' using '$ConfigPath'."
