---
name: bob-hostile-mrb
description: >
  Hostile Material Review Board of a build-agent push as a GitHub issue on the
  product repo, linked to the feature-request issue/doc. Check the tree for
  missing features and file feature-request issues for them. Git is the source
  of truth. Do not write MRB PDFs. Use when the user says MRB, hostile review,
  review the push, ready for UAT, missing features, or /bob-hostile-mrb.
---

# Hostile MRB (GitHub issue)

Git (the product repo's issues + `docs/feature-request-*.md`) is the single source of truth. **Do not generate `docs/mrb-*.pdf`.** A markdown comment on the issue is enough.

## Tone

Detailed and brutal. No credit for intent. Success gates in the feature request and `docs/build-and-test-plan.md` are the law.

## Source of truth

1. The **feature-request GitHub issue** (create one at intake if missing) and/or `docs/feature-request-<slug>-YYYY-MM-DD.md`.
2. The **build-and-test plan** in `/docs`.
3. The **diff** of this push vs that request.
4. **Open issues** on the product repo labeled `feature-request` (and unlabeled English tasks that are actually FRs).

If there is no issue yet: `gh issue create` on the product repo with title from the feature request, body pointing at the md path, labels `feature-request`. Then MRB comments on **that** issue (or a child issue labeled `mrb` that `Fixes` / links it).

## Missing features (do this every MRB)

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

Request means **file the issue and the markdown**, then push. Do not implement the missing feature in the MRB job. Do not claim UAT-ready while requested FRs that this product needs for the stamp are still open (Bob decides which are in-scope for this stamp).

## Steps

1. Diff the new push against the parked feature request and `docs/build-and-test-plan.md`.
2. Run the missing-features check above. File any new FRs before or with the MRB post.
3. Run or cite automated evidence (Test-Pack, CI). Note what was **not** run.
4. Post the review with `tools/Start-BobMrb.ps1` (or `gh issue create` / `gh issue comment`):
   - Title: `MRB FAIL|PASS-nits|PASS-UAT: <feature slug> <sha>`
   - Labels: `mrb` plus `mrb-fail` or `mrb-pass`
   - Body sections: **Verdict**, **Feature request** (issue URL + doc path), **Missing features** (issue URLs opened or already parked), **Blockers**, **Nits**, **Evidence**, **Required fixes** (ordered)
5. If not PASS-ready-for-human-UAT: `Send-BobBuildSpec` (or IRC) with the **issue URL** and ordered fixes. Wait for the next push; comment again on the same issue.
6. Only Bob may declare **ready for human UAT**. Say that phrase in the issue when passing.

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
