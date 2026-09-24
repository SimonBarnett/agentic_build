---
name: box-usage
description: >
  Show Cursor Models remaining % (the MRB/PR fuel), Grok Build / Premium+
  (xAI), and Grok Bot / Cursor Sand on a Windows box: remaining %, reset
  dates, on-demand GBP overage, live grok processes, sessions, BobBridge
  jobs, and ~/.grok disk. Use when the user asks usage, quota, remaining,
  Cursor Models, reset date, overage, how maxed, Premium+ headroom, Cursor
  Sand, unpaid invoice, paid their bill, or /box-usage. Pair with
  cursor-sand-billing when Grok Bot is silent at Sand 100%. Pair with
  bob-fleet-tray for the TipForm card and grok-build-fleet when choosing
  ionos vs marchhare vs flamingo.
---

# Box usage (this machine)

Run on the **target** Windows box via local-exec (ionos, flamingo, marchhare,
ce-priority-dev1). Do not guess another host's quota from chat.

## One-shot report

```powershell
$repo = if (Test-Path 'C:\ai\agentic_build') { 'C:\ai\agentic_build' } elseif (Test-Path 'D:\ai\agentic_build') { 'D:\ai\agentic_build' } else { 'C:\src\agentic_build' }
Import-Module "$repo\src\BobBridge.psd1" -Force
# xAI / Grok Build weekly remaining + reset:
Get-BobWeeklyRemaining
# Cursor Models remaining (MRB/PR fuel) + Sand + GBP overage + reset:
Get-BobCursorAgentWeeklyRemaining
Get-BobCapacity | Select-Object -ExpandProperty cursor_models
# Full tray hover JSON (title, cursor row, machine tiles with seat + reset):
Get-BobTrayHover | ConvertTo-Json -Depth 6
# Or:
powershell -NoProfile -ExecutionPolicy Bypass -File "$repo\tools\Get-BobBoxUsage.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$repo\tools\Get-BobBoxUsage.ps1" -Hover
```

Never paste `auth.json`, sand-secrets, or bearer tokens.

## xAI / Grok Build (per seat)

| Signal | How |
|---|---|
| Weekly remaining % | `Get-BobWeeklyRemaining` → `remaining_pct` from last `billing: fetched credits config` in `~\.grok\logs\unified.jsonl` (`100 - creditUsagePercent`, period type WEEKLY only) |
| Reset date | Same doc → `period_end` (`currentPeriod.end`). Format for UI: `Format-BobResetLabel` → `reset DD Mon` (UK local) |
| Seat map | `config/bob-seats.json`: ionos=Smart Catalogue, flamingo=Club Madeira, marchhare+ce-priority-dev1=ntsa (si@ntsa.uk). Same seat → one shared remaining % (min) and one shared reset |
| Publish to fleet | `Write-BobIrcStatus` writes `weekly` + `period_end` and POINT `reset=YYYY-MM-DD` |

## Cursor dashboard meters (do not mix)

Spending (`cursor.com/dashboard/spending`) included meters on the TipForm
(Simon labels; API in `tools/Get-CursorAgentUsage.py`):

| TipForm group | Spending / API source | Fuel |
|---|---|---|
| **grok chat** | `GetSandUsageStatus.usagePercent` → `cursor_spending_groups[id=grok-chat]` | `grok-bot` only (Sand). Not MRB/PR fuel. |
| **high cost models** | `GetCurrentPeriodUsage.planUsage.apiPercentUsed` | named / Other Models |
| **auto** | `planUsage.autoPercentUsed` (Auto picker / `autoBucketModels`) | `cursor-models` for MRB and PRs |

**Auto** is the pool when the model is Auto — not on-demand. Docs: Auto bills
at the routed model's list price from **Cursor Models** (and Other Models if
the router picks third-party). Do **not** paint an on-demand usage bar; header
`overspend £…` (USD cents → GBP, right-aligned in the tile host) covers
spend-limit pay-as-you-go.

TipForm paints **three labelled bars**. Hover JSON: `cursor_pools` (three
rows). Legacy: low cost models ≈ auto; Cursor Models ≈ auto.

| Signal | How |
|---|---|
| auto remaining % | Must match Spending `autoPercentUsed` (100 − used). `Get-BobCapacity.cursor_models.remaining_pct`. |
| grok chat remaining % | Sand `usagePercent` via `cursor_spending_groups` / `sand_remaining_pct`. |
| high cost models remaining % | `apiPercentUsed` via `cursor_spending_groups`. |
| Empty / overspent GBP | `overage_gbp` from `spendLimitUsage.individualUsed` — header only, not a bar. |
| Reset date | **Every** spending group row: `reset DD Mon`. `grok chat` → Sand `sand_period_end`; high/auto → `billingCycleEnd`. |
| Cache | `~\.grok\bob-bridge\cursor-agent-usage.json` (~15 min); delete to force refresh |

## TipForm wiring

`Get-BobTrayHover` sets `reset_label` on **each** of the three `cursor_pools`
rows, plus each machine tile. Overspend is right-aligned inside the tile host
(host width − text − 2px). Agent section icons resolve Desktop `.lnk` then
Program Files `Grok Bot` / Cursor exe (`ExtractAssociatedIcon` plated on a
light chip).

## Other signals

| Signal | Source |
|---|---|
| Subscription display (e.g. X Premium+) | `~\.grok\settings_cache.json` → `settings.subscription_tier_display` |
| Live `grok.exe` | `Get-Process grok` / `Get-BobLiveGrokAgents` |
| BobBridge lanes | `Get-BobBuilds` when available |
| Disk under `~\.grok` | `grok du --json` |

## Hard rules

- Do not invent weekly % or reset dates.
- Do not print tokens or auth.json.
- DEV1 must not use `XAI_API_KEY` (OIDC session, same ntsa seat as marchhare).
