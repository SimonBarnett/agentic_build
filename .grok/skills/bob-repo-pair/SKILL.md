---
name: bob-repo-pair
description: >
  bob-{machine} grok chair keeps two persistent shop workers (dev + MRB) per
  assigned repo. Use when Simon assigns a FR/spec repo to Bob, spawn the pair,
  idle-stop, working_on webhook, digest report, or issue #175 two-worker path.
  Complements bob-build-dispatch and bob-job-loop (v1 one-shot loop stays until
  pair is live). Never Other Models.
---

# Bob repo pair (two persistent workers)

**FR:** `docs/feature-request-bob-two-persistent-workers-2026-09-22.md`  
**Plan:** `docs/build-and-test-plan-bob-two-workers-2026-09-22.md`

## Chair

`bob-{machine}` (Grok Bot on the box) owns **one repo** at a time. He spawns
**two** persistent workers on the shop `#<machine>`:

| Seat | Role | Skills (via `--rules` / project skills) |
|------|------|-------------------------------------------|
| `dev` | implement PRs | `bob-build-dispatch`, `bob-irc` |
| `mrb` | hostile MRB | `bob-hostile-mrb`, `bob-irc` |

Nick pattern: `w-<short>-dev` / `w-<short>-mrb` (`io`, `fl`, `mh`, `d1`).
Workers JOIN shop only — never `#bobiverse`. Bob stays on bobiverse skills
(`bob-irc`).

## BobBridge (local-exec on the assigned machine)

```powershell
Import-Module "$repo\src\BobBridge.psd1"
Start-BobRepoPair -Repo 'SimonBarnett/agentic_build' -Cwd $clone
Get-BobRepoPair
Update-BobRepoWorkerWorkingOn -Seat dev -Description 'implement #175 PR'
Invoke-BobRepoPairChairTick   # fleet/watch tick: tickets, idle/deaf, bobiverse say
Assign-BobRepoPairTask -Seat dev|mrb -Task '…' [-PrUrl …]
```

- **Idle default:** 5 minutes (`BOB_REPO_PAIR_IDLE_SEC`, U1).
- **No self-MRB:** `Test-BobRepoPairSelfMrb -Seat dev -PrUrl <url>` must be
  `allowed=$false` when dev implemented that PR. MRB seat reviews it.
- **One build SHA:** `Set-BobRepoPairDevActiveSha` / `Test-BobRepoPairMayEnqueueBuild`
  — do not enqueue two implement jobs on the same SHA.
- **Handoff:** `Register-BobRepoPairDevComplete -PrUrl …` then MRB seat;
  `Register-BobRepoPairMrbComplete` for digest lines.
- **Bob reports:** `Invoke-BobRepoPairBobiverseSay` posts digest lines (dev complete /
  MRB complete) to `#bobiverse` via `outbox.txt`. Workers do not spam channel.
- **Shop description:** `Set-BobShopChannelRepoDescription` updates
  `shop-channel-descriptions.json`; `Watch-Bobiverse` / `Sync-BobShopChannelRepoDescriptions`
  apply `SHOPDESC` to the shop channel when the assigned repo changes.
- **No nested agents:** workers never call `Start-BobBuild`, `Start-BobBuildLoop`,
  `Start-BobMrbHandoff`, or `cursor-mrb-dev` handoff.

## Webhook `working_on`

Workers **must** call `Update-BobRepoWorkerWorkingOn` so the digest shows task
text. Posts go to `config/bobiverse.json` `reportUrl` (or `BOB_REPORT_URL`) with
header `X-Bob-Secret` from env/file — never in git. Change-only POST
(`Invoke-BobDigestWebhookPost`); lastSeen-only ticks do not POST.

## MUST NOT

- Implementer MRB/merge own PR (except PASS-nits on MRB seat per fleet rule).
- Stamp ready for human UAT (Bob chair + `design-uat` only).
- `password=` / `XAI_API_KEY=` assignments in git or prompts.
- Replace v1 `Start-BobBuildLoop` until Simon switches the repo to pair mode.

## Fuel

Dev: Cursor Composer `composer-2.5` / grok build models per `grok-build-fleet`.
MRB: Cursor Grok `grok-4.6` or grok.exe `grok-4.6`. Never Other Models.
