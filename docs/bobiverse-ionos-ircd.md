# Bobiverse IRC on ionos (Ergo)

Libera banned `bob-ionos`. Fleet status now targets a private Ergo on this IONOS box.

| | |
|---|---|
| Server | Ergo 2.19.1 `C:\ai\ergo\ergo.exe` |
| Name | `irc.ntsa.uk` |
| Listen | TLS `:6697` only (loopback `:6667` stays localhost) |
| Channel | `#bobiverse` (same nicks) |
| Auth | IRC `PASS` (bcrypt in `ircd.yaml`; plaintext in `~\.grok\ergo\connect.password`) |
| Service | `BobIrcd` (Automatic, LocalSystem, NSSM wraps `C:\ai\ergo\ergo.exe`). Start: `Start-Service BobIrcd`. Recycle: `Restart-Service BobIrcd`. Status Stopped / no `ergo.exe` means down. |
| Firewall | IONOS Cloud Panel inbound TCP 6697 **and** Windows rule `Bobiverse IRC TLS 6697`. Do not open public `:6667`. |

Let’s Encrypt for `irc.ntsa.uk` is live (issued 2026-09-20, HTTP-01). Ergo serves that cert on :6697. win-acme renews into `C:\ai\ergo\*.pem` and `install-cert.ps1` recycles service `BobIrcd` only.

The old logon task `BobIrcd-ionos` is unregistered. Do not `Start-ScheduledTask BobIrcd-ionos`. Do not `Stop-ScheduledTask BobFleet-*` for IRC. Fleet tray/jobs stay logon tasks, not services.

The IONOS **hardware** firewall (Cloud Panel: Network > Firewall Policies) defaults to 80/443/3389. Windows `New-NetFirewallRule` does not open that panel. 80/443 up with 6697 down is the panel. Status "Being configured" flaps the port; wait until Active. Canonical join/recycle: `agentic_irc` skill `bob-irc`.

Copy `~\.grok\ergo\connect.password` to flamingo / marchhare / DEV1 out of band (same path). Pull `agentic_build` + `agentic_irc` (`PASS` support). Recycle **Watch-Bobiverse only** on those boxes. Never commit the password.

## Do not

- Point `irc_agent` at `irc.libera.chat`
- Open public `:6667`
- Run two Watch-Bobiverse processes (Libera banned the reconnect flood)
