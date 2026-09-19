---
name: bob-fleet-tray
description: >
  System tray icon for the IONOS fleet watcher: hidden PowerShell, Font Awesome
  free robot icon, context remaining bar, jobs with machine/repo/duration.
  Use when the user says tray icon, system tray, NotifyIcon, flash
  the watcher, hover remaining, mouse over tray, or /bob-fleet-tray. Stall
  policy is bob-fleet-monitor. Usage numbers come from box-usage / Get-BobBoxUsage.ps1 -Hover.
---

# Fleet tray

`tools/Watch-BobTray.ps1` is the human monitor. `Install-BobFleet` registers it as `BobFleet-<id>` with `-STA -WindowStyle Hidden`. It starts hidden `Watch-BobJobs.ps1`. Do not leave a blank PowerShell window on the desktop.

## UI

- Idle: Font Awesome Free solid **robot** (CC BY 4.0), not grok.exe extract. Red/amber badge = ACTION_REQUIRED.
- Left-click: acknowledge. Right-click: Status, Open log, Exit.
- **Mouse-over**: dark card with a **context remaining** bar (from session `usage.json` uncached input vs model `context_window`). If usage is not recorded yet, the bar is empty — never fake 100%. Jobs list **machine**, GitHub repo, duration, state.
- Context remaining **< 10%**: icon pulses red once a minute.

Log: `~\.grok\long-running-background-tasks\watch_bob_tray.log`.

## Install / recycle

```powershell
powershell -NoProfile -File "$repo\tools\Install-BobFleet.ps1" -MachineId <id> -CwdRoots <roots>
```

Recycling the task **kills** the pull worker. Do not recycle while a job is running (see `bob-fleet-monitor`). Hover/flash code changes apply on the next tray start.

## Hard rules

- Not a Windows service.
- Do not print `auth.json` or tokens in the tooltip.
