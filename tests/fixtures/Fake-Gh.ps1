# Fixture gh.exe for off-DEV Test-Pack (no live GitHub).
$ErrorActionPreference = 'Continue'
$argv = @($args)
$joined = ($argv -join ' ')

function Exit-Mode {
    param([int]$Code = 0)
    exit $Code
}

$mode = [string]$env:BOB_FAKE_GH_MODE
if (-not $mode) { $mode = 'ok' }

function Write-FakeGhLog {
    param([string]$Command)
    $log = $env:BOB_FAKE_GH_LOG
    if (-not $log) { return }
    $entry = [ordered]@{
        ts      = [DateTime]::UtcNow.ToString('o')
        argv    = $joined
        command = $Command
    }
    [IO.File]::AppendAllText($log, (($entry | ConvertTo-Json -Compress) + [Environment]::NewLine))
}

if ($joined -match '(?i)\bauth\s+status\b') {
    Write-FakeGhLog 'auth status'
    if ($mode -eq 'dead') { Exit-Mode 1 }
    Exit-Mode 0
}

if ($joined -match '(?i)\brepo\s+view\b') {
    Write-FakeGhLog 'repo view'
    if ($mode -eq 'dead') { Exit-Mode 1 }
    Write-Output 'fixture-repo'
    Exit-Mode 0
}

if ($joined -match '(?i)\blabel\s+create\b') {
    if ($mode -eq 'label-fail') {
        if ($env:BOB_FAKE_GH_QUIET -ne '1') {
            [Console]::Error.WriteLine('Fake-Gh: label create denied')
        }
        Exit-Mode 1
    }
    Exit-Mode 0
}

if ($joined -match '(?i)\blabel\s+list\b') {
    Write-Output '[]'
    Exit-Mode 0
}

if ($joined -match '(?i)\bissue\s+create\b') {
    $bodyFile = $null
    for ($i = 0; $i -lt $argv.Count; $i++) {
        if ([string]$argv[$i] -eq '--body-file' -and ($i + 1) -lt $argv.Count) {
            $bodyFile = [string]$argv[$i + 1]
            break
        }
    }
    if (-not $bodyFile -or -not (Test-Path -LiteralPath $bodyFile)) {
        Write-Error 'Fake-Gh: issue create missing --body-file'
        Exit-Mode 1
    }
    $body = [IO.File]::ReadAllText($bodyFile)
    $log = $env:BOB_FAKE_GH_LOG
    if ($log) {
        $entry = [ordered]@{
            ts       = [DateTime]::UtcNow.ToString('o')
            argv     = $joined
            body     = $body
            bodyFile = $bodyFile
        }
        [IO.File]::AppendAllText($log, (($entry | ConvertTo-Json -Compress) + [Environment]::NewLine))
    }
    Write-Output 'https://github.com/fixture/repo/issues/1'
    Exit-Mode 0
}

if ($joined -match '(?i)\bissue\s+comment\b') {
    Write-FakeGhLog 'issue comment'
    Exit-Mode 0
}

if ($joined -match '(?i)\bpr\s+list\b') {
    Write-FakeGhLog 'pr list'
    $json = $env:BOB_FAKE_GH_PR_JSON
    if (-not $json) { $json = '[]' }
    Write-Output $json
    Exit-Mode 0
}

if ($joined -match '(?i)\bissue\s+list\b') {
    Write-FakeGhLog 'issue list'
    $json = $env:BOB_FAKE_GH_ISSUE_JSON
    if (-not $json) { $json = '[]' }
    Write-Output $json
    Exit-Mode 0
}

function Get-FakeGhPrViewJson {
    $next = $env:BOB_FAKE_GH_PR_VIEW_NEXT
    if ($next -and (Test-Path -LiteralPath $next)) {
        return [IO.File]::ReadAllText($next)
    }
    $log = $env:BOB_FAKE_GH_LOG
    if ($log) {
        $sidecar = $log + '.pr-view.json'
        if (Test-Path -LiteralPath $sidecar) {
            return [IO.File]::ReadAllText($sidecar)
        }
    }
    $json = $env:BOB_FAKE_GH_PR_VIEW_JSON
    if (-not $json) { $json = '{"state":"OPEN","mergedAt":null}' }
    return $json
}

function Write-FakeGhPrViewMerged {
    $merged = '{"state":"MERGED","mergedAt":"2026-09-22T21:20:14Z"}'
    $next = $env:BOB_FAKE_GH_PR_VIEW_NEXT
    if ($next) {
        [IO.File]::WriteAllText($next, $merged)
    }
    $log = $env:BOB_FAKE_GH_LOG
    if ($log) {
        [IO.File]::WriteAllText(($log + '.pr-view.json'), $merged)
    }
}

if ($joined -match '(?i)\bpr\s+view\b') {
    Write-FakeGhLog 'pr view'
    Write-Output (Get-FakeGhPrViewJson)
    Exit-Mode 0
}

if ($joined -match '(?i)\bpr\s+merge\b') {
    Write-FakeGhLog 'pr merge'
    if ($mode -eq 'merge-fail') {
        [Console]::Error.WriteLine('Fake-Gh: pr merge denied')
        Exit-Mode 1
    }
    if ($mode -eq 'merge-in-progress') {
        Write-FakeGhPrViewMerged
        [Console]::Error.WriteLine('GraphQL: Merge already in progress (mergePullRequest)')
        Exit-Mode 1
    }
    Write-FakeGhPrViewMerged
    Exit-Mode 0
}

if ($joined -match '(?i)\bissue\s+close\b') {
    Write-FakeGhLog 'issue close'
    if ($mode -eq 'close-fail') {
        [Console]::Error.WriteLine('Fake-Gh: issue close denied')
        Exit-Mode 1
    }
    $log = $env:BOB_FAKE_GH_LOG
    if ($log) {
        $entry = [ordered]@{
            ts   = [DateTime]::UtcNow.ToString('o')
            argv = $joined
            op   = 'issue close'
        }
        [IO.File]::AppendAllText($log, (($entry | ConvertTo-Json -Compress) + [Environment]::NewLine))
    }
    Exit-Mode 0
}

Write-Error "Fake-Gh: unhandled: $joined"
Exit-Mode 1
