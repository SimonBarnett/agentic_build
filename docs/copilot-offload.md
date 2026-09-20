# Offload repo work to GitHub Copilot

Cursor/Grok Bot weekly usage is a different seat from Grok Build (`grok.exe` / xAI). GitHub Copilot cloud agent bills **SimonBarnett Copilot credits**.

## Agent start

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Start-BobCopilot.ps1 -Prompt 'Add tests for Watch-Bobiverse idle heartbeat'
```

Assign an existing issue:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Start-BobCopilot.ps1 -Issue 12
```

`gh auth login` as the GitHub user (not an installation token). Paid Copilot + cloud agent on: https://github.com/settings/copilot/features

## Not for

Bob fleet `Watch-BobJobs` / MSSQL integrated `grok.exe` on a build box.
