---
name: bob-fleet-tray
description: >
  System tray icon for Bob Fleet / bobiverse on this Windows box: hidden
  PowerShell NotifyIcon, Font Awesome robot, dark TipForm card. Use when the
  user says tray icon, system tray, Bob Fleet card, #Bobiverse, systray,
  NotifyIcon, flash the watcher, recycle tray, or /bob-fleet-tray. Stall
  policy is bob-fleet-monitor. Usage numbers come from box-usage /
  Get-BobBoxUsage.ps1 -Hover.
---

# Tray (Bob Fleet / #Bobiverse)

`tools/Watch-BobTray.ps1` is the human monitor. Card title is
`#Bobiverse (<machineId>)` from `Get-ThisMachineId` / `$env:BOB_MACHINE_ID`
(bobiverse nick: ionos / flamingo / marchhare / ce-priority-dev1), not the
Windows hostname and not the old "Bob Fleet" string.

When `config/bobiverse.json` has `nicks`, the card lists **only those machine
ids** plus this host if it is one of them. Never a ghost IRC-derived name
(`marchhare-bugets`). Without nicks (hermetic tests), fall back to
`config/fleet-registry.json` + `{BOB_BRIDGE_HOME}\fleet\registry.json`.
Transport is read-only filesystem peek plus IRC moot roster. No WinRM.

## Seat deals (next to the name)

`config/bob-seats.json` (and/or `config/fleet-registry.json` `seats`) maps
machines to xAI seats. Tile heading is `MACHINENAME - SEAT (N%)`:

| Seat label | Account | Machines |
|---|---|---|
| Smart Catalogue | social@smartcatalogue.uk | ionos |
| Club Madeira | social@clubmadeira.uk | flamingo |
| ntsa | si@ntsa.uk | marchhare, ce-priority-dev1 |

Machines on the **same seat share one weekly remaining %** (account-level).
Do not show divergent % for marchhare vs ce-priority-dev1. Prefer the
conservative (lowest) known remaining for that seat.

Never set `XAI_API_KEY` on DEV1; both ntsa boxes use OIDC session
(`si@ntsa.uk`).

## Cursor overage row

Top account row is **Grok Bot / Cursor Sand**, not the xAI Build seat.

- Known remaining: `cursor (N%)` in normal foreground.
- Empty / overspent (Sand weekly exhausted): `cursor (-£x.xx)` in **red**. Money comes from Cursor `GetCurrentPeriodUsage` `spendLimitUsage.individualUsed` (USD cents), converted to GBP via live FX — **not** `tip_cursor.json` and not "12% => £12".
- Machine tile bars still use xAI `unified.jsonl` weekly remaining.

## UI hard rules (diagnostics 2026-09-20)

- **Click-only card.** Left-click (or Status menu) opens/parks the dark
  TipForm. **No hover** to show the card (hover caused double TipForm /
  ghost chips). Close only via **X**.
- **One TipForm only.** `NotifyIcon.Text` stays blank always
  (`Clear-BobNativeTip`). Never park `P+ idle â€¦` â€” that white chip is the
  bad second dialog.
- **Single instance.** Mutex `Local\BobFleetTray-<machineId>`. Restart
  watcher kills every `Watch-BobTray` process (ghosts), rejoins `#bobiverse`,
  then starts exactly one tray.
- **No flash on refresh.** Poll/`Update-Hover` rebuilds tiles under
  `Suspend-BobTrayPaint` (WM_SETREDRAW off + SuspendLayout), then
  `Resume-BobTrayPaint` (redraw on + Invalidate/Update). TipForm and
  tileHost are double-buffered. Never Clear+Add controls while the form is
  painting live without suspending redraw.
- Icon: Font Awesome Free solid robot. `$notify.Visible = $true` must stay
  (missing icon = Visible never set / TipForm CreateHandle at startup).
- Do **not** preload `$script:tip.Handle` at startup.
- Footer: `alert: watcher|stall|weekly|none`.
- Log: `~\.grok\long-running-background-tasks\watch_bob_tray.log`.

## Install / recycle

```powershell
powershell -NoProfile -File "$repo\tools\Install-BobFleet.ps1" -MachineId <id> -CwdRoots <roots>
```

Ionos wrapper: `tools\_Watch-BobTray-ionos.ps1` sets `BOB_MACHINE_ID=ionos`
and bobiverse IRC home, then runs `Watch-BobTray.ps1`.

Hover/flash/card code changes: recycle **Watch-BobTray only** (kill that
process, start one hidden STA instance). Do not `Stop-ScheduledTask
BobFleet-*` while build jobs run.

## Diagnose (when the card/icon misbehaves)

1. Count `Watch-BobTray` processes â€” more than one â†’ kill all, start one.
2. Log tail `watch_bob_tray.log` for `tray up`, `tip show ok`, poll errors.
3. Confirm `$notify.Visible` path still sets Visible=$true after start.
4. Confirm `NotifyIcon.Text` is empty (no white P+ chip).
5. Confirm title `#Bobiverse (<id>)`, cursor `-Â£x.xx` red when overspent,
   seat labels beside names, shared % on ntsa seats.
6. If card flashes on poll: verify Suspend/Resume paint wraps
   `Rebuild-BobTrayTiles`.

## Hard rules

- Not a Windows service.
- Do not print auth.json or tokens.
- Do not invent weekly %. No billing HTTP scrape.
- Do not report session context as weekly quota.
- Job lines are GitHub owner/repo, never a commit SHA as primary label.
- Do not omit registered bobiverse seats. Do not invent jobs. Do not WinRM.

