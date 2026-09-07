function Save-LocalOpsConfiguration {
    param([string]$Path, [hashtable]$Updates)
    $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $exists = Test-Path -LiteralPath $Path -PathType Leaf
    $text = if ($exists) { [IO.File]::ReadAllText($Path) } else { "@{`n}`n" }
    $originalText = $text
    $existing = if ($exists) { Import-PowerShellDataFile -LiteralPath $Path } else { @{} }
    $defaults = @{ GitRead = $true; GitWrite = $true; GitRemote = $false; GitFetch = $true; GitPull = $false; GitPush = $false }
    $values = $Updates.Clone()
    foreach ($key in $defaults.Keys) {
        if (-not $existing.ContainsKey($key) -and -not $values.ContainsKey($key)) { $values[$key] = $defaults[$key] }
    }
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Cannot update an invalid configuration.' }
    $table = $ast.Find({ param($node) $node -is [Management.Automation.Language.HashtableAst] }, $false)
    if (-not $table) { throw 'Configuration must contain a data hashtable.' }
    $changes = @()
    $insertions = @()
    foreach ($key in ($values.Keys | Sort-Object)) {
        $value = $values[$key]
        $literal = if ($value -is [bool]) { '$' + $value.ToString().ToLowerInvariant() } else { "'" + ([string]$value).Replace("'", "''") + "'" }
        $pair = @($table.KeyValuePairs | Where-Object { $_.Item1.SafeGetValue() -eq $key })
        if ($pair.Count -gt 0) {
            $extent = $pair[0].Item2.Extent
            $changes += @{ Start = $extent.StartOffset; Length = $extent.EndOffset - $extent.StartOffset; Text = $literal }
        } else {
            $insertions += "    $key = $literal"
        }
    }
    if ($insertions.Count) { $changes += @{ Start = $table.Extent.EndOffset - 1; Length = 0; Text = "`n" + ($insertions -join "`n") + "`n" } }
    foreach ($change in ($changes | Sort-Object { $_.Start } -Descending)) {
        $text = $text.Remove($change.Start, $change.Length).Insert($change.Start, $change.Text)
    }
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, $text, [Text.UTF8Encoding]::new($true))
        # Import only accepts .psd1; use the parser's safe evaluator for the staged data.
        $validated = [scriptblock]::Create($text).Ast.EndBlock.Statements[0].PipelineElements[0].Expression.SafeGetValue()
        if ($validated -isnot [hashtable]) { throw 'Updated configuration is not a data hashtable.' }
        if ($exists) {
            if ([IO.File]::ReadAllText($Path) -cne $originalText) { throw 'Configuration changed while editing. Reload it and try again.' }
            $backup = $Path + '.' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff') + '.' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.bak'
            Copy-Item -LiteralPath $Path -Destination $backup -ErrorAction Stop
            Write-Host "Configuration backup: $backup"
        } elseif (Test-Path -LiteralPath $Path) {
            throw 'Configuration was created by another process. Reload it and try again.'
        }
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}
