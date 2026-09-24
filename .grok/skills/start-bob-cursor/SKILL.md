---
name: start-bob-cursor
description: >
  Hand a git task to Cursor Agent (cursor-models fuel) on a live fleet box.
  Use when Select-BobGitWorker / Start-BobBuild -Task git picked cursor-models,
  the operator passed -Fuel cursor-models, /start-bob-cursor, or a
  cursor-mrb-dev FIX/MRB launch. Shop IRC: bob-shop-worker.
---

# Start Bob Cursor

Peer of `start-bob-copilot`. Reached via the same capacity picker (`Select-BobGitWorker`), not a separate human ritual.

Bills Cursor Models (shared account pool: Cursor Grok + Composer). Not Grok
Build weekly. Not Other Models. Not Copilot credits. Bob still chairs UAT.
Transaction: `bob-build-loop`.

## Shop IRC

The launched agent (and this dispatcher, if it stays up) follows
`bob-shop-worker`: JOIN `#<machine-id>` as `w-<short>-<pid>`, set
`working_on` from `-Goal` / FR title, POST `reportUrl`. No `!report`.
No `#bobiverse` JOIN from the worker. Canon: agentic_build #124.

## When

Picker selected `cursor-models`, `Start-BobBuild -Task git -Fuel cursor-models`, `Start-BobMrbHandoff`, or `cursor-mrb-dev`.

## Login

Binary is `%LOCALAPPDATA%\cursor-agent\cursor-agent.cmd` (or `.ps1`). Never `~\.grok\bin\agent.exe` (grok). `cursor-agent status` must show logged in. Login: `agent login` with `NO_OPEN_BROWSER=1` (prints a cursor.com URL). A Grok Bot Cursor token is **not** CLI auth.

## Kind / model

`-Kind mrb` -> Cursor Grok (`models.mrbCursor`, `grok-4.6`). `-Kind build`
(default) -> Composer `composer-2.5`. Confirm on the live `node.exe`
command line `--model`. Never Other Models.

## Command

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Start-BobCursor.ps1 `
  -Repo https://github.com/SimonBarnett/agentic_build `
  -Branch work/<job-id> `
  -Docs docs/feature-request-....md `
  -Plan docs/build-and-test-plan-....md `
  -Mrb https://github.com/SimonBarnett/agentic_build/issues/8 `
  -Goal '...' -Kind build -JobId <id> -Cwd <clone>
```

Call the script **in-process** (`& Start-BobCursor.ps1 -Goal $goal -Kind build`). Nested `powershell -File ... -Goal $unquoted` splits the goal on spaces and on tokens that look like flags.

Writes a packet JSON. Starts **cursor-agent** (`-p --model`) via `launch.ps1` that reads the prompt file. Pass the prompt **after `--`** so node does not eat tokens (`unknown option '-join'`). Goal text must not contain CLI-looking tokens (`-join`, `-p`, `-File`) or raw `"` that split node argv.

Do not put the prompt on `Start-Process -ArgumentList` (Windows splits quotes). Do not `Start-Process -RedirectStandardOutput` (PS 5.1 waits for the agent). Start with `Win32_Process.Create` so the agent outlives the grok.exe Job Object. Redirect inside `launch.ps1`. Skip empty Docs/Plan so the prompt is not `Read  and .`.

Watch **GitHub** (PR + MRB issue), not the redirected `.log` (stdout is
often empty until exit). Build kind: open a PR, do not merge. MRB kind:
PASS-nits merge that PR; FAIL do not merge. Does not scrape Cursor cookies.
Does not mark ready for human UAT.

## Packet

```
task: git
fuel: cursor-models
repo / branch / docs / plan / mrb
return: PR URL (build) or MRB issue + merge-or-not (mrb)
```

No vendor name required in IRC verbs (`SPEC` `WAIT` `BUILD` `PUSH` `MRB` `FIX` `UAT`).
