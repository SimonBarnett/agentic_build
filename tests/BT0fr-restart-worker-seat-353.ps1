# FR #353: bob-restart-worker-seat skill + README link
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$skill = Join-Path $RepoRoot '.grok\skills\bob-restart-worker-seat\SKILL.md'
if (-not (Test-Path -LiteralPath $skill)) { throw 'missing bob-restart-worker-seat/SKILL.md' }
$raw = Get-Content -LiteralPath $skill -Raw -Encoding UTF8
if ($raw -notmatch '(?m)^name:\s*bob-restart-worker-seat') { throw 'skill frontmatter name' }
if ($raw -notmatch '```mermaid') { throw 'skill must include mermaid diagram' }
if ($raw -notmatch 'Slow' -or $raw -notmatch 'Hung' -or $raw -notmatch 'tokens' -or $raw -notmatch 'Mis-bound') {
    throw 'skill must classify slow / hung / tokens / mis-bound'
}
foreach ($ref in @('#97', '#345', '#346', '#352')) {
    if ($raw -notmatch [regex]::Escape($ref)) { throw "skill must reference $ref" }
}
$readme = Get-Content -LiteralPath (Join-Path $RepoRoot 'README.md') -Raw -Encoding UTF8
if ($readme -notmatch 'bob-restart-worker-seat') { throw 'README must link bob-restart-worker-seat' }
$pack = Get-Content -LiteralPath (Join-Path $RepoRoot 'docs\worker-pack-fr-mode.md') -Raw -Encoding UTF8
if ($pack -notmatch 'bob-restart-worker-seat') { throw 'worker pack must point at skill' }
Write-Host 'PASS BT0 FR #353 bob-restart-worker-seat'
exit 0
