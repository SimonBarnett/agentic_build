---
name: bob-irc
description: >
  Private Ergo for #bobiverse on ionos (irc.ntsa.uk:6697 TLS). Use when the user
  says join Ergo, irc.ntsa.uk, bobiverse IRC, recycle Watch-Bobiverse, BobIrcd,
  Libera banned, or /bob-irc. Fleet status is this server, not Libera. Job queue
  is grok-build-fleet. Named-bot hangs are unstick-grok-bot.
---

# Bobiverse IRC (private Ergo)

Canonical facts: `docs/bobiverse.md` (nicks, POINT, tray) and `docs/bobiverse-ionos-ircd.md` (Ergo, cert, task). `config/bobiverse.json` `host` / `port` / `nicks`.

Server: Ergo on ionos, TLS `irc.ntsa.uk:6697`. Channel `#bobiverse`. Nicks `bob-flamingo` / `bob-marchhare` / `bob-ionos` / `bob-dev1`. Home `~\.agentic-irc-bobiverse`.

Connect secret is `~\.grok\ergo\connect.password` (env `AGENTIC_IRC_PASSWORD`). Never print it. Never `password=` assignments in prompts, chat, or git.

## Join a build box

1. Pull `agentic_build` and `agentic_irc` (`D:\ai\...` else `C:\ai\...` else `C:\src\...`).
2. Copy the connect file to that user's `~\.grok\ergo\connect.password` (SEAL over `#bobiverse` if you cannot copy).
3. Recycle **Watch-Bobiverse only** (one `_Watch-Bobiverse-<id>.ps1`). Do not `Stop-ScheduledTask BobFleet-*` while `grok.exe` jobs run.
4. Confirm `irc.log` has `001` from `irc.ntsa.uk` and `JOIN #bobiverse`.

One-shot: `tools\Install-BobIrc.ps1 -MachineId <id>`. Ircd on ionos: `tools\Install-BobIrcd.ps1` / task `BobIrcd-ionos`. Start/firewall recovery: `https://github.com/SimonBarnett/agentic_irc` skill `agentic-irc`.

`Watch-Bobiverse` skips `irc_agent` when `host` is empty or `irc.libera.chat`. Pass `--host` / `--port` from `bobiverse.json`.

Git-task verbs (no vendor names): `SPEC` `WAIT` `BUILD` `PUSH` `MRB` `FIX` `UAT`.
`BUILD <job> <nick>` is the machine nick; fuel lives in the job file. `WAIT`
means the picker found no eligible `(machine, fuel)` pair. Do not invent a
new IRC protocol.

## Do not

- Point `bob-ionos` at Libera (IP banned 2026-09-20).
- Run two Watch-Bobiverse processes (reconnect flood).
- Open public `:6667`.
- WinRM.
