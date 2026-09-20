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

## Command

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Start-BobCopilot.ps1 -Prompt '...' -Repo SimonBarnett/agentic_build -BaseRef main
# or -Issue <n> to assign copilot-swe-agent[bot]
```

Requires `gh.exe` logged in as SimonBarnett (user token). Installation tokens fail. If Copilot is missing from Assignees, enable cloud agent at github.com/settings/copilot/features.

See `docs/copilot-offload.md`.

## When Grok starts a build agent

`Start-BobBuild` / fleet prompt includes: GitHub repo coding uses this skill. The build `grok.exe` should call `Start-BobCopilot.ps1` instead of doing that repo work itself.

Bob fleet jobs that need Windows logon (MSSQL) stay on `grok.exe`.
