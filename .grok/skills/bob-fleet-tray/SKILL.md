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
See `docs/bob-fleet-peer-peek.md`. Tiles may show `not in moot` or
`lastSeen stale`; do not invent `unreachable` for a seat that is merely
not in the moot.

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

## Cursor spending groups (this host's Cursor account)

**Three RTFM groups** on the card (not xAI seat names — Smart Catalogue /
Club Madeira / ntsa are Grok Build seats only; issue #151):

1. `grok chat  {N%|n/a}` — Sand (`GetSandUsageStatus.usagePercent`)
2. `high cost models  {N%|n/a}` — `planUsage.apiPercentUsed`
3. `low cost models  {N%|n/a}` — `planUsage.autoPercentUsed` (+ reset on this
   row). MRB/PR fuel gate reads **low cost models** only.

Do **not** collapse groups into one `Cursor Models` strip. Do **not** prefix
those rows with xAI seat labels. Local
`Get-BobCursorAgentWeeklyRemaining` + `cursor_spending_groups` fill this
host; digest `pcent` / `cursor_pools` update `cursor-pools.json` cache but
the tray paints **one trio of bars for this machine's Cursor login**.
`!report PCENT` (irc #36 digest in `bob-peers/_report-digest.json`) can
refresh a pool without a redraw storm.

Fleet peer freshness: `Watch-Bobiverse` polls `!bobiverse` (~120s). Chair
whispers **`BOB DIGEST v1`** JSON (`i/n` chunks when large); `Import-BobIrcTrayPull`
writes tray-complete `bob-peers\*.json`, `_report-digest.json`, and cursor pool
cache — not POINT, not a presence-only digest.

`account_remaining_pct` on `Get-BobTrayHover` is this host's **low cost models**
remaining (MRB fuel gate). Machine rows are Grok Build weekly + fuels
(`cursor-models`, `grok-build`, `copilot`, `grok-bot`).

- Known remaining: each group bar shows N% from Spending (see `box-usage`), not
  Sand overage mislabelled as low cost models.
- Do **not** label Grok Bot Sand overage as Cursor Models remaining. Overage
  GBP from `GetCurrentPeriodUsage.spendLimitUsage.individualUsed` (USD cents
  → GBP FX, not `tip_cursor.json`) is a separate signal. Show it as overage,
  not as the fuel remaining figure.
- Empty Cursor Models remaining (0%): then fuel falls through to grok.exe.
  Sand 100% does not by itself mean Cursor Models is empty.
- Machine tile bars still use xAI `unified.jsonl` weekly remaining
  (`creditUsagePercent` on `billing: fetched credits config`).
- Numbers: `box-usage`.


## Reset dates

Show weekly reset next to the meter, not only in digests:

- **Cursor Models** row: `reset DD Mon` from the Cursor Models period
  (`period_end` → `account_reset_label`). Do not use Grok Bot Sand reset
  as a stand-in when the Cursor Models bar is what the fuel gate reads.
- **Each machine tile**: that xAI seat's `currentPeriod.end` from
  `unified.jsonl` `billing: fetched credits config` (`Get-BobWeeklyRemaining`).
  Same-seat machines share one reset date (and one remaining %).
- Fleet share: IRC POINT includes `reset=YYYY-MM-DD`.
- Durable cache: `~\\.grok\\bob-bridge\\seat-period-end.json` (by_machine + by_seat) so TipForm keeps peer reset dates when IRC peer JSON is wiped. Import must **not** wipe
  an existing peer `period_end` when an older POINT lacks `reset=`.

Example headings:

`low cost models  9%  reset 23 Sep`

`flamingo  -  Club Madeira (15%) - reset 27 Sep`

Job lines under a machine (local jobs or `!report` digest):

`START  SimonBarnett/agentic_irc  395c499  composer-2.5  report digest  1m52s`

No `grok.exe ? running` when repo/sha exist on the packet. When digest
`workers` / `working_on` or live `bob-*` / `{machine}-{seatPid}` nicks are on
IRC, paint a **START** line (not `no jobs`). Idle machine with no IRC workers:
`no jobs`.

Do not show `Cursor Models (-GBP x.xx)` as the remaining figure. That was
Sand overage mislabelled (20 Sep 2026 tray vs Spending).

## UI hard rules (diagnostics 2026-09-20)

- **Click-only card.** Left-click (or Status menu) opens/parks the dark
  TipForm via `ShowParkedAt`. **No hover** to show the card (hover caused
  double TipForm / ghost chips). Close only via **X**. No `hideTip` auto-hide.
- **One TipForm only.** `NotifyIcon.Text` stays blank always
  (`Clear-BobNativeTip`). Never park `P+ idle` text â€” that white chip is the
  bad second dialog.
- **Single instance.** Mutex `Local\BobFleetTray-<machineId>`. Restart
  watcher kills every `Watch-BobTray` process (ghosts), rejoins `#bobiverse`
  via `_Watch-Bobiverse-<id>` (ionos: `_Watch-Bobiverse-ionos.ps1` or that
  scheduled task), then starts exactly one tray.
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

Card place: `Get-BobTrayTipPlacement` (icon rect, then sticky when already visible, else cursor). TipForm uses `ShowWithoutActivation` / WS_EX_NOACTIVATE.

## Diagnose (when the card/icon misbehaves)

1. Count `Watch-BobTray` processes â€” more than one â†’ kill all, start one.
2. Log tail `watch_bob_tray.log` for `tray up`, `tip show ok`, poll errors.
3. Confirm `$notify.Visible` path still sets Visible=$true after start.
4. Confirm `NotifyIcon.Text` is empty (no white P+ chip).
5. Confirm title `#Bobiverse (<id>)`, Cursor Models remaining % on the top
   bar (not Sand overage), seat labels beside names, shared % on ntsa seats.
6. Click / Status does nothing: TipForm C# failed to compile â€” check for
   duplicate `SendMessage` P/Invoke or Add-Type errors in the log.
7. Refresh clears the card: rebuild cleared controls while redraw was
   suspended, or an exception after Clear â€” drop WM_SETREDRAW; format
   labels before Clear; ResumeLayout + Refresh always.
8. If card flashes on poll: verify SuspendLayout/ResumeLayout wraps
   `Rebuild-BobTrayTiles` (no SetRedraw).

## Agents menu

The context menu has an **Agents** submenu (the two watch-seat agents as one
menu; select which). Each entry (Cursor, Grok) uses the **same icon as its
Desktop shortcut** (`Icon.ExtractAssociatedIcon` on the agent `.exe`). Not
installed -> greyed icon, click **initialises setup**
(`tools/Install-AgentMonitor.ps1`); installed -> click launches
`Watch-AgentHealth.cmd <cursor|grok>`. Owner skill: `agent-monitor-setup`.

## Hard rules

- Not a Windows service.
- Do not print auth.json or tokens.
- Do not invent weekly %. No billing HTTP scrape.
- Do not report session context as weekly quota.
- Job lines are GitHub owner/repo, never a commit SHA as primary label.
- Do not omit registered bobiverse seats. Do not invent jobs. Do not WinRM.

