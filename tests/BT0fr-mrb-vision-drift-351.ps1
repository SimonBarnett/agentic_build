# FR #351: bob-mrb-worker vision/drift step + packs
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$skill = Join-Path $RepoRoot '.grok\skills\bob-mrb-worker\SKILL.md'
$raw = Get-Content -LiteralPath $skill -Raw -Encoding UTF8
foreach ($need in @('FR #351', 'drift', 'VISION.md', 'Three Laws', 'Worked example', '```mermaid')) {
    if ($raw -notmatch [regex]::Escape($need) -and $need -ne '```mermaid') {
        if ($need -eq '```mermaid' -and $raw -match 'mermaid') { continue }
        if ($raw -notmatch [regex]::Escape($need)) { throw "bob-mrb-worker missing $need" }
    }
}
if ($raw -notmatch 'mermaid') { throw 'bob-mrb-worker mermaid missing' }
if ($raw -notmatch 'token-free' -and $raw -notmatch 'LLM') {
    throw 'worked example (LLM vs token-free) missing'
}
$pack = Get-Content -LiteralPath (Join-Path $RepoRoot 'docs\worker-pack-fr-mode.md') -Raw -Encoding UTF8
if ($pack -notmatch 'DRIFT' -and $pack -notmatch 'drift') { throw 'worker pack missing drift' }
$mrb = Get-Content -LiteralPath (Join-Path $RepoRoot 'docs\mrb.md') -Raw -Encoding UTF8
if ($mrb -notmatch 'vision' -or $mrb -notmatch 'drift') { throw 'docs/mrb.md missing vision/drift' }
$hostile = Get-Content -LiteralPath (Join-Path $RepoRoot '.grok\skills\bob-hostile-mrb\SKILL.md') -Raw -Encoding UTF8
if ($hostile -notmatch 'Vision / drift' -and $hostile -notmatch 'FR #351') {
    throw 'bob-hostile-mrb missing FR #351 pass/fail bar'
}
Write-Host 'PASS BT0 FR #351 mrb vision drift'
exit 0
