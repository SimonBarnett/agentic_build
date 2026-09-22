---
name: bob-spec-intake
description: >
  Park a functional specification or feature request as git: GitHub issue plus
  /docs markdown. Keep a source PDF only if one was supplied; do not generate
  review PDFs. Use when another agent sends a spec or feature request, says
  park in docs, or /bob-spec-intake. Does not start the build agent by itself.
---

# Spec intake to /docs

## New product (fresh functional spec)

1. Choose a clear public repo name under `SimonBarnett` (kebab-case).
2. Create the public GitHub repo if it does not exist.
3. Commit under `/docs`:
   - Markdown: `docs/functional-spec.md` (LOCKED constants, unknowns, Phase 0, acceptance).
   - Keep a source PDF **only if the sender provided one**. Do not invent a PDF.
   - If the product is a **skill pack**, LOCK a harvest skill as foundation
     (`.grok/skills/harvest-<repo>/SKILL.md` or equivalent). CAST IRON:
     learnings harvest back to that repo (`harvest-agent-skills`).
4. Open a GitHub issue titled from the spec, body linking the md path, label `feature-request`.
5. Push. Tell the human the issue URL and commit SHA.
6. Next: run `bob-build-dispatch` (unless the human said park-only / later).

## Feature request (extends existing repo)

1. Confirm target repo. **Do not break** prior versions.
2. Prefer new work in `v2/`, `v3/`, when the feature is a parallel product surface; keep root/`v1` frozen if the spec says so.
3. Commit `docs/feature-request-<slug>-YYYY-MM-DD.md` with summary plus **gap vs current tree**. Keep a source PDF only if one was supplied.
4. Open a GitHub issue (`feature-request`) linking that markdown. That issue is the MRB home.
5. Push. Do not start implementation unless asked.
5. Next: `bob-build-dispatch` when the human says go.

## Docs quality bar

- Capture LOCKED vs UNKNOWN.
- Name acceptance IDs / phase order if the source PDF has them.
- Never invent instance URLs, secrets, or procedure ENAMEs.
- If park for later, stop after push — do not dispatch.