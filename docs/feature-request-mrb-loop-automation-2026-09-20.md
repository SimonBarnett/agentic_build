# Feature request: MRB loop automation — per-SHA board, back-link, off-DEV coverage

**Date:** 2026-09-20
**Repo:** https://github.com/SimonBarnett/agentic_build
**Raised by:** MRB worker (Cursor Models) while reviewing 6a53bd4 for issue #8
**UAT + hostile MRB owner:** Bob
**Related:** `.grok/skills/cursor-mrb-dev` (landed 6a53bd4), `.grok/skills/bob-hostile-mrb`

## Gap vs current tree

`cursor-mrb-dev` (landed in 6a53bd4) describes a loop: MRB the SHA → new
`MRB FAIL|PASS-nits: ... <sha>` issue → hand the Required fixes to a Cursor build
worker → re-MRB the new SHA → repeat until PASS-nits. Nothing in the tree drives
that loop. Today it is a human retyping `Start-BobMrbHandoff.ps1` with a new
`-Sha`, and the steps below have no code at all:

1. **Back-link.** `bob-hostile-mrb` says "Comment on the prior FAIL issue with the
   new URL." No tool does this. `Start-BobMrb.ps1` creates an issue and returns;
   it does not know the prior board.
2. **Loop driver.** No `Start-BobMrbLoop` / no state file recording
   `(feature issue, sha, mrb issue, verdict)` per pass, so nothing can answer
   "which SHA is the current board and how many passes has this FR burned".
3. **Fix handoff.** `cursor-mrb-dev` step 3 tells the operator to call
   `tools/Start-BobCursor.ps1 -Kind build -Mrb <issue>` by hand. The MRB issue's
   Required fixes are not read by anything; the goal text is retyped.
4. **Off-DEV coverage.** `tools/Test-Pack.ps1` has no case for the handoff path.
   `BT0 skills` only asserts `SKILL.md` exists and `name:` matches the folder. A
   regression in `Start-BobMrbHandoff.ps1` / `Start-BobCursor.ps1` argument
   plumbing ships green.

## Ask

1. A loop driver (name as fits existing nouns, e.g. `Start-BobMrbLoop` /
   `Get-BobMrbBoard`) that: resolves the tip SHA, hands off MRB, waits for the
   new `mrb`-labelled issue, and records the pass in a state file under the
   bridge root. No live GitHub in tests.
2. Auto back-link: when a new MRB issue is created for a FR that already has an
   open `mrb-fail` board, comment the new URL on the old board.
3. Fix handoff reads the Required fixes section out of the MRB issue body rather
   than requiring the operator to paste a goal.
4. Off-DEV Test-Pack cases (Fake-Grok / fixture, no live `gh`, no live
   `cursor-agent`) for: handoff argument plumbing, `-Kind` propagation from a job
   packet, fallback to `grok-build` when Cursor is not logged in, and the
   per-SHA title contract.

## Acceptance

1. Test-Pack green off-DEV with new cases; none of them touch live GitHub, live
   `%USERPROFILE%\.grok\bob-bridge`, or a live agent.
2. Given a fixture prior FAIL issue, the driver produces a back-link comment
   payload (asserted off-DEV, not posted).
3. Loop state file names the feature issue, each SHA, and each verdict.
4. `cursor-mrb-dev` / `bob-hostile-mrb` updated to point at the driver instead of
   describing manual repetition.
5. Worker still cannot emit `PASS-UAT`. Bob stamps UAT.

## Non-goals

- Changing the FAIL / PASS-nits bars (that is `bob-hostile-mrb`).
- Auto-merging or auto-closing the feature-request issue.
- Any MRB PDF.
- Letting the loop driver stamp ready for human UAT.
