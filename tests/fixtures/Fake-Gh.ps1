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

Write-Error "Fake-Gh: unhandled: $joined"
Exit-Mode 1
