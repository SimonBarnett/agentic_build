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
- Empty / overspent (Sand weekly exhausted): `cursor (-Â£x.xx)` in **red**.
  Money comes from Cursor `GetCurrentPeriodUsage`
  `spendLimitUsage.individualUsed` (USD cents), converted to GBP via live FX
  (`open.er-api.com`, fallback `cdn.jsdelivr.net`) â€” **not** `tip_cursor.json`
  and not "12% => Â£12".
- When remaining is null but overage exists, still emit the overage label
  (do not early-return null from `ConvertTo-BobCursorUsageDoc`).
- Machine tile bars still use xAI `unified.jsonl` weekly remaining.


## Reset dates

Show weekly reset next to the meter, not only in digests:

- **cursor** row: `reset DD Mon` from Cursor Sand `nextResetTimestampUtc`
  (via `Get-CursorAgentUsage.py` â†’ `period_end` â†’ `account_reset_label`).
- **Each machine tile**: that xAI seat's `currentPeriod.end` from
  `unified.jsonl` `billing: fetched credits config` (`Get-BobWeeklyRemaining`).
  Same-seat machines share one reset date (and one remaining %).
- Fleet share: IRC POINT includes `reset=YYYY-MM-DD`.
- Durable cache: `~\\.grok\\bob-bridge\\seat-period-end.json` (by_machine + by_seat) so TipForm keeps peer reset dates when IRC peer JSON is wiped. Import must **not** wipe
  an existing peer `period_end` when an older POINT lacks `reset=`.

Example headings:

`cursor (-Â£31.94) - reset 23 Sep`

`flamingo - Club Madeira (15%) - reset 27 Sep`

## UI hard rules (diagnostics 2026-09-20)

- **Click-only card.** Left-click (or Status menu) opens/parks the dark
  TipForm. **No hover** to show the card (hover caused double TipForm /
  ghost chips). Close only via **X**.
- **One TipForm only.** `NotifyIcon.Text` stays blank always
  (`Clear-BobNativeTip`). Never park `P+ idle` text â€” that white chip is the
  bad second dialog.
- **Single instance.** Mutex `Local\BobFleetTray-<machineId>`. Restart
  watcher kills every `Watch-BobTray` process (ghosts), rejoins `#bobiverse`,
  then starts exactly one tray.
- **No blank card on refresh.** In `Rebuild-BobTrayTiles`:
  1. Resolve/format every label and color **before** `Controls.Clear()`.
  2. Wrap Clear+Add under `SuspendLayout` / `ResumeLayout` only.
  3. **Never** use `WM_SETREDRAW` / `SendMessage(SetRedraw)` on TipForm â€”
     a mid-rebuild error with redraw left off blanks the card forever.
  4. TipForm is double-buffered (`DoubleBuffered` + optimized paint styles).
  5. Overage-red check is **inline** in `Watch-BobTray.ps1`
     (`label starts with '-' or contains Â£`). Do not call
     `Test-BobCursorOverageLabel` from the tray script (may be unloaded).
- **TipForm must compile.** Exactly one `DllImport` for `SendMessage` in the
  embedded C# TipForm. A duplicate P/Invoke prevents `Add-Type` and kills
  click/Status (no dialog).
- Icon: Font Awesome Free solid robot. `$notify.Visible = $true` must stay
  (missing icon = Visible never set / TipForm CreateHandle at startup).
- Do **not** preload `$script:tip.Handle` at startup.
- Footer: `alert: watcher|stall|weekly|none`.
- Log: `~\.grok\long-running-background-tasks\watch_bob_tray.log`.

## Install / recycle

```powershell
powershell -NoProfile -File "$repo\tools\Install-BobFleet.ps1" -MachineId <id> -CwdRoots <roots>
```

Copies `.grok/skills/*/SKILL.md` into `~\.grok\skills` via `Copy-BobProjectSkills`.

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
6. Click / Status does nothing: TipForm C# failed to compile â€” check for
   duplicate `SendMessage` P/Invoke or Add-Type errors in the log.
7. Refresh clears the card: rebuild cleared controls while redraw was
   suspended, or an exception after Clear â€” drop WM_SETREDRAW; format
   labels before Clear; ResumeLayout + Refresh always.
8. If card flashes on poll: verify SuspendLayout/ResumeLayout wraps
   `Rebuild-BobTrayTiles` (no SetRedraw).

## Hard rules

- Not a Windows service.
- Do not print auth.json or tokens.
- Do not invent weekly %. No billing HTTP scrape.
- Do not report session context as weekly quota.
- Job lines are GitHub owner/repo, never a commit SHA as primary label.
- Do not omit registered bobiverse seats. Do not invent jobs. Do not WinRM.

