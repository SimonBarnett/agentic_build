# Merge open PRs linked from MRB PASS-nits boards (retroactive cleanup).
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repo,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$here = $PSScriptRoot
if (-not $here) { $here = Split-Path $MyInvocation.MyCommand.Path }
. (Join-Path $here 'Bob-BuildLoop.ps1')
. (Join-Path $here 'Bob-Gh.ps1')

$gh = Get-BobGhExe
if (-not $gh) { throw 'gh.exe not found' }

$raw = & $gh issue list --repo $Repo --label mrb-pass --state all --limit 100 --json number,title,body 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "gh issue list failed: $raw" }
$issues = @(ConvertFrom-BobGhJsonList $raw)

$prUrls = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($i in $issues) {
    $u = Get-BobMrbPrUrlFromBody ([string]$i.body)
    if ($u) { [void]$prUrls.Add($u) }
}

$done = New-Object System.Collections.Generic.List[string]
foreach ($u in @($prUrls)) {
    $n = Get-BobGhPrNumberFromUrl $u
    if ($n -le 0) { continue }
    if (Test-BobGhPrIsMerged -Gh $gh -Repo $Repo -PrNumber $n) {
        [void]$done.Add(('skip merged PR #{0}' -f $n))
        continue
    }
    if ($WhatIf) {
        [void]$done.Add(('would merge PR #{0} ({1})' -f $n, $u))
        continue
    }
    $m = Invoke-BobGhMergePrIfOpen -Gh $gh -Repo $Repo -PrNumber $n
    if ($m.ok) {
        [void]$done.Add(('merged PR #{0}' -f $n))
    }
    else {
        [void]$done.Add(("FAILED PR #{0}: {1}" -f $n, $m.message))
    }
}

$done | ForEach-Object { Write-Output $_ }
Write-Output ("done: {0} lines" -f $done.Count)
