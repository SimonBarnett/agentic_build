# Skill harvest log

## 2026-09-23 — harvest as a PR, not main

Simon `#bobiverse`: update builder skills — send skills harvest as a
PR, NOT a commit to main. Home: `harvest-agent-skills` +
`Harvest-AgentSkills.ps1`.

## 2026-09-23 — FR you parked is a bob job

Simon `#bobiverse`: `Standing rule if you get a FR, you bob job it`.
Park (`bob-spec-intake`) then `bob-job-loop` unless he said park-only.
Homes: `bob-spec-intake` + `bob-job-loop`.

## 2026-09-22 — PASS-nits merge-in-progress + no gh `merged` field

`gh pr view --json state,merged` fails (unknown field `merged`).
`Test-BobGhPrIsMerged` then always returned false, so PASS-nits finish
retried `gh pr merge` and died on `GraphQL: Merge already in progress`
without closing boards (agentic_irc #135 / PR #145). Query
`state,mergedAt`. If merge stderr is in-progress but `state` is MERGED,
treat merged and close. Home: `bob-job-loop` + `tools/Bob-BuildLoop.ps1`.

## 2026-09-22 — talk seats own bob jobs

Simon `#bobiverse`: `no - the bob jobs are YOURS`. Idle talk seats run
`bob-job-loop` on unowned open issues. Do not leave the queue to
`bob-*` / Watch. Home: `bob-job-loop`.

## 2026-09-22 — bob-job checks open issues as well as FRs

Simon `#bobiverse`: bob-job must scan **all open issues** (and open PRs),
not only `--label feature-request`. Skip pure MRB meta boards. Unlabeled
/ other-label open issues are work (intake then loop). Homes:
`bob-job-loop` + `bob-hostile-mrb`.

## 2026-09-22 — CAST IRON: harvest back to the relevant repo

Simon `#bobiverse`: every skill repo has a harvest skill as foundation
(like `harvest-agent-skills` here). If you learn something new, harvest
it back to the **relevant** repo immediately. `harvest-agent-skills` +
`bob-spec-intake` (new skill packs LOCK a harvest skill in P0).

## 2026-09-22 — gh pr merge must pass --merge (non-interactive)

ehf #5 PASS-nits finish FAILED: `gh pr merge` without `--merge`/`--rebase`/`--squash` when not a TTY. PR #10 was MERGED a moment later; treat DONE. Driver `Invoke-BobGhMergePrIfOpen` now passes `--merge`.

## 2026-09-22 — MRB no-Bob: find next seat, do not sit

Simon `#bobiverse`: if you MRB and there is no Bob but open issues
remain, find someone to take the next dev — do not let it sit. Add to
skills and harvest. `bob-hostile-mrb` + `bob-job-loop`.

## 2026-09-22 — MRB MUST close, merge, and pull completed PRs

Simon `#bobiverse`: VERY important. After PASS-nits, MRB must close
finished issues, merge the pull request, and pull completed PRs so the
next job is not on stale main. `bob-hostile-mrb` + `bob-job-loop`.
Detailed FRs are also meant to be done at MRB (not park-only).

## 2026-09-22 — harvest before dismiss + PASS-nits merge race

Simon `#bobiverse`: Bob must remind workers to harvest skills before
dismissing them. `harvest-agent-skills` + `bob-job-loop` On wakeup.
`FAILED: PASS-nits finish: PR still open after gh pr merge` is a race:
if the PR is MERGED and the FR is CLOSED / PASS-nits, treat DONE; do
not relaunch a build (marchhare irc-skill #1).

## 2026-09-22 — Watch must not enqueue !bobiverse (Simon go-for-it)

Simon on #bobiverse: go for it. `!bobiverse` answer is Jeeves-only.
`Request-BobIrcBobiversePull` no longer enqueues channel `!bobiverse`
unless `BOB_IRC_ENQUEUE_BOBIVERSE_PULL=1`. Talk seats never answer it.

## 2026-09-22 — fleet harvest irc skill + failed-pong restart

Simon `#bobiverse`: `everyone harvest your irc skill`; live seat on a
box restarts a nick that fails to pong. Triggers added to
`harvest-agent-skills` and `killproc`. IRC body lives in `agentic_irc`.

## 2026-09-22 — killproc -Roll shop channel from nick

Marchhare-20280: killproc -Roll joined #flamingo on marchhare-23624.
`Stop-HungAgent` now sets `--channel #bobiverse,#<machine>` from the
nick (marchhare-23624 -> #marchhare). Do not hardcode #flamingo.

## 2026-09-22 — killproc: -IrcHome, working seat, new cursor-agent

Simon: harvest the second-seat night. Param is `-IrcHome` (never `-Home`;
`$Home` is read-only). Working live seat killproc-rolls the hung *other*
home only; missing cursor-2 means no hung seat. `-Roll` is still deaf
until a Cursor TSR. After close: new `cursor-agent.ps1` with prompt file
(`--trust --force --model grok-4.6`); no `cmd.exe /c` prompt; no Halloy
SendKeys. Skill `killproc`. Talk-seat nick/home stay `agentic-irc`.

## 2026-09-22 — killproc (end hung agents)

Simon: create a new killproc skill to end hung (jung) agents.
`Stop-HungAgent.ps1 -IrcHome <seat> -Nick <nick> -Roll` kills only
`irc_agent`/`irc_listen` on that home, then rolls a replacement.
Do not spray Stop-Process. Named Grok Bot remains `unstick-grok-bot`.
Skill `killproc`.

## 2026-09-21 — MRB: re-read mergeable immediately before PASS-nits

`bob-hostile-mrb`: GitHub `CLEAN` can flip to `CONFLICTING` while the
board is written (main moved). Re-query `mergeable` immediately before
posting PASS-nits. If `gh pr merge` then fails, void that pass board and
open a new FAIL issue on the same SHA. Learned on open-tts PR #87 /
SHA `86cabf9` (issues #134 then #135).

## 2026-09-21 — MRB worker: isolate review SHA; CONFLICTING is FAIL

`bob-hostile-mrb` worker steps: if the shared checkout HEAD is another
job, use a detached worktree at the review SHA (do not reset that
branch). A GitHub `CONFLICTING` PR is FAIL even when acceptance is
green in isolation — PASS-nits includes merge.

## 2026-09-21 — bob-job launchers + MRB remaining-FR rule

Harvest from live bob-job loops:

- `tools/run-bob-build-loop.ps1` and `tools/start-bob-build-loop-issue.ps1`:
  GCM / credential-manager for `GH_TOKEN` (do not rely on interactive
  `git credential fill` when `gh` is the helper).
- `bob-job-loop`: unique LogPath, recover missed PR, after DONE hand
  remaining open `feature-request` issues to new workers.
- **New MRB rule:** pass to a **new** worker on MRB FAIL **or** when any
  open feature-request / Missing-features issues remain. Homes:
  `bob-hostile-mrb`, `bob-job-loop`, pointer `bob-build-loop`,
  `cursor-mrb-dev`.
- FIX #112: `ConvertFrom-BobGhJsonList` keeps issue `body`; restore `-Pr`
  to `Start-BobMrbHandoff`; Test-Pack BT0loop10/11. Audit write must not
  abort DONE.
## 2026-09-21 â€” running Bob jobs (dispatcher playbook)

Fleet runs of `bob-job-loop` across agentic_build / agentic_irc / open-tts.
Promote: `tools/run-bob-build-loop.ps1` (credential-manager GH_TOKEN first),
unique LogPath, isolated worktree per FR, pin existing PRs with `-Sha`/`-Pr`,
FIX PR titles match `priorMrbIssue`, gh JSON unzip, `$PID` not overwritten,
cursor-agent status stderr non-fatal, Add-Content log lock fallback.
`bob-job-loop` skill owns the dispatcher hard rules. Driver files:
`Start-BobBuildLoop.ps1`, `Bob-BuildLoop.ps1`, `Start-BobCursor.ps1`.

## 2026-09-20 â€” build/MRB loop driver (notify on PASS-nits)

`bob-job-loop` / `tools/Start-BobBuildLoop.ps1`: dispatcher launches one
program; stdout `DONE` on MRB PASS-nits. Starts the PR worker, hands MRB
to a different `-Kind mrb` agent, retries failed cursor/grok jobs (max 3
attempts per phase), reads Required fixes on FAIL, back-links boards.
State under `$BOB_BRIDGE_HOME/loops`. Does not stamp UAT. FR:
`docs/feature-request-mrb-loop-automation-2026-09-20.md`.

## 2026-09-20 â€” dispatcher hands every worker PR to a different MRB worker

When a worker opens a PR, the dispatcher immediately `Start-BobMrbHandoff`
(`-Kind mrb`, new job, isolated worktree). Never the implementer. Never
resume the Composer session. FAIL still spawns a FIX worker who opens a
new PR; that PR is MRBd by yet another worker. Home: `bob-build-loop`.
Pointers: `cursor-mrb-dev`, `bob-hostile-mrb`.

## 2026-09-20 â€” PR/MRB transaction: Cursor Models then grok

Simon: Cursor Models (Cursor Grok + Composer) for MRBs and PRs until that
pool is empty, then grok.exe. Never Other Models. Tray/capacity must show
Cursor Models remaining % (20 Sep Spending: 1% used; tray had labelled
Sand overage as Cursor Models). Both MRB and implementation are handed off.
Workers open PRs. PASS-nits: MRB agent merges. Every FAIL: spawn a FIX
worker. Table + mermaid in `bob-build-loop` / README. `models.mrbCursor`
is Cursor Grok `grok-4.6`, not `claude-opus-5-thinking-high`. FR:
`docs/feature-request-pr-mrb-cursor-models-transaction-2026-09-20.md`.

## 2026-09-20 â€” customer paid their bill

Standalone `cursor-sand-billing`: Grok Bot deaf â†’ Sand 100% / Stripe `NEEDS_AUTH` / Open invoices at `cursor.com/dashboard/billing` (not Spending). After Paid, one ping. Do not Recreate. `box-usage` still owns the numbers.

## 2026-09-20 â€” Cursor MRB/FIX until PASS-nits

`cursor-mrb-dev`: hand off Cursor MRB (reasoning model) then Cursor
builder (`composer-2.5`) until a new `MRB FAIL|PASS-nits` issue on the
new SHA. `start-bob-cursor` owns login, `-Kind`, in-process `-Goal`,
`--` before prompt, Win32_Process.Create, no RedirectStandardOutput.
`bob-hostile-mrb`: new MRB issue per SHA; do not reuse the old FAIL as
the board. `bob-build-loop` points here; fuel is Cursor then Grok.

## 2026-09-20 â€” bob-irc canonical in agentic_irc

All IRC playbooks (client, SEAL, moot, file, dumb, invite-airc, Ergo
start/firewall, Watch-Bobiverse recycle, Halloy) live in
`https://github.com/SimonBarnett/agentic_irc` `.grok/skills/`. This repo
keeps a `bob-irc` stub (Test-Pack / Install-BobFleet) plus
`config/bobiverse.json` and `docs/bobiverse*.md`. `harvest-agent-skills`
routes IRC harvests to agentic_irc.

## 2026-09-20 â€” unpaid Open Cursor invoices silence Grok Bot

Cursor dashboard: "You may have an unpaid invoice" plus invoice Status Open (20 Sep mid-month cycle starting 16 Sep; 16 Sep cycle starting 14 Sep). Same as Stripe `NEEDS_AUTH` + Sand 100%. Pay Open rows, then one Bob ping. `box-usage`.

## 2026-09-20 â€” Stripe Link NEEDS_AUTH blocks Sand on-demand

`ListGrokBotStripeLinkPaymentMethods` returned `GROK_BOT_STRIPE_LINK_PAYMENT_METHODS_OUTCOME_NEEDS_AUTH` while `GetSandUsageStatus` was 100% with on-demand enabled. Box send 503. Human must finish payment method in Grok Bot Settings > Usage. `box-usage` + `unstick-grok-bot` step 3.

## 2026-09-20 â€” Sand usagePercent 100 silences Grok Bot

Dashboard `GetSandUsageStatus` `usagePercent: 100` (reset `nextResetTimestampUtc`). Turns `ACCEPTED_TEMPORAL` with no `send-message` and no limit banner. On-demand enabled / `hasAvailableUsage: true` still silent; box harness 503. Check this **before** RecreateSandBox. `box-usage` owns the Sand numbers; `unstick-grok-bot` step 3 points here.

## 2026-09-20 â€” cursor-agent prompt must not look like CLI flags

Node `cursor-agent` treats unquoted prompt tokens as options
(`unknown option '-join'`). Launch with `--` before the prompt, and do
not put PowerShell `-join` or raw double-quotes in the goal string.

## 2026-09-20 â€” Start-BobCursor must leave the grok Job Object

`Start-Process` children are killed when the grok.exe shell that called
`Start-BobCursor.ps1` exits. Use `Win32_Process.Create` so cursor-agent
outlives the dispatcher. Combined with no `RedirectStandardOutput` on
the parent (PS 5.1 wait bug).

## 2026-09-20 â€” Start-BobCursor must not wait on the agent

`Start-Process -RedirectStandardOutput -PassThru` in Windows PowerShell
5.1 still waited for cursor-agent (handoff `ConvertTo-Json` returned
after 843s when pid 11464 exited). Redirect inside `launch.ps1` instead;
parent Start-Process is Hidden + PassThru only.

## 2026-09-20 â€” cursor-agent prompt via launch.ps1

`Start-Process -ArgumentList` mangles a multiline MRB prompt (quotes
split the node argv). Write `cursor-agent-<job>.prompt.txt` and a
`launch.ps1` that reads it and passes one argument to `cursor-agent.ps1`.
Skip empty Docs/Plan so the prompt is not `Read  and .`.

## 2026-09-20 â€” grok.exe has no build0.1; resolve equivalent

`grok models` on 1.0.34 is only `grok-4.6` / `grok-4.5` (`-m build0.1` is
unknown model id). Keep `models.buildGrok=build0.1`. `Resolve-BobGrokCliModel`
maps it to `models.buildGrokFallback` (`grok-4.5`) before `grok.exe -m`.
When the catalog lists `build0.1`, the preferred id is used as-is.
Cursor builders stay `composer-2.5`; MRB stays `grok-4.6` /
`claude-opus-5-thinking-high`. `-m grok-4.6` already bills `grok-4.6-build`.

## 2026-09-20 â€” MRB reasoning vs build0.1

MRB jobs use the latest reasoning model (`models.mrbCursor` /
`models.mrbGrok`). Build workers use `build0.1` or Cursor `composer-2.5`.
`Get-BobJobModel`; grok.exe `-m`; cursor-agent `--model`.

## 2026-09-20 â€” MRB fuel is Cursor then Grok

`Start-BobMrbHandoff` / picker default: `cursor-models` then `grok-build`. Copilot only with `-AllowCopilot`. `Start-BobCursor` must not launch `~\.grok\bin\agent.exe` (that is grok.exe).

## 2026-09-20 â€” Bob hands off MRBs

Bob does not write the hostile review in-session. `tools/Start-BobMrbHandoff.ps1` posts `@copilot` on the feature-request issue (CCA if enabled) or `-Fleet` git-task. Worker: FAIL / PASS-nits only. Only Bob stamps ready for human UAT. Missing-features check stays in `bob-hostile-mrb`.

## 2026-09-20 â€” MRB requests missing features

`bob-hostile-mrb`: every board walks this FR's acceptance **and** holes with no parked request. Red acceptance stays Required fixes. Unspecified holes / issues with no intake doc are **requested** (`bob-spec-intake` issue + `docs/feature-request-*.md`), not implemented in the MRB job. Body section **Missing features**.


## 2026-09-20 â€” PRs #5 and #6 not merged (stale drafts)

Checked both open drafts vs `main`. Merging either would rewind later tray/git-task work (PR #5) or restore hover/iconProbe/hideTip (PR #6, issue #3). Pulled the unique bits that `main` lacked: per-machine `_Watch-Bobiverse-*.ps1` wrappers (kept ionos env-specific wrapper) and the native P+ idle chip screenshot. Closed the PRs as superseded.

## 2026-09-20 â€” action GitHub issues #1 #3 #4 #7 #8

- `setup-remote-grok-bot`: flamingo remote CLI+desktop playbook (Mode 3 put+spawn, no-GPU, window-state 0x0). Temporal hangs stay `unstick-grok-bot`.
- `reinstall-agentic-build-skills` + `tools/Reinstall-AgentSkills.ps1`: copy `.grok/skills` to `~/.grok/skills`; optional single-instance tray recycle (issue #3).
- `start-bob-cursor` + `Select-BobGitWorker` / `Get-BobCapacity`: git-task dispatch is `(machine, fuel)`. Cursor Models is the shared top bar, not a machine named cursor. DUMB/2012 is not a git worker.
- Tray issue #3: do not merge PR #5 (it would drop seat labels / GBP overage). BT0n now asserts click-only / no hover; `Install-BobFleet` registers `_Watch-Bobiverse-<id>` without double-starting an already-running moot.

## 2026-09-20 â€” unstick: new Temporal agent also hung

Created throwaway `Builder` (`CreateGrokBotTemporalAgent`). Its `grok-bot-turn-<newId>` ACCEPTED a PONG with no send-message, same as Bob and Haitch. `SendGrokBotUserMessage isFork` still returns Bob's old workflow id. Stop Recreate.

## 2026-09-20 â€” unstick: account-wide Temporal

If Haitch (or any idle agent) also ACCEPTED_TEMPORAL with no send-message, RecreateSandBox cannot fix it. Probe a second agent before more Recreate. `window-state.json` x/y ~-32000 w/h 0 is a separate Electron blank; kill, rewrite bounds, relaunch `--disable-gpu`.

## 2026-09-20 â€” unstick wait for new podId

RecreateSandBox `started: true` is not success. Poll EnsureSandBox until `podId` changes (1-3 min; API can timeout mid-transfer). Two 30s samples of the **old** id mean the box has not rotated.

## 2026-09-20 â€” harvest during the job

`harvest-agent-skills` now fires in-session: if a build/fleet job learns a repeatable procedure, write the skill, log, commit, push `origin/main`. Hourly `BobSkillHarvest-*` is backup. `grok-build-fleet` points here.

## 2026-09-20 â€” unstick: shared sandbox + Waiting to send

- Recreate once per shared Grok Bot sandbox, not per agent. Wait for transfer toast / stable `podId` before any ping.
- UI **Waiting to send** = PENDING. Preferred recovery ping is the Grok Bot UI. `GrokBotApi.py --wait` looks for a new assistant `send-message` in the transcript, not roster `lastActivityAt`.

## 2026-09-20 â€” private Ergo + unstick agentId (ionos)

- New skill `bob-irc`: fleet `#bobiverse` is Ergo `irc.ntsa.uk:6697`, not Libera. Join/recycle Watch-Bobiverse only; connect file path not value. Docs remain `docs/bobiverse.md` / `docs/bobiverse-ionos-ircd.md`.
- `grok-build-fleet` Bobiverse section points at Ergo + `bob-irc`.
- `unstick-grok-bot`: RecreateSandBox must pass `--agent` (agentId); ACCEPTED user echo with no later `send-message` is a hung turn.

## 2026-09-20

MRB is a GitHub issue (`Start-BobMrb.ps1`, skill `bob-hostile-mrb`). No MRB PDFs. Feature-request issue + `/docs` markdown is the source of truth.

## 2026-09-20 (copilot)

Harvested `start-bob-copilot`: Grok starts GitHub Copilot cloud agent via `tools/Start-BobCopilot.ps1` (`gh api` user token). Fleet prompt passes that skill so a build `grok.exe` offloads GitHub repo work instead of burning Cursor weekly usage.

## 2026-09-20 â€” bob-fleet-tray diagnostics harvest (ionos)

Promoted live tray diagnostics into `.grok/skills/bob-fleet-tray/SKILL.md`:
click-only TipForm (no hover), blank NotifyIcon.Text, `#Bobiverse (machine)`
title, seat deals beside names (`config/bob-seats.json`), shared weekly % for
ntsa (marchhare + ce-priority-dev1), cursor overage as red negative pounds from
`tip_cursor.json`, Suspend/Resume redraw to stop poll flash, single-instance
mutex + Restart watcher kill-all. Trigger: recycle Watch-BobTray only after
card/hover changes.

## 2026-09-20 â€” bob-fleet-tray blank-card + real GBP overage (ionos UAT)

- Dropped WM_SETREDRAW from Suspend/Resume-BobTrayPaint (SuspendLayout only).
- Rebuild-BobTrayTiles formats cursor/seat labels before Controls.Clear.
- Inline overage-red check (no Test-BobCursorOverageLabel from tray).
- Get-CursorAgentUsage.py: spendLimitUsage.individualUsed â†’ GBP via er-api.
- Skill rewritten with diagnose steps for blank card + no-dialog compile fail.


## 2026-09-20 â€” ionos Ergo outbox POINT flood

`Write-BobIrcStatus` appending a POINT every Watch tick filled
`~\.agentic-irc-bobiverse\outbox.txt` (~1831 lines). `irc_agent.py` drain
plus Ergo flood limits reconnect-looped `bob-ionos`. Playbook:
dedupe last outbox POINT after stripping `lastSeen=`; compact POINT-only
backlog over 32KB on Start/Install; treat `127.0.0.1` as private Ergo
(not stale/Libera); do not default ionos to loopback without SNI.
Owner: `docs/bobiverse.md` + `bob-irc` stub.

## 2026-09-20 â€” cursor/xAI remaining + reset dates

- Harvested into `box-usage` and `bob-fleet-tray`: Get-BobWeeklyRemaining / Get-BobCursorAgentWeeklyRemaining / Format-BobResetLabel / IRC reset= / TipForm headings.
- Import-BobIrcPeerTranscript keeps prior period_end when POINT lacks reset=.

