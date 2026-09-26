# FR #348: separate docs PR; never push docs(MRB onto the PR under review.
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

$guard = Join-Path $RepoRoot 'tools\mrb_docs_branch_guard.py'
if (-not (Test-Path -LiteralPath $guard)) { throw 'missing mrb_docs_branch_guard.py' }

& python $guard --self-test
if ($LASTEXITCODE -ne 0) { throw 'mrb_docs_branch_guard --self-test failed' }

$pack = Get-Content -LiteralPath (Join-Path $RepoRoot 'docs\worker-pack-fr-mode.md') -Raw -Encoding UTF8
if ($pack -notmatch 'never pushes commits to the PR under review' -and $pack -notmatch 'separate docs/mrb') {
    throw 'worker-pack-fr-mode.md must state MRB never pushes to PR under review / separate docs PR'
}

$skill = Get-Content -LiteralPath (Join-Path $RepoRoot '.grok\skills\bob-mrb-worker\SKILL.md') -Raw -Encoding UTF8
if ($skill -notmatch 'never push' -and $skill -notmatch 'Never push') {
    throw 'bob-mrb-worker must forbid pushing to the PR under review'
}
if ($skill -notmatch 'docs/mrb-') {
    throw 'bob-mrb-worker must name docs/mrb-<n> separate PR branch'
}

$mrb = Get-Content -LiteralPath (Join-Path $RepoRoot 'docs\mrb.md') -Raw -Encoding UTF8
if ($mrb -notmatch 'separate' -or $mrb -notmatch 'docs/mrb-') {
    throw 'docs/mrb.md must require separate docs/mrb-<n> PR'
}

Write-Host 'PASS BT0 FR #348 MRB separate docs PR'
exit 0
