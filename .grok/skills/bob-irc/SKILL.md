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
else `C:\src\...`). Nicks/host live in this repo's `config/bobiverse.json`
and `docs/bobiverse.md`. Do not duplicate join/recycle/firewall facts here.

Huge `outbox.txt` POINT backlog floods Ergo and reconnect-loops `bob-ionos`.
See `docs/bobiverse.md` (dedupe `lastSeen=`; do not force `127.0.0.1`).

Parked FR (quiet conversational talk, join DM, `!bobiverse` network DM):
`docs/feature-request-bobiverse-quiet-talk-2026-09-20.md`.
