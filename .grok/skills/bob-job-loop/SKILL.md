---
name: bob-job-loop
description: >
  Hand off starting a git job and hostile MRB until PASS-nits: run
  Start-BobBuildLoop.ps1 and get notified on DONE. Retries failed
  cursor/grok jobs. FAIL spawns FIX. Does not stamp UAT. Use when the
  user says hand off the job, start and mrb until pass, retry failed
  cursor/grok jobs, run the program and notify on PASS-nits, or
  /bob-job-loop. Table: bob-build-loop. Bars: bob-hostile-mrb.
---

# Build / MRB until PASS-nits (one program)

Transaction table: `bob-build-loop`. Fuel and login: `cursor-mrb-dev` /
`start-bob-cursor`. Verdicts: `bob-hostile-mrb`.

The dispatcher does not sit in the MRB/FIX table. Launch the driver, then
stop. Do not poll `Get-BobBuild`. Do not retype `Start-BobMrbHandoff` or
`Start-BobBuild -Fix` unless the driver cannot start.

## Launch

FR + plan already parked (`bob-spec-intake`). Then:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Start-BobBuildLoop.ps1 `
  -Repo owner/repo -Issue <fr> -Cwd C:\ai\<repo> `
  -Docs docs/feature-request-....md -Plan docs/build-and-test-plan-....md
```

Skip `-Goal` unless the parked issue is not enough. Existing PR: pass
`-Sha <pr-head>` (and `-Pr <url>` if you have it) to start at MRB.

Call in-process (`& Start-BobBuildLoop.ps1 ...`) so `-Goal` is not split.
From this Grok session, wrap the same command in `monitor` so a single
stdout line wakes you.

Stdout is `DONE` / `FAILED` only. Diagnostics go to
`~\.grok\long-running-background-tasks\bob-build-loop-<owner>_<repo>-<issue>.log`.
Board: `Get-BobMrbBoard` / `$BOB_BRIDGE_HOME\loops\<owner>_<repo>-<issue>.json`.

## On wakeup

- `DONE: MRB PASS-nits ...` — tell the human the issue, SHA, and PR. Do
  not stamp ready for human UAT. Bob chairs that.
- `FAILED: ...` — read the loop log. Do not start a second loop on the
  same FR until the reason is fixed (gh auth, cwd, secrets in the goal).

## What the driver does

1. Start a **build** worker (`-Kind build`) if there is no tip SHA.
2. Wait for a PR. Cursor/grok job crash or no PR: retry (max 3 attempts
   per phase). Cursor start miss falls back to grok-build. Fuel is
   re-read each start.
3. Start a **new** MRB worker (`Start-BobMrbHandoff`, `-Kind mrb`). Never
   the implementer.
4. Wait for `MRB FAIL|PASS-nits: ... <sha>`. Job crash without that issue:
   retry the MRB job.
5. FAIL: do not merge. Read Required fixes. Start a FIX worker. Comment
   the new PR / next board on the prior FAIL issue.
6. PASS-nits: the MRB worker already merged. Print `DONE` and exit 0.

Never Other Models. Copilot only with `-AllowCopilot`. No MRB PDF. No
`password=` / `XAI_API_KEY=` assignments. Test-Pack seams: `-Once`
`-TestWorld` only.
