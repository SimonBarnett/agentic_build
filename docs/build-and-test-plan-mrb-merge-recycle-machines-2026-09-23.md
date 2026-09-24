# Build/test plan: agentic_build sister of irc #168

1. Read this FR + agentic_irc #168. Implement `bob-hostile-mrb` skill
   text only unless Test-Pack needs a string assert.
2. Do not edit `agentic_irc` in this job. That half is PR 169.
3. Open PR linking this issue. Do not push main. Do not live-recycle.
   No UAT.

## Checks

- `rg recycle-after-merge .grok/skills/bob-hostile-mrb/SKILL.md`
- `rg` ionos + restart in that skill.
- Test-Pack fails if the duty line is deleted.
