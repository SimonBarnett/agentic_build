# Build and test plan: bob two persistent workers

**Date:** 2026-09-22  
**FR:** docs/feature-request-bob-two-persistent-workers-2026-09-22.md  
**Repo:** SimonBarnett/agentic_build

## Goals

1. Park + implement P0 so `bob-{machine}` can own a repo with two persistent workers (dev + MRB), webhook `working_on`, digest visible.
2. Keep existing one-shot loop working until the pair path is live (no break).

## Non-goals

- Human UAT stamp.
- Push/merge `main` from the implementer.
- Undo shop/fleet JOIN policy except as Simon already overrode (#107).

## Locked constants

| Name | Value |
|------|--------|
| Chair | `bob-{machine}` grok agent |
| Pair size | 2 workers per assigned repo |
| Idle stop | 5 minutes (U1 default) |
| Skills on spawn | build + IRC |
| Self-review | forbidden; other worker MRBs |
| Fuel | cursor-models while remaining > 0; never Other Models |

## Phase order

| Phase | Exit |
|-------|------|
| P0 | FR + this plan + issue; skill text for pair spawn + idle + webhook |
| P1 | Bob can spawn/reuse two workers for one repo; persist; idle-stop |
| P2 | Implementer/MRB split + next-PR handoff |
| P3 | Worker `working_on` POST; digest reads it |
| P4 | Bob reports digest states (dev complete / MRB complete) to #bobiverse |
| P5 | Channel description = assigned repo name; update on repo change |

## Tests

| ID | Check |
|----|--------|
| T0 | `tools/Test-Pack.ps1` still green |
| T1 | Docs/skill mention pair, idle, webhook, no self-MRB |
| T2 | Spawn does not enqueue two jobs that both implement the same SHA |
| T3 | Digest/webhook test or documented POST path for workers |

## Definition of done (first ticket / P0–P1)

- [ ] PR title includes the FR issue number
- [ ] T0 green
- [ ] Hostile MRB by the **other** worker; implementer does not merge
- [ ] No UAT stamp

## Kickoff (`Start-BobBuild -Goal`)

Read `docs/feature-request-bob-two-persistent-workers-2026-09-22.md` and this plan.
Implement P0 then P1 on a branch. Open a PR. Never push main. Never merge.
Do not stamp UAT. Do not assign API keys. PR model composer-2.5. Never Other Models.
