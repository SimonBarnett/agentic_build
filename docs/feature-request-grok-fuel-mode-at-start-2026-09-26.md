# FR #356: Grok seat fuel mode at start (pool vs session key)

## Behaviour (check once at start)

1. Read digest `machines.<id>.pcent["grok-chat"]` from `https://irc.ntsa.uk/bob/v1/report`.
   - **> 0** → start on the pool (`fuel_mode: pool`)
   - **0** → `Show-BobTraySessionApiKeyDialog`; session key only (`fuel_mode: session-key`)
   - **blank/missing** → stop and flag; never start keyless (`fuel_mode: unknown`)
2. No mid-run re-check or pool handoff.
3. Report `fuel_mode` on the machine webhook entry; never the key.
4. Grok TUI argv quoting remains via `ConvertTo-WatchProcessArgumentString` / tray `ConvertTo-BobTrayProcessArgumentString`.

## Tray

`tools/Watch-BobTray.ps1`: `Resolve-BobTrayGrokFuelAtStart`, `Publish-BobTrayFuelMode`, Agents + Plan Grok paths.

## Tests

`tools/Test-Pack.ps1` case `BT0agent FR356 grok fuel_mode at start`
