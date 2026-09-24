# Build and test plan — shop worker attach + reportUrl

**Repo:** SimonBarnett/agentic_build
**Spec:** docs/feature-request-shop-channel-worker-cc-webhook-2026-09-21.md
**Issue:** #124
**Sister:** agentic_irc #46

## P0
Read sister FR. Do not invent a fifth machine id.

## P1
`bobiverse.json` `reportUrl`. Skills: `bob-shop-worker`, `bob-irc`,
MRB/build kickoff paragraphs.

## P2
Watch: JOIN shop; no POINT/`!report` outbox; POST on local death.

## P3
Ionos write-only listener if dispatched; otherwise leave as documented
hole for a later ticket.

## P4
PR. Hostile MRB #124. Bob UAT.
