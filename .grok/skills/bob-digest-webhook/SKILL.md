---
name: bob-digest-webhook
description: >
  Fleet digest at https://irc.ntsa.uk/bob/v1/report: shape, who POSTs pcent,
  who consumes cursor_pools, and the accuracy checklist. Use when the user
  says digest webhook, reportUrl, pcent, cursor_pools, TipForm n/a,
  MarchHare Cursor, fingerprint, _digest-webhook-posted.json, or
  /bob-digest-webhook. Paint rules: bob-fleet-tray. Local meters: box-usage.
  Chair: bob-jeeves-chair. Fuel pick: bob-token-handoff. Do not invent
  usage numbers.
---

# Digest webhook

Code for the TipForm consume path is PR #306
(https://github.com/SimonBarnett/agentic_build/pull/306). This skill is the
recipe. Do not re-derive the URL or the group map.

## Endpoint

| | |
|---|---|
| URL | `https://irc.ntsa.uk/bob/v1/report` |
| Config | `config/bobiverse.json` `reportUrl` (same string) |
| GET | `Get-BobDigestUrl`. Env override: `AGENTIC_IRC_DIGEST_URL`, then `BOB_DIGEST_URL`. Default after PR #306 is the HTTPS report URL. The old `http://bob.ntsa.uk/bob/v1/digest` default 404'd. Do not use it. |
| POST | `Get-BobDigestReportUrl`: `reportUrl`, else `BOB_REPORT_URL`, else `AGENTIC_IRC_REPORT_URL`. |
| Auth | Header `X-Bob-Secret` from `BOB_REPORT_SECRET` or `~\.grok\bob\report.secret`. Never git, never the JSON body. |
| Verb | POST `op=merge` on a real peer delta (`Send-BobDigestWebhookIfChanged`). GET is read-only for TipForm / fuel. Do not HTTP GET as the publish path. |
| Git hook | `https://irc.ntsa.uk/bob/v1/git` is a different URL (`setup-github-webhooks`). Do not POST digest merges there. |

Cache: `Read-BobReportDigestHttp` holds the GET for 60 seconds.

## Who publishes

Every `bob-*` builder with a Cursor login runs `Write-BobIrcStatus` (Watch-Bobiverse, ~30s) and **must POST `pcent`** when spending groups are known. MarchHare has no Cursor login: it consumes; it does not invent local Cursor percents.

`Write-BobIrcStatus` builds `pcent` from `cursor_spending_groups` (PR #306):

| Local group id | `pcent` key |
|---|---|
| `auto` or `low-cost-models` | `cursor-models` |
| `high-cost-models` | `high-cost-models` |
| `grok-chat` | `grok-chat` |
| `sand_remaining_pct` | overwrites `grok-chat` |
| `on_demand_remaining_pct` | `on-demand` (not a TipForm bar) |

Fingerprint (`Get-BobDigestWebhookFingerprint`) includes the `pcent` JSON and
`weekly` / `period_end`. Merge payload (`Build-BobDigestWebhookMergePayload`)
copies `weekly`, `period_end`, and `pcent` through. A weekly-only or pcent-only
change must POST.

**agentic_build #387 / gh-Jeeves:** the chair `op=merge` handler must **persist**
`machines.<id>.weekly` and `period_end` (xAI `Get-BobWeeklyRemaining`). If GET
digest shows workers but no weekly while local hover shows weekly remaining,
the chair was dropping those fields — fixed in gh-Jeeves PR that lands
`coerce_machine` + merge for weekly/period_end. MarchHare may have empty
`pcent` (no Cursor login) and still must show weekly.

State file: `{IRC home}\bob-peers\_digest-webhook-posted.json` (`Get-BobDigestWebhookPostStatePath`). If that fingerprint equals the current doc, the next tick does not POST. **When the fingerprint blocks a needed republish** (pcent added in code but the state file predates it, or the chair is stale while the fingerprint still matches), delete `_digest-webhook-posted.json` and let the next `Write-BobIrcStatus` POST. Do not hand-edit the percent inside that file.

Hermetic capture (no live HTTP): `BOB_DIGEST_WEBHOOK_CAPTURE` = an ndjson path. Test-Pack uses it. Do not point it at a live box during a test.

## Who consumes

TipForm on every seat, including MarchHare:

- GET the report URL.
- Apply digest `cursor_pools` and each machine's `pcent`.
- Spending groups are fleet-shared. Fan pool ids out to every seat **except** named xAI seats `smart-catalogue`, `club-madeira`, `ntsa` (those stay per-seat).
- Group aliases (`Normalize-BobCursorSpendingGroupId`, PR #306): `grok-weekly` / `grok_weekly` / `sand` / `grok-chat` -> `grok-chat`; `other-models` / `other_models` / `high-cost-models` -> `high-cost-models`; `cursor-models` / `low-cost-models` / `auto` / `on-demand` / `overage` -> `auto`.
- Also accept chair whisper `BOB DIGEST v1` (`Import-BobIrcTrayPull`) into `bob-peers\`. HTTP digest is the path that fills a host with no local Cursor login.

Paint: `bob-fleet-tray`. Three bars only. No on-demand bar.

## Document shape (no sample numbers)

POST body (change-only merge):

```
op, machine, online, status
weekly, period_end, cursor_label, cursor_period_end
remaining_pct / account_remaining_pct / cursor_remaining_pct
pcent: { cursor-models, high-cost-models, grok-chat, on-demand }
running, queued, jobs[{repo, state}]
model, kind, repo, sha, fuel, working_on, responding
```

GET / chair digest (what TipForm reads):

```
v, ts, chairNick
cursor_pools[{ id, group|group_id, remaining|remaining_pct, period_end }]
machines.<id>.pcent
machines.<id>.task | jobs | weekly | running | queued | uptime_since
```

`pcent` values are remaining percent integers. Omit a key when unknown. Do not send `0` as a placeholder for unknown. `0` means exhausted.

## Accuracy checklist

Run this before trusting a bar or a fuel pick. Do not type a percent the JSON does not contain.

```
curl -fsS https://irc.ntsa.uk/bob/v1/report
```

1. HTTP 200 and JSON. If it fails, do not fall back to `http://bob.ntsa.uk/bob/v1/digest`.
2. `reportUrl` in `config/bobiverse.json` is exactly `https://irc.ntsa.uk/bob/v1/report`.
3. Each online builder that has a Cursor login has a `pcent` object. MarchHare may omit Cursor keys; that is not a license to invent them.
4. Keys you act on: `cursor-models` (auto / low cost models), `high-cost-models`, `grok-chat`. `on-demand` may be present and is not a bar.
5. `cursor_pools` group ids normalize as in the alias table above. Named seats stay per-seat; other pools fan out.
6. Body has no `password=`, `xai_api_key=`, `X-Bob-Secret`, `report.secret`, or `connect.password`.
7. `overage_gbp` may be null on the digest while local TipForm shows GBP. Prefer local `spendLimitUsage` / `Get-BobCursorOverageGbp` when that doc has `overage_gbp`. A label that is only `N%` is remaining, not overspend (overspend text starts with `-` or contains a GBP sign, `GBP`, or `$`).
8. Missing field -> `n/a` on the card and "no fuel number" for dispatch. Do not copy another seat's percent into a different spending group.

## Hard rules

- Do not invent usage numbers.
- Do not print the report secret.
- Builders POST. TipForm GETs. Jeeves whispers `BOB DIGEST v1` (chair), it is not a substitute for `pcent` on the webhook.
- One home for fuel policy: `bob-token-handoff`.
