---
name: bob-hostile-mrb
description: >
  Hostile Material Review Board of a build-agent push as a GitHub issue on the
  product repo. Bob hands the review off (Cursor Models, then Grok Build).
  He does not write the MRB in-session. Check for missing features and file
  FRs. No MRB PDFs. Use when the user says MRB, hostile review, review the
  push, ready for UAT, hand off MRB, missing features, or /bob-hostile-mrb.
---

# Hostile MRB (GitHub issue)

Git (the product repo's issues + `docs/feature-request-*.md`) is the single source of truth. **Do not generate `docs/mrb-*.pdf`.** A markdown comment on the issue is enough.

## Bob hands off (do this first)

Bob **does not write** the review in Grok Bot / this grok.exe session. That burns the wrong seat. Hand off, then wait for the GitHub issue.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Start-BobMrbHandoff.ps1 `
  -Repo owner/repo -Issue <feature-request-n> -Sha <head> -Cwd C:\ai\<repo> `
  -Docs docs/feature-request-....md -Plan docs/build-and-test-plan.md
# default -Fuel cursor-models; falls back to grok-build if cursor-agent.exe is missing
```

Default is Cursor Agent (`cursor-agent.exe`, never `~\.grok\bin\agent.exe` which is grok). Then Grok Build (`Start-BobBuild -Task git -Fuel grok-build`). Do not use Copilot unless `-AllowCopilot`.

Tell the human the issue URL. IRC verb `MRB <job> <nick>` is the machine nick; fuel is in the job file.

**Chair:** only Bob may declare **ready for human UAT**. The worker posts `FAIL` or `PASS-nits` only. If the worker thinks it passed, they write `candidate PASS-UAT, Bob stamp required`. Bob reads that issue and stamps the phrase, or rejects.

Escape hatch: if Cursor Agent and grok.exe both cannot start, Bob writes the MRB himself using the rest of this skill. Say that in the issue.

## Tone (worker)

Detailed and brutal. No credit for intent. Success gates in the feature request and `docs/build-and-test-plan.md` are the law.

## Source of truth

1. The **feature-request GitHub issue** (create one at intake if missing) and/or `docs/feature-request-<slug>-YYYY-MM-DD.md`.
2. The **build-and-test plan** in `/docs`.
3. The **diff** of this push vs that request.
4. **Open issues** on the product repo labeled `feature-request` (and unlabeled English tasks that are actually FRs).

If there is no issue yet: `gh issue create` on the product repo with title from the feature request, body pointing at the md path, labels `feature-request`. Then MRB comments on **that** issue (or a child issue labeled `mrb` that `Fixes` / links it).

## Missing features (every MRB)

Before the verdict, walk:

1. MUST / MUST NOT / acceptance IDs on **this** FR + plan vs the push.
2. Other open GitHub issues on the product repo vs `/docs` vs HEAD.
3. Holes the push made visible that **no** FR covers (landed code with no parked request; issue with no `docs/feature-request-*.md`; product surface the human asked for that is not in git).

Classify each gap:

| Gap | Action |
|---|---|
| This FR's acceptance still red | **Required fix** on this MRB issue. Do not open a second FR for the same MUST. |
| Adjacent / unspecified hole, or an issue with no intake doc | **Request it**: park via `bob-spec-intake` (`docs/feature-request-<slug>-YYYY-MM-DD.md` + GitHub issue `feature-request`). Link the new issue from **Missing features**. |
| Already parked issue+doc, not in this SHA | List under Missing features with the issue URL. Do not duplicate the issue. |

Request means **file the issue and the markdown**, then push. Do not implement the missing feature in the MRB job.

## Worker steps

1. Diff the new push against the parked feature request and `docs/build-and-test-plan.md`.
2. Run the missing-features check. File any new FRs before or with the MRB post.
3. Run or cite automated evidence (Test-Pack, CI). Note what was **not** run.
4. Post with `tools/Start-BobMrb.ps1` (or `gh issue create` / `gh issue comment`):
   - Title: `MRB FAIL|PASS-nits|PASS-UAT: <feature slug> <sha>`
   - Labels: `mrb` plus `mrb-fail` or `mrb-pass`
   - Body: **Verdict**, **Feature request**, **Missing features**, **Blockers**, **Nits**, **Evidence**, **Required fixes**
   - Worker must not use verdict `PASS-UAT` (Bob stamp).
5. If not a UAT candidate: `Send-BobBuildSpec` (or IRC) with the **issue URL** and ordered fixes. Wait for the next push; comment again on the same issue.

## Pass bar

- Feature-request MUST / MUST NOT honored
- Plan phases claimed as done have evidence
- Missing features either requested (issue+doc) or explicitly out of scope in the verdict
- Prior version folders intact on feature work
- No secrets in repo or prompts
- `/docs` markdown matches reality

## Fail bar (examples)

- ok=true without the documented gate
- Invented APIs
- Breaking v1 while adding v2
- Empty errors[] on failure paths the spec requires
- Code landed with no FR, or an open issue with no intake doc, and the MRB did not request them
- Bob wrote the full MRB in-session when Cursor Agent or grok.exe could take it
