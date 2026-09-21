# Feature request: harvest bob-job launchers + MRB remaining-FR new-worker rule

**Date:** 2026-09-21
**Repo:** https://github.com/SimonBarnett/agentic_build
**GitHub issue:** https://github.com/SimonBarnett/agentic_build/issues/109
**Raised by:** harvest (live bob-job loops)
**UAT + hostile MRB owner:** Bob
**Related:** issue #107 (`docs/feature-request-harvest-bob-job-dispatcher-2026-09-21.md` on `docs/park-harvest-bob-job-dispatcher`), `docs/feature-request-mrb-loop-automation-2026-09-20.md` (issues #9 / #31), skill `bob-job-loop`, `docs/skill-harvest-log.md`

Parked after the harvest issue existed with no `docs/feature-request-*.md`. Spec was pointed at PR #108. This markdown is the intake doc.

## Gap vs current tree

`Start-BobBuildLoop.ps1` already drives one FR to PASS-nits. Fleet loops still lacked:

1. **Launchers.** No `tools/run-bob-build-loop.ps1` / `tools/start-bob-build-loop-issue.ps1`. Dispatchers retyped `GH_TOKEN` from interactive `git credential fill`, which fails when `gh` is the helper.
2. **Remaining FRs.** After one FR's PASS-nits, open `feature-request` issues (and Missing-features parks) sat idle. Skills told the dispatcher to stop at one DONE.
3. **New-worker rule incomplete.** FAIL already spawned FIX. Remaining open FRs did not get a new worker.

## Ask

1. Add `tools/run-bob-build-loop.ps1` and `tools/start-bob-build-loop-issue.ps1`: set `GH_TOKEN` from credential-manager first, then fill; call `Start-BobBuildLoop.ps1`; stdout `DONE` / `FAILED` only. No secret literals in git.
2. Skills `bob-job-loop`, `bob-hostile-mrb`, `bob-build-loop`, `cursor-mrb-dev`: pass to a **new** worker on MRB FAIL **or** when any open `feature-request` / Missing-features issues remain after this FR's PASS-nits.
3. Unique `-LogPath` per loop. Isolated worktree per FR. Existing open PR: pin `-Sha` / `-Pr` and start at MRB.
4. Worker still cannot emit `PASS-UAT`. Driver does not stamp UAT. Bob chairs that.

## Acceptance

1. Both launchers exist and parse. They prefer credential-manager over interactive fill. No secret values committed.
2. Skills name the remaining-FR new-worker rule. Home: `bob-job-loop` / `bob-hostile-mrb`. Pointer `bob-build-loop` and `cursor-mrb-dev` point at it.
3. Default / documented `LogPath` includes repo + issue. Launchers accept `-Sha` / `-Pr`.
4. No `PASS-UAT` from worker or driver.

## Non-goals

- Changing FAIL / PASS-nits bars (`bob-hostile-mrb`).
- Stamping UAT.
- Implementing other open FRs (#107 dispatcher playbook leftovers, #9, #89, #91, #11, …).
- Auto-spawning remaining-FR workers inside `Start-BobBuildLoop.ps1` (dispatcher launches a new loop per leftover FR).
- Any MRB PDF.
