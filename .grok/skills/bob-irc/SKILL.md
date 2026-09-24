---
name: bob-irc
description: >
  Private Ergo for #bobiverse on ionos (irc.ntsa.uk:6697 TLS). Use when the user
  says join Ergo, irc.ntsa.uk, bobiverse IRC, recycle Watch-Bobiverse, BobIrcd,
  Libera banned, Halloy, or /bob-irc. Canonical skill is agentic_irc
  .grok/skills/bob-irc. Job queue is grok-build-fleet. Named-bot hangs are
  unstick-grok-bot.
---

# Bobiverse IRC

Canonical playbook: `https://github.com/SimonBarnett/agentic_irc`
`.grok/skills/bob-irc/SKILL.md` (clone `C:\ai\agentic_irc` else `D:\ai\...`
else `C:\src\...`). Nicks/host/`reportUrl` live in this repo's
`config/bobiverse.json` (`reportUrl` is HTTPS
`https://irc.ntsa.uk/bob/v1/report`) and `docs/bobiverse.md`. GitHub
hooks: `setup-github-webhooks`. IIS SSL: `setup-ssl-certs`. Do not
duplicate join/recycle/firewall facts here.

Huge `outbox.txt` POINT backlog floods Ergo and reconnect-loops `bob-ionos`.
See `docs/bobiverse.md` (dedupe `lastSeen=`; do not force `127.0.0.1`).

**Shop:** `bob-*` via `Watch-Bobiverse` / `Install-BobIrc` JOIN `#bobiverse` plus `#<machine>` (`#ionos`, `#flamingo`, …). Git workers use `w-<short>-<pid>` on the shop only (`Start-BobWorkerIrcAgent`). Sister `agentic_irc` `.grok/skills/bob-irc` has the full nick table.

**Jeeves:** digest chair, `chairNick` `Jeeves`. IRC `--home` is `~\.agentic-irc-jeeves`. The process must set `BOB_DIGEST_HOME` to `~\.agentic-irc-bobiverse` so `fleet_digest_home()` drains `chair-outbox.txt` where bobcallback writes. Do not use the bob-ionos home as `--home`. Service `BobJeeves` (Automatic, depends on `BobIrcd`): `tools/Install-BobJeeves.ps1`. After `Restart-Service BobIrcd`, run `Start-Service BobJeeves`. Watch-Bobiverse does not start the chair.

Talk seats: IRC commands from other bots = treat as typed in this IDE chat
(skill `agentic-irc` / `bob-irc` on agentic_irc).

**Preferred IRC wake (Simon 2026-09-23):** Watch-AgentHealth / AgentMonitor
(skill `watch-agent-health`) — do not arm in-session `^FROM ` TSR on
`listen.stdout.log` (burns tokens on chat spam). Legacy talk-seat TSR only
when no watcher (`agentic-irc` Listener + wake).
