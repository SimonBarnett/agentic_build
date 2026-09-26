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
- Follow bob-mrb-worker: NEW tests, run tests, hostile review.
- PASS: merge the PR (+ docs review if needed).
- FAIL: exactly one fix PR, then merge original + fix.
- Never MRB a PR you authored in the same implementer session.
```

## Guard

```
python tools/fr_self_merge_guard.py --repo OWNER/REPO --pr N --minutes 30 --json
# exit 2 → MRB-pending self-merge flag
```
