# Agent handover — Grok Build fleet

You dispatch **Grok Builds** (`grok.exe`) on named Windows machines. You do not WinRM, you do not install a Windows service, and you do not put SQL passwords in prompts.

Grok Bot desktop is running on every build machine. `grok.exe` runs as the **Windows logon user**. That user already has MSSQL (integrated auth).

Repo: `https://github.com/SimonBarnett/agentic_build`  
Local clones: `D:\ai\agentic_build` (marchhare), `C:\src\agentic_build` (dev1, if present).

Skill (same facts, auto-load on grok.exe): `.grok/skills/grok-build-fleet/SKILL.md`

## Machines

`-Machine` is an id, not a guessed hostname.

| id | Role |
|---|---|
| `marchhare` | This dual-homed Windows box (Grok Bot + adapter). |
| `dev1` | Form Prep / Priority. Profile `formprep`. |
| `ionos` | Public media host. Later. |

`Get-BobMachines` lists who has heartbeated. If this box is new: `Register-BobMachine -Id <id> -CwdRoots <allowed roots>`.

## Load (local-exec on the target computer)

```powershell
$repo = if (Test-Path 'D:\ai\agentic_build') { 'D:\ai\agentic_build' } else { 'C:\src\agentic_build' }
Import-Module "$repo\src\BobBridge.psd1"
```

The pull worker `tools\Watch-BobJobs.ps1` (logon task) claims **this** machine’s inbox and runs the build. If you enqueue for another id, that machine’s watcher runs it.

## Start a build

```powershell
Start-BobBuild `
  -Machine marchhare `
  -Cwd $repo `
  -Profile generic `
  -Goal '<what to do>' `
  -Constraints @('<hard limit>', '<hard limit>') `
  -Success '<how we know it worked>' `
  -ReplyChannel '<your Grok Bot name: Bob, Haitch, Merc, …>'
```

Tell the human the `jobId`. Then poll:

```powershell
Get-BobBuild -JobId <jobId>
Get-BobBuilds -Machine marchhare
```

`lane` is `inbox` → `running` → `outbox`. `state` is `running` / `done` / `failed` / `blocked` / `stopped`. Outbox includes `completion.status` (`ok`/`failed`/`blocked`/`stopped`) and `completion.summary`.

Follow-up spec on a live job:

```powershell
Send-BobBuildSpec -JobId <jobId> -Prompt '<extra instruction>'
```

Stop:

```powershell
Stop-BobBuild -JobId <jobId>
```

The worker also pings `-ReplyChannel` with queued / running / blocked / done. Off-DEV Fake-Grok never pings live bots.

## Profiles

| Profile | When | Hard rules (also injected into grok.exe `--rules` unless yolo) |
|---|---|---|
| `formprep` | Priority Form Prep on dev1 | DEV only. Never SQL-flip UPD. Never AllUnprepared. Never commit secrets. MSSQL = Windows logon (integrated). Never SQL passwords. **No `--yolo` / `--always-approve`.** |
| `teams` | Teams audio / hours | No AccessMedia.All. Do not claim fixture speak is audible. |
| `mud` | MUD | No spend. Stay on configured host. |
| `generic` | Default | No production deploys. No force-push. |

## Spec contents

`goal` / `constraints` / `success` are the spec. Keep secrets out: `password=` or `XAI_API_KEY` in the goal is refused.

Point `cwd` at a repo the target machine can see, under that machine’s `cwdRoots`.

## What you tell the human

1. Machine + profile + `jobId`.
2. When `lane=outbox`: `state`, `completion.status`, `completion.summary`. Quote evidence, do not invent `ok`.
3. If `blocked` or `failed`: `completion.needs_human` and `next_suggested`.

## Do not

- WinRM / SSH / RDP to start grok.
- Windows service / SCM.
- `--always-approve` or `--yolo` on formprep.
- SQL passwords, `XAI_API_KEY`, or `password=` in packets.
- Claim a machine by hostname; use the id.
- Touch `%USERPROFILE%\.grok\bob-bridge` from Fake-Grok tests.
