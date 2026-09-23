# Build/test plan: systray start agent visible TUI

## Goals
Systray Agents menu: hidden watcher, visible agent TUI.

## Non-goals
Shortcut fully-hidden launches; flamingo remote recycle.

## Phase 1 — tray launch
1. Change `Start-BobTrayAgentWatch` to start `powershell.exe` `-WindowStyle Hidden` `-File Watch-AgentHealth.ps1 -WatchWorker` plus `-Cursor` or `-Grok` (and `-New` only if that becomes a menu option later). Do **not** pass `-Windows off`.
2. Resolve `Watch-AgentHealth.ps1` under `Resolve-BobTrayAgentMonitorDir` (same candidates as `.cmd`).
3. Log the launch line (kind, path, windows=on implied).

## Phase 2 — tests
1. `Test-Pack.ps1`: assert tray source matches Hidden + `-WatchWorker` and does **not** match `-Windows off` on the Agents launch path.
2. Manual smoke (operator): tray → Agents → Cursor; watch has no console; Composer TUI visible.

## Definition of done
A1–A5 green; PR opened against agentic_build; MRB until PASS-nits.
