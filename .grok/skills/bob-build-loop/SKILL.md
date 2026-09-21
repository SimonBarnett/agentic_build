---
name: bob-build-loop
description: >
  Pointer skill only: use bob-spec-intake, bob-build-dispatch, bob-job-loop,
  bob-hostile-mrb / cursor-mrb-dev, and grok-build-fleet for the PR/MRB loop.
  Do not load this skill expecting a separate orchestration ritual.
---

# Bob build loop (pointer)

This skill does **not** define its own workflow. Use the map in `README.md`:

| Situation | Skill |
|---|---|
| Park FR + `/docs` | `bob-spec-intake` |
| Build-and-test plan + enqueue worker | `bob-build-dispatch` |
| Run until MRB PASS-nits (`Start-BobBuildLoop.ps1`) | `bob-job-loop` |
| Hand off hostile MRB / FIX | `bob-hostile-mrb` or `cursor-mrb-dev` |
| Start/monitor fleet jobs, heal watcher | `grok-build-fleet` |

Hard rules (unchanged): workers open PRs; never push `main`; never merge your
own PR; PASS-nits merge is enforced by `Start-BobMrb.ps1 -PrUrl` (and the loop
finish merges again if the agent skipped it); only Bob stamps ready for human UAT.

**New worker rule (MRB):** pass to a **new** worker when MRB **FAIL** (FIX),
**or** when any open `feature-request` issues remain after PASS-nits /
Missing features park. Home: `bob-job-loop` / `bob-hostile-mrb`.
