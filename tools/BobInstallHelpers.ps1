# Shared helpers for tools\Install-BobFleet.ps1 and tools\Install-BobIrc.ps1 (dot-source them).
# Rules that keep an install safe to re-run on a live box:
# - ONE tray / ONE ear: reuse the #318 single-instance rule (Select-BobTraySingleWatcher in
#   Watch-BobTray.ps1: keep the oldest root process, stop newer duplicates, never start another).
# - Watcher tasks only when meant for this machine: tools\_Watch-<Name>-<machine>.ps1 exists, or the
#   caller opts in (Install-BobFleet -Watchers <Name>). A generic tools\_Watch-<Name>.ps1 alone is not enough.
# - User env: non-secret config only. Set when unset; keep an existing different value unless
#   -UpdateUserEnv. Secrets (API keys, tokens, IRC password) are never persisted (session-only rule).
# Not a Windows service; no Machine-scope env.

$bobInstallHelpersDir = $PSScriptRoot

function Get-BobUserEnv([string]$Name) {
    return [Environment]::GetEnvironmentVariable($Name, 'User')
}

function Set-BobUserEnv([string]$Name, [string]$Value) {
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
}

function Set-BobInstallUserEnv {
    # Persist ONE non-secret config value at User scope (never Machine). Also sets it for this run.
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value,
        [switch]$Update
    )
    if ($Name -match '(?i)KEY|TOKEN|PASSWORD|SECRET|CREDENTIAL|AUTH') {
        throw "refusing to persist secret-like env var $Name (session-only rule)"
    }
    if ($null -eq $script:BobInstallEnvReport) { $script:BobInstallEnvReport = New-Object System.Collections.ArrayList }
    $before = [string](Get-BobUserEnv $Name)
    if (-not $before) {
        Set-BobUserEnv $Name $Value
        $action = 'set (was unset)'
    }
    elseif ($before -eq $Value) {
        $action = 'unchanged'
    }
    elseif ($Update) {
        Set-BobUserEnv $Name $Value
        $action = 'updated (-UpdateUserEnv)'
    }
    else {
        $action = 'kept existing (differs; pass -UpdateUserEnv to overwrite)'
    }
    Set-Item -LiteralPath ("Env:{0}" -f $Name) -Value $Value
    $row = [pscustomobject]@{ Name = $Name; Before = $before; After = [string](Get-BobUserEnv $Name); Action = $action }
    [void]$script:BobInstallEnvReport.Add($row)
    return $row
}

function Write-BobInstallEnvReport([string]$Label) {
    Write-Host "Env ($Label, User scope, non-secret; secrets stay session-only):"
    $rows = @($script:BobInstallEnvReport)
    if ($rows.Count -eq 0) { Write-Host '  (none touched)'; return }
    foreach ($r in $rows) {
        $b = if ($r.Before) { $r.Before } else { '<unset>' }
        $a = if ($r.After) { $r.After } else { '<unset>' }
        Write-Host ('  {0,-17} {1}: before={2} after={3}' -f $r.Name, $r.Action, $b, $a)
    }
}

function Get-BobInstallPattern([string]$Name) {
    # tools\Watch-<Name>.ps1 or tools\_Watch-<Name>[-<machine>].ps1 on a command line.
    return ('(?i)[\\/]_?Watch-{0}(-[^\\/"\s]+)?\.ps1' -f [regex]::Escape($Name))
}

function Get-BobInstallProcesses([string]$Pattern) {
    $h = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -match $Pattern })
    return $h
}

function Get-BobTraySingleInstanceRuleText {
    param([string]$TrayPath = (Join-Path $bobInstallHelpersDir 'Watch-BobTray.ps1'))
    $tok = $null; $err = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($TrayPath, [ref]$tok, [ref]$err)
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Select-BobTraySingleWatcher' }, $true)
    if (-not $fn) { throw "$TrayPath has no Select-BobTraySingleWatcher (#318 single-instance rule)" }
    return $fn.Extent.Text
}

# Same keep-oldest rule the tray uses for its ear / jobs watcher (#318), loaded from Watch-BobTray.ps1.
if (-not (Get-Command Write-TrayLog -ErrorAction SilentlyContinue)) {
    function Write-TrayLog([string]$m) { Write-Host "  $m" }
}
. ([scriptblock]::Create((Get-BobTraySingleInstanceRuleText)))

