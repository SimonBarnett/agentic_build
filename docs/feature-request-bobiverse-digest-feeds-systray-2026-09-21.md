# Feature request: ingest tray-complete `!bobiverse` into systray peers

**Date:** 2026-09-21  
**Repo:** https://github.com/SimonBarnett/agentic_build  
**Sister (protocol):** https://github.com/SimonBarnett/agentic_irc  
`docs/feature-request-bobiverse-digest-feeds-systray-2026-09-21.md`  
**Related:** #26 channel-talk + tray pull, #91 cursor pools, irc #36  
**Raised by:** Simon (2026-09-21 ~23:17 BST)  
**UAT + hostile MRB owner:** Bob  

## Problem

Simon: **a bob has to be able to `!bobiverse` and see all the information
required for the Bob systray.**

Watch already polls `!bobiverse` (~120s) and calls `Import-BobIrcTrayPull`,
but that importer only accepts `BOB TRAY v1` kv lines. Chair whispers today
are mostly `BOB DIGEST v1` presence JSON (online / workers / working_on).
Tray fields (`weekly`, `period_end`, `cursor_label`, job repo/sha/model)
stay local-only via `Write-BobIrcStatus`, so peer boxes cannot paint a full
card from IRC alone.

## LOCKED

1. After a bob-* `!bobiverse` pull, `bob-peers\<id>.json` for each registry
   machine must hold everything `Get-BobTrayHover` needs for that tile +
   Cursor pool bars (see sister FR field list).
2. Prefer extending `Import-BobIrcTrayPull` (and/or a DIGEST→peers path) so
   one poll fills peers; do not revive POINT spam.
3. Job lines: never publish `?` when digest/tray line has repo/sha.
4. Test-Pack hermetic: fake whisper → peers → hover bars/jobs; no live Ergo.
5. Skill `bob-fleet-tray` documents: tray freshness = `!bobiverse` pull,
   not POINT.

## Gap vs tree

| Current | Wanted |
|---|---|
| `Import-BobIrcTrayPull` = `BOB TRAY v1` only | Also DIGEST JSON → peers **or** chair emits TRAY lines for every id |
| Local status rich; pull poor | Pull = tray-complete |
| #91 pools / #26 pull partially parked | This FR is the **bob can paint from !bobiverse** lock |

## Acceptance

1. Fake chair whisper in Test-Pack updates all four machine peer files with
   weekly + cursor + jobs.
2. `Get-BobTrayHover` on that fixture shows seat bars + non-`?` job line.
3. Live: recycle Watch only; bob `!bobiverse` refreshes tray without POINT.
4. PR only; Bob stamps UAT.

## Non-goals

- `Install-BobFleet` / scheduled-task churn.
- HTTP GET digest.
