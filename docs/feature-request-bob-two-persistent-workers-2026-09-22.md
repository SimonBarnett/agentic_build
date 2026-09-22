# Feature request: bob-{machine} two persistent workers per repo

**Parked:** 2026-09-22 by flamingo-24108 from Simon Query.  
**Repo:** SimonBarnett/agentic_build (extends current fleet; do not break v1 job loop).

## Ask (LOCKED)

Change how Bob works:

1. **`bob-{machine}` is the grok agent** on that box.
2. He is **installed on all machines** and is given the skills to **join the bobiverse**.
3. Input is either a **feature request** or a **functional spec for a new repo**.
4. Bob **starts 2 workers** to handle the project (one repo) he is assigned.
5. Those agents **persist** until Bob no longer needs them.
6. Workers are **spawned by Bob** with **build + IRC** skills. They do **dev or MRB**.
7. **No self-review:** if one worker implemented a PR, the **other** must MRB; the implementer **moves to the next PR**.
8. Bob **does not terminate** workers until they have been **idle a few minutes**.
9. Workers **MUST** POST their current **working-on description to the webhook**.
10. That update **must appear on the digest** so we can see what everyone is working on.

## Gap vs current tree (`be8cb6f`)

| Today | Required |
|-------|----------|
| `Start-BobBuild` / `Start-BobBuildLoop` / `Start-BobMrbHandoff` enqueue one-shot cursor/grok jobs; Watch-BobJobs pulls the queue | `bob-{machine}` (grok) owns a repo and keeps **two** live workers |
| Workers are `w-<short>-<pid>` shop-only, or ephemeral cursor-agent PIDs | Persist until Bob idles them out |
| MRB is a **new** job (`-Kind mrb`), never the implementer | Same pair: implementer vs MRB seat; implementer proceeds to next PR |
| `post_working_on` exists on talk seats (`#102` / agentic_irc) | **Workers** must POST; digest must show it |
| Talk seats + Watch recycle `bob-*` | `bob-{machine}` stays the grok chair on every box with bobiverse skills |

Do not break: hostile MRB (not own PR), no UAT stamp by workers, no `!bobiverse` from builders, no Other Models.

## MUST NOT

- Implementer reviews or merges their own PR (except PASS-nits MRB worker merge, existing rule).
- Stamp ready for human UAT (Bob chair only).
- Commit secrets / `password=` / API key assignments.
- Second-open a duplicate FR if this issue is the home.

## UNKNOWN

| ID | Item |
|----|------|
| U1 | Exact idle timeout (Simon: "a few minutes") — default **5 min** unless he sets it. |
| U2 | Whether the two workers are grok.exe, cursor-agent, or mixed (dev Composer / MRB Cursor Grok as today). |
| U3 | How this replaces vs wraps `Start-BobBuildLoop` on the same SHA. |
| U4 | New-repo path vs existing `bob-spec-intake` create-repo. |

## Acceptance

| ID | Check |
|----|--------|
| A1 | Skill/docs: `bob-{machine}` = grok chair; two workers per assigned repo. |
| A2 | Spawn path: Bob starts workers with build + IRC skills; they JOIN shop (and fleet policy). |
| A3 | Persist until Bob stops them after idle timeout (U1). |
| A4 | Implementer cannot MRB that PR; the other worker MRBs; implementer takes next PR. |
| A5 | Worker `working_on` POSTs to webhook; digest shows the description. |
| A6 | BT0/docs validator or pack test covers A1–A5 enough to MRB. |
