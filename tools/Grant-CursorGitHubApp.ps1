# Open the Cursor GitHub App install so Simon can grant All repositories.
# A user OAuth token cannot add GitHub App installations (API 403).
# Skill: setup-github-cursor. Pair with bob-spec-intake New GitHub repo.
[CmdletBinding()]
param(
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
Write-Host 'Cursor Web pushes as cursor[bot], not your gh user.'
Write-Host 'Set Repository access = All repositories (Contents + Pull requests Read and write).'
Write-Host 'https://github.com/apps/cursor'
Write-Host 'https://cursor.com/dashboard  (Integrations -> reconnect GitHub)'
Write-Host ''
Write-Host 'Public SimonBarnett repos (human PRs already allowed; app grant is the 403 fix):'
gh repo list SimonBarnett --limit 200 --json name,isPrivate --jq '.[] | select(.isPrivate|not) | .name'
Write-Host ''
Write-Host 'Private (leave private):'
gh repo list SimonBarnett --limit 200 --json name,isPrivate --jq '.[] | select(.isPrivate) | .name'
if (-not $NoBrowser) {
    Start-Process 'https://github.com/apps/cursor/installations/new'
}
