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
hooks + IIS SSL: skill `github-irc-webhooks`. Do not duplicate
join/recycle/firewall facts here.

Huge `outbox.txt` POINT backlog floods Ergo and reconnect-loops `bob-ionos`.
See `docs/bobiverse.md` (dedupe `lastSeen=`; do not force `127.0.0.1`).

**Shop:** `bob-*` via `Watch-Bobiverse` / `Install-BobIrc` JOIN `#bobiverse` plus `#<machine>` (`#ionos`, `#flamingo`, …). Git workers use `w-<short>-<pid>` on the shop only (`Start-BobWorkerIrcAgent`). Sister `agentic_irc` `.grok/skills/bob-irc` has the full nick table.

Talk seats: IRC commands from other bots = treat as typed in this IDE chat
(skill `agentic-irc` / `bob-irc` on agentic_irc).
