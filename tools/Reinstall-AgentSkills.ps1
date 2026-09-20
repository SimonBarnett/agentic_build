# Sync SimonBarnett/agentic_build .grok/skills into ~/.grok/skills.
# Never commits. Never Start-BobBuild. Optional single-instance tray recycle.
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Pull,
    [switch]$RecycleTray
)

$ErrorActionPreference = 'Stop'

function Resolve-BobAgenticBuildRoot {
    param([string]$Hint)
    if ($Hint -and (Test-Path (Join-Path $Hint 'src\BobBridge.psd1'))) {
        return [IO.Path]::GetFullPath($Hint)
    }
    foreach ($c in @('D:\ai\agentic_build', 'C:\ai\agentic_build', 'C:\src\agentic_build')) {
        try {
            $psd = Join-Path $c 'src\BobBridge.psd1'
            if (Test-Path -LiteralPath $psd -ErrorAction SilentlyContinue) { return $c }
        }
        catch { }
    }
    throw 'agentic_build clone not found (D:\ai, C:\ai, C:\src). Clone https://github.com/SimonBarnett/agentic_build'
}

$RepoRoot = Resolve-BobAgenticBuildRoot $RepoRoot
$psd1 = Join-Path $RepoRoot 'src\BobBridge.psd1'
$git = Get-Command git -ErrorAction SilentlyContinue
$sha = $null
$pulled = $false
if ($git) {
    $sha = (& git -C $RepoRoot rev-parse HEAD 2>$null)
    if ($Pull) {
        $dirty = (& git -C $RepoRoot status --porcelain 2>$null)
        if (-not $dirty) {
            & git -C $RepoRoot fetch origin 2>$null | Out-Null
            & git -C $RepoRoot pull --ff-only origin main 2>$null | Out-Null
            $pulled = ($LASTEXITCODE -eq 0)
            $sha = (& git -C $RepoRoot rev-parse HEAD 2>$null)
        }
        else {
            Write-Host 'git: dirty tree, skipped pull'
        }
    }
}

Import-Module $psd1 -Force
$copied = @()
try {
    $copied = @(Copy-BobProjectSkills)
}
catch {
    $skillRoot = Join-Path $RepoRoot '.grok\skills'
    $skillDstRoot = Join-Path $env:USERPROFILE '.grok\skills'
    if (Test-Path $skillRoot) {
        foreach ($dir in @(Get-ChildItem $skillRoot -Directory)) {
            $src = Join-Path $dir.FullName 'SKILL.md'
            if (-not (Test-Path $src)) { continue }
            $dstDir = Join-Path $skillDstRoot $dir.Name
            New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
            Copy-Item $src (Join-Path $dstDir 'SKILL.md') -Force
            $copied += $dir.Name
        }
    }
}

$trayRecycled = $false
if ($RecycleTray) {
    $hits = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -match 'Watch-BobTray\.ps1' -and
            $_.CommandLine -notmatch 'Watch-BobJobs\.ps1'
        })
    foreach ($p in $hits) {
        try { Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue } catch { }
    }
    Start-Sleep -Milliseconds 400
    $ps = (Get-Command powershell.exe).Source
    $watch = Join-Path $RepoRoot 'tools\Watch-BobTray.ps1'
    Start-Process -FilePath $ps `
        -ArgumentList @('-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', $watch) `
        -WorkingDirectory $RepoRoot -WindowStyle Hidden | Out-Null
    $trayRecycled = $true
}

Write-Host ("repo:    {0}" -f $RepoRoot)
Write-Host ("HEAD:    {0}" -f $(if ($sha) { $sha } else { 'n/a' }))
Write-Host ("pulled:  {0}" -f $pulled)
Write-Host ("skills:  {0}" -f ($(if ($copied.Count) { ($copied | Sort-Object) -join ', ' } else { '(none)' })))
Write-Host ("dst:     {0}" -f (Join-Path $env:USERPROFILE '.grok\skills'))
Write-Host ("tray:    {0}" -f $(if ($trayRecycled) { 'recycled one Watch-BobTray' } else { 'left running' }))

[pscustomobject]@{
    ok      = $true
    repo    = $RepoRoot
    sha     = $sha
    pulled  = $pulled
    skills  = @($copied | Sort-Object)
    tray    = $trayRecycled
}
