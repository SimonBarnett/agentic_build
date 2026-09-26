---
name: bob-mrb-worker
description: >
  STANDARD Material Review Board worker process for every seat that does MRB.
  Tests-first hostile review: after PASS, review docs for stale behavior; if
  needed open exactly one docs PR and merge it with the original. FAIL opens
  exactly one fix PR then merges original + fix. Use when the user says MRB, hostile review,
  review the push, Start-BobMrb, bob-mrb-worker, standard MRB process, or
  /bob-mrb-worker. Handoff launch: bob-hostile-mrb / cursor-mrb-dev. Loop:
  bob-job-loop. Bob alone stamps UAT.
github: https://github.com/SimonBarnett/agentic_build
---

# MRB worker (STANDARD)

Foundation: `harvest-agent-skills` (honesty box) -> report back to
https://github.com/SimonBarnett/agentic_build.

This is the **CAST IRON** process for **all** workers doing MRB — Cursor,
grok.exe, Copilot, free agents, talk seats, shop workers. Different worker
than the PR author. Do not invent a parallel ritual.

Handoff / board posting: `bob-hostile-mrb` + `tools/Start-BobMrbHandoff.ps1`.
Fuel / launch: `cursor-mrb-dev` / `start-bob-cursor`. Dispatcher: `bob-job-loop`.

## Standing process (verbatim)

1. Use `gh pr checkout` in a temporary worktree; read the PR intent + changed files
2. BEFORE testing: add any NEW tests appropriate to the PR
3. Run existing + new tests; perform the hostile review
4. PASS → review README, skills, `docs/`, mermaid diagrams, and usage/help text
   for anything the PR made stale. If docs are stale, open exactly ONE **separate**
   docs PR from branch `docs/mrb-<n>-...` against `main` (references the original
   PR). **Never push commits onto the PR under review** (FR #348). Merge the
   original and that docs PR together; if docs are OK, merge the original only.
   Then close the source issue/FR and hand off to a separate UAT worker; only
   Bob stamps UAT.
5. FAIL → create exactly ONE **separate** fix PR with the fix, then merge both
   (original + fix). Not multiple fix PRs. Never push the fix onto the reviewed
   branch either.
6. Jeeves announces whatever happens (merge / fix+merge)

```mermaid
flowchart LR
  A[gh pr checkout<br/>temp worktree] --> B[Read PR intent]
  B --> C[Add NEW tests]
  C --> D[Run tests +<br/>hostile review]
  D -->|PASS| E[Review docs vs<br/>new behaviour]
  E -->|docs stale| F[Separate docs/mrb-n PR<br/>never push to reviewed branch]
  E -->|docs OK| G[Merge PR]
  F --> G
  D -->|FAIL| H[Separate fix PR]
```

## FR mode vs MRB mode (FR #343 CAST IRON)

| Mode | Who | Allowed | Forbidden |
|------|-----|---------|-----------|
| **FR / implementer** | Dev seat | Open one PR, post URL, stop | `gh pr merge`, self-approve+merge, close FR after self-merge |
| **MRB** | **Different** seat (or **fresh session** if only one seat) | Tests-first review; PASS merge; FAIL one fix then merge both | Author MRB/merge of their own implementer PR in the same session |

Pack text: `docs/fr-mode-no-self-merge.md`, `docs/worker-pack-fr-mode.md`.  
Guard: `tools/fr_self_merge_guard.py` / `tools/Assert-FrPrNoSelfMerge.ps1` (flag self-merge within N minutes).

## Hard rules

- **Different worker than author.** Never MRB your own implementer PR.
- **FR authors never merge.** Opening the PR is the end of FR mode.
- **Tests before verdict.** New tests land on the review branch (or the
  single fix branch) before you claim PASS or FAIL. Run existing + new.
- **PASS → docs review, then merge (FR #348).** After tests and hostile review
  PASS, review README, skills, `docs/`, mermaid diagrams, and usage/help text for
  stale behavior. If anything is stale, open exactly **one separate** docs PR
  from `docs/mrb-<n>-...` against `main` (title/body reference the original PR)
  and merge it **with** the original; if docs are fine, merge the original only
  (`gh pr merge --merge`). **Never** `git push` / commit onto the branch under
  review. Where a second reviewer exists, the docs PR follows FR #343
  no-self-merge; otherwise label it clearly as MRB docs. Guard:
  `tools/mrb_docs_branch_guard.py`. Then close the source FR / issue, pull main,
  and hand off to a separate UAT worker. Only Bob stamps UAT.
- **FAIL → one fix PR only.** Do not spawn a chain of FIX workers / many
  fix PRs. Open **exactly one separate** fix branch/PR with the fix (include the
  new tests). Then merge **both** the original PR and that one fix PR.
  Jeeves announces both. Do not push the fix onto the reviewed branch.
- **No UAT stamp by worker.** Only Bob declares ready for human UAT. If
  you believe it is UAT-ready, write `candidate PASS-UAT, Bob stamp
  required` — never stamp UAT yourself.
- **Shop channel only** for worker IRC chatter about this MRB (machine
  shop `#<machine>`, not spam on `#bobiverse`).
- **Webhook report:** when posting report / completion webhook, include
  **agent + model** (e.g. cursor-agent `grok-4.6`, grok.exe `grok-4.6`).
- No MRB PDFs. No `password=` / `XAI_API_KEY=` assignments. Never Other
  Models. Copilot only with `-AllowCopilot`.

## After merge

Same duty as `bob-hostile-mrb`: close finished boards, pull completed
PRs onto product main, recycle-after-merge when merging `agentic_build`
or `agentic_irc` (Bob/ionos recycle; implementer PR workers do not
live-recycle).

## Free-agent harvest (CAST IRON)

When **setting up a free agent** (any seat that will do MRB), harvest
this process into that agent's instruction/context — link this skill
(`bob-mrb-worker`) so the next seat follows the same standard. Do not
leave MRB process only in chat memory.

## Related

| Concern | Skill |
|---|---|
| Hand off / GitHub MRB issue / PASS-nits board labels | `bob-hostile-mrb` |
| Fuel + FIX/MRB launch until done | `cursor-mrb-dev` |
| Driver `Start-BobBuildLoop.ps1` | `bob-job-loop` |
| Pointer map | `bob-build-loop` |
| Honesty box harvest | `harvest-agent-skills` |
