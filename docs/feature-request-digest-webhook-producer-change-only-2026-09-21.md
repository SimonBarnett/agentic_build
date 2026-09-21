# Feature request: change-only webhook POST from Write-BobIrcStatus

**Date:** 2026-09-21  
**Repo:** https://github.com/SimonBarnett/agentic_build  
**GitHub issue:** https://github.com/SimonBarnett/agentic_build/issues/141  
**Raised by:** Simon (via agentic_irc #73 / Halloy `#bobiverse` status wall)  
**UAT + hostile MRB owner:** Bob  
**Sister (consumer):** https://github.com/SimonBarnett/agentic_irc/issues/73  
**Related:** #124 shop + `reportUrl` (different FR — do not fold this into #124)

## Problem

Watch still treats `#bobiverse` as a telemetry room. `Write-BobIrcStatus`
refreshes `bob-peers\<id>.json` every ~30s and, on named-field change, writes
English to `outbox.txt`. That is how Halloy sees `Working on ?.`,
`ionos is on Cursor Models now.`, and per-machine online/offline lines.

agentic_irc #73 moves **read** to a digest chair and **write** to
`POST /bob/v1/report` (change-only merge). This repo is the **producer**.
#124 is shop-channel attach + write-only `reportUrl`, not the delta-POST
contract.

## LOCKED

1. **No periodic fleet status on IRC.** No `BOB v1` POINT firehose. No
   repeating English online/offline / fuel lines on `#bobiverse` from Watch.
   No `BOB DIGEST` in `outbox.txt`.
2. **POST on change only.** Before POST, hash canonical peer blob vs last
   successful POST (or last `bob-peers\<id>.json` export). Skip when only
   `lastSeen` advanced. Include when present: `online`, `status`,
   `weekly` / `cursor_label`, `jobs`, `working_on`, `repo` / `sha` /
   `model` / `fuel` (and existing `pcent` buckets).
3. **`bobiverse.json`:** `chairNick` (e.g. `bob-chair`) and `chairHome`
   (or reuse ionos briefer home). Watch does **not** start the digest chair.
4. **Secrets:** `X-Bob-Secret` header only; never IRC; never
   `password=` / `XAI_API_KEY=` assignments in git.

## Gap vs current tree

| Area | Now | Want |
|------|-----|------|
| `Write-BobIrcStatus` | Disk peers + English `outbox` on field change | POST `reportUrl` on delta only; no channel status |
| `docs/bobiverse.md` | One English line to channel via outbox | Chair commands on IRC; webhook is the write path |
| `Install-BobIrc` / Watch | Briefer / builder starts; no chair seat | One-shot chair install if launched from this repo; Watch never starts chair |
| #124 | Shop JOIN + write-only report | Leave #124 as shop; this issue is change-only POST |

## MUST

1. Hash canonical peer blob; skip POST when only `lastSeen` advanced.
2. POST body matches consumer `docs/bob-report-callback-change-only.md`
   (`op=merge`, machine id, delta fields above).
3. Test-Pack fixture: two ticks same data → zero POST; fuel/`pcent` flip →
   one POST.
4. Watch / `bob-<machine>` builders do not append fleet English or
   `BOB DIGEST` to `outbox.txt`.

## MUST NOT

- Revive `!report` ingest.
- HTTP GET digest URL.
- Start digest chair from Watch.
- Require Halloy in Test-Pack.

## Acceptance

1. Two Watch ticks with idle fleet → POST count stays flat; no new
   `#bobiverse` outbox line.
2. One fuel / `pcent` / model change → one POST.
3. Off-DEV Test-Pack / Fake HTTP; no live Ergo in pack.

## Out of scope

- Consumer chair seat / `apply_callback` (agentic_irc #73).
- Tray card layout (#91 / #100).
- Shop worker JOIN (#124).
