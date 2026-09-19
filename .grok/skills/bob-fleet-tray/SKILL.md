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
- Left-click: acknowledge if flashing; **always show the dark card** (overflow-chevron fallback when hover is unreliable). Right-click: Status, Open log, Exit.
- **Mouse-over**: dark card. Hover uses `NotifyIcon.MouseMove` plus a 400ms icon-rect probe (`Shell_NotifyIconGetRect` cached on a timer — do **not** call it from the MouseMove callback). If the native `NotifyIcon.Text` tip is the only thing that appears, that is a fail.
  - Title: `Bob (<machineId>)` from this box's `machine.json` / `BOB_MACHINE_ID`.
  - **Context remaining** is the **session window** only: `(context_window - (inputTokens - cachedReadTokens)) / context_window` from that session's `usage.json` vs `models_cache`. If `usage.json` is missing, remaining is **unknown**: caption `n/a`, bar track and fill **hidden**. Never fake 100%. Never paint a depleted/empty bar (do not imply 0%) without `usage.json`.
  - **Weekly limit** is CLI-footer only (`Weekly limit left` in grok.exe). The tray does **not** show weekly %. There is no weekly field in BobBridge. Do not invent one. Do not read the context bar as weekly quota.
  - Jobs on **this machine**: machine, **id8**, GitHub repo, duration, state. Empty: `No jobs on this machine`.
  - Footer: `alert: watcher|stall|context|none`.
  - **Park once** (`Get-BobTrayTipPlacement`): on first show, set `Location` from the notify-icon rect (above-left, clamped to the working area). If the rect is unavailable, use the first MouseMove cursor offset only. While the card is **already visible**, do not re-invoke placement with new cursor coords and do not update `Location`. Restarting `hideTip` on MouseMove is OK. Hide via the existing hide timer / leave as today.
  - **No activate**: tip form is `ShowWithoutActivation` / `WS_EX_NOACTIVATE` (`0x08000000`). Show with `SetWindowPos` `SWP_NOACTIVATE|SWP_SHOWWINDOW` (`ShowParkedAt`); do not rely on `Form.Show()` alone.
  - **Log** show/hide failures (and successful first-show) to `watch_bob_tray.log`.

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
