# FR #348: MRB docs step uses a separate docs PR

**Issue:** https://github.com/SimonBarnett/agentic_build/issues/348

## Rule

MRB never pushes commits onto the PR under review. After PASS, stale docs go in
exactly one separate branch/PR named like `docs/mrb-<n>-...` that references the
original, then merge original + docs PR (or docs-only if already merged). FAIL
fixes stay on one separate fix PR (unchanged).

## Guard

```powershell
python tools/mrb_docs_branch_guard.py --repo OWNER/REPO --pr N --self-test
python tools/mrb_docs_branch_guard.py --repo OWNER/REPO --pr N --json
# exit 2 = docs(MRB on feature branch or foreign commit after MRB start
```
