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

Spending (`cursor.com/dashboard/spending`) has three included bars on the
TipForm (Simon labels; RTFM API fields in `tools/Get-CursorAgentUsage.py`):

| TipForm group | Spending / API source | Fuel |
|---|---|---|
| **grok chat** | `GetSandUsageStatus.usagePercent` → `cursor_spending_groups[id=grok-chat]` | `grok-bot` only (Sand). Not MRB/PR fuel. |
| **high cost models** | `GetCurrentPeriodUsage.planUsage.apiPercentUsed` | none for this loop |
| **low cost models** | `GetCurrentPeriodUsage.planUsage.autoPercentUsed` | `cursor-models` for MRB and PRs (`Get-BobCapacity.cursor_models.remaining_pct`) |

TipForm paints **three labelled bars** for this host's Cursor account (`grok
chat|high cost models|low cost models  N%`). xAI seats in `bob-seats.json`
(Smart Catalogue, Club Madeira, ntsa) are **not** Cursor quotas — do not prefix
Cursor bars with those labels (issue #151). Hover JSON: `cursor_groups` +
`cursor_pools` (three rows). Do not collapse into a single `Cursor Models`
strip.

Legacy names (docs before Sep 2026): Cursor Models ≈ low cost models; Other
Models ≈ high cost models; Grok Bot weekly ≈ grok chat.

20 Sep 2026 21:25: Cursor Models **1% used** (~99% left), Other Models 6%,
Grok Bot 100%. Tray wrongly showed `Cursor Models (-GBP 54.14)` (Sand overage).
Do not substitute overage GBP or Sand remaining for Cursor Models remaining.

| Signal | How |
|---|---|
| low cost models remaining % | Must match Spending `autoPercentUsed` (100 − used). `Get-BobCapacity.cursor_models.remaining_pct`. Do not invent. |
| grok chat remaining % | Sand `usagePercent` via `cursor_spending_groups` / `sand_remaining_pct`. |
| high cost models remaining % | `apiPercentUsed` via `cursor_spending_groups`. |
| Sand remaining % | `Get-BobCursorAgentWeeklyRemaining` / `tools\Get-CursorAgentUsage.py` → Sand `usagePercent`. Live confirm: `GrokBotApi.py post --service aiserver.v1.DashboardService --method GetSandUsageStatus`. This is **not** Cursor Models fuel. |
| Empty / 100% Sand | `usagePercent: 100` / Sand `remaining_pct` null. Grok Bot turns then `ACCEPTED_TEMPORAL` with **no** assistant `send-message` and **no** "limit reached" banner (Cursor bug). `hasAvailableUsage: true` + on-demand `enabled` does not mean they generate. Confirm Stripe: `GrokBotApi.py post --method ListGrokBotStripeLinkPaymentMethods`. `GROK_BOT_STRIPE_LINK_PAYMENT_METHODS_OUTCOME_NEEDS_AUTH` = on-demand cannot charge (box send 503). Cursor dashboard banner **You may have an unpaid invoice** + invoice Status **Open** is the same block (ionos 2026-09-20: Open mid-month 16 Sep cycle and Open 14 Sep cycle). Human pays Open invoices / finishes Stripe Link in billing settings. Not a RecreateSandBox fix — see `unstick-grok-bot`. |
| Empty / overspent | `overage_gbp` from `GetCurrentPeriodUsage.spendLimitUsage.individualUsed` (USD cents → GBP FX). Show as overage, **not** as Cursor Models remaining. Not tip_cursor.json fakes |
| Reset date | **Every** spending group row: `reset DD Mon`. `grok chat` → Sand `sand_period_end` / `nextResetTimestampUtc`; high/low cost → Spending `billingCycleEnd` / `period_end`. Do not leave reset only on low cost models. |
| Cache | `~\.grok\bob-bridge\cursor-agent-usage.json` (~15 min); delete to force refresh |

## TipForm wiring

`Get-BobTrayHover` sets `reset_label` on **each** of the three `cursor_pools`
rows, plus each machine tile. Cursor pool rows are indented like machines.
Overspend is right-aligned inside the tile host. First IRC connect announces
`{machine} is operational.`

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
