# Skill harvest log

## 2026-09-20

MRB is a GitHub issue (`Start-BobMrb.ps1`, skill `bob-hostile-mrb`). No MRB PDFs. Feature-request issue + `/docs` markdown is the source of truth.

## 2026-09-20 (copilot)

Harvested `start-bob-copilot`: Grok starts GitHub Copilot cloud agent via `tools/Start-BobCopilot.ps1` (`gh api` user token). Fleet prompt passes that skill so a build `grok.exe` offloads GitHub repo work instead of burning Cursor weekly usage.

## 2026-09-20 — bob-fleet-tray diagnostics harvest (ionos)

Promoted live tray diagnostics into `.grok/skills/bob-fleet-tray/SKILL.md`:
click-only TipForm (no hover), blank NotifyIcon.Text, `#Bobiverse (machine)`
title, seat deals beside names (`config/bob-seats.json`), shared weekly % for
ntsa (marchhare + ce-priority-dev1), cursor overage as red negative pounds from
`tip_cursor.json`, Suspend/Resume redraw to stop poll flash, single-instance
mutex + Restart watcher kill-all. Trigger: recycle Watch-BobTray only after
card/hover changes.

## 2026-09-20 — bob-fleet-tray blank-card + real GBP overage (ionos UAT)

- Dropped WM_SETREDRAW from Suspend/Resume-BobTrayPaint (SuspendLayout only).
- Rebuild-BobTrayTiles formats cursor/seat labels before Controls.Clear.
- Inline overage-red check (no Test-BobCursorOverageLabel from tray).
- Get-CursorAgentUsage.py: spendLimitUsage.individualUsed → GBP via er-api.
- Skill rewritten with diagnose steps for blank card + no-dialog compile fail.


## 2026-09-20 — cursor/xAI remaining + reset dates

- Harvested into `box-usage` and `bob-fleet-tray`: Get-BobWeeklyRemaining / Get-BobCursorAgentWeeklyRemaining / Format-BobResetLabel / IRC reset= / TipForm headings.
- Import-BobIrcPeerTranscript keeps prior period_end when POINT lacks reset=.
