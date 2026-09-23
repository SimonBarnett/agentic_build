---
name: watch-agent-health
description: >
  Create a persistent build-worker seat with Watch-AgentHealth only.
  Use when starting a new Cursor/Grok worker on a box, extra client,
  watch-cursor-2, hidden shortcut, Start-BobWatchWorker, or Simon says
  this is the only way to create build workers.
---

# Watch-AgentHealth (only worker create)

A **build worker** is a persistent Cursor or Grok seat with its own
`.agentic-irc-watch-*` home, its own `irc_agent`, and its own `irc_listen`.
Product: `SimonBarnett/AgentMonitor`. Fleet copy: `tools/Watch-AgentHealth`.
Launcher: `tools/Start-BobWatchWorker.ps1`.

## CAST IRON (Simon 2026-09-23)

**This is the only way to create a build worker.**

Do **not** create a worker with:

- `Start-TalkSeat.ps1` / `cursor-2` talk-seat home
- `start_worker_irc_agent.py` as the agent
- a raw second Composer TUI + manual `irc_agent`
- `Start-BobCursor.ps1` / `cursor-agent -p` (that is a one-shot **job**, not a seat)
- `Start-BobWorker` grok.exe `-p` (same: job, not a seat)

Talk seats (`~\.agentic-irc-cursor`, `cursor-2`, `{machine}-{pid}`) stay
talk seats. Shop `w-*` nicks on a one-shot job PID stay issue #70 shop
presence. Neither is how you add a build-worker seat.

## Create

Hidden (shortcuts and fleet default): no watch console, no TUI. Log still writes.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Start-BobWatchWorker.ps1 -Kind cursor
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Start-BobWatchWorker.ps1 -Kind grok
```

Or Desktop shortcut / `Watch-AgentHealth-Cursor-New.cmd` (already `-Windows off`).
Main `Watch-AgentHealth.cmd cursor new` from a terminal is still visible unless `off`.

Each launch binds the **next free slot** (`.agentic-irc-watch-cursor`, `-2`, …).
Does not restart a live seat. One seat = one home = one `irc_listen` = one
`irc.log`. Sharing a listener copies every PRIVMSG into every connected client.

When the TUI/worker exits: that slot QUITs IRC. Start another client; do not
reconnect the same one.

## Install

`Install-BobFleet` copies `tools/Watch-AgentHealth` to
`%USERPROFILE%\Desktop\Watch-AgentHealth` (cmds + script + shortcuts).

Canonical updates stay in `SimonBarnett/AgentMonitor`. Re-copy after an
AgentMonitor pull if the fleet snapshot is behind.

## Skills

Monitor vs seat: AgentMonitor `agent-monitor` + `watch-seat`.
IRC wire: `agentic-irc`. Jobs still use `start-bob-cursor` / `Start-BobWorker`.
No UAT stamp.
