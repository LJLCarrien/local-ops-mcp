param(
    [switch]$Reinitialize,
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\local-ops.psd1')
)

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$configPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigPath)
$configDir = Split-Path -Parent $configPath
$setupScript = Join-Path $PSScriptRoot 'setup-tunnel.ps1'
$runScript = Join-Path $PSScriptRoot 'run-tunnel.ps1'
. (Join-Path $PSScriptRoot 'tunnel-client.ps1')

function Read-RequiredValue {
    param(
        [string]$Prompt,
        [string]$DefaultValue
    )

    while ($true) {
        $label = if ($DefaultValue) { "$Prompt [$DefaultValue]" } else { $Prompt }
        $value = Read-Host $label
        if (-not $value) { $value = $DefaultValue }
        if ($value) { return $value.Trim() }
        Write-Host 'A value is required.' -ForegroundColor Yellow
    }
}

function Escape-Psd1String {
    param([string]$Value)
    return $Value.Replace("'", "''")
}

function Install-TunnelClientInteractively {
    $downloadUrl = 'https://platform.openai.com/settings/organization/tunnels'
    $answer = Read-Host 'Open the official OpenAI page and install tunnel-client now? [Y/n]'
    if ($answer -and $answer -notmatch '^[Yy]') {
        throw 'tunnel-client is required. Install it and run this setup again.'
    }

    Write-Host "Opening the official OpenAI Tunnels page: $downloadUrl" -ForegroundColor Cyan
    Start-Process $downloadUrl
    Read-Host 'Download and extract tunnel-client.exe, then press Enter to select it' | Out-Null

    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = 'Select the downloaded tunnel-client.exe'
    $dialog.Filter = 'OpenAI tunnel-client (tunnel-client.exe)|tunnel-client.exe|Executable files (*.exe)|*.exe'
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        throw 'No tunnel-client executable was selected. Run this setup again after downloading it.'
    }

    $selectedPath = $dialog.FileName
    if ([System.IO.Path]::GetFileName($selectedPath) -ne 'tunnel-client.exe') {
        throw "The selected file must be named tunnel-client.exe: '$selectedPath'"
    }

    $localBin = Join-Path $projectRoot 'bin'
    $localClient = Join-Path $localBin 'tunnel-client.exe'
    New-Item -ItemType Directory -Force -Path $localBin | Out-Null
    Copy-Item -LiteralPath $selectedPath -Destination $localClient -Force
    Write-Host "tunnel-client was saved locally at '$localClient'." -ForegroundColor Green
    return (Resolve-Path -LiteralPath $localClient).Path
}

Write-Host ''
$modeLabel = if ($Reinitialize) { 'reconfiguration' } else { 'first-time setup' }
Write-Host "Local Ops $modeLabel" -ForegroundColor Cyan
Write-Host 'This wizard updates the Git-ignored local config, initializes the tunnel, and can start it.'
Write-Host 'The Runtime API key will not be written to disk.' -ForegroundColor Green
Write-Host ''

$tunnelClient = try {
    Resolve-TunnelClient
} catch {
    Write-Host 'The official OpenAI tunnel-client is not installed on this computer.' -ForegroundColor Yellow
    Install-TunnelClientInteractively
}
Write-Host "Official tunnel-client: $tunnelClient" -ForegroundColor Green

$existing = @{}
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    $existing = Import-PowerShellDataFile -LiteralPath $configPath
    Write-Host "Existing local config found at '$configPath'. Press Enter to keep each current value." -ForegroundColor Yellow
}

$workspaceRoot = Read-RequiredValue -Prompt 'Workspace directory that ChatGPT may access' -DefaultValue $existing.WorkspaceRoot
if (-not (Test-Path -LiteralPath $workspaceRoot -PathType Container)) {
    throw "Workspace directory does not exist: '$workspaceRoot'"
}
$workspaceRoot = (Resolve-Path -LiteralPath $workspaceRoot).Path

