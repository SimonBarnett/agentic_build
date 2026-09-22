---
name: killproc
description: >
  End hung agents and roll a replacement process. Use when the user says
  killproc, hung agent, jung agent, end process and roll another, kill the
  deaf talk seat, stuck irc_agent, recycle a hung Cursor TUI seat, or the
  working agent must restart the hung other on this box. Named Grok Bot
  Temporal hangs are unstick-grok-bot. Fleet job queue is grok-build-fleet.
  Talk-seat nick/home rules stay agentic-irc.
---

# killproc

Kill the *named hung seat*, then start a replacement. Do not spray
Stop-Process across every irc_agent / irc_listen / agent.cmd.

## Target

Identify *one* --home and -Nick first (coordinator.pid on that home).
Flamingo examples:

| Seat | Nick | Home |
| First Cursor TUI | flamingo-<seatPid> | ~\.agentic-irc-cursor |
| Second TUI (Agentic Build IRC) | flamingo-<otherSeat> | ~\.agentic-irc-cursor-2 |
| Builder | bob-flamingo | ~\.agentic-irc-bobiverse |

seat= is PowerShell coordinator $PID (issue #88), not python listen/agent.

Hung / "jung" talk seat: 001+JOIN but no pong, listen= empty, or Cursor
killed foreground irc_listen (4294967295). Socket up + deaf is still a
killproc target if Simon said end/roll.

## Do not kill

- The live seat *this* TUI owns (this home's coordinator.pid).
- bob-* / Watch-Bobiverse unless Simon named the builder.
- BobFleet-* scheduled tasks.
- Another seat's --home (same-nick ghost / steal). Skill agentic-irc.
- Halloy. Do not SendKeys into #bobiverse / Halloy.
- Named Grok Bot -> unstick-grok-bot.

## Command

```
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Stop-HungAgent.ps1 -IrcHome "$env:USERPROFILE\.agentic-irc-cursor-2" -Nick flamingo-2224 -Roll
```

-IrcHome is required. Never -Home (PowerShell $Home is read-only).
-Nick required for -Roll. Script stops only irc_agent.py / irc_listen.py
whose command line contains that home.

-Roll starts one new agent (PASS from ~\.grok\ergo\connect.password,
never printed) plus detached irc_listen with stdout
$IrcHome\listen.stdout.log. Writes coordinator.pid.

The Cursor TUI for that nick must still arm notify ^FROM on *that* home
(or tail listen.stdout.log). killproc cannot attach another window's TSR.

## Working seat restarts the hung other

Simon: there is still one hung agent on each box -- the other working
agent restarts the other one.

1. You are the live seat. Read your coordinator.pid. Do not kill that home.
2. Hung other on *this* box: Stop-HungAgent -IrcHome <other home> -Roll.
   Typical other home ~\.agentic-irc-cursor-2.
3. If that home is missing (marchhare often seat-1 only), do not invent
   a kill. Say so. Second window must Start-TalkSeat -IrcHome cursor-2
   in THAT TUI (skill agentic-irc).
4. Do not WinRM other boxes. Ask their working nick on #bobiverse to
   killproc their hung home.
5. -Roll is not listening until a Cursor/Grok session wakes on that
   listen.stdout.log. If Simon says not listening: they close the hung
   TUI, then start a new cursor-agent (next section).

## Start a new cursor-agent after close

Simon: hung window gone / start a new cursor agent / irc and build /
try again.

1. Leave this TUI's cursor-agent (node under agent.cmd) alone.
2. If leftover irc_agent on cursor-2 is still JOIN, keep it. Else a *new*
   PowerShell -NoExit runs Start-TalkSeat.ps1 -MachineId <id> -IrcHome
   ~\.agentic-irc-cursor-2 (nick = that $PID, not the dead 2224).
3. Visible agent: powershell -NoExit -File a launch.ps1 that reads a
   prompt *file* and runs
   %LOCALAPPDATA%\cursor-agent\cursor-agent.ps1 --trust --force
   --workspace C:\ai --model grok-4.6 -- $prompt
   Do not put the prompt on cmd.exe /c (spaces truncate). Do not use -p
   (one-shot exits).
4. Prompt: you are <nick> from coordinator.pid; home cursor-2 only;
   arm FROM; pong; agentic_irc + agentic_build; do not touch cursor.
5. SendKeys only if GetForegroundWindow title is exactly
   Agentic Build IRC or Flamingo Talk Seat. Never Halloy
   (#bobiverse - Halloy).
6. Ping the new nick until pong.

Scripts on agentic_irc: Start-SecondSeatTui.ps1, _Run-SecondSeatTui.ps1,
bootstrap-second-seat.txt. Nick/home facts stay in skill agentic-irc.

## After

1. Confirm 001 / nick in that home's irc.log.
2. PRIVMSG <nick> :ping and keep pinging until pong (Simon: ping him
   when you fix).
3. ACK on #bobiverse which nick was killed and rolled.
4. One voice: do not write the killed nick's outbox.txt from this TUI.

## Pointers

- Talk-seat recycle / two homes / why 2nd kills 1st: agentic-irc.
- Builder recycle: bob-irc.
- Skills refresh: reinstall-agentic-build-skills + install_skill.py.
