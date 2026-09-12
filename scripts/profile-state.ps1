. (Join-Path $PSScriptRoot 'tunnel-client.ps1')

function Get-LocalOpsDefaultProfile {
    param([string]$ConfigPath, [string]$TunnelId = '')
    $name = [IO.Path]::GetFileNameWithoutExtension($ConfigPath).ToLowerInvariant()
    $slug = ($name -replace '[^a-z0-9_-]', '-').Trim('-')
    if (-not $slug) { $slug = 'workspace' }
    if ($slug -cnotmatch '^[a-z0-9]') { $slug = 'workspace-' + $slug }
    if ($slug.Length -gt 40) { $slug = $slug.Substring(0,40) }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($name + '|' + $TunnelId)))).Replace('-', '').Substring(0,8).ToLowerInvariant() }
    finally { $sha.Dispose() }
    return "$slug-$hash"
}

function Test-LocalOpsHealthListenAddress {
    param([string]$Address)

    # The health endpoint exposes the local diagnostics UI. Keep it on loopback
    # rather than accepting :PORT (which makes it reachable on every interface).
    if ($Address -cnotmatch '^127\.0\.0\.1:(\d{1,5})$') { return $false }
    $port = 0
    return [int]::TryParse($Matches[1], [ref]$port) -and $port -ge 0 -and $port -le 65535
}

function Get-LocalOpsProfileConflicts {
    param([string]$ConfigPath, [string]$Profile, [string]$TunnelId)
    $absolute = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigPath)
    $directory = Split-Path -Parent $absolute
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { return }
    foreach ($file in (Get-ChildItem -LiteralPath $directory -File -Filter '*.psd1')) {
        if ($file.FullName -eq $absolute -or $file.Name -like '*.example.psd1') { continue }
        try { $other = Import-PowerShellDataFile -LiteralPath $file.FullName } catch { continue }
        $otherProfile = if ($other.Profile) { [string]$other.Profile } else { 'local-ops' }
        if ($otherProfile -eq $Profile -and $other.TunnelId -and $other.TunnelId -cne $TunnelId) { $file.Name }
    }
}

