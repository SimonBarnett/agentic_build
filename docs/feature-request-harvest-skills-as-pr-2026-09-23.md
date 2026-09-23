# FR: skill harvest as a PR, not a commit to main

**Ask (Simon `#bobiverse` 2026-09-23):**
update builder skills - send skills harvest as a PR, NOT a commit to main.

## LOCKED

1. Useful harvest commits go on a branch and open a PR. Do not
   `git push origin main` for skill harvest.
2. Empty harvest: no commit (unchanged).
3. Workers already never push main. Harvest matches that.
4. No UAT stamp.

## Gap

`harvest-agent-skills` and `Harvest-AgentSkills.ps1` still say commit and
push `origin/main`.

## Acceptance

- A1: Owner skill + harvest script say PR, not main.
- A2: Harvest log notes this rule.
- A3: No UAT stamp.
