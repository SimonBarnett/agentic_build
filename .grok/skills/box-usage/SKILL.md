---
name: box-usage
description: >
  Show current Grok Build / Premium+ usage on this Windows box: subscription
  tier, live grok processes, active sessions, BobBridge jobs, ~/.grok disk, and
  per-session token/cost when recorded. Use when the user or Bob asks usage,
  quota, how maxed is this machine, Premium+ headroom, token burn, disk under
  .grok, or /box-usage. Pair with grok-build-fleet when choosing ionos vs marchhare.
---

# Box usage (this machine)

Run on the **target** Windows box via local-exec (ionos, marchhare, dev1). Do not guess another host's quota from chat.

## One-shot report

```powershell
$repo = if (Test-Path 'C:\ai\agentic_build') { 'C:\ai\agentic_build' } elseif (Test-Path 'D:\ai\agentic_build') { 'D:\ai\agentic_build' } else { 'C:\src\agentic_build' }
powershell -NoProfile -ExecutionPolicy Bypass -File "$repo\tools\Get-BobBoxUsage.ps1"
# machine-readable:
powershell -NoProfile -ExecutionPolicy Bypass -File "$repo\tools\Get-BobBoxUsage.ps1" -Json
# tray hover JSON (Bob Fleet title, weekly remaining bar, machine tiles):
powershell -NoProfile -ExecutionPolicy Bypass -File "$repo\tools\Get-BobBoxUsage.ps1" -Hover
```

Paste the text report (or JSON) back. Never paste `auth.json` or bearer tokens.

## What it covers

| Signal | Source |
|---|---|
| Subscription display (e.g. X Premium+) | `~\.grok\settings_cache.json` → `settings.subscription_tier_display` |
| **Weekly remaining %** | Last `billing: fetched credits config` in `~\.grok\logs\unified.jsonl` → `100 - creditUsagePercent` (CLI footer `Weekly limit left: N%`) |
| Grok CLI / watcher / worker_count | `Get-BobHealth` when BobBridge is installed |
| Live `grok.exe` | `Get-Process grok` |
| Active sessions | `~\.grok\active_sessions.json` + `grok sessions list` |
| BobBridge lanes | `Get-BobBuilds` (queued/running) when available |
| Disk under `~\.grok` | `grok du --json` |
| Token / cost for a finished session | `grok usage <SESSION_ID>` |

## Manual commands

```powershell
$g = Join-Path $env:USERPROFILE '.grok\bin\grok.exe'
& $g du --json
& $g sessions list
& $g usage <SESSION_ID>          # after the session has persisted usage; mid-run often empty
Import-Module ...\BobBridge.psd1
Get-BobHealth
Get-BobBuilds -Machine <id>
Get-BobWeeklyRemaining
Get-BobTrayHover
```

## How to read it for fleet routing

- Prefer a box whose `subscription_tier_display` is Premium+ / SuperGrok **and** that is not already burning many parallel `grok.exe` workers.
- MarchHare personal X maxed → route new builds to `ionos` (dedicated Premium+).
- High `~\.grok` sessions/downloads size → consider `grok worktree gc --max-age 7d --dry-run` before reclaiming (see `grok du --help`).
- `grok usage` with "No usage recorded" on a **running** job is normal; re-check when the job finishes.
- Tray hover (`Get-BobTrayHover`) title is **Bob Fleet**. `scope=fleet-peek` when any peer is registered, else `local-store`. Primary bar is **weekly remaining** from the CLI billing log (`creditUsagePercent`). If that field is missing, remaining is unknown (`n/a`) — not 100% and **not 0%**. Do not paint a depleted bar without a real weekly field. Pulse amber when **known** weekly remaining &lt; 10%.
- Jobs are grouped by **machine tile** for every registered host (see `docs/bob-fleet-peer-peek.md`). Each job line is GitHub `owner/repo`, duration, state — never a commit SHA as the primary label. Registered peer with a failed peek is `  unreachable`, not omitted.
- Session context `(window - (inputTokens - cachedReadTokens)) / window` from `usage.json` is **not** the hover bar. Do not treat context 233K/500K as weekly quota.
- **Weekly limit** is the CLI billing log field above (same as the grok.exe footer). Do not invent a weekly %. Do not call a billing HTTP API. Do not read `auth.json`.

## Hard rules

- Do **not** print or commit contents of `auth.json`.
- Do **not** invent remaining-token counts the CLI does not expose.
- Do **not** invent a weekly-limit API. Weekly % is the CLI billing log `creditUsagePercent` or n/a.
- Report facts from this host only. Do not say "no fleet jobs" when the store is local-only.
