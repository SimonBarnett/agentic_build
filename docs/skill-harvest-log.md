# Skill harvest log

## 2026-09-20 — dispatcher hands every worker PR to a different MRB worker

When a worker opens a PR, the dispatcher immediately `Start-BobMrbHandoff`
(`-Kind mrb`, new job, isolated worktree). Never the implementer. Never
resume the Composer session. FAIL still spawns a FIX worker who opens a
new PR; that PR is MRBd by yet another worker. Home: `bob-build-loop`.
Pointers: `cursor-mrb-dev`, `bob-hostile-mrb`.

## 2026-09-20 — build/MRB loop driver (notify on PASS-nits)

`bob-job-loop` / `tools/Start-BobBuildLoop.ps1`: dispatcher launches one
program; stdout `DONE` on MRB PASS-nits. Starts the PR worker, hands MRB
to a different `-Kind mrb` agent, retries failed cursor/grok jobs (max 3
attempts per phase), reads Required fixes on FAIL, back-links boards.
State under `$BOB_BRIDGE_HOME/loops`. Does not stamp UAT. FR:
`docs/feature-request-mrb-loop-automation-2026-09-20.md`.

## 2026-09-20 — PR/MRB transaction: Cursor Models then grok

Simon: Cursor Models (Cursor Grok + Composer) for MRBs and PRs until that
pool is empty, then grok.exe. Never Other Models. Tray/capacity must show
Cursor Models remaining % (20 Sep Spending: 1% used; tray had labelled
Sand overage as Cursor Models). Both MRB and implementation are handed off.
Workers open PRs. PASS-nits: MRB agent merges. Every FAIL: spawn a FIX
worker. Table + mermaid in `bob-build-loop` / README. `models.mrbCursor`
is Cursor Grok `grok-4.6`, not `claude-opus-5-thinking-high`. FR:
`docs/feature-request-pr-mrb-cursor-models-transaction-2026-09-20.md`.

## 2026-09-20 — customer paid their bill

Standalone `cursor-sand-billing`: Grok Bot deaf → Sand 100% / Stripe `NEEDS_AUTH` / Open invoices at `cursor.com/dashboard/billing` (not Spending). After Paid, one ping. Do not Recreate. `box-usage` still owns the numbers.

## 2026-09-20 — Cursor MRB/FIX until PASS-nits

`cursor-mrb-dev`: hand off Cursor MRB (reasoning model) then Cursor
builder (`composer-2.5`) until a new `MRB FAIL|PASS-nits` issue on the
new SHA. `start-bob-cursor` owns login, `-Kind`, in-process `-Goal`,
`--` before prompt, Win32_Process.Create, no RedirectStandardOutput.
`bob-hostile-mrb`: new MRB issue per SHA; do not reuse the old FAIL as
the board. `bob-build-loop` points here; fuel is Cursor then Grok.

## 2026-09-20 — bob-irc canonical in agentic_irc

All IRC playbooks (client, SEAL, moot, file, dumb, invite-airc, Ergo
start/firewall, Watch-Bobiverse recycle, Halloy) live in
`https://github.com/SimonBarnett/agentic_irc` `.grok/skills/`. This repo
keeps a `bob-irc` stub (Test-Pack / Install-BobFleet) plus
`config/bobiverse.json` and `docs/bobiverse*.md`. `harvest-agent-skills`
routes IRC harvests to agentic_irc.

## 2026-09-20 — unpaid Open Cursor invoices silence Grok Bot

Cursor dashboard: "You may have an unpaid invoice" plus invoice Status Open (20 Sep mid-month cycle starting 16 Sep; 16 Sep cycle starting 14 Sep). Same as Stripe `NEEDS_AUTH` + Sand 100%. Pay Open rows, then one Bob ping. `box-usage`.

## 2026-09-20 — Stripe Link NEEDS_AUTH blocks Sand on-demand

