# BT0 FR #343: packs/skills forbid FR self-merge; guard script self-test.
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
try {
    $requiredPhrases = @(
        'do NOT merge',
        'FR mode',
        'different seat',
        'bob-mrb-worker'
    )
    # soft: at least these files must mention no self-merge / open PR only
    $files = @(
        (Join-Path $RepoRoot 'docs\fr-mode-no-self-merge.md'),
        (Join-Path $RepoRoot 'docs\worker-pack-fr-mode.md'),
        (Join-Path $RepoRoot 'README.md'),
        (Join-Path $RepoRoot '.grok\skills\bob-mrb-worker\SKILL.md'),
        (Join-Path $RepoRoot '.grok\skills\start-bob-cursor\SKILL.md'),
        (Join-Path $RepoRoot 'tools\fr_self_merge_guard.py'),
        (Join-Path $RepoRoot 'tools\Assert-FrPrNoSelfMerge.ps1')
    )
    foreach ($f in $files) {
        if (-not (Test-Path -LiteralPath $f)) { throw "missing $f" }
    }
    $frDoc = Get-Content (Join-Path $RepoRoot 'docs\fr-mode-no-self-merge.md') -Raw
    foreach ($p in @('gh pr merge', 'FR mode', 'MRB mode', 'Different seat', 'fr_self_merge_guard', 'never self-merge')) {
        if ($frDoc -notmatch [regex]::Escape($p)) { throw "fr-mode doc missing: $p" }
    }
    $readme = Get-Content (Join-Path $RepoRoot 'README.md') -Raw
    if ($readme -notmatch 'FR #343' -and $readme -notmatch 'never self-merge') {
        throw 'README missing FR #343 / never self-merge'
    }
    $mrb = Get-Content (Join-Path $RepoRoot '.grok\skills\bob-mrb-worker\SKILL.md') -Raw
    if ($mrb -notmatch 'Different worker than author') { throw 'bob-mrb-worker missing different worker rule' }
    if ($mrb -notmatch 'FR mode') { throw 'bob-mrb-worker missing FR mode pointer' }

    $cursor = Get-Content (Join-Path $RepoRoot '.grok\skills\start-bob-cursor\SKILL.md') -Raw
    if ($cursor -notmatch 'do not merge' -and $cursor -notmatch 'Do not merge') {
        throw 'start-bob-cursor must say build opens PR without merge'
    }
    if ($cursor -notmatch 'FR #343' -and $cursor -notmatch 'FR mode') {
        throw 'start-bob-cursor missing FR #343 / FR mode'
    }

    $guard = Join-Path $RepoRoot 'tools\fr_self_merge_guard.py'
    $pyOut = & python $guard --self-test 2>&1
    if ($LASTEXITCODE -ne 0) { throw "guard self-test failed: $pyOut" }

    # fixture: self merge 2 min
    $fx = Join-Path $env:TEMP ("fr343-fx-" + [guid]::NewGuid().ToString('n') + '.json')
    @'
{"author":{"login":"w1"},"mergedBy":{"login":"w1"},"createdAt":"2026-09-25T10:00:00Z","mergedAt":"2026-09-25T10:01:00Z","state":"MERGED"}
'@ | Set-Content $fx -Encoding utf8
    & python $guard --fixture $fx --minutes 30 --json | Out-Null
    if ($LASTEXITCODE -ne 2) { throw "expected exit 2 for self-merge fixture, got $LASTEXITCODE" }
    Remove-Item $fx -Force -ErrorAction SilentlyContinue

    # Assert-FrPrNoSelfMerge.ps1 exists and -? doesn't throw path
    $ps1 = Join-Path $RepoRoot 'tools\Assert-FrPrNoSelfMerge.ps1'
    if (-not (Test-Path $ps1)) { throw 'missing Assert-FrPrNoSelfMerge.ps1' }

    Write-Host 'PASS BT0 FR #343 no self-merge FR PRs'
    exit 0
}
catch {
    Write-Host ('FAIL BT0 FR #343: ' + $_.Exception.Message)
    exit 1
}
