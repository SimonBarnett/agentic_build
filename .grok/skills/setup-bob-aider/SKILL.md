---
name: setup-bob-aider
description: >
  Install or repair Aider (aider-chat) on a Bob Fleet Windows seat, fix
  WinError 5 / PATH after pip, wire free OpenRouter/Groq/Gemini models, or
  bring up fuel id aider-free. Use when pip install aider-chat fails,
  aider is not recognized, cffi Access is denied, or /setup-bob-aider.
github: https://github.com/SimonBarnett/agentic_build
---

# Setup Bob Aider (Windows seat)

Home: `SimonBarnett/agentic_build` `.grok/skills/setup-bob-aider`. Honesty box:
using this skill obliges a harvest PR/issue back here (see `harvest-agent-skills`).
Fuel id: `aider-free`.

## Why Aider

CLI coding agent for PR/MRB when Cursor Models / Grok seats are thin. Prefer
free backends (OpenRouter free, Groq, Gemini). Same fleet rules as Cursor/Grok:
IRC watch seat, digest webhook activity with **agent** + **model**, clear when idle.

## CAST IRON — do not system-pip into Program Files

MarchHare lesson 2026-09-24:

1. Never `pip install aider-chat` into `C:\Program Files\Python312` while other
   Python processes run.
2. Bare install failed mid-way with `OSError: [WinError 5] Access is denied` on
   `_cffi_backend.cp312-win_amd64.pyd` under Roaming/AppData
   `Python\Python312\site-packages`. Then `aider` was not on PATH
   (`CommandNotFoundException`).
3. Lock holders include `irc_agent.py` (`bob-*` ears) and other long-lived
   Python (e.g. open_tts). Stop them to unlock pip; **restart the ear after**.

## Preferred install (dedicated venv)

```powershell
# 1) Optional: free the lock only if uninstall of cffi fails
Get-CimInstance Win32_Process -Filter "name='python.exe'" |
  Select-Object ProcessId, CommandLine
# Stop only processes holding the locked pyd; then restart bob-<machine> ear.

# 2) Dedicated venv (avoids Program Files + roaming fights)
$venv = Join-Path $env:USERPROFILE 'venvs\aider'
# MarchHare example: D:\Users\Administrator\venvs\aider
python -m venv $venv
& "$venv\Scripts\python.exe" -m pip install --upgrade pip
& "$venv\Scripts\pip.exe" install aider-chat

# 3) User PATH (permanent) + this session
$scripts = "$venv\Scripts"
$env:Path = "$scripts;" + $env:Path
$cur = [Environment]::GetEnvironmentVariable('Path','User')
if ($cur -notlike "*$scripts*") {
  [Environment]::SetEnvironmentVariable('Path', ($scripts + ';' + $cur), 'User')
}

# 4) Verify
& "$scripts\aider.exe" --version
# Expect aider-chat 0.86.x (or newer)
```

Fallback: `pip install --user aider-chat`, then add
`%APPDATA%\Python\Python312\Scripts` to User PATH. Still stop lockers first.

## Known install noise (safe)

- `WARNING: Failed to remove contents in a temporary directory
  '...site-packages\~aml'` (PyYAML) / `~il` (pillow) / `~harset_normalizer` —
  remove leftover dirs when idle.
- Scripts under Roaming `...\Python312\Scripts` "which is not on PATH" — add
  that folder or use the venv Scripts path above.

## Model / API keys (free-first)

Set user or process env (never commit secrets):

| Backend | Env | Typical model flag |
|---------|-----|--------------------|
| OpenRouter free | `OPENROUTER_API_KEY` | `aider --model openrouter/<free-model>` |
| Groq | `GROQ_API_KEY` | `aider --model groq/...` |
| Gemini | `GEMINI_API_KEY` | `aider --model gemini/...` |
| OpenAI-compatible | `OPENAI_API_KEY` + `OPENAI_API_BASE` | per provider |

Prefer OpenRouter free quota for Bob Fleet `aider-free` fuel.

Smoke (throwaway git repo):

```powershell
cd $repo
aider --model openrouter/<free-model> --message "Reply with pong only"
```

## Fleet wire-up (when systray / recruit-fuel lands)

1. Fuel id `aider-free` in digest / TipForm Agents (same IRC watcher + webhook
   rules as Cursor/Grok).
2. On start: report `https://irc.ntsa.uk/bob/v1/report` with **agent=`aider`**
   and **model=`<backend/model>`**.
3. On finish/fail/idle: clear jobs (worker activity webhook).
4. Launch via venv `aider.exe`, not system Python.
5. AgentMonitor / Watch-AgentHealth: free worker seat once start-code exists.

## Troubleshoot (MarchHare transcript)

| Symptom | Fix |
|---------|-----|
| `WinError 5` on `_cffi_backend*.pyd` | Stop python holding the file; prefer venv; rename/delete locked pyd only after stop |
| `aider : The term 'aider' is not recognized` | Install incomplete or Scripts not on PATH; use full venv `Scripts\aider.exe` and fix User PATH |
| Partial Program Files install | Abandon system site-packages; use `$HOME\venvs\aider` |
| Ear killed to unlock pip | Restart `bob-<machine>` before leaving the seat |

## Do not

- `pip install` into Program Files while bob-* / TTS / other Python is running.
- Put API keys in SKILL.md, IRC, or PRs.
- Stamp UAT from Aider.
- Use Copilot CCA as the Aider backend until CCA is live.
- Burn Bob chat tokens implementing PRs — Aider is the worker; Bob starts/assigns.

## Related

- `harvest-agent-skills`
- Bob digest webhook fuel / token-efficient handoff / worker activity webhook
- recruit-fuel / free Agents systray (when merged)
