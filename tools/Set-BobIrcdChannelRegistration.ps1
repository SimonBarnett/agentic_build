# Idempotent Ergo ircd.yaml patch for FR #327 channel registration.
# Does NOT start/stop services. Operator runs against ionos after review.
# Public account registration stays off. No secrets in git.
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ErgoRoot = 'C:\ai\ergo',
    [string]$ConfPath,
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
if (-not $ConfPath) { $ConfPath = Join-Path $ErgoRoot 'ircd.yaml' }
if (-not (Test-Path -LiteralPath $ConfPath)) { throw "missing conf $ConfPath" }

function Set-BobIrcdYamlRegistration {
    param([string]$Text)
    # Line-oriented: force channels.registration.enabled=true and accounts.registration.enabled=false.
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($ln in ($Text -split "`r?`n", -1)) { [void]$lines.Add($ln) }

    function Find-BlockEnabledIndex {
        param([string]$ParentKey)
        $parent = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match ('^\s*{0}:\s*$' -f [regex]::Escape($ParentKey))) { $parent = $i; break }
        }
        if ($parent -lt 0) { return $null }
        $reg = -1
        for ($i = $parent + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^[^\s#]' ) { break }
            if ($lines[$i] -match '^\s{2,}registration:\s*$') { $reg = $i; break }
        }
        if ($reg -lt 0) {
            return @{ Parent = $parent; Reg = -1; Enabled = -1 }
        }
        $en = -1
        for ($i = $reg + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s{2,}\S' -and $lines[$i] -notmatch 'enabled:') { break }
            if ($lines[$i] -match '^\s+enabled:\s*') { $en = $i; break }
        }
        return @{ Parent = $parent; Reg = $reg; Enabled = $en }
    }

    function Ensure-Reg {
        param([string]$ParentKey, [string]$EnabledValue)
        $info = Find-BlockEnabledIndex -ParentKey $ParentKey
        if (-not $info) {
            [void]$lines.Add('')
            [void]$lines.Add("${ParentKey}:")
            [void]$lines.Add('    registration:')
            [void]$lines.Add("        enabled: $EnabledValue")
            return
        }
        if ($info.Reg -lt 0) {
            $insertAt = $info.Parent + 1
            $lines.Insert($insertAt, '    registration:')
            $lines.Insert($insertAt + 1, "        enabled: $EnabledValue")
            return
        }
        if ($info.Enabled -ge 0) {
            $indent = if ($lines[$info.Enabled] -match '^(\s*)') { $Matches[1] } else { '        ' }
            $lines[$info.Enabled] = "${indent}enabled: $EnabledValue"
        }
        else {
            $lines.Insert($info.Reg + 1, "        enabled: $EnabledValue")
        }
    }

    Ensure-Reg -ParentKey 'channels' -EnabledValue 'true'
    Ensure-Reg -ParentKey 'accounts' -EnabledValue 'false'
    return ($lines -join "`n")
}

$before = Get-Content -LiteralPath $ConfPath -Raw -Encoding UTF8
$after = Set-BobIrcdYamlRegistration -Text $before
# normalise newlines for compare
$bNorm = ($before -replace "`r`n", "`n").TrimEnd() + "`n"
$aNorm = ($after -replace "`r`n", "`n").TrimEnd() + "`n"
if ($bNorm -eq $aNorm) {
    Write-Output "unchanged: $ConfPath (channels.registration already desired shape)"
    exit 0
}
if ($WhatIf) {
    Write-Output "would patch: $ConfPath"
    exit 0
}
$bak = "$ConfPath.bak-fr327-$(Get-Date -Format 'yyyyMMddHHmmss')"
Copy-Item -LiteralPath $ConfPath -Destination $bak -Force
[System.IO.File]::WriteAllText($ConfPath, $aNorm.Replace("`n", "`r`n"), (New-Object System.Text.UTF8Encoding $false))
Write-Output "patched: $ConfPath (backup $bak)"
Write-Output "NOTE: does not restart BobIrcd. Operator recycles after review. No live ionos change from CI."
