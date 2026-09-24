# Sync SimonBarnett/skills-visionary into a local sister clone and copy
# .grok/skills/*/SKILL.md into ~/.grok/skills (same pattern as Copy-BobProjectSkills /
# mud skill-book installs). Used by Bob Fleet tray Agents > Plan starts.
# Never commits. Never starts IRC / Watch-Bobiverse / Start-BobBuild.
[CmdletBinding()]
param(
    [string]$CloneRoot,
    [switch]$Pull
)

$ErrorActionPreference = 'Stop'

function Resolve-BobVisionaryCloneParent {
    foreach ($c in @('D:\ai', 'C:\ai', 'C:\src')) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    $fallback = 'D:\ai'
    New-Item -ItemType Directory -Force -Path $fallback | Out-Null
    return $fallback
}

function Resolve-BobVisionaryCloneRoot {
    param([string]$Hint)
    $candidates = @()
    if ($Hint) { $candidates += $Hint }
    $candidates += @(
        'D:\ai\skills-visionary',
        'C:\ai\skills-visionary',
        'C:\src\skills-visionary'
    )
    foreach ($c in $candidates) {
        $skill = Join-Path $c '.grok\skills\visionary\SKILL.md'
        if (Test-Path -LiteralPath $skill) { return [IO.Path]::GetFullPath($c) }
    }
    return $null
}

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) { throw 'git not found (required to sync skills-visionary)' }

$root = Resolve-BobVisionaryCloneRoot -Hint $CloneRoot
$cloned = $false
$pulled = $false
if (-not $root) {
    $parent = Resolve-BobVisionaryCloneParent
    $root = Join-Path $parent 'skills-visionary'
    Write-Host ("clone:   https://github.com/SimonBarnett/skills-visionary -> {0}" -f $root)
    & git clone --depth 1 https://github.com/SimonBarnett/skills-visionary.git $root
    if ($LASTEXITCODE -ne 0) { throw "git clone skills-visionary failed (exit $LASTEXITCODE)" }
    $cloned = $true
}
elseif ($Pull) {
    $dirty = & git -C $root status --porcelain 2>$null
    if (-not $dirty) {
        & git -C $root fetch origin 2>$null | Out-Null
        & git -C $root pull --ff-only origin main 2>$null | Out-Null
        $pulled = ($LASTEXITCODE -eq 0)
    }
    else {
        Write-Host 'git: dirty skills-visionary tree, skipped pull'
    }
}

$skillRoot = Join-Path $root '.grok\skills'
if (-not (Test-Path -LiteralPath $skillRoot)) {
    throw "skills-visionary missing .grok/skills at $root"
}
$skillDstRoot = Join-Path $env:USERPROFILE '.grok\skills'
$copied = @()
foreach ($dir in @(Get-ChildItem -LiteralPath $skillRoot -Directory -ErrorAction SilentlyContinue)) {
    $src = Join-Path $dir.FullName 'SKILL.md'
    if (-not (Test-Path -LiteralPath $src)) { continue }
    $dstDir = Join-Path $skillDstRoot $dir.Name
    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    Copy-Item -LiteralPath $src -Destination (Join-Path $dstDir 'SKILL.md') -Force
    $copied += $dir.Name
}

$sha = & git -C $root rev-parse HEAD 2>$null
Write-Host ("repo:    {0}" -f $root)
Write-Host ("HEAD:    {0}" -f $(if ($sha) { $sha } else { 'n/a' }))
Write-Host ("cloned:  {0}" -f $cloned)
Write-Host ("pulled:  {0}" -f $pulled)
Write-Host ("skills:  {0}" -f ($(if ($copied.Count) { ($copied | Sort-Object) -join ', ' } else { '(none)' })))
Write-Host ("dst:     {0}" -f $skillDstRoot)

[pscustomobject]@{
    ok     = $true
    repo   = $root
    sha    = $sha
    cloned = $cloned
    pulled = $pulled
    skills = @($copied | Sort-Object)
}
