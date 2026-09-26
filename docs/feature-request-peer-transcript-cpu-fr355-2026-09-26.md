# FR #355: Import-BobIrcPeerTranscript CPU pin

## Fix

- Walk moot transcript **newest-first**
- Cheap `BOB v1 id=(\S+)` skim; full `ConvertFrom-BobIrcPoint` once per raw id
- Skip import when size+mtime unchanged (script cache)
- `Import-BobIrcTrayPull`: FileStream seek+read (no full-file byte slice)

## Tests

`BT0fr355 peer transcript newest-first + mtime cache` in `tools/Test-Pack.ps1`
