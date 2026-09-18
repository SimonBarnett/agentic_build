# agentic_build

Thin adapter for Simon's Grok Bots (Bob, Haitch, Merc, …). Freeze PDF still covers the grok.exe Form Prep path.

- Named agents (`-Agent Bob`) talk to Grok Bot over `aiserver.v1.GrokBotService`. No SendKeys, no extra TUI.
- `grok.exe -p` oneshot stays for Form Prep and for Fake-Grok off-DEV tests.
- Form Prep default: `--rules`, never `--always-approve` / `--yolo`.
- Off-DEV (`BOB_GROK_EXE=tools\Fake-Grok.ps1`) never touches the live Grok Bot API.

## Off-DEV (no real grok)

```powershell
powershell -NoProfile -File .\tools\Test-Pack.ps1
```

Points `BOB_GROK_EXE` at `tools/Fake-Grok.ps1` and uses a temp `BOB_BRIDGE_HOME`. Must not touch `%USERPROFILE%\.grok\bob-bridge`.

## Use

```powershell
$env:BOB_BRIDGE_HOME = "$env:USERPROFILE\.grok\bob-bridge"
Import-Module .\src\BobBridge.psd1
Get-BobHealth
Get-BobAgents
Start-BobWorker -Cwd . -Prompt 'ping' -Agent Bob
Send-BobPrompt -SessionId <id> -Prompt 'status?'
Stop-BobWorker -SessionId <id>   # InterruptGrokBotAgentRun
```

Form Prep on DEV1 still uses grok.exe:

```powershell
$env:BOB_GROK_EXE = "$env:USERPROFILE\.grok\bin\grok.exe"
Start-BobWorker -Cwd D:\work\formprep -Prompt 'PONG' -Profile formprep
```

`BOB_TRANSPORT=cli` forces grok.exe. `BOB_GROK_BOT_HOME` overrides the Grok Bot profile dir.

## Layout

```
docs/          freeze PDF + wp0-recon.md
schemas/       health overlay status completion prompt-packet
src/           BobBridge module (Public/Private)
config/        default.json profiles
tools/         Fake-Grok, Test-Pack, Invoke-Recon, Install-OnDev
tests/         last-dev-run.md template
```
