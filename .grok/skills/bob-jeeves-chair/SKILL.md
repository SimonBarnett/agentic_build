---
name: bob-jeeves-chair
description: >
  Digest chair Jeeves on ionos: auto-start, homes, NSSM service BobJeeves,
  dependency on BobIrcd, !recycle, and GIT outbox. Use when the user says
  Jeeves, chairNick, BobJeeves, digest chair, !recycle, GIT outbox,
  BOB_DIGEST_HOME, or /bob-jeeves-chair. Wire join/firewall stays agentic_irc
  bob-irc. Digest shape is bob-digest-webhook. Builders are not the chair.
---

# Jeeves (digest chair)

`!bobiverse` answers and `BOB DIGEST v1` whispers come from **Jeeves**, not
from `bob-ionos` / `bob-flamingo` / `bob-marchhare` / `bob-dev1`.

## Identity

| | |
|---|---|
| Nick | `Jeeves` (`config/bobiverse.json` key `chairNick`) |
| Machine | `chairHome` = `ionos` |
| Install once | `tools/Install-BobChair.ps1` sets `BOB_IRC_NICK` from `chairNick` and runs `Install-BobIrc.ps1 -MachineId ionos -Chair` |
| Not the builder | `Watch-Bobiverse` must not become the chair. Header in `Install-BobChair.ps1`. |

Checked-in `chairNick` may still read `bob-chair` on an old tree. Live chair nick is **Jeeves**. Confirm the key before install. Do not start a second chair.

## Auto-start

Jeeves is Windows service **`BobJeeves`** (NSSM, Automatic) on ionos. It depends on Ergo service **`BobIrcd`** (`tools/Install-BobIrcd.ps1`, NSSM wraps `C:\ai\ergo\ergo.exe`). Ergo must be Running before Jeeves. Do not start Jeeves from a grok.exe reasoning loop.

| Need | Action |
|---|---|
| Ergo down | `Start-Service BobIrcd` or `Restart-Service BobIrcd`. Status Stopped / no `ergo.exe` means down. |
| Chair down, Ergo up | `Restart-Service BobJeeves` only. |
| Cert renewal | `tools/Install-BobIrcdCert.ps1` restarts **BobIrcd only**. Then confirm BobJeeves came back (dependency). |
| Old task | Do not `Start-ScheduledTask BobIrcd-ionos`. That task is unregistered. |

Do not `Stop-Process ergo`. Do not copy NSSM from another product. NSSM for Ergo lives in the Ergo root (`docs/bobiverse-ionos-ircd.md`).

## Homes (do not merge them)

| Home | What it is |
|---|---|
| `--home` / `BOB_IRC_HOME` / `AGENTIC_IRC_HOME` | IRC client home for **that seat**. Builders: `~\.agentic-irc-bobiverse`. `irc_agent.py --home` must be that seat's home. |
| `BOB_DIGEST_HOME` | Digest chair files (Jeeves publish/consume, chair outbox). Separate from a builder `--home`. |

Do not point a `bob-*` `--home` at the digest home. Do not let Jeeves share `bob-ionos` `outbox.txt`. If `BOB_DIGEST_HOME` is unset, read it from the `BobJeeves` service environment. Do not guess a path.

Builder recycle does not use this split as an excuse to restart Ergo. See `bob-irc`: Watch-Bobiverse only.

## GIT outbox

GitHub delivers to `https://irc.ntsa.uk/bob/v1/git` (`setup-github-webhooks`). Jeeves announces accepted events as `GIT ...` on `#bobiverse` from **its** outbox. `bob-*` and talk seats do not narrate GIT. Announce text: agentic_irc skill `jeeves-git-webhook`. A create/ping is `GIT ping`.

Digest merges go to `/bob/v1/report`, not `/bob/v1/git`.

## `!bored` → assign (FR #106)

In every `#{machine}`, a trusted `{machine}-<pid>` worker says `!bored`.
**Jeeves assigns** the next job (`<nick>: <TYPE> <repo>#<n> <url>`, `!focus`
order). ACK → accepted + busy; DONE → done + idle + supersede. The ear OFFER
path is retired. Worker pack: `bob-git-accept`. Source of truth:
[gh-Jeeves README](https://github.com/SimonBarnett/gh-Jeeves#readme).

## !recycle

Jeeves is the ionos notify path for `!recycle`. Implementer PR workers do **not** send live `!recycle` (`bob-hostile-mrb`). Bob or the merger on ionos runs recycle after merge to main.

| Change | Recycle |
|---|---|
| TipForm / tray paint | Kill all `Watch-BobTray`, one CreateNoWindow start (`bob-fleet-tray`). Not Jeeves. |
| Builder IRC peer loop | `Watch-Bobiverse` only (`bob-irc`). Not `BobIrcd`. |
| Ergo / cert / chair code | `Restart-Service BobIrcd` and, if the chair changed, `Restart-Service BobJeeves`. |
| Fleet jobs still running | Do not `Stop-ScheduledTask BobFleet-*`. |

## Hard rules

- One chair nick: Jeeves.
- BobJeeves depends on BobIrcd. Do not recycle Ergo for a tray paint change.
- Do not print `connect.password`, `report.secret`, or `X-Bob-Secret`.
- Canonical IRC wire (JOIN, firewall, Halloy): agentic_irc `.grok/skills/bob-irc`. This file is the chair contract for agentic_build.
