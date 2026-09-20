# WP0 — record official grok surfaces. Do not guess flags.
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$FormPrepCwd
)

$ErrorActionPreference = 'Continue'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$out = Join-Path $RepoRoot 'docs\wp0-recon.md'
$exe = $env:BOB_GROK_EXE
if (-not $exe) {
    $cmd = Get-Command grok -ErrorAction SilentlyContinue
    if ($cmd) { $exe = $cmd.Source }
}
if (-not $exe) { $exe = Join-Path $env:USERPROFILE '.grok\bin\grok.exe' }

function Invoke-Capture {
    param([string[]]$GrokArgs, [int]$TimeoutSec = 60)
    if (-not (Test-Path $exe)) {
        return "grok missing at $exe"
    }
    try {
        $p = Start-Process -FilePath $exe -ArgumentList $GrokArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\bob-recon-out.txt" -RedirectStandardError "$env:TEMP\bob-recon-err.txt"
        if ($TimeoutSec -gt 0 -and $p -and -not $p.HasExited) {
            $null = $p.WaitForExit([Math]::Min($TimeoutSec * 1000, [int]::MaxValue))
        }
        $stdout = Get-Content "$env:TEMP\bob-recon-out.txt" -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content "$env:TEMP\bob-recon-err.txt" -Raw -ErrorAction SilentlyContinue
        return "exit=$($p.ExitCode)`n$stdout`n$stderr"
    }
    catch {
        return $_.Exception.Message
    }
}

$lines = New-Object System.Collections.Generic.List[string]
[void]$lines.Add("# WP0 recon")
[void]$lines.Add('')
[void]$lines.Add("date: $([DateTime]::UtcNow.ToString('o'))")
[void]$lines.Add("computer: $env:COMPUTERNAME")
[void]$lines.Add("user: $env:USERNAME")
[void]$lines.Add("grok: $exe")
[void]$lines.Add('')

[void]$lines.Add('## 1 host / version')
[void]$lines.Add('```')
[void]$lines.Add((Invoke-Capture @('--version')))
[void]$lines.Add('```')

[void]$lines.Add('## 2 --help (sessions / agent / leader)')
[void]$lines.Add('```')
[void]$lines.Add((Invoke-Capture @('--help')))
[void]$lines.Add('```')
[void]$lines.Add('```')
[void]$lines.Add((Invoke-Capture @('sessions', '--help')))
[void]$lines.Add('```')
[void]$lines.Add('```')
[void]$lines.Add((Invoke-Capture @('agent', '--help')))
[void]$lines.Add('```')

[void]$lines.Add('## 3 sessions list')
[void]$lines.Add('```')
[void]$lines.Add((Invoke-Capture @('sessions', 'list')))
[void]$lines.Add('```')

[void]$lines.Add('## 4 inspect --json')
$inspectArgs = @('inspect', '--json')
if ($FormPrepCwd) { $inspectArgs += @('--cwd', $FormPrepCwd) }
[void]$lines.Add('```')
[void]$lines.Add((Invoke-Capture $inspectArgs))
[void]$lines.Add('```')

[void]$lines.Add('## 5 oneshot PONG (skipped unless -RunLive; default off)')
[void]$lines.Add('Not run by default. Use grok --no-auto-update -p PONG --output-format json --max-turns 1')

[void]$lines.Add('## 6 resume PONG2')
[void]$lines.Add('Not run by default. Record -r <id> from step 5.')

[void]$lines.Add('## 7 dual-attach')
[void]$lines.Add('Do not start a TUI. Record error only if one is already open.')

[void]$lines.Add('## 8 safe.directory + git status formprep')
[void]$lines.Add('```')
[void]$lines.Add((git config --global --get-all safe.directory 2>&1 | Out-String))
[void]$lines.Add('```')

[void]$lines.Add('## 9 freeze')
[void]$lines.Add('- oneshot_argv_template: grok --no-auto-update --no-alt-screen --output-format json --cwd PATH -s ID [--rules TEXT] -p TEXT')
[void]$lines.Add('- session_id_json_path: $.sessionId')
[void]$lines.Add('- resume_flag: -r ID')
[void]$lines.Add('- sessions_list_cmd: grok sessions list')
[void]$lines.Add('- leader_required: false')

[IO.File]::WriteAllText($out, ($lines -join "`r`n"))
Write-Host "Wrote $out"
