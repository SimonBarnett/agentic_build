# MRB FAIL: Bob Fleet double dialog + stale job list (2026-09-20)

GitHub: https://github.com/SimonBarnett/agentic_build/issues/3

Screenshot (stale-list shot): `docs/screenshots/bob-fleet-double-dialog-stale-list-2026-09-20.png`

Simon later corrected: the **good** UI is the dark TipForm card. The **bad** dialog is the stuck native white `P+ idle 0%` `NotifyIcon.Text` chip beside the icon (`docs/screenshots/bob-fleet-native-p-plus-idle-chip-2026-09-20.png`).

**Fix in tree:** dark card on **click / Status only** (no hover events, no `hideTip`); stays parked until X; `NotifyIcon.Text` stays empty (`Clear-BobNativeTip`); Restart watcher rejoins `#bobiverse` via `_Watch-Bobiverse-<id>`. `TipForm` guards `IsDisposed`, `TryHide` uses `SWP_HIDEWINDOW`, one `LiveCount`. This doc is the FAIL record — do not treat it as PASS until Simon confirms one card on click and Restart rejoins the moot.
