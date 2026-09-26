# BT0plan new session: tray Plan (Grok / Cursor) MUST always open a brand-new planning session.
# Asserts the Plan launch command line never carries a resume/continue flag and that every
# Plan start gets its own NEW empty folder (fresh skill book, no previous plan files), while
# previous plan folders are left untouched. Standalone: no tray, no agent, no IRC, no network.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\BT0plan-new-session.ps1
[CmdletBinding()]
param([string]$RepoRoot)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$trayPath = Join-Path (Join-Path $RepoRoot 'tools') 'Watch-BobTray.ps1'
if (-not (Test-Path -LiteralPath $trayPath)) { throw "missing $trayPath" }

$script:fail = 0
function Invoke-Case([string]$Name, [scriptblock]$Body) {
    try { & $Body; Write-Host ("PASS {0}" -f $Name) }
    catch { $script:fail++; Write-Host ("FAIL {0}: {1}" -f $Name, $_.Exception.Message) }
}

# Load only the pure Plan helpers from the tray (the tray itself is never started).
$tok = $null; $err = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($trayPath, [ref]$tok, [ref]$err)
if ($err -and $err.Count) { throw ("Watch-BobTray.ps1 parse errors: " + (($err | ForEach-Object { $_.Message }) -join '; ')) }
function Get-TrayFn([string]$Name) {
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name }, $true)
    if (-not $fn) { throw "Watch-BobTray must define $Name" }
    return $fn
}
foreach ($name in @('ConvertTo-BobTrayProcessArgumentString', 'Get-BobTrayPlanRoot', 'Get-BobTrayPlanRules', 'New-BobTrayPlanWorkspace', 'Get-BobTrayPlanLaunchArgs')) {
    . ([scriptblock]::Create((Get-TrayFn $name).Extent.Text))
}
function Write-TrayLog([string]$m) { }

