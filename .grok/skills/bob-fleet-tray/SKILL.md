---
name: bob-fleet-tray
description: >
  System tray icon for Bob Fleet on this Windows box: hidden PowerShell, Font
  Awesome free robot icon, weekly remaining bar, machine tiles with jobs
  listed underneath. Use when the user says tray icon, system tray, NotifyIcon,
  flash the watcher, hover remaining, mouse over tray, or /bob-fleet-tray.
  Stall policy is bob-fleet-monitor. Usage numbers come from box-usage /
  Get-BobBoxUsage.ps1 -Hover.
---

# Tray (Bob Fleet)

`tools/Watch-BobTray.ps1` is the human monitor for **this Windows box**. Title is **Bob Fleet**. Job data is the local BobBridge store (`Get-BobBuilds` on this host) grouped into **machine tiles**. There is no WinRM / remote health peek. If only this host is in the store, the card still uses the Bob Fleet title and tile layout, plus `other hosts not in this store`.

`Install-BobFleet` registers it as `BobFleet-<id>` with `-STA -WindowStyle Hidden`. It starts hidden `Watch-BobJobs.ps1`. Do not leave a blank PowerShell window on the desktop.

## UI

- Idle: Font Awesome Free solid **robot** (CC BY 4.0), not grok.exe extract.
- Left-click: acknowledge if flashing; **always show the dark card** (overflow-chevron fallback when hover is unreliable). Right-click: Status, Open log, Exit.
- **Mouse-over**: dark card. Hover uses `NotifyIcon.MouseMove` plus a 400ms icon-rect probe (`Shell_NotifyIconGetRect` cached on a timer — do **not** call it from the MouseMove callback). If the native `NotifyIcon.Text` tip is the only thing that appears, that is a fail.
  - Title: **Bob Fleet** (not `Bob (<machineId>)`).
  - **Weekly remaining** is the **primary** bar (fleet routing). Source: last `billing: fetched credits config` line in `~\.grok\logs\unified.jsonl`. `remaining_pct = round(100 - creditUsagePercent)` when `currentPeriod.type` is weekly and `creditUsagePercent` is present. Same number the Grok CLI footer shows as `Weekly limit left: N%`. If that field is missing: caption `Weekly remaining  n/a`, bar track and fill **hidden**. Never fake 100%. Never paint a depleted/empty bar (do not imply 0%) without a real weekly field. Do **not** read `auth.json`. Do **not** call a billing HTTP API. Do **not** use session context (233K/500K) as this bar.
  - Session context from `usage.json` is optional on the job object (`context_remaining_pct`) only. It is **not** the hover bar.
  - **Machine tiles**: one heading per machine id (this host first). Under each tile: running then queued jobs as `owner/repo  duration  state`. Prefer `git remote get-url origin` owner/repo; never show a bare commit SHA as the primary label. Empty tile: `  no jobs`.
  - Footer: `alert: watcher|stall|weekly|none`.
  - **Park once** (`Get-BobTrayTipPlacement`): on first show, set `Location` from the notify-icon rect (above-left, clamped to the working area). If the rect is unavailable, use the first MouseMove cursor offset only. While the card is **already visible**, do not re-invoke placement with new cursor coords and do not update `Location`. Restarting `hideTip` on MouseMove is OK. Hide via the existing hide timer / leave as today.
  - **No activate**: tip form is `ShowWithoutActivation` / `WS_EX_NOACTIVATE` (`0x08000000`). Show with `SetWindowPos` `SWP_NOACTIVATE|SWP_SHOWWINDOW` (`ShowParkedAt`); do not rely on `Form.Show()` alone.
  - **Log** show/hide failures (and successful first-show) to `watch_bob_tray.log`.
- Short `NotifyIcon.Text` (63 chars): weekly remaining + run count, e.g. `P+ 1 run  9%`. Omit the percent when weekly remaining is unknown.

## Badge sources

Never pulse weekly remaining when `remaining_pct` is null. Unknown remaining is not &lt;10%.

| `alert:` | Source | Badge |
|---|---|---|
| `watcher` | stall monitor `ACTION_REQUIRED: watcher_down` | red/amber flash |
| `stall` | `ACTION_REQUIRED: agent_stall` / `inbox_stale` / `running_orphan` | red/amber flash |
| `weekly` | weekly remaining **known** and &lt; 10% | amber pulse once a minute |
| `none` | no ACTION_REQUIRED; remaining unknown or ≥ 10% | idle robot |

Log: `~\.grok\long-running-background-tasks\watch_bob_tray.log`.

## Install / recycle

```powershell
powershell -NoProfile -File "$repo\tools\Install-BobFleet.ps1" -MachineId <id> -CwdRoots <roots>
```

Recycling the **scheduled task** **kills** the pull worker. Do not recycle `BobFleet-*` while a job is running (see `bob-fleet-monitor`). Hover/flash code changes: recycle **Watch-BobTray.ps1 only** (stop that process, start a new hidden STA `Watch-BobTray.ps1`). Never `Stop-ScheduledTask BobFleet-*` while jobs run.

## Hard rules

- Not a Windows service.
- Do not print `auth.json` or tokens in the tooltip.
- Do not invent weekly %. No billing HTTP scrape. Log field or n/a.
- Do not report session context as weekly quota.
- Job lines are GitHub `owner/repo`, never a commit SHA as the primary label.