function Start-BobInstallTray {
    # Start the BobFleet-<id> logon task only when no tray runs. Duplicates: keep oldest, stop newer.
    param([Parameter(Mandatory)][string]$TaskName)
    $hits = @(Get-BobInstallProcesses (Get-BobInstallPattern 'BobTray'))
    if ($hits.Count -gt 0) {
        $keep = Select-BobTraySingleWatcher -Hits $hits -Label 'tray'
        return [pscustomobject]@{ Started = $false; Pid = [int]$keep.ProcessId; Status = ('already running pid={0} (not started again; single-instance rule keeps oldest)' -f $keep.ProcessId) }
    }
    try {
        Start-ScheduledTask -TaskName $TaskName
        return [pscustomobject]@{ Started = $true; Pid = $null; Status = 'started now' }
    }
    catch {
        return [pscustomobject]@{ Started = $false; Pid = $null; Status = "register-only (start failed: $($_.Exception.Message))" }
    }
}

function Install-BobWatcherTask {
    # Register + start ONE watcher logon task, only when meant for this machine.
    #   meant for this machine = tools\_Watch-<Name>-<machine>.ps1 exists, or -OptIn, or -AllMachines
    #   (-AllMachines: every fleet box runs it, e.g. the Bobiverse ear). Running already -> not started
    #   again (duplicates: keep oldest). -NoStart: register only (the tray just started and owns it).
    #   A task left from an earlier opt-in install is never removed.
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$MachineId,
        [Parameter(Mandatory)][string]$RepoRoot,
        [switch]$OptIn,
        [switch]$AllMachines,
        [switch]$NoStart,
        $Trigger,
        $Settings,
        $Principal,
        [string]$PsExe
    )
    $wrapId = Join-Path $RepoRoot ('tools\_Watch-{0}-{1}.ps1' -f $Name, $MachineId)
    $wrap = Join-Path $RepoRoot ('tools\_Watch-{0}.ps1' -f $Name)
    $inner = Join-Path $RepoRoot ('tools\Watch-{0}.ps1' -f $Name)
    $file = $null
    if (Test-Path -LiteralPath $wrapId) { $file = $wrapId }
    elseif ($OptIn -or $AllMachines) {
        if (Test-Path -LiteralPath $wrap) { $file = $wrap }
        elseif (Test-Path -LiteralPath $inner) { $file = $inner }
    }
    if (-not $file) {
        if (-not ($OptIn -or $AllMachines) -and ((Test-Path -LiteralPath $wrap) -or (Test-Path -LiteralPath $inner))) {
            $status = ('skipped (not for this machine: no tools\_Watch-{0}-{1}.ps1; opt in with -Watchers {0})' -f $Name, $MachineId)
            if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { $status += '; existing task left untouched' }
        }
        else { $status = 'skipped (no wrapper script)' }
        return [pscustomobject]@{ Task = $TaskName; File = $null; Registered = $false; Started = $false; Status = $status }
    }
    $arg = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$file`""
    $action = New-ScheduledTaskAction -Execute $PsExe -Argument $arg -WorkingDirectory $RepoRoot
    $registered = $true
    $regNote = ''
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $Trigger -Settings $Settings -Principal $Principal -Force -ErrorAction Stop | Out-Null
    }
    catch {
        # e.g. Access is denied from a non-elevated shell: say so instead of reporting success.
        $registered = $false
        $regNote = ('task NOT registered ({0}); ' -f ([string]$_.Exception.Message).Trim())
    }
    $started = $false
    $hits = @(Get-BobInstallProcesses (Get-BobInstallPattern $Name))
    if ($hits.Count -gt 0) {
        $keep = Select-BobTraySingleWatcher -Hits $hits -Label $Name
        $status = ('already running pid={0} (not started again)' -f $keep.ProcessId)
    }
    elseif ($NoStart) {
        $status = 'registered (tray starts / reuses it, #318)'
    }
    else {
        try {
            Start-ScheduledTask -TaskName $TaskName
            $status = 'started now'
            $started = $true
        }
        catch {
            $status = "register-only (start failed: $($_.Exception.Message))"
        }
    }
    return [pscustomobject]@{ Task = $TaskName; File = $file; Registered = $registered; Started = $started; Status = ($regNote + $status) }
}
