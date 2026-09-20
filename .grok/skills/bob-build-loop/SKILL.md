---
name: bob-build-loop
description: >
  Orchestrate Bob functional-spec work: park feature requests as git issues +
  /docs markdown, write build/test plans, dispatch Grok Builds, hostile MRB
  as GitHub issues until ready for human UAT. No MRB PDFs. Use when the user
  says MRB, ready for UAT, bob build loop, or /bob-build-loop.
---

# Bob functional-spec build loop

Bob orchestrates. Build agents implement. Prefer legion machines with spare Premium+ capacity (often `ionos`). Builders: `build0.1` when `grok models` lists it, else `grok-4.5`. MRB: latest reasoning (`grok-4.6` / `claude-opus-5-thinking-high`).

## When which skill

| Situation | Skill |
|---|---|
| Fresh functional spec / new product | `bob-spec-intake` then `bob-build-dispatch` |
| Feature-request on an existing repo | `bob-spec-intake` (issue + markdown) then `bob-build-dispatch` |
| New commits landed; need review | `bob-hostile-mrb` |
| Start/monitor/stop the Windows job | `grok-build-fleet` |
| Named Grok Bot (Bob) silent in chat | `unstick-grok-bot` |
| Live chat with a build agent on Libera | `agentic_irc` (separate repo) |

## Loop (do not skip)

1. Park the feature request as a **GitHub issue** plus `docs/feature-request-*.md` (`bob-spec-intake`). Git is the source of truth.
2. Write / update `docs/build-and-test-plan.md` a build agent can execute.
3. `Start-BobBuild` (see `bob-build-dispatch` / `grok-build-fleet`).
4. On each pushed version: Bob **hands off** hostile MRB (`tools/Start-BobMrbHandoff.ps1` / `bob-hostile-mrb`). Worker posts FAIL or PASS-nits on the feature-request issue. Missing features get parked as new `feature-request` issues. `Send-BobBuildSpec` with the **issue URL**. No MRB PDFs.
5. Repeat until **Bob** passes as **ready for human UAT**. Never claim UAT-ready earlier.

## Hard rules

- New product repos: **public** under `SimonBarnett` unless Simon says otherwise.
- Feature work: **do not break** prior versions; use `v2/` / `v3/` (or next free version folder).
- Do not burn tokens implementing **or writing MRBs** in Bob. Fleet / Copilot does the coding. Bob **hands off** hostile MRB (`Start-BobMrbHandoff.ps1`); only Bob stamps **ready for human UAT**.
- Never put real `password=` or `XAI_API_KEY=` **assignments** in goals/constraints (`Test-PromptSecrets`). Instructional mentions of the names are OK.
- Feature requests and plans live in git (`/docs` markdown + GitHub issues). MRB is an issue, not a PDF.