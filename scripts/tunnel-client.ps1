function Resolve-TunnelClient {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) {
            throw "The specified tunnel-client executable was not found: '$ExplicitPath'"
        }
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    $command = Get-Command tunnel-client.exe -ErrorAction SilentlyContinue
    if (-not $command) {
        $command = Get-Command tunnel-client -ErrorAction SilentlyContinue
    }
    if ($command) { return $command.Source }

    $legacyPath = Join-Path $PSScriptRoot '..\bin\tunnel-client.exe'
    if (Test-Path -LiteralPath $legacyPath -PathType Leaf) {
        Write-Warning "Using the legacy local copy at '$legacyPath'. Install the official OpenAI tunnel-client on PATH when convenient."
        return (Resolve-Path -LiteralPath $legacyPath).Path
    }

    throw @'
The official OpenAI tunnel-client was not found.
Download it from https://platform.openai.com/settings/organization/tunnels or
https://github.com/openai/tunnel-client/releases/latest, install it on PATH,
then run this command again. You may also pass -TunnelClient with its full path.
'@
}
