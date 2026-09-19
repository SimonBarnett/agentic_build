---
name: harvest-agent-skills
description: >
  Hourly scan for repeatable procedures worth promoting into agentic_build
  .grok/skills. Use when the user says harvest skills, promote a playbook,
  skill harvest, hourly skill check, or /harvest-agent-skills. Does not
  dispatch product builds (that is grok-build-fleet / bob-build-dispatch).
---

# Harvest agent skills

Run on the fleet machine (cwd `C:\ai\agentic_build` on ionos). Empty harvest: **no git commit**. Useful harvest: add/update `SKILL.md`, note in `docs/`, commit, push `origin/main`.

## Scan

1. `~\.grok\skills\*` vs repo `.grok/skills\*` — user-only skills that are not one-off.
2. `~\.grok\long-running-background-tasks\` scripts that encode a procedure the repo does not.
3. Recent `docs/*ops*.md` and this repo's uncommitted playbooks.
4. Existing skills — do not duplicate. Point at the owner skill instead.

A candidate is useful only if it is **repeatable**, has a clear trigger, and is not a single incident report.

## Write

Follow `skill-design-principles` (one home per fact, no sprawl). Frontmatter `name` + `description` with triggers. ASCII in SKILL.md.

Add the name to `tools/Test-Pack.ps1` BT0 skills list. Run `tools\Test-Pack.ps1`. `Install-BobFleet` already copies every project skill into `~\.grok\skills`.

Append a short dated section to `docs/skill-harvest-log.md` (create if missing).

## Do not

- Commit "nothing found".
- Force-push, secrets, `password=` / `XAI_API_KEY=` assignments.
- Invent skills from noisy session chat.
- Claim ready for human UAT.
- Start extra fleet product jobs; this job is the harvest.
