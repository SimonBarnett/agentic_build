#Requires -Version 5.1
# FR #346: full local fleet reinstall/update (Restart watcher).
# Pull repos, deploy scripts, record SHAs, optional tray single-instance relaunch.
# Never touches Ergo/Jeeves/other machines. Never logs secrets.
# -WhatIf / -DryRun for tests (fake git via -GitExe mock path or BOB_FLEET_REINSTALL_FAKE=1).
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$ManifestPath,
    [string]$ReportPath,
    [switch]$WhatIf,
    [switch]$DryRun,
    [switch]$SkipTools,
    [switch]$SkipSkills,
    [switch]$SkipRestart,
    [switch]$ForceIdleSeats,
    [switch]$RelaunchTray,
    [string]$GitExe = 'git'
)

$ErrorActionPreference = 'Stop'
if ($DryRun) { $WhatIf = $true }
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)

function Expand-BobPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $p }
    return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($p.Trim()))
}

function Write-BobReinstallLog([string]$m) {
    $dir = Join-Path $env:USERPROFILE 'Desktop\Watch-AgentHealth'
    if ($env:BOB_WATCH_SEAT_PROFILE_ROOT) {
        $dir = Join-Path $env:BOB_WATCH_SEAT_PROFILE_ROOT 'Desktop\Watch-AgentHealth'
    }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $path = Join-Path $dir 'tray-reinstall.log'
    if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path).Length -gt 800KB)) {
        Move-Item -LiteralPath $path -Destination ($path + '.1') -Force -ErrorAction SilentlyContinue
    }
    Add-Content -LiteralPath $path -Value ('{0:o} {1}' -f [datetime]::UtcNow, $m) -Encoding utf8
}

