# MRB FAIL: Bob Fleet double dialog + stale job list (2026-09-20)

GitHub: https://github.com/SimonBarnett/agentic_build/issues/3

Screenshot (stale-list shot): `docs/screenshots/bob-fleet-double-dialog-stale-list-2026-09-20.png`

Later same day: Simon still saw the parked TOPMOST **Bob Fleet** card with a single `Watch-BobTray` PID (hover + iconProbe re-armed `cardClosed` after X).

**Fix in tree:** `tools/Watch-BobTray.ps1` is click/Status-only for the dark card; hover restores the compact native tip; X leaves `cardClosed` set; `TipForm` guards `IsDisposed`, `TryHide` uses `SWP_HIDEWINDOW`, and recreate is a single instance. This doc is the FAIL record — do not treat it as PASS until ionos UAT.
