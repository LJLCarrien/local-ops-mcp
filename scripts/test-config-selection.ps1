$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('local-ops-selection-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
function Assert-True($Condition, $Message) {
    if (-not $Condition) { throw $Message }
}
function Test-Selection($DefaultPath, [string[]]$Answers, $ExpectedPath, [switch]$Reinitialize, [switch]$Cancelled) {
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    foreach ($answer in $Answers) { $queue.Enqueue($answer) }
    function Read-Host {
        if ($queue.Count -eq 0) { throw 'Unexpected prompt.' }
        return $queue.Dequeue()
    }
    function Start-Process($FilePath, $ArgumentList, $WindowStyle) {
        $global:LocalOpsSelectionTestArguments = $ArgumentList
    }
    $global:LocalOpsSelectionTestArguments = $null
    & (Join-Path $PSScriptRoot 'launcher.ps1') -ConfigPath $DefaultPath -SelectConfig
    Assert-True ($queue.Count -eq 0) 'Expected prompts were skipped.'
    $arguments = $global:LocalOpsSelectionTestArguments
    if ($Cancelled) {
        Assert-True ($null -eq $arguments) 'Cancel unexpectedly started a process.'
        return
    }
    $index = [array]::IndexOf($arguments, '-ConfigPath')
    Assert-True ($index -ge 0) 'No config path was passed.'
    Assert-True ($arguments[$index + 1] -eq ('"' + $ExpectedPath + '"')) 'Wrong selected config path.'
    Assert-True (($arguments -contains '-Reinitialize') -eq [bool]$Reinitialize) 'Wrong reinitialization mode.'
}
try {
    $first = Join-Path $fixture 'a.psd1'
    $second = Join-Path $fixture 'b workspace.psd1'
    Set-Content -LiteralPath $first -Value '@{}'
    Set-Content -LiteralPath $second -Value '@{}'
    Set-Content -LiteralPath (Join-Path $fixture 'aa.example.psd1') -Value '@{}'
    Set-Content -LiteralPath (Join-Path $fixture 'ab.txt') -Value 'not a configuration'
    $beforeFirst = (Get-FileHash -LiteralPath $first).Hash
    $beforeSecond = (Get-FileHash -LiteralPath $second).Hash
    foreach ($action in @('1', '2', '3')) {
        Test-Selection $first @('2', $action) $second -Reinitialize:($action -eq '3')
    }
    Test-Selection $first @('garbage', '0', '99', '2147483648', '2', '2') $second
    Test-Selection $first @('', '2') $first
    Test-Selection $first @('q') $null -Cancelled
    $missingDefault = Join-Path $fixture 'new.psd1'
    Test-Selection $missingDefault @('', '1') $missingDefault
    $emptyDefault = Join-Path $fixture 'empty\local-ops.psd1'
    Test-Selection $emptyDefault @('1') $emptyDefault
    New-Item -ItemType Directory -Path (Join-Path $fixture 'empty') | Out-Null
    Set-Content -LiteralPath (Join-Path $fixture 'empty\local-ops.example.psd1') -Value '@{}'
    Test-Selection $emptyDefault @('1') $emptyDefault
    Assert-True ((Get-FileHash -LiteralPath $first).Hash -eq $beforeFirst) 'First config was modified.'
    Assert-True ((Get-FileHash -LiteralPath $second).Hash -eq $beforeSecond) 'Second config was modified.'
    Write-Host 'Configuration selection tests passed.'
} finally {
    Remove-Variable -Name LocalOpsSelectionTestArguments -Scope Global -ErrorAction SilentlyContinue
    $resolved = [IO.Path]::GetFullPath($fixture)
    $prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
