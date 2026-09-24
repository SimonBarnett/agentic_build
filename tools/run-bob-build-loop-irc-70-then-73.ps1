# Run bob-job-loop for agentic_irc #70; on success start #73.
$ErrorActionPreference = 'Continue'
$runner = Join-Path $PSScriptRoot 'run-bob-build-loop.ps1'
$logRoot = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

$log70 = Join-Path $logRoot 'bob-build-loop-SimonBarnett_agentic_irc-70.log'
& $runner `
    -Repo 'SimonBarnett/agentic_irc' `
    -Issue 70 `
    -Cwd 'C:\ai\agentic_irc-i70' `
    -Docs 'docs/feature-request-ionos-shop-channel-bob-ionos-2026-09-21.md' `
    -Plan 'docs/build-and-test-plan-ionos-shop-channel-bob-ionos-2026-09-21.md' `
    -LogPath $log70
if ($LASTEXITCODE -ne 0) {
    Write-Output 'CHAIN: issue 70 loop FAILED; not starting 73'
    exit $LASTEXITCODE
}

$log73 = Join-Path $logRoot 'bob-build-loop-SimonBarnett_agentic_irc-73.log'
Write-Output 'CHAIN: issue 70 DONE; starting loop for issue 73'
& $runner `
    -Repo 'SimonBarnett/agentic_irc' `
    -Issue 73 `
    -Cwd 'C:\ai\agentic_irc-i73' `
    -Docs 'docs/feature-request-digest-webhook-chair-change-only-2026-09-21.md' `
    -Plan 'docs/build-and-test-plan-digest-webhook-chair-change-only-2026-09-21.md' `
    -LogPath $log73
exit $LASTEXITCODE
