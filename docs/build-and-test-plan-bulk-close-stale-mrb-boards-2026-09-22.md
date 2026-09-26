# Build-and-test plan: bulk-close stale MRB boards (#140 / #170)

1. Rewrite `tools/Close-BobMrbPassedIssues.ps1` with mandatory `-Repo` +
   `-MergedPrUrl`, merge gate, PR URL in comments, this-PR scoping.
2. Off-DEV Test-Pack `BT170a`–`BT170d` using Fake-Gh.
3. Point intake docs at issue #140 / FAIL #170.
