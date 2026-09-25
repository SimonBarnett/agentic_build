# Off-DEV test pack (BT0*). Uses Fake-Grok. Does not touch real ~/.grok/bob-bridge.
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$OnlyCase
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) {
    $RepoRoot = Split-Path $PSScriptRoot -Parent
}
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$src = Join-Path $RepoRoot 'src\BobBridge.psd1'
$fake = Join-Path $RepoRoot 'tools\Fake-Grok.ps1'
$schemaDir = Join-Path $RepoRoot 'schemas'

function New-TestRoot {
    $d = Join-Path $env:TEMP ('bob-bridge-test-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $d 'cwd') | Out-Null
    return $d
}

function Test-BobCursorJobLaunchProcesses {
    param([string]$JobId)
    if (-not $JobId) { return @() }
    $needle = "cursor-agent-$JobId.launch.ps1"
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*$needle*" })
}

function Assert-BobCursorJobNotSpawned {
    param([string]$JobId)
    $hits = Test-BobCursorJobLaunchProcesses -JobId $JobId
    if ($hits.Count -gt 0) {
        throw "this job spawned cursor-agent launch (jobId=$JobId pids=$($hits.ProcessId -join ','))"
    }
}

function Import-Bridge {
    param([string]$BridgeRoot)
    $env:BOB_BRIDGE_HOME = $BridgeRoot
    $env:BOB_GROK_EXE = $fake
    $env:BOB_IRC_HOME = Join-Path $BridgeRoot 'irc-home'
    $ircCfg = Join-Path $BridgeRoot 'no-bobiverse.json'
    if (-not (Test-Path $ircCfg)) {
        '{"channel":"#test","mode":"free","mootId":"testmoot","nicks":{}}' | Set-Content -Path $ircCfg -Encoding utf8
    }
    $env:BOB_IRC_CONFIG = $ircCfg
    $env:BOB_CURSOR_USAGE_FILE = Join-Path $BridgeRoot 'no-cursor-usage.json'
    # Default digest URL is the live report endpoint. Keep the pack on local
    # bob-peers fixtures; a refused port fails fast and falls back to the file.
    Remove-Item Env:AGENTIC_IRC_DIGEST_URL -ErrorAction SilentlyContinue
    $env:BOB_DIGEST_URL = 'http://127.0.0.1:9/bob/v1/digest'
    $env:BOB_SKIP_LIVE_GROK = '1'
    $env:BOB_FLEET_BUNDLED = '0'
    $env:BOB_FLEET_REGISTRY = $null
    $env:BOB_FLEET_SHARE = $null
    Remove-Module BobBridge -ErrorAction SilentlyContinue
    Import-Module $src -Force
}

function Add-TestBobIrcDigestWhisper {
    param(
        [Parameter(Mandatory)][string]$IrcHome,
        [Parameter(Mandatory)][string]$Nick,
        $DigestObj,
        [switch]$ResetTrayPos
    )
    $rawJson = ($DigestObj | ConvertTo-Json -Depth 8 -Compress)
    $line = ":Jeeves!u@h PRIVMSG $Nick :$rawJson"
    $ircLog = Join-Path $IrcHome 'irc.log'
    if (Test-Path $ircLog) {
        Add-Content -LiteralPath $ircLog -Value $line -Encoding utf8
    }
    else {
        Set-Content -LiteralPath $ircLog -Value $line -Encoding utf8
    }
    $posPath = Join-Path $IrcHome 'bob-peers\_tray-log.pos'
    if ($ResetTrayPos -and (Test-Path $posPath)) {
        Remove-Item -LiteralPath $posPath -Force
    }
    return @(Import-BobIrcTrayPull)
}

$script:Pass = 0
$script:Fail = 0
$script:Results = @()

function Invoke-Case {
    param([string]$Id, [scriptblock]$Body)
    if ($OnlyCase -and $Id -ne $OnlyCase) { return }
    $bridgeRoot = $null
    try {
        $bridgeRoot = New-TestRoot
        Import-Bridge -BridgeRoot $bridgeRoot
        & $Body $bridgeRoot
        $script:Pass++
        $script:Results += [pscustomobject]@{ id = $Id; ok = $true; detail = 'pass' }
        Write-Host "PASS $Id"
    }
    catch {
        $script:Fail++
        $msg = $_.Exception.Message
        $script:Results += [pscustomobject]@{ id = $Id; ok = $false; detail = $msg }
        Write-Host "FAIL $Id :: $msg"
    }
    finally {
        Remove-Module BobBridge -ErrorAction SilentlyContinue
        $env:BOB_BRIDGE_HOME = $null
        $env:BOB_GROK_EXE = $null
        $env:BOB_WEEKLY_LOG = $null
        $env:BOB_FLEET_REGISTRY = $null
        $env:BOB_FLEET_SHARE = $null
        $env:BOB_FLEET_BUNDLED = $null
        $env:BOB_IRC_HOME = $null
        $env:BOB_IRC_CONFIG = $null
        $env:BOB_CURSOR_USAGE_FILE = $null
        $env:BOB_CURSOR_AGENT_FIXTURE = $null
        $env:BOB_CURSOR_USD_GBP_RATE = $null
        $env:BOB_SKIP_LIVE_GROK = $null
        $env:BOB_CAPACITY_FILE = $null
        $env:BOB_GH_EXE = $null
        $env:BOB_FAKE_GH_MODE = $null
        $env:BOB_FAKE_GH_LOG = $null
        $env:BOB_FAKE_GH_QUIET = $null
        $env:BOB_MACHINE_ID = $null
        $env:BOB_DIGEST_URL = $null
        Remove-Item Env:AGENTIC_IRC_DIGEST_URL -ErrorAction SilentlyContinue
        $env:BOB_GROK_TALK_CURSOR_FIXTURE = $null
        $env:BOB_GROK_TALK_TEST_THROW = $null
        $env:AGENTIC_IRC_HOME = $null
        $env:BOB_REPORT_CAPTURE_DIR = $null
        $env:BOB_REPO_PAIR_IDLE_SEC = $null
        $env:BOB_REPORT_URL = $null
    }
}

# --- BT0 skills ---
Invoke-Case 'BT0 skills' {
    foreach ($n in @('grok-build-fleet', 'unstick-grok-bot', 'bob-build-loop', 'bob-spec-intake', 'bob-build-dispatch', 'bob-hostile-mrb', 'box-usage', 'harvest-agent-skills', 'bob-fleet-monitor', 'bob-fleet-tray', 'start-bob-copilot', 'start-bob-cursor', 'cursor-mrb-dev', 'bob-job-loop', 'bob-irc', 'reinstall-agentic-build-skills', 'setup-remote-grok-bot', 'cursor-sand-billing', 'killproc', 'cleanup-orphans', 'github-irc-webhooks', 'setup-github-webhooks', 'setup-ssl-certs', 'agent-monitor-setup', 'watch-agent-health', 'setup-github-cursor', 'visionary')) {
        $p = Join-Path $RepoRoot ".grok\skills\$n\SKILL.md"
        if (-not (Test-Path $p)) { throw "missing $p" }
        $raw = Get-Content $p -Raw
        if ($raw -notmatch ('(?m)^name:\s*' + [regex]::Escape($n))) { throw "name mismatch $n" }
        if ($n -eq 'harvest-agent-skills' -and $raw -notmatch 'https://github\.com/SimonBarnett/agentic_build') { throw 'harvest-agent-skills must name home GitHub' }
        if ($n -eq 'harvest-agent-skills' -and $raw -notmatch 'honesty box') { throw 'harvest-agent-skills must keep the honesty box' }
        if ($n -eq 'killproc' -and $raw -notmatch '-IrcHome') { throw 'killproc skill must document -IrcHome' }
        if ($n -eq 'cleanup-orphans' -and $raw -notmatch 'Cleanup-OrphanAgents') { throw 'cleanup-orphans skill must document Cleanup-OrphanAgents.ps1' }
        if ($n -eq 'github-irc-webhooks' -and $raw -notmatch 'setup-github-webhooks') { throw 'github-irc-webhooks must point at setup-github-webhooks' }
        if ($n -eq 'setup-github-webhooks' -and $raw -notmatch 'irc\.ntsa\.uk/bob/v1/git') { throw 'setup-github-webhooks must document git URL' }
        if ($n -eq 'setup-ssl-certs' -and $raw -notmatch 'wacs\.exe') { throw 'setup-ssl-certs must document wacs.exe' }
        if ($n -eq 'setup-github-cursor' -and $raw -notmatch 'cursor\[bot\]') { throw 'setup-github-cursor must name cursor[bot]' }
        if ($n -eq 'setup-github-cursor' -and $raw -notmatch 'All repositories') { throw 'setup-github-cursor must require All repositories' }
        if ($n -eq 'setup-github-cursor' -and $raw -notmatch 'not a user') { throw 'setup-github-cursor must say cursor[bot] is not a collaborator user' }
        if ($n -eq 'setup-github-cursor' -and $raw -notmatch 'user/installations') { throw 'setup-github-cursor must document user/installations 403' }
        if ($n -eq 'setup-github-cursor' -and $raw -notmatch 'settings/installations') { throw 'setup-github-cursor must Configure existing install' }
        if ($n -eq 'setup-github-cursor' -and $raw -notmatch 'installations/new') { throw 'setup-github-cursor must warn against installations/new' }
        if ($n -eq 'setup-github-cursor' -and $raw -notmatch 'merge queues') { throw 'setup-github-cursor must record the GitHub UI permission list' }
        if ($n -eq 'setup-github-cursor' -and $raw -notmatch 'Disconnect') { throw 'setup-github-cursor must document dashboard Disconnect when All repos is already set' }
        if ($n -eq 'bob-spec-intake' -and $raw -notmatch 'setup-github-cursor') { throw 'bob-spec-intake New repo must call setup-github-cursor' }
        if ($n -eq 'bob-spec-intake' -and $raw -notmatch 'visionary') { throw 'bob-spec-intake New product must call visionary first' }
        if ($n -eq 'bob-spec-intake' -and $raw -notmatch 'validate-vision-pack') { throw 'bob-spec-intake must run validate-vision-pack before park/dispatch' }
        if ($n -eq 'visionary' -and $raw -notmatch 'validate-vision-pack') { throw 'visionary must refuse until validate-vision-pack exits 0' }
        if ($n -eq 'visionary' -and $raw -notmatch 'measurable') { throw 'visionary must require measurable success' }
        if ($n -eq 'visionary' -and $raw -notmatch 'docs/mocks') { throw 'visionary must park HTML mocks in docs/mocks' }
        if ($n -eq 'visionary' -and $raw -notmatch 'bob-spec-intake') { throw 'visionary must hand park to bob-spec-intake' }
        if ($n -eq 'github-irc-webhooks' -and $raw -notmatch 'setup-github-cursor') { throw 'github-irc-webhooks must point at setup-github-cursor' }
        if ($n -eq 'bob-hostile-mrb' -and $raw -notmatch 'recycle-after-merge') { throw 'bob-hostile-mrb must document recycle-after-merge after merge to main' }
        if ($n -eq 'bob-hostile-mrb' -and $raw -notmatch '(?i)ionos') { throw 'bob-hostile-mrb must document ionos IRC restart when required' }
        if ($n -eq 'bob-hostile-mrb' -and $raw -notmatch '(?i)restart') { throw 'bob-hostile-mrb must document ionos restart IRC when required' }
        if ($n -eq 'bob-hostile-mrb' -and $raw -notmatch '(?i)Implementer PR workers do not live-recycle') { throw 'bob-hostile-mrb must say Bob/ionos recycle, not implementer live-recycle' }
    }
    $visionTpl = Join-Path $RepoRoot 'docs\templates\vision.md'
    if (-not (Test-Path $visionTpl)) { throw 'missing docs/templates/vision.md' }
    $visionTplRaw = Get-Content $visionTpl -Raw
    if ($visionTplRaw -notmatch 'fail-when') { throw 'vision template must have a success fail-when column' }
    $stopHung = Get-Content (Join-Path $RepoRoot 'tools\Stop-HungAgent.ps1') -Raw
    if ($stopHung -match "'#bobiverse,#flamingo'") { throw 'Stop-HungAgent must derive shop channel from nick, not hardcode #flamingo' }
}

# --- BT0plan seat own console ---
Invoke-Case 'BT0plan seat own console' {
    param($bridgeRoot)
    # Tray Plan -> Grok launched agent.exe (log: "plan: launch grok plan seat ... sessionKey=yes") but
    # no window appeared: ProcessStartInfo UseShellExecute=false + CreateNoWindow=false attaches the
    # child to the tray's HIDDEN console (tray runs powershell -WindowStyle Hidden). The no-key path
    # used Start-Process, which joins -ArgumentList unquoted on PS 5.1 (splits --rules).
    $trayPath = Join-Path $RepoRoot 'tools\Watch-BobTray.ps1'
    $tok = $null; $err = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($trayPath, [ref]$tok, [ref]$err)
    foreach ($name in @('ConvertTo-BobTrayProcessArgumentString', 'Initialize-BobTrayConsoleLauncher', 'Start-BobTrayVisibleProcessWithSessionEnv')) {
        $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        if ($fn) { . ([scriptblock]::Create($fn.Extent.Text)) }
        elseif ($name -ne 'Initialize-BobTrayConsoleLauncher') { throw "Watch-BobTray must define $name" }
    }
    function Write-TrayLog([string]$m) { }
    function Register-BobTrayGrokSession { param($Process, $SessionEnv) }
    $child = Join-Path $bridgeRoot 'plan-child.ps1'
    Set-Content -LiteralPath $child -Value @'
param([string]$Out)
[IO.File]::WriteAllText($Out, ('{0}|{1}|{2}|{3}' -f $PID, [string]$env:BT0_PLAN_SESSION, $args.Count, ($args -join '#')))
Start-Sleep -Seconds 6
'@
    $ps = (Get-Command powershell.exe).Source
    $rules = 'PLAN SEAT ONLY. Follow the visionary skill book (skills-visionary). Workspace: D:\ai\skills-visionary'
    $started = @()
    try {
        foreach ($mode in @('session', 'nokey')) {
            $out = Join-Path $bridgeRoot "plan-child-$mode.txt"
            $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $child, $out, $rules, 'second')
            $sess = $null
            if ($mode -eq 'session') { $sess = @{ BT0_PLAN_SESSION = 'bt0-session-not-a-key' } }
            Start-BobTrayVisibleProcessWithSessionEnv -FilePath $ps -ArgumentList $argv -WorkingDirectory $bridgeRoot -SessionEnv $sess
            $deadline = (Get-Date).AddSeconds(20)
            while (-not (Test-Path -LiteralPath $out) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
            if (-not (Test-Path -LiteralPath $out)) { throw "$mode plan child did not start" }
            Start-Sleep -Milliseconds 300
            $f = (Get-Content -LiteralPath $out -Raw).Split('|')
            $childPid = [int]$f[0]
            $started += $childPid
            $conhost = $null
            $deadline = (Get-Date).AddSeconds(4)
            while (-not $conhost -and (Get-Date) -lt $deadline) {
                $conhost = @(Get-CimInstance Win32_Process -Filter "Name='conhost.exe' AND ParentProcessId=$childPid" -ErrorAction SilentlyContinue)[0]
                if (-not $conhost) { Start-Sleep -Milliseconds 200 }
            }
            if (-not $conhost) { throw "$mode plan seat must get its OWN console (no conhost.exe child of pid ${childPid}; it inherited the tray's hidden console)" }
            $want = if ($mode -eq 'session') { 'bt0-session-not-a-key' } else { '' }
            if ($f[1] -ne $want) { throw "$mode child env BT0_PLAN_SESSION='$($f[1])' (want '$want')" }
            if ($f[2] -ne '2' -or $f[3] -ne ($rules + '#second')) { throw "$mode args not preserved (count=$($f[2])): $($f[3])" }
        }
        if ($env:BT0_PLAN_SESSION) { throw 'session value must not leak into the launching (tray) process env' }
    }
    finally {
        foreach ($p in $started) { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue }
    }
    $traySrc = Get-Content -LiteralPath $trayPath -Raw
    if ($traySrc -notmatch "-Title 'Grok plan seat \(visionary\)'" -or $traySrc -notmatch "-Title 'Cursor plan seat \(visionary\)'") { throw 'Plan Grok/Cursor must launch via the own-console launcher with a seat title' }
}

Invoke-Case 'BT0plan seat own console mrb hostile' {
    $tray = Get-Content (Join-Path $RepoRoot 'tools\Watch-BobTray.ps1') -Raw
    if ($tray -notmatch 'function Initialize-BobTrayConsoleLauncher') { throw 'missing Initialize-BobTrayConsoleLauncher' }
    if ($tray -notmatch 'CREATE_NEW_CONSOLE') { throw 'must CreateProcess with CREATE_NEW_CONSOLE' }
    if ($tray -notmatch 'CREATE_UNICODE_ENVIRONMENT') { throw 'must pass Unicode env block' }
    if ($tray -notmatch 'function ConvertTo-BobTrayProcessArgumentString') { throw 'Windows-quoted args required' }
    if ($tray -notmatch 'function Start-BobTrayVisibleProcessWithSessionEnv') { throw 'visible plan path required' }
    if ($tray -notmatch 'own console') { throw 'must log own console' }
    # .cmd via cmd.exe /d /s /c
    if ($tray -notmatch 'cmd\.exe' -or $tray -notmatch '/d' -or $tray -notmatch '/s') { throw 'cmd.bat path must use cmd.exe /d /s /c' }
    # session key must not be written to User/Machine env in this path
    if ($tray -match 'SetEnvironmentVariable\([^\)]*Machine') { throw 'must not set Machine env for session key' }
    if ($tray -match '\[Environment\]::SetEnvironmentVariable') { throw 'must not persist session key via SetEnvironmentVariable' }
    # hidden watch path unchanged marker
    if ($tray -notmatch 'Start-BobTrayProcessWithSessionEnv') { throw 'hidden watch path must remain' }


}

# --- BT0plan visionary sync ---
Invoke-Case 'BT0plan visionary sync git stderr' {
    param($bridgeRoot)
    # Tray Plan -> "Could not sync skills-visionary: Install-VisionarySkills failed (exit 1)".
    # Windows PowerShell 5.1 + ErrorActionPreference Stop + `git pull ... 2>$null`: git's
    # "From <url>" stderr line (printed on EVERY pull) became a terminating NativeCommandError.
    # Run the installer exactly like the tray: powershell.exe -NoProfile -File ... -Pull, 2>&1.
    $installer = Join-Path $RepoRoot 'tools\Install-VisionarySkills.ps1'
    $vis = Join-Path $bridgeRoot 'vis'
    $bare = Join-Path $vis 'origin.git'
    $seed = Join-Path $vis 'seed'
    $clone = Join-Path $vis 'skills-visionary'
    $fakeHome = Join-Path $vis 'home'
    New-Item -ItemType Directory -Force -Path $vis, $fakeHome | Out-Null
    function Invoke-Bt0VisGit {
        param([string[]]$A)
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $o = @(& git -c user.name=bt0 -c user.email=bt0@example.invalid @A 2>&1 | ForEach-Object { [string]$_ })
            $c = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $prev }
        if ($c -ne 0) { throw ("git {0} failed: {1}" -f ($A -join ' '), ($o -join ' | ')) }
    }
    function Invoke-Bt0VisInstaller {
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $savedProfile = $env:USERPROFILE
        try {
            $env:USERPROFILE = $fakeHome
            $o = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Pull -CloneRoot $clone 2>&1 | ForEach-Object { [string]$_ })
            $c = $LASTEXITCODE
        }
        finally {
            $env:USERPROFILE = $savedProfile
            $ErrorActionPreference = $prev
        }
        return [pscustomobject]@{ Code = $c; Text = ($o -join "`n") }
    }
    $skillRel = '.grok\skills\visionary\SKILL.md'
    Invoke-Bt0VisGit @('init', '-q', '--bare', $bare)
    Invoke-Bt0VisGit @('--git-dir', $bare, 'symbolic-ref', 'HEAD', 'refs/heads/main')
    Invoke-Bt0VisGit @('init', '-q', $seed)
    Invoke-Bt0VisGit @('-C', $seed, 'checkout', '-q', '-b', 'main')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent (Join-Path $seed $skillRel)) | Out-Null
    Set-Content -LiteralPath (Join-Path $seed $skillRel) -Value "---`nname: visionary`n---`nbt0 v1"
    Invoke-Bt0VisGit @('-C', $seed, 'add', '-A')
    Invoke-Bt0VisGit @('-C', $seed, 'commit', '-q', '-m', 'v1')
    Invoke-Bt0VisGit @('-C', $seed, 'push', '-q', $bare, 'main')
    Invoke-Bt0VisGit @('clone', '-q', $bare, $clone)
    Set-Content -LiteralPath (Join-Path $seed $skillRel) -Value "---`nname: visionary`n---`nbt0 v2"
    Invoke-Bt0VisGit @('-C', $seed, 'commit', '-q', '-am', 'v2')
    Invoke-Bt0VisGit @('-C', $seed, 'push', '-q', $bare, 'main')

    # 1) clean clone, upstream moved: git prints "From ..." on stderr -> must exit 0 and copy v2
    $r = Invoke-Bt0VisInstaller
    if ($r.Code -ne 0) { throw ("installer exit {0} on a clean pull (git stderr must not be fatal): {1}" -f $r.Code, $r.Text) }
    if ($r.Text -notmatch 'pulled:\s+True') { throw "pull must succeed: $($r.Text)" }
    $copied = Join-Path $fakeHome $skillRel
    if (-not (Test-Path -LiteralPath $copied) -or (Get-Content -LiteralPath $copied -Raw) -notmatch 'bt0 v2') { throw 'visionary SKILL.md v2 must be copied into ~/.grok/skills' }
    # 2) origin unreachable: warn, keep the existing copy, exit 0 (Plan must not be blocked)
    Invoke-Bt0VisGit @('-C', $clone, 'remote', 'set-url', 'origin', (Join-Path $vis 'missing.git'))
    $r = Invoke-Bt0VisInstaller
    if ($r.Code -ne 0) { throw ("unreachable origin must warn, not fail (exit {0}): {1}" -f $r.Code, $r.Text) }
    if ($r.Text -notmatch 'warning: git pull failed' -or $r.Text -notmatch 'pulled:\s+False') { throw "pull failure must be reported as a warning: $($r.Text)" }
    if (-not (Test-Path -LiteralPath $copied)) { throw 'existing skills copy must remain' }
    # 3) no `git ... 2>$null` left under ErrorActionPreference Stop
    $src = Get-Content -LiteralPath $installer -Raw
    if ($src -match '&\s*git\b[^\r\n]*2>\$null') { throw 'Install-VisionarySkills must not run git with 2>$null under ErrorActionPreference Stop' }

    # 4) tray: sync failed but a previous clone exists -> launch with a warning; none -> dialog error with the reason
    $trayPath = Join-Path $RepoRoot 'tools\Watch-BobTray.ps1'
    $tok = $null; $err = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($trayPath, [ref]$tok, [ref]$err)
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Sync-BobTrayVisionarySkills' }, $true)
    if (-not $fn) { throw 'Watch-BobTray must define Sync-BobTrayVisionarySkills' }
    . ([scriptblock]::Create($fn.Extent.Text))
    $trayLog = New-Object System.Collections.ArrayList
    function Write-TrayLog([string]$m) { [void]$trayLog.Add($m) }
    $fakeRepo = Join-Path $vis 'repo'
    New-Item -ItemType Directory -Force -Path (Join-Path $fakeRepo 'tools') | Out-Null
    Set-Content -LiteralPath (Join-Path $fakeRepo 'tools\Install-VisionarySkills.ps1') -Value "Write-Output 'bt0 sync boom'`nexit 1"
    $RepoRoot = $fakeRepo
    function Get-BobTrayVisionaryCloneRoot { return $clone }
    $got = $null
    try { $got = Sync-BobTrayVisionarySkills } catch { throw "failed sync with an existing copy must not block Plan: $($_.Exception.Message)" }
    if ($got -ne $clone) { throw "failed sync with an existing copy must return that copy, got '$got'" }
    if (@($trayLog | Where-Object { $_ -match 'WARNING visionary sync failed \(exit 1\)' }).Count -eq 0) { throw 'tray must log the sync warning' }
    function Get-BobTrayVisionaryCloneRoot { return $null }
    $msg = $null
    try { [void](Sync-BobTrayVisionarySkills) } catch { $msg = $_.Exception.Message }
    if ($msg -notmatch 'Install-VisionarySkills failed \(exit 1\): bt0 sync boom') { throw "no copy must raise the dialog error with the reason, got '$msg'" }
}

# --- BT0 parse ---
Invoke-Case 'BT0 parse' {
    $files = Get-ChildItem $RepoRoot -Recurse -Include *.ps1, *.psm1, *.psd1 |
        Where-Object { $_.FullName -notmatch '\\tests\\fixtures\\' }
    # Report EVERY file that does not parse (Windows PowerShell 5.1 reads BOM-less files as ANSI:
    # a UTF-8 em dash ends in 0x94 = a curly quote, which terminates strings). Throwing on the
    # first failure let Cleanup-OrphanAgents.ps1 hide a broken Install-AgentMonitor.ps1.
    $bad = @()
    foreach ($f in $files) {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
        if ($errors -and $errors.Count -gt 0) {
            $bad += ('{0}: L{1} {2}' -f $f.FullName, $errors[0].Extent.StartLineNumber, $errors[0].Message)
        }
    }
    if ($bad.Count -gt 0) {
        throw ("{0} file(s) do not parse under this PowerShell (save non-ASCII scripts as UTF-8 with BOM): {1}" -f $bad.Count, ($bad -join ' | '))
    }
}

# --- BT0 encoding ---

Invoke-Case 'BT0plan visionary sync mrb hostile' {
    $inst = Get-Content (Join-Path $RepoRoot 'tools\Install-VisionarySkills.ps1') -Raw
    if ($inst -notmatch 'function Invoke-BobVisionaryGit') { throw 'missing Invoke-BobVisionaryGit' }
    if ($inst -match '&\s*git[^\r\n]*2>\$null') { throw 'git must not use 2>$null under Stop EAP' }
    if ($inst -notmatch '\$ErrorActionPreference\s*=\s*''Continue''') { throw 'git helper must use Continue while capturing' }
    $tray = Get-Content (Join-Path $RepoRoot 'tools\Watch-BobTray.ps1') -Raw
    if ($tray -notmatch 'function Get-BobTrayVisionaryCloneRoot') { throw 'Get-BobTrayVisionaryCloneRoot required' }
    if ($tray -notmatch 'launching with existing copy') { throw 'tray must warn and launch with existing copy' }
}
Invoke-Case 'BT0 encoding utf8 bom' {
    # Windows PowerShell 5.1 reads BOM-less scripts as ANSI (cp1252): UTF-8 em dash / arrow bytes turn
    # into mojibake, and a trailing 0x94 / 0x9D byte can act as a curly quote inside strings (#322).
    # Every tracked PowerShell file that contains non-ASCII bytes must be UTF-8 with BOM.
    $tracked = @(& git -C $RepoRoot ls-files -- '*.ps1' '*.psm1' '*.psd1')
    if ($tracked.Count -eq 0) { throw 'git ls-files returned no PowerShell files' }
    $latin1 = [Text.Encoding]::GetEncoding(28591)
    $bad = @()
    foreach ($rel in $tracked) {
        if ($rel -match '(^|/)tests/fixtures/') { continue }
        $p = Join-Path $RepoRoot $rel
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $b = [IO.File]::ReadAllBytes($p)
        if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { continue }
        if ($latin1.GetString($b) -match '[^\x00-\x7F]') { $bad += $rel }
    }
    if ($bad.Count -gt 0) {
        throw ("{0} PowerShell file(s) have non-ASCII bytes but no UTF-8 BOM (save as UTF-8 with BOM): {1}" -f $bad.Count, ($bad -join ', '))
    }
}

# --- BT0b schema ---
Invoke-Case 'BT0b schema' {
    $required = @{
        'health.schema.json'        = @('ok', 'grok_installed', 'logged_in', 'grok_version', 'worker_count', 'leader_up', 'machine', 'watcher_up', 'last_seen')
        'overlay.schema.json'       = @('workers')
        'status.schema.json'        = @('sessionId', 'kind', 'state', 'cwd', 'title', 'updatedAt')
        'completion.schema.json'    = @('id', 'session', 'status', 'summary', 'evidence', 'needs_human', 'next_suggested')
        'prompt-packet.schema.json' = @('id', 'from', 'to_session', 'goal', 'constraints', 'success', 'reply_channel')
    }
    if ($required.Count -ne 5) { throw 'expected five schemas' }
    foreach ($name in $required.Keys) {
        $path = Join-Path $schemaDir $name
        if (-not (Test-Path $path)) { throw "missing $name" }
        $s = Get-Content $path -Raw | ConvertFrom-Json
        if (-not $s.required) { throw "$name has no required keys" }
        foreach ($k in $required[$name]) {
            if (@($s.required) -notcontains $k) { throw "$name missing required $k" }
        }
    }
}

# --- BT0c no-sendkeys ---
Invoke-Case 'BT0c no-sendkeys' {
    $hits2 = @(Get-ChildItem (Join-Path $RepoRoot 'src') -Recurse -Include *.ps1, *.psm1, *.psd1 |
        Select-String -Pattern 'SendKeys|UIAutomation|WScript\.Shell')
    if ($hits2.Count -gt 0) {
        throw ($hits2 | ForEach-Object { "$($_.Path):$($_.LineNumber) $($_.Line.Trim())" }) -join '; '
    }
}

# --- BT0d oneshot ---
Invoke-Case 'BT0d oneshot' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $r = Start-BobWorker -Cwd $cwd -Prompt 'PONG' -Profile generic -Title 'pong'
    if (-not $r.ok) { throw "start not ok: $($r.completion | ConvertTo-Json -Compress)" }
    $last = Get-BobResult -SessionId $r.sessionId
    if ($last.result -ne 'PONG') { throw "last_result.result=$($last.result)" }
    $compPath = Join-Path $bridgeRoot "workers\$($r.sessionId)\outbox\completion.json"
    if (-not (Test-Path $compPath)) { throw "missing $compPath" }
    $comp = Get-Content $compPath -Raw | ConvertFrom-Json
    if ($comp.status -ne 'ok') { throw "completion.status=$($comp.status)" }
    $workers = Get-BobWorkers
    if (@($workers).Count -ne 1) { throw "overlay count=$(@($workers).Count)" }
    if (-not $r.processGone) { throw 'process not gone' }
}

# --- BT0e resume ---
Invoke-Case 'BT0e resume' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $r = Start-BobWorker -Cwd $cwd -Prompt 'PONG' -Profile generic
    $id = $r.sessionId
    Remove-Module BobBridge -Force
    $env:BOB_BRIDGE_HOME = $bridgeRoot
    $env:BOB_GROK_EXE = $fake
    Import-Module $src -Force
    $s = Send-BobPrompt -SessionId $id -Prompt 'PONG2'
    if (-not $s.ok) { throw "send not ok: $($s | ConvertTo-Json -Compress)" }
    if (-not $s.resumed) { throw 'resumed=false' }
    $last = Get-BobResult -SessionId $id
    if ($last.result -ne 'PONG2') { throw "result=$($last.result)" }
    if (-not $last.resumed) { throw 'last_result.resumed=false' }
}

# --- BT0f cwd ---
Invoke-Case 'BT0f cwd' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $r1 = Start-BobWorker -Cwd $cwd -Prompt 'PONG' -Profile generic
    if (-not $r1.ok) { throw 'first start failed' }
    $r2 = Start-BobWorker -Cwd $cwd -Prompt 'PONG' -Profile generic
    if ($r2.ok) { throw 'second start should fail' }
    if ($r2.error -ne 'worker_exists') { throw "error=$($r2.error)" }
    $workers = Get-BobWorkers
    if (@($workers).Count -ne 1) { throw "overlay count=$(@($workers).Count)" }
}

# --- BT0g profile ---
Invoke-Case 'BT0g profile' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $r = Start-BobWorker -Cwd $cwd -Prompt 'PONG' -Profile formprep -WhatIfArgv
    $text = [IO.File]::ReadAllText($r.argvPath)
    if ($text -notmatch '--rules') { throw 'formprep argv missing --rules' }
    if ($text -match '--always-approve') { throw 'formprep argv has --always-approve' }
    if ($text -match '--yolo') { throw 'formprep argv has --yolo' }
    $g = Start-BobWorker -Cwd $cwd -Prompt 'PONG' -Profile generic -WhatIfArgv -Force
    $gtext = [IO.File]::ReadAllText($g.argvPath)
    if ($gtext -notmatch 'SimonBarnett/agentic_build') { throw 'build agent argv must pass agentic_build skills' }
}

# --- BT0h synth ---
Invoke-Case 'BT0h synth' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $fail = Start-BobWorker -Cwd $cwd -Prompt 'FAIL' -Profile generic
    if ($fail.ok) { throw 'FAIL should not be ok' }
    if ($fail.completion.status -ne 'failed') { throw "status=$($fail.completion.status)" }
    if ($fail.completion.status -eq 'ok') { throw 'failed completion marked ok' }
    Stop-BobWorker -SessionId $fail.sessionId | Out-Null

    $cwd2 = Join-Path $bridgeRoot 'cwd2'
    New-Item -ItemType Directory -Force -Path $cwd2 | Out-Null
    $empty = Start-BobWorker -Cwd $cwd2 -Prompt 'EMPTY' -Profile generic
    if ($empty.completion.status -ne 'blocked') { throw "EMPTY status=$($empty.completion.status)" }
    if ($empty.ok) { throw 'EMPTY should not be ok' }
}

# --- BT0i audit ---
Invoke-Case 'BT0i audit' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $null = Start-BobWorker -Cwd $cwd -Prompt 'PONG' -Profile generic
    $audit = Join-Path $bridgeRoot 'audit.jsonl'
    if (-not (Test-Path $audit)) { throw 'audit.jsonl missing' }
    $lines = @(Get-Content $audit | Where-Object { $_.Trim() })
    if ($lines.Count -lt 1) { throw 'audit.jsonl empty' }
    $row = $lines[-1] | ConvertFrom-Json
    if (-not $row.sha256) { throw 'sha256 missing' }
    if ($row.sha256.Length -ne 64) { throw "sha256 length $($row.sha256.Length)" }
    $raw = Get-Content $audit -Raw
    if ($raw -match 'XAI_API_KEY') { throw 'audit contains XAI_API_KEY' }
    $ref = Start-BobWorker -Cwd (Join-Path $bridgeRoot 'other') -Prompt 'password=secret' -Profile generic -Force
    if ($ref.error -ne 'refuse') { throw "password prompt not refused: $($ref.error)" }
    $mention = Start-BobWorker -Cwd $cwd -Prompt 'Do not set or request XAI_API_KEY' -Profile generic -WhatIfArgv -Force
    if ($mention.error -eq 'refuse') { throw 'instructional XAI_API_KEY mention was refused' }
    if (-not $mention.ok) { throw "mention whatif failed: $($mention | ConvertTo-Json -Compress)" }
    $export = Start-BobWorker -Cwd $cwd -Prompt 'export XAI_API_KEY deadbeef' -Profile generic -Force
    if ($export.error -ne 'refuse') { throw "export XAI_API_KEY not refused: $($export.error)" }
}

# --- BT0j grokbot hermetic ---
Invoke-Case 'BT0j grokbot hermetic' {
    param($bridgeRoot)
    $agents = @(Get-BobAgents)
    if ($agents.Count -ne 0) { throw "Fake-Grok must not list live agents: $($agents.Count)" }
    $cwd = Join-Path $bridgeRoot 'cwd'
    $r = Start-BobWorker -Cwd $cwd -Prompt 'PONG' -Profile generic -Agent Bob
    if (-not $r.ok) { throw "fake -Agent Bob should still oneshot: $($r | ConvertTo-Json -Compress)" }
    if ($r.transport -eq 'grokbot') { throw 'Fake-Grok must not use grokbot transport' }
    $last = Get-BobResult -SessionId $r.sessionId
    if ($last.result -ne 'PONG') { throw "result=$($last.result)" }
}

# --- BT0k fleet fake store ---
Invoke-Case 'BT0k fleet fake store' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $reg = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    if ($reg.id -ne 'testhost') { throw "id=$($reg.id)" }
    if ($reg.mssql -ne 'integrated') { throw 'mssql not integrated' }
    $machines = @(Get-BobMachines)
    if ($machines.Count -lt 1) { throw 'no machines' }

    $bad = Start-BobBuild -Machine testhost -Cwd $cwd -Goal 'password=secret' -Profile generic
    if ($bad.error -ne 'refuse') { throw "secret goal not refused: $($bad.error)" }

    $q = Start-BobBuild -Machine testhost -Cwd $cwd -Goal 'PONG' -Profile generic -Success 'echo' -Constraints @('Do not set or request XAI_API_KEY')
    if (-not $q.ok) { throw "enqueue failed $($q | ConvertTo-Json -Compress)" }
    $inbox = Get-BobBuild -JobId $q.jobId
    if ($inbox.lane -ne 'inbox') { throw "lane=$($inbox.lane)" }

    $watch = Join-Path $RepoRoot 'tools\Watch-BobJobs.ps1'
    $env:BOB_MACHINE_ID = 'testhost'
    & $watch -Once -RepoRoot $RepoRoot | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Watch-BobJobs exit $LASTEXITCODE" }

    $done = Get-BobBuild -JobId $q.jobId
    if ($done.lane -ne 'outbox') { throw "expected outbox, lane=$($done.lane)" }
    if ($done.state -ne 'done') { throw "state=$($done.state)" }
    if (-not $done.completion -or $done.completion.status -ne 'ok') { throw 'completion not ok' }
    $jobAudit = Join-Path $bridgeRoot 'job-audit.jsonl'
    if (-not (Test-Path $jobAudit)) { throw 'job-audit.jsonl missing after outbox' }
    $jaLines = @(Get-Content $jobAudit | Where-Object { $_.Trim() })
    if ($jaLines.Count -lt 1) { throw 'job-audit.jsonl empty' }
    $ja = $jaLines[-1] | ConvertFrom-Json
    if ([string]$ja.jobId -ne [string]$q.jobId) { throw "job-audit jobId=$($ja.jobId)" }
    if ([string]$ja.machine -ne 'testhost') { throw "job-audit machine=$($ja.machine)" }
    if (-not $ja.status) { throw 'job-audit status missing' }
    foreach ($f in @('jobId', 'machine', 'fuel', 'model', 'kind', 'prUrl', 'mrbIssue', 'sha', 'status')) {
        if (-not ($ja.PSObject.Properties.Name -contains $f)) { throw "job-audit missing field $f" }
    }

    $q2 = Start-BobBuild -Machine testhost -Cwd $cwd -Goal 'PONG' -Profile generic
    $st = Stop-BobBuild -JobId $q2.jobId
    if (-not $st.ok) { throw 'stop enqueue failed' }
    & $watch -Once -RepoRoot $RepoRoot | Out-Null
    $stopped = Get-BobBuild -JobId $q2.jobId
    if ($stopped.state -ne 'stopped') { throw "expected stopped, state=$($stopped.state)" }

    $drive = Register-BobMachine -Id testhost -CwdRoots 'C:'
    $root = [string]@($drive.cwdRoots)[0]
    if ($root -ne 'C:\') { throw "drive-root cwdRoots=$root" }

    $h = Get-BobHealth
    if ($null -eq $h.watcher_up) { throw 'health.watcher_up missing' }
    if (-not ($h.PSObject.Properties.Name -contains 'last_seen')) { throw 'health.last_seen missing' }

    $watchSrc = Get-Content $watch -Raw
    if ($watchSrc -match '(?m)^\s*\$mid\s*=\s*Get-ThisMachineId\b') { throw 'Watch-BobJobs must not call private Get-ThisMachineId' }
    if ($watchSrc -match 'catch\s*\{\s*Write-Error') { throw 'Watch-BobJobs catch must not Write-Error (kills poller under ErrorAction Stop)' }
    if ($watchSrc -notmatch '(?s)if \(\$Once\).+while \(\$true\).+Invoke-BobFleetTick') {
        throw 'idle Watch-BobJobs loop must Invoke-BobFleetTick so lastSeen stays fresh'
    }
    $tw = Get-Content (Join-Path $RepoRoot 'src\Private\Test-BobWatcher.ps1') -Raw
    if ($tw -match 'Watch-BobTray') { throw 'watcher_up must not treat Watch-BobTray as the pull worker' }
}

# --- BT0l tray hover (weekly remaining + machine tiles T1-T7) ---
Invoke-Case 'BT0l tray hover' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot

    $h = Get-BobTrayHover
    if ($null -ne $h.remaining_pct) { throw "idle remaining_pct=$($h.remaining_pct) expected null (no weekly log)" }
    if ([string]$h.title -ne '#Bobiverse (testhost)') { throw "title=$($h.title)" }
    if ([string]$h.scope -ne 'local-store') { throw "scope=$($h.scope)" }
    if ([string]$h.machine -ne 'testhost') { throw "machine=$($h.machine)" }
    if ([string]$h.body -match '(?i)no fleet jobs running') { throw "idle body still says no fleet jobs: $($h.body)" }
    if (@($h.cursor_pools).Count -ne 3) { throw "idle cursor_pools count=$(@($h.cursor_pools).Count) expected 3 Cursor spending groups" }
    if (@($h.cursor_groups).Count -lt 3) { throw "idle cursor_groups count=$(@($h.cursor_groups).Count) expected >=3" }
    if ([string]$h.jobs_text -notmatch '(?m)^[ ]+grok chat') { throw "idle jobs_text missing grok chat group: $($h.jobs_text)" }
    if ([string]$h.jobs_text -notmatch '(?m)^[ ]+high cost models') { throw "idle jobs_text missing high cost models group: $($h.jobs_text)" }
    if ([string]$h.jobs_text -notmatch '(?m)^[ ]+low cost models') { throw "idle jobs_text missing low cost models group: $($h.jobs_text)" }
    if ([string]$h.jobs_text -match '(?m)^[ ]+Smart Catalogue  (grok chat|high cost models|low cost models)') {
        throw "xAI seat labels must not prefix Cursor spending bars: $($h.jobs_text)"
    }
    if ([string]$h.jobs_text -notmatch '(?m)^[ ]{0,2}testhost \(') { throw "idle jobs_text missing testhost tile: $($h.jobs_text)" }
    if ([string]$h.account_name -ne 'low cost models') { throw "account_name=$($h.account_name)" }
    if ($null -ne $h.account_remaining_pct) { throw 'cursor account must not copy Grok Build xAI remaining' }
    if ([string]$h.jobs_text -notmatch 'no jobs') { throw "idle jobs_text missing no jobs: $($h.jobs_text)" }
    $hoverSrc = Get-Content (Join-Path $RepoRoot 'src\Public\Get-BobTrayHover.ps1') -Raw
    if ($hoverSrc -notmatch 'Get-BobLiveGrokAgents') { throw 'hover must include live grok.exe even if Bob did not start it' }
    $env:BOB_SKIP_LIVE_GROK = '1'
    if (@(Get-BobLiveGrokAgents).Count -ne 0) { throw 'BOB_SKIP_LIVE_GROK must suppress live grok scan' }
    if ([string]$h.remaining_kind -ne 'weekly') { throw "kind=$($h.remaining_kind)" }
    if ([string]$h.body -notmatch 'weekly remaining') { throw "body missing weekly remaining: $($h.body)" }
    if ([string]$h.body -match '(?i)context remaining') { throw "body still says context remaining: $($h.body)" }
    if ([string]$h.title -match '(?i)Bob \(') { throw "title branded as one machine: $($h.title)" }

    $paint = Get-BobTrayBarPaint -RemainingPct $h.remaining_pct -BarWidth 392
    if ($paint.known) { throw 'null remaining must be unknown' }
    if ($paint.show_track) { throw 'null remaining must hide track' }
    if ($paint.show_fill) { throw 'null remaining must not fill' }
    if ($null -ne $paint.fill_width) { throw "null remaining fill_width=$($paint.fill_width) must not be numeric (would look depleted)" }
    if ($paint.pulse) { throw 'must not pulse when remaining unknown' }
    if ($paint.caption -notmatch 'Weekly remaining') { throw "caption=$($paint.caption)" }
    if ($paint.caption -notmatch 'n/a') { throw "caption=$($paint.caption)" }

    $zero = Get-BobTrayBarPaint -RemainingPct 0 -BarWidth 392
    if (-not $zero.known) { throw '0% weekly remaining must be known' }
    if (-not $zero.show_track) { throw '0% must show empty track' }
    if ($zero.show_fill) { throw '0% must not draw a fill' }
    if ($zero.fill_width -ne 0) { throw "0% fill_width=$($zero.fill_width)" }
    if (-not $zero.pulse) { throw '0% weekly remaining must pulse' }
    if ([int]$zero.fill_r -le [int]$zero.fill_g) { throw "0% bar must be redder than green r=$($zero.fill_r) g=$($zero.fill_g)" }

    $full = Get-BobTrayBarPaint -RemainingPct 100 -BarWidth 392
    if ([int]$full.fill_g -le [int]$full.fill_r) { throw "100% bar must be greener than red r=$($full.fill_r) g=$($full.fill_g)" }
    if ($full.fill_width -le 0) { throw '100% must fill' }

    $mid = Get-BobTrayBarPaint -RemainingPct 50 -BarWidth 392
    if ($mid.fill_width -le 0) { throw "50% fill_width=$($mid.fill_width)" }
    if ($mid.pulse) { throw '50% must not pulse' }
    if ($mid.caption -notmatch 'Weekly remaining') { throw "50% caption=$($mid.caption)" }

    $nine = Get-BobTrayBarPaint -RemainingPct 9 -BarWidth 392
    if (-not $nine.show_fill) { throw '9% must show fill (drain as used, remaining fills left)' }
    if ($nine.fill_width -le 0) { throw "9% fill_width=$($nine.fill_width)" }
    if (-not $nine.pulse) { throw '9% weekly remaining must pulse' }

    $low = Get-BobTrayBarPaint -RemainingPct 5 -BarWidth 392
    if (-not $low.pulse) { throw '5% must pulse' }

    $emptyStr = Get-BobTrayBarPaint -RemainingPct '' -BarWidth 392
    if ($null -ne $emptyStr.fill_width) { throw 'empty-string remaining must not fill' }
    if ($emptyStr.pulse) { throw 'empty-string remaining must not pulse' }

    $akNone = Get-BobTrayAlertKind -Alerts @() -RemainingPct $null
    if ($akNone -ne 'none') { throw "alert=$akNone" }
    $akWeek = Get-BobTrayAlertKind -Alerts @() -RemainingPct 5
    if ($akWeek -ne 'weekly') { throw "alert=$akWeek" }
    $akWatch = Get-BobTrayAlertKind -Alerts @('ACTION_REQUIRED: watcher_down watcher_up=False') -RemainingPct 5
    if ($akWatch -ne 'watcher') { throw "alert=$akWatch" }
    $akStall = Get-BobTrayAlertKind -Alerts @('ACTION_REQUIRED: agent_stall Bob idle_sec=900') -RemainingPct $null
    if ($akStall -ne 'stall') { throw "alert=$akStall" }

    $weekLog = Join-Path $bridgeRoot 'weekly.jsonl'
    $weekLine = '{"ts":"2026-09-19T12:00:00Z","src":"shell","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":91.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-09-26T00:00:00Z"}}}}'
    [IO.File]::WriteAllText($weekLog, $weekLine + [Environment]::NewLine)
    $env:BOB_WEEKLY_LOG = $weekLog
    $w = Get-BobWeeklyRemaining -LogPath $weekLog
    if ($null -eq $w) { throw 'weekly parser returned null for 91% used' }
    if ([int]$w.remaining_pct -ne 9) { throw "91% used remaining=$($w.remaining_pct) expected 9" }
    $hw = Get-BobTrayHover
    if ([int]$hw.remaining_pct -ne 9) { throw "hover remaining_pct=$($hw.remaining_pct) expected 9 from weekly log" }
    if ([string]$hw.remaining_kind -ne 'weekly') { throw "kind=$($hw.remaining_kind)" }
    if ([string]$hw.body -notmatch 'weekly remaining  9%') { throw "body missing 9% weekly: $($hw.body)" }
    if ([string]$hw.short.Length -gt 63) { throw "short exceeds 63: $($hw.short)" }
    $pw = Get-BobTrayBarPaint -RemainingPct $hw.remaining_pct -BarWidth 392
    if ($pw.fill_width -le 0) { throw '9% weekly remaining must paint a fill' }
    if ($pw.caption -notmatch '9%') { throw "9% caption=$($pw.caption)" }

    $badWeek = Join-Path $bridgeRoot 'weekly-noperiod.jsonl'
    [IO.File]::WriteAllText($badWeek, '{"ts":"2026-09-19T12:00:00Z","msg":"billing: fetched credits config","ctx":{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY"}}}}' + [Environment]::NewLine)
    $wn = Get-BobWeeklyRemaining -LogPath $badWeek
    if ($null -ne $wn) { throw 'missing creditUsagePercent must be n/a, not invented' }

    $monthLog = Join-Path $bridgeRoot 'weekly-monthly.jsonl'
    [IO.File]::WriteAllText($monthLog, '{"ts":"2026-09-19T12:00:00Z","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":10.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_MONTHLY"}}}}' + [Environment]::NewLine)
    $wm = Get-BobWeeklyRemaining -LogPath $monthLog
    if ($null -ne $wm) { throw 'monthly creditUsagePercent must not be reported as weekly remaining' }

    $noType = Join-Path $bridgeRoot 'weekly-notype.jsonl'
    [IO.File]::WriteAllText($noType, '{"ts":"2026-09-19T12:00:00Z","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":10.0}}}' + [Environment]::NewLine)
    $wt = Get-BobWeeklyRemaining -LogPath $noType
    if ($null -ne $wt) { throw 'creditUsagePercent without weekly period type must be n/a' }

    $env:BOB_WEEKLY_LOG = $null

    $gitCwd = Join-Path $bridgeRoot 'irc-repo'
    New-Item -ItemType Directory -Force -Path $gitCwd | Out-Null
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { throw 'git required for owner/repo job-line test' }
    & git -C $gitCwd init -q
    & git -C $gitCwd remote add origin https://github.com/SimonBarnett/agentic_irc.git

    $jobId = '9f96bc0e-1111-2222-3333-444455556666'
    $runDir = Join-Path $bridgeRoot 'fleet\running\testhost'
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    $job = [pscustomobject]@{
        id        = $jobId
        machine   = 'testhost'
        cwd       = $gitCwd
        claimedAt = [DateTime]::UtcNow.ToString('o')
        state     = 'running'
    }
    [IO.File]::WriteAllText((Join-Path $runDir ($jobId + '.json')), ($job | ConvertTo-Json -Depth 6))

    $h2 = Get-BobTrayHover
    if ($h2.job_count -ne 1) { throw "job_count=$($h2.job_count)" }
    if ([string]$h2.title -ne '#Bobiverse (testhost)') { throw "running title=$($h2.title)" }
    if ([string]$h2.body -match '(?i)no fleet jobs running') { throw "running body says no fleet jobs: $($h2.body)" }
    if ([string]$h2.jobs_text -notmatch 'SimonBarnett/agentic_irc') { throw "jobs_text missing owner/repo: $($h2.jobs_text)" }
    if ([string]$h2.jobs_text -match '(?i)7e8797e|[0-9a-f]{40}') { throw "jobs_text looks like SHA: $($h2.jobs_text)" }
    $row = @($h2.jobs)[0]
    if ([string]$row.repo -ne 'SimonBarnett/agentic_irc') { throw "repo=$($row.repo)" }
    if ([string]$h2.jobs_text -notmatch '(?m)^[ ]{0,2}testhost \(') { throw "running jobs_text missing testhost tile" }
    if ($null -ne $h2.remaining_pct) { throw 'running without weekly log must keep remaining_pct null' }
    $paint2 = Get-BobTrayBarPaint -RemainingPct $h2.remaining_pct -BarWidth 392
    if ($null -ne $paint2.fill_width) { throw 'running without weekly log must not set fill_width' }

    $shaCwd = Join-Path $bridgeRoot '7e8797eabcdef'
    New-Item -ItemType Directory -Force -Path $shaCwd | Out-Null
    $job2Id = 'aaaaaaaa-1111-2222-3333-444455556666'
    $job2 = [pscustomobject]@{
        id        = $job2Id
        machine   = 'testhost'
        cwd       = $shaCwd
        claimedAt = [DateTime]::UtcNow.ToString('o')
        state     = 'running'
    }
    [IO.File]::WriteAllText((Join-Path $runDir ($job2Id + '.json')), ($job2 | ConvertTo-Json -Depth 6))
    $h3 = Get-BobTrayHover
    $shaRow = @($h3.jobs) | Where-Object { $_.id -eq $job2Id } | Select-Object -First 1
    if (-not $shaRow) { throw 'missing SHA-cwd job row' }
    if ([string]$shaRow.repo -match '(?i)^[0-9a-f]{7,40}$') { throw "SHA cwd leaked as repo=$($shaRow.repo)" }
    if ([string]$h3.jobs_text -match '7e8797eabcdef') { throw "jobs_text shows SHA leaf: $($h3.jobs_text)" }

    $macDir = Join-Path $bridgeRoot 'fleet\machines'
    [IO.File]::WriteAllText((Join-Path $macDir 'otherhost.json'), '{"id":"otherhost"}')
    $otherGit = Join-Path $bridgeRoot 'formprep-repo'
    New-Item -ItemType Directory -Force -Path $otherGit | Out-Null
    & git -C $otherGit init -q
    & git -C $otherGit remote add origin git@github.com:SimonBarnett/FormPrep.git
    $otherId = 'bbbbbbbb-1111-2222-3333-444455556666'
    $otherDir = Join-Path $bridgeRoot 'fleet\running\otherhost'
    New-Item -ItemType Directory -Force -Path $otherDir | Out-Null
    $otherJob = [pscustomobject]@{
        id        = $otherId
        machine   = 'otherhost'
        cwd       = $otherGit
        claimedAt = [DateTime]::UtcNow.ToString('o')
        state     = 'running'
    }
    [IO.File]::WriteAllText((Join-Path $otherDir ($otherId + '.json')), ($otherJob | ConvertTo-Json -Depth 6))
    $qId = 'cccccccc-1111-2222-3333-444455556666'
    $qDir = Join-Path $bridgeRoot 'fleet\inbox\testhost'
    New-Item -ItemType Directory -Force -Path $qDir | Out-Null
    $qJob = [pscustomobject]@{
        id        = $qId
        machine   = 'testhost'
        cwd       = $gitCwd
        createdAt = [DateTime]::UtcNow.ToString('o')
        state     = 'queued'
    }
    [IO.File]::WriteAllText((Join-Path $qDir ($qId + '.json')), ($qJob | ConvertTo-Json -Depth 6))
    $h4 = Get-BobTrayHover
    if ([string]$h4.title -ne '#Bobiverse (testhost)') { throw "multi-machine title=$($h4.title)" }
    if ([string]$h4.jobs_text -notmatch '(?m)^[ ]{0,2}testhost \(') { throw "multi jobs_text missing testhost tile: $($h4.jobs_text)" }
    if ([string]$h4.jobs_text -notmatch '(?m)^[ ]{0,2}otherhost \(') { throw "multi jobs_text missing otherhost tile: $($h4.jobs_text)" }
    if ([string]$h4.jobs_text -notmatch 'SimonBarnett/FormPrep') { throw "otherhost missing owner/repo: $($h4.jobs_text)" }
    $idxThis = ([string]$h4.jobs_text).IndexOf("testhost")
    $idxPeer = ([string]$h4.jobs_text).IndexOf("otherhost")
    if ($idxThis -lt 0 -or $idxPeer -lt 0 -or $idxThis -gt $idxPeer) { throw "this host tile must be first: $($h4.jobs_text)" }
    $testhostBlock = ([string]$h4.jobs_text -split '(?m)^otherhost')[0]
    $runIdx = $testhostBlock.IndexOf('START')
    $qIdx = $testhostBlock.IndexOf('QUEUED')
    if ($runIdx -lt 0 -or $qIdx -lt 0 -or $runIdx -gt $qIdx) { throw "testhost must list START before QUEUED: $testhostBlock" }
    if ([string]$h4.jobs_text -match 'other hosts not in this store') { throw 'peer tiles present so must not claim other hosts missing' }
    $macIds = @($h4.machines | ForEach-Object { [string]$_.id })
    if ($macIds[0] -ne 'testhost') { throw "machines[0]=$($macIds[0]) expected testhost" }
    if ($macIds -notcontains 'otherhost') { throw 'machines missing otherhost' }

    $peerHome = Join-Path $bridgeRoot 'peer-marchhare'
    $peerRun = Join-Path $peerHome 'fleet\running\marchhare'
    New-Item -ItemType Directory -Force -Path $peerRun | Out-Null
    $peerGit = Join-Path $bridgeRoot 'peek-repo'
    New-Item -ItemType Directory -Force -Path $peerGit | Out-Null
    & git -C $peerGit init -q
    & git -C $peerGit remote add origin https://github.com/SimonBarnett/agentic_build.git
    $freshSeen = [DateTime]::UtcNow.ToString('o')
    [IO.File]::WriteAllText((Join-Path $peerHome 'machine.json'), (@{ id = 'marchhare'; lastSeen = $freshSeen } | ConvertTo-Json))
    $peerJobId = 'dddddddd-1111-2222-3333-444455556666'
    $peerJob = [pscustomobject]@{
        id        = $peerJobId
        machine   = 'marchhare'
        cwd       = $peerGit
        repo      = 'SimonBarnett/agentic_build'
        claimedAt = $freshSeen
        state     = 'running'
    }
    [IO.File]::WriteAllText((Join-Path $peerRun ($peerJobId + '.json')), ($peerJob | ConvertTo-Json -Depth 6))

    $staleHome = Join-Path $bridgeRoot 'peer-stale'
    New-Item -ItemType Directory -Force -Path (Join-Path $staleHome 'fleet\running\ce-priority-dev1') | Out-Null
    $oldSeen = [datetime]::UtcNow.AddHours(-6).ToString('o')
    [IO.File]::WriteAllText((Join-Path $staleHome 'machine.json'), (@{ id = 'ce-priority-dev1'; lastSeen = $oldSeen } | ConvertTo-Json))

    $deadHome = Join-Path $bridgeRoot 'peer-missing\does-not-exist'
    $regPath = Join-Path $bridgeRoot 'fleet\registry.json'
    $regObj = [ordered]@{
        staleAfterSec = 900
        peekTimeoutMs = 2000
        machines      = @(
            [ordered]@{ id = 'testhost'; hostname = 'testhost' },
            [ordered]@{ id = 'marchhare'; peekRoot = $peerHome },
            [ordered]@{ id = 'ionos'; peekRoot = $deadHome },
            [ordered]@{ id = 'ce-priority-dev1'; peekRoot = $staleHome }
        )
    }
    [IO.File]::WriteAllText($regPath, ($regObj | ConvertTo-Json -Depth 6))

    $h5 = Get-BobTrayHover
    if ([string]$h5.title -ne '#Bobiverse (testhost)') { throw "registry title=$($h5.title)" }
    if ([string]$h5.scope -ne 'fleet-peek') { throw "scope=$($h5.scope) expected fleet-peek" }
    if (-not $h5.peer_peek) { throw 'peer_peek should be true when registry has peers' }
    $txt = [string]$h5.jobs_text
    if ($txt -notmatch '(?m)grok chat') { throw "h5 missing Cursor spending groups: $txt" }
    if ($txt -notmatch '(?m)^[ ]{0,2}testhost \(') { throw "h5 missing testhost: $txt" }
    if ($txt -notmatch '(?m)^[ ]{0,2}otherhost \(') { throw "h5 missing otherhost: $txt" }
    if ($txt -notmatch '(?m)^[ ]{0,2}marchhare\b') { throw "h5 missing marchhare: $txt" }
    if ($txt -notmatch '(?m)^[ ]{0,2}ionos\b') { throw "h5 missing ionos: $txt" }
    if ($txt -notmatch '(?m)^[ ]{0,2}ce-priority-dev1\b') { throw "h5 missing ce-priority-dev1: $txt" }
    if ($txt -match 'other hosts not in this store') { throw 'registry peers present so must not claim other hosts missing' }
    if ($txt -notmatch '(?m)^[ ]{0,2}marchhare(?:  -  [^\r\n(]+)? \([^)]+\)\r?\n(?:[ ]+fuels:[^\r\n]+\r?\n)?[ ]+(?:START|QUEUED)[^\r\n]*SimonBarnett/agentic_build') { throw "marchhare peek missing nested owner/repo: $txt" }
    if ($txt -match '(?m)^marchhare\r?\n  unreachable') { throw "marchhare reachable but marked unreachable: $txt" }
    if ($txt -notmatch '(?m)^[ ]{0,2}ionos(?:  -  [^\r\n(]+)? \(') { throw "ionos missing MACHINENAME (pct) heading: $txt" }
    if ($txt -notmatch '(?m)^[ ]{0,2}ionos(?:  -  [^\r\n(]+)? \([^)]+\)\r?\n(?:[ ]+fuels:[^\r\n]+\r?\n)?[ ]+not in moot') { throw "ionos must be not in moot: $txt" }
    if ($txt -match '(?m)^ionos\r?\n  unreachable') { throw "do not say unreachable for a box that is not in the moot: $txt" }
    if ($txt -notmatch '(?m)^[ ]{0,2}ce-priority-dev1(?:  -  [^\r\n(]+)? \([^)]+\)\r?\n(?:[ ]+fuels:[^\r\n]+\r?\n)?[ ]+lastSeen stale') { throw "stale peer must say lastSeen stale: $txt" }
    $ids5 = @($h5.machines | ForEach-Object { [string]$_.id })
    if ($ids5[0] -ne 'testhost') { throw "h5 machines[0]=$($ids5[0])" }
    foreach ($need in @('testhost', 'otherhost', 'marchhare', 'ionos', 'ce-priority-dev1')) {
        if ($ids5 -notcontains $need) { throw "h5 machines missing $need : $($ids5 -join ',')" }
    }
    $snapHome = Join-Path $bridgeRoot 'peer-snap'
    $snapPeekDir = Join-Path $snapHome 'fleet\peek'
    New-Item -ItemType Directory -Force -Path $snapPeekDir | Out-Null
    $snapNow = [DateTime]::UtcNow.ToString('o')
    [IO.File]::WriteAllText((Join-Path $snapHome 'machine.json'), (@{ id = 'snapbox'; lastSeen = $snapNow } | ConvertTo-Json))
    $env:BOB_MACHINE_ID = 'snapbox'
    $env:BOB_BRIDGE_HOME = $snapHome
    $null = Register-BobMachine -Id snapbox -CwdRoots $snapHome
    $snapRun = Join-Path $snapHome 'fleet\running\snapbox'
    New-Item -ItemType Directory -Force -Path $snapRun | Out-Null
    $sj1 = [pscustomobject]@{ id = 'eeeeeeee-1111-2222-3333-444455556666'; machine = 'snapbox'; cwd = $gitCwd; repo = 'SimonBarnett/agentic_irc'; claimedAt = $snapNow; state = 'running' }
    $sj2 = [pscustomobject]@{ id = 'ffffffff-1111-2222-3333-444455556666'; machine = 'snapbox'; cwd = $otherGit; repo = 'SimonBarnett/FormPrep'; claimedAt = $snapNow; state = 'running' }
    [IO.File]::WriteAllText((Join-Path $snapRun ($sj1.id + '.json')), ($sj1 | ConvertTo-Json -Depth 6))
    [IO.File]::WriteAllText((Join-Path $snapRun ($sj2.id + '.json')), ($sj2 | ConvertTo-Json -Depth 6))
    $mod = Get-Module BobBridge
    & $mod { Write-BobFleetPeekSnapshot }
    $written = Get-Content (Join-Path $snapPeekDir 'snapbox.json') -Raw
    if ($written -notmatch '"running":\[') { throw "snapshot JSON must keep running as an array: $written" }
    if ($written -match 'eeeeeeee-1111-2222-3333-444455556666 ffffffff') { throw "snapshot collapsed job ids (PS5 property unroll): $written" }
    if ($written -notmatch 'eeeeeeee-1111-2222-3333-444455556666') { throw "snapshot missing job 1: $written" }
    if ($written -notmatch 'ffffffff-1111-2222-3333-444455556666') { throw "snapshot missing job 2: $written" }

    $env:BOB_BRIDGE_HOME = $bridgeRoot
    $env:BOB_MACHINE_ID = 'testhost'
    $regObj.machines += [ordered]@{ id = 'snapbox'; peekRoot = $snapHome }
    [IO.File]::WriteAllText($regPath, ($regObj | ConvertTo-Json -Depth 6))
    $hSnap = Get-BobTrayHover
    $snapTxt = [string]$hSnap.jobs_text
    if ($snapTxt -notmatch '(?m)^[ ]{0,2}snapbox \([^)]+\)\r?\n(?:[ ]+fuels:[^\r\n]+\r?\n)?[ ]+(?:START|QUEUED)[^\r\n]*SimonBarnett/') { throw "snapbox tile missing nested jobs: $snapTxt" }
    if ($snapTxt -notmatch 'SimonBarnett/agentic_irc') { throw "snapbox missing irc job: $snapTxt" }
    if ($snapTxt -notmatch 'SimonBarnett/FormPrep') { throw "snapbox missing FormPrep job: $snapTxt" }
    $snapTile = @($hSnap.machines | Where-Object { [string]$_.id -eq 'snapbox' })[0]
    if ([int]$snapTile.job_count -ne 2) { throw "snapbox job_count=$($snapTile.job_count) expected 2 (PS5 ConvertTo-Json collapse?)" }

    $ionosTile = @($h5.machines | Where-Object { [string]$_.id -eq 'ionos' })[0]
    if ([string]$ionosTile.reach -ne 'not-in-moot') { throw "ionos reach=$($ionosTile.reach)" }
    if ([int]$ionosTile.job_count -ne 0) { throw "ionos job_count=$($ionosTile.job_count) (invented?)" }
    $mhTile = @($h5.machines | Where-Object { [string]$_.id -eq 'marchhare' })[0]
    if ([int]$mhTile.job_count -lt 1) { throw 'marchhare peek job missing' }
    $staleTile = @($h5.machines | Where-Object { [string]$_.id -eq 'ce-priority-dev1' })[0]
    if ([string]$staleTile.reach -ne 'stale') { throw "stale reach=$($staleTile.reach)" }

    $peekDoc = Join-Path $RepoRoot 'docs\bob-fleet-peer-peek.md'
    if (-not (Test-Path $peekDoc)) { throw 'missing docs/bob-fleet-peer-peek.md' }
    $peekRaw = Get-Content $peekDoc -Raw
    if ($peekRaw -notmatch '(?i)winrm') { throw 'peer-peek doc must name WinRM (and reject it)' }
    if ($peekRaw -notmatch 'unreachable') { throw 'peer-peek doc must define unreachable' }

    $traySrc = Get-Content (Join-Path $RepoRoot 'tools\Watch-BobTray.ps1') -Raw
    foreach ($bad in @('No fleet jobs running', 'no fleet jobs running', 'Context remaining')) {
        if ($traySrc.Contains($bad)) { throw "Watch-BobTray still contains stale UI copy: $bad" }
    }
    if ($traySrc -notmatch 'jobs_text') { throw 'Watch-BobTray card must render jobs_text machine tiles' }
    if ($traySrc -notmatch 'Weekly remaining') { throw 'Watch-BobTray must label Weekly remaining' }
    if ($traySrc -notmatch 'Hide-BobTrayCard') { throw 'Watch-BobTray must have an X close (Hide-BobTrayCard)' }
    if ($traySrc -notmatch 'Rebuild-BobTrayTiles') { throw 'Watch-BobTray must paint one weekly bar per machine tile' }
    if ($traySrc -match 'New-BobTrayCursorBitmap') { throw 'Watch-BobTray must not draw a cursor icon on the account bar' }
    if ($traySrc -notmatch 'Clear-BobNativeTip') { throw 'dark card must clear native NotifyIcon tip to avoid double dialog' }
    if ($traySrc -notmatch 'HideTooltipWindows') { throw 'must pop shell tooltips_class32 so native tip does not stack on the card' }
    if ($traySrc -match 'ShowBalloonTip') { throw 'BalloonTip is a second dialog; use the dark card only' }
    if ($traySrc -match 'tip\.Show\(\)') { throw 'do not Form.Show after ShowParkedAt (second dialog)' }
    if ($traySrc -notmatch 'Transparent') { throw 'machine-name label BackColor must be Transparent so it does not cover the bar' }
    if ($traySrc -notmatch 'fill_r') { throw 'Watch-BobTray must use gradient fill_r/fill_g/fill_b' }
    if ($traySrc -notmatch 'Get-BobTrayBarPaint') { throw 'Watch-BobTray paint path does not use Get-BobTrayBarPaint' }
    if ($traySrc -notmatch 'Get-BobTrayBarPaint') { throw 'Watch-BobTray must paint weekly bars via Get-BobTrayBarPaint' }

    # Agents submenu: two watch-seat agents as one menu, desktop-parity icons,
    # grey when not installed, click initialises setup (agent-monitor-setup).
    if ($traySrc -notmatch "Text = 'Agents'") { throw 'Watch-BobTray must add an Agents context-menu item' }
    if ($traySrc -notmatch 'Build-BobTrayAgentsMenu') { throw 'Watch-BobTray must build the Agents submenu (Cursor/Grok)' }
    if ($traySrc -notmatch 'ExtractAssociatedIcon') { throw 'Agents menu icons must match the Desktop shortcut app exe' }
    if ($traySrc -notmatch 'ConvertTo-BobTrayGrayImage') { throw 'not-installed agent must be greyed' }
    if ($traySrc -notmatch 'New-BobTrayAgentBadgeImage') { throw 'missing agent must fall back to branded C/G badge icon' }
    if ($traySrc -notmatch 'Resolve-BobTrayAgentIconExe') { throw 'Grok icon must prefer Grok Bot.exe via Resolve-BobTrayAgentIconExe' }
    if ($traySrc -notmatch 'Get-BobTrayAgentExeCandidates') { throw 'Resolve-BobTrayAgentExe must use candidates helper' }
    if ($traySrc -match 'return \$cands\[0\]') { throw 'Resolve must not return a missing candidate path' }
    if ($traySrc -notmatch 'Matrix33 = 0\.92') { throw 'grey icons must stay visible on dark tip (Matrix33 0.92)' }
    if ($traySrc -notmatch 'Install-AgentMonitor') { throw 'clicking a not-installed agent must initialise setup' }
    if ($traySrc -notmatch 'Watch-AgentHealth\.cmd') { throw 'AgentMonitor readiness still resolves Watch-AgentHealth.cmd' }
    if ($traySrc -notmatch 'Start-BobTrayAgentWatch') { throw 'Agents click must call Start-BobTrayAgentWatch' }
    $watchFn = [regex]::Match($traySrc, '(?s)function Start-BobTrayAgentWatch\s*\{.*?^\}', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $watchFn.Success) { throw 'Start-BobTrayAgentWatch function not found' }
    $watchBody = $watchFn.Value
    if ($watchBody -notmatch '-WatchWorker') { throw 'systray Agents must launch Watch-AgentHealth.ps1 -WatchWorker' }
    if ($watchBody -notmatch '''-New''|"-New"|-New') { throw 'systray Agents must always pass -New (never resume an old session)' }
    if ($watchBody -notmatch '-Model.*auto') { throw 'systray Cursor Agents must pass -Model auto' }
    if ($watchBody -notmatch 'WindowStyle.*,\s*''Hidden''') { throw 'systray Agents watch process must be WindowStyle Hidden' }
    if ($watchBody -match "(?i)-Windows['\`"]?\s*,?\s*['\`"]?off") { throw 'systray Agents must not pass -Windows off (TUI must stay visible)' }
    if ($watchBody -match 'agentMonitorCmd') { throw 'systray Agents must not launch via .cmd (visible -NoExit watch)' }
    if ($watchBody -notmatch 'Watch-AgentHealth\.ps1') { throw 'systray Agents must target Watch-AgentHealth.ps1' }
    if ($watchBody -notmatch 'Test-BobTrayAgentFuelExhausted') { throw 'systray Agents must check fuel before start (Test-BobTrayAgentFuelExhausted)' }
    if ($watchBody -notmatch 'Start-BobTrayProcessWithSessionEnv') { throw 'systray Agents must launch via Start-BobTrayProcessWithSessionEnv' }
    if ($traySrc -notmatch 'Show-BobTraySessionApiKeyDialog') { throw 'empty fuel must offer Show-BobTraySessionApiKeyDialog' }
    if ($traySrc -notmatch 'XAI_API_KEY') { throw 'session Grok key must set child env XAI_API_KEY' }
    if ($traySrc -notmatch 'CURSOR_API_KEY') { throw 'session Cursor key must set child env CURSOR_API_KEY' }
    if ($traySrc -notmatch 'UseShellExecute\s*=\s*\$false') { throw 'session env launch must UseShellExecute=false (child-only env)' }
    if ($traySrc -match "SetEnvironmentVariable\([^\)]*'User'|SetEnvironmentVariable\([^\)]*'Machine'") {
        throw 'must not SetEnvironmentVariable User/Machine for session API keys'
    }
    if ($traySrc -notmatch 'lastFuelSnapshot') { throw 'Update-Hover must cache lastFuelSnapshot for fuel checks' }
    if ($traySrc -notmatch 'Start-BobTrayPlanAgent') { throw 'Plan menu must support Plan starts (Start-BobTrayPlanAgent)' }
    if ($traySrc -notmatch "Text = 'Plan'") { throw 'tray must add a Plan menu' }
    # Plan is a top-level context-menu item, same level as Agents (not nested under Agents).
    if ($traySrc -notmatch 'function Build-BobTrayPlanMenu') { throw 'tray must build the Plan menu via Build-BobTrayPlanMenu' }
    if ($traySrc -notmatch '\[void\]\$menu\.Items\.Add\(\$miPlan\)') { throw 'Plan must be added to the top-level context menu ($menu.Items.Add($miPlan))' }
    $agentsFn = [regex]::Match($traySrc, '(?s)function Build-BobTrayAgentsMenu\s*\{.*?^\}', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $agentsFn.Success) { throw 'Build-BobTrayAgentsMenu function not found' }
    if ($agentsFn.Value -match 'Plan') { throw 'Agents submenu must not contain Plan (Plan is top-level)' }
    $planFn = [regex]::Match($traySrc, '(?s)function Build-BobTrayPlanMenu\s*\{.*?^\}', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $planFn.Success -or $planFn.Value -notmatch "'Grok', 'Cursor'" -or $planFn.Value -notmatch 'Start-BobTrayPlanAgent') {
        throw 'Build-BobTrayPlanMenu must offer Grok / Cursor wired to Start-BobTrayPlanAgent'
    }
    if ($traySrc -notmatch 'Sync-BobTrayVisionarySkills') { throw 'Plan starts must sync skills-visionary' }
    if ($traySrc -notmatch 'Install-VisionarySkills') { throw 'Plan sync must call tools/Install-VisionarySkills.ps1' }
    if ($traySrc -notmatch '--permission-mode') { throw 'Plan Grok must use --permission-mode plan' }
    if ($traySrc -notmatch '--plan') { throw 'Plan Cursor must pass --plan' }
    if ($traySrc -notmatch 'skills-visionary') { throw 'Plan seats must target skills-visionary' }
    if (-not (Test-Path (Join-Path $RepoRoot 'tools\Install-VisionarySkills.ps1'))) { throw 'missing tools/Install-VisionarySkills.ps1' }
    if ($traySrc -notmatch 'ConvertTo-BobTrayTipVisibleImage') { throw 'agent icons must plate dark exe glyphs for dark tip' }
    $skillAgents = Get-Content (Join-Path $RepoRoot '.grok\skills\agent-monitor-setup\SKILL.md') -Raw
    if ($skillAgents -notmatch '(?i)agents') { throw 'agent-monitor-setup skill must document the Agents menu' }
    if ($skillAgents -notmatch 'Install-AgentMonitor') { throw 'agent-monitor-setup skill must name Install-AgentMonitor.ps1' }
    if (-not (Test-Path (Join-Path $RepoRoot 'tools\Install-AgentMonitor.ps1'))) { throw 'missing tools/Install-AgentMonitor.ps1 setup' }

    $skillTray = Get-Content (Join-Path $RepoRoot '.grok\skills\bob-fleet-tray\SKILL.md') -Raw
    if ($skillTray -notmatch '(?i)weekly remaining') { throw 'bob-fleet-tray skill must document weekly remaining bar' }
    if ($skillTray -notmatch 'creditUsagePercent') { throw 'bob-fleet-tray skill must name creditUsagePercent source' }
    if ($skillTray -notmatch 'Bob Fleet') { throw 'bob-fleet-tray skill must name title Bob Fleet' }
    if ($skillTray -notmatch 'alert:') { throw 'bob-fleet-tray skill must document badge sources' }
    if ($skillTray -notmatch 'not in moot') { throw 'bob-fleet-tray skill must document not-in-moot tiles' }
    if ($skillTray -notmatch 'bobiverse') { throw 'bob-fleet-tray skill must name bobiverse seats' }
    if ($skillTray -notmatch 'marchhare-bugets') { throw 'bob-fleet-tray skill must reject ghost IRC ids' }
    if ($skillTray -notmatch 'lastSeen stale') { throw 'bob-fleet-tray skill must document lastSeen stale' }
    if ($skillTray -notmatch 'bob-fleet-peer-peek') { throw 'bob-fleet-tray skill must point at peer-peek transport doc' }
    $skillBox = Get-Content (Join-Path $RepoRoot '.grok\skills\box-usage\SKILL.md') -Raw
    if ($skillBox -notmatch '(?i)weekly') { throw 'box-usage skill must document weekly vs context' }
    if ($skillBox -notmatch 'creditUsagePercent') { throw 'box-usage skill must name creditUsagePercent source' }
}

# --- BT0m tray tip placement (NC-T01..NC-T03) ---
Invoke-Case 'BT0m tray tip placement' {
    $icon = @{ X = 1880; Y = 1048; Width = 24; Height = 24 }
    $work = @{ X = 0; Y = 0; Width = 1920; Height = 1040 }
    $cursorA = @{ X = 1892; Y = 1060 }
    $p = Get-BobTrayTipPlacement -TipWidth 420 -TipHeight 120 -IconRect $icon -Cursor $cursorA -WorkArea $work
    if ($p.source -ne 'icon') { throw "source=$($p.source) expected icon" }
    if (-not $p.moved) { throw 'first place must set moved' }
    if ($p.x -ne 1484) { throw "icon x=$($p.x) expected 1484 (right-aligned to icon)" }
    if ($p.y -lt 0) { throw "icon y=$($p.y)" }
    if (($p.y + 120) -gt 1040) { throw "icon y=$($p.y) not clamped into work area" }
    $iconX = $p.x
    $iconY = $p.y

    $cursorB = @{ X = 400; Y = 300 }
    $sticky = Get-BobTrayTipPlacement -TipWidth 420 -TipHeight 120 -IconRect $icon -Cursor $cursorB -WorkArea $work -AlreadyVisible $true -CurrentX $iconX -CurrentY $iconY
    if ($sticky.source -ne 'sticky') { throw "already-visible source=$($sticky.source)" }
    if ($sticky.moved) { throw 'already visible must not move' }
    if ($sticky.x -ne $iconX -or $sticky.y -ne $iconY) { throw "sticky moved from $iconX,$iconY to $($sticky.x),$($sticky.y)" }

    $cur = Get-BobTrayTipPlacement -TipWidth 420 -TipHeight 120 -Cursor @{ X = 800; Y = 600 } -WorkArea @{ X = 0; Y = 0; Width = 1920; Height = 1080 }
    if ($cur.source -ne 'cursor') { throw "missing-icon source=$($cur.source)" }
    if ($cur.x -ne 380) { throw "cursor x=$($cur.x) expected 800-420" }
    if ($cur.y -ne 468) { throw "cursor y=$($cur.y) expected 600-120-12" }

    $clamp = Get-BobTrayTipPlacement -TipWidth 420 -TipHeight 120 -Cursor @{ X = 10; Y = 10 } -WorkArea @{ X = 0; Y = 0; Width = 1920; Height = 1080 }
    if ($clamp.x -lt 8 -or $clamp.y -lt 8) { throw "cursor clamp x=$($clamp.x) y=$($clamp.y)" }

    $topBar = Get-BobTrayTipPlacement -TipWidth 420 -TipHeight 120 `
        -IconRect @{ X = 1880; Y = 4; Width = 24; Height = 24 } `
        -Cursor @{ X = 1890; Y = 16 } `
        -WorkArea @{ X = 0; Y = 40; Width = 1920; Height = 1040 }
    if ($topBar.source -ne 'icon') { throw 'top-taskbar must use icon' }
    if ($topBar.y -lt 40) { throw "top-taskbar y=$($topBar.y) should sit in work area below icon" }

    $traySrc = Get-Content (Join-Path $RepoRoot 'tools\Watch-BobTray.ps1') -Raw
    if ($traySrc -notmatch 'Get-BobTrayTipPlacement') { throw 'Watch-BobTray must call Get-BobTrayTipPlacement' }
    if ($traySrc -notmatch 'AlreadyVisible') { throw 'Watch-BobTray must pass AlreadyVisible to placement' }
    if ($traySrc -notmatch '(?s)if \(-not \(Test-BobTrayTipVisible\)\).{0,800}Get-BobTrayTipPlacement') {
        throw 'Get-BobTrayTipPlacement must run only when tip is not visible'
    }
    if ($traySrc -match '\$x = \$pt\.X - \$tip\.Width') { throw 'Watch-BobTray still derives Location from cursor X every move' }
    if ($traySrc -notmatch 'ShowWithoutActivation') { throw 'tip form missing ShowWithoutActivation (NC-T02)' }
    if ($traySrc -notmatch '0x08000000') { throw 'tip form missing WS_EX_NOACTIVATE (NC-T02)' }
    if ($traySrc -notmatch 'Shell_NotifyIconGetRect') { throw 'Watch-BobTray should prefer Shell_NotifyIconGetRect' }
    foreach ($bad in @('Bob fleet', 'No fleet jobs running', 'no fleet jobs running')) {
        if ($traySrc.Contains($bad)) { throw "Watch-BobTray still contains fleet UI copy: $bad" }
    }

    $skillTray = Get-Content (Join-Path $RepoRoot '.grok\skills\bob-fleet-tray\SKILL.md') -Raw
    if ($skillTray -notmatch 'Get-BobTrayTipPlacement') { throw 'bob-fleet-tray skill must name Get-BobTrayTipPlacement' }
    if ($skillTray -notmatch '(?i)already visible') { throw 'bob-fleet-tray skill must document already-visible sticky contract' }
    if ($skillTray -notmatch 'ShowWithoutActivation') { throw 'bob-fleet-tray skill must document ShowWithoutActivation' }
}

# --- BT0n tray tip show (NC-D01 / NC-D02) ---
Invoke-Case 'BT0n tray tip show' {
    $traySrc = Get-Content (Join-Path $RepoRoot 'tools\Watch-BobTray.ps1') -Raw
    if ($traySrc -notmatch 'function Show-BobTrayCard') { throw 'Watch-BobTray missing Show-BobTrayCard' }
    if ($traySrc -match "Show-BobTrayCard -Reason 'hover'") { throw 'MouseMove must not Show-BobTrayCard (hover stacked a second TipForm)' }
    if ($traySrc -match 'Add_MouseMove') { throw 'no hover events: Add_MouseMove must be gone' }
    if ($traySrc -match '\$iconProbe') { throw 'no hover events: iconProbe timer must be gone' }
    if ($traySrc -match '\$hideTip') { throw 'card must stay parked until X; hideTip auto-hide must be gone' }
    if ($traySrc -notmatch "Show-BobTrayCard -Reason 'click'") { throw 'left-click / Status must show the dark card' }
    if ($traySrc -match '(?s)overTip.{0,240}cardClosed = \$false') { throw 'must not rearm hover by clearing cardClosed when leaving the tip' }
    if ($traySrc -match 'function Restore-BobNativeTip') { throw 'must not restore NotifyIcon.Text (white P+ idle chip is the double dialog)' }
    if ($traySrc -match '\$notify\.Text = \$') { throw 'must not assign NotifyIcon.Text from a short P+ string' }
    if ($traySrc -notmatch 'IsDisposed') { throw 'TipForm access must guard IsDisposed' }
    if ($traySrc -notmatch 'TryHide') { throw 'TipForm must TryHide so the TOPMOST HWND is actually hidden' }
    if ($traySrc -notmatch 'SWP_HIDEWINDOW') { throw 'TryHide must use SWP_HIDEWINDOW' }
    if ($traySrc -notmatch 'Initialize-BobTrayTipForm') { throw 'disposed TipForm must recreate via Initialize-BobTrayTipForm' }
    if ($traySrc -notmatch 'LiveCount') { throw 'TipForm must expose LiveCount so only one instance is live' }
    if ($traySrc -match '(?s)function Show-BobTrayCard.{0,500}Update-Hover') { throw 'Show-BobTrayCard must not Get-BobTrayHover/Update-Hover (idle hover would freeze on peer DNS)' }
    $peekSrc = Get-Content (Join-Path $RepoRoot 'src\Private\Get-BobFleetPeek.ps1') -Raw
    if ($peekSrc -notmatch '(?s)function Test-BobHostnameResolves.+Invoke-BobTimed') {
        throw 'Test-BobHostnameResolves must time out DNS so idle tray hover stays instant'
    }
    if ($traySrc -notmatch "Show-BobTrayCard -Reason 'click'") { throw 'left-click must show card (overflow fallback)' }
    if ($traySrc -notmatch 'ShowParkedAt') { throw 'tip form must force-show via ShowParkedAt' }
    if ($traySrc -notmatch 'SetWindowPos') { throw 'tip show must use SetWindowPos' }
    if ($traySrc -notmatch 'SWP_NOACTIVATE') { throw 'SetWindowPos must pass SWP_NOACTIVATE' }
    if ($traySrc -notmatch 'SWP_SHOWWINDOW') { throw 'SetWindowPos must pass SWP_SHOWWINDOW' }
    if ($traySrc -notmatch 'tip show fail') { throw 'Watch-BobTray must log tip show failures' }
    if ($traySrc -notmatch 'tip hide error') { throw 'Watch-BobTray must log tip hide failures' }
    if ($traySrc -notmatch 'iconRectCache') { throw 'icon rect must be cached off the NotifyIcon callback' }
    if ($traySrc -match '(?s)Add_MouseMove\(\{.{0,400}Get-BobNotifyIconRect') {
        throw 'Do not call Shell_NotifyIconGetRect / Get-BobNotifyIconRect from MouseMove'
    }
    if ($traySrc -notmatch '(?s)if \(-not \(Test-BobTrayTipVisible\)\).{0,800}Get-BobTrayTipPlacement') {
        throw 'Get-BobTrayTipPlacement must run only when tip is not visible'
    }
    if ($traySrc -match '\$x = \$pt\.X - \$tip\.Width') { throw 'Watch-BobTray still derives Location from cursor X every move' }
    foreach ($bad in @('Bob fleet', 'No fleet jobs running', 'no fleet jobs running')) {
        if ($traySrc.Contains($bad)) { throw "Watch-BobTray still contains fleet UI copy: $bad" }
    }

    $skillTray = Get-Content (Join-Path $RepoRoot '.grok\skills\bob-fleet-tray\SKILL.md') -Raw
    if ($skillTray -notmatch '(?i)left-click') { throw 'bob-fleet-tray skill must document left-click card show' }
    if ($skillTray -notmatch '(?i)P\+ idle') { throw 'bob-fleet-tray skill must name the native P+ idle chip as the fail' }
    if ($skillTray -notmatch '(?i)Never park') { throw 'bob-fleet-tray skill must forbid parking NotifyIcon.Text' }
    if ($skillTray -notmatch 'ShowParkedAt') { throw 'bob-fleet-tray skill must document ShowParkedAt' }
    if ($skillTray -notmatch '(?i)watch_bob_tray\.log') { throw 'bob-fleet-tray skill must name the tray log' }
    if ($skillTray -notmatch '(?i)hideTip') { throw 'bob-fleet-tray skill must say no hideTip auto-hide' }
    if ($skillTray -notmatch '_Watch-Bobiverse-ionos') { throw 'bob-fleet-tray skill must name _Watch-Bobiverse-ionos Restart path' }
    if ($traySrc -notmatch 'Stop-BobiverseMoot') { throw 'Restart watcher must kill Watch-Bobiverse + bobiverse irc_agent' }
    if ($traySrc -notmatch 'Restart-BobTrayWatcher') { throw 'tray Restart watcher must rejoin #bobiverse' }
    if ($traySrc -notmatch '_Watch-Bobiverse') { throw 'Restart watcher must start _Watch-Bobiverse-<id> wrapper' }
    if ($traySrc -notmatch "Restart watcher") { throw 'right-click menu must include Restart watcher' }
    if (-not (Test-Path (Join-Path $RepoRoot 'tools\_Watch-Bobiverse-ionos.ps1'))) { throw 'missing tools/_Watch-Bobiverse-ionos.ps1' }
    $installSrc = Get-Content (Join-Path $RepoRoot 'tools\Install-BobFleet.ps1') -Raw
    if ($installSrc -notmatch '_Watch-Bobiverse-') { throw 'Install-BobFleet must register _Watch-Bobiverse-<id>' }
    if ($installSrc -notmatch '_Watch-GrokTalk-') { throw 'Install-BobFleet must register _Watch-GrokTalk-<id>' }
    if (-not (Test-Path (Join-Path $RepoRoot 'tools\_Watch-GrokTalk.ps1'))) { throw 'missing tools/_Watch-GrokTalk.ps1' }
    $gtWrapSrc = Get-Content (Join-Path $RepoRoot 'tools\_Watch-GrokTalk.ps1') -Raw
    if ($gtWrapSrc -notmatch 'Watch-GrokTalk\.ps1') { throw '_Watch-GrokTalk must delegate to Watch-GrokTalk.ps1' }

    $onWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
    if (-not $onWindows) {
        Write-Host 'BT0n STA ShowParkedAt smoke skipped (WinForms not available on this host)'
        return
    }
    $sta = {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        if (-not ('BobTrayShowTest.TipForm' -as [type])) {
            $refs = @(
                [System.Windows.Forms.Form].Assembly.Location,
                [System.Drawing.Point].Assembly.Location
            )
            Add-Type -ReferencedAssemblies $refs -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
namespace BobTrayShowTest {
    public static class Shell {
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
        public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
        public const int SW_SHOWNA = 8;
        public const uint SWP_NOSIZE = 0x0001;
        public const uint SWP_NOMOVE = 0x0002;
        public const uint SWP_NOACTIVATE = 0x0010;
        public const uint SWP_SHOWWINDOW = 0x0040;
        public const uint SWP_HIDEWINDOW = 0x0080;
    }
    public class TipForm : Form {
        static TipForm _live;
        public static int LiveCount {
            get { return (_live != null && !_live.IsDisposed) ? 1 : 0; }
        }
        public TipForm() { _live = this; }
        protected override void Dispose(bool disposing) {
            if (object.ReferenceEquals(_live, this)) _live = null;
            base.Dispose(disposing);
        }
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams {
            get {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x08000000;
                cp.ExStyle |= 0x00000080;
                cp.ExStyle |= 0x00000008;
                return cp;
            }
        }
        public bool TryHide() {
            if (this.IsDisposed) return true;
            try {
                if (this.IsHandleCreated) {
                    Shell.SetWindowPos(this.Handle, System.IntPtr.Zero, 0, 0, 0, 0,
                        Shell.SWP_NOSIZE | Shell.SWP_NOMOVE | Shell.SWP_NOACTIVATE | Shell.SWP_HIDEWINDOW);
                }
                if (this.Visible) this.Hide();
                return this.IsDisposed || !this.Visible;
            } catch (System.ObjectDisposedException) { return true; }
        }
        public bool ShowParkedAt(int x, int y) {
            if (this.IsDisposed) return false;
            try {
                this.Left = x; this.Top = y;
                if (!this.IsHandleCreated) this.CreateHandle();
                if (this.IsDisposed) return false;
                Shell.SetWindowPos(this.Handle, Shell.HWND_TOPMOST, x, y, this.Width, this.Height,
                    Shell.SWP_NOACTIVATE | Shell.SWP_SHOWWINDOW);
                if (!this.Visible) this.Visible = true;
                return !this.IsDisposed && this.Visible;
            } catch (System.ObjectDisposedException) { return false; }
        }
    }
}
'@
        }
        $f = New-Object BobTrayShowTest.TipForm
        $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $f.ShowInTaskbar = $false
        $f.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $f.Size = New-Object System.Drawing.Size 200, 80
        $ok = $false
        try {
            $ok = [bool]$f.ShowParkedAt(48, 48)
            if (-not $f.Visible) { throw 'ShowParkedAt did not set Visible' }
            if (-not $ok) { throw 'ShowParkedAt returned false' }
            if ([int][BobTrayShowTest.TipForm]::LiveCount -ne 1) { throw 'LiveCount must be 1 while shown' }
            if (-not $f.TryHide()) { throw 'TryHide failed' }
            $f.Dispose()
            $after = $false
            try { $after = [bool]$f.ShowParkedAt(48, 48) } catch { throw 'ShowParkedAt on disposed form must not throw' }
            if ($after) { throw 'ShowParkedAt on disposed form must return false' }
            $hid = $false
            try { $hid = [bool]$f.TryHide() } catch { throw 'TryHide on disposed form must not throw' }
            if (-not $hid) { throw 'TryHide on disposed form must return true' }
            if ([int][BobTrayShowTest.TipForm]::LiveCount -ne 0) { throw 'LiveCount must be 0 after dispose' }
        }
        finally {
            try { if (-not $f.IsDisposed) { $f.Hide(); $f.Dispose() } } catch { }
        }
        'ok'
    }
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($sta.ToString())
    try {
        $out = $ps.Invoke()
        if ($ps.HadErrors) {
            $err = @($ps.Streams.Error | ForEach-Object { $_.ToString() }) -join '; '
            throw "STA ShowParkedAt smoke failed: $err"
        }
        if ([string]$out[-1] -ne 'ok') { throw "STA ShowParkedAt smoke output=$out" }
    }
    finally {
        $ps.Dispose()
        $rs.Dispose()
    }
}

# --- BT0o bobiverse IRC fallback (no SMB) ---
Invoke-Case 'BT0o bobiverse irc' {
    param($bridgeRoot)
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $env:BOB_MACHINE_ID = 'testhost'
    $pt = ConvertTo-BobIrcPoint ([pscustomobject]@{
            id       = 'ionos'
            weekly   = 4
            running  = 1
            queued   = 0
            lastSeen = [DateTime]::UtcNow.ToString('o')
            jobs     = @([pscustomobject]@{ repo = 'SimonBarnett/agentic_build'; state = 'running' })
        })
    if ($pt -notmatch '^BOB v1 id=ionos') { throw "point=$pt" }
    $parsed = ConvertFrom-BobIrcPoint $pt
    if ($parsed.id -ne 'ionos') { throw "parsed id=$($parsed.id)" }
    if ([int]$parsed.weekly -ne 4) { throw "weekly=$($parsed.weekly)" }
    if ($parsed.jobs[0].repo -ne 'SimonBarnett/agentic_build') { throw 'job repo missing' }

    $ircHome = Join-Path $bridgeRoot 'irc-home'
    $peerDir = Join-Path $ircHome 'bob-peers'
    New-Item -ItemType Directory -Force -Path $peerDir | Out-Null
    $env:BOB_IRC_HOME = $ircHome
    $fresh = [DateTime]::UtcNow.ToString('o')
    $ionosPeer = @{
        ok       = $true
        id       = 'ionos'
        weekly   = 4
        running  = 1
        queued   = 0
        lastSeen = $fresh
        jobs     = @(@{ repo = 'SimonBarnett/agentic_build'; state = 'running'; machine = 'ionos'; id = 'irc-job-1' })
        source   = 'irc'
    } | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $peerDir 'ionos.json'), $ionosPeer)
    $macDir = Join-Path $bridgeRoot 'fleet\machines'
    New-Item -ItemType Directory -Force -Path $macDir | Out-Null
    [IO.File]::WriteAllText((Join-Path $macDir 'ionos.json'), '{"id":"ionos"}')
    $h = Get-BobTrayHover
    $txt = [string]$h.jobs_text
    if ($txt -notmatch '(?m)^[ ]{0,2}ionos\b') { throw "missing ionos tile: $txt" }
    if ($txt -match '(?m)^ionos\r?\n  unreachable') { throw "IRC peer marked unreachable: $txt" }
    if ($txt -notmatch 'SimonBarnett/agentic_build') { throw "IRC jobs missing: $txt" }
    $tile = @($h.machines | Where-Object { [string]$_.id -eq 'ionos' })[0]
    if ([string]$tile.reach -ne 'irc-fallback') { throw "reach=$($tile.reach)" }

    $cfg = Get-Content (Join-Path $RepoRoot 'config\bobiverse.json') -Raw | ConvertFrom-Json
    if ([string]$cfg.channel -ne '#bobiverse') { throw "channel=$($cfg.channel)" }
    if ([string]$cfg.mode -ne 'free') { throw "mode=$($cfg.mode)" }
    if ([string]$cfg.host -ne 'irc.ntsa.uk') { throw "host=$($cfg.host)" }
    if ([string]$cfg.reportUrl -ne 'https://irc.ntsa.uk/bob/v1/report') { throw "reportUrl=$($cfg.reportUrl)" }
    if ([string]$cfg.nicks.flamingo -ne 'bob-flamingo') { throw 'flamingo nick' }
    $installIrc = Get-Content (Join-Path $RepoRoot 'tools\Install-BobIrc.ps1') -Raw
    if ($installIrc -notmatch 'AGENTIC_IRC_PASSWORD') { throw 'Install-BobIrc must load connect.password' }

    $env:BOB_IRC_CONFIG = Join-Path $RepoRoot 'config\bobiverse.json'
    $mootDir = Join-Path $ircHome 'moot'
    New-Item -ItemType Directory -Force -Path $mootDir | Out-Null
    $tx = '1700000000 bob-marchhare POINT BOB v1 id=marchhare weekly=40 running=0 queued=0 lastSeen=2026-09-20T10:00:00Z jobs=-'
    [IO.File]::WriteAllText((Join-Path $mootDir ($cfg.mootId + '.txt')), $tx)
    $got = @(Import-BobIrcPeerTranscript)
    $mh = Read-BobIrcPeer -Id marchhare
    if (-not $mh) { throw 'transcript harvest did not write marchhare peer' }
    if ([int]$mh.weekly -ne 40) { throw "harvest weekly=$($mh.weekly)" }

    $ghostTx = @(
        '1700000001 evil POINT BOB v1 id=marchhare-bugets weekly=9 running=0 queued=0 lastSeen=2026-09-20T10:00:00Z jobs=-'
        '1700000002 bob-flamingo POINT BOB v1 id=bob-flamingo weekly=20 running=0 queued=0 lastSeen=2026-09-20T10:00:00Z jobs=-'
    ) -join "`n"
    [IO.File]::WriteAllText((Join-Path $mootDir ($cfg.mootId + '.txt')), $tx + "`n" + $ghostTx)
    $got2 = @(Import-BobIrcPeerTranscript)
    if ($got2 -contains 'marchhare-bugets') { throw 'ghost IRC id marchhare-bugets must not be harvested' }
    if (Test-Path (Join-Path $peerDir 'marchhare-bugets.json')) { throw 'must not write bob-peers/marchhare-bugets.json' }
    if ($got2 -notcontains 'flamingo') { throw 'id=bob-flamingo POINT must resolve to flamingo' }
    $macDir2 = Join-Path $bridgeRoot 'fleet\machines'
    New-Item -ItemType Directory -Force -Path $macDir2 | Out-Null
    [IO.File]::WriteAllText((Join-Path $macDir2 'marchhare-bugets.json'), '{"id":"marchhare-bugets"}')
    $hSeats = Get-BobTrayHover
    $seatIds = @($hSeats.machines | ForEach-Object { [string]$_.id })
    if ($seatIds -contains 'marchhare-bugets') { throw "ghost tile leaked: $($seatIds -join ',')" }
    foreach ($need in @('flamingo', 'ionos', 'marchhare', 'ce-priority-dev1')) {
        if ($seatIds -notcontains $need) { throw "missing bobiverse seat $need : $($seatIds -join ',')" }
    }
    $ionosSeat = @($hSeats.machines | Where-Object { [string]$_.id -eq 'ionos' })[0]
    if ([string]$ionosSeat.reach -ne 'irc-fallback') { throw "ionos seat reach=$($ionosSeat.reach) expected irc-fallback" }
    if ([string]$hSeats.jobs_text -match 'marchhare-bugets') { throw "jobs_text has ghost: $($hSeats.jobs_text)" }

    $watchBv = Get-Content (Join-Path $RepoRoot 'tools\Watch-Bobiverse.ps1') -Raw
    if ($watchBv -notmatch 'irc\.ntsa\.uk') { throw 'Watch-Bobiverse must require irc.ntsa.uk' }
    if ($watchBv -match 'grok\.exe') { throw 'Watch-Bobiverse must not invoke grok.exe' }
    if ($watchBv -match 'Start-BobWorker|Invoke-BobFleetTick|Send-BobPrompt') { throw 'Watch-Bobiverse must not start a Grok reasoning job' }
    if ($watchBv -notmatch 'Write-BobIrcStatus') { throw 'Watch-Bobiverse must refresh via Write-BobIrcStatus' }
    if ($watchBv -notmatch 'Request-BobIrcBobiversePull') { throw 'Watch-Bobiverse must poll !bobiverse for tray pull' }
    if ($watchBv -notmatch 'Sync-BobDigestWebhookAfterBobiversePull') { throw 'Watch-Bobiverse must POST digest webhook after !bobiverse ingest (#196)' }
    if ($watchBv -notmatch 'SkipDigestWebhook') { throw 'Watch-Bobiverse must defer webhook until after chair digest (#196)' }
    if ($watchBv -match '\$pulled\b') { throw 'Watch must not gate Sync on !bobiverse enqueue; chair answer lands later (#247)' }
    $psd1Bv = Get-Content (Join-Path $RepoRoot 'src\BobBridge.psd1') -Raw
    $psm1Bv = Get-Content (Join-Path $RepoRoot 'src\BobBridge.psm1') -Raw
    if ($psd1Bv -notmatch 'Sync-BobDigestWebhookAfterBobiversePull') { throw 'BobBridge.psd1 must export Sync-BobDigestWebhookAfterBobiversePull (#247)' }
    if ($psm1Bv -notmatch 'Sync-BobDigestWebhookAfterBobiversePull') { throw 'BobBridge.psm1 must export Sync-BobDigestWebhookAfterBobiversePull (#247)' }
    if (-not (Get-Command Sync-BobDigestWebhookAfterBobiversePull -ErrorAction SilentlyContinue)) {
        throw 'Sync-BobDigestWebhookAfterBobiversePull must resolve after Import-Module (#247)'
    }
    foreach ($watchCmd in @(
            'Write-BobIrcStatus',
            'Request-BobIrcBobiversePull',
            'Import-BobIrcTrayPull',
            'Sync-BobDigestWebhookAfterBobiversePull',
            'Import-BobIrcPeerTranscript',
            'Compact-BobIrcOutbox',
            'Get-BobIrcBuilderChannels',
            'Resolve-BobiverseMachineId'
        )) {
        if ($watchBv -notmatch ('\b' + [regex]::Escape($watchCmd) + '\b')) {
            throw "Watch-Bobiverse must call $watchCmd"
        }
        $quoted = "'" + $watchCmd + "'"
        if ($psd1Bv -notmatch [regex]::Escape($quoted)) {
            throw "BobBridge.psd1 FunctionsToExport missing $watchCmd"
        }
        if ($psm1Bv -notmatch [regex]::Escape($quoted)) {
            throw "BobBridge.psm1 Export-ModuleMember missing $watchCmd"
        }
        if (-not (Get-Command $watchCmd -ErrorAction SilentlyContinue)) {
            throw "Watch-Bobiverse module surface missing $watchCmd (#255)"
        }
    }
    if ($watchBv -match 'Get-Command\s+Resolve-BobiverseMachineId') {
        throw 'Watch-Bobiverse must call Resolve-BobiverseMachineId directly so a missing export fails the tick'
    }
    if ((Resolve-BobiverseMachineId 'ionos') -ne 'ionos') { throw 'Resolve-BobiverseMachineId ionos' }
    if ((Resolve-BobiverseMachineId 'BOB-IONOS') -ne 'ionos') { throw 'Resolve-BobiverseMachineId must map nick bob-ionos to ionos' }
    if ((Resolve-BobiverseMachineId 'bob-dev1') -ne 'ce-priority-dev1') { throw 'Resolve-BobiverseMachineId must map bob-dev1 to ce-priority-dev1' }
    $unknownSeat = Resolve-BobiverseMachineId 'not-a-seat'
    if ($unknownSeat) { throw "Resolve-BobiverseMachineId unknown seat returned $unknownSeat" }
    if ($watchBv -match 'Get-BobIrcChairDigestPeerForMachine') {
        if (-not (Get-Command Get-BobIrcChairDigestPeerForMachine -ErrorAction SilentlyContinue)) {
            throw 'Watch calls Get-BobIrcChairDigestPeerForMachine but it is not exported (#255)'
        }
    }
    $ircSrc = Get-Content (Join-Path $RepoRoot 'src\Private\Get-BobIrc.ps1') -Raw
    if ($ircSrc -match 'BOB_IRC_ENQUEUE_BOBIVERSE_PULL') {
        throw 'Request-BobIrcBobiversePull must not gate on BOB_IRC_ENQUEUE_BOBIVERSE_PULL (#255)'
    }
    if ($ircSrc -notmatch '_chair-digest-peers\.json') { throw 'chair digest peer cache must not use _report-digest.json patch (#247)' }
    if ($ircSrc -notmatch 'Test-BobIrcBobiversePullSeat') { throw 'Get-BobIrc must gate !bobiverse to bob-* builders (#196)' }
    if ($watchBv -notmatch 'Import-BobIrcTrayPull') { throw 'Watch-Bobiverse must ingest !bobiverse tray/digest whispers' }
    if ($watchBv -notmatch 'Import-BobIrcPeerTranscript') { throw 'Watch-Bobiverse may still harvest MOOT POINT transcript' }
    if ($watchBv -notmatch 'BOB_IRC_HOST') { throw 'Watch-Bobiverse must honor BOB_IRC_HOST' }
    if ($watchBv -notmatch '127\.0\.0\.1') { throw 'Watch-Bobiverse must treat 127.0.0.1 as private Ergo' }
    if ($watchBv -notmatch 'Test-BobiverseIrcPrivateErgoHost') { throw 'Watch-Bobiverse must share private-Ergo host match' }
    if ($watchBv -match '(?m)^\s*\$ircHost\s*=\s*[''"]127\.0\.0\.1[''"]') { throw 'must not default ionos to 127.0.0.1' }
    if ($watchBv -notmatch 'Compact-BobIrcOutbox') { throw 'Start-BobiverseIrcAgent must compact a fat POINT outbox' }
    $installIrc2 = Get-Content (Join-Path $RepoRoot 'tools\Install-BobIrc.ps1') -Raw
    if ($installIrc2 -notmatch 'Compact-BobIrcOutbox') { throw 'Install-BobIrc must compact a fat POINT outbox' }
    $docsBv = Get-Content (Join-Path $RepoRoot 'docs\bobiverse.md') -Raw
    if ($docsBv -notmatch 'Outbox backlog') { throw 'docs/bobiverse.md must note outbox backlog disconnect loop' }
    if ($docsBv -notmatch 'BOB TRAY v1') { throw 'docs/bobiverse.md must document tray pull dialect' }
    if ($docsBv -notmatch 'BOB DIGEST v1') { throw 'docs/bobiverse.md must document BOB DIGEST v1 JSON pull' }
    if ($docsBv -notmatch 'Resolve-BobiverseMachineId') { throw 'docs/bobiverse.md must document exported Resolve-BobiverseMachineId' }
    $skillIrcWatch = Get-Content (Join-Path $RepoRoot '.grok\skills\bob-irc\SKILL.md') -Raw
    if ($skillIrcWatch -notmatch 'Resolve-BobiverseMachineId') { throw 'bob-irc skill must name exported Resolve-BobiverseMachineId' }

    $trayLine = 'BOB TRAY v1 id=ionos weekly=4 running=1 queued=0 repo=SimonBarnett/agentic_build kind=worker model=CursorModels lastSeen=2026-09-21T00:00:00Z jobs=SimonBarnett/agentic_build:running'
    $parsedTray = ConvertFrom-BobIrcTrayLine $trayLine
    if ($parsedTray.id -ne 'ionos') { throw "tray id=$($parsedTray.id)" }
    if ([string]$parsedTray.repo -ne 'SimonBarnett/agentic_build') { throw "tray repo=$($parsedTray.repo)" }
    $nick = 'bob-testhost'
    $env:BOB_IRC_NICK = $nick
    $ircLog = Join-Path $ircHome 'irc.log'
    ":bob-flamingo!u@h PRIVMSG $nick :$trayLine" | Set-Content -Path $ircLog -Encoding utf8
    $gotTray = @(Import-BobIrcTrayPull)
    if ($gotTray -notcontains 'ionos') { throw "tray pull ingest=$($gotTray -join ',')" }
    $ionosTray = Read-BobIrcPeer -Id ionos
    if ([string]$ionosTray.repo -ne 'SimonBarnett/agentic_build') { throw "ionos tray repo=$($ionosTray.repo)" }
    if ([string]$ionosTray.source -ne 'irc-tray') { throw "ionos tray source=$($ionosTray.source)" }

    $badPointBody = 'BOB v1 id=ionos weekly=1 running=1 queued=0 lastSeen=2026-09-21T02:00:00Z jobs=?:running'
    $badParsed = ConvertFrom-BobIrcPoint $badPointBody
    if (@($badParsed.jobs).Count -gt 0) { throw 'ConvertFrom-BobIrcPoint must skip ? repo jobs' }
    $badTx = '1700000010 bob-ionos POINT ' + $badPointBody
    $mootFile = Join-Path $mootDir ($cfg.mootId + '.txt')
    $existingMoot = Get-Content $mootFile -Raw
    [IO.File]::WriteAllText($mootFile, $existingMoot.TrimEnd() + "`n" + $badTx)
    Import-BobIrcPeerTranscript | Out-Null
    $ionosAfter = Read-BobIrcPeer -Id ionos
    if ([string]$ionosAfter.repo -ne 'SimonBarnett/agentic_build') { throw "transcript clobbered repo=$($ionosAfter.repo)" }
    if ([string]$ionosAfter.kind -ne 'worker') { throw "transcript clobbered kind=$($ionosAfter.kind)" }
    if ([string]$ionosAfter.model -ne 'CursorModels') { throw "transcript clobbered model=$($ionosAfter.model)" }
    if ([string]$ionosAfter.source -ne 'irc-tray') { throw "transcript clobbered source=$($ionosAfter.source)" }
    foreach ($j in @($ionosAfter.jobs)) {
        if ([string]$j.repo -eq '?') { throw 'transcript left ? job repo on ionos peer' }
    }

    $ob = Join-Path $ircHome 'outbox.txt'
    if (Test-Path $ob) { Remove-Item -LiteralPath $ob -Force }
    $stampBob = Join-Path $peerDir '_bobiverse-last.txt'
    if (Test-Path $stampBob) { Remove-Item -LiteralPath $stampBob -Force }
    $env:BOB_MACHINE_ID = 'ionos'
    $env:BOB_IRC_NICK = 'bob-ionos'
    $savedSkip = $env:BOB_IRC_SKIP_BOBIVERSE_PULL
    $env:BOB_IRC_SKIP_BOBIVERSE_PULL = $null
    $env:BOB_IRC_NICK = 'ionos-23624'
    if (Request-BobIrcBobiversePull -MinIntervalSec 120) { throw 'talk seat ionos-23624 must not pull !bobiverse' }
    if (Test-Path $ob) {
        $obTalk = @(Get-Content $ob | Where-Object { $_ })
        if ($obTalk.Count -gt 0) { throw "talk seat outbox=$($obTalk -join ' | ')" }
    }
    $env:BOB_IRC_NICK = 'w-io-4242'
    if (Request-BobIrcBobiversePull -MinIntervalSec 120) { throw 'shop worker w-io-4242 must not pull !bobiverse' }
    $env:BOB_IRC_NICK = 'bob-ionos'
    $p1 = Request-BobIrcBobiversePull -MinIntervalSec 120
    if (-not $p1) { throw 'first Request-BobIrcBobiversePull must enqueue !bobiverse' }
    $obLines1 = @(Get-Content $ob | Where-Object { $_ })
    if ($obLines1.Count -ne 1 -or [string]$obLines1[0] -notmatch '!bobiverse') { throw "bobiverse pull outbox=$($obLines1 -join ' | ')" }
    $p2 = Request-BobIrcBobiversePull -MinIntervalSec 120
    if ($p2) { throw 'second Request-BobIrcBobiversePull within 120s must be suppressed' }
    $obLines2 = @(Get-Content $ob | Where-Object { $_ })
    if ($obLines2.Count -ne 1) { throw "bobiverse pull duplicated outbox=$($obLines2 -join ' | ')" }
    $env:BOB_IRC_SKIP_BOBIVERSE_PULL = $savedSkip

    $env:BOB_MACHINE_ID = 'testhost'
    $env:BOB_IRC_NICK = $null
    if (Test-Path $ob) { Remove-Item -LiteralPath $ob -Force }
    Write-BobIrcStatus | Out-Null
    Write-BobIrcStatus | Out-Null
    if (Test-Path $ob) {
        $obLines = @(Get-Content $ob | Where-Object { $_ })
        if ($obLines.Count -gt 0) { throw "lastSeen-only tick must not speak: outbox=$($obLines -join ' | ')" }
    }
    $peerSelf = Read-BobIrcPeer -Id testhost
    if (-not $peerSelf) { throw 'Write-BobIrcStatus must write bob-peers json without POINT outbox' }

    $cursorFile = Join-Path $bridgeRoot 'cursor-usage.json'
    $env:BOB_CURSOR_USAGE_FILE = $cursorFile
    '{"percentUsed":10}' | Set-Content -Path $cursorFile -Encoding utf8
    $webhookCap = Join-Path $bridgeRoot 'digest-webhook-capture.ndjson'
    if (Test-Path $webhookCap) { Remove-Item -LiteralPath $webhookCap -Force }
    $postedState = Join-Path $peerDir '_digest-webhook-posted.json'
    if (Test-Path $postedState) { Remove-Item -LiteralPath $postedState -Force }
    $env:BOB_DIGEST_WEBHOOK_CAPTURE = $webhookCap
    $env:BOB_MACHINE_ID = 'testhost'
    Write-BobIrcStatus | Out-Null
    if (Test-Path $webhookCap) { Remove-Item -LiteralPath $webhookCap -Force }
    Write-BobIrcStatus | Out-Null
    Write-BobIrcStatus | Out-Null
    $capLines = @()
    if (Test-Path $webhookCap) { $capLines = @(Get-Content $webhookCap | Where-Object { $_ }) }
    if ($capLines.Count -ne 0) { throw "lastSeen-only webhook must not POST: $($capLines -join ' | ')" }
    '{"percentUsed":50}' | Set-Content -Path $cursorFile -Encoding utf8
    Write-BobIrcStatus | Out-Null
    $capLines = @(Get-Content $webhookCap | Where-Object { $_ })
    if ($capLines.Count -ne 1) { throw "fuel delta must POST once: count=$($capLines.Count)" }
    if ($capLines[0] -notmatch '"op":"merge"' -or $capLines[0] -notmatch '"machine":"testhost"') {
        throw "webhook payload=$($capLines[0])"
    }
    if ($capLines[0] -match 'password=|xai_api_key=') { throw 'webhook must not carry secrets in JSON' }
    Write-BobIrcStatus | Out-Null
    $capLines = @(Get-Content $webhookCap | Where-Object { $_ })
    if ($capLines.Count -ne 1) { throw "duplicate webhook after same fuel: count=$($capLines.Count)" }
    $env:BOB_DIGEST_WEBHOOK_CAPTURE = $null

    $env:BOB_MACHINE_ID = 'ionos'
    $env:BOB_IRC_NICK = 'bob-ionos'
    $cursorFileChair = Join-Path $bridgeRoot 'cursor-usage-chair-sync.json'
    '{"percentUsed":10}' | Set-Content -Path $cursorFileChair -Encoding utf8
    $env:BOB_CURSOR_USAGE_FILE = $cursorFileChair
    $localChairBase = Write-BobIrcStatus -SkipDigestWebhook -PassThru
    if (-not $localChairBase) { throw 'Write-BobIrcStatus must return local doc for chair sync' }
    $chairJobs = @()
    foreach ($cj in @($localChairBase.jobs)) {
        if (-not $cj) { continue }
        $chairJobs += @{
            repo  = [string]$cj.repo
            state = [string]$cj.state
        }
    }
    $chairEnt = @{
        weekly            = $localChairBase.weekly
        remaining_pct     = $localChairBase.remaining_pct
        running           = $localChairBase.running
        queued            = $localChairBase.queued
        model             = $localChairBase.model
        kind              = $localChairBase.kind
        repo              = $localChairBase.repo
        sha               = $localChairBase.sha
        lastSeen          = $localChairBase.lastSeen
        cursor_label      = $localChairBase.cursor_label
        cursor_period_end = $localChairBase.cursor_period_end
        period_end        = $localChairBase.period_end
        fuel              = $localChairBase.fuel
        working_on        = $localChairBase.working_on
        online            = $localChairBase.online
        status            = $localChairBase.status
        responding        = $localChairBase.responding
        jobs              = $chairJobs
    }
    $chairPeersPath = Join-Path $peerDir '_chair-digest-peers.json'
    if (Test-Path $chairPeersPath) { Remove-Item -LiteralPath $chairPeersPath -Force }
    $chairDigestObj = @{
        v        = 1
        ts       = '2026-09-21T12:00:00Z'
        machines = @{ ionos = $chairEnt }
    }
    $ingested = @(Add-TestBobIrcDigestWhisper -IrcHome $ircHome -Nick 'bob-ionos' -DigestObj $chairDigestObj -ResetTrayPos)
    if ($ingested -notcontains 'ionos') { throw "chair digest whisper ingest=$($ingested -join ',')" }
    if (-not (Test-Path $chairPeersPath)) { throw 'chair digest whisper must write _chair-digest-peers.json (#247)' }
    $webhookCapChair = Join-Path $bridgeRoot 'digest-webhook-chair-sync.ndjson'
    if (Test-Path $webhookCapChair) { Remove-Item -LiteralPath $webhookCapChair -Force }
    if (Test-Path $postedState) { Remove-Item -LiteralPath $postedState -Force }
    $env:BOB_DIGEST_WEBHOOK_CAPTURE = $webhookCapChair
    function Invoke-TestWatchBobiverseChairSync {
        param($LocalDoc)
        if ($LocalDoc) {
            Sync-BobDigestWebhookAfterBobiversePull -LocalDoc $LocalDoc
        }
    }
    $localChair = Write-BobIrcStatus -SkipDigestWebhook -PassThru
    Invoke-TestWatchBobiverseChairSync -LocalDoc $localChair
    Invoke-TestWatchBobiverseChairSync -LocalDoc $localChair
    $chairCap = @()
    if (Test-Path $webhookCapChair) { $chairCap = @(Get-Content $webhookCapChair | Where-Object { $_ }) }
    if ($chairCap.Count -ne 0) { throw "chair match must not POST: $($chairCap -join ' | ')" }
    '{"percentUsed":55}' | Set-Content -Path $cursorFileChair -Encoding utf8
    $localChairDelta = Write-BobIrcStatus -SkipDigestWebhook -PassThru
    Invoke-TestWatchBobiverseChairSync -LocalDoc $localChairDelta
    $chairCap = @(Get-Content $webhookCapChair | Where-Object { $_ })
    if ($chairCap.Count -ne 1) { throw "chair-diff fuel delta must POST once via Sync: count=$($chairCap.Count)" }
    Write-BobIrcStatus -SkipDigestWebhook | Out-Null
    Write-BobIrcStatus -SkipDigestWebhook | Out-Null
    $localChairLastSeen = Write-BobIrcStatus -SkipDigestWebhook -PassThru
    Invoke-TestWatchBobiverseChairSync -LocalDoc $localChairLastSeen
    $chairCap = @(Get-Content $webhookCapChair | Where-Object { $_ })
    if ($chairCap.Count -ne 1) { throw "lastSeen-only chair sync must not POST again: count=$($chairCap.Count)" }
    if ($chairCap[0] -notmatch '"op":"merge"' -or $chairCap[0] -notmatch '"machine":"ionos"') {
        throw "chair-diff webhook payload=$($chairCap[0])"
    }
    $env:BOB_DIGEST_WEBHOOK_CAPTURE = $null
    $env:BOB_MACHINE_ID = $null
    $env:BOB_IRC_NICK = $null
    $env:BOB_CURSOR_USAGE_FILE = $cursorFile

    $stamp = Get-BobJobRepoStamp ([pscustomobject]@{ cwd = (Join-Path $bridgeRoot 'agentic_build-i74'); repo = '?' })
    if ($stamp -eq '?' -or -not $stamp) {
        $stamp2 = Get-BobJobRepoStamp ([pscustomobject]@{ cwd = $RepoRoot; repo = '?' })
        if (-not $stamp2 -or $stamp2 -eq '?') { throw "repo stamp still ?: $stamp2" }
    }

    if (@(Normalize-BobPeerLaneJobsResult $null).Count -ne 0) {
        throw 'Normalize-BobPeerLaneJobsResult($null) must be empty (not @($null).Count=1)'
    }
    $env:BOB_MACHINE_ID = 'testhost'
    $staleDir = Join-Path $bridgeRoot (Join-Path 'fleet' (Join-Path 'running' 'testhost'))
    New-Item -ItemType Directory -Force -Path $staleDir | Out-Null
    $staleWhen = ([DateTime]::UtcNow.AddHours(-60)).ToString('o')
    $staleJob = @{
        id        = 'stale-orphan-job-0001'
        machine   = 'testhost'
        cwd       = $RepoRoot
        repo      = 'SimonBarnett/agentic_build'
        kind      = 'git'
        fuel      = 'copilot'
        claimedAt = $staleWhen
        state     = 'START'
    } | ConvertTo-Json -Compress
    Set-Content -Path (Join-Path $staleDir 'stale.json') -Value $staleJob -Encoding utf8
    $idleDoc = Write-BobIrcStatus -SkipDigestWebhook -PassThru
    if ([int]$idleDoc.running -ne 0) { throw "stale orphan must zero running: $($idleDoc.running)" }
    if ([int]$idleDoc.queued -ne 0) { throw "stale orphan must zero queued: $($idleDoc.queued)" }
    if (@($idleDoc.jobs).Count -ne 0) { throw 'stale orphan must publish jobs=[]' }
    Remove-Item -LiteralPath (Join-Path $staleDir 'stale.json') -Force -ErrorAction SilentlyContinue

    $capIdle = Join-Path $bridgeRoot 'digest-webhook-idle-clear.ndjson'
    if (Test-Path $capIdle) { Remove-Item -LiteralPath $capIdle -Force }
    if (Test-Path $postedState) { Remove-Item -LiteralPath $postedState -Force }
    $env:BOB_DIGEST_WEBHOOK_CAPTURE = $capIdle
    $idlePost = Write-BobIrcStatus -PassThru
    if ([int]$idlePost.running -ne 0 -or @($idlePost.jobs).Count -ne 0) { throw 'idle post doc not empty' }
    $idleCap = @(Get-Content $capIdle | Where-Object { $_ })
    if ($idleCap.Count -ne 1) { throw "idle webhook must POST once: count=$($idleCap.Count)" }
    if ($idleCap[0] -notmatch '"jobs"\s*:\s*\[\]' -or $idleCap[0] -notmatch '"running"\s*:\s*0') {
        throw "idle webhook must clear jobs/running: $($idleCap[0])"
    }
    $env:BOB_DIGEST_WEBHOOK_CAPTURE = $null

    $peerDirStale = Join-Path $peerDir 'ce-priority-dev1.json'
    $prevPeer = @{
        ok    = $true
        id    = 'ce-priority-dev1'
        jobs  = @(@{ repo = 'irc'; state = 'START'; description = 'irc agent'; model = 'running' })
        repo  = 'irc'
        model = 'running'
        running = 1
        queued  = 0
        source  = 'irc-digest'
    }
    Write-JsonFile $peerDirStale $prevPeer
    $clearDigest = @{
        v        = 1
        ts       = '2026-09-24T09:00:00Z'
        machines = @{
            'ce-priority-dev1' = @{
                running = 0
                queued  = 0
                jobs    = @()
                weekly  = 0
            }
        }
    }
    $ingClear = @(Import-BobIrcDigestJson -DigestObj $clearDigest)
    if ($ingClear -notcontains 'ce-priority-dev1') { throw "idle digest ingest=$($ingClear -join ',')" }
    $clearedPeer = Read-JsonFile $peerDirStale
    if (@($clearedPeer.jobs).Count -gt 0) { throw 'chair idle digest must not merge stale irc START jobs' }
    if ([int]$clearedPeer.running -ne 0) { throw "cleared peer running=$($clearedPeer.running)" }

    $env:BOB_MACHINE_ID = $null

    $fatHome = Join-Path $bridgeRoot 'irc-fat'
    New-Item -ItemType Directory -Force -Path $fatHome | Out-Null
    $fatOut = Join-Path $fatHome 'outbox.txt'
    $sample = 'MOOT v1 POINT b0b1be15e0000001 :BOB v1 id=testhost weekly=1 reset=- cur=- crst=- running=0 queued=0 lastSeen=2026-09-20T00:00:00Z jobs=-'
    $fat = New-Object System.Collections.Generic.List[string]
    [void]$fat.Add('PRIVMSG #bobiverse :keep-me')
    while (([Text.Encoding]::UTF8.GetByteCount(($fat -join "`n"))) -lt 33000) { [void]$fat.Add($sample) }
    [IO.File]::WriteAllLines($fatOut, $fat)
    Compact-BobIrcOutbox -Home $fatHome
    $after = @(Get-Content $fatOut | Where-Object { $_ })
    if ($after.Count -ne 2) { throw "compact kept $($after.Count) lines (want PRIVMSG + latest POINT)" }
    if ($after[0] -notmatch 'keep-me') { throw 'compact dropped non-POINT line' }
    if ($after[1] -notmatch 'id=testhost') { throw 'compact lost self POINT' }
    $tickSrc = Get-Content (Join-Path $RepoRoot 'src\Private\Invoke-BobFleet.ps1') -Raw
    if ($tickSrc -match 'Write-BobIrcStatus') { throw 'fleet tick must not POINT; that is Watch-Bobiverse automation' }

    '{"percentUsed":98}' | Set-Content -Path $cursorFile -Encoding utf8
    $cu = Get-BobCursorAgentWeeklyRemaining
    if ([int]$cu.used_pct -ne 98) { throw "cursor used=$($cu.used_pct)" }
    if ([int]$cu.remaining_pct -ne 2) { throw "cursor remaining=$($cu.remaining_pct) expected 2 from 98% used" }
    $env:BOB_MACHINE_ID = 'ionos'
    $hCur = Get-BobTrayHover
    if ([int]$hCur.account_remaining_pct -ne 2) { throw "hover cursor remaining=$($hCur.account_remaining_pct)" }
    if ([string]$hCur.jobs_text -notmatch '(?m)^[ ]+low cost models  2%') { throw "jobs_text cursor pool=$($hCur.jobs_text)" }
    $env:BOB_MACHINE_ID = $null
    $traySrc = Get-Content (Join-Path $RepoRoot 'tools\Watch-BobTray.ps1') -Raw
    if ($traySrc -notmatch 'Watch-Bobiverse\.ps1') { throw 'tray must start Watch-Bobiverse, not a grok job' }
    if ($traySrc -match 'Start-IrcWatcher[\s\S]{0,400}Install-BobIrc') { throw 'tray must not run Install-BobIrc on every poll' }
}

# --- BT0o2 Cursor Models spending meter vs Sand (issue #21 / #25) ---
Invoke-Case 'BT0o2 cursor models spending meter' {
    param($bridgeRoot)
    $apiFixture = Join-Path $bridgeRoot 'cursor-spending-api-fixture.json'
    @'
{
  "period": {
    "planUsage": { "autoPercentUsed": 1, "apiPercentUsed": 6 },
    "billingCycleEnd": "2026-10-16T00:00:00Z",
    "spendLimitUsage": { "individualUsed": 6850 }
  },
  "sand": {
    "usagePercent": 100,
    "nextResetTimestampUtc": "2026-09-23T00:00:00Z"
  }
}
'@ | Set-Content -Path $apiFixture -Encoding utf8
    $py = $null
    foreach ($c in @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
            'C:\Python\Python313\python.exe',
            'C:\Python\Python312\python.exe',
            'python',
            'py'
        )) {
        if (-not $c) { continue }
        if ($c -eq 'python' -or $c -eq 'py') {
            try {
                $probe = & $c -c "import sys; print(sys.executable)" 2>$null
                if (-not $probe) { continue }
                $ok = & $c -c "print(1)" 2>$null
                if ($ok -eq '1') { $py = $c; break }
            }
            catch { }
            continue
        }
        if (-not (Test-Path $c)) { continue }
        try {
            $ok = & $c -c "print(1)" 2>$null
            if ($ok -eq '1') { $py = $c; break }
        }
        catch { }
    }
    $script = Join-Path $RepoRoot 'tools\Get-CursorAgentUsage.py'
    $env:BOB_CURSOR_AGENT_FIXTURE = $apiFixture
    $env:BOB_CURSOR_USD_GBP_RATE = '0.7918'
    $parsedRaw = $null
    if ($py) { $parsedRaw = & $py $script 2>$null }
    if (-not $parsedRaw) {
        $psDoc = Get-BobCursorSpendingFromApiFixture -Path $apiFixture
        if (-not $psDoc) {
            $psDoc = Get-BobCursorAgentWeeklyRemaining
        }
        if (-not $psDoc) { throw 'Get-CursorAgentUsage fixture parse failed (python and PS fallback)' }
        $parsedRaw = ($psDoc | ConvertTo-Json -Depth 6 -Compress)
    }
    $parsed = $parsedRaw | ConvertFrom-Json
    if ([int]$parsed.used_pct -ne 1) { throw "parser used_pct=$($parsed.used_pct) expected 1 from autoPercentUsed=1" }
    if ([int]$parsed.remaining_pct -ne 99) { throw "parser remaining_pct=$($parsed.remaining_pct) expected 99" }
    if ([string]$parsed.period_end -notmatch '2026-10-16') { throw "parser period_end=$($parsed.period_end) expected Cursor Models Oct 16" }
    if ([string]$parsed.period_end -match '2026-09-23') { throw 'parser must not use Sand reset as Cursor Models period_end' }
    if ([int]$parsed.sand_used_pct -ne 100) { throw "parser sand_used_pct=$($parsed.sand_used_pct)" }
    if (@($parsed.cursor_spending_groups).Count -lt 3) { throw "parser cursor_spending_groups=$(@($parsed.cursor_spending_groups).Count)" }
    $cursorFile = Join-Path $bridgeRoot 'cursor-spending-meter-doc.json'
    $parsedRaw | Set-Content -Path $cursorFile -Encoding utf8
    $env:BOB_CURSOR_USAGE_FILE = $cursorFile
    $env:BOB_CURSOR_AGENT_FIXTURE = $null
    $cu = Get-BobCursorAgentWeeklyRemaining
    if ([int]$cu.used_pct -ne 1) { throw "cursor models used=$($cu.used_pct) expected 1" }
    if ([int]$cu.remaining_pct -ne 99) { throw "cursor models remaining=$($cu.remaining_pct) expected 99 (not Sand/overage)" }
    if ($null -eq $cu.sand_remaining_pct -or [int]$cu.sand_remaining_pct -ne 0) { throw "sand_remaining_pct=$($cu.sand_remaining_pct)" }
    if (-not $cu.sand_exhausted) { throw 'sand_exhausted must be true' }
    if ($null -eq $cu.overage_gbp) { throw 'overage_gbp must remain a separate field' }
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $cap = Get-BobCapacity
    if ([int]$cap.cursor_models.remaining_pct -ne 99) { throw "capacity cursor_models=$($cap.cursor_models.remaining_pct)" }
    if ([string]$cap.cursor_models.period_end -notmatch '2026-10-16') { throw "capacity period_end=$($cap.cursor_models.period_end)" }
    if ([string]$cap.cursor_models.period_end -match '2026-09-23') { throw 'capacity must not use Sand reset for cursor_models.period_end' }
    $hostRow = @($cap.machines | Where-Object { [string]$_.id -eq 'testhost' })[0]
    if ($null -eq $hostRow.grok_bot.remaining_pct -or [int]$hostRow.grok_bot.remaining_pct -ne 0) {
        throw "grok_bot.remaining_pct=$($hostRow.grok_bot.remaining_pct) expected Sand slot 0"
    }
    if ([int]$cap.cursor_models.remaining_pct -le 0) {
        throw 'Sand 100% + overage must not block cursor-models fuel'
    }
    $pick = Select-BobGitWorker -Capacity $cap
    if ($pick.wait -or [string]$pick.fuel -ne 'cursor-models') {
        throw "Select-BobGitWorker expected cursor-models got fuel=$($pick.fuel) wait=$($pick.wait)"
    }
    $env:BOB_MACHINE_ID = 'ionos'
    $hCur = Get-BobTrayHover
    if ([int]$hCur.account_remaining_pct -ne 99) { throw "hover cursor remaining=$($hCur.account_remaining_pct)" }
    if ([string]$hCur.jobs_text -notmatch '(?m)^[ ]+low cost models  99%') { throw "jobs_text must show low cost models 99%: $($hCur.jobs_text)" }
    if ([string]$hCur.jobs_text -notmatch '(?m)^[ ]+high cost models  94%') { throw "jobs_text must show high cost models 94%: $($hCur.jobs_text)" }
    if ([string]$hCur.jobs_text -notmatch '(?m)^[ ]+grok chat  0%') { throw "jobs_text must show grok chat 0% from Sand: $($hCur.jobs_text)" }
    if ([string]$hCur.jobs_text -match [char]0x00A3) { throw 'jobs_text must not show Sand overage GBP as Cursor Models remaining' }
    $env:BOB_MACHINE_ID = $null
}

# --- BT0l3 tray cursor pools + !report #36 digest (issues #91 / #100) ---
Invoke-Case 'BT0l3 tray cursor pools report' {
    param($bridgeRoot)
    $env:BOB_MACHINE_ID = 'ionos'
    $env:BOB_IRC_CONFIG = Join-Path $RepoRoot 'config\bobiverse.json'
    $null = Register-BobMachine -Id ionos -CwdRoots $bridgeRoot
    $poolsFile = Join-Path $bridgeRoot 'cursor-pools-fixture.json'
    @'
{
  "by_seat": {
    "smart-catalogue": { "remaining_pct": 99, "period_end": "2026-09-23T00:00:00Z" },
    "club-madeira": { "remaining_pct": 8, "period_end": "2026-09-26T00:00:00Z" },
    "ntsa": { "remaining_pct": 5, "period_end": "2026-09-22T00:00:00Z" }
  }
}
'@ | Set-Content -Path $poolsFile -Encoding utf8
    Copy-Item -LiteralPath $poolsFile -Destination (Join-Path $bridgeRoot 'cursor-pools.json') -Force

    $ircHome = Join-Path $bridgeRoot 'irc-digest'
    New-Item -ItemType Directory -Force -Path (Join-Path $ircHome 'bob-peers') | Out-Null
    @'
{
  "machines": {
    "ionos": {
      "task": {
        "repo": "SimonBarnett/agentic_build",
        "sha": "deadbee",
        "model": "composer-2.5",
        "description": "digest fixture line",
        "run_time": "3m11s",
        "state": "START"
      },
      "pcent": {
        "cursor-models": 9,
        "grok-build": 12
      },
      "uptime_since": "2026-09-21T08:00:00Z"
    },
    "flamingo": {
      "task": {
        "repo": "SimonBarnett/agentic_irc",
        "sha": "cafebad",
        "model": "grok-4.6",
        "description": "peer digest task",
        "run_time": "1m52s",
        "state": "START"
      },
      "pcent": {
        "cursor-models": 37
      }
    },
    "marchhare": {},
    "ce-priority-dev1": {
      "pcent": {
        "cursor-models": 0
      }
    }
  }
}
'@ | Set-Content -Path (Join-Path $ircHome 'bob-peers\_report-digest.json') -Encoding utf8
    $env:BOB_IRC_HOME = $ircHome
    $env:AGENTIC_IRC_HOME = $ircHome

    $ircPools = Get-Content (Join-Path $RepoRoot 'src\Private\Get-BobIrc.ps1') -Raw
    if ($ircPools -notmatch 'https://irc\.ntsa\.uk/bob/v1/report') {
        throw 'Get-BobDigestUrl default must be the report endpoint'
    }

    $h = Get-BobTrayHover
    $txt = [string]$h.jobs_text
    if (@($h.cursor_pools).Count -ne 3) { throw "cursor_pools=$(@($h.cursor_pools).Count) expected 3 groups" }
    # Fleet-shared Cursor groups: peer pcent is not dropped when machine != local.
    # Fixture order ends on ce-priority-dev1 cursor-models 0, so the auto bar is 0%.
    if ($txt -notmatch '(?m)^[ ]+auto  0%') { throw "fleet digest pcent must paint auto bar: $txt" }
    Remove-Item -LiteralPath (Join-Path $bridgeRoot 'cursor-pools.json') -ErrorAction SilentlyContinue
    $env:BOB_MACHINE_ID = 'marchhare'
    $hMh = Get-BobTrayHover
    $txtMh = [string]$hMh.jobs_text
    if ($txtMh -notmatch '(?m)^[ ]+auto  0%') { throw "marchhare must consume peer cursor-models pcent: $txtMh" }
    if ($txtMh -match '(?m)^[ ]+auto  n/a') { throw "marchhare auto bar still n/a: $txtMh" }
    $env:BOB_MACHINE_ID = 'ionos'
    if ($txt -match '(?m)^[ ]+Club Madeira  low cost models') { throw "peer xAI seat must not appear as Cursor bar: $txt" }
    if ($txt -match '(?m)^[ ]+ntsa  low cost models') { throw "peer xAI seat must not appear as Cursor bar: $txt" }
    if ($txt -notmatch 'deadbee') { throw "ionos digest sha missing: $txt" }
    if ($txt -notmatch 'digest fixture line') { throw "ionos description missing: $txt" }
    if ($txt -notmatch '3m11s') { throw "ionos run_time missing: $txt" }
    if ($txt -notmatch 'cafebad') { throw "flamingo digest sha missing: $txt" }
    if ($txt -notmatch 'up since 2026-09-21T08:00:00Z') { throw "ionos uptime_since missing: $txt" }
    if ($txt -notmatch '(?m)marchhare[^\r\n]*\r?\n(?:[^\r\n]*\r?\n)*?[ ]+no jobs') { throw "idle marchhare must say no jobs: $txt" }
    @'
{
  "machines": {
    "ce-priority-dev1": {
      "task": {
        "repo": "SimonBarnett/agentic_irc",
        "model": "Copilot",
        "kind": "git",
        "description": "stale chair task",
        "state": "START"
      },
      "running": 0,
      "queued": 0,
      "jobs": []
    }
  }
}
'@ | Set-Content -Path (Join-Path $ircHome 'bob-peers\_report-digest-stale.json') -Encoding utf8
    Copy-Item -LiteralPath (Join-Path $ircHome 'bob-peers\_report-digest-stale.json') -Destination (Join-Path $ircHome 'bob-peers\_report-digest.json') -Force
    $hStale = Get-BobTrayHover
    $txtStale = [string]$hStale.jobs_text
    if ($txtStale -match 'ce-priority-dev1[^\r\n]*\r?\n[ ]+START[^\r\n]*stale chair task') {
        throw "zeroed digest must not paint stale START: $txtStale"
    }
    if ($txtStale -notmatch '(?m)ce-priority-dev1[^\r\n]*\r?\n(?:[^\r\n]*\r?\n)*?[ ]+no jobs') {
        throw "ce-priority-dev1 must be no jobs when digest running=0: $txtStale"
    }
    if ($txt -match 'grok\.exe \?') { throw "must not show grok.exe ?: $txt" }
    if ($txt -match '395c499|abcd123') { throw "must not rely on invented tasks[] fixture shas: $txt" }

    $traySrc = Get-Content (Join-Path $RepoRoot 'tools\Watch-BobTray.ps1') -Raw
    if ($traySrc -notmatch 'CursorPools') { throw 'Watch-BobTray must paint cursor pool bars' }
    $skillTray = Get-Content (Join-Path $RepoRoot '.grok\skills\bob-fleet-tray\SKILL.md') -Raw
    if ($skillTray -notmatch '(?i)grok chat') { throw 'bob-fleet-tray skill must document Cursor spending groups' }
    if ($skillTray -notmatch 'START') { throw 'bob-fleet-tray skill must document START report lines' }

    $env:BOB_MACHINE_ID = $null
    $env:BOB_IRC_HOME = $null
    $env:AGENTIC_IRC_HOME = $null
}

# --- BT0l4 !bobiverse BOB DIGEST v1 ingest (issue #142) ---
Invoke-Case 'BT0l4 bobiverse digest tray ingest' {
    param($bridgeRoot)
    $env:BOB_MACHINE_ID = 'ionos'
    $env:BOB_IRC_CONFIG = Join-Path $RepoRoot 'config\bobiverse.json'
    $null = Register-BobMachine -Id ionos -CwdRoots $bridgeRoot
    $ircHome = Join-Path $bridgeRoot 'irc-bobiverse-digest'
    New-Item -ItemType Directory -Force -Path (Join-Path $ircHome 'bob-peers') | Out-Null
    $env:BOB_IRC_HOME = $ircHome
    $env:AGENTIC_IRC_HOME = $ircHome
    $nick = 'bob-testhost'
    $env:BOB_IRC_NICK = $nick
    $digestObj = @{
        v            = 1
        ts           = '2026-09-21T12:00:00Z'
        chairNick    = 'Jeeves'
        cursor_pools = @(
            @{ id = 'smart-catalogue'; group = 'low-cost-models'; remaining = 11; period_end = '2026-09-23T00:00:00Z' }
            @{ id = 'club-madeira'; group = 'low-cost-models'; remaining = 22; period_end = '2026-09-26T00:00:00Z' }
            @{ id = 'ntsa'; group = 'low-cost-models'; remaining = 3; period_end = '2026-09-22T00:00:00Z' }
        )
        machines     = @{
            ionos            = @{
                weekly       = 12
                period_end   = '2026-09-28T00:00:00Z'
                running      = 1
                queued       = 0
                lastSeen     = '2026-09-21T12:00:00Z'
                uptime_since = '2026-09-21T08:00:00Z'
                jobs         = @(
                    @{
                        repo        = 'SimonBarnett/agentic_build'
                        sha         = 'beef142'
                        model       = 'composer-2.5'
                        description = 'digest ingest fixture'
                        run_time    = '4m02s'
                        state       = 'running'
                    }
                )
                pcent        = @{ 'cursor-models' = 11 }
            }
            flamingo         = @{
                weekly   = 8
                running  = 1
                lastSeen = '2026-09-21T11:00:00Z'
                jobs     = @(
                    @{
                        repo        = 'SimonBarnett/agentic_irc'
                        sha         = 'face142'
                        model       = 'grok-4.6'
                        description = 'peer digest line'
                        run_time    = '2m01s'
                        state       = 'START'
                    }
                )
            }
            marchhare          = @{ weekly = 4; running = 0; queued = 0; jobs = @() }
            'ce-priority-dev1' = @{ weekly = 4; running = 0; queued = 0; jobs = @() }
        }
    }
    $rawJson = ($digestObj | ConvertTo-Json -Depth 8 -Compress)
    $chunkA = $rawJson.Substring(0, [Math]::Min(120, $rawJson.Length))
    $chunkB = $rawJson.Substring($chunkA.Length)
    $logLines = @(
        ":Jeeves!u@h PRIVMSG $nick :BOB DIGEST v1 1/2 $chunkA"
        ":Jeeves!u@h PRIVMSG $nick :BOB DIGEST v1 2/2 $chunkB"
    )
    $ircLog = Join-Path $ircHome 'irc.log'
    $logLines | Set-Content -Path $ircLog -Encoding utf8
    $posPath = Join-Path $ircHome 'bob-peers\_tray-log.pos'
    if (Test-Path $posPath) { Remove-Item -LiteralPath $posPath -Force }
    $got = @(Import-BobIrcTrayPull)
    foreach ($need in @('ionos', 'flamingo', 'marchhare', 'ce-priority-dev1')) {
        if ($got -notcontains $need) { throw "digest ingest missing peer $need : $($got -join ',')" }
        if (-not (Test-Path (Join-Path $ircHome "bob-peers\$need.json"))) { throw "missing bob-peers/$need.json" }
    }
    if (-not (Test-Path (Join-Path $ircHome 'bob-peers\_chair-digest-peers.json'))) {
        throw 'digest ingest must cache chair machine rows (#247)'
    }
    $ionosPeer = Read-BobIrcPeer -Id ionos
    if ([string]$ionosPeer.source -ne 'irc-digest') { throw "ionos source=$($ionosPeer.source)" }
    if ([string]$ionosPeer.sha -ne 'beef142') { throw "ionos sha=$($ionosPeer.sha)" }
    $poolsPath = Join-Path $bridgeRoot 'cursor-pools.json'
    if (-not (Test-Path $poolsPath)) { throw 'cursor-pools.json missing after digest ingest' }
    $poolsDoc = Get-Content -LiteralPath $poolsPath -Raw | ConvertFrom-Json
    if (-not $poolsDoc.by_seat.'smart-catalogue') { throw 'smart-catalogue pool not cached' }
    if ([int]$poolsDoc.by_seat.'smart-catalogue'.remaining_pct -ne 11) {
        throw "smart-catalogue remaining=$($poolsDoc.by_seat.'smart-catalogue'.remaining_pct)"
    }
    $h = Get-BobTrayHover
    $txt = [string]$h.jobs_text
    if ($txt -notmatch 'beef142') { throw "hover missing digest sha: $txt" }
    if ($txt -notmatch 'digest ingest fixture') { throw "hover missing description: $txt" }
    if ($txt -notmatch 'face142') { throw "hover missing flamingo sha: $txt" }
    if ($txt -notmatch '(?m)^[ ]+low cost models  11%') { throw "local low cost models bar from digest: $txt" }
    if ($txt -match '(?m)^[ ]+Club Madeira  low cost models') { throw "peer pool cache must not paint xAI seat as Cursor bar: $txt" }
    if ($txt -notmatch '(?m)ionos[^\r\n]*\(12%\)') { throw "ionos weekly bar missing: $txt" }
    if ($txt -notmatch '(?m)flamingo[^\r\n]*\(8%\)') { throw "flamingo weekly bar missing: $txt" }
    if ($txt -notmatch 'reset 28 Sep') { throw "ionos reset label missing: $txt" }
    if ($txt -notmatch 'composer-2\.5') { throw "hover missing digest model: $txt" }
    if ($txt -match 'grok\.exe \?') { throw "must not show grok.exe ?: $txt" }
    $skillTray = Get-Content (Join-Path $RepoRoot '.grok\skills\bob-fleet-tray\SKILL.md') -Raw
    if ($skillTray -notmatch 'BOB DIGEST v1') { throw 'bob-fleet-tray skill must document BOB DIGEST v1 pull' }

    $env:BOB_MACHINE_ID = $null
    $env:BOB_IRC_NICK = $null
    $env:BOB_IRC_HOME = $null
    $env:AGENTIC_IRC_HOME = $null
}

# --- BT0l4b thin digest merge-preserve (issue #144) ---
Invoke-Case 'BT0l4b thin digest preserves rich peers' {
    param($bridgeRoot)
    $env:BOB_MACHINE_ID = 'ionos'
    $env:BOB_IRC_CONFIG = Join-Path $RepoRoot 'config\bobiverse.json'
    $null = Register-BobMachine -Id ionos -CwdRoots $bridgeRoot
    $ircHome = Join-Path $bridgeRoot 'irc-bobiverse-digest-thin'
    New-Item -ItemType Directory -Force -Path (Join-Path $ircHome 'bob-peers') | Out-Null
    $env:BOB_IRC_HOME = $ircHome
    $env:AGENTIC_IRC_HOME = $ircHome
    $full = @{
        v        = 1
        machines = @{
            ionos    = @{
                weekly     = 12
                period_end = '2026-09-28T00:00:00Z'
                running    = 1
                jobs       = @(@{ repo = 'SimonBarnett/agentic_build'; sha = 'beef144'; model = 'composer-2.5'; description = 'rich peer line'; state = 'running' })
            }
            flamingo = @{
                weekly = 8
                jobs   = @(@{ repo = 'SimonBarnett/agentic_irc'; sha = 'face144'; model = 'grok-4.6'; description = 'flamingo rich'; state = 'START' })
            }
        }
    }
    $env:BOB_IRC_NICK = 'bob-thin-test'
    $null = Add-TestBobIrcDigestWhisper -IrcHome $ircHome -Nick 'bob-thin-test' -DigestObj $full -ResetTrayPos
    $thin = @{
        v        = 1
        ts       = '2026-09-21T13:00:00Z'
        machines = @{
            ionos            = @{ online = $true; status = 'ok'; workers = 1; working_on = 'presence only'; lastSeen = '2026-09-21T13:00:00Z'; running = 1 }
            flamingo         = @{ online = $true; status = 'ok'; workers = 0; lastSeen = '2026-09-21T13:00:00Z' }
            marchhare        = @{ online = $false }
            'ce-priority-dev1' = @{ online = $false }
        }
    }
    $null = Add-TestBobIrcDigestWhisper -IrcHome $ircHome -Nick 'bob-thin-test' -DigestObj $thin
    $ionosPeer = Read-BobIrcPeer -Id ionos
    if ([int]$ionosPeer.weekly -ne 12) { throw "ionos weekly wiped=$($ionosPeer.weekly)" }
    if ([string]$ionosPeer.sha -ne 'beef144') { throw "ionos sha wiped=$($ionosPeer.sha)" }
    if (@($ionosPeer.jobs).Count -lt 1) { throw 'ionos jobs wiped by thin digest' }
    $flPeer = Read-BobIrcPeer -Id flamingo
    if ([int]$flPeer.weekly -ne 8) { throw "flamingo weekly wiped=$($flPeer.weekly)" }
    if ([string]$flPeer.sha -ne 'face144') { throw "flamingo sha wiped=$($flPeer.sha)" }
    $report = Get-Content -LiteralPath (Join-Path $ircHome 'bob-peers\_report-digest.json') -Raw | ConvertFrom-Json
    if (-not $report.machines.flamingo.task.sha) { throw 'report digest task wiped by thin whisper' }
    if ([string]$report.machines.flamingo.task.sha -ne 'face144') { throw "report sha=$($report.machines.flamingo.task.sha)" }
    $h = Get-BobTrayHover
    $txt = [string]$h.jobs_text
    if ($txt -notmatch 'beef144') { throw "hover lost sha after thin digest: $txt" }
    if ($txt -notmatch 'rich peer line') { throw "hover lost description after thin digest: $txt" }
    if ($txt -notmatch 'face144') { throw "hover lost flamingo sha after thin digest: $txt" }

    $env:BOB_MACHINE_ID = $null
    $env:BOB_IRC_NICK = $null
    $env:BOB_IRC_HOME = $null
    $env:AGENTIC_IRC_HOME = $null
}

# --- BT0l4c digest machines[].task mapping (issue #144) ---
Invoke-Case 'BT0l4c digest task field paints hover' {
    param($bridgeRoot)
    $env:BOB_MACHINE_ID = 'ionos'
    $env:BOB_IRC_CONFIG = Join-Path $RepoRoot 'config\bobiverse.json'
    $null = Register-BobMachine -Id ionos -CwdRoots $bridgeRoot
    $ircHome = Join-Path $bridgeRoot 'irc-bobiverse-digest-task'
    New-Item -ItemType Directory -Force -Path (Join-Path $ircHome 'bob-peers') | Out-Null
    $env:BOB_IRC_HOME = $ircHome
    $env:AGENTIC_IRC_HOME = $ircHome
    $digest = @{
        v        = 1
        machines = @{
            flamingo = @{
                task = @{
                    repo        = 'SimonBarnett/agentic_irc'
                    sha         = 'cafebad'
                    model       = 'grok-4.6'
                    description = 'task only digest line'
                    run_time    = '2m44s'
                    state       = 'START'
                }
            }
        }
    }
    $env:BOB_IRC_NICK = 'bob-task-test'
    $null = Add-TestBobIrcDigestWhisper -IrcHome $ircHome -Nick 'bob-task-test' -DigestObj $digest -ResetTrayPos
    $flPeer = Read-BobIrcPeer -Id flamingo
    if (@($flPeer.jobs).Count -lt 1) { throw 'task-only digest must populate peer jobs' }
    if ([string]$flPeer.sha -ne 'cafebad') { throw "flamingo peer sha=$($flPeer.sha)" }
    $report = Get-Content -LiteralPath (Join-Path $ircHome 'bob-peers\_report-digest.json') -Raw | ConvertFrom-Json
    if ([string]$report.machines.flamingo.task.sha -ne 'cafebad') { throw 'task missing from _report-digest.json' }
    $h = Get-BobTrayHover
    $txt = [string]$h.jobs_text
    if ($txt -notmatch 'cafebad') { throw "hover missing task sha: $txt" }
    if ($txt -notmatch 'task only digest line') { throw "hover missing task description: $txt" }

    $env:BOB_MACHINE_ID = $null
    $env:BOB_IRC_NICK = $null
    $env:BOB_IRC_HOME = $null
    $env:AGENTIC_IRC_HOME = $null
}

# --- BT0l5 systray Cursor groups + IRC workers (issue #151) ---
Invoke-Case 'BT0l5 cursor spending groups and irc workers' {
    param($bridgeRoot)
    $env:BOB_MACHINE_ID = 'ionos'
    $env:BOB_IRC_CONFIG = Join-Path $RepoRoot 'config\bobiverse.json'
    $null = Register-BobMachine -Id ionos -CwdRoots $bridgeRoot
    $cursorFile = Join-Path $bridgeRoot 'cursor-groups-fixture.json'
    @'
{
  "used_pct": 5,
  "remaining_pct": 95,
  "period_end": "2026-10-16T00:00:00Z",
  "sand_period_end": "2026-09-23T00:00:00Z",
  "sand_used_pct": 25,
  "sand_remaining_pct": 75,
  "cursor_spending_groups": [
    { "id": "grok-chat", "label": "grok chat", "used_pct": 25, "remaining_pct": 75 },
    { "id": "high-cost-models", "label": "high cost models", "used_pct": 10, "remaining_pct": 90 },
    { "id": "low-cost-models", "label": "low cost models", "used_pct": 5, "remaining_pct": 95 }
  ]
}
'@ | Set-Content -Path $cursorFile -Encoding utf8
    $env:BOB_CURSOR_USAGE_FILE = $cursorFile
    $ircHome = Join-Path $bridgeRoot 'irc-issue-151'
    New-Item -ItemType Directory -Force -Path (Join-Path $ircHome 'bob-peers') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $ircHome 'moot') | Out-Null
    $env:BOB_IRC_HOME = $ircHome
    $env:AGENTIC_IRC_HOME = $ircHome
    $digest = @{
        v        = 1
        machines = @{
            flamingo = @{
                online     = $true
                workers    = 1
                working_on = 'digest worker fixture line'
                running    = 1
                lastSeen   = '2026-09-22T10:00:00Z'
            }
        }
    }
    $env:BOB_IRC_NICK = 'bob-ionos'
    $null = Add-TestBobIrcDigestWhisper -IrcHome $ircHome -Nick 'bob-ionos' -DigestObj $digest -ResetTrayPos
    $h = Get-BobTrayHover
    $txt = [string]$h.jobs_text
    if (@($h.cursor_groups).Count -lt 3) { throw "cursor_groups=$(@($h.cursor_groups).Count)" }
    if ($txt -notmatch '(?m)^[ ]+grok chat  75%') { throw "ionos local grok chat bar: $txt" }
    if ($txt -notmatch '(?m)^[ ]+high cost models  90%') { throw "ionos local high cost bar: $txt" }
    if ($txt -notmatch '(?m)^[ ]+low cost models  95%') { throw "ionos local low cost bar: $txt" }
    if ($txt -match '(?m)^[ ]+Smart Catalogue  (grok chat|high cost models|low cost models)') {
        throw 'xAI seat labels must not prefix Cursor spending bars'
    }
    if ($txt -match '(?m)^[ ]+low cost models  95%[^\r\n]*\r?\n[ ]+low cost models') {
        throw 'must not collapse Cursor groups into one low cost row only'
    }
    if ($txt -notmatch 'digest worker fixture line') { throw "flamingo irc worker line missing: $txt" }
    if ($txt -match '(?m)^[ ]+flamingo[^\r\n]*\r?\n[ ]+no jobs') { throw "flamingo tile must not lead with no jobs: $txt" }
    $skillUsage = Get-Content (Join-Path $RepoRoot '.grok\skills\box-usage\SKILL.md') -Raw
    if ($skillUsage -notmatch 'grok chat') { throw 'box-usage must document grok chat spending group' }
    if ($skillUsage -notmatch 'high cost models') { throw 'box-usage must document high cost models group' }
    if ($skillUsage -notmatch 'low cost models') { throw 'box-usage must document low cost models group' }

    $env:BOB_MACHINE_ID = $null
    $env:BOB_IRC_NICK = $null
    $env:BOB_IRC_HOME = $null
    $env:AGENTIC_IRC_HOME = $null
    $env:BOB_CURSOR_USAGE_FILE = $null
}

# --- BT0l6 systray Cursor overspend / help / section icons (issue #266) ---
Invoke-Case 'BT0l6 tray cursor overspend help icons' {
    $traySrc = Get-Content (Join-Path $RepoRoot 'tools\Watch-BobTray.ps1') -Raw
    if ($traySrc -notmatch 'function Format-BobTrayCursorOverspendLine') { throw 'Watch-BobTray must format Cursor overspend for the card' }
    if ($traySrc -notmatch "overspend \{0\}\{1:N2\}") { throw 'overspend line must be overspend Â£N.NN' }
    if ($traySrc -notmatch 'function Get-BobTrayCursorHelpTooltip') { throw 'Watch-BobTray must define Cursor help tooltip' }
    if ($traySrc -notmatch 'low cost models: Cursor build fuel gate') { throw 'help tooltip must name low-cost as Cursor build fuel gate' }
    if ($traySrc -notmatch 'grok chat:') { throw 'help tooltip must explain grok chat bracket' }
    if ($traySrc -notmatch 'high cost models:') { throw 'help tooltip must explain high cost models bracket' }
    if ($traySrc -notmatch 'function Add-BobTraySectionHeader') { throw 'Watch-BobTray must paint labelled Cursor vs Grok sections' }
    if ($traySrc -notmatch "Title 'Cursor'") { throw 'Cursor section label missing' }
    if ($traySrc -notmatch "Title 'Grok accounts'") { throw 'Grok accounts section label missing' }
    if ($traySrc -notmatch 'AccountOverageGbp') { throw 'Rebuild-BobTrayTiles must take account_overage_gbp from hover' }
    if ($traySrc -notmatch 'Get-BobTrayAgentImage') { throw 'section icons must reuse Get-BobTrayAgentImage (Agents menu parity)' }
    if ($traySrc -notmatch 'ExtractAssociatedIcon') { throw 'section icons must use ExtractAssociatedIcon on agent exes' }
    if ($traySrc -notmatch 'ToolTip') { throw 'help ? must use a ToolTip on hover' }
    if ($traySrc -notmatch 'function Set-BobTrayHelpTip') { throw 'TipForm ? must use Set-BobTrayHelpTip (MouseHover Show)' }
    if ($traySrc -notmatch 'RightText') { throw 'Cursor overspend must sit on section header RightText' }
    if ($traySrc -notmatch 'TextRenderer::MeasureText|TextRenderer\]::MeasureText') { throw 'overspend must MeasureText for right-align inside tile host' }
    if ($traySrc -notmatch '\$indent = 18') { throw 'Cursor pools and machines must share indent 18' }
    if ($traySrc -notmatch 'ToUpperInvariant') { throw 'machine names must render ALL CAPS' }
    $zero = 'overspend {0}{1:N2}' -f [char]0x00A3, 0.0
    if ($zero -match 'overspend') {
        # formatter must omit zero â€” contract checked via source branch on $v -le 0
        if ($traySrc -notmatch '\$v -le 0') { throw 'Format-BobTrayCursorOverspendLine must omit zero overspend' }
    }
    $pos = 'overspend {0}{1:N2}' -f [char]0x00A3, 12.34
    if ($pos -ne ('overspend {0}12.34' -f [char]0x00A3)) { throw "overspend format sample=$pos" }

    $ircSrc = Get-Content (Join-Path $RepoRoot 'src\Private\Get-BobIrc.ps1') -Raw
    if ($ircSrc -notmatch 'is operational') { throw 'first IRC peer write must announce machine is operational' }
    if ($ircSrc -notmatch "status\s*=\s*'operational'") { throw 'digest webhook status must be operational' }

    $hoverSrc = Get-Content (Join-Path $RepoRoot 'src\Public\Get-BobTrayHover.ps1') -Raw
    if ($hoverSrc -match "gid -eq 'low-cost-models'\) \{ \$heading") { throw 'reset must not be low-cost-only on headings' }
    if ($hoverSrc -notmatch 'sand_period_end') { throw 'grok chat reset must prefer sand_period_end' }
}

# --- BT0l24 shop channel + worker nick + reportUrl (issue #124) ---
Invoke-Case 'BT0l24 shop channel worker reportUrl' {
    param($bridgeRoot)
    $env:BOB_IRC_CONFIG = Join-Path $RepoRoot 'config\bobiverse.json'
    if ((Get-BobIrcShopChannel -MachineId ionos) -ne '#ionos') { throw 'ionos shop channel' }
    if ((Get-BobIrcShopChannel -MachineId dev1) -ne '#ce-priority-dev1') { throw 'dev1 shop alias' }
    if ((Get-BobIrcBuilderChannels -MachineId ionos) -ne '#bobiverse,#ionos') { throw 'builder channels ionos' }
    if ((Get-BobWorkerIrcNick -MachineId ionos -WorkerPid 4242) -ne 'w-io-4242') { throw 'worker nick ionos' }
    if ((Get-BobWorkerIrcNick -MachineId ce-priority-dev1 -WorkerPid 99) -ne 'w-d1-99') { throw 'worker nick dev1' }

    $cfg = Get-Content (Join-Path $RepoRoot 'config\bobiverse.json') -Raw | ConvertFrom-Json
    if (-not [string]$cfg.reportUrl) { throw 'config/bobiverse.json must define reportUrl' }
    if ([string]$cfg.reportUrl -match 'password=|xai_api_key=') { throw 'reportUrl must not embed secrets' }

    $ircSrc = Get-Content (Join-Path $RepoRoot 'src\Private\Get-BobIrc.ps1') -Raw
    if ($ircSrc -notmatch 'Invoke-WebRequest.*-Method POST') { throw 'digest webhook must POST only' }
    if ($ircSrc -match '-Method\s+Get') { throw 'digest webhook must not HTTP GET reportUrl' }

    $watchBv = Get-Content (Join-Path $RepoRoot 'tools\Watch-Bobiverse.ps1') -Raw
    if ($watchBv -notmatch 'Get-BobIrcBuilderChannels') { throw 'Watch-Bobiverse must join fleet + shop' }
    $installIrc = Get-Content (Join-Path $RepoRoot 'tools\Install-BobIrc.ps1') -Raw
    if ($installIrc -notmatch 'Get-BobIrcBuilderChannels') { throw 'Install-BobIrc agent must join fleet + shop' }
    if ($installIrc -notmatch 'mootChannel') { throw 'Install-BobIrc moot must stay on fleet channel only' }

    $workerSrc = Get-Content (Join-Path $RepoRoot 'src\Private\Start-BobWorkerIrcAgent.ps1') -Raw
    if ($workerSrc -notmatch 'start_worker_irc_agent\.py') { throw 'worker IRC spawn helper missing' }

    foreach ($root in @('C:\ai\agentic_irc', 'D:\ai\agentic_irc')) {
        $spawn = Join-Path $root 'scripts\start_worker_irc_agent.py'
        if (-not (Test-Path -LiteralPath $spawn)) { continue }
        $py = $null
        foreach ($c in @(
                (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe'),
                (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
                (Get-Command python.exe -ErrorAction SilentlyContinue).Source
            )) {
            if ($c -and (Test-Path -LiteralPath $c)) { $py = $c; break }
        }
        if (-not $py) { break }
        $dryLines = @(& $py $spawn --dry-run --machine-id ionos --pid 4242 2>&1)
        if ($LASTEXITCODE -ne 0 -or $dryLines.Count -eq 0) { break }
        $dry = ($dryLines | Out-String)
        if ($dry -notmatch 'w-io-4242') { throw "worker dry-run nick: $dry" }
        if ($dry -notmatch '#ionos') { throw "worker dry-run shop: $dry" }
        if ($dry -match '#bobiverse') { throw "worker dry-run must be shop-only: $dry" }
        break
    }

    $docsBv = Get-Content (Join-Path $RepoRoot 'docs\bobiverse.md') -Raw
    if ($docsBv -notmatch 'shop') { throw 'docs/bobiverse.md must document shop channels' }
    $skillIrc = Get-Content (Join-Path $RepoRoot '.grok\skills\bob-irc\SKILL.md') -Raw
    if ($skillIrc -notmatch 'shop') { throw 'bob-irc skill must mention shop JOIN' }
    $env:BOB_IRC_CONFIG = $null
}

# --- BT0p git-task capacity picker (issue #8) ---
Invoke-Case 'BT0p git-task picker' {
    param($bridgeRoot)
    $fixture = [pscustomobject]@{
        cursor_models = [pscustomobject]@{ remaining_pct = 99; period_end = '2026-10-01T00:00:00Z' }
        on_demand     = [pscustomobject]@{ remaining_pct = 0; enabled = $false }
        copilot       = [pscustomobject]@{ remaining_pct = 0; available = $false }
        machines      = @(
            [pscustomobject]@{
                id = 'ionos'; kind = 'windows'; gitEligible = $true; alive = $true; jobs = 0
                cwdRoots = @('C:\ai'); grok_build = [pscustomobject]@{ remaining_pct = 100; period_end = '2026-09-27T00:00:00Z' }
                grok_bot = [pscustomobject]@{ remaining_pct = 0; period_end = '2026-09-23T00:00:00Z' }
                fuels = @('cursor-models', 'grok-build', 'copilot', 'grok-bot')
            }
            [pscustomobject]@{
                id = 'flamingo'; kind = 'windows'; gitEligible = $true; alive = $true; jobs = 0
                cwdRoots = @('C:\ai'); grok_build = [pscustomobject]@{ remaining_pct = 85; period_end = '2026-09-27T00:00:00Z' }
                grok_bot = [pscustomobject]@{ remaining_pct = 0 }
                fuels = @('cursor-models', 'grok-build', 'copilot', 'grok-bot')
            }
            [pscustomobject]@{
                id = 'marchhare'; kind = 'windows'; gitEligible = $true; alive = $true; jobs = 0
                cwdRoots = @('C:\ai'); grok_build = [pscustomobject]@{ remaining_pct = 4; period_end = '2026-09-26T00:00:00Z' }
                grok_bot = [pscustomobject]@{ remaining_pct = 0 }
                fuels = @('cursor-models', 'grok-build', 'copilot', 'grok-bot')
            }
            [pscustomobject]@{
                id = '2012'; kind = 'dumb'; gitEligible = $false; alive = $true; jobs = 0
                cwdRoots = @(); grok_build = [pscustomobject]@{ remaining_pct = $null }
                grok_bot = [pscustomobject]@{ remaining_pct = $null }
                fuels = @()
            }
        )
    }

    $def = Select-BobGitWorker -Capacity $fixture
    if ($def.wait) { throw "default picker waited: $($def.reason)" }
    if ($def.fuel -ne 'cursor-models') { throw "default fuel=$($def.fuel) expected cursor-models" }
    if ($def.machine -eq '2012') { throw 'default picker selected DUMB' }
    if (@('ionos', 'flamingo', 'marchhare') -notcontains $def.machine) { throw "default machine=$($def.machine)" }
    if ($def.machine -ne 'ionos') { throw "default machine=$($def.machine) expected ionos (highest grok-build remaining tie-break)" }

    $gb = Select-BobGitWorker -Capacity $fixture -Fuel grok-build
    if ($gb.wait) { throw "grok-build picker waited: $($gb.reason)" }
    if ($gb.fuel -ne 'grok-build') { throw "grok-build fuel=$($gb.fuel)" }
    if ($gb.machine -ne 'ionos') { throw "grok-build machine=$($gb.machine) expected ionos over flamingo over marchhare" }

    $dumb = Select-BobGitWorker -Capacity $fixture -Machine '2012' -Fuel grok-build
    if (-not $dumb.wait) { throw 'pin DUMB must wait' }

    $pin = Select-BobGitWorker -Capacity $fixture -Machine flamingo -Fuel grok-build
    if ($pin.wait) { throw "pin wait: $($pin.reason)" }
    if ($pin.machine -ne 'flamingo' -or $pin.fuel -ne 'grok-build') { throw "pin=$($pin.machine)/$($pin.fuel)" }

    $empty = [pscustomobject]@{
        cursor_models = [pscustomobject]@{ remaining_pct = 0 }
        on_demand     = [pscustomobject]@{ remaining_pct = 10; enabled = $true }
        copilot       = [pscustomobject]@{ available = $false }
        machines      = @(
            [pscustomobject]@{
                id = 'ionos'; kind = 'windows'; gitEligible = $true; alive = $true; jobs = 0
                cwdRoots = @('C:\ai'); grok_build = [pscustomobject]@{ remaining_pct = 0 }
                grok_bot = [pscustomobject]@{ remaining_pct = 0 }
                fuels = @('cursor-models', 'grok-build', 'grok-bot', 'on-demand')
            }
        )
    }
    $wait = Select-BobGitWorker -Capacity $empty
    if (-not $wait.wait) { throw 'all included empty must wait when AllowOnDemand is false' }
    $od = Select-BobGitWorker -Capacity $empty -AllowOnDemand
    if ($od.wait) { throw "on-demand should pick: $($od.reason)" }
    if ($od.fuel -ne 'on-demand') { throw "on-demand fuel=$($od.fuel)" }

    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $capFile = Join-Path $bridgeRoot 'capacity.json'
    $liveFix = [pscustomobject]@{
        cursor_models = [pscustomobject]@{ remaining_pct = 99 }
        on_demand     = [pscustomobject]@{ remaining_pct = 0; enabled = $false }
        copilot       = [pscustomobject]@{ available = $false }
        machines      = @(
            [pscustomobject]@{
                id = 'testhost'; kind = 'windows'; gitEligible = $true; alive = $true; jobs = 0
                cwdRoots = @($bridgeRoot)
                grok_build = [pscustomobject]@{ remaining_pct = 50 }
                grok_bot = [pscustomobject]@{ remaining_pct = 0 }
                fuels = @('cursor-models', 'grok-build')
            }
        )
    }
    [IO.File]::WriteAllText($capFile, ($liveFix | ConvertTo-Json -Depth 8))
    $env:BOB_CAPACITY_FILE = $capFile
    $q = Start-BobBuild -Task git -Goal ping -Cwd (Join-Path $bridgeRoot 'cwd')
    if (-not $q.ok) { throw "git enqueue failed $($q | ConvertTo-Json -Compress)" }
    if ($q.wait) { throw "git enqueue waited: $($q.reason)" }
    if (-not $q.machine) { throw 'git job missing machine' }
    if ($q.fuel -ne 'cursor-models') { throw "git job fuel=$($q.fuel)" }
    $job = Get-BobBuild -JobId $q.jobId
    if ($job.task -ne 'git') { throw "job.task=$($job.task)" }
    if ($job.fuel -ne 'cursor-models') { throw "job.fuel=$($job.fuel)" }
    if (-not $job.machine) { throw 'job.machine empty' }
    if ($job.branch -notmatch '^work/') { throw "job.branch=$($job.branch)" }
    if ([string]$job.kind -ne 'build') { throw "git ping kind=$($job.kind)" }
    if ([string]$job.model -ne 'composer-2.5') { throw "cursor build model=$($job.model) expected composer-2.5" }
    $pinModel = Get-BobJobModel -Kind build -Fuel grok-build
    if ($pinModel -ne 'build0.1') { throw "grok build model=$pinModel expected build0.1" }
    $mrbC = Get-BobJobModel -Kind mrb -Fuel cursor-models
    if ($mrbC -ne 'grok-4.6') { throw "mrb cursor model=$mrbC" }
    $mrbG = Get-BobJobModel -Kind mrb -Fuel grok-build
    if ($mrbG -ne 'grok-4.6') { throw "mrb grok model=$mrbG" }
    $equiv = Resolve-BobGrokCliModel -Wanted 'build0.1'
    if ($equiv -eq 'build0.1') { throw 'Resolve-BobGrokCliModel must not pass unknown build0.1 to grok.exe -m' }
    if ($equiv -ne 'grok-4.5' -and $equiv -ne 'grok-4.6') { throw "build0.1 equivalent=$equiv" }
    $argvBuild = Start-BobWorker -Cwd (Join-Path $bridgeRoot 'cwd') -Prompt 'PONG' -Profile generic -Model 'build0.1' -WhatIfArgv -Force
    $argvText = ($argvBuild.argv -join ' ')
    if ($argvText -match '(^|\s)-m\s+build0\.1(\s|$)') { throw "argv still has -m build0.1: $argvText" }
    if ($argvText -notmatch '(^|\s)-m\s+grok-4\.(5|6)(\s|$)') { throw "argv missing grok catalog -m: $argvText" }

    $pinJob = Start-BobBuild -Task git -Machine testhost -Fuel grok-build -Goal ping -Cwd (Join-Path $bridgeRoot 'cwd')
    if ($pinJob.machine -ne 'testhost' -or $pinJob.fuel -ne 'grok-build') {
        throw "pin job $($pinJob.machine)/$($pinJob.fuel)"
    }

    $fix = Start-BobBuild -Task git -Fix -Goal ping -Cwd (Join-Path $bridgeRoot 'cwd')
    if ($fix.fuel -ne 'cursor-models') { throw "FIX picker fuel=$($fix.fuel) (must re-run, not stick on grok-build)" }

    $env:BOB_CAPACITY_FILE = $null
}

# --- BT0q kind mrb cursor packet (issue #10 fix 2) ---
Invoke-Case 'BT0q kind mrb packet' {
    param($bridgeRoot)
    $cfgPath = Join-Path $RepoRoot 'config\default.json'
    $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
    $expectedMrb = [string]$cfg.models.mrbCursor
    if (-not $expectedMrb) { throw 'config models.mrbCursor missing' }
    $cursor = Join-Path $RepoRoot 'tools\Start-BobCursor.ps1'
    $jobCwd = Join-Path $bridgeRoot 'mrb-cwd'
    New-Item -ItemType Directory -Force -Path $jobCwd | Out-Null
    $job = [pscustomobject]@{
        id     = [guid]::NewGuid().ToString()
        repo   = 'https://github.com/SimonBarnett/agentic_build'
        cwd    = $jobCwd
        goal   = 'Hostile MRB fixture'
        kind   = 'mrb'
        fuel   = 'cursor-models'
        task   = 'git'
        branch = 'work/mrb-fixture'
    }
    $r = & $cursor -Job $job -NoLaunch
    if ($r.started) { throw 'Start-BobCursor -NoLaunch must not start an agent' }
    if ([string]$r.startError -ne 'no_launch') { throw "startError=$($r.startError) expected no_launch" }
    Assert-BobCursorJobNotSpawned -JobId $job.id
    if (-not $r.packetPath -or -not (Test-Path $r.packetPath)) { throw 'missing cursor handoff packet' }
    $packet = Get-Content $r.packetPath -Raw | ConvertFrom-Json
    if ([string]$packet.kind -ne 'mrb') { throw "packet.kind=$($packet.kind)" }
    if ([string]$packet.model -eq 'composer-2.5') { throw 'kind=mrb must not resolve composer-2.5' }
    if ([string]$packet.model -ne $expectedMrb) { throw "packet.model=$($packet.model) expected $expectedMrb" }
}

# Start-BobCursor must not Win32_Process-launch under Fake-Grok (BOB_GROK_EXE); fleet tick still completes.
Invoke-Case 'BT0q2 fleet mrb cursor suppress' {
    param($bridgeRoot)
    $cfg = Get-Content (Join-Path $RepoRoot 'config\default.json') -Raw | ConvertFrom-Json
    $expectedMrb = [string]$cfg.models.mrbCursor
    $cwd = Join-Path $bridgeRoot 'cwd'
    if ($env:BOB_GROK_EXE -notmatch '(?i)Fake-Grok') { throw 'BOB_GROK_EXE must be Fake-Grok for suppress seam' }
    $cursor = Join-Path $RepoRoot 'tools\Start-BobCursor.ps1'
    $direct = & $cursor -Repo 'https://github.com/SimonBarnett/agentic_build' -Cwd $cwd -Goal 'MRB suppress probe' -Kind mrb -Mrb 'https://github.com/SimonBarnett/agentic_build/issues/1' -NoLaunch
    if ($direct.started) { throw 'Start-BobCursor -NoLaunch must not launch cursor-agent' }
    if ([string]$direct.startError -ne 'no_launch') { throw "startError=$($direct.startError) expected no_launch" }
    if ($direct.pid) { throw "unexpected pid=$($direct.pid)" }
    Assert-BobCursorJobNotSpawned -JobId $direct.jobId
    if (-not $direct.packetPath -or -not (Test-Path $direct.packetPath)) { throw 'missing cursor handoff packet' }

    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $env:BOB_MACHINE_ID = 'testhost'
    $capFile = Join-Path $bridgeRoot 'capacity.json'
    $liveFix = [pscustomobject]@{
        cursor_models = [pscustomobject]@{ remaining_pct = 99 }
        on_demand     = [pscustomobject]@{ remaining_pct = 0; enabled = $false }
        copilot       = [pscustomobject]@{ available = $false }
        machines      = @(
            [pscustomobject]@{
                id = 'testhost'; kind = 'windows'; gitEligible = $true; alive = $true; jobs = 0
                cwdRoots = @($bridgeRoot)
                grok_build = [pscustomobject]@{ remaining_pct = 50 }
                grok_bot = [pscustomobject]@{ remaining_pct = 0 }
                fuels = @('cursor-models', 'grok-build')
            }
        )
    }
    [IO.File]::WriteAllText($capFile, ($liveFix | ConvertTo-Json -Depth 8))
    $env:BOB_CAPACITY_FILE = $capFile
    $q = Start-BobBuild -Task git -Fuel cursor-models -Kind mrb -Goal 'MRB fleet fixture' -Cwd $cwd -Repo 'https://github.com/SimonBarnett/agentic_build'
    if (-not $q.ok) { throw "enqueue failed $($q | ConvertTo-Json -Compress)" }
    $watch = Join-Path $RepoRoot 'tools\Watch-BobJobs.ps1'
    & $watch -Once -RepoRoot $RepoRoot | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Watch-BobJobs exit $LASTEXITCODE" }
    $done = Get-BobBuild -JobId $q.jobId
    if ($done.lane -ne 'outbox') { throw "lane=$($done.lane)" }
    if ($done.state -ne 'done') { throw "state=$($done.state)" }
    if ([string]$done.kind -ne 'mrb') { throw "job.kind=$($done.kind)" }
    if ([string]$done.model -ne $expectedMrb) { throw "job.model=$($done.model)" }
    if ([string]$done.fuel -ne 'cursor-models') { throw "job.fuel=$($done.fuel)" }
    if (-not $done.completion -or $done.completion.status -ne 'ok') { throw 'fleet cursor-models handoff must complete ok' }
    Assert-BobCursorJobNotSpawned -JobId $q.jobId
}

# --- BT0q3 invalid git kind refused at enqueue (issue #12) ---
Invoke-Case 'BT0q3 invalid git kind enqueue' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $env:BOB_MACHINE_ID = 'testhost'
    $capFile = Join-Path $bridgeRoot 'capacity.json'
    $liveFix = [pscustomobject]@{
        cursor_models = [pscustomobject]@{ remaining_pct = 99 }
        on_demand     = [pscustomobject]@{ remaining_pct = 0; enabled = $false }
        copilot       = [pscustomobject]@{ available = $false }
        machines      = @(
            [pscustomobject]@{
                id = 'testhost'; kind = 'windows'; gitEligible = $true; alive = $true; jobs = 0
                cwdRoots = @($bridgeRoot)
                grok_build = [pscustomobject]@{ remaining_pct = 50 }
                grok_bot = [pscustomobject]@{ remaining_pct = 0 }
                fuels = @('cursor-models', 'grok-build')
            }
        )
    }
    [IO.File]::WriteAllText($capFile, ($liveFix | ConvertTo-Json -Depth 8))
    $env:BOB_CAPACITY_FILE = $capFile
    $bad = Start-BobBuild -Task git -Fuel cursor-models -Kind 'wat' -Goal 'bad kind fixture' -Cwd $cwd -Repo 'https://github.com/SimonBarnett/agentic_build'
    if ($bad.ok) { throw 'invalid kind must not enqueue' }
    if ([string]$bad.error -ne 'invalid_kind') { throw "error=$($bad.error) expected invalid_kind" }
    $inbox = Join-Path $bridgeRoot 'fleet\inbox\testhost'
    if (Test-Path $inbox) {
        $left = @(Get-ChildItem $inbox -Filter '*.json' -ErrorAction SilentlyContinue)
        if ($left.Count -gt 0) { throw "inbox must stay empty after invalid_kind ($($left.Count) files)" }
    }
}

# --- BT0rÃ¢â‚¬â€œBT0u Start-BobMrb / gh preflight (issue #13) ---
Invoke-Case 'BT0r mrb body-file' {
    param($bridgeRoot)
    $fakeGh = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $log = Join-Path $bridgeRoot 'fake-gh.jsonl'
    $savedGh = $env:BOB_GH_EXE
    $savedMode = $env:BOB_FAKE_GH_MODE
    $savedLog = $env:BOB_FAKE_GH_LOG
    $env:BOB_GH_EXE = $fakeGh
    $env:BOB_FAKE_GH_MODE = 'ok'
    $env:BOB_FAKE_GH_LOG = $log
    try {
        $body = @'
Verdict line with "double quotes", `backticks`, and $dollar.

```powershell
Write-Output "fenced"
```
'@
        $mrb = Join-Path $RepoRoot 'tools\Start-BobMrb.ps1'
        $r = & $mrb -Repo 'fixture/repo' -Title 'quote test' -Verdict FAIL -Body $body
        if (-not $r.ok) { throw 'Start-BobMrb failed' }
        if (-not (Test-Path $log)) { throw 'fake gh log missing' }
        $row = (Get-Content $log | Select-Object -Last 1) | ConvertFrom-Json
        if ([string]$row.body -ne $body) { throw 'body round-trip mismatch' }
        if ($row.argv -notmatch '--body-file') { throw 'gh must use --body-file' }
        if ($row.argv -match '--body\s') { throw 'gh must not use --body argv' }
    }
    finally {
        $env:BOB_GH_EXE = $savedGh
        $env:BOB_FAKE_GH_MODE = $savedMode
        $env:BOB_FAKE_GH_LOG = $savedLog
    }
}

Invoke-Case 'BT0s mrb label skip' {
    param($bridgeRoot)
    $fakeGh = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $log = Join-Path $bridgeRoot 'fake-gh-label.jsonl'
    $savedGh = $env:BOB_GH_EXE
    $savedMode = $env:BOB_FAKE_GH_MODE
    $savedLog = $env:BOB_FAKE_GH_LOG
    $env:BOB_GH_EXE = $fakeGh
    $env:BOB_FAKE_GH_MODE = 'label-fail'
    $env:BOB_FAKE_GH_LOG = $log
    $env:BOB_FAKE_GH_QUIET = '1'
    try {
        $mrb = Join-Path $RepoRoot 'tools\Start-BobMrb.ps1'
        $r = & $mrb -Repo 'fixture/repo' -Title 'label skip' -Verdict FAIL -Body 'plain body' 2>$null
        if (-not $r.ok) { throw 'issue create should succeed without labels' }
        if ($r.labelsApplied -contains 'mrb-fail') { throw 'mrb-fail should be dropped when create fails' }
        if ($r.labelsDropped -notcontains 'mrb-fail') { throw "labelsDropped=$($r.labelsDropped -join ',')" }
        $row = (Get-Content $log | Select-Object -Last 1) | ConvertFrom-Json
        if ([string]$row.body -notmatch 'Labels not applied') { throw 'body must note dropped labels' }
    }
    finally {
        $env:BOB_GH_EXE = $savedGh
        $env:BOB_FAKE_GH_MODE = $savedMode
        $env:BOB_FAKE_GH_LOG = $savedLog
        $env:BOB_FAKE_GH_QUIET = $null
    }
}

Invoke-Case 'BT0t gh preflight absent' {
    param($bridgeRoot)
    . (Join-Path $RepoRoot 'tools\Bob-Gh.ps1')
    $savedGh = $env:BOB_GH_EXE
    $env:BOB_GH_EXE = Join-Path $bridgeRoot 'no-such-gh.exe'
    try {
        $null = Test-BobGhIssuePosting -Repo 'fixture/repo'
        throw 'preflight should fail when gh absent'
    }
    catch {
        if ($_.Exception.Message -notmatch 'gh\.exe not found') { throw $_.Exception.Message }
    }
    finally {
        $env:BOB_GH_EXE = $savedGh
    }
}

Invoke-Case 'BT0u gh preflight dead token' {
    param($bridgeRoot)
    . (Join-Path $RepoRoot 'tools\Bob-Gh.ps1')
    $fakeGh = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $savedGh = $env:BOB_GH_EXE
    $savedMode = $env:BOB_FAKE_GH_MODE
    $env:BOB_GH_EXE = $fakeGh
    $env:BOB_FAKE_GH_MODE = 'dead'
    try {
        $null = Test-BobGhIssuePosting -Repo 'fixture/repo'
        throw 'preflight should fail on dead token'
    }
    catch {
        if ($_.Exception.Message -notmatch 'gh auth login') { throw $_.Exception.Message }
    }
    finally {
        $env:BOB_GH_EXE = $savedGh
        $env:BOB_FAKE_GH_MODE = $savedMode
    }
}

# --- BT0v Start-BobMrbHandoff (issue #16 fix 3) ---
function New-Bt0vCapacity {
    param([string]$BridgeRoot)
    $capFile = Join-Path $BridgeRoot 'capacity-mrb.json'
    $liveFix = [pscustomobject]@{
        cursor_models = [pscustomobject]@{ remaining_pct = 99 }
        on_demand     = [pscustomobject]@{ remaining_pct = 0; enabled = $false }
        copilot       = [pscustomobject]@{ available = $false }
        machines      = @(
            [pscustomobject]@{
                id = 'testhost'; kind = 'windows'; gitEligible = $true; alive = $true; jobs = 0
                cwdRoots = @($BridgeRoot)
                grok_build = [pscustomobject]@{ remaining_pct = 50 }
                grok_bot = [pscustomobject]@{ remaining_pct = 0 }
                fuels = @('cursor-models', 'grok-build')
            }
        )
    }
    [IO.File]::WriteAllText($capFile, ($liveFix | ConvertTo-Json -Depth 8))
    return $capFile
}

Invoke-Case 'BT0v1 mrb handoff remote refuse' {
    param($bridgeRoot)
    $handoff = Join-Path $RepoRoot 'tools\Start-BobMrbHandoff.ps1'
    $fakeGh = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $env:BOB_MACHINE_ID = 'testhost'
    $env:BOB_GH_EXE = $fakeGh
    $env:BOB_FAKE_GH_MODE = 'ok'
    $pick = [pscustomobject]@{ wait = $false; machine = 'flamingo'; fuel = 'grok-build'; reason = $null }
    try {
        & $handoff -Issue 16 -Repo 'fixture/repo' -Fuel grok-build -TestSkipCursor -TestGitWorkerResult $pick -Cwd (Join-Path $bridgeRoot 'cwd')
        throw 'expected remote worker refuse'
    }
    catch {
        if ($_.Exception.Message -notmatch 'cannot verify worker') { throw $_.Exception.Message }
    }
}

Invoke-Case 'BT0v2 mrb handoff identity refuse' {
    param($bridgeRoot)
    $handoff = Join-Path $RepoRoot 'tools\Start-BobMrbHandoff.ps1'
    $fakeGh = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $env:BOB_GH_EXE = $fakeGh
    $env:BOB_FAKE_GH_MODE = 'ok'
    $pick = [pscustomobject]@{ wait = $false; machine = 'testhost'; fuel = 'grok-build'; reason = $null }
    try {
        & $handoff -Issue 16 -Repo 'fixture/repo' -Fuel grok-build -TestSkipCursor -TestGitWorkerResult $pick -Cwd (Join-Path $bridgeRoot 'cwd')
        throw 'expected identity refuse'
    }
    catch {
        if ($_.Exception.Message -notmatch 'cannot resolve this machine identity') { throw $_.Exception.Message }
    }
}

Invoke-Case 'BT0v3 mrb handoff local packet' {
    param($bridgeRoot)
    $cfg = Get-Content (Join-Path $RepoRoot 'config\default.json') -Raw | ConvertFrom-Json
    $expectedMrb = [string]$cfg.models.mrbGrok
    $handoff = Join-Path $RepoRoot 'tools\Start-BobMrbHandoff.ps1'
    $fakeGh = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $ghLog = Join-Path $bridgeRoot 'handoff-gh.jsonl'
    $cwd = Join-Path $bridgeRoot 'cwd'
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $env:BOB_MACHINE_ID = 'testhost'
    $env:BOB_CAPACITY_FILE = New-Bt0vCapacity -BridgeRoot $bridgeRoot
    $env:BOB_GH_EXE = $fakeGh
    $env:BOB_FAKE_GH_MODE = 'ok'
    $env:BOB_FAKE_GH_LOG = $ghLog
    $pick = [pscustomobject]@{ wait = $false; machine = 'testhost'; fuel = 'grok-build'; reason = $null }
    $r = & $handoff -Issue 16 -Repo 'fixture/repo' -Fuel grok-build -TestSkipCursor -TestGitWorkerResult $pick -Cwd $cwd
    if (-not $r.ok) { throw "handoff failed $($r | ConvertTo-Json -Compress)" }
    if ($r.handed -ne 'grok-build') { throw "handed=$($r.handed)" }
    if (-not (Test-Path $r.path)) { throw 'missing inbox packet' }
    if (-not (Test-Path $ghLog)) { throw 'gh preflight log missing' }
    $ghRows = @(Get-Content $ghLog | ForEach-Object { $_ | ConvertFrom-Json })
    if (-not ($ghRows | Where-Object { $_.command -eq 'auth status' })) { throw 'preflight must log auth status' }
    $repoProbe = @($ghRows | Where-Object { $_.command -eq 'repo view' })
    if ($repoProbe.Count -lt 1) { throw 'preflight must log repo view' }
    if (($repoProbe[0].argv -join ' ') -notmatch 'fixture/repo') { throw 'repo view must target fixture/repo' }
    $packet = Get-Content $r.path -Raw | ConvertFrom-Json
    $mrbUrl = 'https://github.com/fixture/repo/issues/16'
    if ([string]$packet.mrb -ne $mrbUrl) { throw "packet.mrb=$($packet.mrb)" }
    if ([string]$packet.kind -ne 'mrb') { throw "packet.kind=$($packet.kind)" }
    if ([string]$packet.model -ne $expectedMrb) { throw "packet.model=$($packet.model) expected $expectedMrb" }
}

Invoke-Case 'BT0w mrb handoff skip cursor fuel refuse' {
    param($bridgeRoot)
    $handoff = Join-Path $RepoRoot 'tools\Start-BobMrbHandoff.ps1'
    $pick = [pscustomobject]@{ wait = $false; machine = 'testhost'; fuel = 'grok-build'; reason = $null }
    try {
        & $handoff -Issue 16 -Repo 'fixture/repo' -Fuel cursor-models -TestSkipCursor -TestGitWorkerResult $pick -Cwd (Join-Path $bridgeRoot 'cwd')
        throw 'cursor-models + TestSkipCursor must refuse'
    }
    catch {
        if ($_.Exception.Message -notmatch 'TestSkipCursor') { throw $_.Exception.Message }
    }
}

# --- BT0x fuel/model compatibility gate (issue #17) ---
Invoke-Case 'BT0x1 fuel model enqueue refuse' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $bad = Start-BobBuild -Machine testhost -Cwd $cwd -Goal 'PONG' -Profile generic -Fuel grok-build -Model 'composer-2.5'
    if ($bad.ok) { throw 'mismatched fuel/model must not enqueue' }
    if ([string]$bad.error -ne 'fuel_model_mismatch') { throw "error=$($bad.error)" }
    if ([string]$bad.reason -notmatch 'fuel_model_mismatch') { throw "reason=$($bad.reason)" }
    $inbox = Join-Path $bridgeRoot 'fleet\inbox\testhost'
    if (Test-Path $inbox) {
        $left = @(Get-ChildItem $inbox -Filter '*.json' -ErrorAction SilentlyContinue).Count
        if ($left -gt 0) { throw "inbox still has $left packet(s) after refuse" }
    }
}

Invoke-Case 'BT0x2 fuel model tick refuse' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $env:BOB_MACHINE_ID = 'testhost'
    $jobId = [guid]::NewGuid().ToString()
    $packet = [pscustomobject]@{
        id            = $jobId
        from          = 'test'
        goal          = 'PONG'
        machine       = 'testhost'
        cwd           = $cwd
        profile       = 'generic'
        createdAt     = [DateTime]::UtcNow.ToString('o')
        fuel          = 'grok-build'
        model         = 'claude-opus-5-thinking-high'
        task          = 'fleet'
        kind          = 'build'
    }
    $inDir = Join-Path $bridgeRoot 'fleet\inbox\testhost'
    New-Item -ItemType Directory -Force -Path $inDir | Out-Null
    $inPath = Join-Path $inDir ($jobId + '.json')
    [IO.File]::WriteAllText($inPath, ($packet | ConvertTo-Json -Depth 8))
    $sessDir = Join-Path $bridgeRoot 'fake-grok-home\sessions'
    $before = 0
    if (Test-Path $sessDir) { $before = @(Get-ChildItem $sessDir -Filter '*.json' -ErrorAction SilentlyContinue).Count }
    Invoke-BobFleetTick | Out-Null
    $after = 0
    if (Test-Path $sessDir) { $after = @(Get-ChildItem $sessDir -Filter '*.json' -ErrorAction SilentlyContinue).Count }
    if ($after -ne $before) { throw "Fake-Grok sessions grew $before -> $after (grok.exe must not start)" }
    $done = Get-BobBuild -JobId $jobId
    if ($done.lane -ne 'outbox') { throw "lane=$($done.lane)" }
    if ($done.state -ne 'failed') { throw "state=$($done.state)" }
    if (-not $done.completion -or $done.completion.status -ne 'failed') { throw 'completion not failed' }
    if ([string]$done.completion.summary -notmatch 'fuel_model_mismatch') { throw "summary=$($done.completion.summary)" }
}

Invoke-Case 'BT0x3 fuel model matched enqueue' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $cfg = Get-Content (Join-Path $RepoRoot 'config\default.json') -Raw | ConvertFrom-Json
    if (-not $cfg.fuelModelFamilies) { throw 'config fuelModelFamilies missing' }
    $pairs = [ordered]@{
        'cursor-models' = [string]$cfg.models.buildCursor
        'grok-build'    = [string]$cfg.models.buildGrok
        'grok-bot'      = 'grok-4.6'
        'on-demand'     = [string]$cfg.models.buildGrokFallback
        'copilot'       = $null
    }
    foreach ($fuel in $pairs.Keys) {
        $model = $pairs[$fuel]
        $args = @{
            Machine = 'testhost'
            Cwd     = $cwd
            Goal    = 'PONG'
            Profile = 'generic'
            Fuel    = $fuel
        }
        if ($model) { $args['Model'] = $model }
        $q = Start-BobBuild @args
        if (-not $q.ok) { throw "fuel=$fuel model=$model enqueue failed $($q | ConvertTo-Json -Compress)" }
        if ([string]$q.fuel -ne $fuel) { throw "fuel=$fuel got $($q.fuel)" }
        $job = Get-BobBuild -JobId $q.jobId
        if ($job.lane -ne 'inbox') { throw "fuel=$fuel lane=$($job.lane)" }
    }
    $src = Get-Content (Join-Path $RepoRoot 'src\Public\Get-BobCapacity.ps1') -Raw
    if ($src -match 'fuel_model_mismatch fuel=grok-build model=composer') { throw 'hard-coded mismatch string in Get-BobCapacity' }
    if ($src -notmatch 'Get-BobFuelModelConfig') { throw 'mapping must use Get-BobFuelModelConfig' }
}

Invoke-Case 'BT0x4 fuel model matched tick' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $env:BOB_MACHINE_ID = 'testhost'
    $q = Start-BobBuild -Machine testhost -Cwd $cwd -Goal 'PONG' -Profile generic -Fuel grok-build -Model 'build0.1'
    if (-not $q.ok) { throw "enqueue failed $($q | ConvertTo-Json -Compress)" }
    $watch = Join-Path $RepoRoot 'tools\Watch-BobJobs.ps1'
    & $watch -Once -RepoRoot $RepoRoot | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Watch-BobJobs exit $LASTEXITCODE" }
    $done = Get-BobBuild -JobId $q.jobId
    if ($done.lane -ne 'outbox') { throw "lane=$($done.lane)" }
    if ($done.state -ne 'done') { throw "state=$($done.state)" }
    if (-not $done.completion -or $done.completion.status -ne 'ok') { throw 'matched grok-build tick must complete ok' }
}

# --- BT0y empty fuel packet gate (issue #80) ---
function Test-BT0yEmptyFuelModelTickRefuse {
    param(
        $bridgeRoot,
        [string]$ModelId,
        [string]$CaseLabel
    )
    $cwd = Join-Path $bridgeRoot 'cwd'
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $env:BOB_MACHINE_ID = 'testhost'
    $jobId = [guid]::NewGuid().ToString()
    $packet = [pscustomobject]@{
        id        = $jobId
        from      = 'test'
        goal      = 'PONG'
        machine   = 'testhost'
        cwd       = $cwd
        profile   = 'generic'
        createdAt = [DateTime]::UtcNow.ToString('o')
        model     = $ModelId
        task      = 'fleet'
        kind      = 'build'
    }
    $inDir = Join-Path $bridgeRoot 'fleet\inbox\testhost'
    New-Item -ItemType Directory -Force -Path $inDir | Out-Null
    $inPath = Join-Path $inDir ($jobId + '.json')
    [IO.File]::WriteAllText($inPath, ($packet | ConvertTo-Json -Depth 8))
    $sessDir = Join-Path $bridgeRoot 'fake-grok-home\sessions'
    $before = 0
    if (Test-Path $sessDir) { $before = @(Get-ChildItem $sessDir -Filter '*.json' -ErrorAction SilentlyContinue).Count }
    Invoke-BobFleetTick | Out-Null
    $after = 0
    if (Test-Path $sessDir) { $after = @(Get-ChildItem $sessDir -Filter '*.json' -ErrorAction SilentlyContinue).Count }
    if ($after -ne $before) { throw "$CaseLabel Fake-Grok sessions grew $before -> $after (grok.exe must not start)" }
    $done = Get-BobBuild -JobId $jobId
    if ($done.lane -ne 'outbox') { throw "$CaseLabel lane=$($done.lane)" }
    if ($done.state -ne 'failed') { throw "$CaseLabel state=$($done.state)" }
    if (-not $done.completion -or $done.completion.status -ne 'failed') { throw "$CaseLabel completion not failed" }
    if ([string]$done.completion.summary -notmatch 'missing_fuel') { throw "$CaseLabel summary=$($done.completion.summary)" }
    if ([string]$done.completion.summary -notmatch "missing_fuel model=$ModelId") { throw "$CaseLabel summary=$($done.completion.summary)" }
}

Invoke-Case 'BT0y1 empty fuel model tick refuse' {
    param($bridgeRoot)
    Test-BT0yEmptyFuelModelTickRefuse -bridgeRoot $bridgeRoot -ModelId 'composer-2.5' -CaseLabel 'BT0y1'
}

Invoke-Case 'BT0y2 empty fuel build0.1 tick refuse' {
    param($bridgeRoot)
    Test-BT0yEmptyFuelModelTickRefuse -bridgeRoot $bridgeRoot -ModelId 'build0.1' -CaseLabel 'BT0y2'
}

Invoke-Case 'BT0y3 empty fuel grok-4.6 tick refuse' {
    param($bridgeRoot)
    Test-BT0yEmptyFuelModelTickRefuse -bridgeRoot $bridgeRoot -ModelId 'grok-4.6' -CaseLabel 'BT0y3'
}

Invoke-Case 'BT0y4 empty fuel unknown model tick refuse' {
    param($bridgeRoot)
    Test-BT0yEmptyFuelModelTickRefuse -bridgeRoot $bridgeRoot -ModelId 'not-a-known-family-id' -CaseLabel 'BT0y4'
}

# --- BT0z empty fuel and model packet gate (issue #79) ---
function Test-BT0zEmptyFuelAndModelTickRefuse {
    param(
        $bridgeRoot,
        [string]$CaseLabel
    )
    $cwd = Join-Path $bridgeRoot 'cwd'
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $env:BOB_MACHINE_ID = 'testhost'
    $jobId = [guid]::NewGuid().ToString()
    $packet = [pscustomobject]@{
        id        = $jobId
        from      = 'test'
        goal      = 'PONG'
        machine   = 'testhost'
        cwd       = $cwd
        profile   = 'generic'
        createdAt = [DateTime]::UtcNow.ToString('o')
        task      = 'fleet'
        kind      = 'build'
    }
    $inDir = Join-Path $bridgeRoot 'fleet\inbox\testhost'
    New-Item -ItemType Directory -Force -Path $inDir | Out-Null
    $inPath = Join-Path $inDir ($jobId + '.json')
    [IO.File]::WriteAllText($inPath, ($packet | ConvertTo-Json -Depth 8))
    $sessDir = Join-Path $bridgeRoot 'fake-grok-home\sessions'
    $before = 0
    if (Test-Path $sessDir) { $before = @(Get-ChildItem $sessDir -Filter '*.json' -ErrorAction SilentlyContinue).Count }
    Invoke-BobFleetTick | Out-Null
    $after = 0
    if (Test-Path $sessDir) { $after = @(Get-ChildItem $sessDir -Filter '*.json' -ErrorAction SilentlyContinue).Count }
    if ($after -ne $before) { throw "$CaseLabel Fake-Grok sessions grew $before -> $after (grok.exe must not start)" }
    $done = Get-BobBuild -JobId $jobId
    if ($done.lane -ne 'outbox') { throw "$CaseLabel lane=$($done.lane)" }
    if ($done.state -ne 'failed') { throw "$CaseLabel state=$($done.state)" }
    if (-not $done.completion -or $done.completion.status -ne 'failed') { throw "$CaseLabel completion not failed" }
    if ([string]$done.completion.summary -ne 'missing_fuel_and_model') { throw "$CaseLabel summary=$($done.completion.summary)" }
}

Invoke-Case 'BT0z1 empty fuel and model tick refuse' {
    param($bridgeRoot)
    Test-BT0zEmptyFuelAndModelTickRefuse -bridgeRoot $bridgeRoot -CaseLabel 'BT0z1'
}

# --- BT0loop Start-BobBuildLoop (issue mrb-loop-automation / #44) ---
. (Join-Path $RepoRoot 'tools\Bob-BuildLoop.ps1')

Invoke-Case 'BT0loop1 required-fixes parse' {
    param($bridgeRoot)
    $body = @'
## Verdict
FAIL

## Required fixes
- Gate A still red
- Do not invent API Foo

## Nits
- typo
'@
    $fixes = Get-BobMrbRequiredFixes $body
    if ($fixes -notmatch 'Gate A still red') { throw "fixes missing gate: $fixes" }
    if ($fixes -notmatch 'Do not invent API Foo') { throw 'fixes missing API line' }
    if ($fixes -match 'typo') { throw 'nits leaked into required fixes' }
    if ($fixes -match 'PASS-UAT') { throw 'UAT must not appear' }
}

Invoke-Case 'BT0loop2 backlink payload' {
    param($bridgeRoot)
    $payload = New-BobMrbBacklinkComment -Url 'https://github.com/fixture/repo/issues/9' -Sha 'abc1234dead'
    if ($payload -notmatch 'https://github.com/fixture/repo/issues/9') { throw "payload missing url: $payload" }
    if ($payload -notmatch 'abc1234dead') { throw "payload missing sha: $payload" }
    if ($payload -notmatch '^Next board:') { throw "payload prefix: $payload" }
    $pr = New-BobFixPrComment -Url 'https://github.com/fixture/repo/pull/4' -Sha 'abc1234dead'
    if ($pr -notmatch 'FIX PR:') { throw "fix pr payload: $pr" }
}

Invoke-Case 'BT0loop3 state file round-trip' {
    param($bridgeRoot)
    $path = Get-BobBuildLoopStatePath -Repo 'fixture/repo' -Issue 19
    $root = [IO.Path]::GetFullPath($env:BOB_BRIDGE_HOME)
    if (-not $path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw "state path not under test bridge: $path (root $root)" }
    $liveBridge = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.grok\bob-bridge'))
    if ($path.StartsWith($liveBridge, [StringComparison]::OrdinalIgnoreCase)) { throw 'must not use live bob-bridge' }
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Sha 'deadbeefcafebabe' -Cwd (Join-Path $bridgeRoot 'cwd')
    $row = [pscustomobject]@{ sha = 'deadbeefcafebabe'; pr = 'https://github.com/fixture/repo/pull/2'; mrb = 'https://github.com/fixture/repo/issues/8'; verdict = 'FAIL'; issue = 8 }
    $state = Add-BobBuildLoopPass -State $state -Pass $row
    Write-BobBuildLoopState -Path $path -State $state
    $board = Get-BobMrbBoard -Repo 'fixture/repo' -Issue 19 -Path $path
    if ([int]$board.issue -ne 19) { throw "issue=$($board.issue)" }
    if ([string]$board.sha -ne 'deadbeefcafebabe') { throw "sha=$($board.sha)" }
    if ([string]$board.verdict -ne 'FAIL') { throw "verdict=$($board.verdict)" }
    if (@($board.passes).Count -ne 1) { throw 'expected one pass row' }
}

Invoke-Case 'BT0loop4 wait_pr retry on dead job' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Cwd (Join-Path $bridgeRoot 'cwd') -MaxJobRetries 3
    $state.phase = 'wait_pr'
    $state.jobAttempts = 1
    $state.currentPid = 4242
    $state.currentKind = 'build'
    $world = [pscustomobject]@{
        Job          = [pscustomobject]@{ pid = 4242; startError = $null; started = $true }
        ProcessAlive = $false
        Prs          = @()
        Issues       = @()
    }
    $d = Get-BobBuildLoopDecision -State $state -World $world
    if ($d.action -ne 'retry_job') { throw "action=$($d.action)" }
    if ($d.kind -ne 'build') { throw "kind=$($d.kind)" }
}

Invoke-Case 'BT0loop4b wait_pr retry on start refused (state startError)' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Cwd (Join-Path $bridgeRoot 'cwd') -MaxJobRetries 3
    $state.phase = 'wait_pr'
    $state.jobAttempts = 1
    $state.currentKind = 'build'
    $state.startError = 'enqueue refused'
    $state.currentPid = $null
    $state.currentJobId = 'job-refused'
    $world = [pscustomobject]@{
        Job          = $null
        ProcessAlive = $null
        Prs          = @()
        Issues       = @()
    }
    $d = Get-BobBuildLoopDecision -State $state -World $world
    if ($d.action -ne 'retry_job') { throw "action=$($d.action)" }
    if ($d.kind -ne 'build') { throw "kind=$($d.kind)" }
}

Invoke-Case 'BT0loop4c wait_mrb retry on refused-start world' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd (Join-Path $bridgeRoot 'cwd') -MaxJobRetries 3
    $state.phase = 'wait_mrb'
    $state.jobAttempts = 1
    $state.currentKind = 'mrb'
    $state.startError = 'MRB handoff enqueue failed (fixture)'
    $state.currentPid = $null
    $state.currentJobId = $null
    $world = [pscustomobject]@{
        Job          = $null
        ProcessAlive = $null
        Prs          = @()
        Issues       = @()
    }
    $d = Get-BobBuildLoopDecision -State $state -World $world
    if ($d.action -ne 'retry_job') { throw "action=$($d.action)" }
    if ($d.kind -ne 'mrb') { throw "kind=$($d.kind)" }
}

Invoke-Case 'BT0loop4d wait_pr cursor-models no pid no job' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Cwd (Join-Path $bridgeRoot 'cwd') -MaxJobRetries 3 -Fuel 'cursor-models'
    $state.phase = 'wait_pr'
    $state.jobAttempts = 1
    $state.currentKind = 'build'
    $state.currentPid = $null
    $state.currentJobId = 'cursor-miss'
    $world = [pscustomobject]@{
        Job          = $null
        ProcessAlive = $null
        Prs          = @()
        Issues       = @()
    }
    $d = Get-BobBuildLoopDecision -State $state -World $world
    if ($d.action -ne 'retry_job') { throw "action=$($d.action)" }
}

Invoke-Case 'BT0loop4e wait_pr cursor-models completion error no pid' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Cwd (Join-Path $bridgeRoot 'cwd') -MaxJobRetries 3 -Fuel 'cursor-models'
    $state.phase = 'wait_pr'
    $state.jobAttempts = 1
    $state.currentKind = 'build'
    $state.currentPid = $null
    $state.currentJobId = 'cursor-done-bad'
    $world = [pscustomobject]@{
        Job          = [pscustomobject]@{ lane = 'outbox'; state = 'done'; completionStatus = 'error'; pid = $null }
        ProcessAlive = $null
        Prs          = @()
        Issues       = @()
    }
    $d = Get-BobBuildLoopDecision -State $state -World $world
    if ($d.action -ne 'retry_job') { throw "action=$($d.action)" }
}

Invoke-Case 'BT0loop4f retry_job FIX goal keeps required fixes from state' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Cwd (Join-Path $bridgeRoot 'cwd')
    $state.lastMrb = 'https://github.com/fixture/repo/issues/8'
    $state.requiredFixes = '- Restore gate A'
    $fixes = Resolve-BobBuildLoopRequiredFixes -State $state -World ([pscustomobject]@{ Issues = @() })
    if ($fixes -notmatch 'Restore gate A') { throw "fixes=$fixes" }
    $goal = New-BobFixGoal -MrbUrl ([string]$state.lastMrb) -Fixes $fixes
    if ($goal -notmatch 'Restore gate A') { throw "goal missing fixes" }
}

Invoke-Case 'BT0loop4g retry_job FIX resolves required fixes from MRB issue body' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Cwd (Join-Path $bridgeRoot 'cwd')
    $state.lastMrb = 'https://github.com/fixture/repo/issues/8'
    $body = @"
## Required fixes
- Re-parse gate B
"@
    $world = [pscustomobject]@{
        Issues = @(
            [pscustomobject]@{
                number = 8
                url    = 'https://github.com/fixture/repo/issues/8'
                body   = $body
            }
        )
    }
    $fixes = Resolve-BobBuildLoopRequiredFixes -State $state -World $world
    if ($fixes -notmatch 'Re-parse gate B') { throw "fixes=$fixes" }
    $goal = New-BobFixGoal -MrbUrl ([string]$state.lastMrb) -Fixes $fixes
    if ($goal -notmatch 'Re-parse gate B') { throw "goal missing fixes from body" }
}

Invoke-Case 'BT0loop5 fail starts fix with required fixes' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd (Join-Path $bridgeRoot 'cwd')
    $state.phase = 'wait_mrb'
    $state.currentKind = 'mrb'
    $body = @"
## Verdict
FAIL

## Required fixes
- Restore gate A
"@
    $world = [pscustomobject]@{
        Job          = $null
        ProcessAlive = $true
        Prs          = @()
        Issues       = @(
            [pscustomobject]@{
                number = 8
                title  = 'MRB FAIL: slug abc1234deadbeef'
                url    = 'https://github.com/fixture/repo/issues/8'
                body   = $body
            }
        )
    }
    $d = Get-BobBuildLoopDecision -State $state -World $world
    if ($d.action -ne 'start_fix') { throw "action=$($d.action)" }
    if ($d.goal -notmatch 'Restore gate A') { throw "goal missing fixes: $($d.goal)" }
    if ($d.goal -match 'PASS-UAT') { throw 'FIX goal must not stamp UAT' }
    if ($d.pass.verdict -ne 'FAIL') { throw "pass verdict=$($d.pass.verdict)" }
}

# --- BT228 dispatcher skip FIX on leftover FAIL when PR merged (issue #228) ---
Invoke-Case 'BT228a leftover fail merged pr no fix' {
    param($bridgeRoot)
    $fakeGh = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $savedGh = $env:BOB_GH_EXE
    $savedView = $env:BOB_FAKE_GH_PR_VIEW_JSON
    $env:BOB_GH_EXE = $fakeGh
    $env:BOB_FAKE_GH_PR_VIEW_JSON = '{"state":"MERGED","mergedAt":"2026-09-22T21:20:14Z"}'
    try {
        $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 228 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd (Join-Path $bridgeRoot 'cwd')
        $state.phase = 'wait_mrb'
        $state.currentKind = 'mrb'
        $world = [pscustomobject]@{
            Job          = $null
            ProcessAlive = $true
            Prs          = @()
            Issues       = @(
                [pscustomobject]@{
                    number = 8
                    title  = 'MRB FAIL: slug abc1234deadbeef'
                    url    = 'https://github.com/fixture/repo/issues/8'
                    body   = "## Verdict`nFAIL`n## Required fixes`n- Should not FIX"
                }
            )
        }
        $d = Get-BobBuildLoopDecision -State $state -World $world
        if ($d.action -ne 'close_leftover_fail') { throw "action=$($d.action)" }
        if ($d.goal) { throw 'must not spawn FIX goal' }
        if (-not $d.close -or [int]$d.close.issue -ne 8) { throw 'close issue missing' }
        if ($d.close.comment -notmatch [regex]::Escape('https://github.com/fixture/repo/pull/2')) { throw "close comment=$($d.close.comment)" }
    }
    finally {
        $env:BOB_GH_EXE = $savedGh
        $env:BOB_FAKE_GH_PR_VIEW_JSON = $savedView
    }
}

Invoke-Case 'BT228b open pr fail still starts fix' {
    param($bridgeRoot)
    $fakeGh = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $savedGh = $env:BOB_GH_EXE
    $savedView = $env:BOB_FAKE_GH_PR_VIEW_JSON
    $env:BOB_GH_EXE = $fakeGh
    $env:BOB_FAKE_GH_PR_VIEW_JSON = '{"state":"OPEN","mergedAt":null}'
    try {
        $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 228 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd (Join-Path $bridgeRoot 'cwd')
        $state.phase = 'wait_mrb'
        $state.currentKind = 'mrb'
        $body = @"
## Verdict
FAIL

## Required fixes
- Restore gate A
"@
        $world = [pscustomobject]@{
            Job          = $null
            ProcessAlive = $true
            Prs          = @()
            Issues       = @(
                [pscustomobject]@{
                    number = 8
                    title  = 'MRB FAIL: slug abc1234deadbeef'
                    url    = 'https://github.com/fixture/repo/issues/8'
                    body   = $body
                }
            )
        }
        $d = Get-BobBuildLoopDecision -State $state -World $world
        if ($d.action -ne 'start_fix') { throw "action=$($d.action)" }
        if ($d.goal -notmatch 'Restore gate A') { throw "goal missing fixes" }
    }
    finally {
        $env:BOB_GH_EXE = $savedGh
        $env:BOB_FAKE_GH_PR_VIEW_JSON = $savedView
    }
}

Invoke-Case 'BT228c loop closes leftover fail via hook' {
    param($bridgeRoot)
    $savedGh = $env:BOB_GH_EXE
    $savedView = $env:BOB_FAKE_GH_PR_VIEW_JSON
    $env:BOB_GH_EXE = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $env:BOB_FAKE_GH_PR_VIEW_JSON = '{"state":"MERGED","mergedAt":"2026-09-22T21:20:14Z"}'
    $cwd = Join-Path $bridgeRoot 'cwd'
    New-Item -ItemType Directory -Force -Path $cwd | Out-Null
    $loop = Join-Path $RepoRoot 'tools\Start-BobBuildLoop.ps1'
    $path = Get-BobBuildLoopStatePath -Repo 'fixture/repo' -Issue 228
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 228 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd $cwd
    $state.phase = 'wait_mrb'
    $state.currentKind = 'mrb'
    Write-BobBuildLoopState -Path $path -State $state
    $world = [pscustomobject]@{
        Job          = $null
        ProcessAlive = $true
        Prs          = @()
        Issues       = @(
            [pscustomobject]@{
                number = 8
                title  = 'MRB FAIL: slug abc1234deadbeef'
                url    = 'https://github.com/fixture/repo/issues/8'
                body   = "## Verdict`nFAIL"
            }
        )
    }
    $fixStarts = New-Object System.Collections.Generic.List[string]
    $closeCalls = New-Object System.Collections.Generic.List[string]
    $r = & $loop -Issue 228 -Repo 'fixture/repo' -Cwd $cwd -Once -TestWorld $world -StatePath $path -TestStartBuild {
        param($st, $goal)
        [void]$fixStarts.Add('build')
        [pscustomobject]@{ ok = $true; started = $true; jobId = 'job-build'; pid = 1; fuel = 'cursor-models'; branch = 'work/job-build' }
    } -TestClose {
        param($c)
        [void]$closeCalls.Add([string]$c.comment)
        $c
    }
    if ($r.action -ne 'close_leftover_fail') { throw "action=$($r.action)" }
    if ($fixStarts.Count -gt 0) { throw 'must not start FIX worker' }
    if ($closeCalls.Count -ne 1) { throw "close hook calls=$($closeCalls.Count)" }
    if ($closeCalls[0] -notmatch 'pull/2') { throw "close comment=$($closeCalls[0])" }
    $env:BOB_GH_EXE = $savedGh
    $env:BOB_FAKE_GH_PR_VIEW_JSON = $savedView
}

Invoke-Case 'BT228d leftover fail merged fr closed done path' {
    param($bridgeRoot)
    $savedGh = $env:BOB_GH_EXE
    $savedView = $env:BOB_FAKE_GH_PR_VIEW_JSON
    $savedIssueView = $env:BOB_FAKE_GH_ISSUE_VIEW_JSON
    $env:BOB_GH_EXE = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $env:BOB_FAKE_GH_PR_VIEW_JSON = '{"state":"MERGED","mergedAt":"2026-09-22T21:20:14Z"}'
    $env:BOB_FAKE_GH_ISSUE_VIEW_JSON = '{"state":"CLOSED","comments":[]}'
    $cwd = Join-Path $bridgeRoot 'cwd-bt228d'
    New-Item -ItemType Directory -Force -Path $cwd | Out-Null
    $loop = Join-Path $RepoRoot 'tools\Start-BobBuildLoop.ps1'
    $path = Get-BobBuildLoopStatePath -Repo 'fixture/repo' -Issue 228
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 228 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd $cwd
    $state.phase = 'wait_mrb'
    $state.currentKind = 'mrb'
    Write-BobBuildLoopState -Path $path -State $state
    $world = [pscustomobject]@{
        Job          = $null
        ProcessAlive = $true
        Prs          = @()
        Issues       = @(
            [pscustomobject]@{
                number = 8
                title  = 'MRB FAIL: slug abc1234deadbeef'
                url    = 'https://github.com/fixture/repo/issues/8'
                body   = "## Verdict`nFAIL"
                state  = 'OPEN'
            }
        )
    }
    $fixStarts = New-Object System.Collections.Generic.List[string]
    $finishCalls = New-Object System.Collections.Generic.List[int]
    $pullCalls = New-Object System.Collections.Generic.List[string]
    try {
        $r = & $loop -Issue 228 -Repo 'fixture/repo' -Cwd $cwd -Once -TestWorld $world -StatePath $path -TestStartBuild {
            param($st, $goal)
            [void]$fixStarts.Add('build')
            [pscustomobject]@{ ok = $true; started = $true; jobId = 'job-build'; pid = 1; fuel = 'cursor-models'; branch = 'work/job-build' }
        } -TestPassNitsFinish {
            param($st, $passIssue)
            [void]$finishCalls.Add($passIssue)
            [pscustomobject]@{ ok = $true }
        } -TestPullProductMain {
            param($st)
            [void]$pullCalls.Add([string]$st.cwd)
            [pscustomobject]@{ ok = $true }
        }
        if ($r.action -ne 'close_leftover_fail') { throw "action=$($r.action)" }
        if (-not $r.ok) { throw "loop not ok stdout=$($r.stdout)" }
        if ($r.phase -ne 'pass') { throw "phase=$($r.phase)" }
        if ($r.stdout -notmatch '^DONE: MRB PASS-nits') { throw "stdout=$($r.stdout)" }
        if ($fixStarts.Count -gt 0) { throw 'must not start FIX worker' }
        if ($finishCalls.Count -ne 1) { throw "finish hook calls=$($finishCalls.Count)" }
        if ($pullCalls.Count -ne 1) { throw "pull hook calls=$($pullCalls.Count)" }
    }
    finally {
        $env:BOB_GH_EXE = $savedGh
        $env:BOB_FAKE_GH_PR_VIEW_JSON = $savedView
        $env:BOB_FAKE_GH_ISSUE_VIEW_JSON = $savedIssueView
    }
}

Invoke-Case 'BT228e leftover fail merged fr pass-nits comment done' {
    param($bridgeRoot)
    $savedGh = $env:BOB_GH_EXE
    $savedView = $env:BOB_FAKE_GH_PR_VIEW_JSON
    $savedIssueView = $env:BOB_FAKE_GH_ISSUE_VIEW_JSON
    $env:BOB_GH_EXE = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $env:BOB_FAKE_GH_PR_VIEW_JSON = '{"state":"MERGED","mergedAt":"2026-09-22T21:20:14Z"}'
    $env:BOB_FAKE_GH_ISSUE_VIEW_JSON = '{"state":"OPEN","comments":[{"body":"PASS-nits finished. Merged PR: https://github.com/fixture/repo/pull/2"}]}'
    $cwd = Join-Path $bridgeRoot 'cwd-bt228e'
    New-Item -ItemType Directory -Force -Path $cwd | Out-Null
    $loop = Join-Path $RepoRoot 'tools\Start-BobBuildLoop.ps1'
    $path = Get-BobBuildLoopStatePath -Repo 'fixture/repo' -Issue 228
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 228 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd $cwd
    $state.phase = 'wait_mrb'
    $state.currentKind = 'mrb'
    Write-BobBuildLoopState -Path $path -State $state
    $world = [pscustomobject]@{
        Job          = $null
        ProcessAlive = $true
        Prs          = @()
        Issues       = @(
            [pscustomobject]@{
                number = 8
                title  = 'MRB FAIL: slug abc1234deadbeef'
                url    = 'https://github.com/fixture/repo/issues/8'
                body   = "## Verdict`nFAIL"
                state  = 'OPEN'
            }
        )
    }
    $finishCalls = New-Object System.Collections.Generic.List[int]
    try {
        $r = & $loop -Issue 228 -Repo 'fixture/repo' -Cwd $cwd -Once -TestWorld $world -StatePath $path -TestPassNitsFinish {
            param($st, $passIssue)
            [void]$finishCalls.Add($passIssue)
            [pscustomobject]@{ ok = $true }
        } -TestPullProductMain {
            param($st)
            [pscustomobject]@{ ok = $true }
        }
        if (-not $r.ok) { throw "loop not ok stdout=$($r.stdout)" }
        if ($r.stdout -notmatch '^DONE: MRB PASS-nits') { throw "stdout=$($r.stdout)" }
        if ($finishCalls.Count -ne 1) { throw "finish hook calls=$($finishCalls.Count)" }
    }
    finally {
        $env:BOB_GH_EXE = $savedGh
        $env:BOB_FAKE_GH_PR_VIEW_JSON = $savedView
        $env:BOB_FAKE_GH_ISSUE_VIEW_JSON = $savedIssueView
    }
}

Invoke-Case 'BT0loop6 pass-nits terminal' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd (Join-Path $bridgeRoot 'cwd')
    $state.phase = 'wait_mrb'
    $world = [pscustomobject]@{
        Job          = $null
        ProcessAlive = $true
        Prs          = @()
        Issues       = @(
            [pscustomobject]@{
                number = 9
                title  = 'MRB PASS-nits: slug abc1234deadbeef'
                url    = 'https://github.com/fixture/repo/issues/9'
                body   = "## Verdict`nPASS-nits"
            }
        )
    }
    $d = Get-BobBuildLoopDecision -State $state -World $world
    if ($d.action -ne 'pass') { throw "action=$($d.action)" }
    if ($d.stdout -notmatch '^DONE: MRB PASS-nits') { throw "stdout=$($d.stdout)" }
    if ($d.stdout -match 'PASS-UAT') { throw 'driver must not stamp UAT' }
    if ($d.patch.phase -ne 'pass') { throw "phase=$($d.patch.phase)" }
}

Invoke-Case 'BT0loop6b pass-nits audit export' {
    param($bridgeRoot)
    Remove-Module BobBridge -ErrorAction SilentlyContinue
    $env:BOB_BRIDGE_HOME = $bridgeRoot
    $loopPsd1 = Join-Path $RepoRoot 'src\BobBridge.psd1'
    Import-Module $loopPsd1 -Force
    if (-not (Get-Command Write-BobJobAuditLine -ErrorAction SilentlyContinue)) {
        throw 'Write-BobJobAuditLine not exported after Import-Module BobBridge.psd1'
    }
    Write-BobJobAuditLine -JobId 'loop-pass-fixture' -Machine '' -Fuel 'cursor-models' -Model '' -Kind 'mrb-pass' -PrUrl 'https://github.com/fixture/repo/pull/2' -MrbIssue 'https://github.com/fixture/repo/issues/9' -Sha 'abc1234deadbeef' -Status 'pass-nits'
    $jobAudit = Join-Path $bridgeRoot 'job-audit.jsonl'
    if (-not (Test-Path $jobAudit)) { throw 'job-audit.jsonl missing after pass-nits writer' }
    $ja = (Get-Content $jobAudit | Where-Object { $_.Trim() } | Select-Object -Last 1) | ConvertFrom-Json
    if ([string]$ja.jobId -ne 'loop-pass-fixture') { throw "job-audit jobId=$($ja.jobId)" }
    if ([string]$ja.status -ne 'pass-nits') { throw "job-audit status=$($ja.status)" }
    if ([string]$ja.prUrl -ne 'https://github.com/fixture/repo/pull/2') { throw "job-audit prUrl=$($ja.prUrl)" }
    if ([string]$ja.mrbIssue -ne 'https://github.com/fixture/repo/issues/9') { throw "job-audit mrbIssue=$($ja.mrbIssue)" }
    foreach ($f in @('jobId', 'machine', 'fuel', 'model', 'kind', 'prUrl', 'mrbIssue', 'sha', 'status')) {
        if (-not ($ja.PSObject.Properties.Name -contains $f)) { throw "job-audit missing field $f" }
    }
}

Invoke-Case 'BT0loop7 retries exhausted' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Cwd (Join-Path $bridgeRoot 'cwd') -MaxJobRetries 3
    $state.phase = 'wait_pr'
    $state.jobAttempts = 3
    $state.currentPid = 99
    $world = [pscustomobject]@{
        Job          = [pscustomobject]@{ pid = 99 }
        ProcessAlive = $false
        Prs          = @()
        Issues       = @()
    }
    $d = Get-BobBuildLoopDecision -State $state -World $world
    if ($d.action -ne 'fail') { throw "action=$($d.action)" }
    if ($d.stdout -notmatch '^FAILED:') { throw "stdout=$($d.stdout)" }
}

Invoke-Case 'BT0loop8 loop once testworld no live gh' {
    param($bridgeRoot)
    $env:BOB_GH_EXE = Join-Path $bridgeRoot 'no-such-gh.exe'
    $cwd = Join-Path $bridgeRoot 'cwd'
    New-Item -ItemType Directory -Force -Path $cwd | Out-Null
    $loop = Join-Path $RepoRoot 'tools\Start-BobBuildLoop.ps1'
    $world = [pscustomobject]@{
        Job          = $null
        ProcessAlive = $null
        Prs          = @()
        Issues       = @()
    }
    $starts = New-Object System.Collections.Generic.List[string]
    $r = & $loop -Issue 19 -Repo 'fixture/repo' -Cwd $cwd -Once -TestWorld $world -TestStartBuild {
        param($st, $goal)
        $starts.Add('build')
        [pscustomobject]@{ ok = $true; started = $true; jobId = 'job-build'; pid = 1; fuel = 'cursor-models'; branch = 'work/job-build' }
    }
    if ($r.action -ne 'start_build') { throw "action=$($r.action)" }
    if ($r.phase -ne 'wait_pr') { throw "phase=$($r.phase)" }
    $root = [IO.Path]::GetFullPath($env:BOB_BRIDGE_HOME)
    if (-not $r.statePath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw "state escaped test root: $($r.statePath) (root $root)" }
    $liveBridge = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.grok\bob-bridge'))
    if ($r.statePath.StartsWith($liveBridge, [StringComparison]::OrdinalIgnoreCase)) { throw 'wrote live bob-bridge' }
    $board = Get-BobMrbBoard -Repo 'fixture/repo' -Issue 19 -Path $r.statePath
    if ([int]$board.issue -ne 19) { throw 'board issue missing' }
    if ($starts.Count -lt 1) { throw 'TestStartBuild not called' }
}

Invoke-Case 'BT0loop9 mrb handoff refuse does not abort driver' {
    param($bridgeRoot)
    $env:BOB_GH_EXE = Join-Path $bridgeRoot 'no-such-gh.exe'
    $cwd = Join-Path $bridgeRoot 'cwd'
    New-Item -ItemType Directory -Force -Path $cwd | Out-Null
    $loop = Join-Path $RepoRoot 'tools\Start-BobBuildLoop.ps1'
    $path = Get-BobBuildLoopStatePath -Repo 'fixture/repo' -Issue 44
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 44 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd $cwd -MaxJobRetries 3
    $state.phase = 'wait_mrb'
    $state.currentKind = 'mrb'
    $state.jobAttempts = 1
    $state.startError = 'MRB handoff enqueue failed (enqueue refused)'
    Write-BobBuildLoopState -Path $path -State $state
    $world = [pscustomobject]@{
        Job          = $null
        ProcessAlive = $null
        Prs          = @()
        Issues       = @()
    }
    $mrbCalls = New-Object System.Collections.Generic.List[string]
    $r = & $loop -Issue 44 -Repo 'fixture/repo' -Cwd $cwd -Once -TestWorld $world -StatePath $path -TestStartMrb {
        param($st)
        [void]$mrbCalls.Add('mrb')
        [pscustomobject]@{ ok = $false; started = $false; startError = 'MRB handoff enqueue failed (enqueue refused)'; jobId = $null; pid = $null; fuel = 'cursor-models' }
    }
    if ($r.action -ne 'retry_job') { throw "expected retry_job after refused mrb observe, got $($r.action)" }
    if (-not [string]$r.state.startError) { throw 'startError must persist on state' }
    if ($mrbCalls.Count -lt 1) { throw 'TestStartMrb not invoked on retry_job' }
}

Invoke-Case 'BT0loop10 ConvertFrom-BobGhJsonList keeps issue body' {
    param($bridgeRoot)
    if (-not (Get-Command ConvertFrom-BobGhJsonList -ErrorAction SilentlyContinue)) {
        throw 'ConvertFrom-BobGhJsonList missing after Bob-BuildLoop.ps1'
    }
    $raw = @'
[
  {"number":8,"title":"MRB FAIL: slug abc1234deadbeef","url":"https://github.com/fixture/repo/issues/8","body":"## Required fixes\n- Gate A still red\n","labels":[{"name":"mrb"}],"createdAt":"2026-01-01T00:00:00Z"},
  {"number":9,"title":"MRB PASS-nits: slug def","url":"https://github.com/fixture/repo/issues/9","body":"## Verdict\nPASS-nits","labels":[{"name":"mrb"}],"createdAt":"2026-01-02T00:00:00Z"}
]
'@
    $items = @(ConvertFrom-BobGhJsonList $raw)
    if ($items.Count -ne 2) { throw "expected 2 items, got $($items.Count)" }
    $fixes = Get-BobMrbRequiredFixes ([string]$items[0].body)
    if ($fixes -notmatch 'Gate A still red') { throw "body lost on normal parse: $fixes" }

    # PS 5.1 unzip reconstruct: one object with Object[] columns
    $unzip = [pscustomobject]@{
        number    = @(8, 9)
        title     = @('MRB FAIL: slug abc1234deadbeef', 'MRB PASS-nits: slug def')
        url       = @('https://github.com/fixture/repo/issues/8', 'https://github.com/fixture/repo/issues/9')
        body      = @("## Required fixes`n- Unzip body kept`n", '## Verdict')
        createdAt = @('2026-01-01T00:00:00Z', '2026-01-02T00:00:00Z')
    }
    $unzipRaw = ($unzip | ConvertTo-Json -Depth 6)
    # Force the unzip shape by converting that single object JSON back
    $forced = ConvertFrom-BobGhJsonList ($unzip | ConvertTo-Json -Compress -Depth 6)
    # When input is already a single object with array number, Raw path needs the array JSON.
    # Simulate gh-unzip by calling the reconstruct branch via a crafted object pipe:
    # JSON \n (not PowerShell `n) so ConvertFrom-Json yields real newlines in body.
    $rawUnzip = '{"number":[8,9],"title":["MRB FAIL: slug abc","MRB PASS-nits: slug def"],"url":["https://github.com/fixture/repo/issues/8","https://github.com/fixture/repo/issues/9"],"body":["## Required fixes\n- Unzip body kept\n","## Verdict"],"createdAt":["2026-01-01T00:00:00Z","2026-01-02T00:00:00Z"]}'
    $rows = @(ConvertFrom-BobGhJsonList $rawUnzip)
    if ($rows.Count -ne 2) { throw "unzip expected 2 rows, got $($rows.Count)" }
    $uFixes = Get-BobMrbRequiredFixes ([string]$rows[0].body)
    if ($uFixes -notmatch 'Unzip body kept') { throw "body dropped on unzip reconstruct: '$uFixes' body='$($rows[0].body)'" }
}

Invoke-Case 'BT0loop11 Select-BobBuildLoopPr title hash contract' {
    param($bridgeRoot)
    $mkPr = {
        param($title, $created, $num)
        if (-not $num) { $num = 1 }
        [pscustomobject]@{
            number    = $num
            url       = "https://github.com/fixture/repo/pull/$num"
            title     = $title
            branch    = 'work/fix'
            sha       = 'deadbeefcafebabe'
            createdAt = $created
        }
    }
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 107 -Cwd (Join-Path $bridgeRoot 'cwd')
    $state.watchAfter = $null
    $harvestTitle = 'harvest: bob-job dispatcher playbook and loop hardening'
    $prs = @(
        & $mkPr $harvestTitle '2026-09-21T12:00:00Z'
    )
    if (Select-BobBuildLoopPr -State $state -Prs $prs) { throw 'title without issue hash must not match' }
    $prs = @(& $mkPr 'issue #107' '2026-09-21T12:00:00Z')
    $picked = Select-BobBuildLoopPr -State $state -Prs $prs
    if (-not $picked -or [string]$picked.title -notmatch '#107') { throw 'issue #107 title must match' }
    $state.priorMrbIssue = 21
    $prs = @(& $mkPr 'Fix issue #21' '2026-09-21T12:01:00Z')
    $picked = Select-BobBuildLoopPr -State $state -Prs $prs
    if (-not $picked -or [string]$picked.title -notmatch '#21') { throw 'Fix issue #priorMrbIssue must match' }
    # Hostile probe (#115): unrelated #91 must not win when Fix issue #priorMrbIssue exists
    $state.priorMrbIssue = 119
    $prs = @(
        & $mkPr $harvestTitle '2026-09-21T12:00:00Z' 1
        & $mkPr 'Fix issue #119' '2026-09-21T12:02:00Z' 2
        & $mkPr 'Tray: Cursor pool bars (#91)' '2026-09-21T12:03:00Z' 3
    )
    $picked = Select-BobBuildLoopPr -State $state -Prs $prs
    if (-not $picked -or [int]$picked.number -ne 2) { throw "expected PR #2 Fix #119, got #$($picked.number) $($picked.title)" }
}

Invoke-Case 'BT0loop12 build and fix goals require title hash' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 107 -Cwd (Join-Path $bridgeRoot 'cwd')
    $buildGoal = New-BobBuildGoal -State $state
    if ($buildGoal -notmatch 'PR title must include #107') { throw "build goal missing title hash: $buildGoal" }
    $fixGoal = New-BobFixGoal -MrbUrl 'https://github.com/fixture/repo/issues/110' -Fixes '- Fix A' -FrIssue 107
    if ($fixGoal -notmatch '#107') { throw 'fix goal missing FR hash' }
    if ($fixGoal -notmatch '#110') { throw 'fix goal missing MRB hash' }
}

# --- BT118 PASS-nits close finished boards (issue #118) ---
Invoke-Case 'BT118a pass-nits close payload first try' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 107 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd (Join-Path $bridgeRoot 'cwd')
    $passRow = [pscustomobject]@{
        sha     = 'abc1234deadbeef'
        pr      = 'https://github.com/fixture/repo/pull/2'
        mrb     = 'https://github.com/fixture/repo/issues/115'
        verdict = 'PASS-nits'
        issue   = 115
    }
    $state = Add-BobBuildLoopPass -State $state -Pass $passRow
    $payload = Get-BobPassNitsClosePayload -State $state -PassIssue 115
    $nums = @($payload.issues | ForEach-Object { [int]$_.number })
    if ($nums.Count -ne 2) { throw "expected FR+PASS, got $($nums -join ',')" }
    if ($nums[0] -ne 107 -or $nums[1] -ne 115) { throw "order=$($nums -join ',')" }
    if ($payload.issues[0].comment -notmatch [regex]::Escape($payload.prUrl)) { throw 'comment must link merged PR' }
}

Invoke-Case 'BT118b pass-nits close payload all fail boards' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 107 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd (Join-Path $bridgeRoot 'cwd')
    foreach ($pair in @(@(110, 'FAIL'), @(113, 'FAIL'), @(115, 'PASS-nits'))) {
        $state = Add-BobBuildLoopPass -State $state -Pass ([pscustomobject]@{
            sha = 'abc1234deadbeef'; pr = 'https://github.com/fixture/repo/pull/2'
            mrb = "https://github.com/fixture/repo/issues/$($pair[0])"
            verdict = $pair[1]; issue = $pair[0]
        })
    }
    $payload = Get-BobPassNitsClosePayload -State $state -PassIssue 115
    $nums = @($payload.issues | ForEach-Object { [int]$_.number })
    if ($nums -notcontains 107) { throw 'missing FR' }
    if ($nums -notcontains 110 -or $nums -notcontains 113) { throw "missing FAIL boards: $($nums -join ',')" }
    if ($nums -notcontains 115) { throw 'missing PASS board' }
    if ($nums.Count -ne 4) { throw "expected 4 closes, got $($nums -join ',')" }
}

Invoke-Case 'BT118c pass-nits merge fail leaves boards open' {
    param($bridgeRoot)
    $fakeGh = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $log = Join-Path $bridgeRoot 'fake-gh-merge-fail.jsonl'
    $savedGh = $env:BOB_GH_EXE
    $savedMode = $env:BOB_FAKE_GH_MODE
    $savedLog = $env:BOB_FAKE_GH_LOG
    $savedView = $env:BOB_FAKE_GH_PR_VIEW_JSON
    $env:BOB_GH_EXE = $fakeGh
    $env:BOB_FAKE_GH_MODE = 'merge-fail'
    $env:BOB_FAKE_GH_LOG = $log
    $env:BOB_FAKE_GH_PR_VIEW_JSON = '{"state":"OPEN","merged":false}'
    try {
        $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 107 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd (Join-Path $bridgeRoot 'cwd')
        $r = Invoke-BobPassNitsFinish -State $state -PassIssue 115 -Gh $fakeGh
        if ($r.ok) { throw 'merge-fail must not succeed' }
        if ($r.message -notmatch 'merge') { throw "message=$($r.message)" }
        if (-not (Test-Path $log)) { throw 'log missing' }
        $lines = @(Get-Content $log | Where-Object { $_.Trim() })
        foreach ($line in $lines) {
            $row = $line | ConvertFrom-Json
            if ([string]$row.command -eq 'issue close' -or [string]$row.op -eq 'issue close') {
                throw 'must not close issues when merge fails'
            }
        }
    }
    finally {
        $env:BOB_GH_EXE = $savedGh
        $env:BOB_FAKE_GH_MODE = $savedMode
        $env:BOB_FAKE_GH_LOG = $savedLog
        $env:BOB_FAKE_GH_PR_VIEW_JSON = $savedView
    }
}

Invoke-Case 'BT119a Start-BobMrb PASS-nits requires PrUrl' {
    param($bridgeRoot)
    $mrb = Join-Path $RepoRoot 'tools\Start-BobMrb.ps1'
    try {
        & $mrb -Repo 'fixture/repo' -Title 'slug' -Verdict 'PASS-nits' -Body '## Verdict`nPASS-nits' -Sha 'abc1234deadbeef' 2>&1 | Out-Null
        throw 'PASS-nits without PrUrl must throw'
    }
    catch {
        if ($_.Exception.Message -notmatch 'requires -PrUrl') { throw $_.Exception.Message }
    }
}

Invoke-Case 'BT119b Start-BobMrb PASS-nits merges before issue create' {
    param($bridgeRoot)
    $fakeGh = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $log = Join-Path $bridgeRoot 'fake-gh-pass-merge.jsonl'
    $savedGh = $env:BOB_GH_EXE
    $savedMode = $env:BOB_FAKE_GH_MODE
    $savedLog = $env:BOB_FAKE_GH_LOG
    $savedView = $env:BOB_FAKE_GH_PR_VIEW_JSON
    $env:BOB_GH_EXE = $fakeGh
    $env:BOB_FAKE_GH_MODE = 'ok'
    $env:BOB_FAKE_GH_LOG = $log
    $env:BOB_FAKE_GH_PR_VIEW_JSON = '{"state":"OPEN","merged":false}'
    try {
        $mrb = Join-Path $RepoRoot 'tools\Start-BobMrb.ps1'
        $r = & $mrb -Repo 'fixture/repo' -Title 'slug' -Verdict 'PASS-nits' -Body '## Verdict`nPASS-nits' -Sha 'abc1234deadbeef' -PrUrl 'https://github.com/fixture/repo/pull/2'
        if (-not $r.ok) { throw 'Start-BobMrb failed' }
        $sawMerge = $false
        $sawCreateAfterMerge = $false
        foreach ($line in @(Get-Content $log)) {
            $row = $line | ConvertFrom-Json
            $a = [string]$row.argv
            if ($a -match '(?i)\bpr\s+merge\b') { $sawMerge = $true }
            if ($a -match '(?i)\bissue\s+create\b') {
                if (-not $sawMerge) { throw 'issue create before pr merge' }
                $sawCreateAfterMerge = $true
            }
        }
        if (-not $sawCreateAfterMerge) { throw 'expected pr merge then issue create in fake gh log' }
    }
    finally {
        $env:BOB_GH_EXE = $savedGh
        $env:BOB_FAKE_GH_MODE = $savedMode
        $env:BOB_FAKE_GH_LOG = $savedLog
        $env:BOB_FAKE_GH_PR_VIEW_JSON = $savedView
    }
}

Invoke-Case 'BT118d pass-nits finish without gh' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 107 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd (Join-Path $bridgeRoot 'cwd')
    $saved = $env:BOB_GH_EXE
    $env:BOB_GH_EXE = Join-Path $bridgeRoot 'no-such-gh.exe'
    try {
        $r2 = Invoke-BobPassNitsFinish -State $state -PassIssue 115
        if ($r2.ok) { throw 'missing gh must fail' }
        if ($r2.message -notmatch 'gh\.exe not found') { throw "message=$($r2.message)" }
    }
    finally {
        $env:BOB_GH_EXE = $saved
    }
}

Invoke-Case 'BT118e loop pass testworld finish hook' {
    param($bridgeRoot)
    $env:BOB_GH_EXE = Join-Path $bridgeRoot 'no-such-gh.exe'
    $cwd = Join-Path $bridgeRoot 'cwd'
    New-Item -ItemType Directory -Force -Path $cwd | Out-Null
    $loop = Join-Path $RepoRoot 'tools\Start-BobBuildLoop.ps1'
    $path = Get-BobBuildLoopStatePath -Repo 'fixture/repo' -Issue 118
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 118 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd $cwd
    $state.phase = 'wait_mrb'
    Write-BobBuildLoopState -Path $path -State $state
    $world = [pscustomobject]@{
        Job          = $null
        ProcessAlive = $true
        Prs          = @()
        Issues       = @(
            [pscustomobject]@{
                number = 200
                title  = 'MRB PASS-nits: slug abc1234deadbeef'
                url    = 'https://github.com/fixture/repo/issues/200'
                body   = '## Verdict`nPASS-nits'
            }
        )
    }
    $finishCalls = New-Object System.Collections.Generic.List[int]
    $r = & $loop -Issue 118 -Repo 'fixture/repo' -Cwd $cwd -Once -TestWorld $world -StatePath $path -TestPassNitsFinish {
        param($st, $passIssue)
        [void]$finishCalls.Add($passIssue)
        $payload = Get-BobPassNitsClosePayload -State $st -PassIssue $passIssue
        if ($payload.issues.Count -lt 2) { throw 'hook expected FR+PASS payload' }
        [pscustomobject]@{ ok = $true; payload = $payload }
    }
    if ($r.action -ne 'pass') { throw "action=$($r.action)" }
    if (-not $r.ok) { throw "loop not ok stdout=$($r.stdout)" }
    if ($finishCalls.Count -ne 1 -or $finishCalls[0] -ne 200) { throw 'finish hook not called with PASS issue' }
    if ($r.stdout -notmatch '^DONE: MRB PASS-nits') { throw "stdout=$($r.stdout)" }
}

Invoke-Case 'BT118f pass-nits finish closes via fake gh' {
    param($bridgeRoot)
    $fakeGh = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $log = Join-Path $bridgeRoot 'fake-gh-finish-ok.jsonl'
    $savedGh = $env:BOB_GH_EXE
    $savedMode = $env:BOB_FAKE_GH_MODE
    $savedLog = $env:BOB_FAKE_GH_LOG
    $savedView = $env:BOB_FAKE_GH_PR_VIEW_JSON
    $env:BOB_GH_EXE = $fakeGh
    $env:BOB_FAKE_GH_MODE = 'ok'
    $env:BOB_FAKE_GH_LOG = $log
    $env:BOB_FAKE_GH_PR_VIEW_JSON = '{"state":"OPEN","merged":false}'
    try {
        $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 107 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd (Join-Path $bridgeRoot 'cwd')
        $state = Add-BobBuildLoopPass -State $state -Pass ([pscustomobject]@{
            sha = 'abc1234deadbeef'; pr = 'https://github.com/fixture/repo/pull/2'
            mrb = 'https://github.com/fixture/repo/issues/115'; verdict = 'PASS-nits'; issue = 115
        })
        $r = Invoke-BobPassNitsFinish -State $state -PassIssue 115 -Gh $fakeGh
        if (-not $r.ok) { throw "finish failed: $($r.message)" }
        $closes = @(Get-Content $log | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.op -eq 'issue close' -or $_.command -eq 'issue close' })
        if ($closes.Count -lt 2) { throw "expected issue close log lines, got $($closes.Count)" }
    }
    finally {
        $env:BOB_GH_EXE = $savedGh
        $env:BOB_FAKE_GH_MODE = $savedMode
        $env:BOB_FAKE_GH_LOG = $savedLog
        $env:BOB_FAKE_GH_PR_VIEW_JSON = $savedView
    }
}

Invoke-Case 'BT118g pass-nits merge-in-progress already MERGED' {
    param($bridgeRoot)
    $fakeGh = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $log = Join-Path $bridgeRoot 'fake-gh-merge-in-progress.jsonl'
    $next = Join-Path $bridgeRoot 'fake-gh-pr-view-next.json'
    $savedGh = $env:BOB_GH_EXE
    $savedMode = $env:BOB_FAKE_GH_MODE
    $savedLog = $env:BOB_FAKE_GH_LOG
    $savedView = $env:BOB_FAKE_GH_PR_VIEW_JSON
    $savedNext = $env:BOB_FAKE_GH_PR_VIEW_NEXT
    $env:BOB_GH_EXE = $fakeGh
    $env:BOB_FAKE_GH_MODE = 'merge-in-progress'
    $env:BOB_FAKE_GH_LOG = $log
    $env:BOB_FAKE_GH_PR_VIEW_JSON = '{"state":"OPEN","mergedAt":null}'
    $env:BOB_FAKE_GH_PR_VIEW_NEXT = $next
    try {
        $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 107 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd (Join-Path $bridgeRoot 'cwd')
        $state = Add-BobBuildLoopPass -State $state -Pass ([pscustomobject]@{
            sha = 'abc1234deadbeef'; pr = 'https://github.com/fixture/repo/pull/2'
            mrb = 'https://github.com/fixture/repo/issues/115'; verdict = 'PASS-nits'; issue = 115
        })
        $r = Invoke-BobPassNitsFinish -State $state -PassIssue 115 -Gh $fakeGh
        if (-not $r.ok) { throw "in-progress MERGED must succeed: $($r.message)" }
        $closes = @(Get-Content $log | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.op -eq 'issue close' -or $_.command -eq 'issue close' })
        if ($closes.Count -lt 2) { throw "expected issue close after in-progress merge, got $($closes.Count)" }
    }
    finally {
        $env:BOB_GH_EXE = $savedGh
        $env:BOB_FAKE_GH_MODE = $savedMode
        $env:BOB_FAKE_GH_LOG = $savedLog
        $env:BOB_FAKE_GH_PR_VIEW_JSON = $savedView
        $env:BOB_FAKE_GH_PR_VIEW_NEXT = $savedNext
    }
}

# --- BT0gtalk grok-talk inbox worker (#126 / #129) ---
Invoke-Case 'BT0gtalk inbox outbox fuel' {
    param($bridgeRoot)
    $gtTalkSrc = Get-Content (Join-Path $RepoRoot 'src\Private\Invoke-BobGrokTalk.ps1') -Raw
    if ($gtTalkSrc -match 'Start-BobCursor') { throw 'grok-talk must not call Start-BobCursor (use Invoke-BobCursorModelsOneShot)' }
    $ircHome = Join-Path $bridgeRoot 'grok-talk-home'
    New-Item -ItemType Directory -Force -Path $ircHome | Out-Null
    $env:BOB_IRC_HOME = $ircHome
    $env:AGENTIC_IRC_HOME = $ircHome
    $env:BOB_MACHINE_ID = 'testhost'

    $weekLog = Join-Path $bridgeRoot 'grok-talk-weekly.jsonl'
    $weekLine = '{"ts":"2026-09-21T12:00:00Z","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":50.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-09-26T00:00:00Z"}}}}'
    [IO.File]::WriteAllText($weekLog, $weekLine + [Environment]::NewLine)
    $env:BOB_WEEKLY_LOG = $weekLog
    $cursorFile = Join-Path $bridgeRoot 'grok-talk-cursor-empty.json'
    '{"percentUsed":100}' | Set-Content -Path $cursorFile -Encoding utf8
    $env:BOB_CURSOR_USAGE_FILE = $cursorFile

    $inboxJob = @{
        v            = 1
        job_id       = 'deadbeefcafebabe'
        ts           = 1758470400
        asker        = 'simon'
        channel      = '#bobiverse'
        body         = 'status on this box?'
        nick         = 'bob-testhost'
        machine_id   = 'testhost'
        reply_target = '#bobiverse'
        body_hash    = 'abc123'
    } | ConvertTo-Json -Compress
    $inboxPath = Join-Path $ircHome 'grok-inbox.jsonl'
    [IO.File]::WriteAllText($inboxPath, $inboxJob + [Environment]::NewLine)

    if (-not (Test-BobGrokTalkFuelAllowed)) { throw 'expected fuel ok with weekly 50%' }
    if ([string](Select-BobGrokTalkFuel) -ne 'grok-build') { throw 'weekly>0 cursor=0 must pick grok-build' }

    $tick = Invoke-BobGrokTalkTick -Cwd $RepoRoot
    if (-not $tick.ok) { throw "tick failed: $($tick | ConvertTo-Json -Compress)" }
    if ([string]$tick.job_id -ne 'deadbeefcafebabe') { throw "job_id=$($tick.job_id)" }

    $outRows = @(Get-Content (Join-Path $ircHome 'grok-outbox.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
    if ($outRows.Count -ne 1) { throw "outbox lines=$($outRows.Count)" }
    $out = $outRows[0]
    if ([int]$out.v -ne 1) { throw "out.v=$($out.v) expected 1" }
    if ([string]$out.job_id -ne 'deadbeefcafebabe') { throw "out job_id=$($out.job_id)" }
    if ([string]$out.reply_target -ne '#bobiverse') { throw "reply_target=$($out.reply_target)" }
    if (@($out.lines).Count -lt 1) { throw 'lines empty' }
    if ([string]$out.lines[0] -match '(?i)password\s*=') { throw 'lines must not contain secrets' }

    $lines = @(ConvertTo-BobGrokTalkOutLines -Text "Fact one.`npassword=secret`nFact two.")
    if ($lines.Count -ne 2) { throw "secret filter lines=$($lines.Count)" }

    $weekZero = Join-Path $bridgeRoot 'grok-talk-weekly-zero.jsonl'
    [IO.File]::WriteAllText($weekZero, '{"ts":"2026-09-21T12:00:00Z","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":100.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY"}}}}' + [Environment]::NewLine)
    $env:BOB_WEEKLY_LOG = $weekZero
    if (Test-BobGrokTalkFuelAllowed) { throw 'weekly=0 cursor=0 must refuse fuel' }
    $inbox2 = Join-Path $bridgeRoot 'grok-talk-inbox-2'
    New-Item -ItemType Directory -Force -Path $inbox2 | Out-Null
    $env:BOB_IRC_HOME = $inbox2
    $env:AGENTIC_IRC_HOME = $inbox2
    @{
        v            = 1
        job_id       = 'blocked00000001'
        ts           = 1758470500
        asker        = 'simon'
        channel      = '#bobiverse'
        body         = 'hello'
        nick         = 'bob-testhost'
        machine_id   = 'testhost'
        reply_target = '#bobiverse'
        body_hash    = 'zzz'
    } | ConvertTo-Json -Compress | Set-Content -Path (Join-Path $inbox2 'grok-inbox.jsonl') -Encoding utf8
    $refuse = Invoke-BobGrokTalkTick -Cwd $RepoRoot
    if ($refuse.error -ne 'no_fuel') { throw "expected no_fuel got $($refuse | ConvertTo-Json -Compress)" }
    if (Test-Path (Join-Path $inbox2 'grok-outbox.jsonl')) { throw 'no_fuel must not write outbox' }

    $watchGt = Get-Content (Join-Path $RepoRoot 'tools\Watch-GrokTalk.ps1') -Raw
    if ($watchGt -notmatch 'Invoke-BobGrokTalkTick') { throw 'Watch-GrokTalk must call Invoke-BobGrokTalkTick' }
    $watchBv = Get-Content (Join-Path $RepoRoot 'tools\Watch-Bobiverse.ps1') -Raw
    if ($watchBv -match 'Invoke-BobGrokTalkTick|grok-inbox') { throw 'Watch-Bobiverse must not run grok-talk worker' }
    $installGt = Get-Content (Join-Path $RepoRoot 'tools\Install-BobFleet.ps1') -Raw
    if ($installGt -notmatch 'Install-BobWatcherTask -Name ''GrokTalk'' -TaskName \$gtTask') { throw 'Install-BobFleet must register scheduled task for grok-talk poller' }
    $installHelpers = Get-Content (Join-Path $RepoRoot 'tools\BobInstallHelpers.ps1') -Raw
    if ($installHelpers -notmatch 'Register-ScheduledTask -TaskName \$TaskName') { throw 'Install-BobWatcherTask must register the watcher logon task' }
    if ($installGt -notmatch 'Watch-GrokTalk') { throw 'Install-BobFleet grok-talk task must target Watch-GrokTalk' }

    $env:BOB_WEEKLY_LOG = $null
    $env:BOB_MACHINE_ID = $null
}

Invoke-Case 'BT0gtalk cursor models outbox' {
    param($bridgeRoot)
    $cursorOneShotSrc = Get-Content (Join-Path $RepoRoot 'src\Private\Invoke-BobCursorModels.ps1') -Raw
    if ($cursorOneShotSrc -match '\$pid\s*=\s*\[int\]\$created\.ProcessId') {
        throw 'Invoke-BobCursorModelsOneShot must not assign automatic $PID (use $procId)'
    }
    if ($cursorOneShotSrc -match 'if\s*\(\s*\$env:BOB_GROK_TALK_CURSOR_FIXTURE\s*\)\s*\{[^\}]*return') {
        throw 'BOB_GROK_TALK_CURSOR_FIXTURE must not return before Win32_Process create and child wait'
    }
    $ircHome = Join-Path $bridgeRoot 'grok-talk-cursor-home'
    New-Item -ItemType Directory -Force -Path $ircHome | Out-Null
    $env:BOB_IRC_HOME = $ircHome
    $env:AGENTIC_IRC_HOME = $ircHome
    $env:BOB_MACHINE_ID = 'testhost'

    $weekZero = Join-Path $bridgeRoot 'grok-talk-cursor-weekly-zero.jsonl'
    [IO.File]::WriteAllText($weekZero, '{"ts":"2026-09-21T12:00:00Z","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":100.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY"}}}}' + [Environment]::NewLine)
    $env:BOB_WEEKLY_LOG = $weekZero
    $cursorFile = Join-Path $bridgeRoot 'grok-talk-cursor-ten.json'
    '{"percentUsed":10}' | Set-Content -Path $cursorFile -Encoding utf8
    $env:BOB_CURSOR_USAGE_FILE = $cursorFile

    if ([string](Select-BobGrokTalkFuel) -ne 'cursor-models') { throw 'cursor>0 weekly=0 must pick cursor-models' }

    $fixtureLine = 'Listen-talk completions are written to grok-outbox.jsonl on this machine.'
    $env:BOB_GROK_TALK_CURSOR_FIXTURE = $fixtureLine

    $inboxJob = @{
        v            = 1
        job_id       = 'cafebabedeadbeef'
        ts           = 1758470600
        asker        = 'simon'
        channel      = '#bobiverse'
        body         = 'what file gets the reply?'
        nick         = 'bob-testhost'
        machine_id   = 'testhost'
        reply_target = '#bobiverse'
        body_hash    = 'def456'
    } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText((Join-Path $ircHome 'grok-inbox.jsonl'), $inboxJob + [Environment]::NewLine)

    $tick = Invoke-BobGrokTalkTick -Cwd $RepoRoot
    if (-not $tick.ok) { throw "cursor tick failed: $($tick | ConvertTo-Json -Compress)" }
    if ([string]$tick.fuel -ne 'cursor-models') { throw "fuel=$($tick.fuel) expected cursor-models" }

    $outRows = @(Get-Content (Join-Path $ircHome 'grok-outbox.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
    if ($outRows.Count -ne 1) { throw "cursor outbox lines=$($outRows.Count)" }
    $out = $outRows[0]
    if ([int]$out.v -ne 1) { throw "cursor out.v=$($out.v)" }
    if ([string]$out.job_id -ne 'cafebabedeadbeef') { throw "cursor out job_id=$($out.job_id)" }
    if (@($out.lines).Count -ne 1) { throw "cursor lines count=$(@($out.lines).Count) expected 1" }
    if ([string]$out.lines[0] -ne $fixtureLine) { throw "cursor line mismatch: $($out.lines[0])" }

    $env:BOB_GROK_TALK_CURSOR_FIXTURE = $null
    $ircHome2 = Join-Path $bridgeRoot 'grok-talk-cursor-no-fixture'
    New-Item -ItemType Directory -Force -Path $ircHome2 | Out-Null
    $env:BOB_IRC_HOME = $ircHome2
    $env:AGENTIC_IRC_HOME = $ircHome2
    @{
        v            = 1
        job_id       = 'nocursorfixture01'
        ts           = 1758470700
        asker        = 'simon'
        channel      = '#bobiverse'
        body         = 'probe'
        nick         = 'bob-testhost'
        machine_id   = 'testhost'
        reply_target = '#bobiverse'
        body_hash    = 'zzz'
    } | ConvertTo-Json -Compress | Set-Content -Path (Join-Path $ircHome2 'grok-inbox.jsonl') -Encoding utf8
    $emptyTick = Invoke-BobGrokTalkTick -Cwd $RepoRoot
    if ($emptyTick.ok) { throw 'cursor>0 without fixture must not complete via Fake-Grok worker' }
    if ($emptyTick.error -ne 'empty') { throw "expected empty got $($emptyTick | ConvertTo-Json -Compress)" }
    if (Test-Path (Join-Path $ircHome2 'grok-outbox.jsonl')) { throw 'Fake-Grok must not write outbox without cursor fixture' }

    $env:BOB_WEEKLY_LOG = $null
    $env:BOB_CURSOR_USAGE_FILE = $null
    $env:BOB_MACHINE_ID = $null
}

Invoke-Case 'BT0gtalk worker finally unwedge' {
    param($bridgeRoot)
    $ircHome = Join-Path $bridgeRoot 'grok-talk-wedge-home'
    New-Item -ItemType Directory -Force -Path $ircHome | Out-Null
    $env:BOB_IRC_HOME = $ircHome
    $env:AGENTIC_IRC_HOME = $ircHome
    $env:BOB_MACHINE_ID = 'testhost'

    $weekLog = Join-Path $bridgeRoot 'grok-talk-wedge-weekly.jsonl'
    $weekLine = '{"ts":"2026-09-21T12:00:00Z","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":50.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-09-26T00:00:00Z"}}}}'
    [IO.File]::WriteAllText($weekLog, $weekLine + [Environment]::NewLine)
    $env:BOB_WEEKLY_LOG = $weekLog
    $cursorFile = Join-Path $bridgeRoot 'grok-talk-wedge-cursor-empty.json'
    '{"percentUsed":100}' | Set-Content -Path $cursorFile -Encoding utf8
    $env:BOB_CURSOR_USAGE_FILE = $cursorFile

    @{
        v            = 1
        job_id       = 'wedge00000000001'
        ts           = 1758470800
        asker        = 'simon'
        channel      = '#bobiverse'
        body         = 'wedge probe'
        nick         = 'bob-testhost'
        machine_id   = 'testhost'
        reply_target = '#bobiverse'
        body_hash    = 'wedge'
    } | ConvertTo-Json -Compress | Set-Content -Path (Join-Path $ircHome 'grok-inbox.jsonl') -Encoding utf8

    $env:BOB_GROK_TALK_TEST_THROW = '1'
    try {
        Invoke-BobGrokTalkTick -Cwd $RepoRoot | Out-Null
    }
    catch {
        if ($_.Exception.Message -notmatch 'BT0gtalk inject worker throw') { throw $_.Exception.Message }
    }
    $env:BOB_GROK_TALK_TEST_THROW = $null
    if (Test-Path (Join-Path $ircHome 'grok-talk-worker.json')) { throw 'grok-talk-worker.json must clear in finally after throw' }

    $tick2 = Invoke-BobGrokTalkTick -Cwd $RepoRoot
    if ($tick2.skipped -eq 'busy') { throw 'next tick wedged busy after worker throw' }

    $env:BOB_WEEKLY_LOG = $null
    $env:BOB_CURSOR_USAGE_FILE = $null
    $env:BOB_MACHINE_ID = $null
}

# --- BT0irtsr IRC TSR + Cursor listen watchdog (#163) ---
Invoke-Case 'BT0irtsr wake silence matrix' {
    . (Join-Path $RepoRoot 'tools\Irc-Tsr-Health.ps1')
    $now = [datetime]'2026-09-22T12:00:00'
    $wake = Join-Path $bridgeRoot 'irc-tsr-test-wake.jsonl'
    $hb30 = ($now.AddSeconds(-30).ToUniversalTime().ToString('o')) + ' PROCESS_HEARTBEAT'
    Set-Content -LiteralPath $wake -Value $hb30 -Encoding utf8
    if (Test-IrcTsrWakeSilenceStale -WakePath $wake -SilenceSec 60 -Now $now) {
        throw '30s-old process heartbeat must not be stale at 60s gate'
    }
    $hb120 = ($now.AddSeconds(-120).ToUniversalTime().ToString('o')) + ' PROCESS_HEARTBEAT'
    Set-Content -LiteralPath $wake -Value $hb120 -Encoding utf8
    if (-not (Test-IrcTsrWakeSilenceStale -WakePath $wake -SilenceSec 60 -Now $now)) {
        throw '120s-old process heartbeat must be stale'
    }
    Add-Content -LiteralPath $wake -Value 'FROM recent chat must not reset silence' -Encoding utf8
    (Get-Item -LiteralPath $wake).LastWriteTime = $now
    if (-not (Test-IrcTsrWakeSilenceStale -WakePath $wake -SilenceSec 60 -Now $now)) {
        throw 'recent FROM must not mask stale process heartbeat'
    }
    $ircLog = Join-Path $bridgeRoot 'irc.log'
    Set-Content -LiteralPath $ircLog -Value 'PRIVMSG quiet channel' -Encoding utf8
    (Get-Item -LiteralPath $ircLog).LastWriteTime = $now
    (Get-Item -LiteralPath $wake).LastWriteTime = $now.AddSeconds(-120)
    if (-not (Test-IrcTsrWakeSilenceStale -WakePath $wake -SilenceSec 60 -Now $now)) {
        throw 'fresh irc.log must not override wake-only stale check'
    }
    $missingWake = Join-Path $bridgeRoot 'irc-tsr-missing-wake.jsonl'
    if (Test-Path -LiteralPath $missingWake) { Remove-Item -LiteralPath $missingWake -Force }
    if (Test-IrcTsrWakeSilenceStale -WakePath $missingWake -SilenceSec 60 -Now $now) {
        throw 'missing wake file must not count as stale process heartbeat'
    }
    $watch = Get-Content (Join-Path $RepoRoot 'tools\Watch-IrcTsr.ps1') -Raw
    if ($watch -match 'irc\.log') { throw 'Watch-IrcTsr must not gate on irc.log mtime' }
}

Invoke-Case 'BT0irtsr listen leak' {
    # ionos 25/09: Start-IrcTsr killed only the runner; each 600s recycle orphaned irc_listen.py (148).
    . (Join-Path $RepoRoot 'tools\Irc-Tsr-Health.ps1')
    $h = 'C:\Users\x\.agentic-irc-cursor'
    $procs = @(
        [pscustomobject]@{ ProcessId = 100; ParentProcessId = 1; CommandLine = 'powershell.exe -File Irc-Tsr-Runner.ps1 -IrcHome C:\Users\x\.agentic-irc-cursor' },
        [pscustomobject]@{ ProcessId = 101; ParentProcessId = 100; CommandLine = 'python.exe -u C:\ai\agentic_irc\scripts\irc_listen.py --home C:\Users\x\.agentic-irc-cursor' },
        [pscustomobject]@{ ProcessId = 55; ParentProcessId = 999; CommandLine = 'python.exe -u C:\ai\agentic_irc\scripts\irc_listen.py --home C:\Users\x\.agentic-irc-cursor' },
        [pscustomobject]@{ ProcessId = 77; ParentProcessId = 5; CommandLine = 'python.exe -u irc_listen.py --home C:\Users\x\.agentic-irc-bobiverse' },
        [pscustomobject]@{ ProcessId = 88; ParentProcessId = 5; CommandLine = 'python.exe -u irc_listen.py --home "C:\Users\x\.agentic-irc-cursor2"' },
        [pscustomobject]@{ ProcessId = 66; ParentProcessId = 5; CommandLine = 'python.exe -u irc_agent.py --home C:\Users\x\.agentic-irc-cursor' }
    )
    $mine = @(Select-IrcTsrListenProcesses -Processes $procs -IrcHome $h | ForEach-Object { $_.ProcessId } | Sort-Object)
    if (($mine -join ',') -ne '55,101') { throw "listens for home: got $($mine -join ',')" }
    $stale = @(Select-IrcTsrStaleListens -Processes $procs -IrcHome $h -KeepRunnerPid 100 | ForEach-Object { $_.ProcessId })
    if (($stale -join ',') -ne '55') { throw "orphan must be stale, runner child kept: got $($stale -join ',')" }
    $all = @(Select-IrcTsrStaleListens -Processes $procs -IrcHome $h -KeepRunnerPid 0 | ForEach-Object { $_.ProcessId } | Sort-Object)
    if (($all -join ',') -ne '55,101') { throw "restart must reap every listen for home: got $($all -join ',')" }
    if (-not (Test-IrcTsrListenChildOf -Processes $procs -IrcHome $h -RunnerPid 100)) { throw 'runner child listen must count' }
    if (Test-IrcTsrListenChildOf -Processes $procs -IrcHome $h -RunnerPid 200) { throw 'live runner 200 without its own listen must not borrow the orphan' }
    if (Test-IrcTsrListenChildOf -Processes @($procs[2]) -IrcHome $h -RunnerPid 100) { throw 'orphan-only must not look healthy' }
    $start = Get-Content (Join-Path $RepoRoot 'tools\Start-IrcTsr.ps1') -Raw
    $iReap = $start.IndexOf('Stop-IrcTsrStaleListens')
    $iLaunch = $start.IndexOf('Start-Process powershell.exe')
    if ($iReap -lt 0 -or $iReap -gt $iLaunch) { throw 'Start-IrcTsr must reap listens before launching the new runner' }
    $watch = Get-Content (Join-Path $RepoRoot 'tools\Watch-IrcTsr.ps1') -Raw
    if ($watch -match '\$listen\.Count -gt 0') { throw 'Watch-IrcTsr must not treat any listen (orphans) as the runner child' }
    if ($watch -notmatch 'Test-IrcTsrListenChildOf') { throw 'Watch-IrcTsr must check the listen is a child of the runner' }
}

Invoke-Case 'BT0irtsr listen leak mrb hostile' {
    # MRB #326: home match edge cases + watch tick reaps orphans while keeping runner child.
    . (Join-Path $RepoRoot 'tools\Irc-Tsr-Health.ps1')
    $h = 'C:\Users\x\.agentic-irc-cursor'
    $procs = @(
        [pscustomobject]@{ ProcessId = 100; ParentProcessId = 1; CommandLine = 'powershell.exe -File runner.ps1' },
        [pscustomobject]@{ ProcessId = 101; ParentProcessId = 100; CommandLine = 'python.exe irc_listen.py --home=C:\Users\x\.agentic-irc-cursor' },
        [pscustomobject]@{ ProcessId = 102; ParentProcessId = 100; CommandLine = 'python.exe irc_listen.py --home "C:\Users\x\.agentic-irc-cursor\"' },
        [pscustomobject]@{ ProcessId = 55; ParentProcessId = 999; CommandLine = 'python.exe irc_listen.py --home C:\Users\x\.agentic-irc-cursor' },
        [pscustomobject]@{ ProcessId = 88; ParentProcessId = 5; CommandLine = 'python.exe irc_listen.py --home C:\Users\x\.agentic-irc-cursor2' },
        [pscustomobject]@{ ProcessId = 66; ParentProcessId = 100; CommandLine = 'python.exe irc_agent.py --home C:\Users\x\.agentic-irc-cursor' }
    )
    $mine = @(Select-IrcTsrListenProcesses -Processes $procs -IrcHome $h | ForEach-Object { $_.ProcessId } | Sort-Object)
    if (($mine -join ',') -ne '55,101,102') { throw "home match (= / quoted slash): got $($mine -join ',')" }
    if (Select-IrcTsrListenProcesses -Processes $procs -IrcHome $h | Where-Object { $_.ProcessId -eq 66 }) {
        throw 'irc_agent must not count as irc_listen'
    }
    if (Select-IrcTsrListenProcesses -Processes $procs -IrcHome $h | Where-Object { $_.ProcessId -eq 88 }) {
        throw 'cursor2 home must not match cursor home'
    }
    $stale = @(Select-IrcTsrStaleListens -Processes $procs -IrcHome $h -KeepRunnerPid 100 | ForEach-Object { $_.ProcessId } | Sort-Object)
    if (($stale -join ',') -ne '55') { throw "only orphan 55 stale under keep 100: got $($stale -join ',')" }
    if (-not (Test-IrcTsrListenChildOf -Processes $procs -IrcHome $h -RunnerPid 100)) {
        throw 'equals-home listen child of runner must count'
    }
    if (Test-IrcTsrListenChildOf -Processes $procs -IrcHome $h -RunnerPid 0) {
        throw 'RunnerPid 0 must never look healthy'
    }
    $watch = Get-Content (Join-Path $RepoRoot 'tools\Watch-IrcTsr.ps1') -Raw
    if ($watch -notmatch 'Stop-IrcTsrStaleListens') { throw 'Watch-IrcTsr must reap orphans each tick' }
    if ($watch -notmatch 'KeepRunnerPid \$rid') { throw 'Watch-IrcTsr must keep the live runner listen while reaping' }
    $start = Get-Content (Join-Path $RepoRoot 'tools\Start-IrcTsr.ps1') -Raw
    if ($start -notmatch 'KeepRunnerPid 0') { throw 'Start-IrcTsr must reap all listens for home before launch' }
}

Invoke-Case 'BT0irtsr runner core matrix' {
    . (Join-Path $RepoRoot 'tools\Irc-Tsr-Health.ps1')
    if (-not (Test-IrcTsrRunnerHealthyCore -RunnerAlive $true -ListenChildUp $true -RunnerAgeSec 10 -RestartAfterSec 600 -WakeSilenceStale $false)) {
        throw 'expected healthy runner'
    }
    if (Test-IrcTsrRunnerHealthyCore -RunnerAlive $false -ListenChildUp $true -RunnerAgeSec 10 -RestartAfterSec 600 -WakeSilenceStale $false) {
        throw 'dead runner must fail'
    }
    if (Test-IrcTsrRunnerHealthyCore -RunnerAlive $true -ListenChildUp $false -RunnerAgeSec 10 -RestartAfterSec 600 -WakeSilenceStale $false) {
        throw 'missing listen child must fail'
    }
    if (Test-IrcTsrRunnerHealthyCore -RunnerAlive $true -ListenChildUp $true -RunnerAgeSec 900 -RestartAfterSec 600 -WakeSilenceStale $false) {
        throw 'runner age cap must fail'
    }
    if (Test-IrcTsrRunnerHealthyCore -RunnerAlive $true -ListenChildUp $true -RunnerAgeSec 10 -RestartAfterSec 600 -WakeSilenceStale $true) {
        throw 'stale wake must fail'
    }
    # #173 fix 5: quiet channel â€” fresh process heartbeat, idle/old/missing irc.log, no FROM â†’ no recycle
    $now = [datetime]'2026-09-22T12:00:00'
    $wakeQuiet = Join-Path $bridgeRoot 'irc-tsr-fix5-wake.jsonl'
    $hbFix5 = ($now.AddSeconds(-20).ToUniversalTime().ToString('o')) + ' PROCESS_HEARTBEAT'
    Set-Content -LiteralPath $wakeQuiet -Value $hbFix5 -Encoding utf8
    $wakeStaleFlag = Test-IrcTsrWakeSilenceStale -WakePath $wakeQuiet -SilenceSec 60 -Now $now
    if (-not (Test-IrcTsrRunnerHealthyCore -RunnerAlive $true -ListenChildUp $true -RunnerAgeSec 10 -RestartAfterSec 600 -WakeSilenceStale $wakeStaleFlag)) {
        throw 'healthy runner+listen with fresh process heartbeat must not recycle'
    }
    foreach ($ircCase in @(
            @{ label = 'idle'; content = 'PRIVMSG quiet' },
            @{ label = 'old'; content = 'PRIVMSG stale' },
            @{ label = 'missing'; content = $null }
        )) {
        $ircLogFix5 = Join-Path $bridgeRoot ("irc-fix5-{0}.log" -f $ircCase.label)
        if ($ircCase.content) {
            Set-Content -LiteralPath $ircLogFix5 -Value $ircCase.content -Encoding utf8
            (Get-Item -LiteralPath $ircLogFix5).LastWriteTime = $now.AddSeconds(-3600)
        }
        elseif (Test-Path -LiteralPath $ircLogFix5) { Remove-Item -LiteralPath $ircLogFix5 -Force }
        if (-not (Test-IrcTsrRunnerHealthyCore -RunnerAlive $true -ListenChildUp $true -RunnerAgeSec 10 -RestartAfterSec 600 -WakeSilenceStale $wakeStaleFlag)) {
            throw "irc.log $($ircCase.label) must not affect recycle when process heartbeat is fresh"
        }
    }
    $hbStale = ($now.AddSeconds(-120).ToUniversalTime().ToString('o')) + ' PROCESS_HEARTBEAT'
    Set-Content -LiteralPath $wakeQuiet -Value $hbStale -Encoding utf8
    if (-not (Test-IrcTsrWakeSilenceStale -WakePath $wakeQuiet -SilenceSec 60 -Now $now)) {
        throw 'stale process heartbeat must trip silence gate'
    }
    if (Test-IrcTsrRunnerHealthyCore -RunnerAlive $true -ListenChildUp $true -RunnerAgeSec 10 -RestartAfterSec 600 -WakeSilenceStale $true) {
        throw 'stale process heartbeat must fail healthy core'
    }
    $missingWakeFix5 = Join-Path $bridgeRoot 'irc-tsr-fix5-no-wake.jsonl'
    if (Test-Path -LiteralPath $missingWakeFix5) { Remove-Item -LiteralPath $missingWakeFix5 -Force }
    if (-not (Test-IrcTsrRunnerHealthyCore -RunnerAlive $true -ListenChildUp $true -RunnerAgeSec 10 -RestartAfterSec 600 -WakeSilenceStale $false)) {
        throw 'runner+listen up with missing wake must stay healthy until heartbeat is written'
    }
    foreach ($rel in @('tools\Watch-IrcTsr.ps1', 'tools\Start-IrcTsr.ps1', 'tools\Watch-CursorIrc.ps1')) {
        $raw = Get-Content (Join-Path $RepoRoot $rel) -Raw
        if ($raw -match "if \(\-not `$MachineId\) \{ `$MachineId = 'ionos' \}") { throw "$rel must not default MachineId to ionos" }
    }
    $runner = Get-Content (Join-Path $RepoRoot 'tools\Irc-Tsr-Runner.ps1') -Raw
    if ($runner -notmatch 'AGENT_LOOP_WAKE_irc-tsr') { throw 'Irc-Tsr-Runner must emit AGENT_LOOP_WAKE_irc-tsr' }
    if ($runner -notmatch 'PROCESS_HEARTBEAT') { throw 'Irc-Tsr-Runner must touch wake with PROCESS_HEARTBEAT while listen is alive' }
}

Invoke-Case 'BT0bobircd install contract' {
    $ircd = Get-Content (Join-Path $RepoRoot 'tools\Install-BobIrcd.ps1') -Raw
    if ($ircd -notmatch "ServiceName = 'BobIrcd'") { throw 'Install-BobIrcd must default service BobIrcd' }
    if ($ircd -notmatch 'nssm\.exe') { throw 'Install-BobIrcd must use Ergo-root nssm.exe' }
    if ($ircd -match 'filebrowser') { throw 'Install-BobIrcd must not copy NSSM from filebrowser' }
    if ($ircd -notmatch 'Unregister-ScheduledTask') { throw 'Install-BobIrcd must unregister BobIrcd-ionos' }
    if ($ircd -notmatch 'BobIrcd-ionos') { throw 'Install-BobIrcd must name old task BobIrcd-ionos' }
    if ($ircd -match '(?<!Un)Register-ScheduledTask') { throw 'Install-BobIrcd must not register BobIrcd-ionos' }
    if ($ircd -match 'Stop-Process.*ergo') { throw 'Install-BobIrcd must not Stop-Process ergo' }
    if ($ircd -notmatch 'sc\.exe create') { throw 'Install-BobIrcd must create service via sc.exe' }
    if ($ircd -notmatch 'start= auto') { throw 'Install-BobIrcd must set Automatic start' }
    if ($ircd -notmatch 'Application') { throw 'Install-BobIrcd must set NSSM Application to ergo.exe' }
    if ($ircd -notmatch "AppParameters.*run --conf ircd\.yaml") { throw 'Install-BobIrcd must pass run --conf ircd.yaml' }
    if ($ircd -notmatch 'AppExit') { throw 'Install-BobIrcd must configure NSSM AppExit Restart' }
    if ($ircd -notmatch 'Restart-Service') { throw 'Install-BobIrcd help must document Restart-Service' }
}

Invoke-Case 'BT0bobircd cert and ionos docs' {
    $cert = Get-Content (Join-Path $RepoRoot 'tools\Install-BobIrcdCert.ps1') -Raw
    if ($cert -notmatch 'Restart-Service') { throw 'Install-BobIrcdCert must Restart-Service BobIrcd' }
    if ($cert -match 'Start-ScheduledTask|Stop-ScheduledTask|(?<!Un)Register-ScheduledTask|Unregister-ScheduledTask|BobFleet-') {
        throw 'Install-BobIrcdCert must not touch scheduled tasks or BobFleet'
    }
    $doc = Get-Content (Join-Path $RepoRoot 'docs\bobiverse-ionos-ircd.md') -Raw
    if ($doc -notmatch 'Start-Service BobIrcd') { throw 'ionos doc must document Start-Service BobIrcd' }
    if ($doc -notmatch 'Restart-Service BobIrcd') { throw 'ionos doc must document Restart-Service BobIrcd' }
    if ($doc -match 'Start-ScheduledTask -TaskName.*BobIrcd-ionos') { throw 'ionos doc must not tell operators to start BobIrcd-ionos' }
    if ($doc -match '\| Task \|.*BobIrcd-ionos') { throw 'ionos doc must not list BobIrcd-ionos as a logon task' }
    if ($doc -notmatch 'Install-BobIrcdCert') { throw 'ionos doc must reference in-repo cert recycle script' }
}

Invoke-Case 'BT0bobircd fleet isolation' {
    $fleet = Get-Content (Join-Path $RepoRoot 'tools\Install-BobFleet.ps1') -Raw
    if ($fleet -notmatch 'Register-ScheduledTask') { throw 'Install-BobFleet must keep logon scheduled tasks' }
    if ($fleet -match 'BobIrcd') { throw 'Install-BobFleet must not register BobIrcd service' }
    $ircd = Get-Content (Join-Path $RepoRoot 'tools\Install-BobIrcd.ps1') -Raw
    if ($ircd -match 'BobFleet') { throw 'Install-BobIrcd must not stop BobFleet tasks' }
}

Invoke-Case 'BT0jeeves chair autostart' {
    $cfg = Get-Content (Join-Path $RepoRoot 'config\bobiverse.json') -Raw | ConvertFrom-Json
    if ([string]$cfg.chairNick -ne 'Jeeves') { throw 'chairNick must be Jeeves' }
    $chair = Get-Content (Join-Path $RepoRoot 'tools\Install-BobChair.ps1') -Raw
    if ($chair -notmatch '\.agentic-irc-jeeves') { throw 'Install-BobChair must use .agentic-irc-jeeves' }
    if ($chair -notmatch 'BOB_DIGEST_HOME') { throw 'Install-BobChair must set BOB_DIGEST_HOME' }
    if ($chair -notmatch '\.agentic-irc-bobiverse') { throw 'Install-BobChair must point BOB_DIGEST_HOME at .agentic-irc-bobiverse' }
    if ($chair -match 'Install-BobIrc\.ps1') { throw 'Install-BobChair must not call Install-BobIrc' }
    if ($chair -match '--hello|--announce-key') { throw 'Install-BobChair must not pass hello or announce-key' }
    $inst = Get-Content (Join-Path $RepoRoot 'tools\Install-BobJeeves.ps1') -Raw
    if ($inst -notmatch "ServiceName = 'BobJeeves'") { throw 'Install-BobJeeves must default service BobJeeves' }
    if ($inst -notmatch "DependsOn = 'BobIrcd'") { throw 'BobJeeves must depend on BobIrcd' }
    if ($inst -notmatch 'depend=') { throw 'Install-BobJeeves must pass sc depend=' }
    if ($inst -notmatch 'start= auto') { throw 'BobJeeves must be Automatic' }
    if ($inst -notmatch 'nssm\.exe') { throw 'Install-BobJeeves must use Ergo-root nssm.exe' }
    if ($inst -match 'filebrowser') { throw 'Install-BobJeeves must not copy NSSM from filebrowser' }
    if ($inst -notmatch 'BOB_DIGEST_HOME') { throw 'Install-BobJeeves must set BOB_DIGEST_HOME' }
    if ($inst -notmatch '\.agentic-irc-jeeves') { throw 'Install-BobJeeves must keep the Jeeves IRC home' }
    if ($inst -notmatch '\.agentic-irc-bobiverse') { throw 'Install-BobJeeves must name the digest home' }
    if ($inst -match '--hello|--announce-key') { throw 'Install-BobJeeves must not pass hello or announce-key' }
    $start = Get-Content (Join-Path $RepoRoot 'tools\Start-BobJeeves.ps1') -Raw
    if ($start -notmatch '\$env:BOB_DIGEST_HOME') { throw 'Start-BobJeeves must set BOB_DIGEST_HOME' }
    if ($start -notmatch '\.agentic-irc-jeeves') { throw 'Start-BobJeeves must default --home to .agentic-irc-jeeves' }
    if ($start -notmatch '\.agentic-irc-bobiverse') { throw 'Start-BobJeeves must default digest home to .agentic-irc-bobiverse' }
    if ($start -notmatch '--chair') { throw 'Start-BobJeeves must pass --chair' }
    if ($start -notmatch "'--home'") { throw 'Start-BobJeeves must pass --home' }
    if ($start -notmatch 'irc\.ntsa\.uk') { throw 'Start-BobJeeves must target irc.ntsa.uk' }
    if ($start -match '--hello|--announce-key') { throw 'Start-BobJeeves must not pass hello or announce-key' }
    if ($start -notmatch 'connect\.password') { throw 'Start-BobJeeves must read connect.password into the environment' }
    if ($start -notmatch 'Stop-Process') { throw 'Start-BobJeeves must kill the prior chair before start' }
    $ircd = Get-Content (Join-Path $RepoRoot 'tools\Install-BobIrcd.ps1') -Raw
    if ($ircd -notmatch 'Start-Service -Name ''BobJeeves''') { throw 'Install-BobIrcd must start BobJeeves when that service exists' }
    if ($ircd -notmatch 'Start-Service BobJeeves') { throw 'Install-BobIrcd must document Start-Service BobJeeves' }
    $cert = Get-Content (Join-Path $RepoRoot 'tools\Install-BobIrcdCert.ps1') -Raw
    if ($cert -notmatch 'Restart-Service') { throw 'Install-BobIrcdCert must still restart BobIrcd' }
    if ($cert -notmatch 'BobJeeves') { throw 'Install-BobIrcdCert must start BobJeeves after BobIrcd' }
    if ($cert -match 'Start-ScheduledTask|Stop-ScheduledTask|(?<!Un)Register-ScheduledTask|Unregister-ScheduledTask|BobFleet-') {
        throw 'Install-BobIrcdCert must not touch scheduled tasks or BobFleet'
    }
    $doc = Get-Content (Join-Path $RepoRoot 'docs\bobiverse-ionos-ircd.md') -Raw
    if ($doc -notmatch 'BobJeeves') { throw 'ionos doc must document BobJeeves' }
    if ($doc -notmatch 'Start-Service BobJeeves') { throw 'ionos doc must document Start-Service BobJeeves' }
    if ($doc -notmatch 'BOB_DIGEST_HOME') { throw 'ionos doc must document BOB_DIGEST_HOME' }
    if ($doc -notmatch '\.agentic-irc-jeeves') { throw 'ionos doc must document the Jeeves home' }
    if ($doc -notmatch 'Restart-Service BobIrcd') { throw 'ionos doc must keep Restart-Service BobIrcd' }
    $bv = Get-Content (Join-Path $RepoRoot 'docs\bobiverse.md') -Raw
    if ($bv -notmatch 'BobJeeves') { throw 'bobiverse.md must document BobJeeves autostart' }
    if ($bv -notmatch '\.agentic-irc-jeeves') { throw 'bobiverse.md must document the Jeeves home' }
    if ($bv -notmatch 'BOB_DIGEST_HOME') { throw 'bobiverse.md must document BOB_DIGEST_HOME' }
    $skill = Get-Content (Join-Path $RepoRoot '.grok\skills\bob-irc\SKILL.md') -Raw
    if ($skill -notmatch 'BOB_DIGEST_HOME') { throw 'bob-irc stub must mention BOB_DIGEST_HOME' }
    if ($skill -notmatch 'BobJeeves') { throw 'bob-irc stub must mention service BobJeeves' }
    $watch = Get-Content (Join-Path $RepoRoot 'tools\Watch-Bobiverse.ps1') -Raw
    if ($watch -match 'Install-BobJeeves|Install-BobChair|--chair') { throw 'Watch-Bobiverse must not start the chair' }
}

Invoke-Case 'BT0irtsr install and bobiverse isolation' {
    $installSrc = Get-Content (Join-Path $RepoRoot 'tools\Install-BobFleet.ps1') -Raw
    if ($installSrc -notmatch '_Watch-IrcTsr-') { throw 'Install-BobFleet must register _Watch-IrcTsr-<id>' }
    if ($installSrc -notmatch '_Watch-CursorIrc-') { throw 'Install-BobFleet must register _Watch-CursorIrc-<id>' }
    if (-not (Test-Path (Join-Path $RepoRoot 'tools\_Watch-IrcTsr.ps1'))) { throw 'missing tools/_Watch-IrcTsr.ps1' }
    if (-not (Test-Path (Join-Path $RepoRoot 'tools\_Watch-CursorIrc.ps1'))) { throw 'missing tools/_Watch-CursorIrc.ps1' }
    $tsWrap = Get-Content (Join-Path $RepoRoot 'tools\_Watch-IrcTsr.ps1') -Raw
    if ($tsWrap -notmatch 'Watch-IrcTsr\.ps1') { throw '_Watch-IrcTsr must delegate to Watch-IrcTsr.ps1' }
    $ciWrap = Get-Content (Join-Path $RepoRoot 'tools\_Watch-CursorIrc.ps1') -Raw
    if ($ciWrap -notmatch 'Watch-CursorIrc\.ps1') { throw '_Watch-CursorIrc must delegate to Watch-CursorIrc.ps1' }
    $watchBv = Get-Content (Join-Path $RepoRoot 'tools\Watch-Bobiverse.ps1') -Raw
    if ($watchBv -match 'Watch-IrcTsr|Start-IrcTsr|Watch-CursorIrc') {
        throw 'Watch-Bobiverse must not fold IRC TSR / Cursor listen pollers'
    }
    $watchCi = Get-Content (Join-Path $RepoRoot 'tools\Watch-CursorIrc.ps1') -Raw
    if ($watchCi -notmatch 'Start-IrcTsr') { throw 'Watch-CursorIrc must start TSR via Start-IrcTsr' }
    if ($watchCi -match 'grok\.exe') { throw 'Watch-CursorIrc must not invoke grok.exe' }
}

# --- BT0git shop !BORED / !TASK (digest webhook queue, no worker !ACCEPT) ---
Invoke-Case 'BT0git shop bored accept' {
    param($bridgeRoot)
    $src = Get-Content (Join-Path $RepoRoot 'src\Private\Invoke-BobGitAccept.ps1') -Raw
    if ($src -match '-AllowCopilot') { throw 'git accept must not pass -AllowCopilot' }
    if ($src -match 'chair-outbox') { throw 'git accept must not reference chair-outbox' }
    if ($src -match 'git-accept-queue') { throw 'git accept must not use git-accept-queue.json' }
    if ($src -match '(?m)^\s*PRIVMSG .+ :!ACCEPT') { throw 'worker tick must not emit !ACCEPT' }
    if ($src -notmatch 'Start-BobBuild') { throw 'git accept must call Start-BobBuild' }
    if ($src -notmatch '!TASK') { throw 'worker must take Jeeves !TASK' }
    if ($src -notmatch '!BORED') { throw 'worker must send !BORED' }

    $watchBv = Get-Content (Join-Path $RepoRoot 'tools\Watch-Bobiverse.ps1') -Raw
    if ($watchBv -notmatch 'Import-BobWorkerGitShop') { throw 'Watch-Bobiverse must tick shop !BORED' }
    if ($watchBv -notmatch 'Does not !ACCEPT') { throw 'Watch must say it does not !ACCEPT' }
    if ($watchBv -notmatch 'does not claim Jeeves GIT') { throw 'Watch must say it does not claim fleet GIT' }
    if ($watchBv -match 'chair-outbox') { throw 'Watch must not write the chair outbox' }

    $ping = ConvertFrom-BobGitAnnounce 'GIT ping SimonBarnett/agentic_build Keep it logically awesome by octocat'
    if ($ping) { throw 'ping must not be claimable' }
    $push = ConvertFrom-BobGitAnnounce 'GIT push SimonBarnett/agentic_build main deadbeef0123 1 commit(s) by simon'
    if ($push) { throw 'push must not be claimable' }
    $sync = ConvertFrom-BobGitAnnounce 'GIT pull_request SimonBarnett/agentic_build synchronize #44 more by simon'
    if ($sync) { throw 'synchronize must not be claimable' }
    $closed = ConvertFrom-BobGitAnnounce 'GIT pull_request SimonBarnett/agentic_build closed #44 done by simon'
    if ($closed) { throw 'closed pull_request must not be claimable' }
    $labeled = ConvertFrom-BobGitAnnounce 'GIT issues SimonBarnett/agentic_build labeled #12 label=FR by simon'
    if ($labeled) { throw 'labeled must not be claimable' }
    $pr = ConvertFrom-BobGitAnnounce 'GIT pull_request SimonBarnett/agentic_build opened #44 Hostile MRB by simon'
    if (-not $pr -or $pr.task -ne 'MRB' -or $pr.id -ne '#44') { throw "pull_request opened id=$($pr.id)" }
    $ready = ConvertFrom-BobGitAnnounce 'GIT pull_request SimonBarnett/agentic_build ready_for_review #7 title by simon'
    if (-not $ready -or $ready.task -ne 'MRB' -or $ready.id -ne '#7') { throw 'ready_for_review must be MRB #7' }
    $issue = ConvertFrom-BobGitAnnounce 'GIT issues SimonBarnett/agentic_build opened #12 Add a widget by simon'
    if (-not $issue -or $issue.task -ne 'PR' -or $issue.id -ne '#12') { throw "issues opened id=$($issue.id)" }
    $taskLine = ConvertFrom-BobGitTask '!TASK SimonBarnett/agentic_build MRB #44'
    if (-not $taskLine -or $taskLine.task -ne 'MRB' -or $taskLine.id -ne '#44' -or $taskLine.number -ne '44') {
        throw 'TASK parse failed'
    }
    $bareId = ConvertFrom-BobGitTask '!TASK SimonBarnett/agentic_build MRB 44'
    if ($bareId) { throw 'TASK id must keep the # prefix' }
    if (Test-BobGitBoredNak 'NAK !BORED empty') { } else { throw 'NAK empty' }
    if (Test-BobGitBoredNak 'FILE v1 ACCEPT abc') { throw 'FILE v1 ACCEPT is not a NAK' }
    if (ConvertFrom-BobGitTask 'FILE v1 ACCEPT owner/repo MRB #44') { throw 'FILE v1 ACCEPT must not parse as TASK' }
    if (ConvertFrom-BobGitTask 'OFFER SimonBarnett/agentic_build MRB #44') { throw 'OFFER is not a TASK' }

    $digest = [pscustomobject]@{
        v = 1
        git_unaccepted = [pscustomobject]@{
            v = 1
            items = @(
                [pscustomobject]@{ repo = 'SimonBarnett/agentic_build'; task = 'MRB'; id = '#44'; seq = 2 }
                [pscustomobject]@{ repo = 'SimonBarnett/agentic_build'; task = 'PR'; id = '#12'; seq = 1 }
                [pscustomobject]@{ repo = 'nope'; task = 'BUILD'; id = '#1'; seq = 0 }
            )
        }
    }
    $queued = @(Get-BobGitUnaccepted -Digest $digest)
    if ($queued.Count -ne 2) { throw "unaccepted rows=$($queued.Count)" }
    if ($queued[0].id -ne '#12' -or $queued[0].task -ne 'PR') { throw "fifo top=$($queued[0].task) $($queued[0].id)" }
    if ($queued[1].id -ne '#44') { throw 'second row must be #44' }
    $qpath = Join-Path $bridgeRoot 'no-queue.json'
    if (Test-Path $qpath) { Remove-Item $qpath -Force }
    $missing = @(Get-BobGitUnaccepted -JsonPath $qpath)
    if ($missing.Count -ne 0) { throw 'missing report must be empty' }
    if (Test-Path $qpath) { throw 'unaccepted read must not create a file' }

    $ircHome = Join-Path $bridgeRoot 'irc-home'
    New-Item -ItemType Directory -Force -Path $ircHome | Out-Null
    $env:BOB_MACHINE_ID = 'flamingo'
    $worker = Join-Path $ircHome 'workers\flamingo\4242'
    New-Item -ItemType Directory -Force -Path $worker | Out-Null
    $earOut = Join-Path $ircHome 'outbox.txt'
    'PRIVMSG #bobiverse :keep-builder' | Set-Content -LiteralPath $earOut -Encoding utf8
    $t0 = [datetime]::Parse('2026-09-24T10:00:00Z').ToUniversalTime()
    $startLog = Join-Path $bridgeRoot 'git-accept-starts.txt'
    $env:BOB_GIT_ACCEPT_TEST_LOG = $startLog
    $startOk = {
        param($Claim)
        Add-Content -LiteralPath $env:BOB_GIT_ACCEPT_TEST_LOG -Value ($Claim.repo + ' ' + $Claim.task + ' ' + $Claim.id) -Encoding utf8
        [pscustomobject]@{ ok = $true; wait = $false; jobId = 'job-44'; fuel = 'cursor-models'; model = 'grok-4.6' }
    }
    $chairs = @('Jeeves')
    $common = @{
        WorkerHome   = $worker
        ShopChannel  = '#flamingo'
        ChairNicks   = $chairs
        WorkerNick   = 'w-fl-4242'
        MachineId    = 'flamingo'
        StartWork    = $startOk
        SkipActivity = $true
    }
    $r0 = Invoke-BobWorkerShopTick @common -IsBusy:$false -Now $t0
    if ($r0.bored -or $r0.started) { throw 'first idle tick must only start the clock' }
    $r119 = Invoke-BobWorkerShopTick @common -IsBusy:$false -Now $t0.AddSeconds(119)
    if ($r119.bored) { throw '119s must not !BORED' }
    $rb = Invoke-BobWorkerShopTick @common -IsBusy:$false -Now $t0.AddSeconds(121)
    if (-not $rb.bored) { throw '121s must !BORED' }
    $ob = @(Get-Content (Join-Path $worker 'outbox.txt'))
    if ($ob.Count -ne 1 -or $ob[0] -ne 'PRIVMSG #flamingo :!BORED') { throw "bored line=$($ob -join ' | ')" }
    $rb2 = Invoke-BobWorkerShopTick @common -IsBusy:$false -Now $t0.AddSeconds(130)
    if ($rb2.bored -or $rb2.started) { throw 'second tick must not repeat !BORED' }

    Add-Content -LiteralPath (Join-Path $worker 'irc.log') -Value ':Jeeves!u@h PRIVMSG #bobiverse :!TASK SimonBarnett/agentic_build MRB #44' -Encoding utf8
    Add-Content -LiteralPath (Join-Path $worker 'irc.log') -Value ':Jeeves!u@h PRIVMSG #flamingo :GIT pull_request SimonBarnett/agentic_build opened #44 Hostile MRB by simon' -Encoding utf8
    Add-Content -LiteralPath (Join-Path $worker 'irc.log') -Value ':Jeeves!u@h PRIVMSG #flamingo :GIT ping SimonBarnett/agentic_build zen by simon' -Encoding utf8
    Add-Content -LiteralPath (Join-Path $worker 'irc.log') -Value ':bob-flamingo!u@h PRIVMSG #flamingo :!TASK SimonBarnett/agentic_build MRB #44' -Encoding utf8
    Add-Content -LiteralPath (Join-Path $worker 'irc.log') -Value ':Jeeves!u@h PRIVMSG #flamingo :FILE v1 ACCEPT deadbeef' -Encoding utf8
    Add-Content -LiteralPath (Join-Path $worker 'irc.log') -Value ':Jeeves!u@h PRIVMSG #flamingo :OFFER SimonBarnett/agentic_build MRB #44' -Encoding utf8
    $rnoise = Invoke-BobWorkerShopTick @common -IsBusy:$false -Now $t0.AddSeconds(140)
    if ($rnoise.started) { throw 'fleet TASK, GIT, ping, non-chair, FILE, and OFFER must not start' }
    $ob = @(Get-Content (Join-Path $worker 'outbox.txt'))
    if ($ob.Count -ne 1) { throw "noise wrote outbox=$($ob -join ' | ')" }

    Add-Content -LiteralPath (Join-Path $worker 'irc.log') -Value ':Jeeves!u@h PRIVMSG #flamingo :!TASK SimonBarnett/agentic_build MRB #44' -Encoding utf8
    $rok = Invoke-BobWorkerShopTick @common -IsBusy:$false -Now $t0.AddSeconds(150)
    if (-not $rok.started) { throw 'shop !TASK must start work' }
    if ($rok.claim.id -ne '#44' -or $rok.claim.task -ne 'MRB') { throw "claim=$($rok.claim.task) $($rok.claim.id)" }
    $ob = @(Get-Content (Join-Path $worker 'outbox.txt'))
    if ($ob.Count -ne 1 -or ($ob -join ' ') -match '!ACCEPT') { throw "worker must not !ACCEPT: $($ob -join ' | ')" }
    $started = @(Get-Content $startLog)
    if ($started.Count -ne 1 -or $started[0] -ne 'SimonBarnett/agentic_build MRB #44') { throw "start log=$($started -join ' | ')" }
    $ear = @(Get-Content $earOut)
    if ($ear.Count -ne 1 -or $ear[0] -notmatch 'keep-builder') { throw "builder ear outbox changed: $($ear -join ' | ')" }

    $cap = Join-Path $bridgeRoot 'git-activity.ndjson'
    if (Test-Path $cap) { Remove-Item $cap -Force }
    $env:BOB_DIGEST_WEBHOOK_CAPTURE = $cap
    $code = Send-BobGitWorkActivity -Phase start -MachineId flamingo -Claim $rok.claim -Start $rok.start
    if ($code -ne 204) { throw "activity start status=$code" }
    $posted = Get-Content $cap -Raw
    if ($posted -notmatch 'Cursor Models') { throw "activity missing agent: $posted" }
    if ($posted -notmatch 'grok-4.6') { throw "activity missing model: $posted" }
    if ($posted -notmatch 'working_on') { throw "activity missing working_on: $posted" }
    if ($posted -notmatch 'SimonBarnett/agentic_build#44') { throw "activity missing repo id: $posted" }
    Send-BobGitWorkActivity -Phase clear -MachineId flamingo -Claim $rok.claim | Out-Null
    $lines = @(Get-Content $cap)
    if ($lines.Count -ne 2) { throw "activity lines=$($lines.Count)" }
    $cleared = $lines[1] | ConvertFrom-Json
    if ([string]$cleared.working_on -ne '') { throw "clear working_on=$($cleared.working_on)" }
    $env:BOB_DIGEST_WEBHOOK_CAPTURE = $null

    $busyPath = Join-Path $worker 'git-accept-busy.json'
    if (-not (Test-Path $busyPath)) { throw 'start must record busy job' }
    if (Test-BobGitAcceptWorkerBusy -WorkerHome $worker) { throw 'missing fleet job must clear busy' }
    if (Test-Path $busyPath) { throw 'cleared busy file must be gone' }

    $jobDir = Join-Path $bridgeRoot 'fleet\inbox\flamingo'
    New-Item -ItemType Directory -Force -Path $jobDir | Out-Null
    '{"id":"live-job","machine":"flamingo","goal":"hold"}' | Set-Content -LiteralPath (Join-Path $jobDir 'live-job.json') -Encoding utf8
    '{"jobId":"live-job","repo":"SimonBarnett/agentic_build","task":"MRB","id":"#44"}' | Set-Content -LiteralPath $busyPath -Encoding utf8
    if (-not (Test-BobGitAcceptWorkerBusy -WorkerHome $worker)) { throw 'inbox job must stay busy' }

    $waitHome = Join-Path $ircHome 'workers\flamingo\99'
    New-Item -ItemType Directory -Force -Path $waitHome | Out-Null
    $t1 = [datetime]::Parse('2026-09-24T12:00:00Z').ToUniversalTime()
    $startWait = { param($Claim) [pscustomobject]@{ ok = $true; wait = $true; jobId = $null; reason = 'no eligible worker' } }
    Invoke-BobWorkerShopTick -WorkerHome $waitHome -ShopChannel '#flamingo' -IsBusy:$false -Now $t1 -ChairNicks $chairs -StartWork $startOk -SkipActivity | Out-Null
    Invoke-BobWorkerShopTick -WorkerHome $waitHome -ShopChannel '#flamingo' -IsBusy:$false -Now $t1.AddSeconds(121) -ChairNicks $chairs -StartWork $startOk -SkipActivity | Out-Null
    Add-Content -LiteralPath (Join-Path $waitHome 'irc.log') -Value ':Jeeves!u@h PRIVMSG #flamingo :NAK !BORED empty' -Encoding utf8
    $rnak = Invoke-BobWorkerShopTick -WorkerHome $waitHome -ShopChannel '#flamingo' -IsBusy:$false -Now $t1.AddSeconds(130) -ChairNicks $chairs -StartWork $startOk -SkipActivity
    if ($rnak.started) { throw 'NAK must not start' }
    if ($rnak.nak -ne 'empty') { throw "nak=$($rnak.nak)" }
    $wob = @(Get-Content (Join-Path $waitHome 'outbox.txt'))
    if ($wob.Count -ne 1 -or $wob[0] -ne 'PRIVMSG #flamingo :!BORED') { throw "nak outbox=$($wob -join ' | ')" }
    $rbored2 = Invoke-BobWorkerShopTick -WorkerHome $waitHome -ShopChannel '#flamingo' -IsBusy:$false -Now $t1.AddSeconds(260) -ChairNicks $chairs -StartWork $startOk -SkipActivity
    if (-not $rbored2.bored) { throw 'after NAK the worker must !BORED again once idle' }
    Add-Content -LiteralPath (Join-Path $waitHome 'irc.log') -Value ':Jeeves!u@h PRIVMSG #flamingo :!TASK SimonBarnett/agentic_build PR #12' -Encoding utf8
    $rwait = Invoke-BobWorkerShopTick -WorkerHome $waitHome -ShopChannel '#flamingo' -IsBusy:$false -Now $t1.AddSeconds(270) -ChairNicks $chairs -StartWork $startWait -SkipActivity
    if ($rwait.started) { throw 'wait start must not count as started' }
    $wob = @(Get-Content (Join-Path $waitHome 'outbox.txt'))
    if ($wob.Count -ne 2 -or ($wob -join ' ') -match '!ACCEPT') { throw "wait outbox=$($wob -join ' | ')" }

    foreach ($pair in @(@('21', 'w-fl-21'), @('22', 'w-fl-22'))) {
        $sib = Join-Path $ircHome ('workers\flamingo\' + $pair[0])
        New-Item -ItemType Directory -Force -Path $sib | Out-Null
        $t4 = [datetime]::Parse('2026-09-24T15:00:00Z').ToUniversalTime()
        Invoke-BobWorkerShopTick -WorkerHome $sib -ShopChannel '#flamingo' -IsBusy:$false -Now $t4 -ChairNicks $chairs -WorkerNick $pair[1] -StartWork $startOk -SkipActivity | Out-Null
        Invoke-BobWorkerShopTick -WorkerHome $sib -ShopChannel '#flamingo' -IsBusy:$false -Now $t4.AddSeconds(121) -ChairNicks $chairs -WorkerNick $pair[1] -StartWork $startOk -SkipActivity | Out-Null
    }
    $taskMsg = ':Jeeves!u@h PRIVMSG #flamingo :!TASK SimonBarnett/agentic_build MRB #88'
    Add-Content -LiteralPath (Join-Path $ircHome 'workers\flamingo\21\irc.log') -Value $taskMsg -Encoding utf8
    Add-Content -LiteralPath (Join-Path $ircHome 'workers\flamingo\22\irc.log') -Value $taskMsg -Encoding utf8
    $t5 = [datetime]::Parse('2026-09-24T15:05:00Z').ToUniversalTime()
    $first = Invoke-BobWorkerShopTick -WorkerHome (Join-Path $ircHome 'workers\flamingo\21') -ShopChannel '#flamingo' -IsBusy:$false -Now $t5 -ChairNicks $chairs -WorkerNick 'w-fl-21' -StartWork $startOk -SkipActivity
    $second = Invoke-BobWorkerShopTick -WorkerHome (Join-Path $ircHome 'workers\flamingo\22') -ShopChannel '#flamingo' -IsBusy:$false -Now $t5 -ChairNicks $chairs -WorkerNick 'w-fl-22' -StartWork $startOk -SkipActivity
    if (-not $first.started) { throw 'first idle sibling must start' }
    if ($second.started) { throw 'second sibling must no-op once the claim is taken' }
    $sib2 = @(Get-Content (Join-Path $ircHome 'workers\flamingo\22\outbox.txt'))
    if ($sib2 -join ' ' -match '!ACCEPT') { throw "second sibling spoke ACCEPT: $($sib2 -join ' | ')" }

    $env:BOB_GIT_ACCEPT_TEST_LOG = $null
    $env:BOB_DIGEST_WEBHOOK_CAPTURE = $null
    $env:BOB_MACHINE_ID = $null
}

# --- BT0house fleet docs / skills surface ---
Invoke-Case 'BT0house machine tables' {
    $regPath = Join-Path $RepoRoot 'config\fleet-registry.json'
    $ids = @((Get-Content $regPath -Raw | ConvertFrom-Json).machines | ForEach-Object { [string]$_.id })
    if ($ids.Count -lt 1) { throw 'fleet-registry has no machines' }
    $readme = Get-Content (Join-Path $RepoRoot 'README.md') -Raw
    $agent = Get-Content (Join-Path $RepoRoot 'agent_readme.md') -Raw
    foreach ($id in $ids) {
        $pat = '\|\s*``?' + [regex]::Escape($id) + '``?\s*\|'
        if ($readme -notmatch $pat) { throw "README missing machine table row for $id" }
        if ($agent -notmatch $pat) { throw "agent_readme missing machine table row for $id" }
    }
}

Invoke-Case 'BT0house no libera in agent docs' {
    foreach ($rel in @('README.md', 'agent_readme.md')) {
        $raw = Get-Content (Join-Path $RepoRoot $rel) -Raw
        if ($raw -match 'Libera') { throw "$rel mentions Libera" }
    }
    $skill = Get-Content (Join-Path $RepoRoot '.grok\skills\grok-build-fleet\SKILL.md') -Raw
    if ($skill -match 'Libera') { throw 'grok-build-fleet mentions Libera' }
    if ($skill -match 'machine named cursor') { throw 'grok-build-fleet has stale cursor-machine prose' }
}

Invoke-Case 'BT0house grok-fleet no tray cmdlets' {
    $skill = Get-Content (Join-Path $RepoRoot '.grok\skills\grok-build-fleet\SKILL.md') -Raw
    foreach ($bad in @('Get-BobTrayBarPaint', 'Get-BobTrayHover', 'Get-BobTrayTipPlacement', 'Get-BobTrayBarFillRgb')) {
        if ($skill -match $bad) { throw "grok-build-fleet documents tray cmdlet $bad" }
    }
}

Invoke-Case 'BT0house watch wrappers marked generated' {
    $watch = @(Get-ChildItem (Join-Path $RepoRoot 'tools') -Filter '_Watch-*.ps1' -ErrorAction SilentlyContinue)
    if ($watch.Count -lt 1) { throw 'no _Watch-*.ps1 under tools' }
    foreach ($f in $watch) {
        $head = (Get-Content $f.FullName -TotalCount 1) -join ''
        if ($head -notmatch 'DO NOT EDIT') { throw "$($f.Name) missing DO NOT EDIT header" }
    }
    $harvest = Get-Content (Join-Path $RepoRoot '.grok\skills\harvest-agent-skills\SKILL.md') -Raw
    if ($harvest -notmatch '_Watch-\*') { throw 'harvest-agent-skills must skip _Watch-* wrappers' }
}

Invoke-Case 'BT0house bob-build-loop pointer' {
    $loop = Get-Content (Join-Path $RepoRoot '.grok\skills\bob-build-loop\SKILL.md') -Raw
    if ($loop -notmatch 'Pointer') { throw 'bob-build-loop must be a pointer skill' }
    if ($loop -match 'flowchart') { throw 'bob-build-loop must not duplicate mermaid flowchart' }
}

Invoke-Case 'BT0house agent export list' {
    $agent = Get-Content (Join-Path $RepoRoot 'agent_readme.md') -Raw
    if ($agent -notmatch 'Select-BobGitWorker') { throw 'agent_readme missing agent export list' }
    if ($agent -notmatch 'Get-BobTrayHover') { throw 'agent_readme must classify tray exports' }
    if ($agent -notmatch 'job-audit') { throw 'agent_readme must document job-audit.jsonl' }
}

# --- BT0p21 control systray Cursor meters (issue #175 P21) ---
Invoke-Case 'BT0p21 control systray cursor meters' {
    param($bridgeRoot)
    $env:BOB_MACHINE_ID = 'ce-priority-dev1'
    $env:BOB_IRC_CONFIG = Join-Path $RepoRoot 'config\bobiverse.json'
    $null = Register-BobMachine -Id ce-priority-dev1 -CwdRoots $bridgeRoot
    $ircHome = Join-Path $bridgeRoot 'irc-p21-control'
    New-Item -ItemType Directory -Force -Path (Join-Path $ircHome 'bob-peers') | Out-Null
    $env:BOB_IRC_HOME = $ircHome
    $env:AGENTIC_IRC_HOME = $ircHome
    @'
{
  "machines": {
    "ce-priority-dev1": {
      "pcent": { "cursor-models": 0 },
      "running": 0,
      "jobs": []
    }
  }
}
'@ | Set-Content -Path (Join-Path $ircHome 'bob-peers\_report-digest.json') -Encoding utf8

    $h = Get-BobTrayHover
    $txt = [string]$h.jobs_text
    if (@($h.cursor_pools).Count -ne 3) { throw "cursor_pools count=$(@($h.cursor_pools).Count) want 3 control groups" }
    if ($txt -notmatch '(?m)^[ ]+(low cost models|auto)  0%') { throw "ntsa box must show 0% not n/a: $txt" }
    if ($txt -match '(?m)(low cost models|auto)  n/a') { throw "zero remaining must not render n/a: $txt" }
    $hoverSrc = Get-Content (Join-Path $RepoRoot 'src\Public\Get-BobTrayHover.ps1') -Raw
    if ($hoverSrc -notmatch 'Format-BobCursorControlPoolHeading') { throw 'hover must format control Cursor pool headings' }

    $env:BOB_MACHINE_ID = $null
    $env:BOB_IRC_HOME = $null
    $env:AGENTIC_IRC_HOME = $null
}

# --- BT0pair175 bob two persistent workers (issue #175 / FIX #177) ---
Invoke-Case 'BT0pair175 repo pair spawn idle webhook' {
    param($bridgeRoot)
    $env:BOB_MACHINE_ID = 'flamingo'
    $cwd = Join-Path $bridgeRoot 'cwd'
    $cap = Join-Path $bridgeRoot 'webhook-cap'
    $env:BOB_REPORT_CAPTURE_DIR = $cap
    $env:BOB_REPO_PAIR_IDLE_SEC = '120'

    $pairSrc = Get-Content (Join-Path $RepoRoot 'src\Private\Invoke-BobRepoPair.ps1') -Raw
    $pairWorkerSrc = Get-Content (Join-Path $RepoRoot 'src\Private\Start-BobRepoPairWorker.ps1') -Raw
    if ($pairSrc -match '(?<!Stop-)Start-BobWorker' -or $pairWorkerSrc -match '(?<!Stop-)Start-BobWorker') {
        throw 'repo pair must not spawn oneshot Start-BobWorker'
    }
    if ($pairWorkerSrc -match 'shop-joined-[^\s''"]+\.flag') { throw 'JOIN must not use shop-joined flag files' }
    if ($pairWorkerSrc -notmatch 'irc_agent') { throw 'shop JOIN must start irc_agent' }
    if ($pairWorkerSrc -match 'seat-supervisor\.ps1') { throw 'repo pair must not use heartbeat supervisor instead of agent' }
    if ($pairWorkerSrc -match "seat-cursor[^`n]*'-p'") { throw 'repo pair cursor seat must not use -p oneshot launch' }
    if ($pairWorkerSrc -match 'Get-BobArgv' -and $pairWorkerSrc -notmatch 'Get-BobRepoPairArgv') { throw 'repo pair must use Get-BobRepoPairArgv not oneshot Get-BobArgv' }
    if ($pairWorkerSrc -match 'irc_agent_stub|shop-irc-loop') { throw 'repo pair must not use IRC JOIN stub/sidecar' }
    if ($pairWorkerSrc -notmatch 'bob-build-dispatch') { throw 'dev seat must bind build skills' }
    if ($pairWorkerSrc -notmatch '--rules') { throw 'cursor persistent seat must pass --rules' }
    if ($pairWorkerSrc -notmatch 'grokbot') { throw 'seat agent must implement grokbot path' }
    $grokPairSrc = Get-Content (Join-Path $RepoRoot 'src\Private\Invoke-Grok.ps1') -Raw
    if ($grokPairSrc -match "Add\('--persistent'\)") { throw 'Get-BobRepoPairArgv must not emit invented grok --persistent' }
    $fakeGrokSrc = Get-Content (Join-Path $RepoRoot 'tools\Fake-Grok.ps1') -Raw
    if ($fakeGrokSrc -match '--persistent' -and $fakeGrokSrc -notmatch 'not a real grok flag') { throw 'Fake-Grok must reject invented --persistent' }
    if ($pairWorkerSrc -notmatch "cursor-agent', 'persist'|cursor-agent', `"persist`"" -and $pairWorkerSrc -notmatch "'persist'") { throw 'cursor seat must launch cursor-agent persist subcommand' }
    if ($pairSrc -notmatch 'Get-BobBobiverseAgentsIdleOverSec') { throw 'chair must wire idle-over-20s bobiverse agents' }
    if ($pairSrc -notmatch 'Invoke-BobIrcDrainOutboxLines') { throw 'bobiverse digest must drain PRIVMSG from outbox' }
    if ($pairSrc -notmatch 'TOPIC \$chan') { throw 'shop channel description must queue IRC TOPIC' }
    if ($pairSrc -notmatch 'Sync-BobIrcChannelOpsWire') { throw 'channel ops must MODE on wire not JSON copy only' }
    if ($pairWorkerSrc -match '--hello') { throw 'workers must not use irc_agent --hello shop PRIVMSG' }
    if ($pairSrc -match 'Add-BobIrcOutboxChannelLine \$line' -and $pairSrc -notmatch 'Add-BobIrcBobiversePrivmsg') { throw 'bobiverse digest must PRIVMSG #bobiverse not channel say()' }
    if ($pairSrc -match 'PRIVMSG \$chan.*TOPIC') { throw 'shop description must not fake TOPIC as PRIVMSG text' }
    if ($pairSrc -notmatch 'Sync-BobChannelOpsManifest') { throw 'repo pair must write channel ops manifest (A23)' }
    if ($pairSrc -notmatch 'Test-BobRepoPairTicketCadenceDue') { throw 'chair must gate outstanding tickets on cadence' }
    $digestSrc = Get-Content (Join-Path $RepoRoot 'src\Private\Invoke-BobDigestWebhook.ps1') -Raw
    if ($digestSrc -notmatch 'Merge-BobFleetCursorPoolsLesser') { throw 'usage webhook must lesser-merge fleet cursor pools' }
    if ($digestSrc -notmatch 'Invoke-BobRepoPairChairUsageWebhookIfChanged') { throw 'chair must post usage webhook on change' }
    if ($digestSrc -notmatch 'cursor_pools') { throw 'usage webhook must include cursor_pools' }
    if ($digestSrc -notmatch 'local_weekly') { throw 'usage webhook must include local_weekly grok pool' }
    if ($pairSrc -match 'bob-job-loop|cursor-mrb-dev') { throw 'repo pair prompts must not reference nested handoff skills' }
    $fleetSrc = Get-Content (Join-Path $RepoRoot 'src\Private\Invoke-BobFleet.ps1') -Raw
    if ($fleetSrc -notmatch 'Invoke-BobRepoPairChairTick') { throw 'Invoke-BobFleetTick must tick repo pair chair' }
    $watchBv = Get-Content (Join-Path $RepoRoot 'tools\Watch-Bobiverse.ps1') -Raw
    if ($watchBv -notmatch 'Sync-BobShopChannelRepoDescriptions') { throw 'Watch-Bobiverse must apply shop channel descriptions' }

    $pairSkill = Get-Content (Join-Path $RepoRoot '.grok\skills\bob-repo-pair\SKILL.md') -Raw
    if ($pairSkill -notmatch 'Start-BobRepoPair') { throw 'bob-repo-pair skill missing Start-BobRepoPair' }
    if ($pairSkill -notmatch 'no self-MRB|self-MRB') { throw 'bob-repo-pair skill must document self-MRB rule' }
    if ($pairSkill -notmatch 'working_on') { throw 'bob-repo-pair skill must document working_on webhook' }
    if ($pairSkill -notmatch '5 min') { throw 'bob-repo-pair skill must document idle default' }
    if ($pairSkill -match 'pending-shop-topic\.txt.*only') { throw 'skill must not claim pending-shop-topic alone is enough' }
    $bv = Get-Content (Join-Path $RepoRoot 'docs\bobiverse.md') -Raw
    if ($bv -notmatch 'Start-BobRepoPair') { throw 'bobiverse.md must document repo pair' }

    $live = Start-BobRepoPair -Repo 'SimonBarnett/agentic_build' -Cwd $cwd -MachineId flamingo
    if (-not $live.ok) { throw "Start-BobRepoPair live: $($live | ConvertTo-Json -Compress)" }
    $workers = @(Get-BobWorkers)
    if ($workers.Count -ne 2) { throw "expected 2 overlay workers got $($workers.Count)" }
    foreach ($w in $workers) {
        if ([string]$w.kind -ne 'persistent') { throw "worker $($w.sessionId) kind=$($w.kind) must be persistent" }
        if (-not $w.shopNick) { throw 'worker missing shopNick (JOIN policy)' }
    }
    Start-Sleep -Seconds 1
    if (-not (Test-BobRepoPairSeatAlive -Seat $live.dev)) { throw 'dev seat not alive (process/shop)' }
    if (-not (Test-BobRepoPairSeatAlive -Seat $live.mrb)) { throw 'mrb seat not alive (process/shop)' }

    $fakeSeat = [pscustomobject]@{ sessionId = [guid]::NewGuid().ToString() }
    $overlayPath = Join-Path $bridgeRoot 'overlay.json'
    $ov = Get-Content $overlayPath -Raw | ConvertFrom-Json
    $ov.workers += ,[pscustomobject]@{
        sessionId = [string]$fakeSeat.sessionId
        title     = 'w-fl-fake'
        cwd       = $cwd
        kind      = 'oneshot'
        profile   = 'generic'
        shopNick  = 'w-fl-fake'
        createdAt = [DateTime]::UtcNow.ToString('o')
    }
    ($ov | ConvertTo-Json -Depth 8) | Set-Content -Path $overlayPath -Encoding utf8
    if (Test-BobRepoPairSeatAlive -Seat $fakeSeat) { throw 'oneshot overlay row must not count as alive seat' }

    $pr = 'https://github.com/SimonBarnett/agentic_build/issues/175'
    $regCheck = Register-BobRepoPairDevComplete -PrUrl $pr
    if (-not $regCheck.ok) { throw "Register-BobRepoPairDevComplete: $($regCheck.error)" }
    $deny = Test-BobRepoPairSelfMrb -Seat dev -PrUrl $pr
    if ($deny.allowed) { throw 'dev must not MRB own PR' }
    $allow = Test-BobRepoPairSelfMrb -Seat mrb -PrUrl $pr
    if (-not $allow.allowed) { throw 'mrb seat must be allowed to review implementer PR' }
    $mrbEmpty = Test-BobRepoPairSelfMrb -Seat mrb -PrUrl 'https://github.com/SimonBarnett/agentic_build/pull/999'
    if ($mrbEmpty.allowed) { throw 'mrb must not default-allow with no implementer PR' }

    $sha = 'dead175beef'
    $a = Set-BobRepoPairDevActiveSha -Sha $sha
    if (-not $a.ok) { throw 'first active sha should ok' }
    $dup = Test-BobRepoPairMayEnqueueBuild -Sha $sha
    if ($dup.allowed) { throw 'second job same sha must be blocked' }

    $u1 = Update-BobRepoWorkerWorkingOn -Seat dev -Description 'implement #175 pair module'
    if (-not $u1.ok) { throw 'working_on update failed' }
    if (-not $u1.webhook.posted) { throw 'first working_on must POST' }
    $posts1 = @(Get-ChildItem $cap -Filter 'post-*.json').Count
    if ($posts1 -lt 1) { throw 'capture dir missing post json' }
    $u2 = Update-BobRepoWorkerWorkingOn -Seat dev -Description 'implement #175 pair module'
    if ($u2.webhook.posted) { throw 'unchanged working_on must not POST again' }

    $assign = Assign-BobRepoPairTask -Seat mrb -Task 'hostile MRB issue #175' -PrUrl $pr
    if (-not $assign.ok) { throw "chair assign mrb: $($assign.error)" }
    $badAssign = Assign-BobRepoPairTask -Seat dev -Task 'self review' -PrUrl $pr
    if ($badAssign.ok) { throw 'dev must not be assigned MRB on own PR' }

    $env:BOB_FAKE_GH_MODE = 'ok'
    [IO.File]::WriteAllText(
        (Join-Path $bridgeRoot 'fake-gh-open-issues.json'),
        '[{"number":177,"title":"MRB FAIL pair","labels":[{"name":"mrb"}]},{"number":175,"title":"FR pair","labels":[{"name":"feature-request"}]}]'
    )
    $tix = Invoke-BobRepoPairOutstandingTickets
    if (-not $tix.ok -or $tix.ticketCount -lt 1) { throw "ticket assign: $($tix | ConvertTo-Json -Compress)" }

    Register-BobRepoPairMrbComplete -PrUrl $pr -Verdict PASS-nits | Out-Null
    $say = Invoke-BobRepoPairBobiverseSay
    if (@($say.said).Count -lt 1) { throw 'bobiverse say must post digest lines' }
    $outbox = Join-Path $env:BOB_IRC_HOME 'outbox.txt'
    if (-not (Test-Path $outbox)) { throw 'missing IRC outbox after bobiverse say' }
    $drainedPath = Join-Path $env:BOB_IRC_HOME 'outbox-drained.txt'
    if (-not (Test-Path $drainedPath)) { throw 'bobiverse PRIVMSG must be drained from outbox (not only queued)' }
    $drained = Get-Content $drainedPath -Raw
    if ($drained -notmatch 'dev complete') { throw "drained outbox missing dev complete: $drained" }
    if ($drained -notmatch 'MRB complete') { throw "drained outbox missing MRB complete: $drained" }
    if ((Get-Content $outbox -Raw) -match 'PRIVMSG #bobiverse') { throw 'bobiverse lines must not remain in outbox after drain' }

    $topic = Set-BobShopChannelRepoDescription -Repo 'SimonBarnett/agentic_build' -MachineId flamingo
    if (-not $topic.ok) { throw 'shop topic failed' }
    $descPath = Join-Path $env:BOB_IRC_HOME 'shop-channel-descriptions.json'
    if (-not (Test-Path $descPath)) { throw 'shop-channel-descriptions.json missing' }
    $desc = Get-Content $descPath -Raw
    if ($desc -notmatch '#flamingo') { throw "shop desc channel: $desc" }
    if ($desc -notmatch 'SimonBarnett/agentic_build') { throw "shop desc repo: $desc" }
    if (-not (Test-Path $outbox) -or (Get-Content $outbox -Raw) -notmatch 'SHOPDESC') { throw 'outbox must carry SHOPDESC for shop channel description' }
    if ($drained -notmatch 'PRIVMSG #bobiverse') { throw 'bobiverse digest must use PRIVMSG #bobiverse' }
    if ((Get-Content $outbox -Raw) -notmatch 'TOPIC #flamingo') { throw 'shop topic must use IRC TOPIC command' }

    $usage = Invoke-BobRepoPairChairUsageWebhookIfChanged -Force
    if (-not $usage.posted) { throw 'usage webhook must POST with pools' }
    $usageCap = Get-ChildItem $cap -Filter 'usage-post-*.json' | Select-Object -First 1
    if (-not $usageCap) { throw 'missing usage-post capture json' }
    $usageJson = Get-Content $usageCap.FullName -Raw | ConvertFrom-Json
    if (-not $usageJson.cursor_pools -or @($usageJson.cursor_pools).Count -lt 3) { throw 'usage webhook missing cursor_pools' }
    if (-not $usageJson.local_weekly) { throw 'usage webhook missing local_weekly' }

    $chair = Invoke-BobRepoPairChairTick
    if (-not $chair.ok) { throw 'chair tick failed' }
    if ($chair.tickets -and $chair.tickets.skipped -ne 'cadence' -and $chair.tickets.ticketCount -gt 0) {
        throw 'chair tick must not assign tickets every fleet poll (cadence gate)'
    }

    $pairPath = Join-Path $bridgeRoot 'repo-pair.json'
    $st = Get-Content $pairPath -Raw | ConvertFrom-Json
    $st.seats.dev.lastActiveAt = [DateTime]::UtcNow.AddMinutes(-10).ToString('o')
    ($st | ConvertTo-Json -Depth 8) | Set-Content -Path $pairPath -Encoding utf8
    $tick = Invoke-BobRepoPairTick
    if (@($tick.idleStop) -notcontains 'dev') { throw "idle tick must stop dev seat: $($tick.idleStop -join ',')" }

    $st2 = Get-Content $pairPath -Raw | ConvertFrom-Json
    $devSid = [string]$st2.seats.dev.sessionId
    if ($devSid) {
        $statusPath = Join-Path $bridgeRoot "workers\$devSid\status.json"
        if (Test-Path $statusPath) {
            $status = Get-Content $statusPath -Raw | ConvertFrom-Json
            if ($status.pid) {
                try { Stop-Process -Id ([int]$status.pid) -Force -ErrorAction SilentlyContinue } catch { }
            }
        }
    }
    $tick2 = Invoke-BobRepoPairTick
    if (@($tick2.restarted) -notcontains 'dev') { throw "deaf tick must restart dev: $($tick2.restarted -join ',')" }
}

Invoke-Case 'BT0house no duplicate module function names' {
    param($bridgeRoot)
    # Dot-sourced Private/Public files share one scope: a later same-named function
    # silently replaces an earlier one (Invoke-BobDigestWebhookPost -Payload regression).
    $defs = @{}
    foreach ($f in @(Get-ChildItem (Join-Path $RepoRoot 'src') -Recurse -Filter '*.ps1')) {
        $tok = $null; $err = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tok, [ref]$err)
        foreach ($st in @($ast.EndBlock.Statements)) {
            if ($st -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { continue }
            if (-not $defs.ContainsKey($st.Name)) { $defs[$st.Name] = @() }
            $defs[$st.Name] += ('{0}:{1}' -f $f.Name, $st.Extent.StartLineNumber)
        }
    }
    $dups = @($defs.GetEnumerator() | Where-Object { @($_.Value).Count -gt 1 } | ForEach-Object { '{0} -> {1}' -f $_.Key, (@($_.Value) -join ', ') })
    if ($dups.Count -gt 0) { throw "duplicate top-level functions: $($dups -join ' ; ')" }
}

Invoke-Case 'BT0tip hover pcent rows no remaining_pct crash' {
    param($bridgeRoot)
    $m = Get-Module BobBridge
    $rows = @(
        [pscustomobject]@{ source = 'cursor-models'; pct = 0; machine = 'ionos' }
        [pscustomobject]@{ source = 'grok-chat'; pct = 68; machine = 'flamingo' }
    )
    $pools = & $m { param($r) @(Get-BobCursorPoolsForTray -MachineId 'testhost' -LocalCursorDoc $null -PcentRows $r) } $rows
    if (@($pools | Where-Object { $null -eq $_ }).Count -gt 0) { throw 'pools must not contain null rows' }
    $auto = @($pools | Where-Object { [string]$_.group_id -eq 'auto' })[0]
    if (-not $auto -or [string]$auto.remaining_pct -ne '0') { throw "auto pool remaining_pct=$($auto.remaining_pct) (0 is real)" }
    $chat = @($pools | Where-Object { [string]$_.group_id -eq 'grok-chat' })[0]
    if (-not $chat -or [int]$chat.remaining_pct -ne 68) { throw "grok-chat pool remaining_pct=$($chat.remaining_pct)" }
    # Set-BobCursorControlPoolRow tolerates null, digest `remaining` shape, and hashtables.
    & $m { Set-BobCursorControlPoolRow -Pool $null -RemainingPct 5 -PeriodEnd '2026-10-16T17:23:01Z' }
    $digestPool = [pscustomobject]@{ id = 'cursor-models'; label = 'Cursor Models'; remaining = 9; group_label = 'auto' }
    & $m { param($p) Set-BobCursorControlPoolRow -Pool $p -RemainingPct 7 -PeriodEnd '2026-10-16T17:23:01Z' } $digestPool
    if ([int]$digestPool.remaining_pct -ne 7 -or [int]$digestPool.remaining -ne 7) { throw "digest pool remaining=$($digestPool.remaining) remaining_pct=$($digestPool.remaining_pct)" }
    $ht = @{ group_label = 'auto'; remaining = 3 }
    & $m { param($p) Set-BobCursorControlPoolRow -Pool $p -RemainingPct 4 -PeriodEnd $null } $ht
    if ([int]$ht['remaining_pct'] -ne 4 -or [int]$ht['remaining'] -ne 4) { throw 'hashtable pool not updated' }
}

Invoke-Case 'BT0tip digest webhook merge post lastSeen heartbeat' {
    param($bridgeRoot)
    $m = Get-Module BobBridge
    $cap = Join-Path $bridgeRoot 'digest-webhook-heartbeat.ndjson'
    $env:BOB_DIGEST_WEBHOOK_CAPTURE = $cap
    $env:BOB_DIGEST_WEBHOOK_HEARTBEAT_SEC = $null
    try {
        $doc1 = [pscustomobject]@{ id = 'testhost'; online = $true; status = 'operational'; weekly = 50; running = 0; queued = 0; jobs = @(); lastSeen = '2026-09-24T19:00:00.0000000Z'; source = 'irc' }
        $doc2 = [pscustomobject]@{ id = 'testhost'; online = $true; status = 'operational'; weekly = 50; running = 0; queued = 0; jobs = @(); lastSeen = '2026-09-24T19:01:00.0000000Z'; source = 'irc' }
        $code = & $m { param($d) Send-BobDigestWebhookIfChanged -Doc $d } $doc1
        if ($code -ne 204) { throw "first merge POST status=$code (Invoke-BobDigestWebhookMergePost -Payload must bind)" }
        $lines = @(Get-Content $cap | Where-Object { $_ })
        if ($lines.Count -ne 1) { throw "first POST count=$($lines.Count)" }
        if (($lines[0] | ConvertFrom-Json).lastSeen -ne '2026-09-24T19:00:00.0000000Z') { throw "merge payload must carry lastSeen: $($lines[0])" }
        $null = & $m { param($d, $b) Send-BobDigestWebhookIfChanged -Doc $d -Before $b } $doc2 $doc1
        $lines = @(Get-Content $cap | Where-Object { $_ })
        if ($lines.Count -ne 1) { throw "lastSeen-only within heartbeat must not POST: count=$($lines.Count)" }
        $statePath = & $m { Get-BobDigestWebhookPostStatePath }
        $st = Get-Content $statePath -Raw | ConvertFrom-Json
        if (-not $st.'testhost@posted_at') { throw 'state must record testhost@posted_at' }
        $st.'testhost@posted_at' = [string]([DateTimeOffset]::UtcNow.AddSeconds(-600).ToUnixTimeSeconds())
        ($st | ConvertTo-Json -Compress) | Set-Content -Path $statePath -Encoding utf8
        $code = & $m { param($d, $b) Send-BobDigestWebhookIfChanged -Doc $d -Before $b } $doc2 $doc1
        if ($code -ne 204) { throw "stale posted_at must heartbeat POST: status=$code" }
        $lines = @(Get-Content $cap | Where-Object { $_ })
        if ($lines.Count -ne 2) { throw "heartbeat POST count=$($lines.Count)" }
        if (($lines[1] | ConvertFrom-Json).lastSeen -ne '2026-09-24T19:01:00.0000000Z') { throw "heartbeat must advance lastSeen: $($lines[1])" }
        $env:BOB_DIGEST_WEBHOOK_HEARTBEAT_SEC = '0'
        $st = Get-Content $statePath -Raw | ConvertFrom-Json
        $st.'testhost@posted_at' = [string]([DateTimeOffset]::UtcNow.AddSeconds(-600).ToUnixTimeSeconds())
        ($st | ConvertTo-Json -Compress) | Set-Content -Path $statePath -Encoding utf8
        $null = & $m { param($d, $b) Send-BobDigestWebhookIfChanged -Doc $d -Before $b } $doc2 $doc1
        $lines = @(Get-Content $cap | Where-Object { $_ })
        if ($lines.Count -ne 2) { throw "HEARTBEAT_SEC=0 must disable heartbeat: count=$($lines.Count)" }
    }
    finally {
        $env:BOB_DIGEST_WEBHOOK_CAPTURE = $null
        $env:BOB_DIGEST_WEBHOOK_HEARTBEAT_SEC = $null
    }
}

Invoke-Case 'BT0agent grok TUI argv quoting' {
    param($bridgeRoot)
    # Systray Agents/Grok -> Watch-AgentHealth -> agent.exe TUI. PS 5.1 Start-Process does not
    # quote -ArgumentList elements, so '--rules <text with spaces>' + prompt split into words and
    # grok exited ("unexpected argument 'at' found") before the TUI window was visible.
    $wah = Join-Path $RepoRoot 'tools\Watch-AgentHealth\Watch-AgentHealth.ps1'
    $wahSrc = Get-Content $wah -Raw
    $tok = $null; $err = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($wah, [ref]$tok, [ref]$err)
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'ConvertTo-WatchProcessArgumentString' }, $true)
    if (-not $fn) { throw 'Watch-AgentHealth must define ConvertTo-WatchProcessArgumentString' }
    . ([scriptblock]::Create($fn.Extent.Text))
    if (-not ('BobTestArgv' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class BobTestArgv {
    [DllImport("shell32.dll", SetLastError = true)]
    static extern IntPtr CommandLineToArgvW([MarshalAs(UnmanagedType.LPWStr)] string cmd, out int n);
    [DllImport("kernel32.dll")]
    static extern IntPtr LocalFree(IntPtr h);
    public static string[] Split(string cmd) {
        int n;
        IntPtr p = CommandLineToArgvW(cmd, out n);
        try {
            string[] r = new string[n];
            for (int i = 0; i < n; i++) { r[i] = Marshal.PtrToStringUni(Marshal.ReadIntPtr(p, i * IntPtr.Size)); }
            return r;
        }
        finally { LocalFree(p); }
    }
}
"@
    }
    $rules = 'Skills live at C:\Users\x\.grok\skills. Follow agent-monitor, watch-seat; fleet to agentic_build.'
    $prompt = "WATCH SEAT. Line with `"quotes`" and C:\dir\ path`r`nsecond line ends with backslash\"
    $in = @('--no-auto-update', '--no-alt-screen', '--cwd', 'D:\ai', '-s', 'sid-1', '--rules', $rules, $prompt, '', 'C:\Program Files\x\')
    $cmd = ConvertTo-WatchProcessArgumentString -ArgumentList $in
    $round = @([BobTestArgv]::Split('agent.exe ' + $cmd))
    if ($round.Count -ne ($in.Count + 1)) { throw "argv count=$($round.Count - 1) want $($in.Count): $cmd" }
    for ($i = 0; $i -lt $in.Count; $i++) {
        if ($round[$i + 1] -cne $in[$i]) { throw "argv[$i] round-trip mismatch: got <$($round[$i + 1])> want <$($in[$i])>" }
    }
    $tui = [regex]::Match($wahSrc, "(?s)\`$argList = @\('--no-auto-update', '--no-alt-screen'.*?AgentTuiWindowStyle")
    if (-not $tui.Success) { throw 'grok TUI launch block not found' }
    if ($tui.Value -notmatch 'ConvertTo-WatchProcessArgumentString -ArgumentList \$argList') { throw 'grok TUI Start-Process must quote argv via ConvertTo-WatchProcessArgumentString' }
    if ($tui.Value -match "'-p'|'--print'|'--prompt'") { throw 'grok TUI launch must not use headless -p/--print flags' }
    if ($wahSrc -notmatch "\[string\]\`$Windows = 'on'") { throw 'Watch-AgentHealth default -Windows must stay on (visible TUI)' }
    if ($wahSrc -notmatch "AgentTuiWindowStyle = \`$\(if \(\`$Windows -eq 'on'\) \{ 'Normal' \}") { throw 'TUI window style must be Normal when -Windows on' }
    $traySrc = Get-Content (Join-Path $RepoRoot 'tools\Watch-BobTray.ps1') -Raw
    $sessFn = [regex]::Match($traySrc, '(?s)function Start-BobTrayProcessWithSessionEnv\s*\{.*?^\}', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $sessFn.Success) { throw 'Start-BobTrayProcessWithSessionEnv not found' }
    if ($sessFn.Value -notmatch 'EnvironmentVariables\[') { throw 'session API key must be passed only via child ProcessStartInfo.EnvironmentVariables' }
    if ($sessFn.Value -match 'SetEnvironmentVariable|\$env:XAI_API_KEY\s*=|\$env:CURSOR_API_KEY\s*=') { throw 'session API key must not be set on the tray process / User / Machine env' }
}

Invoke-Case 'BT0tray idempotent ear/jobs start' {
    param($bridgeRoot)
    # Tray restart spawned a second Watch-Bobiverse ear (and Watch-BobJobs): PS 5.1 unrolls a
    # one-element @() returned from Test-*WatcherUp to a bare object whose .Count is $null.
    $trayPath = Join-Path $RepoRoot 'tools\Watch-BobTray.ps1'
    $tok = $null; $err = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($trayPath, [ref]$tok, [ref]$err)
    foreach ($name in @('Select-BobTraySingleWatcher', 'Start-IrcWatcher', 'Start-JobsWatcher')) {
        $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        if (-not $fn) { throw "Watch-BobTray must define $name" }
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    $calls = @{ wrap = 0; jobs = 0; stopped = @() }
    $ears = @()
    $jobsUp = @()
    function Write-TrayLog([string]$m) { }
    function Start-BobiverseMootWrapper { $calls.wrap++ }
    function Test-BobiverseWatcherUp { $h = @($ears); return $h }
    function Test-JobsWatcherUp { $h = @($jobsUp); return $h }
    function Stop-Process { param([int]$Id, [switch]$Force, [string]$ErrorAction) $calls.stopped += $Id }
    function Start-Process { $calls.jobs++; return [pscustomobject]@{ Id = 999 } }
    $watchJobs = 'x'
    $old = [pscustomobject]@{ ProcessId = 100; ParentProcessId = 1; CreationDate = [datetime]'2026-09-24T20:00:00' }
    $new = [pscustomobject]@{ ProcessId = 200; ParentProcessId = 1; CreationDate = [datetime]'2026-09-24T21:00:00' }
    $child = [pscustomobject]@{ ProcessId = 300; ParentProcessId = 100; CreationDate = [datetime]'2026-09-24T20:00:01' }
    # one existing ear -> reuse (the bug: started a second one)
    $ears = @($old)
    Start-IrcWatcher
    if ($calls.wrap -ne 0) { throw "tray start with one existing ear spawned another (wrap=$($calls.wrap))" }
    if ($calls.stopped.Count -ne 0) { throw 'single ear must not be stopped' }
    # no ear -> start exactly one
    $ears = @()
    Start-IrcWatcher
    if ($calls.wrap -ne 1) { throw "no ear must start exactly one (wrap=$($calls.wrap))" }
    # two ears -> keep oldest, stop newer, start none
    $calls.wrap = 0
    $ears = @($new, $old)
    Start-IrcWatcher
    if ($calls.wrap -ne 0) { throw 'duplicate ears must not start a third' }
    if (($calls.stopped -join ',') -ne '200') { throw "must stop newer duplicate only, stopped=$($calls.stopped -join ',')" }
    # wrapper + in-process child tree is one watcher, not a duplicate
    $calls.stopped = @()
    $ears = @($old, $child)
    Start-IrcWatcher
    if ($calls.stopped.Count -ne 0) { throw 'wrapper->child tree must not be treated as duplicate' }
    # jobs watcher: one existing -> reuse, no Start-Process
    $jobsUp = @($old)
    Start-JobsWatcher
    if ($calls.jobs -ne 0) { throw 'tray start with one Watch-BobJobs spawned another' }
    if ($script:jobsPid -ne 100) { throw "jobsPid must adopt existing pid 100, got $($script:jobsPid)" }
}

Invoke-Case 'BT0agent watch seat joins IRC' {
    param($bridgeRoot)
    # Tray Agents > Grok opened the TUI but no seat nick joined #<machine>: Install-BobFleet copied a
    # stale fleet fork (no Ensure-WatchIrcSeat) over the Desktop AgentMonitor clone. Also: a reused
    # home kept agent.quit.request (irc_agent QUITs on connect) and coordinator.pid seat=<dead pid>
    # (irc_agent seat liveness QUITs "seat ended").
    $wah = Join-Path $RepoRoot 'tools\Watch-AgentHealth\Watch-AgentHealth.ps1'
    $wahSrc = Get-Content $wah -Raw
    if ($wahSrc -notmatch 'function Ensure-WatchIrcSeat') { throw 'fleet Watch-AgentHealth must define Ensure-WatchIrcSeat (monitor starts irc_agent + irc_listen)' }
    if (([regex]::Matches($wahSrc, '\$state = Ensure-WatchIrcSeat -State \$state')).Count -lt 2) { throw 'Ensure-WatchIrcSeat must run at watch start and in the watch loop' }
    $tok = $null; $err = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($wah, [ref]$tok, [ref]$err)
    foreach ($name in @('Resolve-WatchSeatPid', 'Clear-WatchStaleQuitRequest', 'Ensure-WatchIrcSeat', 'ConvertTo-WatchProcessArgumentString')) {
        $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        if (-not $fn) { throw "fleet Watch-AgentHealth must define $name" }
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    $root = Join-Path $bridgeRoot 'wah-irc'
    $seatHome = Join-Path $root '.agentic-irc-watch-grok'
    $scripts = Join-Path $root 'scripts'
    New-Item -ItemType Directory -Force -Path $seatHome, $scripts, (Join-Path $root '.grok\ergo') | Out-Null
    Set-Content -LiteralPath (Join-Path $root '.grok\ergo\connect.password') -Value 'bt0-fake-not-a-password'
    Set-Content -LiteralPath (Join-Path $seatHome 'agent.quit.request') -Value '1790282899 watch stop'
    Set-Content -LiteralPath (Join-Path $seatHome 'quit.req') -Value 'watch stop'
    $dead = 999990
    while (Get-Process -Id $dead -ErrorAction SilentlyContinue) { $dead-- }
    Set-Content -LiteralPath (Join-Path $seatHome 'coordinator.pid') -Value @("nick=marchhare-$dead", "seat=$dead", 'listen=1', 'agent=', "home=$seatHome")
    $started = New-Object System.Collections.ArrayList
    function Write-WatchLog([string]$m) { }
    function Test-ForbiddenIrcHome { param([string]$ResolvedHome) return $false }
    function Get-WatchIrcAgentRows { param([string]$ResolvedHome) return @() }
    function Get-WatchIrcListenRows { param([string]$ResolvedHome) return @() }
    function Resolve-AgenticIrcScriptsDir { return $scripts }
    function Get-WatchMachineId { return 'marchhare' }
    function Get-Command { return [pscustomobject]@{ Source = 'python.exe' } }
    function Start-Sleep { }
    function Start-Process { param($FilePath, $ArgumentList, $WindowStyle, $RedirectStandardOutput, $RedirectStandardError) [void]$started.Add([string]$ArgumentList) }
    $saved = @{ up = $env:USERPROFILE; pw = $env:AGENTIC_IRC_PASSWORD; dbg = $env:AGENTIC_IRC_DEBUG; seat = $env:AGENTIC_IRC_SEAT_PID }
    try {
        $env:USERPROFILE = $root
        $state = Ensure-WatchIrcSeat -State ([pscustomobject]@{ ircHome = $seatHome })
    }
    finally {
        $env:USERPROFILE = $saved.up
        $env:AGENTIC_IRC_PASSWORD = $saved.pw
        $env:AGENTIC_IRC_DEBUG = $saved.dbg
        $env:AGENTIC_IRC_SEAT_PID = $saved.seat
    }
    if ($started.Count -ne 2) { throw "Ensure-WatchIrcSeat must start irc_agent + irc_listen (started=$($started.Count))" }
    if ($started[0] -notmatch 'irc_agent\.py') { throw 'first start must be irc_agent.py' }
    if ($started[0] -notmatch '--channel #bobiverse,#marchhare,#agentic_irc') { throw "seat must JOIN #bobiverse,#<machine>,#agentic_irc: $($started[0])" }
    if ($started[0] -match "marchhare-$dead\b") { throw 'stale coordinator seat= (dead pid) must not become the nick (irc_agent QUITs: seat ended)' }
    if ($started[0] -notmatch "--nick marchhare-$PID(\s|$)") { throw "nick must be <machine>-<live seat pid>: $($started[0])" }
    if ($started[1] -notmatch 'irc_listen\.py') { throw 'second start must be irc_listen.py' }
    foreach ($leaf in @('agent.quit.request', 'quit.req')) {
        if (Test-Path -LiteralPath (Join-Path $seatHome $leaf)) { throw "stale $leaf must be cleared before starting irc_agent (else it QUITs on connect)" }
    }
    if ([string]$state.ircNick -ne "marchhare-$PID") { throw "state.ircNick=$($state.ircNick)" }
    if ((Get-Content -LiteralPath (Join-Path $seatHome 'coordinator.pid') -Raw) -notmatch "(?m)^seat=$PID\s*$") { throw 'coordinator.pid must be rewritten with the live seat pid' }
    $live = Join-Path $seatHome 'live.pid'
    Set-Content -LiteralPath $live -Value "seat=$PID"
    if ((Resolve-WatchSeatPid -CoordPath $live -Default 1) -ne $PID) { throw 'a running coordinator seat= must be honoured' }
    $fleet = Get-Content (Join-Path $RepoRoot 'tools\Install-BobFleet.ps1') -Raw
    if ($fleet -notmatch 'Install-AgentMonitor\.ps1') { throw 'Install-BobFleet must deploy the watch seat via Install-AgentMonitor (canonical AgentMonitor clone)' }
    if ($fleet -notmatch "-not \(Test-Path -LiteralPath \(Join-Path \`$watchDst '\.git'\)\)") { throw 'Install-BobFleet must not copy the fleet fork over the AgentMonitor git clone' }
}

Invoke-Case 'BT0tray grok session key overrides OAuth' {
    param($bridgeRoot)
    # grok 1.0.41 prefers ~/.grok/auth.json (OAuth) over XAI_API_KEY; the #314 session key was
    # ignored. Session env must isolate GROK_AUTH_PATH to a fresh temp path, child-env only.
    $trayPath = Join-Path $RepoRoot 'tools\Watch-BobTray.ps1'
    $traySrc = Get-Content $trayPath -Raw
    $tok = $null; $err = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($trayPath, [ref]$tok, [ref]$err)
    foreach ($name in @('Get-BobTrayGrokSessionRoot', 'New-BobTrayGrokSessionEnv', 'Register-BobTrayGrokSession', 'Clear-BobTrayGrokSessionDirs')) {
        $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        if (-not $fn) { throw "Watch-BobTray must define $name" }
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    function Write-TrayLog([string]$m) { }
    $script:bobTrayGrokSessions = @()
    $beforeAuth = $env:GROK_AUTH_PATH
    $beforeKey = $env:XAI_API_KEY
    $dummy = 'xai-bt0-dummy-not-a-key'
    $e1 = New-BobTrayGrokSessionEnv -ApiKey $dummy
    $e2 = New-BobTrayGrokSessionEnv -ApiKey $dummy
    if ($e1.XAI_API_KEY -ne $dummy) { throw 'session env must carry XAI_API_KEY' }
    $ap = [string]$e1.GROK_AUTH_PATH
    if (-not $ap) { throw 'session env must set GROK_AUTH_PATH (else OAuth auth.json wins over XAI_API_KEY)' }
    $tmp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not ([IO.Path]::GetFullPath($ap)).StartsWith($tmp, [StringComparison]::OrdinalIgnoreCase)) { throw "GROK_AUTH_PATH must live under TEMP: $ap" }
    if ((Split-Path -Leaf $ap) -ne 'auth.json') { throw 'GROK_AUTH_PATH must point at an auth.json file path' }
    if (Test-Path -LiteralPath $ap) { throw 'session auth.json must not exist (no OAuth creds for the child)' }
    if (-not (Test-Path -LiteralPath (Split-Path -Parent $ap))) { throw 'session dir must exist' }
    if ($ap -eq $e2.GROK_AUTH_PATH) { throw 'each start needs its own session dir' }
    if ($ap -like "*\.grok\auth.json") { throw 'must not reuse ~/.grok/auth.json' }
    if ($env:GROK_AUTH_PATH -ne $beforeAuth -or $env:XAI_API_KEY -ne $beforeKey) { throw 'tray process env must not be modified' }
    # exited child -> session dir removed; running child -> kept
    Register-BobTrayGrokSession -Process ([pscustomobject]@{ HasExited = $true }) -SessionEnv $e1
    Register-BobTrayGrokSession -Process ([pscustomobject]@{ HasExited = $false }) -SessionEnv $e2
    Clear-BobTrayGrokSessionDirs
    if (Test-Path -LiteralPath (Split-Path -Parent $e1.GROK_AUTH_PATH)) { throw 'exited session dir must be removed' }
    if (-not (Test-Path -LiteralPath (Split-Path -Parent $e2.GROK_AUTH_PATH))) { throw 'running session dir must be kept' }
    Remove-Item -LiteralPath (Split-Path -Parent $e2.GROK_AUTH_PATH) -Recurse -Force
    # contracts: Agents->Grok and Plan->Grok both use it; child-env only; tracked for cleanup
    if (([regex]::Matches($traySrc, '\$sessionEnv = New-BobTrayGrokSessionEnv -ApiKey \$key')).Count -ne 2) { throw 'Agents->Grok and Plan->Grok must both build env via New-BobTrayGrokSessionEnv' }
    if ($traySrc -match '\$sessionEnv = @\{ XAI_API_KEY') { throw 'bare XAI_API_KEY session env is ignored when OAuth auth.json exists' }
    if ($traySrc -match 'SetEnvironmentVariable|\$env:XAI_API_KEY\s*=|\$env:GROK_AUTH_PATH\s*=|\$env:CURSOR_API_KEY\s*=') { throw 'session key/auth path must not touch tray/User/Machine env' }
    if (([regex]::Matches($traySrc, 'Register-BobTrayGrokSession -Process \$proc -SessionEnv \$SessionEnv')).Count -ne 2) { throw 'both session launch helpers must register the child for session-dir cleanup' }
}

Invoke-Case 'BT0install bobfleet idempotent' {
    param($bridgeRoot)
    # Re-running Install-BobFleet on a live box: Start-ScheduledTask BobFleet-<id> with no running
    # check -> SECOND tray; GrokTalk/IrcTsr/CursorIrc tasks registered + started on every machine
    # from the generic tools\_Watch-<Name>.ps1; User env overwritten every run.
    . (Join-Path $RepoRoot 'tools\BobInstallHelpers.ps1')
    foreach ($name in @('Select-BobTraySingleWatcher', 'Start-BobInstallTray', 'Install-BobWatcherTask', 'Set-BobInstallUserEnv')) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "BobInstallHelpers must provide $name" }
    }
    $st = @{ procs = @(); start = @(); stop = @(); reg = @(); env = @{}; set = @() }
    function Write-TrayLog([string]$m) { }
    function Get-BobInstallProcesses([string]$Pattern) { $h = @($st.procs | Where-Object { $_.CommandLine -match $Pattern }); return $h }
    function Stop-Process { param([int]$Id, [switch]$Force, [string]$ErrorAction) $st.stop += $Id }
    function Start-ScheduledTask { param([string]$TaskName) $st.start += $TaskName }
    function Register-ScheduledTask { param($TaskName, $Action, $Trigger, $Settings, $Principal, [switch]$Force, [string]$ErrorAction) if ($st.regFail) { throw 'Access is denied.' }; $st.reg += $TaskName }
    function New-ScheduledTaskAction { param($Execute, $Argument, $WorkingDirectory) return 'action' }
    function Get-ScheduledTask { param($TaskName, $ErrorAction) return $null }
    function Reset-Bt0Install { $st.start = @(); $st.stop = @(); $st.reg = @() }
    function New-Bt0Proc([int]$ProcId, [string]$When, [string]$Cmd) { [pscustomobject]@{ ProcessId = $ProcId; ParentProcessId = 1; CreationDate = [datetime]$When; CommandLine = $Cmd } }
    $trayOld = New-Bt0Proc 100 '2026-09-24T20:00:00' 'powershell.exe -NoProfile -STA -File D:\ai\agentic_build\tools\_Watch-BobTray-testbox.ps1'
    $trayNew = New-Bt0Proc 200 '2026-09-24T21:00:00' 'powershell.exe -NoProfile -STA -File "D:\ai\agentic_build\tools\Watch-BobTray.ps1"'
    $jobs = New-Bt0Proc 300 '2026-09-24T20:00:05' 'powershell.exe -NoProfile -File D:\ai\agentic_build\tools\Watch-BobJobs.ps1'
    $ear = New-Bt0Proc 400 '2026-09-24T20:00:10' 'powershell.exe -NoProfile -File D:\ai\agentic_build\tools\_Watch-Bobiverse-testbox.ps1'

    # --- tray: none -> start once; one -> reuse; two -> keep oldest, stop newer, start none
    $st.procs = @($jobs, $ear)
    $r = Start-BobInstallTray -TaskName 'BobFleet-testbox'
    if (-not $r.Started -or ($st.start -join ',') -ne 'BobFleet-testbox') { throw "no tray must start exactly one (start=$($st.start -join ','))" }
    Reset-Bt0Install
    $st.procs = @($trayOld, $jobs, $ear)
    $r = Start-BobInstallTray -TaskName 'BobFleet-testbox'
    if ($r.Started -or $st.start.Count -ne 0) { throw 're-run with a running tray started a second tray' }
    if ($st.stop.Count -ne 0) { throw 'single running tray must not be stopped' }
    if ($r.Pid -ne 100) { throw "must report the running tray pid 100, got $($r.Pid)" }
    Reset-Bt0Install
    $st.procs = @($trayNew, $trayOld, $jobs)
    $r = Start-BobInstallTray -TaskName 'BobFleet-testbox'
    if ($st.start.Count -ne 0) { throw 'duplicate trays must not start a third' }
    if (($st.stop -join ',') -ne '200' -or $r.Pid -ne 100) { throw "must keep oldest tray 100 and stop newer 200 only (stop=$($st.stop -join ','))" }

    # --- watcher tasks: generic wrapper alone is NOT this machine; machine wrapper or opt-in is
    $repo = Join-Path $bridgeRoot 'repo'
    New-Item -ItemType Directory -Force -Path (Join-Path $repo 'tools') | Out-Null
    foreach ($leaf in @('_Watch-GrokTalk.ps1', '_Watch-IrcTsr.ps1', '_Watch-IrcTsr-testbox.ps1', '_Watch-CursorIrc.ps1', '_Watch-Bobiverse.ps1', '_Watch-Bobiverse-testbox.ps1')) {
        Set-Content -LiteralPath (Join-Path $repo "tools\$leaf") -Value '# bt0'
    }
    $ta = @{ MachineId = 'testbox'; RepoRoot = $repo; Trigger = $null; Settings = $null; Principal = $null; PsExe = 'powershell.exe' }
    Reset-Bt0Install
    $st.procs = @()
    $w = Install-BobWatcherTask -Name 'GrokTalk' -TaskName '_Watch-GrokTalk-testbox' @ta
    if ($w.Registered -or $st.reg.Count -ne 0 -or $st.start.Count -ne 0) { throw 'generic-only GrokTalk must not be registered/started without -Watchers GrokTalk' }
    if ($w.Status -notmatch 'not for this machine' -or $w.Status -notmatch '-Watchers GrokTalk') { throw "skip status must explain opt-in: $($w.Status)" }
    $w = Install-BobWatcherTask -Name 'IrcTsr' -TaskName '_Watch-IrcTsr-testbox' @ta
    if (-not $w.Started -or $w.File -notlike '*_Watch-IrcTsr-testbox.ps1') { throw "machine wrapper IrcTsr must register + start its own wrapper ($($w.File))" }
    $w = Install-BobWatcherTask -Name 'CursorIrc' -TaskName '_Watch-CursorIrc-testbox' -OptIn @ta
    if (-not $w.Started -or $w.File -notlike '*\_Watch-CursorIrc.ps1') { throw 'opt-in CursorIrc must register + start the generic wrapper' }
    if (($st.reg -join ',') -ne '_Watch-IrcTsr-testbox,_Watch-CursorIrc-testbox') { throw "registered=$($st.reg -join ',')" }
    Reset-Bt0Install
    $w = Install-BobWatcherTask -Name 'Bobiverse' -TaskName '_Watch-Bobiverse-testbox' -AllMachines -NoStart @ta
    if (-not $w.Registered -or $w.Started -or $st.start.Count -ne 0) { throw 'ear with a just-started tray must be registered only (tray owns the ear start)' }
    if ($w.File -notlike '*_Watch-Bobiverse-testbox.ps1') { throw 'ear must prefer the machine wrapper' }
    Reset-Bt0Install
    $st.procs = @($ear, $trayOld)
    $w = Install-BobWatcherTask -Name 'Bobiverse' -TaskName '_Watch-Bobiverse-testbox' -AllMachines @ta
    if ($w.Started -or $st.start.Count -ne 0 -or $st.stop.Count -ne 0) { throw 'running ear must be reused, not started again' }
    if ($w.Status -notmatch 'already running pid=400') { throw "ear status: $($w.Status)" }
    # non-elevated shell: Register-ScheduledTask Access is denied -> say NOT registered, still no second ear
    Reset-Bt0Install
    $st.regFail = $true
    $w = Install-BobWatcherTask -Name 'Bobiverse' -TaskName '_Watch-Bobiverse-testbox' -AllMachines @ta
    $st.regFail = $false
    if ($w.Registered -or $w.Status -notmatch 'task NOT registered \(Access is denied\.\)') { throw "register failure must be reported: $($w.Status)" }
    if ($w.Status -notmatch 'already running pid=400' -or $st.start.Count -ne 0) { throw 'register failure must not start a second ear' }

    # --- User env: set when unset, keep existing, overwrite only with -Update, never secrets
    function Get-BobUserEnv([string]$Name) { return $st.env[$Name] }
    function Set-BobUserEnv([string]$Name, [string]$Value) { $st.set += $Name; $st.env[$Name] = $Value }
    $script:BobInstallEnvReport = $null
    $st.env = @{ BT0_INST_A = $null; BT0_INST_B = 'same'; BT0_INST_C = 'old' }
    try {
        $e = Set-BobInstallUserEnv -Name 'BT0_INST_A' -Value 'a'
        if ($e.Action -notmatch '^set' -or $st.env.BT0_INST_A -ne 'a' -or $e.Before -ne '' -or $e.After -ne 'a') { throw "unset var must be set: $($e | ConvertTo-Json -Compress)" }
        $e = Set-BobInstallUserEnv -Name 'BT0_INST_B' -Value 'same'
        if ($e.Action -ne 'unchanged') { throw "same value must be unchanged: $($e.Action)" }
        $e = Set-BobInstallUserEnv -Name 'BT0_INST_C' -Value 'new'
        if ($e.Action -notmatch '^kept' -or $st.env.BT0_INST_C -ne 'old') { throw 'existing different value must be kept without -Update' }
        if (($st.set -join ',') -ne 'BT0_INST_A') { throw "only the unset var may be written (set=$($st.set -join ','))" }
        $e = Set-BobInstallUserEnv -Name 'BT0_INST_C' -Value 'new' -Update
        if ($e.Action -notmatch '^updated' -or $st.env.BT0_INST_C -ne 'new') { throw '-Update must overwrite' }
        if (@($script:BobInstallEnvReport).Count -ne 4) { throw "env report must list every touched var ($(@($script:BobInstallEnvReport).Count))" }
        $threw = $false
        try { [void](Set-BobInstallUserEnv -Name 'BT0_INST_API_KEY' -Value 'bt0-fake') } catch { $threw = $true }
        if (-not $threw -or $st.env.ContainsKey('BT0_INST_API_KEY')) { throw 'secret-like names must never be persisted' }
    }
    finally {
        foreach ($n in @('BT0_INST_A', 'BT0_INST_B', 'BT0_INST_C')) { Remove-Item -LiteralPath "Env:$n" -ErrorAction SilentlyContinue }
        $script:BobInstallEnvReport = $null
    }

    # --- contracts: installers go through the helpers; no bare task start / env write
    $fleetSrc = Get-Content (Join-Path $RepoRoot 'tools\Install-BobFleet.ps1') -Raw
    $ircSrc = Get-Content (Join-Path $RepoRoot 'tools\Install-BobIrc.ps1') -Raw
    $helperSrc = Get-Content (Join-Path $RepoRoot 'tools\BobInstallHelpers.ps1') -Raw
    foreach ($pair in @(@('Install-BobFleet', $fleetSrc), @('Install-BobIrc', $ircSrc))) {
        if ($pair[1] -notmatch 'BobInstallHelpers\.ps1') { throw "$($pair[0]) must dot-source BobInstallHelpers.ps1" }
        if ($pair[1] -match 'SetEnvironmentVariable') { throw "$($pair[0]) must persist env only via Set-BobInstallUserEnv" }
    }
    if ($fleetSrc -match 'Start-ScheduledTask') { throw 'Install-BobFleet must start tasks only via Start-BobInstallTray / Install-BobWatcherTask' }
    if ($fleetSrc -notmatch '\$tray = Start-BobInstallTray -TaskName \$taskName') { throw 'Install-BobFleet must start the tray via Start-BobInstallTray' }
    if ($fleetSrc -notmatch 'Register-ScheduledTask -TaskName \$taskName [^\r\n]*-ErrorAction Stop' -or $fleetSrc -notmatch 'task NOT registered') { throw 'Install-BobFleet must report a failed tray task registration' }
    foreach ($n in @('GrokTalk', 'IrcTsr', 'CursorIrc')) {
        if ($fleetSrc -notmatch "-Name '$n' -TaskName \S+ -OptIn:\(\`$Watchers -contains '$n'\)") { throw "$n task must be opt-in (-Watchers $n) unless a machine wrapper exists" }
    }
    if (([regex]::Matches($helperSrc, 'SetEnvironmentVariable')).Count -ne 1) { throw 'only Set-BobUserEnv may call SetEnvironmentVariable' }
    if ($helperSrc -match "SetEnvironmentVariable\([^\)]*'Machine'") { throw 'installers must never write Machine env' }
    if ($ircSrc -notmatch '\$env:AGENTIC_IRC_PASSWORD = \$savedIrcEnv\.pw') { throw 'Install-BobIrc must restore AGENTIC_IRC_PASSWORD after starting irc_agent (session-only)' }
}

Write-Host ''
# BT0ergo cases for FR #327 - appended by mrb
Invoke-Case 'BT0ergo fleet should_op matrix' {
    . (Join-Path $RepoRoot 'tools\Ergo-FleetChannelOps.ps1')
    $reg = @{
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' = 'marchhare'
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' = 'flamingo'
    }
    $cloaks = @{ marchhare = 'thvzqfwjnt7bn.irc'; flamingo = 'thvzqfwjnt7bn.irc' }

    if (-not (Test-BobErgoStandingBotOp -Channel '#marchhare' -Nick 'bob-marchhare')) { throw 'bob-marchhare must stand +o in #marchhare' }
    if (Test-BobErgoStandingBotOp -Channel '#flamingo' -Nick 'bob-marchhare') { throw 'bob-marchhare must not stand in #flamingo' }
    if (-not (Test-BobErgoStandingBotOp -Channel '#bobiverse' -Nick 'Jeeves')) { throw 'Jeeves must stand in #bobiverse' }
    if (Test-BobErgoStandingBotOp -Channel '#bobiverse' -Nick 'simon') { throw 'simon never standing' }

    if (-not (Test-BobErgoShouldOp -Channel '#marchhare' -Nick 'bob-marchhare' -Account 'bob-marchhare' -FleetRegistry $reg)) {
        throw 'bob standing path'
    }

    $fpMh = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    if (-not (Test-BobErgoShouldOp -Channel '#marchhare' -Nick 'simon' -Account 'simon' -CertFp $fpMh -IrcHost 'thvzqfwjnt7bn.irc' -FleetRegistry $reg -BobCloaks $cloaks -RequireCloakMatch:$true)) {
        throw 'simon+fleet cert must op #marchhare'
    }
    if (-not (Test-BobErgoShouldOp -Channel '#bobiverse' -Nick 'simon' -Account 'simon' -CertFp $fpMh -FleetRegistry $reg)) {
        throw 'simon+fleet cert must op #bobiverse'
    }
    if (Test-BobErgoShouldOp -Channel '#flamingo' -Nick 'simon' -Account 'simon' -CertFp $fpMh -FleetRegistry $reg) {
        throw 'marchhare cert must not op #flamingo'
    }

    if (Test-BobErgoShouldOp -Channel '#marchhare' -Nick 'simon' -Account 'simon' -CertFp '' -IrcHost 'thvzqfwjnt7bn.irc' -FleetRegistry $reg) {
        throw 'password SASL simon without cert must not op'
    }
    if (Test-BobErgoShouldOp -Channel '#marchhare' -Nick 'simon' -Account 'simon' -CertFp 'ffffffffffffffffffffffffffffffffffffffff' -IrcHost 'thvzqfwjnt7bn.irc' -FleetRegistry $reg) {
        throw 'unknown certfp must not op even on fleet cloak'
    }

    if (Test-BobErgoShouldOp -Channel '#marchhare' -Nick 'simon' -Account '' -CertFp $fpMh -FleetRegistry $reg) {
        throw 'unauthenticated nick simon must not op'
    }
    if (Test-BobErgoShouldOp -Channel '#marchhare' -Nick 'simon' -Account 'other' -CertFp $fpMh -FleetRegistry $reg) {
        throw 'wrong account must not op'
    }

    $fpColon = 'aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa'
    if (-not (Test-BobErgoShouldOp -Channel '#marchhare' -Nick 'simon' -Account 'simon' -CertFp $fpColon -FleetRegistry $reg)) {
        throw 'certfp with colons must match registry'
    }
}

Invoke-Case 'BT0ergo channel registration yaml patch' {
    $script = Join-Path $RepoRoot 'tools\Set-BobIrcdChannelRegistration.ps1'
    $dir = Join-Path $env:TEMP ('ergo-fr327-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    try {
        $conf = Join-Path $dir 'ircd.yaml'
        $yaml = "server:`n    name: test`naccounts:`n    registration:`n        enabled: true`nchannels:`n    registration:`n        enabled: false`n"
        [System.IO.File]::WriteAllText($conf, $yaml, (New-Object System.Text.UTF8Encoding $false))
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -ConfPath $conf
        if ($LASTEXITCODE -ne 0) { throw "patch exit $LASTEXITCODE" }
        $t = Get-Content -LiteralPath $conf -Raw
        if ($t -notmatch '(?ms)channels:.*?registration:.*?enabled:\s*true') { throw "channels.registration not enabled: $t" }
        if ($t -notmatch '(?ms)accounts:.*?registration:.*?enabled:\s*false') { throw "accounts.registration must stay false: $t" }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -ConfPath $conf
        if ($LASTEXITCODE -ne 0) { throw 'second patch failed' }
        $inst = Get-Content (Join-Path $RepoRoot 'tools\Install-BobIrcd.ps1') -Raw
        if ($inst -notmatch 'Set-BobIrcdChannelRegistration') { throw 'Install-BobIrcd must call registration patch' }
        $doc = Get-Content (Join-Path $RepoRoot 'docs\bobiverse-ionos-ircd.md') -Raw
        if ($doc -notmatch 'FR #327' -or $doc -notmatch 'Test-BobErgoShouldOp') { throw 'docs must cover FR #327' }
        if ($doc -notmatch 'standing') { throw 'docs must cover simon standing op ban' }
        $ex = Join-Path $RepoRoot 'config\ergo-fleet-registry.example.json'
        if (-not (Test-Path $ex)) { throw 'missing fleet registry example' }
    }
    finally {
        Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
    }
}


Write-Host "BT0 summary: $($script:Pass) pass / $($script:Fail) fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