function Get-LocalOpsProfileState {
    param([string]$Profile, [string]$TunnelId, [string]$TunnelClient)
    $state = [pscustomobject]@{ Code = 'Unknown'; Path = $null; Message = 'Cannot verify profile binding.' }
    if ($Profile -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$' -or $TunnelId -cnotmatch '^tunnel_[A-Za-z0-9]+$') {
        $state.Code = 'Invalid'; $state.Message = 'Set a valid Profile and TunnelId in this configuration.'; return $state
    }
    if ($env:TUNNEL_CLIENT_CONFIG -or $env:TUNNEL_CLIENT_PROFILE_FILE) {
        $state.Message = 'Clear TUNNEL_CLIENT_CONFIG / TUNNEL_CLIENT_PROFILE_FILE overrides before using this menu.'; return $state
    }
    try {
        $client = Resolve-TunnelClient -ExplicitPath $TunnelClient
        $json = & $client profiles list --json 2>$null
        if ($LASTEXITCODE -ne 0) { return $state }
        $raw = ($json -join "`n").Trim()
        if (-not $raw -or -not $raw.StartsWith('[')) { return $state }
        $decoded = ConvertFrom-Json -InputObject $raw
        $profiles = @($decoded)
        foreach ($item in $profiles) {
            if (-not $item.name -or -not $item.path -or -not [IO.Path]::IsPathRooted([string]$item.path)) { return $state }
        }
        $matches = @($profiles | Where-Object { $_.name -eq $Profile })
        if ($matches.Count -eq 0) {
            $state.Code = 'Missing'; $state.Message = 'Needs initialization.'; return $state
        }
        if ($matches.Count -ne 1 -or -not [IO.Path]::IsPathRooted([string]$matches[0].path)) { return $state }
        $state.Path = [string]$matches[0].path
        $text = [IO.File]::ReadAllText($state.Path)
        # Read only the simple literal binding written by tunnel-client init.
        # Unsupported YAML (flow maps, aliases, merges, duplicate blocks) is never treated as ready.
        $blocks = [regex]::Matches($text, '(?m)^control_plane:[ \t]*(?:#[^\r\n]*)?\r?$')
        $allBlocks = [regex]::Matches($text, '(?m)^["'']?control_plane["'']?\s*:')
        if ($blocks.Count -ne 1 -or $allBlocks.Count -ne 1 -or $text -match '(?m)^---[ \t]*\r?$|^\.\.\.[ \t]*\r?$|^\s*<<\s*:') { return $state }
        $tail = $text.Substring($blocks[0].Index + $blocks[0].Length)
        $next = [regex]::Match($tail, '(?m)^[^\s#][^\r\n]*')
        if ($next.Success) { $tail = $tail.Substring(0, $next.Index) }
        if ($tail -match '(?m)^\s*<<\s*:') { return $state }
        $ids = [regex]::Matches($tail, '(?m)^  tunnel_id:[ \t]*(?:"(tunnel_[A-Za-z0-9]+)"|''(tunnel_[A-Za-z0-9]+)''|(tunnel_[A-Za-z0-9]+))[ \t]*(?:#[^\r\n]*)?\r?$')
        $keys = [regex]::Matches($tail, '(?m)^\s*["'']?tunnel_id["'']?\s*:')
        if ($ids.Count -ne 1 -or $keys.Count -ne 1) { return $state }
        $binding = ($ids[0].Groups[1].Value + $ids[0].Groups[2].Value + $ids[0].Groups[3].Value)
        if ($binding -ceq $TunnelId) { $state.Code = 'Ready'; $state.Message = 'Ready (binding verified).' }
        else { $state.Code = 'Mismatch'; $state.Message = 'Profile is bound to another Tunnel. Edit configuration and choose an independent Profile.' }
    } catch { return $state }
    return $state
}

function Get-LocalOpsConfigurationState {
    param([string]$ConfigPath, [string]$TunnelClient)
    $result = [pscustomobject]@{ Code = 'Invalid'; Message = 'Invalid or missing configuration.'; Workspace = ''; Profile = ''; Path = $null }
    try {
        $config = Import-PowerShellDataFile -LiteralPath $ConfigPath
        $result.Workspace = [string]$config.WorkspaceRoot
        $result.Profile = if ($config.Profile) { [string]$config.Profile } else { 'local-ops' }
        if ($config.TunnelId -cnotmatch '^tunnel_[A-Za-z0-9]+$') { $result.Message = 'Set a valid TunnelId.'; return $result }
        if ($config.ContainsKey('HealthListenAddr') -and -not (Test-LocalOpsHealthListenAddress -Address ([string]$config.HealthListenAddr))) {
            $result.Message = 'Set HealthListenAddr to a loopback address such as 127.0.0.1:0 or 127.0.0.1:8081.'; return $result
        }
        if (-not $result.Workspace -or -not (Test-Path -LiteralPath $result.Workspace -PathType Container)) {
            $result.Message = 'Workspace directory does not exist.'; return $result
        }
        $conflicts = @(Get-LocalOpsProfileConflicts -ConfigPath $ConfigPath -Profile $result.Profile -TunnelId $config.TunnelId)
        if ($conflicts.Count) { $result.Code = 'Conflict'; $result.Message = 'Profile shared by different Tunnels: ' + ($conflicts -join ', '); return $result }
        $binding = Get-LocalOpsProfileState -Profile $result.Profile -TunnelId $config.TunnelId -TunnelClient $TunnelClient
        $result.Code = $binding.Code; $result.Message = $binding.Message; $result.Path = $binding.Path
    } catch { Write-Verbose $_.Exception.Message }
    return $result
}
