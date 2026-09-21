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

**FR order:** one FR until MRB **PASS-nits**; then the next in receive order
(user sequence or lowest open `feature-request` #). No parallel FR loops on the
same repo. Home: `bob-job-loop`.

**New worker rule (MRB):** pass to a **new** worker on MRB **FAIL** (FIX).
After PASS-nits, hand off **only the next** queued FR. Home: `bob-job-loop` /
`bob-hostile-mrb`.

**GitHub hygiene:** `Close-BobMrbPassedIssues.ps1`,
`Close-BobSupersededGithub.ps1`, `Merge-BobMrbPassOpenPrs.ps1` — see
`bob-job-loop` (keep PR/issue lists current; protect active loop PRs).