$resumeRx = '^(-r|--resume|-c|--continue|--fork-session|--restore-code)(=.*)?$'
function Assert-NoResumeFlag([string[]]$Argv, [string]$What) {
    foreach ($a in $Argv) {
        if ([string]$a -match $resumeRx) { throw "$What argv carries resume/continue flag '$a'" }
    }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('bt0-plan-new-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
if (-not $env:USERPROFILE) { $env:USERPROFILE = $tmp }
try {
    # Fake skills-visionary clone, dirty with a PREVIOUS plan's leftovers (the bug: every Plan reopened it).
    $vis = Join-Path $tmp 'skills-visionary'
    foreach ($d in @('.grok/skills/visionary', 'tools', 'docs/templates', 'docs/mocks')) { New-Item -ItemType Directory -Force -Path (Join-Path $vis $d) | Out-Null }
    Set-Content -LiteralPath (Join-Path $vis '.grok/skills/visionary/SKILL.md') -Value "---`nname: visionary`n---`nbt0 skill book"
    Set-Content -LiteralPath (Join-Path $vis 'tools/validate-vision-pack.py') -Value 'print(0)'
    Set-Content -LiteralPath (Join-Path $vis 'docs/templates/vision.md') -Value '# template'
    Set-Content -LiteralPath (Join-Path $vis 'docs/vision.md') -Value '# skills-visionary own vision (not a new plan)'
    Set-Content -LiteralPath (Join-Path $vis 'docs/mocks/home.html') -Value '<html></html>'
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try {
            & $git.Source -C $vis init -q 2>&1 | Out-Null
            & $git.Source -C $vis add -A 2>&1 | Out-Null
            & $git.Source -C $vis -c user.name=bt0 -c user.email=bt0@example.invalid commit -q -m seed 2>&1 | Out-Null
        }
        finally { $ErrorActionPreference = $prev }
    }
    # Previous plan leftovers AFTER the commit (untracked, like docs/club-madeira-skill/ on MarchHare).
    New-Item -ItemType Directory -Force -Path (Join-Path $vis 'docs/club-madeira-skill') | Out-Null
    Set-Content -LiteralPath (Join-Path $vis 'docs/club-madeira-skill/plan.md') -Value 'previous plan: club-madeira-onboarding'

    $planRoot = Join-Path $tmp 'BobPlans'
    $now = [datetime]'2026-09-25T13:45:07'

    $script:dirs = @()
    Invoke-Case 'BT0plan new folder per start (unique, empty of previous plans)' {
        $d1 = New-BobTrayPlanWorkspace -VisionRoot $vis -PlanRoot $planRoot -Now $now
        Set-Content -LiteralPath (Join-Path $d1 'my-plan.md') -Value 'plan one'
        $d2 = New-BobTrayPlanWorkspace -VisionRoot $vis -PlanRoot $planRoot -Now $now   # same second
        $d3 = New-BobTrayPlanWorkspace -VisionRoot $vis -PlanRoot $planRoot -Now $now.AddSeconds(1)
        $script:dirs = @($d1, $d2, $d3)
        if (@($script:dirs | Select-Object -Unique).Count -ne 3) { throw ("plan folders not unique: " + ($script:dirs -join ', ')) }
        foreach ($d in $script:dirs) {
            if (-not (Test-Path -LiteralPath $d -PathType Container)) { throw "plan folder missing: $d" }
            if ((Split-Path -Parent $d) -ne [IO.Path]::GetFullPath($planRoot)) { throw "plan folder not under BobPlans: $d" }
            if ((Split-Path -Leaf $d) -notmatch '^plan-\d{8}-\d{6}(-\d+)?$') { throw "plan folder name must be plan-yyyyMMdd-HHmmss: $d" }
            if ($d -eq [IO.Path]::GetFullPath($vis)) { throw 'plan folder must not be the skills-visionary clone' }
            if (-not (Test-Path -LiteralPath (Join-Path $d '.grok/skills/visionary/SKILL.md'))) { throw "fresh skill book missing in $d" }
            if (-not (Test-Path -LiteralPath (Join-Path $d 'docs/templates/vision.md'))) { throw "vision template missing in $d" }
            if (Test-Path -LiteralPath (Join-Path $d 'docs/club-madeira-skill')) { throw "previous plan leftovers carried into $d" }
            if (Test-Path -LiteralPath (Join-Path $d 'docs/vision.md')) { throw "clone's own docs/vision.md carried into $d" }
            if (Test-Path -LiteralPath (Join-Path $d 'docs/mocks')) { throw "clone's docs/mocks carried into $d" }
        }
        if ((Split-Path -Leaf $d1) -ne 'plan-20260925-134507') { throw "first folder name: $(Split-Path -Leaf $d1)" }
        foreach ($d in @($d2, $d3)) {
            if (Test-Path -LiteralPath (Join-Path $d 'my-plan.md')) { throw "previous plan's files carried into $d" }
        }
        # Previous plan folders are left untouched (never cleaned / deleted).
        if ((Get-Content -LiteralPath (Join-Path $d1 'my-plan.md') -Raw) -notmatch 'plan one') { throw 'previous plan folder was modified' }
        if (-not (Test-Path -LiteralPath (Join-Path $vis 'docs/club-madeira-skill/plan.md'))) { throw 'skills-visionary leftovers must not be deleted' }
    }

    Invoke-Case 'BT0plan grok command line: new session, no resume/continue, unique cwd' {
        $seen = @{}; $sids = @{}
        foreach ($d in $script:dirs) {
            $rules = Get-BobTrayPlanRules -VisionRoot $vis -Workspace $d
            $argv = @(Get-BobTrayPlanLaunchArgs -Kind 'grok' -Workspace $d -Rules $rules -Prompt 'Follow the visionary skill.')
            Assert-NoResumeFlag $argv 'grok'
            $line = ConvertTo-BobTrayProcessArgumentString -ArgumentList $argv
            if ($line -match '(^|\s)(-r|--resume|-c|--continue|--fork-session)(\s|=|$)') { throw "grok command line has resume/continue: $line" }
            $i = [array]::IndexOf($argv, '--permission-mode'); if ($i -lt 0 -or $argv[$i + 1] -ne 'plan') { throw 'grok must keep --permission-mode plan' }
            $i = [array]::IndexOf($argv, '--cwd'); if ($i -lt 0 -or $argv[$i + 1] -ne $d) { throw "grok --cwd must be the new plan folder ($d)" }
            $i = [array]::IndexOf($argv, '--session-id'); if ($i -lt 0) { throw 'grok must get a fresh --session-id' }
            $sid = [string]$argv[$i + 1]; $g = [guid]::Empty
            if (-not [guid]::TryParse($sid, [ref]$g)) { throw "grok --session-id must be a UUID: $sid" }
            if ($sids.ContainsKey($sid)) { throw "grok --session-id reused: $sid" }; $sids[$sid] = $true
            if ($seen.ContainsKey($d)) { throw "cwd reused: $d" }; $seen[$d] = $true
            if ($rules -notmatch [regex]::Escape("Workspace: $d")) { throw 'rules must name the new plan folder as workspace' }
            foreach ($bad in @('irc', 'Watch-Bobiverse', 'Start-BobBuild')) { if ($argv -contains $bad) { throw "grok argv must not contain $bad" } }
        }
    }

    Invoke-Case 'BT0plan cursor command line: new chat, no resume/continue, unique workspace' {
        $seen = @{}
        foreach ($d in $script:dirs) {
            $argv = @(Get-BobTrayPlanLaunchArgs -Kind 'cursor' -Workspace $d -Prompt 'Follow the visionary skill.')
            Assert-NoResumeFlag $argv 'cursor'
            if ($argv -notcontains '--plan') { throw 'cursor must keep --plan' }
            $i = [array]::IndexOf($argv, '--workspace'); if ($i -lt 0 -or $argv[$i + 1] -ne $d) { throw "cursor --workspace must be the new plan folder ($d)" }
            if ($seen.ContainsKey($d)) { throw "workspace reused: $d" }; $seen[$d] = $true
        }
    }

    Invoke-Case 'BT0plan Start-BobTrayPlanAgent wiring (static)' {
        $fn = (Get-TrayFn 'Start-BobTrayPlanAgent').Extent.Text
        foreach ($t in @("'-r'", "'--resume'", "'-c'", "'--continue'", "'--fork-session'")) {
            if ($fn.Contains($t)) { throw "Start-BobTrayPlanAgent must not pass $t" }
        }
        if ($fn -notmatch 'New-BobTrayPlanWorkspace') { throw 'Plan start must create a new plan folder each click' }
        if (([regex]::Matches($fn, 'Get-BobTrayPlanLaunchArgs')).Count -lt 2) { throw 'Grok and Cursor Plan must build argv via Get-BobTrayPlanLaunchArgs' }
        if ($fn -match '-WorkingDirectory \$visionRoot') { throw 'Plan seat must not run in the shared skills-visionary clone' }
        if ($fn -match "'--cwd', \`$visionRoot|'--workspace', \`$visionRoot") { throw 'Plan seat must not point the agent at the shared skills-visionary clone' }
        $argsFn = (Get-TrayFn 'Get-BobTrayPlanLaunchArgs').Extent.Text
        foreach ($t in @("'-r'", "'--resume'", "'-c'", "'--continue'", "'--fork-session'")) {
            if ($argsFn.Contains($t)) { throw "Get-BobTrayPlanLaunchArgs must not emit $t" }
        }
        $wsFn = (Get-TrayFn 'New-BobTrayPlanWorkspace').Extent.Text
        # Only the temp skill-book zip may be removed; never a plan folder.
        foreach ($m in [regex]::Matches($wsFn, 'Remove-Item[^\r\n]*')) {
            if ($m.Value -notmatch '-LiteralPath \$zip\b') { throw "New-BobTrayPlanWorkspace must never delete previous plans: $($m.Value)" }
        }
        $src = Get-Content -LiteralPath $trayPath -Raw
        if ($src -match '\[Environment\]::SetEnvironmentVariable') { throw 'session key must stay child-env only' }
    }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:fail) { Write-Host ("BT0plan-new-session: {0} failed" -f $script:fail); exit 1 }
Write-Host 'BT0plan-new-session: all passed'
exit 0
