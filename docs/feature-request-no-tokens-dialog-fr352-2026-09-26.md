# FR #352: out of tokens → API key dialog; never a silent hang

## Behaviour

1. **Tray / `-WatchWorker`:** check digest fuel before start (see also FR #356). Exhausted → session API key dialog; cancel → nothing starts, tray shows **no tokens**.
2. **Automated starts** (`Select-BobGitWorker` / Bob): never start when strike fuels are at 0%. Return `wait` with `reason=needs Simon: API key` and `error=no_tokens`.
3. **Monitor:** quota / 402 / 429 / out-of-credits in agent output → mark `no_tokens`, stop, **no retry**, **no session rotation** (distinct from FR #99 hang).
4. **TipForm:** machine line `out of tokens, open with key`.

## Tests

`tools/Test-Pack.ps1` case `BT0agent FR352 no_tokens automated + quota detect`
