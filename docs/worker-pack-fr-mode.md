# Worker pack: FR mode vs MRB mode (FR #343) + UTF-8 no BOM (FR #347)

Paste into Cursor / Grok / Aider / free-seat system prompts.

## FR mode (implement)

```
MODE=FR
- Open exactly one PR against main.
- Print the PR URL.
- Do NOT gh pr merge. Do NOT approve and merge your own PR.
- Do NOT close the FR as DONE after a self-merge.
- Stop after the PR is open. Another seat runs MRB.
- Encoding (FR #347): read/write UTF-8 WITHOUT BOM.
  PS5: [IO.File]::WriteAllText($p,$s,(New-Object Text.UTF8Encoding $false))
  or . .\tools\Utf8NoBom.ps1 ; Write-Utf8NoBomFile ...
  Never Get-Content | Set-Content without explicit encodings.
```

## MRB mode (review)

```
MODE=MRB
- You are a different seat than the PR author (or a fresh session if only one seat).
- Follow bob-mrb-worker: NEW tests, run tests, hostile review.
- Never push commits to the PR under review (FR #348).
- PASS: merge the PR. If docs are stale, open a SEPARATE docs/mrb-<n>-... PR
  against main (references the original), then merge both. Do not commit onto
  the feature branch. Label docs PR as MRB docs if no second reviewer.
- FAIL: exactly one SEPARATE fix PR, then merge original + fix.
- Never MRB a PR you authored in the same implementer session.
- Encoding: on changed *.md run python tools/check_utf8_mojibake.py --root . PATHS
  Fail on UTF-8 BOM or mojibake.
- Guard: python tools/mrb_docs_branch_guard.py --repo OWNER/REPO --pr N
```

## Guard

```
python tools/fr_self_merge_guard.py --repo OWNER/REPO --pr N --minutes 30 --json
# exit 2 → MRB-pending self-merge flag
```

## Hung / slow seat (FR #353)

Load skill `bob-restart-worker-seat` before stopping a seat. Diagnose first
(slow TTFT vs hung vs out of tokens vs mis-bound slot 2). Ask the user before
restart. Never tray-stop a mis-bound seat 2. Never touch ear/Ergo/Jeeves.

## Encoding helpers

See `docs/utf8-no-bom.md`. Check: `python tools/check_utf8_mojibake.py --root .`
