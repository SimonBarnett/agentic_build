# Bob irc_agent supervisor (FR #328)

`tools/Bob-IrcAgentSupervisor.ps1` — pure singleton logic (ensure / cull extras / graceful restart).
`tools/Ensure-BobIrcAgent.ps1` — operator one-shot ensure or `-Restart` (writes `agent.quit.request`, waits, starts).
`tools/Register-BobIrcAgentTask.ps1` — logon + 5-minute keepalive scheduled task (like Jeeves chair).
`Install-BobIrc.ps1` calls ensure (does not force-restart a healthy single agent).

## Operator hotpatch (live box)
```text
powershell -NoProfile -File tools\Ensure-BobIrcAgent.ps1 -MachineId marchhare -Restart
```
Do not run `-Restart` from CI against production without Simon.
