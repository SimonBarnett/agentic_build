---
name: bob-job-loop
description: >
  Hand off starting a git job and hostile MRB until PASS-nits: run
  Start-BobBuildLoop.ps1 (or tools/run-bob-build-loop.ps1) and get notified
  on DONE. Retries failed cursor/grok jobs. FAIL spawns FIX. After PASS-nits,
  hand remaining open feature-request issues to new workers. Does not stamp
  UAT. Use when the user says hand off the job, bob job, bob job FRs, start
  and mrb until pass, retry failed cursor/grok jobs, run the program and
  notify on PASS-nits, or /bob-job-loop. Table: bob-build-loop. Bars:
  bob-hostile-mrb.
---

# Build / MRB until PASS-nits (one program)

Transaction table: `bob-build-loop`. Fuel and login: `cursor-mrb-dev` /
`start-bob-cursor`. Verdicts: `bob-hostile-mrb`.

The dispatcher does not sit in the MRB/FIX table. Launch the driver, then
stop. Do not poll `Get-BobBuild`. Do not retype `Start-BobMrbHandoff` or
`Start-BobBuild -Fix` unless the driver cannot start.

## Launch (Grok session)

FR + plan already parked (`bob-spec-intake`). Prefer isolated worktree per
FR. Unique `-LogPath` per loop (two loops must not share one log file).

```powershell
# Prefer the wrapper (GH_TOKEN via credential-manager; fill often fails):
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\run-bob-build-loop.ps1 `
  -Repo owner/repo -Issue <fr> -Cwd C:\ai\<repo>-i<fr> `
  -Docs docs/feature-request-....md -Plan docs/build-and-test-plan-....md `
  -LogPath $env:USERPROFILE\.grok\long-running-background-tasks\bob-build-loop-owner_repo-<fr>.log
```

Or `tools/start-bob-build-loop-issue.ps1` (same GCM token path). Or call
`Start-BobBuildLoop.ps1` in-process with `$env:GH_TOKEN` already set.

Skip `-Goal` unless the parked issue is not enough. Existing PR: pass
`-Sha <pr-head>` and `-Pr <url>` to start at MRB.

From this Grok session, wrap the launch in `monitor` so a single stdout
line wakes you. Stdout is `DONE` / `FAILED` only.

Board: `$BOB_BRIDGE_HOME\loops\<owner>_<repo>-<issue>.json`
(default `~\.grok\bob-bridge\loops\`).

## Dispatcher hard rules

1. One FR, one loop board, one isolated cwd/worktree.
2. Unique `LogPath` / default log name includes repo + issue.
3. `GH_TOKEN`: GCM / `git credential-manager get` first; do not rely on
   interactive `git credential fill` (often fails when `gh` is the helper).
4. Existing open PR for that FR (or its `priorMrbIssue` FAIL board): pin
   `-Sha`/`-Pr` and start at MRB. Do not spawn another build that ignores
   the open PR.
5. Title match accepts `#<issue>` and `#<priorMrbIssue>` (FIX PRs often
   say `Fix issue #21` while the FR is `#2`).
6. Never the implementer for MRB. New job, `-Kind mrb`.
7. On `FAILED: PR worker exited without a PR`: list open PRs; if a matching
   PR exists (or a local branch with the work), push if needed, re-pin the
   board to `idle`/`wait_mrb` with `-Sha`/`-Pr`, and relaunch. Do not burn
   three more blind builds first.
8. **Pass to a new worker when MRB FAIL** (FIX with Required fixes) **or
   when any open `feature-request` issues remain** after this FR's
   PASS-nits / Missing features park. Do not stop at one FR DONE while
   open FRs sit idle. Skip boards already `phase=pass` and superseded
   issues.

## On wakeup

- `DONE: MRB PASS-nits ...` — tell the human the issue, SHA, and PR. Do
  not stamp ready for human UAT. Bob chairs that. Then list open
  `feature-request` issues on that repo; for each not already PASS and
  not superseded, launch a new `bob-job-loop` (isolated worktree + unique
  log). Also launch any issues the MRB just parked under Missing features.
- `FAILED: ...` — read the loop log. Fix the reason (auth, cwd, missed PR,
  secrets in the goal), then relaunch. Do not start a second loop on the
  same FR while one is still alive.

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
