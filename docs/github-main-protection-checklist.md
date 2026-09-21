# GitHub `main` protection checklist (agentic_build)

**Owner:** Bob at human UAT on the feature issue. Workers document intent; they do not need org admin.

For `SimonBarnett/agentic_build`:

- [ ] **Branch protection on `main`:** require pull request before merge; no direct push from worker accounts.
- [ ] **Required review:** at least one approving review (MRB agent on PASS-nits).
- [ ] **Block merge when label `mrb-fail` is on the open MRB issue** for that PR head (policy: FAIL must not merge).
- [ ] **Allow merge on PASS-nits:** MRB issue title `MRB PASS-nits: …` + label `mrb-pass`; nits do not block merge.
- [ ] **No required status checks** that Fake-Grok cannot satisfy unless CI is wired for this private legion repo.
- [ ] Workers still never push `main` and never self-merge implementation PRs (implementer ≠ MRB agent).

If org settings cannot be changed from a worker token, Bob ticks this list manually at UAT and records the outcome on the FR issue.
