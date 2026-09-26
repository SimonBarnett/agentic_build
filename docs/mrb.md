# MRB (lightweight)

Hostile Material Review Board is a **GitHub issue** on the product repo,
linked to the **feature-request issue**, `docs/feature-request-*.md`, and
the **worker PR**.

Do **not** write `docs/mrb-*.pdf`. Git is the source of truth.

Transaction (no judgment): `.grok/skills/bob-build-loop`.

1. Worker opens a PR. Never push `main`. Never merge (**FR #343** — other seat MRBs).
2. Bob hands off MRB with `tools/Start-BobBuildLoop.ps1` (skill
   `bob-job-loop`) or a single `tools/Start-BobMrbHandoff.ps1` (Cursor Models
   while remaining > 0, else grok.exe). Never Other Models.
3. In a temporary worktree, use `gh pr checkout`, read intent, add NEW tests,
   run existing + new tests, and perform the hostile review.
4. **PASS:** review README, skills, `docs/`, mermaid diagrams, and usage/help
   text for stale behavior. If anything is stale, open exactly ONE **separate**
   docs PR from branch `docs/mrb-<n>-...` against `main` (references the original)
   and merge it together with the original; if docs are fine, merge the original
   as before. **Never push onto the PR under review** (FR #348). Close the source
   issue/FR, then hand off to a separate UAT worker. Only Bob stamps UAT.
   Guard: `tools/mrb_docs_branch_guard.py`.
5. **FAIL:** open exactly ONE **separate** fix PR with the fix, then merge both
   the original PR and the fix PR. Do not open multiple fix PRs. Do not push the
   fix onto the reviewed branch.
6. Worker posts `MRB FAIL|PASS-nits: <slug> <sha>` via
   `tools/Start-BobMrb.ps1`. Jeeves announces whatever lands.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Start-BobMrbHandoff.ps1 `
  -Repo SimonBarnett/agentic_build -Issue N -Sha <pr-head> -Cwd C:\ai\agentic_build
```

Skill: `.grok/skills/bob-hostile-mrb`.