function Get-BobFleetManifest {
    param([string]$Path, [string]$Root)
    if (-not $Path) {
        foreach ($c in @(
                (Join-Path $Root 'config\bob-fleet-repos.json'),
                (Join-Path $Root 'config\bob-fleet-repos.example.json')
            )) {
            if (Test-Path -LiteralPath $c) { $Path = $c; break }
        }
    }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        throw 'fleet repo manifest missing (config/bob-fleet-repos.example.json)'
    }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Resolve-BobFleetRepoPath {
    param($Entry, [string]$FleetRoot)
    if ($Entry.path_env) {
        $ev = [Environment]::GetEnvironmentVariable([string]$Entry.path_env)
        if ($ev -and (Test-Path -LiteralPath $ev)) { return Expand-BobPath $ev }
    }
    if ($Entry.path_default) {
        $d = Expand-BobPath ([string]$Entry.path_default)
        if ($d -and (Test-Path -LiteralPath $d)) { return $d }
    }
    foreach ($c in @($Entry.path_candidates)) {
        $p = Expand-BobPath ([string]$c)
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    # agentic_build often is the fleet root
    if ([string]$Entry.name -eq 'agentic_build' -and $FleetRoot) {
        return $FleetRoot
    }
    return $null
}

function Invoke-BobGit {
    param([string[]]$ArgumentList, [string]$WorkDir)
    if ($env:BOB_FLEET_REINSTALL_FAKE -match '^(?i)1|true|yes$') {
        return [pscustomobject]@{ ExitCode = 0; StdOut = 'fake'; StdErr = '' }
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $GitExe
    $psi.Arguments = ($ArgumentList -join ' ')
    $psi.WorkingDirectory = $WorkDir
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return [pscustomobject]@{ ExitCode = $p.ExitCode; StdOut = $out; StdErr = $err }
}

function Get-BobGitSha {
    param([string]$WorkDir)
    if ($env:BOB_FLEET_REINSTALL_FAKE -match '^(?i)1|true|yes$') {
        $marker = Join-Path $WorkDir '.bob-fake-sha'
        if (Test-Path -LiteralPath $marker) {
            return (Get-Content -LiteralPath $marker -TotalCount 1).Trim()
        }
        return 'deadbeef'
    }
    $r = Invoke-BobGit -WorkDir $WorkDir -ArgumentList @('rev-parse', 'HEAD')
    if ($r.ExitCode -ne 0) { return '' }
    return ([string]$r.StdOut).Trim()
}

function Test-BobGitDirty {
    param([string]$WorkDir)
    if ($env:BOB_FLEET_REINSTALL_FAKE -match '^(?i)1|true|yes$') {
        return (Test-Path -LiteralPath (Join-Path $WorkDir '.bob-fake-dirty'))
    }
    $r = Invoke-BobGit -WorkDir $WorkDir -ArgumentList @('status', '--porcelain')
    return ([string]$r.StdOut).Trim().Length -gt 0
}

function Update-BobFleetRepo {
    param(
        $Entry,
        [string]$Path,
        [string]$Branch = 'main',
        [switch]$WhatIf
    )
    $name = [string]$Entry.name
    $row = [ordered]@{
        name       = $name
        path       = $Path
        ok         = $true
        stashed    = $false
        stash_name = ''
        old_sha    = ''
        new_sha    = ''
        action     = 'skip'
        error      = ''
    }
    if (-not $Path -or -not (Test-Path -LiteralPath (Join-Path $Path '.git'))) {
        $row.ok = $false
        $row.error = 'not a git checkout'
        $row.action = 'missing'
        return [pscustomobject]$row
    }
    $row.old_sha = Get-BobGitSha -WorkDir $Path
    $isFake = ($env:BOB_FLEET_REINSTALL_FAKE -match '^(?i)1|true|yes$')
    if ($WhatIf) {
        $dirty = Test-BobGitDirty -WorkDir $Path
        if ($dirty) {
            $row.stashed = $true
            $row.stash_name = ('bob-reinstall/{0:yyyyMMdd-HHmmss}' -f [datetime]::UtcNow)
            $row.action = 'would-stash-and-ff'
        }
        else {
            $row.action = 'would-ff'
        }
        if ($isFake) {
            $row.new_sha = ($row.old_sha + 'ff')
            if (-not $dirty) { $row.action = 'would-ff' }
        }
        else {
            $row.new_sha = $row.old_sha
        }
        return [pscustomobject]$row
    }
    try {
        if (Test-BobGitDirty -WorkDir $Path) {
            $stash = 'bob-reinstall/{0:yyyyMMdd-HHmmss}-{1}' -f [datetime]::UtcNow, $name
            if ($isFake) {
                $row.stashed = $true
                $row.stash_name = $stash
                Remove-Item -LiteralPath (Join-Path $Path '.bob-fake-dirty') -Force -ErrorAction SilentlyContinue
            }
            else {
                $s = Invoke-BobGit -WorkDir $Path -ArgumentList @('stash', 'push', '-u', '-m', $stash)
                if ($s.ExitCode -ne 0) { throw "stash failed: $($s.StdErr)" }
                $row.stashed = $true
                $row.stash_name = $stash
            }
        }
        if ($isFake) {
            $newSha = ($row.old_sha + 'ff')
            Set-Content -LiteralPath (Join-Path $Path '.bob-fake-sha') -Value $newSha -Encoding ascii
            $row.new_sha = $newSha
            $row.action = 'fast-forward'
        }
        else {
            $fetch = Invoke-BobGit -WorkDir $Path -ArgumentList @('fetch', 'origin', $Branch)
            if ($fetch.ExitCode -ne 0) { throw "fetch failed: $($fetch.StdErr)" }
            $ff = Invoke-BobGit -WorkDir $Path -ArgumentList @('merge', '--ff-only', "origin/$Branch")
            if ($ff.ExitCode -ne 0) {
                $ff = Invoke-BobGit -WorkDir $Path -ArgumentList @('pull', '--ff-only', 'origin', $Branch)
                if ($ff.ExitCode -ne 0) { throw "ff-only failed: $($ff.StdErr)" }
            }
            $row.new_sha = Get-BobGitSha -WorkDir $Path
            $row.action = $(if ($row.new_sha -eq $row.old_sha) { 'up-to-date' } else { 'fast-forward' })
        }
    }
    catch {
        $row.ok = $false
        $row.error = [string]$_.Exception.Message
        $row.action = 'error'
        $row.new_sha = Get-BobGitSha -WorkDir $Path
    }
    return [pscustomobject]$row
}

function Deploy-BobFleetComponentSha {
    param(
        [string]$Name,
        [string]$Sha,
        [string]$DestDir
    )
    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
    $path = Join-Path $DestDir ('deployed-{0}.sha' -f $Name)
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($path, ($Sha.Trim() + "`n"), $utf8)
    return $path
}

function Get-BobBusyWatchSeats {
    # Heuristic: state has accepted busy worker OR open ACK marker file
    $busy = @()
    $profile = if ($env:BOB_WATCH_SEAT_PROFILE_ROOT) { $env:BOB_WATCH_SEAT_PROFILE_ROOT } else { $env:USERPROFILE }
    foreach ($kind in @('grok', 'cursor')) {
        for ($s = 1; $s -le 8; $s++) {
            $stPath = Join-Path $profile ('.grok\agent-health\watch-{0}-{1}\state.json' -f $kind, $s)
            if (-not (Test-Path -LiteralPath $stPath)) { continue }
            try {
                $st = Get-Content -LiteralPath $stPath -Raw -Encoding UTF8 | ConvertFrom-Json
            }
            catch { continue }
            if ($st.busy -eq $true -or $st.openAck -eq $true) {
                $busy += [pscustomobject]@{ kind = $kind; slot = $s; state = $stPath }
            }
        }
    }
    return $busy
}

function Start-BobFleetTraySingleInstance {
    param(
        [string]$RepoRoot,
        [switch]$WhatIf
    )
    $tray = Join-Path $RepoRoot 'tools\Watch-BobTray.ps1'
    $pat = '(?i)Watch-BobTray\.ps1'
    $hits = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.CommandLine -and $_.CommandLine -match $pat
        })
    if ($hits.Count -gt 0) {
        $oldest = $hits | Sort-Object CreationDate | Select-Object -First 1
        return [pscustomobject]@{
            started = $false
            pid     = [int]$oldest.ProcessId
            status  = 'already running (single-instance; bring-forward only)'
        }
    }
    if ($WhatIf) {
        return [pscustomobject]@{ started = $false; pid = $null; status = 'would-start-tray' }
    }
    if ($env:BOB_FLEET_REINSTALL_FAKE -match '^(?i)1|true|yes$') {
        return [pscustomobject]@{ started = $true; pid = 0; status = 'fake-started-tray' }
    }
    $ps = (Get-Command powershell.exe).Source
    $p = Start-Process -FilePath $ps -ArgumentList @(
        '-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass',
        '-File', $tray
    ) -WorkingDirectory $RepoRoot -WindowStyle Hidden -PassThru
    return [pscustomobject]@{ started = $true; pid = [int]$p.Id; status = 'started' }
}

