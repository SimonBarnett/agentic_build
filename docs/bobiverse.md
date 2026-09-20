# Bobiverse (MODE2 moot on `#bobiverse`)

Fleet machines do **not** SMB-peek each other. Flamingo and MarchHare sit on bobnet copper; ionos is a VPS; DEV1 is the customer Azure box. Status rides Libera TLS IRC.

## Channel

| | |
|---|---|
| Channel | `#bobiverse` |
| Mode | MODE2 moot, `free` (every builder may POINT) |
| Moot id | `b0b1be15e0000001` |
| Transport | `MOOT v1 POINT` trailing text `BOB v1 …` (clear; not a secret) |

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

`irc_agent.py` writes `~\.agentic-irc-bobiverse\bob-peers\<id>.json`. The tray paints **one weekly bar per machine** from that POINT. `reach=irc-fallback` when they are on the moot roster. `not in moot` (not `unreachable`) when the nick is not on the MODE2 roster. The card has an **X** to close.

## Install (each build box)

Python 3.12+ plus `pip install -r C:\ai\agentic_irc\requirements.txt`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Install-BobIrc.ps1 -MachineId flamingo -Chair
# other boxes: omit -Chair (JOIN)
```

`Install-BobIrc.ps1` is **one-shot** (genkey, JOIN/OPEN). After that, `tools\Watch-Bobiverse.ps1` is a hidden 30s loop: POINT local status, scrape peer POINT lines into `bob-peers\`, keep `irc_agent.py` joined. **No grok.exe. No reasoning. Not `Invoke-BobFleetTick`.** The tray only reads those JSON files. `Watch-BobTray` starts the loop the same way it starts `Watch-BobJobs`.

Do not open Libera from CI. SASL env only if the box requires it (`AGENTIC_IRC_SASL_USER` / `AGENTIC_IRC_SASL_PASSWORD`); do not commit those.
