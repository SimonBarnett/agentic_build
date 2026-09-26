# FR #401: Report-BobDeterministicException files templated issues via Fake-Gh; dedupe.
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Import-Module (Join-Path $RepoRoot 'src\BobBridge.psd1') -Force

$fakeGh = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
$bridge = Join-Path $env:TEMP ('bob-ex401-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $bridge | Out-Null
$log = Join-Path $bridge 'fake-gh.log'
$stateDir = Join-Path $bridge 'exception-issues'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

$env:BOB_GH_EXE = $fakeGh
$env:BOB_FAKE_GH_MODE = 'ok'
$env:BOB_FAKE_GH_LOG = $log
$env:BOB_EXCEPTION_ISSUE_DIR = (Join-Path $bridge 'exception-issues')

try {
    $ex = [System.Exception]::new('Access to the path is denied (fixture)')
    $r1 = Report-BobDeterministicException -Site 'Send-IrcLineToSession' -Exception $ex -ScriptPath 'Watch-AgentHealth.ps1' -Force
    if (-not $r1.ok) { throw "first report failed: $($r1.reason)" }
    if ($r1.deduped) { throw 'first report must not be deduped' }
    if ($r1.repo -ne 'SimonBarnett/AgentMonitor') { throw "owning repo=$($r1.repo)" }
    if (-not (Test-Path $log)) { throw 'Fake-Gh log missing' }
    $raw = Get-Content $log -Raw
    if ($raw -notmatch 'issue create') { throw 'expected issue create in fake gh log' }
    if ($raw -notmatch 'Deterministic exception \(no LLM\)') { throw 'body template missing' }

    $r2 = Report-BobDeterministicException -Site 'Send-IrcLineToSession' -Exception $ex -ScriptPath 'Watch-AgentHealth.ps1'
    if (-not $r2.ok) { throw "dedupe report failed: $($r2.reason)" }
    if (-not $r2.deduped) { throw 'second report must be deduped' }

    $own = Get-BobDeterministicExceptionOwningRepo -Site 'Write-BobIrcStatus' -ScriptPath 'src\Private\Get-BobIrc.ps1'
    if ($own -ne 'SimonBarnett/agentic_build') { throw "build own=$own" }

    Write-Host 'PASS BT0 FR #401 deterministic exception issue'
    exit 0
}
finally {
    Remove-Item -LiteralPath $bridge -Recurse -Force -ErrorAction SilentlyContinue
}
