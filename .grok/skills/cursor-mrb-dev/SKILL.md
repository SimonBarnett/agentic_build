---
name: cursor-mrb-dev
description: >
  Hand off hostile MRB then FIX until PASS-nits: Cursor Models while remaining
  > 0, else grok.exe. Workers open PRs. PASS-nits merges. Every FAIL spawns a
  FIX worker. Use when the user says cursor mrb, mrb until pass, cursor
  builder, re-mrb, mrb/dev loop, or /cursor-mrb-dev. Launch: start-bob-cursor.
  Verdicts: bob-hostile-mrb. Table: bob-build-loop. Bob stamps UAT.
---

# MRB / FIX until PASS-nits

Transaction table and mermaid: `bob-build-loop`. Bob does not write the MRB
or the code. Hand off, watch GitHub, dispatch the next row.

## Fuel (no judgment)

`Select-BobGitWorker` / default `-Fuel cursor-models`.

- Cursor Models remaining > 0: Cursor Agent. MRB = Cursor Grok
  (`models.mrbCursor` = `grok-4.6`). PR = Composer (`composer-2.5`).
- Remaining = 0, or cursor-agent not logged in: grok.exe. MRB = `grok-4.6`.
  PR = `build0.1` if listed, else `grok-4.5`.
- Never Other Models. Copilot only with `-AllowCopilot`.

Show remaining: `box-usage` / tray top bar. Catalog mapping:
`Resolve-BobGrokCliModel`.

## Login

`start-bob-cursor`: `cursor-agent status` must be logged in. Never
`~\.grok\bin\agent.exe` (that is grok). If Cursor is not logged in,
`Start-BobMrbHandoff` falls back to grok-build.

## GitHub posting (preflight)

Before `Start-BobMrbHandoff` starts an agent, the **worker box** must post
issues and merge PRs. `Get-BobGhPostingReadiness` probes live auth (not just
env presence): `gh.exe` present, `gh auth status` OK, and `gh repo view`
on the product repo (`SimonBarnett/agentic_build` or `BOB_PRODUCT_REPO`).

### Token contract (unattended fleet boxes)

| Item | Rule |
|---|---|
| Env var | `GH_TOKEN` preferred; `GITHUB_TOKEN` also honored by `gh` |
| Scopes | `issues:write` and `pull_requests:write` on the product repo (classic PAT or fine-grained repo access) |
| Where it lives | **User-level** Windows env or Credential Manager from interactive `gh auth login` — never git, job packets, or prompts |
| Rotation | Regenerate the PAT on GitHub, update the user env (or re-run `gh auth login`), then `Install-BobFleet` / `Get-BobHealth` should show `gh_posting.issue_posting_ready=true` |
| Probe | `Get-BobHealth.gh_posting`, `Get-BobCapacity.machines[].gh_posting`, tray `Get-BobTrayHover.gh_posting` |

Remediation when preflight fails: `winget install GitHub.cli` (or
`Install-BobFleet`), then set `GH_TOKEN` or `gh auth login`. See
`Get-BobGhExe` / `tools/Bob-Gh.ps1`. When `BOB_GH_EXE` is set to a path that
does not exist, `Get-BobGhExe` returns `$null` (it does not fall through to a
system `gh.exe`). Off-DEV Test-Pack points `BOB_GH_EXE` at
`tests/fixtures/Fake-Gh.ps1`.

`Select-BobGitWorker -Kind mrb` skips machines with
`gh_posting.issue_posting_ready=false`. Grok-build fallback still runs on the
**dispatcher** box until the remote worker is verified (issue #11 handoff
checks).

If preflight fails, fix auth first. Do not start the MRB agent.

### Test-Pack-only seams on `Start-BobMrbHandoff.ps1`

`-TestSkipCursor` and `-TestGitWorkerResult` exist only for `tools/Test-Pack.ps1`.
`-TestSkipCursor` requires `-Fuel grok-build` and `-TestGitWorkerResult`. Do not
use them in live MRB dispatch.

Workers post via `tools/Start-BobMrb.ps1` (creates missing `mrb` /
`mrb-pass` / `mrb-fail` labels).

## Loop

1. Tip = the **open PR** head SHA (or named SHA). Unrelated dirty files are
   out of scope.
2. **MRB:** as soon as the PR URL exists, `tools/Start-BobMrbHandoff.ps1
   -Repo owner/repo -Issue <fr> -Sha <pr-head> -Cwd <clone>
   -Fuel cursor-models`. That starts a **new** agent (`-Kind mrb`, Cursor
   Grok). Do not ask the implementer to review their own PR. Do not resume
   the Composer/`-Kind build` session. Isolated cwd/worktree. Wait for a
   **new** GitHub issue `MRB FAIL|PASS-nits: ... <sha>` (labels `mrb` +
   `mrb-fail` or `mrb-pass`). Prior FAIL issue is history.
3. **FAIL:** do not merge. Immediately
   `Start-BobBuild -Task git -Fix -Kind build -Mrb <new-mrb-issue>`
   (or `Start-BobCursor.ps1 -Kind build` when fuel is still cursor-models).
   Goal = Required fixes only. Worker opens a **new** PR. Comment the PR
   URL on the FAIL issue.
4. Repeat step 2 on the new PR until **PASS-nits**.
5. **PASS-nits:** the MRB worker merges that PR. Nits stay on the issue.
6. Only **Bob** stamps **ready for human UAT**.

Launch: `start-bob-cursor`. Bars: `bob-hostile-mrb`.

## Watch

Watch the **GitHub issue and PR**, not the redirected `.log`. Confirm
`node.exe --model grok-4.6` (MRB) or `--model composer-2.5` (PR) when fuel
is cursor-models.

## Hard

- No MRB PDFs.
- No `password=` / `XAI_API_KEY=` assignments.
- Do not burn Grok Bot weekly when Cursor Models or grok.exe can take it.
