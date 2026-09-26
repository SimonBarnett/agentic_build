# FR #354: Get-BobDigestUrl must not use bob.ntsa.uk /digest

## Problem

Default digest GET pointed at `http://bob.ntsa.uk/bob/v1/digest` (does not resolve; IIS has no `/digest`). Public digest is GET `https://irc.ntsa.uk/bob/v1/report` (`reportUrl`).

## Fix

`Get-BobDigestUrl` order: env → config `digestUrl` → config `reportUrl` → hard default `https://irc.ntsa.uk/bob/v1/report`.

## Tests

`BT354` in `tools/Test-Pack.ps1`
