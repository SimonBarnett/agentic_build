# Bobiverse IRC on ionos (Ergo)

Libera banned `bob-ionos`. Fleet status now targets a private Ergo on this IONOS box.

| | |
|---|---|
| Server | Ergo 2.19.1 `C:\ai\ergo\ergo.exe` |
| Name | `irc.ntsa.uk` |
| Listen | TLS `:6697` only (loopback `:6667` stays localhost) |
| Channel | `#bobiverse` (same nicks) |
| Auth | IRC `PASS` (bcrypt in `ircd.yaml`; plaintext in `~\.grok\ergo\connect.password`) |
| Task | `BobIrcd-ionos` (AtLogOn, not a Windows service) |
| Firewall | `Bobiverse IRC TLS 6697` |

`irc_agent.py` still uses `ssl.create_default_context()`. Self-signed certs will not work for the fleet. Let’s Encrypt needs DNS.

## You do this once

At Talk Internet (ntsa.uk NS: `ns1.talkinternet.co.uk` …):

```
irc.ntsa.uk.  A  217.154.57.228
```

`rtp-teams.ntsa.uk` already points here; this is a new name. Do not reuse the Teams hostname.

When the A record answers, on ionos:

```powershell
# HTTP-01 is ready: IIS site irc-ntsa binds *:80:irc.ntsa.uk
# Issue a cert, write PEM next to ergo, restart the task.
```

Then set `config/bobiverse.json` `"host": "irc.ntsa.uk"` and recycle **Watch-Bobiverse only** (not BobFleet-ionos while jobs run). Copy `connect.password` to flamingo / marchhare / DEV1 out of band; never commit it.

## Do not

- Point `irc_agent` at `irc.libera.chat`
- Open public `:6667`
- Run two Watch-Bobiverse processes (Libera banned the reconnect flood)
