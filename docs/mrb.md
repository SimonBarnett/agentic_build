# MRB (lightweight)

Hostile Material Review Board is a **GitHub issue** on the product repo,
linked to the **feature-request issue**, `docs/feature-request-*.md`, and
the **worker PR**.

Do **not** write `docs/mrb-*.pdf`. Git is the source of truth.

Transaction (no judgment): `.grok/skills/bob-build-loop`.

1. Worker opens a PR. Never push `main`. Never merge.
2. Bob hands off MRB with `tools/Start-BobMrbHandoff.ps1` (Cursor Models
   while remaining > 0, else grok.exe). Never Other Models.
3. Worker posts `MRB FAIL|PASS-nits: <slug> <sha>` via `tools/Start-BobMrb.ps1`.
4. **FAIL:** do not merge; dispatcher starts a FIX worker; new PR; re-MRB.
5. **PASS-nits:** the MRB agent merges the PR. Nits do not block.
6. Only Bob stamps **ready for human UAT**.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Start-BobMrbHandoff.ps1 `
  -Repo SimonBarnett/agentic_build -Issue N -Sha <pr-head> -Cwd C:\ai\agentic_build
```

Skill: `.grok/skills/bob-hostile-mrb`.
