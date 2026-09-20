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

`tools/Watch-BobTray.ps1` is the human monitor. Title is **Bob Fleet**. The card lists **every registered fleet machine** (bundled `config/fleet-registry.json` + `{BOB_BRIDGE_HOME}\fleet\registry.json` + local `fleet/machines`), this host first. Under each tile: running then queued jobs **on that machine**. Transport is read-only filesystem peek (`docs/bob-fleet-peer-peek.md`). No WinRM. Status is the `#bobiverse` MODE2 roster, not SMB. Tile stays for every registered peer. Empty in-moot tile: `  no jobs`. Not on the moot roster: `  not in moot` (do not say `unreachable` unless they are not in the moot). Readable store, old heartbeat: `  lastSeen stale`. Never invent jobs. Never omit a registered peer.

`Install-BobFleet` registers it as `BobFleet-<id>` with `-STA -WindowStyle Hidden`. It starts hidden `Watch-BobJobs.ps1`. Do not leave a blank PowerShell window on the desktop.

## UI

- Idle: Font Awesome Free solid **robot** (CC BY 4.0), not grok.exe extract.
- Left-click: acknowledge if flashing; **always show the dark card** (overflow-chevron fallback when hover is unreliable). Right-click: Status, Open log, Exit.
- **Mouse-over**: dark card. Hover uses `NotifyIcon.MouseMove` plus a 400ms icon-rect probe (`Shell_NotifyIconGetRect` cached on a timer — do **not** call it from the MouseMove callback). If the native `NotifyIcon.Text` tip is the only thing that appears, that is a fail.
  - Title: **Bob Fleet** (not `Bob (<machineId>)`).
  - **Cursor account row** under the title: pointer icon to the left of a full-width weekly bar, heading `cursor (N%)`. This is the **Grok Bot / Cursor-agent** account (`Get-BobCursorAgentWeeklyRemaining`, `percentUsed` → remaining = 100−used). It is **not** the Grok Build xAI seat. Machine tiles use xAI `unified.jsonl` `creditUsagePercent`. Then **indent** machine tiles under that.
  - **One weekly remaining bar per machine tile** (each box has its own Grok seat). Heading `MACHINENAME (75%)` uses a **transparent** label so it does not cover the bar. Bar fill is a gradient: **100% green, 0% red** (amber in the middle). This host: last `billing: fetched credits config` in `~\.grok\logs\unified.jsonl`, `remaining_pct = round(100 - creditUsagePercent)` when `currentPeriod.type` is weekly. Peers: `weekly=` on their `BOB v1` POINT. Unknown weekly: empty track, `(n/a)`. Never fake 100%. No `auth.json`. No billing HTTP. Session context is not this bar.
  - **One card only.** While the dark card is visible, `NotifyIcon.Text` is blank so Windows does not stack the native `P+ idle` tip on top of it.
  - **X** on the card closes it (`Hide-BobTrayCard`). Hover does not re-open until the cursor leaves the icon.
  - Session context from `usage.json` is optional on the job object (`context_remaining_pct`) only. It is **not** the hover bar.
  - **Machine tiles**: heading `MACHINENAME (75%)` or `(n/a)`, full-width weekly bar beneath, then indented jobs (`owner/repo  duration  state`). Empty in-moot: `  no jobs`. Not in the `#bobiverse` roster: `  not in moot`. Stale heartbeat: `  lastSeen stale`. Never a commit SHA as the primary label.
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
- Do not omit registered peers. Do not invent jobs. Do not WinRM. Recycle Watch-BobTray only after hover/peek code changes.
