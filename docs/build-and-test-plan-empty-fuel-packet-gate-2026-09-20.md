# Build and test plan: empty fuel packet gate (issue #54)

**Date:** 2026-09-20  
**Repo:** https://github.com/SimonBarnett/agentic_build  
**Issue:** https://github.com/SimonBarnett/agentic_build/issues/54  
**Spec:** `docs/feature-request-empty-fuel-packet-gate-2026-09-20.md`  
**Chair:** Bob (hostile MRB on #54). Builder opens PR; never push `main`; never merge.

## Goals

- Refuse hand-written inbox packets with a `model` and no `fuel` on fleet tick before `Start-BobWorker`.
- Named completion summary (`missing_fuel model=…`).

## Implementation

1. Add `Test-BobPacketMissingFuel` (module surface).
2. `Invoke-BobFleetOnce`: after cwd check, before move to `running`, fail when model present and fuel absent.

## Tests (off-DEV)

| ID | Case | Acceptance |
|---|---|---|
| BT0y1 | empty fuel model tick refuse | AC1–AC2 (no Fake-Grok session growth) |
