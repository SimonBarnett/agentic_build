---
name: grok-build-fleet
description: Start, spec, monitor, and stop Grok Builds on named machines (marchhare, dev1, ionos). Use when the user says start a grok build, run Form Prep on DEV1, dispatch a build, fleet job, Watch-BobJobs, Start-BobBuild, or /grok-build-fleet. Grok Bot is installed on every build machine; grok.exe runs as the Windows logon user (MSSQL integrated auth).
---

# Grok Build fleet

Any Grok Bot uses this skill. Grok Bot desktop is running on the target machine. Builds are `grok.exe -p` as the **logged-in Windows user** (that user has MSSQL). Do not put SQL passwords in specs.

## Cmdlets

From the `agentic_build` repo (local-exec on the target computer):

```powershell
$repo = 'D:\ai\agentic_build'   # or C:\src\agentic_build on DEV1
Import-Module "$repo\src\BobBridge.psd1"
Get-BobMachines
Start-BobBuild -Machine marchhare -Cwd $repo -Goal '…' -Profile generic -ReplyChannel $env:USERNAME
Get-BobBuild -JobId <id>
Get-BobBuilds -Machine marchhare
Send-BobBuildSpec -JobId <id> -Prompt 'follow-up'
Stop-BobBuild -JobId <id>
```

`Watch-BobJobs.ps1` (logon task, not a Windows service) claims inbox jobs on **this** machine and runs them.

## Spec

`Start-BobBuild` writes a prompt-packet: `goal`, `constraints`, `success`, `cwd`, `profile`, `reply_channel`.

Profiles: `formprep` (`--rules`, no yolo, no SQL-flip UPD, no AllUnprepared, Windows MSSQL only), `teams`, `mud`, `generic`.

## Updates

Poll `Get-BobBuild`. Worker also pings `reply_channel` (Grok Bot name or id) with running/blocked/done. Fake-Grok off-DEV never pings live bots.

## Targeting a machine

`-Machine` is an id (`marchhare`, `dev1`, `ionos`), not a hostname guess. If this computer is the target, local-exec here. If not, enqueue anyway; that machine's watcher picks it up. Never WinRM. Never a Windows service.
