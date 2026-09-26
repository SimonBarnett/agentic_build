# FR #401: deterministic exceptions open owning-repo issues (no LLM)

**Issue:** https://github.com/SimonBarnett/agentic_build/issues/401

`Report-BobDeterministicException` templates a GitHub issue via `gh` (Fake-Gh in tests).
Fingerprint dedupe under `~/.grok/bob-bridge/exception-issues/`. Owning repo map:
AgentMonitor / agentic_irc / gh-Jeeves / agentic_build.

Call from unexpected `catch` blocks in deterministic tools. Do not LLM-author bodies.
