---
name: agent-monitor-setup
description: >
  Install / initialise the AgentMonitor watch-seat (Cursor or Grok) from the
  Bob Fleet tray "Agents" menu, and via tools/Install-AgentMonitor.ps1. Use
  when the user says agents menu, tray agents, install watch seat, set up
  Cursor/Grok agent, agent not installed grey, initialise agent setup,
  Install-AgentMonitor, or /agent-monitor-setup. The watch-seat behaviour
  itself lives in the AgentMonitor repo skills (agent-monitor, watch-seat).
---

# Agent monitor setup (tray Agents menu)

The Bob Fleet tray (`tools/Watch-BobTray.ps1`, skill `bob-fleet-tray`) exposes
the two watch-seat agents as ONE context-menu item, **Agents**. Right-click the
tray robot, open **Agents**, then select which agent to launch. This replaces
having two separate desktop/tray icons.

## Menu entries

| Entry | Watch-AgentHealth arg | Icon source (same as Desktop shortcut) |
|-------|-----------------------|-----------------------------------------|
| Cursor | `cursor` | `%LOCALAPPDATA%\Programs\cursor\Cursor.exe` |
| Grok | `grok` | `%LOCALAPPDATA%\Programs\Grok Bot\Grok Bot.exe` |

- **Icon parity.** Each entry's icon is extracted from the agent app `.exe`
  with `Icon.ExtractAssociatedIcon`, so it matches the AgentMonitor Desktop
  shortcut (`shortcuts/*.lnk` IconLocation), not the tray robot glyph.
- **Installed** = `Desktop\Watch-AgentHealth\Watch-AgentHealth.cmd` exists AND
  the agent `.exe` exists. Installed -> click launches a **hidden** watch
  worker (`powershell -WindowStyle Hidden -File Watch-AgentHealth.ps1
  -WatchWorker -Cursor|-Grok`) so the watch console stays hidden but the
  agent TUI stays visible (do **not** pass `-Windows off`). Desktop shortcut
  `*-New`/`*-Resume` `.cmd` files stay fully hidden via `Run-Hidden.vbs`.
- **Not installed** = icon is greyed (desaturated). The entry stays clickable;
  clicking **initialises the setup** (`tools/Install-AgentMonitor.ps1 -Agent
  <cursor|grok>`), which deploys AgentMonitor and re-enables the entry.
- The dropdown rebuilds on open (`DropDownOpening`) so grey/enabled state and
  icons reflect the current install.

## Setup / initialise

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$repo\tools\Install-AgentMonitor.ps1" -Agent both
```

`Install-AgentMonitor.ps1`:

1. Clones (or `fetch` + `reset --hard`) `https://github.com/SimonBarnett/AgentMonitor`
   into `Desktop\Watch-AgentHealth` (the Desktop shortcut target).
2. Copies the AgentMonitor watch-seat skills (`agent-monitor`, `watch-seat`)
   into `~\.grok\skills`.
3. Logs to `~\.grok\long-running-background-tasks\install_agent_monitor.log`.

Idempotent: re-running updates the deploy in place.

## Preferred IRC wake (Simon 2026-09-23)

Watch-AgentHealth is the **preferred** way to receive IRC in a Cursor/Grok
session. The monitor forwards `FROM` into the TUI so agents do **not** arm
an in-session `listen.stdout.log` `^FROM ` TSR (that burns tokens on
`#bobiverse` spam). Fleet create + wake playbook: skill `watch-agent-health`.
IRC wire: `agentic-irc`. Seat behaviour: AgentMonitor `watch-seat`.

## Skill harvest

This setup ships with the agentic_build skill harvest: `Copy-BobProjectSkills`
/ `Install-BobFleet` copy this `SKILL.md` (and `watch-agent-health`) into
`~\.grok\skills`, and `harvest-agent-skills` lists them. The watch-seat
runtime contract stays in the AgentMonitor repo skills; this skill owns
tray wiring + install.

## Hard rules

- Not a Windows service. Recycle the tray (skill `bob-fleet-tray`) after menu
  code changes; do not add a second NotifyIcon.
- Do not point a watch seat at a forbidden IRC home (see `watch-seat`); the
  tray only passes `cursor` / `grok`, letting AgentMonitor pick the watch home.
- No secrets. No UAT stamp.
