# Build and test plan: automated gate and module surface (issue #15)

**Date:** 2026-09-20
**Repo:** https://github.com/SimonBarnett/agentic_build
**Issue:** https://github.com/SimonBarnett/agentic_build/issues/15
**Spec:** `docs/feature-request-automated-gate-and-module-surface-2026-09-20.md`
**Chair:** Bob (hostile MRB on #15). Builder opens PR; Bob merges after PASS-nits.

## 0. Guardrails

- Offline only in CI: no live `gh`, agents, fleet share, or quota spend.
- No secrets in repo, workflow, or job packets.
- Do not mark ready for human UAT on the PR.
- Never push `main` from the worker branch.

## 1. Implement

1. `.github/workflows/test-pack.yml` on `windows-latest`: install PSScriptAnalyzer, run `tools/Test-Pack.ps1` on push to `main` and on pull requests.
2. `Test-Pack.ps1`: dirty-checkout banner; repo-source reads via `git show HEAD:`; BT0p tools→BobBridge export surface; BT0q PSScriptAnalyzer + gate empty-catch scan.
3. Export `Format-BobCursorAccountLabel` and `Resolve-BobiverseMachineId` on `FunctionsToExport` so tray tools stay on the public surface.

## 2. Test (local + CI)

```powershell
cd C:\ai\agentic_build
Install-Module PSScriptAnalyzer -Force -Scope CurrentUser -MinimumVersion 1.21.0
.\tools\Test-Pack.ps1
```

Expect: all BT0* pass including `BT0p tools bobbridge surface` and `BT0q psscriptanalyzer gate lint`.

### Gate evidence (not left on main)

Before opening the PR, temporarily add `throw 'gate probe'` to any BT0 case, push, confirm the GitHub check fails, then revert. Do not commit the probe.

### Dirty checkout

With a modified tracked file, re-run Test-Pack: banner lists dirty paths; pass/fail counts match a clean worktree at the same SHA.

## 3. PR

- Branch: `work/issue-15-automated-gate-module-surface`
- Title references issue #15
- Body links spec, plan, and issue; states Bob chairs MRB
- Push branch only; open PR; do not merge
