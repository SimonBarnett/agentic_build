---
name: bob-build-loop
description: >
  Pointer skill only: use bob-spec-intake, bob-build-dispatch, bob-job-loop,
  bob-hostile-mrb / cursor-mrb-dev / bob-mrb-worker, and grok-build-fleet for
  the PR/MRB loop. Do not load this skill expecting a separate orchestration
  ritual.
github: https://github.com/SimonBarnett/agentic_build
---

# Bob build loop (pointer)

Foundation: `harvest-agent-skills` (honesty box) -> report back to
https://github.com/SimonBarnett/agentic_build.

This skill does **not** define its own workflow. Use the map in `README.md`:

| Situation | Skill |
|---|---|
| Park FR + `/docs` | `bob-spec-intake` |
| Build-and-test plan + enqueue worker | `bob-build-dispatch` |
| Run until MRB PASS (`Start-BobBuildLoop.ps1`) | `bob-job-loop` |
| Hand off hostile MRB / board posting | `bob-hostile-mrb` or `cursor-mrb-dev` |
| **STANDARD MRB worker process** (tests-first, PASS merge, one fix PR) | `bob-mrb-worker` |
| Start/monitor fleet jobs, heal watcher | `grok-build-fleet` |

Hard rules (unchanged): workers open PRs; never push `main`; never merge your
own implementer PR; PASS merge is the MRB agent; FAIL → exactly one fix PR
then merge both (`bob-mrb-worker`); only Bob stamps ready for human UAT.

**New worker rule:** pass to a **new** worker when any open actionable /
`feature-request` issues remain after PASS / Missing features park. Home:
`bob-job-loop` / `bob-hostile-mrb`. FAIL fix is **not** a separate FIX-worker
chain — it is one fix PR on the MRB seat (`bob-mrb-worker`).
