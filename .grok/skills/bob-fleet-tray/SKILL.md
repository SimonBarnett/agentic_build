---
name: bob-fleet-tray
description: >
  System tray icon for the IONOS this-machine watcher: hidden PowerShell, Font
  Awesome free robot icon, context remaining bar, jobs with machine/id8/repo/duration.
  Use when the user says tray icon, system tray, NotifyIcon, flash
  the watcher, hover remaining, mouse over tray, or /bob-fleet-tray. Stall
  policy is bob-fleet-monitor. Usage numbers come from box-usage / Get-BobBoxUsage.ps1 -Hover.
---

# Tray (this machine)

`tools/Watch-BobTray.ps1` is the human monitor for **this Windows box**. Job data is the local BobBridge store (`Get-BobBuilds` on this host). There is no cross-host peek (no WinRM, no remote health API). Title is `Bob (<machineId>)`. Do **not** call it a fleet monitor and do **not** say "No fleet jobs running" — idle copy is `No jobs on this machine`.

`Install-BobFleet` registers it as `BobFleet-<id>` with `-STA -WindowStyle Hidden`. It starts hidden `Watch-BobJobs.ps1`. Do not leave a blank PowerShell window on the desktop.

## UI

- Idle: Font Awesome Free solid **robot** (CC BY 4.0), not grok.exe extract.
- Left-click: acknowledge. Right-click: Status, Open log, Exit.
- **Mouse-over**: dark card.
  - Title: `Bob (<machineId>)` from this box's `machine.json` / `BOB_MACHINE_ID`.
  - **Context remaining** is the **session window** only: `(context_window - (inputTokens - cachedReadTokens)) / context_window` from that session's `usage.json` vs `models_cache`. If `usage.json` is missing, remaining is **unknown**: caption `n/a`, bar track and fill **hidden**. Never fake 100%. Never paint a depleted/empty bar (do not imply 0%) without `usage.json`.
  - **Weekly limit** is CLI-footer only (`Weekly limit left` in grok.exe). The tray does **not** show weekly %. There is no weekly field in BobBridge. Do not invent one. Do not read the context bar as weekly quota.
  - Jobs on **this machine**: machine, **id8**, GitHub repo, duration, state. Empty: `No jobs on this machine`.
  - Footer: `alert: watcher|stall|context|none`.

## Badge sources

Never pulse context when `remaining_pct` is null. Unknown remaining is not &lt;10%.

| `alert:` | Source | Badge |
|---|---|---|
| `watcher` | stall monitor `ACTION_REQUIRED: watcher_down` | red/amber flash |
| `stall` | `ACTION_REQUIRED: agent_stall` / `inbox_stale` / `running_orphan` | red/amber flash |
| `context` | session context remaining **known** and &lt; 10% | amber pulse once a minute |
| `none` | no ACTION_REQUIRED; remaining unknown or ≥ 10% | idle robot |

Log: `~\.grok\long-running-background-tasks\watch_bob_tray.log`.

## Install / recycle

```powershell
powershell -NoProfile -File "$repo\tools\Install-BobFleet.ps1" -MachineId <id> -CwdRoots <roots>
```

Recycling the task **kills** the pull worker. Do not recycle while a job is running (see `bob-fleet-monitor`). Hover/flash code changes apply on the next tray start.

## Hard rules

- Not a Windows service.
- Do not print `auth.json` or tokens in the tooltip.
- Do not claim the card is fleet-wide. Other hosts (ionos vs marchhare) have their own local stores.
- Do not report weekly % from the context bar.
