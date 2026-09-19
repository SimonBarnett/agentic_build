---
name: bob-fleet-tray
description: >
  System tray icon for the IONOS fleet watcher: hidden PowerShell, green when
  idle, flashes on ACTION_REQUIRED, mouse-over shows box occupancy from
  box-usage. Use when the user says tray icon, system tray, NotifyIcon, flash
  the watcher, hover remaining, mouse over tray, or /bob-fleet-tray. Stall
  policy is bob-fleet-monitor. Usage numbers come from box-usage / Get-BobBoxUsage.ps1 -Hover.
---

# Fleet tray

`tools/Watch-BobTray.ps1` is the human monitor. `Install-BobFleet` registers it as `BobFleet-<id>` with `-STA -WindowStyle Hidden`. It starts hidden `Watch-BobJobs.ps1`. Do not leave a blank PowerShell window on the desktop.

## UI

- Green: idle. Flashing red/amber: ACTION_REQUIRED (same tokens as `Watch-BobAgents.ps1`).
- Left-click: acknowledge (stop flash).
- Right-click: Status, Acknowledge, Open log, Exit watcher.
- **Mouse-over** (`NotifyIcon.Text`, max 63 chars): `Get-BobBoxUsage.ps1 -Hover` — occupancy, not invented token remainder. Format `P+ grok:n/max q:inbox r:running`. `box-usage` owns what those numbers mean.

Log: `~\.grok\long-running-background-tasks\watch_bob_tray.log`.

## Install / recycle

```powershell
powershell -NoProfile -File "$repo\tools\Install-BobFleet.ps1" -MachineId <id> -CwdRoots <roots>
```

Recycling the task **kills** the pull worker. Do not recycle while a job is running (see `bob-fleet-monitor`). Hover/flash code changes apply on the next tray start.

## Hard rules

- Not a Windows service.
- Do not print `auth.json` or tokens in the tooltip.
