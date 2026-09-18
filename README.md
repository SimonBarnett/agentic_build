# agentic_build

Any Grok Bot starts Grok Builds on named machines. Skill: `.grok/skills/grok-build-fleet`. Grok Bot desktop runs on every build box; `grok.exe` is the Windows logon user (MSSQL integrated auth).

- Skill cmdlets: `Start-BobBuild`, `Get-BobBuild`, `Send-BobBuildSpec`, `Stop-BobBuild`.
- Pull worker `tools/Watch-BobJobs.ps1` (logon task, not a Windows service).
- Named bots (`-Agent Bob`) still use the Grok Bot API. Form Prep stays `--rules`, never `--always-approve`.
- Off-DEV Fake-Grok never touches live bots or GitHub.

## Off-DEV (no real grok)

```powershell
powershell -NoProfile -File .\tools\Test-Pack.ps1
```

Points `BOB_GROK_EXE` at `tools/Fake-Grok.ps1` and uses a temp `BOB_BRIDGE_HOME`. Must not touch `%USERPROFILE%\.grok\bob-bridge`.

## Use

```powershell
Import-Module .\src\BobBridge.psd1
Register-BobMachine -Id marchhare -CwdRoots D:\ai
Start-BobBuild -Machine marchhare -Cwd D:\ai\agentic_build -Goal 'ping' -Profile generic
powershell -NoProfile -File .\tools\Watch-BobJobs.ps1 -Once
Get-BobBuild -JobId <id>
```

Install the logon watcher + user skill copy (not a Windows service):

```powershell
powershell -NoProfile -File .\tools\Install-BobFleet.ps1 -MachineId marchhare
```

Form Prep on DEV1 still uses grok.exe:

```powershell
$env:BOB_GROK_EXE = "$env:USERPROFILE\.grok\bin\grok.exe"
Start-BobWorker -Cwd D:\work\formprep -Prompt 'PONG' -Profile formprep
```

`BOB_TRANSPORT=cli` forces grok.exe. `BOB_GROK_BOT_HOME` overrides the Grok Bot profile dir.

## Layout

```
agent_readme.md  handover for any Grok Bot (attach this)
.grok/skills/    grok-build-fleet skill (agent interface)
docs/            freeze PDF + wp0-recon.md
schemas/       health overlay status completion prompt-packet
src/           BobBridge module (Public/Private)
config/        default.json profiles
tools/         Fake-Grok, Test-Pack, Watch-BobJobs, Install-BobFleet
tests/         last-dev-run.md template
```
