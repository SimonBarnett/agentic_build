---
name: bob-irc
description: >
  Private Ergo for #bobiverse on ionos (irc.ntsa.uk:6697 TLS). Use when the user
  says join Ergo, irc.ntsa.uk, bobiverse IRC, recycle Watch-Bobiverse, BobIrcd,
  Halloy, shop channel, !bobiverse, or /bob-irc. Canonical protocol skill is
  agentic_irc .grok/skills/bob-irc. Job queue is grok-build-fleet.
---

# Bobiverse IRC

Protocol playbook: `https://github.com/SimonBarnett/agentic_irc`
`.grok/skills/bob-irc/SKILL.md` and issue #46.
Nicks/host/`reportUrl` live in this repo `config/bobiverse.json` and
`docs/bobiverse.md`.

`bob-<id>` JOINs `#bobiverse` + `#<id>`. Workers: skill `bob-shop-worker`.
Read status: `!bobiverse`. Write: POST `reportUrl`. No `!report`.
Machines persist offline. Workers delete on disconnect. Bob drop closes shop.

Do not duplicate firewall/recycle steps here — see agentic_irc `bob-irc`.
