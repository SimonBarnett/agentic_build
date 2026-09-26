# FR #369: tray watch seats use per-machine bob-seat-work (not live C:\ai)

## Problem

`Start-BobTrayAgentWatch` passed `-Cwd`, but `Get-BobTrayWatchWorkspace` preferred existing `\ai` roots (`C:\ai`), so seats worked inside live `agentic_build` / Jeeves trees.

## Expected

- Default: `C:\bob-seat-work\<machine>` (created if missing)
- Configurable: `BOB_SEAT_WORK` (exact path) or `BOB_SEAT_WORK_ROOT` (parent)
- Never resolve seat cwd to a live `\ai` tree
- Tray launch always includes `-Cwd <seat-work>`

## Tests

`BT102`, `BT369` in `tools/Test-Pack.ps1`