`ListGrokBotStripeLinkPaymentMethods` returned `GROK_BOT_STRIPE_LINK_PAYMENT_METHODS_OUTCOME_NEEDS_AUTH` while `GetSandUsageStatus` was 100% with on-demand enabled. Box send 503. Human must finish payment method in Grok Bot Settings > Usage. `box-usage` + `unstick-grok-bot` step 3.

## 2026-09-20 — Sand usagePercent 100 silences Grok Bot

Dashboard `GetSandUsageStatus` `usagePercent: 100` (reset `nextResetTimestampUtc`). Turns `ACCEPTED_TEMPORAL` with no `send-message` and no limit banner. On-demand enabled / `hasAvailableUsage: true` still silent; box harness 503. Check this **before** RecreateSandBox. `box-usage` owns the Sand numbers; `unstick-grok-bot` step 3 points here.

## 2026-09-20 — cursor-agent prompt must not look like CLI flags

Node `cursor-agent` treats unquoted prompt tokens as options
(`unknown option '-join'`). Launch with `--` before the prompt, and do
not put PowerShell `-join` or raw double-quotes in the goal string.

## 2026-09-20 — Start-BobCursor must leave the grok Job Object

`Start-Process` children are killed when the grok.exe shell that called
`Start-BobCursor.ps1` exits. Use `Win32_Process.Create` so cursor-agent
outlives the dispatcher. Combined with no `RedirectStandardOutput` on
the parent (PS 5.1 wait bug).

## 2026-09-20 — Start-BobCursor must not wait on the agent

`Start-Process -RedirectStandardOutput -PassThru` in Windows PowerShell
5.1 still waited for cursor-agent (handoff `ConvertTo-Json` returned
after 843s when pid 11464 exited). Redirect inside `launch.ps1` instead;
parent Start-Process is Hidden + PassThru only.

## 2026-09-20 — cursor-agent prompt via launch.ps1

`Start-Process -ArgumentList` mangles a multiline MRB prompt (quotes
split the node argv). Write `cursor-agent-<job>.prompt.txt` and a
`launch.ps1` that reads it and passes one argument to `cursor-agent.ps1`.
Skip empty Docs/Plan so the prompt is not `Read  and .`.

## 2026-09-20 — grok.exe has no build0.1; resolve equivalent

`grok models` on 1.0.34 is only `grok-4.6` / `grok-4.5` (`-m build0.1` is
unknown model id). Keep `models.buildGrok=build0.1`. `Resolve-BobGrokCliModel`
maps it to `models.buildGrokFallback` (`grok-4.5`) before `grok.exe -m`.
When the catalog lists `build0.1`, the preferred id is used as-is.
Cursor builders stay `composer-2.5`; MRB stays `grok-4.6` /
`claude-opus-5-thinking-high`. `-m grok-4.6` already bills `grok-4.6-build`.

## 2026-09-20 — MRB reasoning vs build0.1

MRB jobs use the latest reasoning model (`models.mrbCursor` /
`models.mrbGrok`). Build workers use `build0.1` or Cursor `composer-2.5`.
`Get-BobJobModel`; grok.exe `-m`; cursor-agent `--model`.

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


## 2026-09-20 — ionos Ergo outbox POINT flood

`Write-BobIrcStatus` appending a POINT every Watch tick filled
`~\.agentic-irc-bobiverse\outbox.txt` (~1831 lines). `irc_agent.py` drain
plus Ergo flood limits reconnect-looped `bob-ionos`. Playbook:
dedupe last outbox POINT after stripping `lastSeen=`; compact POINT-only
backlog over 32KB on Start/Install; treat `127.0.0.1` as private Ergo
(not stale/Libera); do not default ionos to loopback without SNI.
Owner: `docs/bobiverse.md` + `bob-irc` stub.

## 2026-09-20 — cursor/xAI remaining + reset dates

- Harvested into `box-usage` and `bob-fleet-tray`: Get-BobWeeklyRemaining / Get-BobCursorAgentWeeklyRemaining / Format-BobResetLabel / IRC reset= / TipForm headings.
- Import-BobIrcPeerTranscript keeps prior period_end when POINT lacks reset=.
