---
name: github-irc-webhooks
description: >
  Default GitHub webhooks and ionos IIS HTTPS for irc.ntsa.uk. Use when
  SSL for webhooks, Let's Encrypt on irc-ntsa, GitHub hook URL, add the
  hook to all repos, a new SimonBarnett repo needs the Jeeves git hook,
  reportUrl HTTPS, or /github-irc-webhooks. Jeeves announce text is
  agentic_irc jeeves-git-webhook. Digest POST auth is bob-irc.
---

# GitHub webhooks on irc.ntsa.uk HTTPS

Default payload URL for every SimonBarnett repo:

`https://irc.ntsa.uk/bob/v1/git`

Events: `push`, `pull_request`, `issues`. `content_type` json.
`insecure_ssl` 0. No hook secret in git, issues, or channel.

Fleet digest POST (not GitHub): `reportUrl` in `config/bobiverse.json`
is `https://irc.ntsa.uk/bob/v1/report` (`X-Bob-Secret`). Same IIS site
also serves `https://bob.ntsa.uk` (SAN).

Jeeves announces accepted git events as `GIT ...` on `#bobiverse`.
Do not narrate from `bob-*` or talk seats. Skill
`jeeves-git-webhook` in **agentic_irc**.

## New repo

GitHub user accounts have no org-wide default hook. On a new
`SimonBarnett/<name>` repo, add this hook. Leave other hooks
(Amplify, etc.) in place.

```
gh api repos/SimonBarnett/<name>/hooks -X POST --input hook.json
```

`hook.json` UTF-8 **without BOM**:

```
{"name":"web","active":true,"events":["push","pull_request","issues"],"config":{"url":"https://irc.ntsa.uk/bob/v1/git","content_type":"json","insecure_ssl":"0"}}
```

Create sends a `ping`. Jeeves will `GIT ping`. Do not extra-ping
unless checking a dead delivery.

List: `gh api repos/SimonBarnett/<name>/hooks --jq '.[].config.url'`

## All repos

`gh repo list SimonBarnett --limit 200 --json name --jq '.[].name'`
then add the hook when the URL is missing. PowerShell 5.1
`ConvertFrom-Json` of a JSON array can wrap as one object; iterate
names from `--jq '.[].name'`, not `$array.name`.

## Ionos IIS (site `irc-ntsa`)

Webroot `C:\inetpub\irc-ntsa`. Host bindings `irc.ntsa.uk` and
`bob.ntsa.uk` on **80** and **443** (SNI). URL Rewrite + ARR to
loopback `bobcallback.py` `127.0.0.1:19781` for **both**
`/bob/v1/report` and `/bob/v1/git`.

Let's Encrypt via win-acme `C:\ai\win-acme\wacs.exe` (account under
`C:\ProgramData\win-acme`). Renewal friendly name
`IIS irc-ntsa webhook` (CN `irc.ntsa.uk`, SAN both names, store `My`).
Scheduled task `win-acme renew (acme-v02.api.letsencrypt.org)`.
Contact `si@ntsa.uk`. Keep HTTP :80 for ACME HTTP-01.

Do **not** replace the separate Ergo PEM renewal (`C:\ai\ergo`,
script `install-cert.ps1`). That is IRC :6697, not IIS.

Listener must be origin/main `bobcallback.py` (has `GIT_WEBHOOK_PATH`).
Ionos run path: `C:\ai\agentic_irc-www\scripts\bobcallback.py`
(worktree of `origin/main`), wrapper
`~\.grok\long-running-background-tasks\Start-BobReport-ionos.ps1`,
task `BobReport-ionos`. Home `~\.agentic-irc-bobiverse`.
GET `/git` or `/report` is **405**. Git ping POST is **204**.

IONOS panel: **6697**, **80**, **443**. Policy "Being configured"
flaps the port.

## Do not

- Point GitHub at `/bob/v1/report` (needs `X-Bob-Secret`, not
  `X-GitHub-Event`).
- HMAC / webhook secret in git.
- Stamp UAT.
- Recycle `BobIrcd` for an IIS cert.
