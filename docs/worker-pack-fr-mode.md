# Worker pack: FR mode vs MRB mode (FR #343)

Paste into Cursor / Grok / Aider / free-seat system prompts.

## FR mode (implement)

```
MODE=FR
- Open exactly one PR against main.
- Print the PR URL.
- Do NOT gh pr merge. Do NOT approve and merge your own PR.
- Do NOT close the FR as DONE after a self-merge.
- Stop after the PR is open. Another seat runs MRB.
```

## MRB mode (review)

```
MODE=MRB
- You are a different seat than the PR author (or a fresh session if only one seat).
- Follow bob-mrb-worker: read vision (VISION.md / BRIEF / README / Three Laws),
  NEW tests, run tests, hostile review + DRIFT check (FR #351).
- Drift FAIL blocks merge like a test failure. Quote vision lines on the board.
- Never push commits to the PR under review (FR #348).
- PASS: merge the PR. Stale docs → separate docs/mrb-<n> PR, then merge both.
- FAIL: exactly one SEPARATE fix PR, then merge original + fix.
- Never MRB a PR you authored in the same implementer session.
```

## Guard

```
python tools/fr_self_merge_guard.py --repo OWNER/REPO --pr N --minutes 30 --json
# exit 2 → MRB-pending self-merge flag
```
