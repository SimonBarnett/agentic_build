# Bobiverse (MODE2 moot on `#bobiverse`)

Fleet machines do **not** SMB-peek each other. Flamingo and MarchHare sit on bobnet copper; ionos is a VPS; DEV1 is the customer Azure box. Status rides a private Ergo on ionos (`irc.ntsa.uk:6697` TLS), not Libera. See `docs/bobiverse-ionos-ircd.md`.

## Channel

| | |
|---|---|
| Channel | `#bobiverse` |
| Mode | MODE2 moot, `free` |
| Moot id | `b0b1be15e0000001` |
| Human talk | Short English PRIVMSG on real field change or one-shot long-running warning |
| Tray pull | `!bobiverse` ~every 120s from `bob-*` nicks; chair whispers `BOB DIGEST v1 i/n` JSON (full card) or legacy `BOB TRAY v1 …` kv lines |

Nicks (one builder agent per machine):

| Machine id | Nick |
|---|---|
| flamingo | `bob-flamingo` |
| marchhare | `bob-marchhare` |
| ionos | `bob-ionos` |
| ce-priority-dev1 | `bob-dev1` |

Home on each box: `~\.agentic-irc-bobiverse` (not the Club Madeira `#cm-bob-oscar` homes).

## Shop channels (`#<machine>`)

Each fleet box has a **shop** room `#<machine-id>` (`#flamingo`, `#marchhare`, `#ionos`, `#ce-priority-dev1`; `#dev1` is the same room as `#ce-priority-dev1`). `bob-*` builders JOIN `#bobiverse` **and** the local shop (`Get-BobIrcBuilderChannels` in `Watch-Bobiverse` / `Install-BobIrc`). Git/MRB workers never JOIN `#bobiverse`; they appear on the shop only as `w-<short>-<pid>` (`w-io-<pid>` on ionos, `w-fl-<pid>` on flamingo, etc.) via `Start-BobWorkerIrcAgent` → `agentic_irc` `start_worker_irc_agent.py`. No `!report` write path on IRC; digest updates use write-only `reportUrl` POST (below).

### Shop GIT backup (`!BORED` / `!ACCEPT`)

Jeeves is the only nick that says `GIT` on `#bobiverse`. `bob-*` does not auto-claim those lines. When a `w-*` ear has been idle for more than 2 minutes, `Watch-Bobiverse` appends `PRIVMSG #<shop> :!BORED` to **that worker's** `outbox.txt` (not the builder outbox, not the chair outbox). Jeeves (agentic_irc chair; it already joins each shop) offers the next unaccepted task. The same `w-*` then says `!ACCEPT {repo} {task} {id}` and `Start-BobBuild` enqueues it. The digest webhook reports that inbox job and drops it when the job leaves inbox/running. Chair FIFO file `git-accept-queue.json` is read-only here. Skill `bob-git-accept`.

After this lands on `main`, recycle **Watch-Bobiverse** on each box so the poller loads the shop tick. Recycle Jeeves only with the agentic_irc chair-queue change.

## Status on disk

`Write-BobIrcStatus` (Watch loop, ~30s) refreshes `~\.agentic-irc-bobiverse\bob-peers\<id>.json` with weekly bars, jobs, model/kind/repo/sha, and `lastSeen`. It does **not** append a `MOOT v1 POINT … BOB v1` line every tick (that was the Halloy firehose). When model, kind, repo, sha, hung/responding, or running/queued counts change, one conversational English line goes to the channel via `outbox.txt`.
Historical park (2026-09-20 quieter-talk intake, DM-centric `!bobiverse` later superseded by #74 / digest): `docs/feature-request-bobiverse-quiet-talk-2026-09-20.md` / issue #36.


On the same delta gate (not `lastSeen`-only), it may **POST** ionos `reportUrl` from `config/bobiverse.json` (`op=merge`, header `X-Bob-Secret` from `BOB_REPORT_SECRET` or `~\.grok\bob\report.secret` — never git). The digest **chair** (`chairNick` / `Install-BobChair.ps1`) is separate from `bob-<machine>` builders; Watch does not start the chair.

Tray peers for **other** machines: `Watch-Bobiverse` sends `!bobiverse` about every **120 seconds**, then ingests chair **`BOB DIGEST v1`** JSON whispers (chunked when needed) from `irc.log` into `bob-peers\` plus `cursor-pools.json` cache. Legacy **`BOB TRAY v1`** kv lines still work. Protocol: `agentic_irc` `!bobiverse` digest + issue #142 / `docs/feature-request-bobiverse-digest-feeds-systray-2026-09-21.md`.

Example tray line (machine-readable, not for channel spam):

```
BOB TRAY v1 id=ionos weekly=4 running=1 queued=0 repo=SimonBarnett/agentic_build kind=worker model=Cursor Models lastSeen=2026-09-21T00:00:00Z jobs=SimonBarnett/agentic_build:running
```

`BOB v1` POINT trailing text remains supported for transcript ingest (`Import-BobIrcPeerTranscript`) but is not the primary Watch publish path.

The tray paints **one weekly bar per registered `nicks` machine** from `bob-peers\`. Ghost IRC ids (`marchhare-bugets`, raw nicks) are dropped. `reach=irc-fallback` for those four seats. Repo stamps never publish `?` when a job is known.

## Install (each build box)

Python 3.12+ plus `pip install -r C:\ai\agentic_irc\requirements.txt`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Install-BobIrc.ps1 -MachineId flamingo -Chair
# other boxes: omit -Chair (JOIN)
```

`Install-BobIrc.ps1` is **one-shot** (genkey, JOIN/OPEN). After that, `tools\Watch-Bobiverse.ps1` is a hidden ~30s loop: local peer JSON, optional channel talk, `!bobiverse` tray pull ~120s, keep `irc_agent.py` joined. **No grok.exe. No reasoning. Not `Invoke-BobFleetTick`.** The tray only reads those JSON files. `Watch-BobTray` starts the loop the same way it starts `Watch-BobJobs`.

Do not open IRC from CI. Ergo `PASS` is `~\.grok\ergo\connect.password` (env `AGENTIC_IRC_PASSWORD`); do not commit it. Prefer `host=irc.ntsa.uk`. `$env:BOB_IRC_HOST` overrides `--host` when set. `127.0.0.1` is a valid private Ergo host; do not kill loopback `irc_agent` as stale/Libera.

## Outbox backlog (Ergo disconnect loop)

A huge `outbox.txt` of pending lines makes `irc_agent.py` drain at FLOOD_S=0.8s; Ergo flood limits drop the client. `Compact-BobIrcOutbox` compacts old `MOOT v1 POINT` backlogs over 32KB. With quiet talk, outbox should stay small (change lines + `!bobiverse` only).

Verify on the box: no `BOB v1` kv firehose in Halloy; outbox stays small; one `irc_agent` process; tray peers refresh after `!bobiverse`.
