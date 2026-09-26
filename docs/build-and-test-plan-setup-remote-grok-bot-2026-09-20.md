# Build-and-test plan: setup-remote-grok-bot skill

**FR:** `docs/feature-request-setup-remote-grok-bot-2026-09-20.md`  
**Issue:** https://github.com/SimonBarnett/agentic_build/issues/1  

## Steps

1. Read issue #1 body + existing `.grok/skills/unstick-grok-bot`, `bob-fleet-*`, harvest-agent-skills.
2. Create `.grok/skills/setup-remote-grok-bot/SKILL.md` covering all seven playbook sections from the issue.
3. Cross-links to agentic_irc#2 / mode3-dumb-ops when present; unstick-grok-bot distinction (Temporal ≠ Electron blank).
4. Append docs/skill-harvest-log.md; update Test-Pack BT0 if needed.
5. Commit/push. Slab UAT + hostile MRB.

## Success

Acceptance criteria green on main.
