function Get-BobRepoPairRulesText {
    param([Parameter(Mandatory)][ValidateSet('dev', 'mrb')][string]$Role)
    $skillList = if ($Role -eq 'dev') {
        'bob-build-dispatch, bob-irc, reinstall-agentic-build-skills'
    }
    else {
        'bob-hostile-mrb, bob-irc, reinstall-agentic-build-skills'
    }
    return @(
        "Persistent repo-pair $Role seat. Load skills: $skillList."
        'JOIN the machine shop channel only (never #bobiverse).'
        'Do your own implement or hostile MRB work in this seat.'
        'Do not invoke Start-BobBuild, Start-BobBuildLoop, Start-BobMrbHandoff, or cursor-mrb-dev handoff.'
        'Chair assigns work via Assign-BobRepoPairTask; execute assigned tasks only.'
        'POST working_on via Update-BobRepoWorkerWorkingOn. Never stamp ready for human UAT.'
    ) -join ' '
}

function Get-BobRepoPairWorkerProfile {
    param([Parameter(Mandatory)][ValidateSet('dev', 'mrb')][string]$Role)
    if ($Role -eq 'dev') { return 'repo-pair-dev' }
    return 'repo-pair-mrb'
}

function Select-BobRepoPairFuel {
    param([Parameter(Mandatory)][ValidateSet('dev', 'mrb')][string]$Role)
    if (Test-BobUsesFakeGrok) { return 'grok-build' }
    $cur = 0
    try {
        $c = Get-BobCursorAgentWeeklyRemaining
        if ($c -and $null -ne $c.remaining_pct) {
            $rp = $c.remaining_pct
            if ($rp -is [System.Array]) { $rp = @($rp)[0] }
            $cur = [int]$rp
        }
    }
    catch { }
    if ($cur -gt 0) { return 'cursor-models' }
    return 'grok-build'
}

function Get-BobRepoPairWorkerModel {
    param(
        [Parameter(Mandatory)][ValidateSet('dev', 'mrb')][string]$Role,
        [string]$Fuel
    )
    $kind = if ($Role -eq 'dev') { 'build' } else { 'mrb' }
    if ($Fuel -eq 'cursor-models') {
        return Get-BobJobModel -Kind $kind -Fuel cursor-models
    }
    return Get-BobJobModel -Kind $kind -Fuel grok-build
}

function ConvertTo-BobRepoPairProcessId {
    param($Raw)
    if ($null -eq $Raw) { return $null }
    if ($Raw -is [System.Array]) { $Raw = @($Raw)[0] }
    try { return [int]$Raw } catch { return $null }
}

function Start-BobRepoPairShopJoin {
    param(
        [Parameter(Mandatory)][string]$ShopChannel,
        [Parameter(Mandatory)][string]$ShopNick,
        [Parameter(Mandatory)][string]$SessionId
    )
    $home = Get-BobIrcHome
    if (-not $home) {
        return [pscustomobject]@{ ok = $false; error = 'no_irc_home' }
    }
    New-Item -ItemType Directory -Force -Path $home | Out-Null
    $manifestPath = Join-Path $home ('shop-join-' + $SessionId + '.json')
    $manifest = [pscustomobject]@{
        channel   = $ShopChannel
        nick      = $ShopNick
        sessionId = $SessionId
        joinedAt  = [DateTime]::UtcNow.ToString('o')
        policy    = 'shop_only_no_bobiverse'
    }
    Write-JsonFile $manifestPath $manifest
    $flag = Join-Path $home ('shop-joined-' + $ShopNick + '.flag')
    $joinPid = $null
    if (Test-BobUsesFakeGrok -ErrorAction SilentlyContinue) {
        [IO.File]::WriteAllText($flag, ([string]$ShopChannel + "`t" + $ShopNick))
        return [pscustomobject]@{ ok = $true; nick = $ShopNick; channel = $ShopChannel; flag = $flag; pid = $null }
    }
    $stub = Join-Path $home ('shop-join-' + $SessionId + '.ps1')
    $body = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$flag = '$($flag.Replace("'","''"))'
`$line = '$($ShopChannel.Replace("'","''"))`t$($ShopNick.Replace("'","''"))'
while (`$true) {
    [IO.File]::WriteAllText(`$flag, `$line)
    Start-Sleep -Seconds 30
}
"@
    [IO.File]::WriteAllText($stub, $body)
    $exe = (Get-Command powershell.exe).Source
    $cmdLine = '"{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}"' -f $exe, $stub
    $created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine      = $cmdLine
        CurrentDirectory = $home
    }
    if ($created.ReturnValue -eq 0 -and $created.ProcessId) {
        $joinPid = ConvertTo-BobRepoPairProcessId $created.ProcessId
        [IO.File]::WriteAllText($flag, ([string]$ShopChannel + "`t" + $ShopNick))
    }
    return [pscustomobject]@{ ok = $true; nick = $ShopNick; channel = $ShopChannel; flag = $flag; pid = $joinPid }
}

