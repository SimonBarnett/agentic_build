---
name: bob-hostile-mrb
description: >
  Hostile Material Review Board of a build-agent push as a GitHub issue on the
  product repo, linked to the feature-request issue/doc. Git is the source of
  truth. Do not write MRB PDFs. Use when the user says MRB, hostile review,
  review the push, ready for UAT, or /bob-hostile-mrb.
---

# Hostile MRB (GitHub issue)

Git (the product repo's issues + `docs/feature-request-*.md`) is the single source of truth. **Do not generate `docs/mrb-*.pdf`.** A markdown comment on the issue is enough.

## Tone

Detailed and brutal. No credit for intent. Success gates in the feature request and `docs/build-and-test-plan.md` are the law.

## Source of truth

1. The **feature-request GitHub issue** (create one at intake if missing) and/or `docs/feature-request-<slug>-YYYY-MM-DD.md`.
2. The **build-and-test plan** in `/docs`.
3. The **diff** of this push vs that request.

If there is no issue yet: `gh issue create` on the product repo with title from the feature request, body pointing at the md path, labels `feature-request`. Then MRB comments on **that** issue (or a child issue labeled `mrb` that `Fixes` / links it).

## Steps

1. Diff the new push against the parked feature request and `docs/build-and-test-plan.md`.
2. Run or cite automated evidence (Test-Pack, CI). Note what was **not** run.
3. Post the review with `tools/Start-BobMrb.ps1` (or `gh issue create` / `gh issue comment`):
   - Title: `MRB FAIL|PASS-nits|PASS-UAT: <feature slug> <sha>`
   - Labels: `mrb` plus `mrb-fail` or `mrb-pass`
   - Body sections: **Verdict**, **Feature request** (issue URL + doc path), **Blockers**, **Nits**, **Evidence**, **Required fixes** (ordered)
4. If not PASS-ready-for-human-UAT: `Send-BobBuildSpec` (or IRC) with the **issue URL** and ordered fixes. Wait for the next push; comment again on the same issue.
5. Only Bob may declare **ready for human UAT**. Say that phrase in the issue when passing.

## Pass bar

- Feature-request MUST / MUST NOT honored
- Plan phases claimed as done have evidence
- Prior version folders intact on feature work
- No secrets in repo or prompts
- `/docs` markdown matches reality

## Fail bar (examples)

- ok=true without the documented gate
- Invented APIs
- Breaking v1 while adding v2
- Empty errors[] on failure paths the spec requires
