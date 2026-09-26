# FR #347: UTF-8 without BOM (stop README mojibake)

**Issue:** https://github.com/SimonBarnett/agentic_build/issues/347

## Acceptance

1. Worker packs + skills: UTF-8 no BOM; PS5 uses `UTF8Encoding $false` / `tools/Utf8NoBom.ps1`.
2. Repo helpers for files/outbox use no-BOM writes; tested.
3. `tools/check_utf8_mojibake.py` + pytest fail on BOM / mojibake in `*.md`; adoption notes for other fleet repos.
4. `bob-mrb-worker` checklist includes encoding/mojibake check on changed files.
