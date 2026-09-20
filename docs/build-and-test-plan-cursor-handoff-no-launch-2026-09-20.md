# Build and test plan: Cursor handoff no-launch contract (issue #12)

**Spec:** `docs/feature-request-cursor-handoff-no-launch-contract-2026-09-20.md`

## Changes

- `tools/Start-BobCursor.ps1`: `-NoLaunch`, `BOB_NO_AGENT_LAUNCH`, Fake-Grok / `Test-BobUsesFakeGrok` backstop; `startError=no_launch`.
- `src/Private/Invoke-BobFleet.ps1`: pass `-NoLaunch` under Fake-Grok; `invalid_kind` before claim.
- `src/Public/Start-BobBuild.ps1`: `invalid_kind` at enqueue.
- `src/Private/Test-BobGitKind.ps1`: shared kind validation.
- `tools/Test-Pack.ps1`: BT0q/BT0q2 use `-NoLaunch` + process count; BT0q3 invalid kind.

## Test

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Test-Pack.ps1
```

Expect PASS on BT0q, BT0q2, BT0q3 and no growth in Win32 `cursor-agent` process count during the pack.
