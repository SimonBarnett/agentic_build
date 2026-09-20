# Bobiverse (MODE2 moot on `#bobiverse`)

Fleet machines do **not** SMB-peek each other. Flamingo and MarchHare sit on bobnet copper; ionos is a VPS; DEV1 is the customer Azure box. Status rides a private Ergo on ionos (`irc.ntsa.uk:6697` TLS), not Libera. See `docs/bobiverse-ionos-ircd.md`.

## Channel

| | |
|---|---|
| Channel | `#bobiverse` |
| Mode | MODE2 moot, `free` (every builder may POINT) |
| Moot id | `b0b1be15e0000001` |
| Transport | `MOOT v1 POINT` trailing text `BOB v1 …` (clear; not a secret) on `irc.ntsa.uk:6697` |

Nicks (one builder agent per machine):

| Machine id | Nick |
|---|---|
| flamingo | `bob-flamingo` |
| marchhare | `bob-marchhare` |
| ionos | `bob-ionos` |
| ce-priority-dev1 | `bob-dev1` |

Home on each box: `~\.agentic-irc-bobiverse` (not the Club Madeira `#cm-bob-oscar` homes).

## Status line

```
MOOT v1 POINT b0b1be15e0000001 :BOB v1 id=flamingo weekly=96 running=0 queued=0 lastSeen=2026-09-20T08:31:16Z jobs=-
```

`jobs` is `-` or `owner/repo:state,...`. Weekly remaining is **that machine's** Grok seat. No SQL passwords, no `XAI_API_KEY`.

Parked: quieter conversational talk (one field per message, only when it changes; join briefing as a DM). See `docs/feature-request-bobiverse-quiet-talk-2026-09-20.md`. Protocol work also belongs on `SimonBarnett/agentic_irc`.

`irc_agent.py` writes `~\.agentic-irc-bobiverse\bob-peers\<id>.json`. The tray paints **one weekly bar per registered `nicks` machine** from that POINT. Ghost IRC ids (`marchhare-bugets`, raw nicks) are dropped. `reach=irc-fallback` for those four seats (prefer over `not in moot`). `not in moot` (not `unreachable`) only for an id that is not a bobiverse seat. The card has an **X** to close.

## Install (each build box)

Python 3.12+ plus `pip install -r C:\ai\agentic_irc\requirements.txt`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Install-BobIrc.ps1 -MachineId flamingo -Chair
# other boxes: omit -Chair (JOIN)
```

`Install-BobIrc.ps1` is **one-shot** (genkey, JOIN/OPEN). After that, `tools\Watch-Bobiverse.ps1` is a hidden 30s loop: POINT local status, scrape peer POINT lines into `bob-peers\`, keep `irc_agent.py` joined. **No grok.exe. No reasoning. Not `Invoke-BobFleetTick`.** The tray only reads those JSON files. `Watch-BobTray` starts the loop the same way it starts `Watch-BobJobs`.

Do not open IRC from CI. Ergo `PASS` is `~\.grok\ergo\connect.password` (env `AGENTIC_IRC_PASSWORD`); do not commit it. SASL env only if a box still needs it (`AGENTIC_IRC_SASL_USER` / `AGENTIC_IRC_SASL_PASSWORD`). Prefer `host=irc.ntsa.uk` (cert/SNI). Do not default ionos to `127.0.0.1` unless the agent sets `server_hostname=irc.ntsa.uk` while connecting to loopback. `$env:BOB_IRC_HOST` overrides `--host` when set. `127.0.0.1` is a valid private Ergo host (same daemon); do not kill loopback `irc_agent` as stale/Libera.

## Outbox POINT backlog (Ergo disconnect loop)

`Write-BobIrcStatus` appends a POINT every Watch tick (~30s). A huge `~\.agentic-irc-bobiverse\outbox.txt` of pending `MOOT v1 POINT … BOB v1` lines (`lastSeen=` is the only change) makes `irc_agent.py` drain at FLOOD_S=0.8s; Ergo flood/burst limits drop the client; the agent reconnects; the backlog grows. Dedupe skips an append when the last outbox line matches the new POINT after stripping `lastSeen=`. Start/Install also compact a POINT-only backlog over 32KB down to the latest self POINT.

Verify on the box: outbox stays small across several Watch ticks; one `irc_agent` process; no rapid `001`/`JOIN` spam in `irc.log`.
