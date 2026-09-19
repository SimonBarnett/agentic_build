---
name: bob-spec-intake
description: >
  Park a functional specification or feature-request PDF into a SimonBarnett
  repo /docs (new public repo or versioned folders). Use when another agent
  sends a functional spec, feature-request PDF, says park in docs, create repo
  for spec, or /bob-spec-intake. Does not start the build agent by itself.
---

# Spec intake to /docs

## New product (fresh functional spec)

1. Choose a clear public repo name under `SimonBarnett` (kebab-case).
2. Create the public GitHub repo if it does not exist.
3. Commit under `/docs`:
   - Original PDF (or source): `docs/functional-spec-<slug>-YYYY-MM-DD.pdf`
   - Markdown mirror: `docs/functional-spec.md` (LOCKED constants, unknowns, Phase 0, acceptance).
4. Optionally add a short README pointing at `/docs`.
5. Push. Tell the human the commit SHA and doc URLs.
6. Next: run `bob-build-dispatch` (unless the human said park-only / later).

## Feature request (extends existing repo)

1. Confirm target repo. **Do not break** prior versions.
2. Prefer new work in `v2/`, `v3/`, when the feature is a parallel product surface; keep root/`v1` frozen if the spec says so.
3. Commit under `/docs`:
   - `docs/feature-request-<slug>-YYYY-MM-DD.pdf`
   - `docs/feature-request-<slug>-YYYY-MM-DD.md` with summary plus **gap vs current tree** (what already exists vs what is missing).
4. Push. Do not start implementation unless asked.
5. Next: `bob-build-dispatch` when the human says go.

## Docs quality bar

- Capture LOCKED vs UNKNOWN.
- Name acceptance IDs / phase order if the source PDF has them.
- Never invent instance URLs, secrets, or procedure ENAMEs.
- If park for later, stop after push — do not dispatch.