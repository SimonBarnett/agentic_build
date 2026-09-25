---
name: bob-git-accept
description: >
  Shop backup when Bob is out of Sand: idle {machine}-<pid> says !bored only,
  Jeeves assigns the next unaccepted GIT job (one line), worker ACK then
  Start-BobBuild and reports agent+model on the digest webhook.
  Use when the user says !bored, !BORED, git accept, shop idle worker,
  or /bob-git-accept. Queue is the digest report / gh-Jeeves. Do not merge
  until ACK matches. bob-* must not auto-claim.
---

# Shop !bored → Jeeves assigns → ACK

Backup when the builder is out of Sand. `bob-*` does **not** auto-claim
Jeeves `GIT` lines. **Jeeves assigns** on `!bored` (FR #106; ear OFFER
retired). Source of truth: [gh-Jeeves README](https://github.com/SimonBarnett/gh-Jeeves#readme).

The worker does **not** say `!ACCEPT` on this path. It says `ACK` after the
assign line.

## Who speaks

| Nick | Where | What |
|---|---|---|
| `Jeeves` | `#bobiverse` | `GIT …` announce only |
| `{machine}-<pid>` | shop `#{machine}` only | `!bored` after idle **> 2 min** (120s) |
| `Jeeves` | that shop | assign: `<nick>: <TYPE> <repo>#<n> <url>` (`!focus` order) |
| same worker | that shop | `ACK <TYPE> <repo>#<n>` → Jeeves marks accepted + busy |
| same worker | — | `Start-BobBuild` / work; then `DONE` → done + idle |

`!bored` is `PRIVMSG #<shop> :!bored` on **that worker's** `outbox.txt`.
Not the builder outbox. Not `chair-outbox.txt`.

Legacy `w-<short>-<pid>` nicks are retired for the trust gate; live seats use
`{machine}-<pid>` (for example `marchhare-34992`).

## Queue (digest webhook)

Source of truth for **not-yet-accepted** jobs is the digest report / Jeeves
queue (`queue.json` crash mirror):

`https://irc.ntsa.uk/bob/v1/report`

(`reportUrl` in `config/bobiverse.json`.)

Jeeves owns assign-on-`!bored`, ACK→accepted+busy, DONE→done+idle+supersede.
This skill only describes the **worker** side.

## Worker clock

`Watch-Bobiverse` / watch-seat packs call the idle loop each tick.

- Busy (ACK'd job still running): no `!bored`. When the job finishes, send
  `DONE` then `!bored` again.
- Idle 120 seconds: append `!bored` once. A later idle stretch appends it again.
- Chair reply on that shop, after the `!bored` byte offset:
  - `<nick>: nothing queued` — reset the idle clock.
  - `<nick>: <TYPE> <repo>#<n> <url>` — **assign**. Reply `ACK <TYPE> <repo>#<n>`
    (FR match rules: ACK FR may match a legacy PR row; see gh-Jeeves FR #102).
- `OFFER`, bare `GIT`, and `#bobiverse` chatter do not start work.
- On one box, the first seat to ACK owns the row. A sibling that sees the same
  assign no-ops.

## Start and activity

`Start-BobBuild -Task git` on **this** machine. No `-AllowCopilot`.
Fuel order inside the picker: Cursor Models, then grok-build.

| TYPE | Kind | goal |
|---|---|---|
| `FR` | `build` | issue → implement |
| `MRB` | `mrb` | hostile MRB of `…/pull/{n}` |
| `UAT` | `uat` | Bob stamps only after MRB PASS |

On a real start, POST the digest webhook (`op: merge`) with `working_on`
set to `{agent} {model} {TYPE} {repo}{#n}`, plus `model`, `fuel`, `kind`, and
`repo`. When the job leaves inbox/running, POST `working_on` empty and send
`DONE`.

## Hard rules

- Jeeves **assigns**; workers do not invent OFFER/ASSIGN lines.
- ACK before work; DONE after work; then `!bored` again.
- Self-MRB only when one live seat (CAST IRON).
- Do not merge UNSTABLE.
