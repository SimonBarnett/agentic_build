---
name: grok-build-fleet
description: >
  Start, spec, monitor, and stop Grok Builds on named machines (marchhare, dev1,
  ionos). Heal a dead Watch-BobJobs pull worker. Use when the user says start a
  grok build, run Form Prep on DEV1, dispatch a build, fleet job, Watch-BobJobs,
  Start-BobBuild, Get-BobHealth, Install-BobFleet, Watch-BobAgents, stalled
  watcher, or /grok-build-fleet. Named Grok Bot silent â†’ also load unstick-grok-bot.
  Grok Bot desktop is on every build machine; grok.exe is the Windows logon user
  (MSSQL integrated auth).
---

# Grok Build fleet

Any Grok Bot uses this skill. Builds are `grok.exe -p` as the **logged-in Windows user** (MSSQL integrated). Do not put SQL passwords in specs.

If a **named Grok Bot** (Bob, Haitch, â€¦) is silent in chat, follow `unstick-grok-bot`. This skill is the Windows pull-worker and job queue.

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
Start-BobBuild -Machine ionos -Cwd $repo -Goal 'â€¦' -Profile generic -ReplyChannel $env:USERNAME
Get-BobBuild -JobId <id>
Get-BobBuilds -Machine ionos
Send-BobBuildSpec -JobId <id> -Prompt 'follow-up'
Stop-BobBuild -JobId <id>
```

`Watch-BobJobs.ps1` (logon task `BobFleet-<id>`, not a Windows service) claims **this** machine's inbox.

`Test-PromptSecrets` refuses `password=` / `XAI_API_KEY=` **assignments**. Instructional mentions (`Do not set or request XAI_API_KEY`) must pass.

## Spec

`Start-BobBuild` packet: `goal`, `constraints`, `success`, `cwd`, `profile`, `reply_channel`.

Profiles: `formprep` (`--rules`, no yolo, no SQL-flip UPD, no AllUnprepared, Windows MSSQL only), `teams`, `mud`, `generic`.

Poll `Get-BobBuild`. Worker pings `reply_channel` (Grok Bot name) queued/running/blocked/done. Fake-Grok off-DEV never pings live bots.

## Watcher dead

`Get-BobHealth.watcher_up` is a live `Watch-BobJobs.ps1` process (not `-Once`). `last_seen` / `last_seen_age_sec` come from `machine.json`.

A `BobFleet-<id>` task that is `Ready` with LastRunTime 1932 / result 267011 **never started** (registered after this logon).

```powershell
powershell -NoProfile -File "$repo\tools\Install-BobFleet.ps1" -MachineId <id> -CwdRoots <roots>
# Install demand-starts the task and sets ExecutionTimeLimit 0 (the poll loop is infinite; 72h would kill it).
Start-ScheduledTask -TaskName "BobFleet-<id>"   # if already registered
```

Prove: `watcher_up=true` and `last_seen_age_sec` under 90.

## Stall monitor

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$repo\tools\Watch-BobAgents.ps1"
```

Stdout is ACTION_REQUIRED only. Handle:

| Token | Do |
|---|---|
| `watcher_down` | `Start-ScheduledTask BobFleet-<id>`; confirm heartbeat |
| `inbox_stale <jobId>` | watcher up? then `Get-BobBuild` |
| `running_orphan <jobId>` | worker process gone â†’ `Stop-BobBuild` |
| `agent_stall <name>` | load `unstick-grok-bot` for that name |

Do not exit the monitor on Grok Bot desktop restart. Diag log: `~\.grok\long-running-background-tasks\watch_bob_agents_<pid>.log`.

## Spec / MRB loop

For functional-spec intake, dispatch, and hostile MRB PDFs see ob-build-loop, ob-spec-intake, ob-build-dispatch, and ob-hostile-mrb.
