---
name: bob-build-dispatch
description: >
  Write a build-and-test plan under /docs and Start-BobBuild on a legion machine.
  Use when the user says start the build agent, dispatch build, build0.1, kick
  the parked spec, or /bob-build-dispatch. Requires docs already parked (see
  bob-spec-intake). Job polling is grok-build-fleet.
---

# Build plan + dispatch

## 1. Build-and-test plan

Write `docs/build-and-test-plan.md` in the target repo (commit + push) that a build agent can execute without more questions:

- Goals / non-goals
- Phase order with exit criteria
- Suggested tree / commands
- Locked config constants
- Test IDs and CI rules
- Definition of done for the first ticket
- Kickoff prompt block for `Start-BobBuild -Goal`

## 2. Choose machine (or let the picker)

Git tasks: `Start-BobBuild -Task git` with **optional** `-Machine` / `-Fuel`.
Default is `Select-BobGitWorker` (capacity pair, not a nick called cursor).
Fuel order: `cursor-models` -> `grok-build` (`-AllowCopilot` adds copilot).
Override remains: `-Machine flamingo -Fuel grok-build` for formprep / MSSQL.
`-Fix` re-runs the picker. **Builders** use `build0.1` when grok.exe
lists it, else `grok-4.5` (`models.buildGrokFallback`); Cursor
`composer-2.5`. **MRB** uses the latest reasoning model
(`grok-4.6` / `claude-opus-5-thinking-high`). Cursor MRB/FIX until
PASS-nits: `cursor-mrb-dev`.

Ids: `ionos`, `marchhare`, `dev1`, `flamingo` — not hostnames. DUMB / 2012
is not a git worker.

Load BobBridge from the local agentic_build clone (`C:\ai\agentic_build`, `D:\ai\agentic_build`, or `C:\src\agentic_build`). Run `Get-BobHealth` / `Get-BobMachines` / `Get-BobCapacity`. Heal a dead watcher via `grok-build-fleet`.

## 3. Start-BobBuild

Point `-Cwd` at the **product** repo checkout on that machine (clone first if needed).

Goal should tell the build agent to read `docs/functional-spec.md` and `docs/build-and-test-plan.md`, implement the first ticket/phases, commit and push, and paste the test summary.

Constraints (examples):

- Do not invent APIs or procedure names the spec forbids
- Do not put password= or API key **assignments** in prompts or commits
- Build workers: `build0.1` if `grok models` has it, else `grok-4.5` (or Cursor `composer-2.5`). Do not use the MRB reasoning model for implementation.
- Keep prior version folders intact on feature work

`ReplyChannel` is usually `Bob`. Profile is usually `generic` (use `formprep` only for Priority Form Prep on DEV).

Prefer instructional wording for secrets ("do not set an API key environment variable"). Never paste `XAI_API_KEY=...` values. Bare name mentions are OK.

## 4. After dispatch

- Tell the human `jobId` + machine.
- Poll `Get-BobBuild` / reply_channel pings (see `grok-build-fleet`).
- On successful push from the build agent, run `bob-hostile-mrb` (GitHub issue, not a PDF).

## Long jobs

Product builds often exceed a few minutes. Rely on Watch-BobAgents for unning_orphan / inbox_stale / gent_stall. Do not Stop-BobBuild solely because wall time feels long while the worker process is alive. Prefer profiles.generic.timeoutSec >= 7200 on legion boxes.