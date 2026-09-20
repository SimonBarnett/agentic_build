---
name: cursor-mrb-dev
description: >
  Run Cursor Agent for hostile MRB then FIX until PASS-nits on a product repo.
  Use when the user says cursor mrb, mrb until pass, cursor builder, re-mrb,
  mrb/dev loop, or /cursor-mrb-dev. Launch mechanics are start-bob-cursor.
  Verdict rules are bob-hostile-mrb. Bob still stamps UAT.
---

# Cursor MRB / FIX until PASS-nits

Default fuel: `cursor-models`, then `grok-build`. Copilot only with `-AllowCopilot`.

Bob does not write the MRB or the code in this grok.exe session. Hand off, watch GitHub, repeat.

## Models

`Get-BobJobModel -Kind mrb|build -Fuel cursor-models|grok-build` (`config/default.json` `models`).

| Kind | Cursor | grok.exe |
|---|---|---|
| mrb | latest reasoning (`claude-opus-5-thinking-high`) | `grok-4.6` |
| build | `composer-2.5` | `build0.1` if listed, else `grok-4.5` |

Do not use the MRB model for implementation. Catalog mapping: `grok-build-fleet` / `Resolve-BobGrokCliModel`.

## Login

`start-bob-cursor`: `cursor-agent status` must be logged in. Never `~\.grok\bin\agent.exe` (that is grok). If Cursor is not logged in, `Start-BobMrbHandoff` falls back to grok-build.

## GitHub posting (preflight)

Before `Start-BobMrbHandoff` starts Cursor or grok-build, the **worker box** must be able to open MRB issues:

1. `gh.exe` on PATH, under `%ProgramFiles%\GitHub CLI\`, or under `%LOCALAPPDATA%\GitHubCLI\` / `%LOCALAPPDATA%\Programs\GitHub CLI\` (see `Get-BobGhExe` in `tools/Bob-Gh.ps1`).
2. **Either** interactive `gh auth login` as a user with `issues:write` on the product repo, **or** non-interactive `GH_TOKEN` / `GITHUB_TOKEN` (same scopes). `gh auth status` honours those variables; preflight also runs one cheap `gh repo view` on the product repo so the token is live, not merely present.

On the `grok-build` fallback, `Start-BobMrbHandoff.ps1` refuses to enqueue when the picker selects a **remote** machine it cannot verify; only this box's posting path is probed when worker and dispatcher are the same machine.

If preflight fails, fix auth on that machine first — do not burn the MRB reasoning model on a review that cannot be posted.

Workers post via `tools/Start-BobMrb.ps1` (creates missing `mrb` / `mrb-pass` / `mrb-fail` labels instead of failing after composing the body).

## Loop

1. Tip = named SHA or `origin/main`. Unrelated dirty files in the checkout are out of scope (do not stage them).
2. **MRB:** `tools/Start-BobMrbHandoff.ps1 -Repo owner/repo -Issue <fr-or-prior-fail> -Sha <sha> -Cwd <clone> -Fuel cursor-models`. That uses `-Kind mrb`. Wait for a **new** GitHub issue titled `MRB FAIL|PASS-nits: ... <sha>` (labels `mrb` + `mrb-fail` or `mrb-pass`). The prior FAIL issue is history, not this board.
3. **FAIL:** `tools/Start-BobCursor.ps1 -Kind build -Repo <url> -Cwd <clone> -Mrb <new-mrb-issue> -Goal <required fixes>`. Implement only this board's required fixes. Do not implement parked FRs or a live walk this box cannot do. Comment on the MRB issue with the new SHA, tests, and which fixes are green vs still red.
4. Repeat step 2 on the new SHA until **PASS-nits**.
5. Only **Bob** stamps **ready for human UAT**. Worker never writes those words.

Launch, prompt quoting, and Job Object detach: `start-bob-cursor`. Missing-features / FAIL vs PASS-nits bars: `bob-hostile-mrb`.

## Watch

Watch the **GitHub issue**, not the redirected `.log` (cursor-agent stdout is often empty until exit). Confirm the live `node.exe` command line has `--model claude-opus-5-thinking-high` (MRB) or `--model composer-2.5` (FIX).

## Hard

- No MRB PDFs.
- No `password=` / `XAI_API_KEY=` assignments in goals or git.
- Do not burn Grok Bot weekly on this loop when Cursor or grok.exe can take it.
