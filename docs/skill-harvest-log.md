# Skill harvest log

## 2026-09-24 - standard MRB worker process (tests-first, PASS merge, one fix PR)

Simon: make the new MRB process STANDARD for all workers doing MRB.
New skill `bob-mrb-worker` (mermaid + standing steps). PASS merges the
PR; FAIL opens exactly one fix PR then merges original + fix (not a
FIX-worker chain). Handoff/board skills (`bob-hostile-mrb`,
`cursor-mrb-dev`, `bob-job-loop`, `bob-build-loop`, `bob-build-dispatch`,
`start-bob-cursor`) and README point here. Free-agent setup must harvest
`bob-mrb-worker` into the seat context (`setup-remote-grok-bot`,
`agent-monitor-setup`). Jeeves announces; shop channel only; report
agent+model on webhook; no UAT stamp by worker. Foundation honesty box:
`harvest-agent-skills`.

## Historical entries (merge note)

Entries dated 2026-09-23 and earlier remain on `main` at
`docs/skill-harvest-log.md` (pre-harvest tip `46b496d`). When merging this
PR: **prepend** the 2026-09-24 section above onto main's existing log.
Do not replace main's historical harvest log with this file alone.
