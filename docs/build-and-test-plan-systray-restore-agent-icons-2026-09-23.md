# Build/test plan: restore systray Cursor/Grok icons

## Phase 1
1. Fix `Resolve-BobTrayAgentExe` to return `$null` when no candidate exists.
2. Add `Get-BobTrayAgentBrandImage` (or extend `Get-BobTrayAgentImage`) that: prefers desktop app exe for icon extract; falls back to a drawn badge (C / G) when extract fails or image is empty; greyscale only when not installed, without making the icon invisible.
3. Wire TipForm section headers + Agents menu through that helper.

## Phase 2
Test-Pack: Resolve returns null when missing; Grok Bot.exe preferred for icon; badge fallback exists; section header code still calls Get-BobTrayAgentImage.

## Done
A1–A6; PR; MRB PASS-nits.