function Install-BobFleetTrayShortcuts {
    param(
        [string]$RepoRoot,
        [switch]$WhatIf,
        [string]$DesktopDir = '',
        [string]$StartMenuDir = ''
    )
    $launcher = Join-Path $RepoRoot 'tools\Start-BobFleetTray.ps1'
    if (-not (Test-Path -LiteralPath $launcher)) {
        return [pscustomobject]@{ ok = $false; error = 'Start-BobFleetTray.ps1 missing'; paths = @() }
    }
    if (-not $DesktopDir) {
        $DesktopDir = [Environment]::GetFolderPath('Desktop')
        if ($env:BOB_WATCH_SEAT_PROFILE_ROOT) {
            $DesktopDir = Join-Path $env:BOB_WATCH_SEAT_PROFILE_ROOT 'Desktop'
            New-Item -ItemType Directory -Force -Path $DesktopDir | Out-Null
        }
    }
    if (-not $StartMenuDir) {
        $StartMenuDir = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\Bob Fleet'
        if ($env:BOB_WATCH_SEAT_PROFILE_ROOT) {
            $StartMenuDir = Join-Path $env:BOB_WATCH_SEAT_PROFILE_ROOT 'StartMenu\Bob Fleet'
        }
    }
    New-Item -ItemType Directory -Force -Path $DesktopDir, $StartMenuDir | Out-Null
    $paths = @()
    $ps = (Get-Command powershell.exe).Source
    $args = "-NoProfile -STA -ExecutionPolicy Bypass -File `"$launcher`""
    foreach ($dir in @($DesktopDir, $StartMenuDir)) {
        $lnkPath = Join-Path $dir 'Bob Fleet.lnk'
        if ($WhatIf) {
            $paths += $lnkPath
            continue
        }
        if ($env:BOB_FLEET_REINSTALL_FAKE -match '^(?i)1|true|yes$') {
            # fake: write a stub file instead of COM shortcut
            Set-Content -LiteralPath ($lnkPath + '.target.txt') -Value "$ps $args" -Encoding utf8
            $paths += ($lnkPath + '.target.txt')
            continue
        }
        try {
            $w = New-Object -ComObject WScript.Shell
            $s = $w.CreateShortcut($lnkPath)
            $s.TargetPath = $ps
            $s.Arguments = $args
            $s.WorkingDirectory = $RepoRoot
            $s.WindowStyle = 7
            $s.Description = 'Bob Fleet systray (single instance)'
            $s.Save()
            $paths += $lnkPath
        }
        catch {
            $paths += "error:$($_.Exception.Message)"
        }
    }
    return [pscustomobject]@{ ok = $true; paths = $paths }
}

# --- main ---
$manifest = Get-BobFleetManifest -Path $ManifestPath -Root $RepoRoot
$branch = if ($manifest.default_branch) { [string]$manifest.default_branch } else { 'main' }
$report = [ordered]@{
    ok            = $true
    when          = (Get-Date).ToUniversalTime().ToString('o')
    machine       = $env:COMPUTERNAME
    what_if       = [bool]$WhatIf
    repos         = New-Object System.Collections.ArrayList
    skills        = New-Object System.Collections.ArrayList
    tools         = New-Object System.Collections.ArrayList
    deploy_shas   = New-Object System.Collections.ArrayList
    busy_seats    = @()
    tray          = $null
    shortcuts     = $null
    summary       = ''
    errors        = New-Object System.Collections.ArrayList
}

Write-BobReinstallLog ('begin what_if={0}' -f $WhatIf)

# Pull
foreach ($entry in @($manifest.repos)) {
    $p = Resolve-BobFleetRepoPath -Entry $entry -FleetRoot $RepoRoot
    $row = Update-BobFleetRepo -Entry $entry -Path $p -Branch $branch -WhatIf:$WhatIf
    [void]$report.repos.Add($row)
    Write-BobReinstallLog ("repo {0} {1} {2}->{3} stash={4} err={5}" -f $row.name, $row.action, $row.old_sha, $row.new_sha, $row.stashed, $row.error)
    if (-not $row.ok) {
        $report.ok = $false
        [void]$report.errors.Add(($row.name + ': ' + $row.error))
    }
    if ($row.ok -and $row.new_sha) {
        $shaDir = Join-Path $env:USERPROFILE '.grok\bob-fleet-deploy'
        if ($env:BOB_WATCH_SEAT_PROFILE_ROOT) {
            $shaDir = Join-Path $env:BOB_WATCH_SEAT_PROFILE_ROOT '.grok\bob-fleet-deploy'
        }
        if (-not $WhatIf) {
            $sp = Deploy-BobFleetComponentSha -Name $row.name -Sha $row.new_sha -DestDir $shaDir
            [void]$report.deploy_shas.Add([pscustomobject]@{ name = $row.name; sha = $row.new_sha; file = $sp })
        }
        else {
            [void]$report.deploy_shas.Add([pscustomobject]@{ name = $row.name; sha = $row.new_sha; file = '(what-if)' })
        }
    }
}

# Skills (idempotent copy SKILL.md)
if (-not $SkipSkills) {
    $skillDst = Join-Path $env:USERPROFILE '.grok\skills'
    if ($env:BOB_WATCH_SEAT_PROFILE_ROOT) {
        $skillDst = Join-Path $env:BOB_WATCH_SEAT_PROFILE_ROOT '.grok\skills'
    }
    $copied = 0
    foreach ($entry in @($manifest.repos)) {
        $p = Resolve-BobFleetRepoPath -Entry $entry -FleetRoot $RepoRoot
        if (-not $p) { continue }
        $rel = '.grok/skills'
        $srcRoot = Join-Path $p ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $srcRoot)) { continue }
        foreach ($dir in @(Get-ChildItem -LiteralPath $srcRoot -Directory -ErrorAction SilentlyContinue)) {
            $src = Join-Path $dir.FullName 'SKILL.md'
            if (-not (Test-Path -LiteralPath $src)) { continue }
            $dstDir = Join-Path $skillDst $dir.Name
            if (-not $WhatIf) {
                New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
                Copy-Item $src (Join-Path $dstDir 'SKILL.md') -Force
            }
            $copied++
            [void]$report.skills.Add([pscustomobject]@{ name = $dir.Name; from = $entry.name })
        }
    }
    Write-BobReinstallLog ("skills copied={0}" -f $copied)
}

# Tools (report-only hooks; real installs are idempotent external)
if (-not $SkipTools) {
    foreach ($t in @('python', 'gh', 'git')) {
        $cmd = Get-Command $t -ErrorAction SilentlyContinue
        [void]$report.tools.Add([pscustomobject]@{
                name   = $t
                found  = [bool]$cmd
                path   = $(if ($cmd) { $cmd.Source } else { '' })
                action = $(if ($cmd) { 'present' } else { 'missing' })
            })
    }
}

# Busy seats
$report.busy_seats = @(Get-BobBusyWatchSeats)
if ($report.busy_seats.Count -gt 0 -and -not $ForceIdleSeats) {
    Write-BobReinstallLog ('busy seats={0} (default wait; not force-killed)' -f $report.busy_seats.Count)
}

# Shortcuts always refresh
$report.shortcuts = Install-BobFleetTrayShortcuts -RepoRoot $RepoRoot -WhatIf:$WhatIf

# Tray single-instance
if ($RelaunchTray -or -not $SkipRestart) {
    $report.tray = Start-BobFleetTraySingleInstance -RepoRoot $RepoRoot -WhatIf:$WhatIf
    Write-BobReinstallLog ('tray {0}' -f $report.tray.status)
}

$repoLines = @($report.repos | ForEach-Object {
        '{0} {1}->{2} ({3})' -f $_.name, $_.old_sha.Substring(0, [Math]::Min(7, $_.old_sha.Length)), $_.new_sha.Substring(0, [Math]::Min(7, $_.new_sha.Length)), $_.action
    })
$report.summary = (@(
        ('repos: ' + ($repoLines -join '; '))
        ('skills: {0}' -f @($report.skills).Count)
        ('tray: {0}' -f $(if ($report.tray) { $report.tray.status } else { 'n/a' }))
        ('errors: {0}' -f @($report.errors).Count)
    ) -join ' | ')

Write-BobReinstallLog ('end ok={0} {1}' -f $report.ok, $report.summary)

if (-not $ReportPath) {
    $rd = Join-Path $env:USERPROFILE 'Desktop\Watch-AgentHealth'
    if ($env:BOB_WATCH_SEAT_PROFILE_ROOT) {
        $rd = Join-Path $env:BOB_WATCH_SEAT_PROFILE_ROOT 'Desktop\Watch-AgentHealth'
    }
    New-Item -ItemType Directory -Force -Path $rd | Out-Null
    $ReportPath = Join-Path $rd 'last-reinstall-report.json'
}
$report.repos = @($report.repos)
$report.skills = @($report.skills)
$report.tools = @($report.tools)
$report.deploy_shas = @($report.deploy_shas)
$report.errors = @($report.errors)
$report.report_path = $ReportPath
$json = ($report | ConvertTo-Json -Depth 8)
# Always write report file (tests + tray read this; avoids fragile stdout JSON parse)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportPath) | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText($ReportPath, $json + "`n", $utf8)
Write-Output ("REPORT_PATH={0}" -f $ReportPath)
Write-Output ("SUMMARY={0}" -f $report.summary)
if (-not $report.ok) { exit 2 }
exit 0