function Start-BobRepoPairWorker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('dev', 'mrb')][string]$Role,
        [Parameter(Mandatory)][string]$Cwd,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][string]$ShopNick,
        [Parameter(Mandatory)][string]$ShopChannel
    )

    if (Test-PromptSecrets -Prompt $Repo) {
        return [pscustomobject]@{ ok = $false; error = 'refuse'; reason = 'repo looks like secret' }
    }

    $cwdFull = [IO.Path]::GetFullPath($Cwd)
    $profileName = Get-BobRepoPairWorkerProfile -Role $Role
    $prof = Get-Profile -Name $profileName
    $fuel = Select-BobRepoPairFuel -Role $Role
    $model = Get-BobRepoPairWorkerModel -Role $Role -Fuel $fuel
    $prompt = Build-BobRepoPairWorkerPrompt -Role $Role -Repo $Repo

    $dir = Get-WorkerDir $SessionId
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'outbox') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'inbox') | Out-Null

    $heartbeatPath = Join-Path $dir 'heartbeat.json'
    $supervisor = Join-Path $dir 'seat-supervisor.ps1'
    $moduleRoot = Get-ModuleRoot
    $psd1 = Join-Path $moduleRoot 'src\BobBridge.psd1'
    $supervisorBody = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$env:BOB_BRIDGE_HOME = '$((Get-BridgeRoot).Replace("'","''"))'
Import-Module '$($psd1.Replace("'","''"))' -Force
`$seat = '$Role'
`$sid = '$SessionId'
`$hb = '$($heartbeatPath.Replace("'","''"))'
while (`$true) {
    @{ seat = `$seat; sessionId = `$sid; at = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json -Compress |
        Set-Content -LiteralPath `$hb -Encoding utf8
    try {
        `$s = Read-BobRepoPairState
        if (`$s -and `$s.seats -and `$s.seats.`$seat -and `$s.seats.`$seat.chairTask) {
            `$row = `$s.seats.`$seat
            `$row | Add-Member -NotePropertyName lastActiveAt -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
            Write-BobRepoPairState `$s
        }
    }
    catch { }
    Start-Sleep -Seconds 15
}
"@
    [IO.File]::WriteAllText($supervisor, $supervisorBody)

    $exe = (Get-Command powershell.exe).Source
    $cmdLine = '"{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}"' -f $exe, $supervisor
    $created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine      = $cmdLine
        CurrentDirectory = $cwdFull
    }
    if ($created.ReturnValue -ne 0 -or -not $created.ProcessId) {
        return [pscustomobject]@{ ok = $false; error = 'spawn_failed'; reason = "supervisor return=$($created.ReturnValue)" }
    }
    $procId = ConvertTo-BobRepoPairProcessId $created.ProcessId
    if (-not $procId) {
        return [pscustomobject]@{ ok = $false; error = 'spawn_failed'; reason = 'bad_supervisor_pid' }
    }

    $join = Start-BobRepoPairShopJoin -ShopChannel $ShopChannel -ShopNick $ShopNick -SessionId $SessionId
    if (-not $join.ok) {
        try { Stop-ProcessTree -ProcessId $procId } catch { }
        return [pscustomobject]@{ ok = $false; error = 'shop_join_failed'; reason = $join.error }
    }

    try { Copy-BobProjectSkills | Out-Null } catch { }
    Write-Audit -SessionId $SessionId -Cwd $cwdFull -Profile $profileName -Prompt $prompt

    $argv = Get-BobArgv -Prompt $prompt -Cwd $cwdFull -SessionId $SessionId -Profile $prof -Model $model
    [IO.File]::WriteAllText((Join-Path $dir 'outbox\argv.txt'), (($argv | ForEach-Object { $_ }) -join "`n"))

    $now = [DateTime]::UtcNow.ToString('o')
    $status = [pscustomobject]@{
        sessionId       = $SessionId
        kind            = 'persistent'
        state           = 'running'
        cwd             = $cwdFull
        title           = $Title
        updatedAt       = $now
        pid             = $procId
        lastHeartbeat   = $now
        fuel            = $fuel
        model           = $model
        role            = $Role
        shopNick        = $ShopNick
        shopChannel     = $ShopChannel
        shopJoinPid     = $join.pid
    }
    Write-JsonFile (Join-Path $dir 'status.json') $status

    $overlay = Read-Overlay
    $entry = [pscustomobject]@{
        sessionId   = $SessionId
        title       = $Title
        cwd         = $cwdFull
        kind        = 'persistent'
        profile     = $profileName
        createdAt   = $now
        pid         = $procId
        shopNick    = $ShopNick
        shopChannel = $ShopChannel
        fuel        = $fuel
        model       = $model
        role        = $Role
    }
    $workers = @($overlay.workers | Where-Object { $_.sessionId -ne $SessionId })
    $workers += $entry
    $overlay | Add-Member -NotePropertyName workers -NotePropertyValue $workers -Force
    Write-Overlay $overlay

    return [pscustomobject]@{
        ok          = $true
        sessionId   = $SessionId
        pid         = $procId
        processGone = $false
        kind        = 'persistent'
        fuel        = $fuel
        model       = $model
        shopNick    = $ShopNick
        argv        = $argv
    }
}
