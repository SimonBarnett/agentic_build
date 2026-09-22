---
name: killproc
description: >
  End hung agents and roll a replacement process. Use when the user says
  killproc, hung agent, jung agent, end process and roll another, kill the
  deaf talk seat, stuck irc_agent, or recycle a hung Cursor TUI seat.
  Named Grok Bot Temporal hangs are unstick-grok-bot. Fleet job queue is
  grok-build-fleet. Talk-seat nick/home rules stay agentic-irc.
---

# killproc

Kill the **named hung seat**, then start a replacement. Do not spray
`Stop-Process` across every `irc_agent` / `irc_listen` / `agent.cmd`.

## Target

Identify **one** `--home` and `--nick` first (`coordinator.pid` on that
home). Flamingo examples:

| Seat | Nick | Home |
|---|---|---|
| First Cursor TUI | `flamingo-<seatPid>` | `~\.agentic-irc-cursor` |
| Second TUI (Agentic Build IRC) | `flamingo-<otherSeat>` | `~\.agentic-irc-cursor-2` |
| Builder | `bob-flamingo` | `~\.agentic-irc-bobiverse` |

`seat=` is PowerShell coordinator `$PID` (issue #88), not python listen/agent.

Hung / "jung" talk seat: `001`+JOIN but no `pong`, `listen=` empty, or
Cursor killed foreground `irc_listen` (`4294967295`). Socket up + deaf
is still a killproc target if Simon said end/roll.

## Do not kill

- The live seat **this** TUI owns (this home's `coordinator.pid`).
- `bob-*` / Watch-Bobiverse unless Simon named the builder.
- `BobFleet-*` scheduled tasks.
- Another seat's `--home` (same-nick ghost / steal). Skill `agentic-irc`.
- Halloy. Do not `SendKeys` into `#bobiverse – Halloy`.
- Named Grok Bot — `unstick-grok-bot`.

## Command

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Stop-HungAgent.ps1 -IrcHome "$env:USERPROFILE\.agentic-irc-cursor-2" -Nick flamingo-2224 -Roll
```

`-Home` is required. `-Nick` required for `-Roll`. Script stops only
`irc_agent.py` / `irc_listen.py` whose command line contains that home.
`-Roll` starts one new agent (PASS from `~\.grok\ergo\connect.password`,
never printed) plus detached `irc_listen` with stdout
`$Home\listen.stdout.log`. Writes `coordinator.pid`.

The **Cursor TUI** for that nick must still arm notify `^FROM ` on
**that** home (or tail `listen.stdout.log`). killproc cannot attach
another window's TSR.

## After

1. Confirm `001 <nick>` in that home's `irc.log`.
2. `PRIVMSG <nick> :ping` and keep pinging until `pong` (Simon: ping
   him when you fix). Cap retries; do not flood.
3. ACK on `#bobiverse` which nick was killed and rolled.
4. One voice: do not write the killed nick's `outbox.txt` from this TUI.

## Pointers

- Talk-seat recycle / two homes: `agentic-irc`.
- Builder recycle: `bob-irc`.
- Skills refresh: `reinstall-agentic-build-skills` + `install_skill.py`.
