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
# tray hover JSON (this-machine jobs + session context remaining; not weekly quota):
powershell -NoProfile -ExecutionPolicy Bypass -File "$repo\tools\Get-BobBoxUsage.ps1" -Hover
```

Paste the text report (or JSON) back. Never paste `auth.json` or bearer tokens.

## What it covers

| Signal | Source |
|---|---|
| Subscription display (e.g. X Premium+) | `~\.grok\settings_cache.json` → `settings.subscription_tier_display` |
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
```

## How to read it for fleet routing

- Prefer a box whose `subscription_tier_display` is Premium+ / SuperGrok **and** that is not already burning many parallel `grok.exe` workers.
- MarchHare personal X maxed → route new builds to `ionos` (dedicated Premium+).
- High `~\.grok` sessions/downloads size → consider `grok worktree gc --max-age 7d --dry-run` before reclaiming (see `grok du --help`).
- `grok usage` with "No usage recorded" on a **running** job is normal; re-check when the job finishes.
- Tray hover (`Get-BobTrayHover`) is **this machine only** (`scope=this-machine`, title `Bob (<id>)`). It lists local running jobs with machine, **id8**, repo, duration, state. Remaining is **session context** `(window - (inputTokens - cachedReadTokens)) / window` from session `usage.json`. If that file is missing, remaining is unknown (`n/a`) — not 100% and **not 0%**. Do not paint a depleted bar without `usage.json`. Pulse amber when **known** remaining < 10%.
- **Weekly limit** (`Weekly limit left` in the grok.exe CLI footer) is **not** on the tray and **not** in BobBridge. Do not invent a weekly %. Read it from the CLI footer on that box. Never treat the context bar as weekly quota.

## Hard rules

- Do **not** print or commit contents of `auth.json`.
- Do **not** invent remaining-token counts the CLI does not expose.
- Do **not** invent a weekly-limit API. Weekly % is CLI-footer only.
- Report facts from this host only. Do not say "no fleet jobs" when the store is local-only.