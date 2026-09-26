# FR #346: Restart watcher full reinstall + tray shortcut (fake git).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-BobFleetReinstall-FR346.ps1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:Pass = 0
$script:Fail = 0
function Invoke-Case {
    param([string]$Id, [scriptblock]$Body)
    try {
        & $Body
        $script:Pass++
        Write-Host "PASS $Id"
    }
    catch {
        $script:Fail++
        Write-Host "FAIL $Id :: $($_.Exception.Message)"
    }
}

function Invoke-Reinstall {
    param([string[]]$Extra)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'tools\Invoke-BobFleetReinstall.ps1') @Extra 2>&1
    $code = $LASTEXITCODE
    $joined = ($out | ForEach-Object { [string]$_ }) -join "`n"
    $path = $null
    if ($joined -match 'REPORT_PATH=(.+)') { $path = $Matches[1].Trim() }
    if (-not $path -or -not (Test-Path -LiteralPath $path)) {
        throw "no REPORT_PATH exit=$code out=$joined"
    }
    $rep = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    return [pscustomobject]@{ code = $code; report = $rep; path = $path; raw = $joined }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('fr346-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $root | Out-Null
$env:BOB_WATCH_SEAT_PROFILE_ROOT = $root
$env:BOB_FLEET_REINSTALL_FAKE = '1'

function New-FakeGitRepo {
    param([string]$Name, [string]$Sha = 'deadbeef', [switch]$Dirty)
    $p = Join-Path $root $Name
    New-Item -ItemType Directory -Force -Path (Join-Path $p '.git') | Out-Null
    Set-Content -LiteralPath (Join-Path $p '.bob-fake-sha') -Value $Sha -Encoding ascii
    if ($Dirty) {
        Set-Content -LiteralPath (Join-Path $p '.bob-fake-dirty') -Value '1' -Encoding ascii
        Set-Content -LiteralPath (Join-Path $p 'dirty.txt') -Value 'local change' -Encoding utf8
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $p '.grok\skills\demo-skill') | Out-Null
    Set-Content -LiteralPath (Join-Path $p '.grok\skills\demo-skill\SKILL.md') -Value "# demo`n" -Encoding utf8
    return $p
}

$ab = New-FakeGitRepo -Name 'agentic_build' -Sha 'aaa1111'
$irc = New-FakeGitRepo -Name 'agentic_irc' -Sha 'bbb2222' -Dirty
$am = New-FakeGitRepo -Name 'AgentMonitor' -Sha 'ccc3333'

$manifest = @{
    default_branch = 'main'
    repos          = @(
        @{ name = 'agentic_build'; path_default = $ab }
        @{ name = 'agentic_irc'; path_default = $irc }
        @{ name = 'AgentMonitor'; path_default = $am }
    )
}
$manPath = Join-Path $root 'manifest.json'
($manifest | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $manPath -Encoding utf8

New-Item -ItemType Directory -Force -Path (Join-Path $ab 'tools') | Out-Null
Copy-Item (Join-Path $RepoRoot 'tools\Start-BobFleetTray.ps1') (Join-Path $ab 'tools\Start-BobFleetTray.ps1') -Force
Copy-Item (Join-Path $RepoRoot 'tools\Watch-BobTray.ps1') (Join-Path $ab 'tools\Watch-BobTray.ps1') -Force -ErrorAction SilentlyContinue

Invoke-Case 'T346-1 what-if pull stashes dirty and records shas' {
    $r = Invoke-Reinstall -Extra @('-RepoRoot', $ab, '-ManifestPath', $manPath, '-WhatIf', '-RelaunchTray')
    $rep = $r.report
    $ircRow = @($rep.repos | Where-Object { $_.name -eq 'agentic_irc' } | Select-Object -First 1)[0]
    if (-not $ircRow) { throw 'agentic_irc row missing' }
    if (-not $ircRow.stashed) { throw "dirty repo should stash (action=$($ircRow.action))" }
    if ($ircRow.action -notmatch 'stash') { throw "action should mention stash: $($ircRow.action)" }
    if (@($rep.deploy_shas).Count -lt 1) { throw 'deploy_shas empty' }
    if (-not $rep.summary) { throw 'summary missing' }
}

Invoke-Case 'T346-2 apply fake writes deploy sha files + skills' {
    $r = Invoke-Reinstall -Extra @('-RepoRoot', $ab, '-ManifestPath', $manPath, '-RelaunchTray')
    $rep = $r.report
    if (-not $rep.ok) { throw "report not ok errors=$($rep.errors -join ',')" }
    $shaDir = Join-Path $root '.grok\bob-fleet-deploy'
    if (-not (Test-Path -LiteralPath $shaDir)) { throw "deploy sha dir missing $shaDir" }
    $files = @(Get-ChildItem -LiteralPath $shaDir -Filter 'deployed-*.sha')
    if ($files.Count -lt 1) { throw 'no deployed-*.sha files' }
    $skill = Join-Path $root '.grok\skills\demo-skill\SKILL.md'
    if (-not (Test-Path -LiteralPath $skill)) { throw 'skill not copied' }
    $log = Join-Path $root 'Desktop\Watch-AgentHealth\tray-reinstall.log'
    if (-not (Test-Path -LiteralPath $log)) { throw 'tray-reinstall.log missing' }
    $ircRow = @($rep.repos | Where-Object { $_.name -eq 'agentic_irc' })[0]
    if (-not $ircRow.stashed) { throw 'live dirty should stash' }
    if ($ircRow.new_sha -eq $ircRow.old_sha) { throw 'fake ff should bump sha' }
}

Invoke-Case 'T346-3 shortcuts created (fake)' {
    $r = Invoke-Reinstall -Extra @('-RepoRoot', $ab, '-ManifestPath', $manPath, '-SkipTools', '-SkipSkills', '-SkipRestart')
    $rep = $r.report
    if (-not $rep.shortcuts.ok) { throw 'shortcuts not ok' }
    $paths = @($rep.shortcuts.paths)
    if ($paths.Count -lt 1) { throw 'no shortcut paths' }
}

Invoke-Case 'T346-4 Start-BobFleetTray single-instance script exists' {
    $p = Join-Path $RepoRoot 'tools\Start-BobFleetTray.ps1'
    if (-not (Test-Path -LiteralPath $p)) { throw 'Start-BobFleetTray.ps1 missing' }
    $t = Get-Content -LiteralPath $p -Raw
    if ($t -notmatch 'already running') { throw 'single-instance message missing' }
    if ($t -notmatch 'Watch-BobTray') { throw 'must launch Watch-BobTray' }
}

Invoke-Case 'T346-5 tray Restart watcher wires reinstall' {
    $tray = Get-Content -LiteralPath (Join-Path $RepoRoot 'tools\Watch-BobTray.ps1') -Raw
    if ($tray -notmatch 'Invoke-BobFleetReinstall') { throw 'Restart must call Invoke-BobFleetReinstall' }
    if ($tray -notmatch 'Start-BobFleetTray') { throw 'Restart should relaunch via Start-BobFleetTray' }
    if ($tray -notmatch 'function Restart-BobTrayWatcher') { throw 'Restart-BobTrayWatcher missing' }
}

Invoke-Case 'T346-6 manifest example present' {
    $m = Join-Path $RepoRoot 'config\bob-fleet-repos.example.json'
    if (-not (Test-Path -LiteralPath $m)) { throw 'manifest example missing' }
    $j = Get-Content -LiteralPath $m -Raw | ConvertFrom-Json
    if (@($j.repos).Count -lt 2) { throw 'manifest needs repos' }
}

Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item Env:\BOB_WATCH_SEAT_PROFILE_ROOT -ErrorAction SilentlyContinue
Remove-Item Env:\BOB_FLEET_REINSTALL_FAKE -ErrorAction SilentlyContinue
Write-Host "FR346 summary: $($script:Pass) pass / $($script:Fail) fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
