# Build/test plan: validate-vision-pack intake (#275)

1. Edit `.grok/skills/visionary/SKILL.md`: add the validator refuse line
   from skills-visionary (`python tools/validate-vision-pack.py ...`).
2. Edit `.grok/skills/bob-spec-intake/SKILL.md`: New product step 0 and
   FR step 0 run that command (local `tools/` else sister clone
   `C:\ai\skills-visionary`, `D:\ai\...`, `C:\src\...`) and refuse
   park/dispatch on non-zero.
3. BT0: `bob-spec-intake` must match `validate-vision-pack`.
4. Note `docs/skill-harvest-log.md`.
5. `tools\Test-Pack.ps1`. Open PR. Do not push `main`. No UAT.
