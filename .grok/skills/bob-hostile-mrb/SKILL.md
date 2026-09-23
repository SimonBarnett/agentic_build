---
name: bob-hostile-mrb
description: >
  Hostile Material Review Board of a worker PR as a GitHub issue. Bob hands
  the review off (Cursor Models, then grok.exe). He does not write the MRB
  in-session. PASS-nits: that MRB agent merges the PR. FAIL or remaining
  open issues (FRs and other actionable issues): dispatcher passes each
  to a new worker. No MRB PDFs. Use when the user says MRB, hostile
  review, review the push, ready for UAT, hand off MRB, missing features,
  or /bob-hostile-mrb. Loop table is bob-build-loop.
---

# Hostile MRB (GitHub issue)

Git (the product repo's issues + `docs/feature-request-*.md`) is the single
source of truth. **Do not generate `docs/mrb-*.pdf`.** Loop table:
`bob-build-loop`.

## Bob hands off (do this first)

Bob **does not write** the review in Grok Bot / this grok.exe session.
The implementer does not review their own PR. Dispatcher runs
`tools/Start-BobBuildLoop.ps1` (skill `bob-job-loop`) or, for a single
SHA, starts a **new** MRB worker (`Start-BobMrbHandoff`, `-Kind mrb`) as
soon as the PR exists. The driver comments the new URL on the prior FAIL
board.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Start-BobMrbHandoff.ps1 `
  -Repo owner/repo -Issue <feature-request-n> -Sha <pr-head> -Cwd C:\ai\<repo> `
  -Docs docs/feature-request-....md -Plan docs/build-and-test-plan.md
# default -Fuel cursor-models; grok-build only when Cursor Models remaining is 0
# or cursor-agent is missing
```

Default is Cursor Agent (`cursor-agent.cmd`, never `~\.grok\bin\agent.exe`)
on Cursor Grok (`config/default.json` `models.mrbCursor`, `grok-4.6`).
Grok Build fallback uses `models.mrbGrok` (`grok-4.6` on grok.exe). PR
workers use Composer `composer-2.5` or `build0.1` / `grok-4.5`. Never Other
Models. Copilot only with `-AllowCopilot`.

**Grok-build fallback is dispatcher-local until issue #11.** Run the handoff
on the machine that will post.

After a FIX **PR**, hand off **again** on the **new head SHA**. The worker
opens a **new** MRB issue (title includes that SHA). Comment the new URL on
the prior FAIL issue. Review that SHA only.

IRC verb `MRB <job> <nick>` is the machine nick; fuel is in the job file.

**Chair:** only Bob may declare **ready for human UAT**. Worker posts `FAIL`
or `PASS-nits` only. PASS-nits **includes merge**. If the worker thinks it
passed UAT, they write `candidate PASS-UAT, Bob stamp required`.

## PASS-nits MUST close, merge, and pull (Simon 2026-09-22 — VERY important)

A PASS-nits that leaves git dirty is not finished. The MRB worker MUST,
in this order, before the driver prints DONE:

1. **Merge** the reviewed PR (`gh pr merge --merge` — non-interactive
   `gh` requires a strategy). Do not claim merged unless that command
   succeeded (or `gh pr view` is already MERGED).
2. **Close finished issues**: the feature-request issue, **every** prior
   FAIL MRB board for this FR, and this PASS-nits issue. Each close
   comment links the merged PR URL.
3. **Pull completed PRs** on the product checkout and isolated worktrees
   (`git fetch` + fast-forward `main` / default branch to the merge SHA).
   The next FR must not start on stale main. Dispatcher verifies
   `origin/main` contains the merge commit before `start_build` on a
   remaining issue.

The loop finish race (`FAILED: PASS-nits finish: PR still open after gh
pr merge`) is not a reason to skip close/pull. If the PR is already
MERGED and the FR is CLOSED, treat DONE, then still pull.

Escape hatch: if Cursor Agent and grok.exe both cannot start, Bob writes the
MRB himself using the rest of this skill. Say that in the issue.

## Tone (worker)

Detailed and brutal. No credit for intent. Success gates in the feature
request and `docs/build-and-test-plan.md` are the law.

## Source of truth

1. The **feature-request GitHub issue** and/or `docs/feature-request-<slug>-YYYY-MM-DD.md`.
2. The **build-and-test plan** in `/docs`.
3. The **PR diff** vs that request.
4. **Open issues** labeled `feature-request`.

If there is no issue yet: `gh issue create` with label `feature-request`,
then MRB comments on that issue (or a child labeled `mrb`).

## Missing features (every MRB)

Before the verdict, walk:

1. MUST / MUST NOT / acceptance IDs on **this** FR + plan vs the PR.
2. Other open GitHub issues vs `/docs` vs the PR head.
3. Holes the PR made visible that **no** FR covers.

| Gap | Action |
|---|---|
| This FR's acceptance still red | **Required fix** on this MRB issue. Do not open a second FR for the same MUST. Dispatcher starts a **new** FIX worker. |
| Adjacent / unspecified hole, or an issue with no intake doc | **Request it**: park via `bob-spec-intake`. Link from **Missing features**. Dispatcher starts a **new** worker for that FR. |
| Already parked issue+doc, not in this PR | List under Missing features with the issue URL. Do not duplicate. Dispatcher starts a **new** worker if none is running. |

Do not implement the missing feature in the MRB job. Listing alone is not
enough — the dispatcher must hand remaining FRs to new workers
(`bob-job-loop`).

## Worker steps

Score the review SHA only. If the shared checkout HEAD is a different
job, add a detached worktree at that SHA. Do not `reset` / `checkout`
away from another worker's branch. Do not score later commits or dirty
files. A GitHub `CONFLICTING` PR is FAIL even when this SHA's
acceptance is green in isolation: PASS-nits includes `gh pr merge`.
Re-read `mergeable` immediately before posting PASS-nits. A stale
`CLEAN` can go `DIRTY` while the board is written. If `gh pr merge`
then fails, that PASS-nits is void: open a **new** FAIL issue on the
same SHA (do not reuse the pass board). Comment the FAIL URL on the
voided issue. If you then see the **same PR already MERGED** (another
worker scored a later head, or `gh pr view` is MERGED), close that
leftover FAIL with the merged PR URL. Do **not** start FIX. Pull
main. Do not claim you merged unless your `gh pr merge` succeeded.
`gh pr merge` can print `already merged` and still exit 0. That is
not this worker's merge. Parse stdout. Do not write `Merged <url>`
unless this process created the merge commit.

1. Diff the PR against the parked feature request and plan.
2. Run the missing-features check. File any new FRs before or with the MRB post.
3. Run or cite automated evidence (Test-Pack, CI). Note what was **not** run.
4. Post with `tools/Start-BobMrb.ps1`:
   - Title: `MRB FAIL|PASS-nits: <feature slug> <sha>`
   - Labels: `mrb` plus `mrb-fail` or `mrb-pass`
   - Body: **Verdict**, **Feature request**, **Missing features**, **Blockers**, **Nits**, **Evidence**, **Required fixes**, **PR**
   - Worker must not use verdict `PASS-UAT` (Bob stamp).
5. **FAIL:** do not merge. Required fixes only. Dispatcher starts a **new**
   FIX worker (`cursor-mrb-dev` / `bob-job-loop`). Do not reuse this FAIL
   issue as the next board.
6. **PASS-nits:** merge the PR (`gh pr merge --merge`). Nits stay listed; they do
   not block the merge. After merge succeeds, close the feature-request
   issue, **every** prior FAIL MRB board for this FR (all FAIL cycles on
   the loop board, not only the latest), and this PASS-nits issue. Each
   close comment links the merged PR URL. Do not write that the PR merged
   unless `gh pr merge` succeeded.
7. **Remaining issues / feature requests:** after FAIL or PASS-nits, the
   dispatcher must pass work to **new** workers for (a) this FAIL's
   Required fixes (FIX worker), and (b) **any other open actionable
   issues** — not only those labeled `feature-request` (Simon
   2026-09-22: bob-job checks open issues as well as FRs). Skip pure
   MRB meta boards. Missing features just parked count. Listing under
   Missing features is not enough — hand each to `bob-job-loop`.
   Remaining issues do not block this PASS-nits merge.
8. **No Bob, still open issues — do not sit (Simon 2026-09-22):** if you
   just MRB'd and Bob is not on channel / not assigning, **do not leave
   remaining open issues idle**. Find someone: ask `#bobiverse` for a
   spare seat, or launch the next `bob-job-loop` yourself on another
   open actionable issue. Waiting for Bob to notice is a bug. Harvest
   this playbook when you learn it (`harvest-agent-skills`).

## Pass bar

- Feature-request MUST / MUST NOT honored
- Plan phases claimed as done have evidence
- Missing features either requested (issue+doc) or explicitly out of scope
- Prior version folders intact on feature work
- No secrets in repo or prompts
- `/docs` markdown matches reality
- PR is merged by this MRB worker

## Fail bar (examples)

- ok=true without the documented gate
- Invented APIs
- Breaking v1 while adding v2
- Empty errors[] on failure paths the spec requires
- Code landed with no FR, or an open issue with no intake doc, and the MRB did not request them
- Worker pushed `main` or merged their own PR
- Bob wrote the full MRB in-session when Cursor Agent or grok.exe could take it
