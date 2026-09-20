# Skill harvest log

## 2026-09-20 — MRB fuel is Cursor then Grok

`Start-BobMrbHandoff` / picker default: `cursor-models` then `grok-build`. Copilot only with `-AllowCopilot`. `Start-BobCursor` must not launch `~\.grok\bin\agent.exe` (that is grok.exe).

## 2026-09-20 — Bob hands off MRBs

Bob does not write the hostile review in-session. `tools/Start-BobMrbHandoff.ps1` posts `@copilot` on the feature-request issue (CCA if enabled) or `-Fleet` git-task. Worker: FAIL / PASS-nits only. Only Bob stamps ready for human UAT. Missing-features check stays in `bob-hostile-mrb`.

## 2026-09-20 — MRB requests missing features

`bob-hostile-mrb`: every board walks this FR's acceptance **and** holes with no parked request. Red acceptance stays Required fixes. Unspecified holes / issues with no intake doc are **requested** (`bob-spec-intake` issue + `docs/feature-request-*.md`), not implemented in the MRB job. Body section **Missing features**.


## 2026-09-20 — PRs #5 and #6 not merged (stale drafts)

Checked both open drafts vs `main`. Merging either would rewind later tray/git-task work (PR #5) or restore hover/iconProbe/hideTip (PR #6, issue #3). Pulled the unique bits that `main` lacked: per-machine `_Watch-Bobiverse-*.ps1` wrappers (kept ionos env-specific wrapper) and the native P+ idle chip screenshot. Closed the PRs as superseded.

## 2026-09-20 — action GitHub issues #1 #3 #4 #7 #8

- `setup-remote-grok-bot`: flamingo remote CLI+desktop playbook (Mode 3 put+spawn, no-GPU, window-state 0x0). Temporal hangs stay `unstick-grok-bot`.
- `reinstall-agentic-build-skills` + `tools/Reinstall-AgentSkills.ps1`: copy `.grok/skills` to `~/.grok/skills`; optional single-instance tray recycle (issue #3).
- `start-bob-cursor` + `Select-BobGitWorker` / `Get-BobCapacity`: git-task dispatch is `(machine, fuel)`. Cursor Models is the shared top bar, not a machine named cursor. DUMB/2012 is not a git worker.
- Tray issue #3: do not merge PR #5 (it would drop seat labels / GBP overage). BT0n now asserts click-only / no hover; `Install-BobFleet` registers `_Watch-Bobiverse-<id>` without double-starting an already-running moot.

## 2026-09-20 — unstick: new Temporal agent also hung

Created throwaway `Builder` (`CreateGrokBotTemporalAgent`). Its `grok-bot-turn-<newId>` ACCEPTED a PONG with no send-message, same as Bob and Haitch. `SendGrokBotUserMessage isFork` still returns Bob's old workflow id. Stop Recreate.

## 2026-09-20 — unstick: account-wide Temporal

If Haitch (or any idle agent) also ACCEPTED_TEMPORAL with no send-message, RecreateSandBox cannot fix it. Probe a second agent before more Recreate. `window-state.json` x/y ~-32000 w/h 0 is a separate Electron blank; kill, rewrite bounds, relaunch `--disable-gpu`.

## 2026-09-20 — unstick wait for new podId

RecreateSandBox `started: true` is not success. Poll EnsureSandBox until `podId` changes (1-3 min; API can timeout mid-transfer). Two 30s samples of the **old** id mean the box has not rotated.

## 2026-09-20 — harvest during the job

`harvest-agent-skills` now fires in-session: if a build/fleet job learns a repeatable procedure, write the skill, log, commit, push `origin/main`. Hourly `BobSkillHarvest-*` is backup. `grok-build-fleet` points here.

## 2026-09-20 — unstick: shared sandbox + Waiting to send

- Recreate once per shared Grok Bot sandbox, not per agent. Wait for transfer toast / stable `podId` before any ping.
- UI **Waiting to send** = PENDING. Preferred recovery ping is the Grok Bot UI. `GrokBotApi.py --wait` looks for a new assistant `send-message` in the transcript, not roster `lastActivityAt`.

## 2026-09-20 — private Ergo + unstick agentId (ionos)

- New skill `bob-irc`: fleet `#bobiverse` is Ergo `irc.ntsa.uk:6697`, not Libera. Join/recycle Watch-Bobiverse only; connect file path not value. Docs remain `docs/bobiverse.md` / `docs/bobiverse-ionos-ircd.md`.
- `grok-build-fleet` Bobiverse section points at Ergo + `bob-irc`.
- `unstick-grok-bot`: RecreateSandBox must pass `--agent` (agentId); ACCEPTED user echo with no later `send-message` is a hung turn.

## 2026-09-20

MRB is a GitHub issue (`Start-BobMrb.ps1`, skill `bob-hostile-mrb`). No MRB PDFs. Feature-request issue + `/docs` markdown is the source of truth.

## 2026-09-20 (copilot)

Harvested `start-bob-copilot`: Grok starts GitHub Copilot cloud agent via `tools/Start-BobCopilot.ps1` (`gh api` user token). Fleet prompt passes that skill so a build `grok.exe` offloads GitHub repo work instead of burning Cursor weekly usage.

## 2026-09-20 — bob-fleet-tray diagnostics harvest (ionos)

Promoted live tray diagnostics into `.grok/skills/bob-fleet-tray/SKILL.md`:
click-only TipForm (no hover), blank NotifyIcon.Text, `#Bobiverse (machine)`
title, seat deals beside names (`config/bob-seats.json`), shared weekly % for
ntsa (marchhare + ce-priority-dev1), cursor overage as red negative pounds from
`tip_cursor.json`, Suspend/Resume redraw to stop poll flash, single-instance
mutex + Restart watcher kill-all. Trigger: recycle Watch-BobTray only after
card/hover changes.

## 2026-09-20 — bob-fleet-tray blank-card + real GBP overage (ionos UAT)

- Dropped WM_SETREDRAW from Suspend/Resume-BobTrayPaint (SuspendLayout only).
- Rebuild-BobTrayTiles formats cursor/seat labels before Controls.Clear.
- Inline overage-red check (no Test-BobCursorOverageLabel from tray).
- Get-CursorAgentUsage.py: spendLimitUsage.individualUsed → GBP via er-api.
- Skill rewritten with diagnose steps for blank card + no-dialog compile fail.


## 2026-09-20 — cursor/xAI remaining + reset dates

- Harvested into `box-usage` and `bob-fleet-tray`: Get-BobWeeklyRemaining / Get-BobCursorAgentWeeklyRemaining / Format-BobResetLabel / IRC reset= / TipForm headings.
- Import-BobIrcPeerTranscript keeps prior period_end when POINT lacks reset=.
