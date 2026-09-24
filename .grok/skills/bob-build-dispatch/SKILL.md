---
name: bob-build-dispatch
description: >
  Write a build-and-test plan under /docs and Start-BobBuild on a legion machine.
  Use when the user says start the build agent, dispatch build, build0.1, kick
  the parked spec, or /bob-build-dispatch. Requires docs already parked (see
  bob-spec-intake). Job polling is grok-build-fleet.
github: https://github.com/SimonBarnett/agentic_build
---

# Build plan + dispatch

Foundation: `harvest-agent-skills` (honesty box) -> report back to
https://github.com/SimonBarnett/agentic_build.

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
Fuel order: Cursor Models remaining > 0 -> `cursor-models`, else
`grok-build` (`-AllowCopilot` adds copilot). Override remains:
`-Machine flamingo -Fuel grok-build` for formprep / MSSQL. `-Fix`
re-runs the picker. **PR workers** use Cursor Composer `composer-2.5`
or `build0.1` when grok.exe lists it, else `grok-4.5`. **MRB** uses
Cursor Grok `grok-4.6` (cursor-agent) or grok.exe `grok-4.6`. Never
Other Models. Transaction: `bob-build-loop`. Handoff: `cursor-mrb-dev`.
STANDARD MRB worker process: `bob-mrb-worker`.

Ids: `ionos`, `marchhare`, `dev1`, `flamingo` — not hostnames. DUMB / 2012
is not a git worker.

Load BobBridge from the local agentic_build clone (`C:\\ai\\agentic_build`, `D:\\ai\\agentic_build`, or `C:\\src\\agentic_build`). Run `Get-BobHealth` / `Get-BobMachines` / `Get-BobCapacity`. Heal a dead watcher via `grok-build-fleet`.

## 3. Start-BobBuild

Point `-Cwd` at the **product** repo checkout on that machine (clone first if needed).

Goal should tell the build agent to read `docs/functional-spec.md` and `docs/build-and-test-plan.md`, implement the first ticket/phases, **open a PR**, and paste the test summary. Never push `main`. Never merge.

Constraints (examples):

- Do not invent APIs or procedure names the spec forbids
- Do not put password= or API key **assignments** in prompts or commits
- PR workers: Composer `composer-2.5`, or `build0.1` if `grok models` has it, else `grok-4.5`. Do not use Other Models.
- Keep prior version folders intact on feature work
- Success = PR URL, not a push to main

`ReplyChannel` is usually `Bob`. Profile is usually `generic` (use `formprep` only for Priority Form Prep on DEV).

Prefer instructional wording for secrets ("do not set an API key environment variable"). Never paste `XAI_API_KEY=...` values. Bare name mentions are OK.

## 4. After dispatch

- Tell the human `jobId` + machine.
- Poll `Get-BobBuild` / reply_channel pings (see `grok-build-fleet`).
- On the worker PR, run `bob-job-loop` (`Start-BobBuildLoop.ps1`) so MRB
  follows `bob-mrb-worker` until PASS merge (GitHub issue, not a PDF).
  Single-SHA handoff: `bob-hostile-mrb` / `cursor-mrb-dev`. Worker STANDARD:
  `bob-mrb-worker` (PASS merge; FAIL one fix PR then merge both).

## Long jobs

Product builds often exceed a few minutes. Rely on Watch-BobAgents for
running_orphan / inbox_stale / agent_stall. Do not Stop-BobBuild solely because wall time feels long while the worker process is alive. Prefer profiles.generic.timeoutSec >= 7200 on legion boxes.
