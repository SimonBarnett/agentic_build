---
name: box-usage
description: >
  Show Grok Build / Premium+ (xAI) and Grok Bot / Cursor Sand usage on a Windows
  box: weekly remaining %, reset dates, on-demand GBP overage, live grok
  processes, sessions, BobBridge jobs, and ~/.grok disk. Use when the user asks
  usage, quota, remaining, reset date, overage, how maxed, Premium+ headroom,
  Cursor Sand, unpaid invoice, paid their bill, or /box-usage. Pair with
  cursor-sand-billing when Grok Bot is silent at Sand 100%. Pair with bob-fleet-tray for the TipForm card and
  grok-build-fleet when choosing ionos vs marchhare vs flamingo.
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
# Cursor / Grok Bot Sand remaining + GBP overage + reset:
Get-BobCursorAgentWeeklyRemaining
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

## Cursor / Grok Bot Sand (account row)

| Signal | How |
|---|---|
| Remaining % | `Get-BobCursorAgentWeeklyRemaining` / `tools\Get-CursorAgentUsage.py` → Sand `usagePercent`. Live confirm: `GrokBotApi.py post --service aiserver.v1.DashboardService --method GetSandUsageStatus` |
| Empty / 100% | `usagePercent: 100` / `remaining_pct` null. Grok Bot turns then `ACCEPTED_TEMPORAL` with **no** assistant `send-message` and **no** "limit reached" banner (Cursor bug). `hasAvailableUsage: true` + on-demand `enabled` does not mean they generate. Confirm Stripe: `GrokBotApi.py post --method ListGrokBotStripeLinkPaymentMethods`. `GROK_BOT_STRIPE_LINK_PAYMENT_METHODS_OUTCOME_NEEDS_AUTH` = on-demand cannot charge (box send 503). Cursor dashboard banner **You may have an unpaid invoice** + invoice Status **Open** is the same block (ionos 2026-09-20: Open mid-month 16 Sep cycle and Open 14 Sep cycle). Human pays Open invoices / finishes Stripe Link in billing settings. Not a RecreateSandBox fix — see `unstick-grok-bot`. |
| Empty / overspent | `overage_gbp` from `GetCurrentPeriodUsage.spendLimitUsage.individualUsed` (USD cents → GBP FX). TipForm shows red `-£x.xx` — not tip_cursor.json fakes |
| Reset date | Sand `nextResetTimestampUtc` → `period_end` → `reset DD Mon` |
| Cache | `~\.grok\bob-bridge\cursor-agent-usage.json` (~15 min); delete to force refresh |

## TipForm wiring

`Get-BobTrayHover` sets `account_reset_label` and each machine's `reset_label`.
`Watch-BobTray` appends them on the cursor row and every seat tile.

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
