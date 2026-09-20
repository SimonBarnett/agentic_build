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
