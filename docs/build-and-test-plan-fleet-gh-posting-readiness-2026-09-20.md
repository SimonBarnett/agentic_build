# Build and test plan: fleet GitHub-posting readiness (issue #11)

**Feature request:** `docs/feature-request-fleet-gh-posting-readiness-2026-09-20.md`

## Build

1. `src/Private/Get-BobGh.ps1` — `Get-BobGhPostingReadiness`, `Install-BobGitHubCliIfMissing`, machine snapshot helpers.
2. `tools/Bob-Gh.ps1` — preflight uses shared probe (no token sniff).
3. `Register-BobMachine` / fleet heartbeat — persist `gh_posting` on `machine.json`.
4. `Get-BobHealth`, `Get-BobCapacity`, `Select-BobGitWorker -Kind mrb`, `Install-BobFleet`, tray / `box-usage` surfaces.
5. Skills `cursor-mrb-dev`, `grok-build-fleet` — token contract + remediation.

## Test (Off-DEV)

Run `tools/Test-Pack.ps1` (Fake-Grok + Fake-Gh). Cases **BT0y1**–**BT0y5** cover readiness absent/dead/ready, mrb picker gate, and Install reporting.

No live `gh`, no live agent, no secrets in git.
