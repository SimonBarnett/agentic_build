---
name: bob-git-accept
description: >
  Shop backup when Bob is out of Sand: idle w-* says !BORED only, Jeeves
  returns the top unaccepted GIT job as !TASK and marks it accepted,
  the worker Start-BobBuild and reports agent+model on the digest webhook.
  Use when the user says !BORED, !TASK, git accept, shop idle worker,
  or /bob-git-accept. Queue is the digest report. Do not merge until
  agentic_irc #197 follow-up uses this schema. bob-* must not auto-claim.
---

# Shop !BORED / !TASK

Backup when the builder is out of Sand. `bob-*` does **not** auto-claim
Jeeves `GIT` lines. The worker does **not** say `!ACCEPT`.

## Who speaks

| Nick | Where | What |
|---|---|---|
| `Jeeves` | `#bobiverse` | `GIT …` announce only |
| `w-<short>-<pid>` | shop `#<machine>` only | `!BORED` after idle **> 2 min** (120s) |
| `Jeeves` | that shop | `!TASK {repo} {task} {id}` — top row, already accepted |
| same `w-*` | — | `Start-BobBuild` and digest activity. No `!ACCEPT` line |

`!BORED` is `PRIVMSG #<shop> :!BORED` on **that worker's** `outbox.txt`.
Not the builder outbox. Not `chair-outbox.txt`.

## Queue (digest webhook)

Source of truth for **not-yet-accepted** jobs is the digest report:

`https://irc.ntsa.uk/bob/v1/report`

(`reportUrl` in `config/bobiverse.json`. Local dev may be `http://bob.ntsa.uk/bob/v1/report`.)

agentic_irc #197 follow-up must publish the FIFO on that document. This
repo only **reads** it (`Get-BobGitUnaccepted`). It does not write the
queue and it does not read `git-accept-queue.json`.

```json
{
  "git_unaccepted": {
    "v": 1,
    "items": [
      {
        "repo": "owner/repo",
        "task": "MRB",
        "id": "#44",
        "seq": 1,
        "ts": "2026-09-24T10:00:00Z",
        "event": "pull_request",
        "action": "opened",
        "line": "GIT pull_request owner/repo opened #44 …"
      }
    ]
  }
}
```

`seq` ascending is the only order. `id` keeps the `#`. `task` is `PR`
or `MRB`. `BUILD` is not used.

Do not merge this PR until the #197 follow-up stores that object on the
report and marks the top row accepted in the same step as `!TASK`.

## Allowlist (chair)

| GitHub event | action | task |
|---|---|---|
| `issues` | `opened` | `PR` |
| `pull_request` | `opened` | `MRB` |
| `pull_request` | `ready_for_review` | `MRB` |

`ping`, `push`, `synchronize`, `labeled`, `closed`, and everything else
are announced only and are not queued. The worker does not start from a
`GIT` line. It starts only from `!TASK`.

## Worker clock

`Watch-Bobiverse` calls `Import-BobWorkerGitShop` each loop.

- Busy (`git-accept-busy.json` and that fleet job still inbox/running): no `!BORED`. When the job leaves those lanes, post `working_on` empty.
- Idle 120 seconds: append `!BORED` once. A later idle stretch appends it again.
- Chair reply on that shop, after the `!BORED` byte offset:
  - `NAK !BORED wait|busy|empty` — reset the idle clock. Do not start.
  - `!TASK {owner/repo} {PR|MRB} {#n}` — Jeeves has already marked that row accepted. Start work.
- `OFFER`, `GIT`, `FILE v1 ACCEPT`, and a `!TASK` on `#bobiverse` do not start work.
- On one box, the first `w-*` to enqueue writes `workers/<machine>/_git-accept-claims.json`. A sibling that sees the same `!TASK` no-ops. A refused start drops that claim. Jeeves will not put the row back.

## Start and activity

`Start-BobBuild -Task git` on **this** machine. No `-AllowCopilot`.
Fuel order inside the picker: Cursor Models, then grok-build.

| task | Kind | goal |
|---|---|---|
| `PR` | `build` | issue → implement |
| `MRB` | `mrb` | hostile MRB of `…/pull/{n}` |

On a real start, POST the digest webhook (`op: merge`) with `working_on`
set to `{agent} {model} {task} {repo}{#n}` (example: `Cursor Models grok-4.6 MRB owner/repo#44`), plus `model`, `fuel`, `kind`, and `repo`.
`Write-BobIrcStatus` still posts the inbox job. When the job leaves
inbox/running, POST `working_on` empty.

`bob-*` may still say `!ACCEPT` on `#bobiverse` if that seat already
accepted work itself. This backup path does not.
