# Feature request: capacity dispatch for git tasks (machine × fuel)

**Date:** 2026-09-20  
**Repo:** https://github.com/SimonBarnett/agentic_build  
**GitHub issue:** https://github.com/SimonBarnett/agentic_build/issues/7  
**Raised by:** Simon (originating agent / this thread)  
**UAT + hostile MRB owner:** Bob  
**Build orchestrator:** Bob  

## Ask

Bob hands a **git task** to whoever has capacity. The worker brand is not in the packet. Cursor Models is **fuel**, not a machine: it has its own bar at the top of the fleet form and is reachable from every Cursor-capable box.

A git task is accepted when the worker **commits and pushes** a branch. Chat transcripts are not the handoff. Git + the issue are the swap-out point. A fix pass may land on a different `(machine, fuel)` than the first implement pass.

## LOCKED

1. Packet has no model name and no required `-Machine`.
2. Capacity is a pair `(machine, fuel)`.
3. Machines = tray **rows** (flamingo, ionos, marchhare, ce-priority-dev1, …).
4. Fuels include at least: `cursor-models` (shared top bar), `grok-build`, `grok-bot`, `copilot`, `on-demand`.
5. `cursor-models` is account-level. Burning it from ionos or flamingo moves the **top bar**, not a fake machine named cursor.
6. The tray row labelled `cursor` / Grok Bot week is **`grok-bot` fuel**, not the top bar.
7. DUMB / Mode 3 / 2012 is **not** eligible for git tasks unless a later FR wraps a jailed git-only script. Default: no.
8. `-Machine` and `-Fuel` remain explicit overrides (formprep, MSSQL, pinned box).
9. Default `Start-BobBuild -Task git` picks capacity.
10. Included quota beats on-demand. Do not pick `on-demand` or empty `grok-bot` if any included fuel+machine pair is eligible.
11. Bob stays chair: spec intake, dispatch, hostile MRB, UAT stamp. Cursor / Copilot / grok.exe only implement.
12. IRC verbs stay vendor-free: `SPEC` `WAIT` `BUILD` `PUSH` `MRB` `FIX` `UAT`.
13. Do not break prior versions of Start-BobBuild / Watch-BobJobs / named `-Machine` behaviour.

## UNKNOWN (do not invent)

- Exact Cursor cloud-agent API vs local IDE launch on a box.
- Whether Copilot quota is readable from the tray process.
- Numeric remaining units for Cursor Models (form shows %).
- Whether two Cursor agents on two boxes share one cloud-agent slot.

## Gap vs current tree

- `Start-BobBuild` requires / assumes a named machine. No `-Task git`. No fuel.
- Profiles are `generic` / `formprep` (transport), not fuels.
- `start-bob-copilot` exists as a side door, not behind the same picker.
- No `start-bob-cursor`.
- Tray / `bob-fleet-tray` / peer peek / `seat-period-end.json` already track per-machine Grok weeks and jobs. They do not expose a first-class shared `cursor-models` pool as dispatch input.
- `bob-build-dispatch` writes a plan and calls Start-BobBuild; it does not sort eligible pairs.
- DUMB is in agentic_irc, not filtered out of a git picker because no git picker exists yet.

## Git packet (LOCKED fields)

```
task: git
repo: <https url>
branch: work/<job-id>
docs: /docs/<spec>.md
plan: /docs/<plan>.md
mrb: <issue url or empty>
return: issue comment + POINT UAT
```

Optional override: `machine`, `fuel`.

## Picker order (LOCKED)

```
for fuel in cursor-models, grok-build, copilot, grok-bot, on-demand:
  if fuel has no remaining included (or on-demand not allowed): continue
  seats = machines that can run that fuel
           AND alive AND jobs==0 AND scratch Cwd ok
           AND not dumb-only
  pick best seat: idle, reset furthest, repo already present
  return (machine, fuel)
POINT WAIT if none
```

Today (2026-09-20, Ultra): Cursor Models ~1% used (month 16 Oct), Grok Bot weekly 100% until 23 Sep, on-demand $62.52/$100. Rows: ionos 0%/26 Sep, flamingo 15%/27 Sep, marchhare and ce-priority-dev1 thin/23 Sep. Picker should prefer `(any Cursor-capable box, cursor-models)` then `(ionos|flamingo, grok-build)` before Bot on-demand.

## Acceptance

1. `Start-BobBuild -Task git` with no `-Machine` writes a job naming `{machine, fuel, packet}` and does not require a vendor in the packet.
2. Tray / capacity snapshot distinguishes **top-bar `cursor-models`** from **row `grok-bot`**. Shared pool is not a machine row.
3. Each machine row can declare which fuels it can strike. Dumb-only rows never win a git pick.
4. `start-bob-cursor` (new) and existing `start-bob-copilot` are reachable from the same picker, not only as human rituals.
5. `-Machine` / `-Fuel` override still works; existing named-machine jobs keep working.
6. Watch-BobJobs / pull worker starts the chosen fuel on the chosen box (or documents WAIT + how a human starts Cursor IDE when cloud launch is UNKNOWN).
7. Completion record is SHA + job id (PUSH). MRB stays a GitHub issue on this FR issue or the feature-request issue being built.
8. Off-DEV Fake-Grok path: picker can be unit-tested without live bots or GitHub (pair selection only).
9. README + `bob-build-dispatch` / `grok-build-fleet` skill text describe `-Task git` and fuel vs machine.
10. Commit/push. Hostile MRB on issue #7.

## Non-goals

- Public token marketplace / paying strangers / silent consumer app.
- Unattended public IRC.
- Making DUMB a git worker.
- Cursor as MRB chair or second Bob.
- Changing Grok Bot or Cursor billing.
- Secrets in docs.
