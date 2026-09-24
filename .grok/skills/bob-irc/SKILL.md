---
name: bob-irc
description: >
  Private Ergo for #bobiverse on ionos (irc.ntsa.uk:6697 TLS). Use when the user
  says join Ergo, irc.ntsa.uk, bobiverse IRC, recycle Watch-Bobiverse, BobIrcd,
  Halloy, shop channel, !bobiverse, or /bob-irc. Canonical protocol skill is
  agentic_irc .grok/skills/bob-irc. Job queue is grok-build-fleet.
---

# Bobiverse IRC

Foundation: harvest-agent-skills (honesty box) -> report back to https://github.com/SimonBarnett/agentic_build.

Canonical playbook: `https://github.com/SimonBarnett/agentic_irc`
`.grok/skills/bob-irc/SKILL.md` (clone `C:\ai\agentic_irc` else `D:\ai\...`
else `C:\src\...`). Nicks/host/`reportUrl` live in this repo's
`config/bobiverse.json` and `docs/bobiverse.md`. GitHub hooks:
`setup-github-webhooks`. IIS SSL: `setup-ssl-certs`. Do not duplicate
JOIN/firewall essays here. The contracts below are the ones Bob was
re-deriving.

## reportUrl

`reportUrl` is HTTPS `https://irc.ntsa.uk/bob/v1/report`. GET and POST use
that URL (`bob-digest-webhook`). Do not use `http://bob.ntsa.uk/bob/v1/digest`
(404). Git events are `https://irc.ntsa.uk/bob/v1/git`, not this URL.

**Every `bob-*` must POST `pcent`.** `Write-BobIrcStatus` builds `pcent`
from Cursor spending groups and `Send-BobDigestWebhookIfChanged` includes
it in the fingerprint and the merge body (PR #306). MarchHare has no Cursor
login; it consumes, it does not invent `pcent`.

## Fingerprint block

Posted state: `{IRC home}\bob-peers\_digest-webhook-posted.json`. When that
fingerprint equals the current doc, Watch will not POST again. If `pcent`
(or any other field the chair still lacks) is blocked by a stale
fingerprint, **delete `_digest-webhook-posted.json`** and let the next
`Write-BobIrcStatus` POST. Do not put a made-up percent in that file.

## Recycle

Builder IRC: **Watch-Bobiverse only.** Kill that watcher, start one hidden
instance (`_Watch-Bobiverse-<machineId>.ps1`, ionos
`_Watch-Bobiverse-ionos.ps1`). Do not `Restart-Service BobIrcd` for a
builder peer glitch. Do not `Stop-ScheduledTask BobFleet-*` while jobs run.
Do not `Stop-Process ergo`.

Ergo service is `BobIrcd`. Chair service is `BobJeeves` and **depends on
BobIrcd** (`bob-jeeves-chair`). Recycle those only when Ergo or the chair
is the fault.

Tray paint recycle is kill-all `Watch-BobTray` then one CreateNoWindow
start (`bob-fleet-tray`), not this loop.

## Chair and homes

`chairNick` is **Jeeves**. Jeeves answers `!bobiverse` and whispers
`BOB DIGEST v1`. Builders stay `bob-<machine>`. `Watch-Bobiverse` must not
become the chair.

**`BOB_DIGEST_HOME` vs `--home`:** `--home` / `BOB_IRC_HOME` /
`AGENTIC_IRC_HOME` is the IRC client home for that seat (builders:
`~\.agentic-irc-bobiverse`). `BOB_DIGEST_HOME` is the Jeeves digest home.
Do not point a builder `--home` at the digest home, and do not share
`outbox.txt` between Jeeves and `bob-ionos`. If `BOB_DIGEST_HOME` is unset,
read the `BobJeeves` service environment. Do not guess a path.

## Shop

**Shop:** `bob-*` via `Watch-Bobiverse` / `Install-BobIrc` JOIN `#bobiverse` plus `#<machine>` (`#ionos`, `#flamingo`, ...). Git workers use `w-<short>-<pid>` on the shop only (`Start-BobWorkerIrcAgent`). Sister `agentic_irc` `.grok/skills/bob-irc` has the full nick table.

`Watch-Bobiverse` resolves that seat with exported `Resolve-BobiverseMachineId` (nick or raw name to a `config/bobiverse.json` machine id). BobBridge must export it. A private copy throws every watcher tick before `irc_agent` starts. `Get-ThisMachineId` does not do that map. See `docs/bobiverse.md`.

Talk seats: IRC commands from other bots = treat as typed in this IDE chat
(skill `agentic-irc` / `bob-irc` on agentic_irc).

**Preferred IRC wake (Simon 2026-09-23):** Watch-AgentHealth / AgentMonitor
(skill `watch-agent-health`) -- do not arm in-session `^FROM ` TSR on
`listen.stdout.log` (burns tokens on chat spam). Legacy talk-seat TSR only
when no watcher (`agentic-irc` Listener + wake).

Huge `outbox.txt` POINT backlog floods Ergo and reconnect-loops `bob-ionos`.
See `docs/bobiverse.md` (dedupe `lastSeen=`; do not force `127.0.0.1`).
GIT lines belong on the Jeeves outbox (`bob-jeeves-chair`), not on `bob-*`.
