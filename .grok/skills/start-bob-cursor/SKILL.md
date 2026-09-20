---
name: start-bob-cursor
description: >
  Hand a git task to Cursor Agent (cursor-models fuel) on a live fleet box.
  Use when Select-BobGitWorker / Start-BobBuild -Task git picked cursor-models,
  the operator passed -Fuel cursor-models, or /start-bob-cursor.
---

# Start Bob Cursor

Peer of `start-bob-copilot`. Reached via the same capacity picker (`Select-BobGitWorker`), not a separate human ritual.

Bills Cursor Models (shared account pool on every Cursor-capable box). Not Grok Build weekly. Not Copilot credits. Bob still chairs MRB / UAT.

## When

Picker selected `cursor-models`, or `Start-BobBuild -Task git -Fuel cursor-models`.

## Command

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Start-BobCursor.ps1 `
  -Repo https://github.com/SimonBarnett/agentic_build `
  -Branch work/<job-id> `
  -Docs docs/feature-request-....md `
  -Plan docs/build-and-test-plan-....md `
  -Mrb https://github.com/SimonBarnett/agentic_build/issues/8 `
  -Goal '...' -JobId <id> -Cwd <clone>
```

Writes a packet JSON. Starts **`cursor-agent.exe`** (`-p`). Never `~\.grok\bin\agent.exe` (that file is grok). Does not scrape Cursor cookies. Does not mark ready for human UAT.

## Packet

```
task: git
fuel: cursor-models
repo / branch / docs / plan / mrb
return: issue comment + POINT UAT
```

No vendor name required in IRC verbs (`SPEC` `WAIT` `BUILD` `PUSH` `MRB` `FIX` `UAT`).
