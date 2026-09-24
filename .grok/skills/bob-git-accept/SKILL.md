---
name: bob-git-accept
description: >
  Shop backup when Bob is out of Sand: idle w-* says !BORED, Jeeves
  offers the next unaccepted GIT task, the worker says !ACCEPT and
  Start-BobBuild. Use when the user says !BORED, !ACCEPT, git accept,
  shop idle worker, Jeeves offer, or /bob-git-accept. Chair FIFO is
  agentic_irc jeeves-git-webhook. bob-* must not auto-claim GIT lines.
---

# Shop !BORED / !ACCEPT

Simon 2026-09-24. When Bob is out of Sand, idle workers on the boxes
take incoming GIT work. Jeeves stays deterministic. No model call in
the chair, and no model call in this tick.

## Who speaks

| Nick | Room | Line |
|---|---|---|
| `w-<short>-<pid>` | shop `#<machine>` only | `!BORED` after idle **> 2 min** (120s) |
| Jeeves (chair) | that shop | next unaccepted task, FIFO |
| same `w-*` | same shop | `!ACCEPT {repo} {task} {id}` then start |

`!ACCEPT` is spoken from **that worker ear outbox**
(`~\.agentic-irc-bobiverse\workers\<machine>\<pid>\outbox.txt`), as
`PRIVMSG #<shop> :!ACCEPT {repo} {task} {id}`. Not the chair outbox.
Not the `bob-*` builder outbox.

`FILE v1 ACCEPT` is filexfer. Do not treat it as this claim.

## Chair owns the queue (do not copy it here)

On-disk list of GIT tasks **not yet accepted**, shop announce, and
"mark accepted" when `!ACCEPT` is seen: **SimonBarnett/agentic_irc**
`irc_agent.py --chair` / skill `jeeves-git-webhook`. Jeeves already
JOINs `#bobiverse` and every fleet shop (`chair_channels` in
`scripts/bobreport.py`), so a shop `!BORED` is audible.

This repo only **reads** `git-accept-queue.json` on the IRC home
(`Get-BobGitAcceptQueue`). It never creates or writes that file.
Schema the chair may write:

```json
{"v":1,"pending":[{"repo":"owner/repo","task":"MRB","id":"44","enqueued":"2026-09-24T00:00:00Z"}]}
```

`task` is `PR`, `MRB`, or `BUILD`. As of 2026-09-24 agentic_irc `main`
has no queue PR yet. Workers already speak the lines below so that
chair change can mark them. Do not invent a second queue in
agentic_build.

## Offer the worker will take

After **this** nick has said `!BORED`, only a later line from the
chair nick (`Jeeves`, else `config/bobiverse.json` `chairNick`) whose
target is the shop or this `w-*` nick:

- `OFFER {repo} {task} {id}` (preferred; task `PR` / `MRB` / `BUILD`)
- or a claimable `GIT ...` line (same allowlist as Jeeves announce)

Ignore `#bobiverse`. Ignore `GIT ping`. Ignore lines from `bob-*`.

### GIT allowlist (skip if unsure)

Live shape (`format_github_webhook_announce`):
`GIT <event> <owner/repo> <action> #n ... by <actor>`.

| Event | Action | Task |
|---|---|---|
| `issues` | `opened` | `PR` (issue to PR; not `BUILD`) |
| `issues` | `labeled` | `PR` only when the line contains `label=FR`, `label=build`, or `label=feature-request`. Live Jeeves text does not include the label name, so a bare `labeled` is skipped. |
| `pull_request` | `opened`, `ready_for_review`, `synchronize` | `MRB` |
| `ping`, `push`, other actions (`closed`, `edited`, ...) | | skip |

`{id}` is the `#n` digits. `{repo}` is `owner/repo`.

One winner: if the worker log already contains `!ACCEPT {repo} {task} {id}`, do not start and do not say it again. On one box, the first `w-*` to enqueue writes `workers/<machine>/_git-accept-claims.json`; a sibling that sees the same offer no-ops. A refused start drops that claim.

## Start and activity

On a fresh offer, `Start-BobGitAcceptWork` calls `Start-BobBuild -Task git`
on **this** machine. Fuel order is `Get-BobFuelOrder`: Cursor Models
while remaining > 0, else grok-build. Never Other Models. Never
`-AllowCopilot` (CCA is not live).

- `MRB` -> `-Kind mrb` and the pull URL
- `PR` / `BUILD` -> `-Kind build`

`!ACCEPT` is appended only when that enqueue returns `ok` and not
`wait`. A refused start leaves the task unaccepted.

Activity is the fleet inbox/running job, posted by the existing
`Write-BobIrcStatus` digest webhook (`reportUrl`
`https://irc.ntsa.uk/bob/v1/report`). `git-accept-busy.json` in the
worker home tracks that job id. When the job is no longer inbox or
running, the stamp is removed and the next status post no longer
lists it. Do not POST a synthetic START that is not a job file.

## What Watch-Bobiverse does

Each poll calls `Import-BobWorkerGitShop` for local `w-*` homes. That
appends to the **worker** outbox. It does not claim a Jeeves `GIT`
line on `#bobiverse`. It does not write the chair queue.

Optional fast path: a `bob-*` nick may still say
`!ACCEPT {repo} {task} {id}` on `#bobiverse` if that seat already
holds the work. Watch does not emit that from a fleet `GIT` line.
The backup path is `!BORED` workers.

## After merge

Recycle **Watch-Bobiverse** on each box (`_Watch-Bobiverse-<id>`) so
the poller loads `Import-BobWorkerGitShop`. Worker ears already drain
`PRIVMSG` lines from their own `outbox.txt`; recycle a `w-*` irc_agent
only if its outbox is stuck. Recycle Jeeves only when the agentic_irc
chair-queue change merges.
