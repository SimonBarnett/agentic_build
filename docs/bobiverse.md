# Bobiverse (MODE2 moot on `#bobiverse`)

Fleet machines do **not** SMB-peek each other. Flamingo and MarchHare sit on bobnet copper; ionos is a VPS; DEV1 is the customer Azure box. Status rides a private Ergo on ionos (`irc.ntsa.uk:6697` TLS), not Libera. See `docs/bobiverse-ionos-ircd.md`.

Live shop-channel spec: `docs/feature-request-shop-channel-worker-cc-webhook-2026-09-21.md` (issue #124) and `agentic_irc` issue #46.

## Channels

| | |
|---|---|
| Fleet | `#bobiverse` — Bob ACTION (`/me`) + working-on. MODE2 `free`. No POINT firehose. |
| Shop | `#flamingo` `#marchhare` `#ionos` `#ce-priority-dev1` (`#dev1` same channel) |
| Moot id | `b0b1be15e0000001` |
| Read | `!bobiverse` whisper JSON (no HTTP GET of digest) |
| Write | POST `reportUrl` in `config/bobiverse.json` (write-only) + IRC JOIN/QUIT |

Nicks (one builder Bob per machine):

| Machine id | Nick | Shop | Worker nick |
|---|---|---|---|
| flamingo | `bob-flamingo` | `#flamingo` | `w-fl-<pid>` |
| marchhare | `bob-marchhare` | `#marchhare` | `w-mh-<pid>` |
| ionos | `bob-ionos` | `#ionos` | `w-io-<pid>` |
| ce-priority-dev1 | `bob-dev1` | `#ce-priority-dev1` | `w-d1-<pid>` |

`bob-<id>` JOINs fleet + shop. Workers JOIN shop only. Key is `<id>:<pid>`.
Home on each box: `~\.agentic-irc-bobiverse`.
Worker home: `~\.agentic-irc-bobiverse\workers\<id>\<pid>`.

Machines persist in the digest as `I am online` / `I am offline`.
Disconnected workers are **deleted**. Bob drop closes that shop and deletes its workers.

`!report` is gone. Do not send it.

## Status on disk

Briefer file: `~\.agentic-irc-bobiverse\digest.json` (ionos). Not a public URL.
`Write-BobIrcStatus` may still refresh local `bob-peers\<id>.json` for the tray.
It does **not** append `MOOT v1 POINT` / `!report` every tick.
Watch POSTs `working_on` / `pcent` / `uptime_since` on change to `reportUrl`.

Tray may still `!bobiverse` ~120s and ingest the whisper. Do not HTTP GET the digest.

## Install (each build box)

Python 3.12+ plus `pip install -r C:\ai\agentic_irc\requirements.txt`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Install-BobIrc.ps1 -MachineId flamingo -Chair
# other boxes: omit -Chair (JOIN)
```

`Watch-Bobiverse` keeps `irc_agent.py` on `#bobiverse` and `#<id>`.
MRB/build skills load `bob-shop-worker` and attach `w-<short>-<pid>`.

Ergo `PASS` is `~\.grok\ergo\connect.password`. Callback secret is
`~\.grok\bob\report.secret`. Do not commit either.

Do not open IRC from CI.
