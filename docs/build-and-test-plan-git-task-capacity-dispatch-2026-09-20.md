# Build-and-test plan: git-task capacity dispatch

**FR:** `docs/feature-request-git-task-capacity-dispatch-2026-09-20.md`  
**Issue:** https://github.com/SimonBarnett/agentic_build/issues/7  

## Steps

1. Read issue #7 + FR. Read `Start-BobBuild`, job schema, `Watch-BobJobs.ps1`, `bob-build-dispatch`, `grok-build-fleet`, `start-bob-copilot`, tray / peer-peek / `seat-period-end.json`.
2. Add fuel + task to job schema (do not break existing jobs). Fuels: `cursor-models`, `grok-build`, `grok-bot`, `copilot`, `on-demand`.
3. Add capacity snapshot: shared `cursor-models` pool (top bar) separate from per-machine `grok-bot` / `grok-build` rows. Machine row lists fuels it can run. Dumb-only = not git-eligible.
4. Implement picker (LOCKED order in FR). Included before on-demand. `-Machine` / `-Fuel` short-circuit.
5. `Start-BobBuild -Task git` (machine optional). Writes job `{machine, fuel, repo, branch, docs, plan, mrb}`.
6. Skill `start-bob-cursor` analogue of `start-bob-copilot`. Wire both into picker. If cloud launch is UNKNOWN, print the IDE packet and POINT WAIT rather than invent an API.
7. Watch-BobJobs: honour fuel; do not send git tasks to DUMB.
8. Optional IRC POINT mapping in `bob-irc` / bobstat: WAIT BUILD PUSH FIX UAT — no vendor words required this pass if existing POINT BOB v1 can carry status; document the verbs.
9. Fake-Grok / Test-Pack: picker unit tests only (fixture tray: cursor-models 1%, grok-bot 100%, ionos 0%, flamingo 15% → expect cursor-models on a Cursor-capable idle box).
10. README + dispatch skill one-paragraph. Commit/push. Point this issue. Bob hostile MRB.

## Success

Acceptance 1–10 on issue #7 green on main. Named `-Machine` generic/formprep jobs still start. No marketplace. No DUMB git worker.
