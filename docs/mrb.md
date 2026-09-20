# MRB (lightweight)

Hostile Material Review Board is a **GitHub issue** on the product repo, linked to the **feature-request issue** and `docs/feature-request-*.md`.

Do **not** write `docs/mrb-*.pdf`. Git is the source of truth.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Start-BobMrb.ps1 -Repo SimonBarnett/agentic_build -Verdict FAIL -Title 'slug sha' -Body '...' -FeatureIssue 'https://github.com/SimonBarnett/agentic_build/issues/N'
```

Skill: `.grok/skills/bob-hostile-mrb`.
