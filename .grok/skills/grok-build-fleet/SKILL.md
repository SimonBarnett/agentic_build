---
name: grok-build-fleet
description: >
  Start, spec, monitor, and stop Grok Builds on named machines (marchhare, dev1,
  ionos). Heal a dead Watch-BobJobs pull worker. Use when the user says start a
  grok build, run Form Prep on DEV1, dispatch a build, fleet job, Watch-BobJobs,
  Start-BobBuild, Get-BobHealth, Install-BobFleet, Watch-BobAgents, stalled
  watcher, or /grok-build-fleet. Named Grok Bot silent -> also load unstick-grok-bot.
  Grok Bot desktop is on every build machine; grok.exe is the Windows logon user
  (MSSQL integrated auth).
---

# Grok Build fleet

Any Grok Bot uses this skill. Builds are `grok.exe -p` as the **logged-in Windows user** (MSSQL integrated). Do not put SQL passwords in specs.

If a **named Grok Bot** (Bob, Haitch, ...) is silent in chat, follow `unstick-grok-bot`. This skill is the Windows pull-worker and job queue.

## Load (local-exec on the target computer)

```powershell
$repo = if (Test-Path 'D:\ai\agentic_build') { 'D:\ai\agentic_build' } elseif (Test-Path 'C:\ai\agentic_build') { 'C:\ai\agentic_build' } else { 'C:\src\agentic_build' }
Import-Module "$repo\src\BobBridge.psd1"
```

`-Machine` is an id (`marchhare`, `dev1`, `ionos`), not a hostname. Local-exec if this box is the target; otherwise enqueue and that machine's watcher claims it. Never WinRM. Never a Windows service.

## Cmdlets

```powershell
Get-BobMachines
Get-BobHealth
Get-BobGhPostingReadiness          # gh present + auth probe for product repo
Get-BobCapacity
Select-BobGitWorker                  # optional -Machine / -Fuel
Start-BobBuild -Task git -Goal '...' -Profile generic -ReplyChannel $env:USERNAME
Start-BobBuild -Machine ionos -Fuel grok-build -Cwd $repo -Goal '...' -Profile formprep
Get-BobBuild -JobId <id>
Get-BobBuilds -Machine ionos
Send-BobBuildSpec -JobId <id> -Prompt 'follow-up'
Stop-BobBuild -JobId <id>
```

`-Task git` makes `-Machine` optional: `Select-BobGitWorker` picks a
`(machine, fuel)` pair (Cursor Models remaining > 0 then grok-build;
copilot only with `-AllowCopilot`). Pin with both `-Machine` and `-Fuel`.
`-Fix` re-runs the picker. Mode 3 DUMB / 2012 is not a git worker. Cursor
Models remaining % is the shared top-bar pool, not a machine named cursor.

Models (`config/default.json` `models`): **PR / build** = Cursor Composer
`composer-2.5`, or `build0.1` when `grok models` lists it else
`buildGrokFallback` (`grok-4.5`). **MRB** = Cursor Grok `grok-4.6` on
cursor-agent, else grok.exe `grok-4.6`. Fuel: Cursor Models remaining > 0
then grok.exe. Never Other Models. `Resolve-BobGrokCliModel` maps unknown
grok `-m` ids so workers start. Transaction: `bob-build-loop`.

