# Build and test plan: IRC TSR + Cursor listen watchdog (issue #163)

**Date:** 2026-09-22  
**Repo:** https://github.com/SimonBarnett/agentic_build  
**Issue:** https://github.com/SimonBarnett/agentic_build/issues/163  
**Spec:** `docs/feature-request-watch-irc-tsr-cursor-listen-2026-09-22.md`  
**Chair:** Bob (hostile MRB on #163). Builder opens PR; never push `main`; never merge.

## Goals

- `Start-IrcTsr.ps1` / `Irc-Tsr-Runner.ps1` run `irc_listen.py`, append `PROCESS_HEARTBEAT` to `irc-tsr-*-wake.jsonl` on start and every 30s while listen is alive, and emit `AGENT_LOOP_WAKE_irc-tsr` on `FROM` lines.
- `Watch-IrcTsr.ps1` restarts TSR when runner/listen child is gone, runner age exceeds cap, or **process** wake heartbeat is stale.
- Idle `#bobiverse` must not recycle: silence gate uses wake file mtime only (not `irc.log` mtime; missing wake is not stale until heartbeat is written).
- `Watch-CursorIrc.ps1` keeps `cursor-<machine-id>` `irc_agent` + TSR up; `Watch-Bobiverse.ps1` stays dumb.
- `Install-BobFleet` registers `_Watch-IrcTsr-<id>` and `_Watch-CursorIrc-<id>` (AtLogOn + demand start).
- Off-DEV Test-Pack only; no live Ergo; no secret assignments in git.

## Implementation

1. Add `tools/Irc-Tsr-Health.ps1` (wake stale + runner core matrix for tests).
2. Add TSR runner/start/watch scripts and `_Watch-*` wrappers (per-machine ionos copies set `BOB_MACHINE_ID`).
3. Extend `tools/Install-BobFleet.ps1` for IRC TSR and Cursor IRC scheduled tasks.
4. Test-Pack `BT0irtsr*` cases for wake matrix, install wiring, and Watch-Bobiverse isolation.

## Tests (off-DEV)

| ID | Case | Acceptance |
|---|---|---|
| BT0irtsr1 | wake silence matrix | AC2/AC3 healthy vs stale wake; idle irc.log does not affect wake-only gate |
| BT0irtsr2 | runner core matrix | AC2 dead runner / missing listen / age cap |
| BT0irtsr3 | install + bobiverse | AC1 wiring; Watch-Bobiverse unchanged |

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Test-Pack.ps1
```
