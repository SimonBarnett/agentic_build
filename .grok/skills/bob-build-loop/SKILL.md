---
name: bob-build-loop
description: >
  Orchestrate Bob functional-spec work: park feature requests as git issues +
  /docs markdown, write build/test plans, dispatch git-task workers, hostile
  MRB as GitHub issues until ready for human UAT. No MRB PDFs. Use when the
  user says MRB, ready for UAT, bob build loop, or /bob-build-loop. Cursor
  MRB/FIX until PASS-nits is cursor-mrb-dev.
---

# Bob functional-spec build loop

Bob orchestrates. Build agents implement. Prefer legion machines with spare Premium+ capacity (often `ionos`). Fuel: Cursor Models then Grok Build (`cursor-mrb-dev` for MRB/FIX until PASS-nits). Builders: `composer-2.5` or `build0.1` (else `grok-4.5`). MRB: latest reasoning (`claude-opus-5-thinking-high` / `grok-4.6`).

## When which skill

| Situation | Skill |
|---|---|
| Fresh functional spec / new product | `bob-spec-intake` then `bob-build-dispatch` |
| Feature-request on an existing repo | `bob-spec-intake` (issue + markdown) then `bob-build-dispatch` |
| New commits landed; need review | `bob-hostile-mrb` (hand off; Cursor loop `cursor-mrb-dev`) |
| Cursor MRB then FIX until PASS-nits | `cursor-mrb-dev` |
| Start/monitor/stop the Windows job | `grok-build-fleet` |
| Named Grok Bot (Bob) silent in chat | `unstick-grok-bot` |
| Live chat with a build agent on Ergo | `bob-irc` / `agentic-irc` |

## Loop (do not skip)

1. Park the feature request as a **GitHub issue** plus `docs/feature-request-*.md` (`bob-spec-intake`). Git is the source of truth.
2. Write / update `docs/build-and-test-plan.md` a build agent can execute.
3. `Start-BobBuild` (see `bob-build-dispatch` / `grok-build-fleet`).
4. On each pushed version: Bob **hands off** hostile MRB (`cursor-mrb-dev` / `bob-hostile-mrb`). Worker posts a **new** issue `MRB FAIL|PASS-nits: ... <sha>`. Missing features get parked as new `feature-request` issues. No MRB PDFs.
5. On FAIL, dispatch a **build** worker (`Start-BobCursor -Kind build` or grok-build), then re-MRB the new SHA. Repeat until **PASS-nits**. Only **Bob** stamps **ready for human UAT**.

## Hard rules

- New product repos: **public** under `SimonBarnett` unless Simon says otherwise.
- Feature work: **do not break** prior versions; use `v2/` / `v3/` (or next free version folder).
- Do not burn tokens implementing **or writing MRBs** in Bob. Cursor Models then Grok Build do the coding and the hostile review. Bob **hands off** (`Start-BobMrbHandoff.ps1`); only Bob stamps **ready for human UAT**. Copilot only with `-AllowCopilot`.
- Never put real `password=` or `XAI_API_KEY=` **assignments** in goals/constraints (`Test-PromptSecrets`). Instructional mentions of the names are OK.
- Feature requests and plans live in git (`/docs` markdown + GitHub issues). MRB is an issue, not a PDF.