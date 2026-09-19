---
name: bob-hostile-mrb
description: >
  Hostile Material Review Board of a build-agent push: brutal detailed review as
  PDF (+ md) under /docs, then feed the review back to the build agent until Bob
  passes ready for human UAT. Use when the user says MRB, hostile review, review
  the push, ready for UAT, or /bob-hostile-mrb.
---

# Hostile MRB

## Tone

Detailed and brutal. No credit for intent. Success gates in the functional spec and build plan are the law. Missing tests, invented APIs, broken prior versions, secret leaks, and SDK-said-success without the SQL/file gate all fail.

## Steps

1. Diff the new push against the parked spec and `docs/build-and-test-plan.md`.
2. Run or cite available automated evidence (Test-Pack, CI, WP0). Note what was **not** run.
3. Write the review:
   - `docs/mrb-YYYY-MM-DD-vN.pdf` (and `.md` mirror)
   - Sections: verdict (FAIL / PASS-with-nits / PASS-ready-for-human-UAT), blockers, nits, evidence, required fixes ordered.
4. Commit and push to `/docs`.
5. If not PASS-ready-for-human-UAT:
   - `Send-BobBuildSpec -JobId <id> -Prompt` (or IRC) with the review URL/path and ordered fixes.
   - Wait for the next push, then repeat MRB.
6. Only Bob may declare **ready for human UAT**. Say that phrase explicitly when passing.

## Pass bar

- Spec MUST / MUST NOT honored
- Plan phases claimed as done have evidence
- Prior version folders intact on feature work
- No secrets in repo or prompts
- Docs in `/docs` match reality

## Fail bar (examples)

- ok=true without the documented gate
- Guessed Priority ENAMEs / WCF before PinComplete
- Join/UI clicks before gated unknowns are closed
- Breaking v1 while adding v2
- Empty errors[] on failure paths the spec requires