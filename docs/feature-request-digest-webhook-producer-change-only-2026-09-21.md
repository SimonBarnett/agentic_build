# Feature request: change-only webhook POST from Write-BobIrcStatus

**Date:** 2026-09-21  
**Repo:** https://github.com/SimonBarnett/agentic_build  
**GitHub issue:** https://github.com/SimonBarnett/agentic_build/issues/141  
**Sister (chair):** https://github.com/SimonBarnett/agentic_irc/issues/73  
`docs/feature-request-digest-webhook-chair-change-only-2026-09-21.md`  
**Related:** #124 shop-channel `reportUrl` (not this contract), #142 tray DIGEST ingest  
**Raised by:** Simon (parked from agentic_irc MRB of `a0102b350157649d2d5673e71687058808e9e705`)  
**UAT + hostile MRB owner:** Bob  

## Problem

`Write-BobIrcStatus` refreshes **local** `bob-peers\<id>.json` and may emit
one English line on real field change. It does **not** POST the fleet
digest to ionos `reportUrl`. The chair `digest.json` therefore stays
presence-only (online / workers / `working_on`) unless some other path
fills weekly / jobs / sha / `cursor_pools`.

Sister #73: peers POST **on change only**; a dedicated chair answers
`!bobiverse`. `bob-ionos` is the ionos builder, not the fleet announcer.

## LOCKED

1. Watch / `Write-BobIrcStatus` POSTs fleet digest to ionos `reportUrl`
   **on change only**. Skip `lastSeen`-only ticks.
2. No periodic English / `BOB DIGEST` / POINT on `#bobiverse`.
3. `config/bobiverse.json` may gain `chairNick` / `chairHome`. Watch does
   **not** start the digest chair.
4. `Install-BobChair` one-shot lives here **only if** the consumer seat
   is launched from this repo. Do not turn Watch into the chair.
5. #124 is shop-channel `reportUrl` sister work, not this change-only
   contract. Do not conflate the two.
6. No secrets. No `password=` / `XAI_API_KEY=` assignments in git.

## Gap vs tree

| Current | Wanted |
|---|---|
| Local peer JSON + optional English on change | Same, **plus** change-only POST to `reportUrl` |
| Chair digest starved of tray fields | Chair `digest.json` receives weekly / jobs / sha / pools when they change |
| Watch might be mistaken for chair | Watch never starts the chair nick |

## Acceptance

1. Field change (model, kind, repo, sha, running/queued, weekly, hung) →
   one POST. `lastSeen`-only tick → no POST.
2. No POINT / `BOB DIGEST` channel firehose from this path.
3. Hermetic Test-Pack: fake `reportUrl`, assert change-only; no live Ergo.
4. PR only; Bob stamps UAT.

## Non-goals

- Implementing agentic_irc chair / `#142` ingest.
- Shop-channel #124 `reportUrl` contract.
- HTTP GET of digest.
- Starting the chair from Watch.