while ($true) {
    $tunnelId = Read-RequiredValue -Prompt 'OpenAI Tunnel ID' -DefaultValue $existing.TunnelId
    if ($tunnelId -match '^tunnel_[A-Za-z0-9]+$') { break }
    Write-Host 'Tunnel ID must start with tunnel_ and contain only letters and numbers after it.' -ForegroundColor Yellow
}

$defaultProxyPort = ''
if ($existing.ProxyUrl -match '^http://127\.0\.0\.1:(\d+)$') {
    $defaultProxyPort = $Matches[1]
}
$proxyPort = Read-Host $(if ($defaultProxyPort) { "Local HTTP or mixed proxy port; leave blank to keep $defaultProxyPort" } else { 'Local HTTP or mixed proxy port; leave blank for no proxy' })
if (-not $proxyPort) { $proxyPort = $defaultProxyPort }
if ($proxyPort -and $proxyPort -notmatch '^\d{1,5}$') {
    throw "Proxy port must be blank or a number: '$proxyPort'"
}
$proxyUrl = if ($proxyPort) { "http://127.0.0.1:$proxyPort" } else { '' }

$profile = Read-RequiredValue -Prompt 'Local tunnel profile name' -DefaultValue $(if ($existing.Profile) { $existing.Profile } else { 'local-ops' })

$nodePath = $existing.NodePath
if ($nodePath -and -not (Test-Path -LiteralPath $nodePath -PathType Leaf)) {
    Write-Host "Configured Node.js was not found; automatic detection will be used instead: '$nodePath'" -ForegroundColor Yellow
    $nodePath = ''
}

$bundledNode = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
$detectedNode = if ($nodePath) { $nodePath } elseif (Test-Path -LiteralPath $bundledNode -PathType Leaf) { $bundledNode } else { (Get-Command node.exe -ErrorAction SilentlyContinue).Source }
if (-not $detectedNode) {
    throw 'Node.js was not found. Install Node.js or Codex before continuing.'
}
if ($detectedNode -match '\s') {
    throw "The detected Node.js path contains spaces and cannot be used safely by this tunnel-client version: '$detectedNode'. Install Codex, or place Node.js in a path without spaces and set NodePath in config/local-ops.psd1."
}

New-Item -ItemType Directory -Force -Path $configDir | Out-Null
$configText = @"
@{
    WorkspaceRoot = '$(Escape-Psd1String $workspaceRoot)'
    TunnelId     = '$(Escape-Psd1String $tunnelId)'
    ProxyUrl     = '$(Escape-Psd1String $proxyUrl)'
    Profile      = '$(Escape-Psd1String $profile)'
    NodePath     = '$(Escape-Psd1String $nodePath)'
    GitRead      = `$true
    GitWrite     = `$true
    GitRemote    = `$false
    GitFetch     = `$true
    GitPull      = `$false
    GitPush      = `$false
}
"@
Set-Content -LiteralPath $configPath -Value $configText -Encoding UTF8

Write-Host ''
Write-Host "Local config saved to '$configPath'." -ForegroundColor Green
Write-Host "Workspace: $workspaceRoot"
Write-Host "Tunnel:    $tunnelId"
Write-Host "Proxy:     $(if ($proxyUrl) { $proxyUrl } else { '(direct connection)' })"
Write-Host "Profile:   $profile"
Write-Host ''
Write-Host 'Starting tunnel initialization. Paste the Runtime API key when prompted.' -ForegroundColor Cyan

& $setupScript -ConfigPath $configPath -TunnelClient $tunnelClient
if ($LASTEXITCODE -ne 0) { throw "Tunnel initialization failed with exit code $LASTEXITCODE" }

Write-Host ''
Write-Host "Local Ops $modeLabel completed successfully." -ForegroundColor Green
$startNow = Read-Host 'Start Local Ops Tunnel now? [Y/n]'
if (-not $startNow -or $startNow -match '^[Yy]') {
    Write-Host 'Starting Local Ops Tunnel. Keep this window open while ChatGPT uses local files.' -ForegroundColor Cyan
    & $runScript -ConfigPath $configPath -TunnelClient $tunnelClient
}