Human watcher UI: `bob-fleet-tray`. This grok.exe session on a build box, if it is the stall monitor: `bob-fleet-monitor` (do not dispatch or kill Bob's jobs).

`Test-PromptSecrets` refuses `password=` / `XAI_API_KEY=` **assignments**. Instructional mentions (`Do not set or request XAI_API_KEY`) must pass.

## Spec

GitHub repo work: picker may choose `copilot` (`start-bob-copilot` /
`tools\Start-BobCopilot.ps1`) or `cursor-models` (`start-bob-cursor` /
`tools\Start-BobCursor.ps1`). Fleet `grok.exe` jobs still get the copilot
constraint in `New-FleetPrompt`. Do not implement GitHub-only work on Grok
Bot weekly usage. Formprep / MSSQL stays `-Fuel grok-build`.

`Start-BobWorker` copies `https://github.com/SimonBarnett/agentic_build` `.grok/skills` into `~/.grok/skills` and puts that path on `--rules`, so the build agent has those skills even when `--cwd` is another repo.

`Start-BobBuild` packet: `goal`, `constraints`, `success`, `cwd`, `profile`, `reply_channel`, and for git tasks `task`, `machine`, `fuel`, `repo`, `branch`, `docs`, `plan`, `mrb`.

Profiles: `formprep` (`--rules`, no yolo, no SQL-flip UPD, no AllUnprepared, Windows MSSQL only), `teams`, `mud`, `generic`.

Poll `Get-BobBuild`. Worker pings `reply_channel` (Grok Bot name) queued/running/blocked/done. Fake-Grok off-DEV never pings live bots.

## Watcher dead

`Get-BobHealth.watcher_up` is a live `Watch-BobJobs.ps1` process (not `-Once`, not the tray). `last_seen` / `last_seen_age_sec` come from `machine.json`. `gh_posting` / `Get-BobGhPostingReadiness` reports whether this box can open issues on the product repo (live `gh auth status` + `repo view`, not token sniff). `Select-BobGitWorker -Kind mrb` requires `gh_posting.issue_posting_ready`. `lastSeen` is written at the start of each tick (idle `Invoke-BobFleetTick` included); a live claimed job holds the `-Once` child so age can exceed 90s while healthy.

### GitHub CLI on fleet workers

`Install-BobFleet` calls `Install-BobGitHubCliIfMissing` (winget `GitHub.cli` when absent) and prints readiness. Unattended auth: user-level **`GH_TOKEN`** (or `GITHUB_TOKEN`) with `issues:write` and `pull_requests:write`, or interactive `gh auth login` (Credential Manager). Never commit tokens. Rotate by updating the user env and re-probing `Get-BobGhPostingReadiness`.

A `BobFleet-<id>` task that is `Ready` with LastRunTime 1932 / result 267011 **never started** (registered after this logon).

```powershell
powershell -NoProfile -File "$repo\tools\Install-BobFleet.ps1" -MachineId <id> -CwdRoots <roots>
# Install demand-starts the task and sets ExecutionTimeLimit 0 (the poll loop is infinite; 72h would kill it).
Start-ScheduledTask -TaskName "BobFleet-<id>"   # if already registered
```

Prove idle watcher: `watcher_up=true` and `last_seen_age_sec` under 90. Prove busy watcher: `Get-BobBuilds -Lane running` plus live `grok.exe` with that job's session id. Do not restart a busy watcher.

## Stall monitor

See `bob-fleet-monitor` and `bob-fleet-tray`.

## Bobiverse (IRC, not SMB)

Machines cannot see each other's `bridgeHome` (flamingo/marchhare on bobnet, ionos VPS, DEV1 Azure). Status is a MODE2 **free** moot on `#bobiverse` over **private Ergo** `irc.ntsa.uk:6697` (not Libera). Nicks `bob-flamingo`, `bob-marchhare`, `bob-ionos`, `bob-dev1`. Skill `bob-irc` lives in **agentic_irc** (`.grok/skills/bob-irc`; this repo keeps a stub). Docs `docs/bobiverse.md`. One-shot: `Install-BobIrc.ps1`. Ongoing: `Watch-Bobiverse.ps1` (30s loop, **no grok.exe**) POINTs local BOB v1 into `bob-peers\`. Tray only reads those files.

## Skill harvest

When you learn a repeatable fleet/build fact in this job, follow `harvest-agent-skills` immediately (edit `.grok/skills`, harvest log, commit, push). Do not wait for the hourly task. IRC client and Ergo start/firewall harvests go to `https://github.com/SimonBarnett/agentic_irc`.

`tools\Install-SkillHarvest.ps1` registers `BobSkillHarvest-<id>` (hourly, not a Windows service). It enqueues `harvest-agent-skills`. Skip if a harvest job is already inbox/running.

## Spec / MRB loop

For functional-spec intake, PR dispatch, and hostile MRB (Bob **hands off**;
PASS-nits merges; FAIL spawns a worker; no PDFs) see `bob-build-loop`,
`bob-spec-intake`, `bob-build-dispatch`, `bob-hostile-mrb`, and
`cursor-mrb-dev`.

## Long builds (do not kill early)

config/default.json profiles.generic.timeoutSec defaults to **7200** (2h). Multi-phase gap-closes need that headroom. Do **not** lower it for real product work.

Monitor stalls with Watch-BobAgents.ps1 (ACTION_REQUIRED only). A quiet long run is OK — timeout is a safety net, not a productivity target. If Get-BobBuild stays unning with a live grok process, let it finish.