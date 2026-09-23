---
name: setup-github-cursor
description: >
  Grant the Cursor GitHub App on SimonBarnett repos so Cursor Web / Cloud
  Agents can push and open PRs. Use when setting up a git, new repo,
  cursor[bot] 403, git-receive-pack 403, Permission denied to cursor[bot],
  Cursor Web cannot create a PR, or /setup-github-cursor.
---

# Cursor GitHub App (every new git)

Cursor Web does **not** use your `gh` user token. It pushes as
`cursor[bot]` with an installation token (`x-access-token`). If that
app is not granted on the repo (or Contents is Read only):

```
GET .../info/refs?service=git-receive-pack  -> 401 (no auth)
GET ... + authorization: Basic x-access-token:...  -> 403
remote: Permission to SimonBarnett/<repo>.git denied to cursor[bot].
```

Your user can still `gh pr create`. That does not fix Cursor Web.

## All existing repos (once)

A user account has no org-wide default. Set the Cursor app to
**All repositories** so every current and **future** public repo is
included. Do not leave "Only select repositories" (new repos 403).

1. Open https://github.com/apps/cursor (Configure on **SimonBarnett**).
2. Repository access: **All repositories**.
3. Permissions must include Contents **Read and write** and
   Pull requests **Read and write**.
4. Reconnect GitHub at https://cursor.com/dashboard (Integrations).

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\agentic_build\tools\Grant-CursorGitHubApp.ps1
```

That script opens the install page. A user OAuth `gh` token **cannot**
add a GitHub App installation. Simon must click All repositories.

Leave `oBank-democust` (and any other private) private. All-repos still
covers it for the app; do not `gh repo edit --visibility public` on
private customer trees.

## New repo (same turn as create)

After `gh repo create --public` and the git webhook
(`setup-github-webhooks`):

1. Confirm the Cursor app is still **All repositories**. If it is
   "Only select repositories", add this repo now or switch to All.
2. Do not set interaction limits. Do not add a ruleset that blocks
   `cursor/*` branches or outside collaborators opening PRs.
3. Leave forking on.

Home for the create checklist: `bob-spec-intake` **New GitHub repo**.

## Check

- `gh` as SimonBarnett can read the repo (not the test).
- Cursor Web push no longer 403s as `cursor[bot]`.
- Human fork PRs still work (public + forking on).

## Do not

- Put a PAT or installation token in git, issues, or channel.
- Stamp UAT.
- Treat a working local `gh` as proof Cursor Web can push.
