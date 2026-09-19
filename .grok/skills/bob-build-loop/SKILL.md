---
name: bob-build-loop
description: >
  Orchestrate Bob functional-spec work: park specs in /docs, write build/test
  plans, dispatch Grok Builds, hostile MRB PDFs until ready for human UAT.
  Use when the user or another agent sends a functional specification, feature-
  request PDF, says MRB, ready for UAT, bob build loop, or /bob-build-loop.
  Job queue mechanics are grok-build-fleet; named-bot hangs are unstick-grok-bot.
---

# Bob functional-spec build loop

Bob orchestrates. Build agents implement. Prefer legion machines with spare Premium+ capacity (often `ionos`). Prefer model `build0.1` when the CLI/packet supports it; otherwise note in constraints.

## When which skill

| Situation | Skill |
|---|---|
| Fresh functional spec / new product | `bob-spec-intake` then `bob-build-dispatch` |
| Feature-request PDF on an existing repo | `bob-spec-intake` (feature mode) then `bob-build-dispatch` |
| New commits landed; need review | `bob-hostile-mrb` |
| Start/monitor/stop the Windows job | `grok-build-fleet` |
| Named Grok Bot (Bob) silent in chat | `unstick-grok-bot` |
| Live chat with a build agent on Libera | `agentic_irc` (separate repo) |

## Loop (do not skip)

1. Park artefacts under `/docs` (PDF + markdown mirror).
2. Write / update `docs/build-and-test-plan.md` a build agent can execute.
3. `Start-BobBuild` (see `bob-build-dispatch` / `grok-build-fleet`).
4. On each pushed version: **hostile MRB** PDF into `/docs`, then `Send-BobBuildSpec` (or IRC) with the review URL.
5. Repeat until **Bob** passes as **ready for human UAT**. Never claim UAT-ready earlier.

## Hard rules

- New product repos: **public** under `SimonBarnett` unless Simon says otherwise.
- Feature work: **do not break** prior versions; use `v2/` / `v3/` (or next free version folder).
- Do not burn tokens implementing in Bob; fleet does the coding.
- Never put real `password=` or `XAI_API_KEY=` **assignments** in goals/constraints (`Test-PromptSecrets`). Instructional mentions of the names are OK.
- Specs, plans, and MRB PDFs always land in `/docs` and are committed/pushed.