---
name: start-bob-copilot
description: >
  Start GitHub Copilot cloud agent on a SimonBarnett repo from this Grok
  session. Use when the user says start Copilot, assign Copilot, offload to
  Copilot, GitHub coding agent, or /start-bob-copilot. Bills GitHub Copilot
  credits, not Cursor weekly usage and not grok.exe.
---

# Start Bob Copilot

Repo work that can live on GitHub goes to Copilot. Do not implement that work with Grok Bot (Cursor weekly usage) or extra `grok.exe` when Copilot can take it.

Grok **hands off** by opening a GitHub issue that `@copilot`s Copilot, then tries the cloud-agent task API. If GitHub returns `CCA not enabled`, the issue is still the handoff — do not implement that work in Grok Bot or extra grok.exe.

## Command

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Start-BobCopilot.ps1 -Prompt '...' -Repo SimonBarnett/agentic_build -BaseRef main
# or -Issue <n> to assign copilot-swe-agent[bot]
```

Requires `gh.exe` logged in as SimonBarnett (user token). Installation tokens fail. If Copilot is missing from Assignees, enable cloud agent at github.com/settings/copilot/features.

See `docs/copilot-offload.md`.

## When Grok starts a build agent

`Start-BobWorker` copies this repo's `.grok/skills` (https://github.com/SimonBarnett/agentic_build) into `~/.grok/skills` and adds that path on grok.exe `--rules`. Fleet prompt also names `start-bob-copilot`. The build `grok.exe` should call `Start-BobCopilot.ps1` for GitHub repo work instead of Grok Bot.

Bob fleet jobs that need Windows logon (MSSQL) stay on `grok.exe`.
