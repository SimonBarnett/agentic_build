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

Let’s Encrypt for `irc.ntsa.uk` is live (issued 2026-09-20, HTTP-01). Ergo serves that cert on :6697. `bob-ionos` joined `#bobiverse` as `@bob-ionos`. win-acme renews into `C:\ai\ergo\*.pem` and `install-cert.ps1` recycles `BobIrcd-ionos`.

Copy `~\.grok\ergo\connect.password` to flamingo / marchhare / DEV1 out of band (same path). Pull `agentic_build` + `agentic_irc` (`PASS` support). Recycle **Watch-Bobiverse only** on those boxes. Never commit the password.

## Do not

- Point `irc_agent` at `irc.libera.chat`
- Open public `:6667`
- Run two Watch-Bobiverse processes (Libera banned the reconnect flood)
