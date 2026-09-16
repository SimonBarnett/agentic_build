# agentic_build

Thin Bob ↔ official `grok` adapter. Freeze is `docs/Bob_GrokBuild_Connector_Plan.pdf`.

- No Windows service, no `/v1` control plane, no SendKeys, no second session registry.
- MVP is oneshot: `grok -p` + `-r` for turn 2. Live ACP is WP3 only if resume fails.
- Form Prep default: `--rules`, never `--always-approve` / `--yolo`.
- TUI xor Bob. Workers always `--no-alt-screen`.

## Off-DEV (no real grok)

```powershell
powershell -NoProfile -File .\tools\Test-Pack.ps1
```

Points `BOB_GROK_EXE` at `tools/Fake-Grok.ps1` and uses a temp `BOB_BRIDGE_HOME`. Must not touch `%USERPROFILE%\.grok\bob-bridge`.

## Use

```powershell
$env:BOB_GROK_EXE = "$env:USERPROFILE\.grok\bin\grok.exe"
$env:BOB_BRIDGE_HOME = "$env:USERPROFILE\.grok\bob-bridge"
Import-Module .\src\BobBridge.psd1
Get-BobHealth
Start-BobWorker -Cwd D:\work\formprep -Prompt 'PONG' -Profile formprep
```

## Layout

```
docs/          freeze PDF + wp0-recon.md
schemas/       health overlay status completion prompt-packet
src/           BobBridge module (Public/Private)
config/        default.json profiles
tools/         Fake-Grok, Test-Pack, Invoke-Recon, Install-OnDev
tests/         last-dev-run.md template
```
