function Get-BobRepoPairRulesText {
    param([Parameter(Mandatory)][ValidateSet('dev', 'mrb')][string]$Role)
    $skillList = if ($Role -eq 'dev') {
        'bob-spec-intake, bob-irc, reinstall-agentic-build-skills'
    }
    else {
        'bob-hostile-mrb, bob-irc, reinstall-agentic-build-skills'
    }
    return @(
        "Persistent repo-pair $Role seat. Load skills: $skillList."
        'JOIN the machine shop channel only (never #bobiverse).'
        'Do your own implement or hostile MRB work in this seat.'
        'Do not invoke Start-BobBuild, Start-BobBuildLoop, Start-BobMrbHandoff, or cursor-mrb-dev handoff.'
        'Chair assigns work via inbox/chair-task; execute assigned tasks only.'
        'POST working_on via Update-BobRepoWorkerWorkingOn. Never stamp ready for human UAT.'
        'MRB: merge duplicate issues, close finished/superseded issues, merge PR on PASS-nits.'
        'Workers report status via webhook only — no shop or fleet PRIVMSG.'
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

function Select-BobRepoPairInvokeMode {
    param(
        [Parameter(Mandatory)][ValidateSet('dev', 'mrb')][string]$Role,
        [string]$Fuel
    )
    if (Test-BobUsesFakeGrok) { return 'fake-seat' }
    $hostPref = $null
    if ($env:BOB_REPO_PAIR_AGENT_HOST -and $env:BOB_REPO_PAIR_AGENT_HOST.Trim()) {
        $hostPref = $env:BOB_REPO_PAIR_AGENT_HOST.Trim().ToLowerInvariant()
    }
    if ($hostPref -eq 'agent.com' -and (Test-GrokBotAvailable)) {
        return 'grokbot'
    }
    if ($Fuel -eq 'cursor-models') {
        if (Get-BobCursorAgentExePath) { return 'cursor-cli' }
    }
    if (Get-GrokExe) { return 'grok-cli' }
    return 'fake-seat'
}

function Get-BobRepoPairWorkerModel {
    param(
        [Parameter(Mandatory)][ValidateSet('dev', 'mrb')][string]$Role,
        [string]$Fuel,
        [string]$InvokeMode
    )
    if ($InvokeMode -eq 'grokbot') {
        return Get-BobJobModel -Kind $(if ($Role -eq 'dev') { 'build' } else { 'mrb' }) -Fuel grok-build
    }
    $kind = if ($Role -eq 'dev') { 'build' } else { 'mrb' }
    if ($Fuel -eq 'cursor-models' -and $InvokeMode -eq 'cursor-cli') {
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

function Get-BobRepoPairIrcAgentScriptPath {
    $ircRoot = $null
    if (Test-Path 'C:\ai\agentic_irc') { $ircRoot = 'C:\ai\agentic_irc' }
    elseif (Test-Path 'D:\ai\agentic_irc') { $ircRoot = 'D:\ai\agentic_irc' }
    if ($ircRoot) {
        $agent = Join-Path $ircRoot 'scripts\irc_agent.py'
        if (Test-Path $agent) { return $agent }
    }
    return $null
}

function Start-BobRepoPairShopIrc {
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
    $ircPid = $null
    $joinKind = 'irc_agent'

    if (Test-BobUsesFakeGrok -ErrorAction SilentlyContinue) {
        $stubPy = Join-Path $home 'irc_agent.py'
        if (-not (Test-Path $stubPy)) {
            [IO.File]::WriteAllText($stubPy, "# BT0 shop irc stub`nimport time`nwhile True: time.sleep(60)`n")
        }
        $loopPs1 = Join-Path $home ('shop-irc-loop-' + $SessionId + '.ps1')
        $body = @"
`$ErrorActionPreference = 'SilentlyContinue'
while (`$true) { Start-Sleep -Seconds 60 }
"@
        [IO.File]::WriteAllText($loopPs1, $body)
        $exe = (Get-Command powershell.exe).Source
        $cmdLine = '"{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}" irc_agent.py --nick {2} --channel {3}' -f $exe, $loopPs1, $ShopNick, $ShopChannel
        $created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
            CommandLine      = $cmdLine
            CurrentDirectory = $home
        }
        if ($created.ReturnValue -eq 0 -and $created.ProcessId) {
            $ircPid = ConvertTo-BobRepoPairProcessId $created.ProcessId
        }
    }
    else {
        $agent = Get-BobRepoPairIrcAgentScriptPath
        if (-not $agent) {
            return [pscustomobject]@{ ok = $false; error = 'no_irc_agent' }
        }
        $py = $null
        foreach ($c in @(
                (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
                (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe')
            )) {
            if (Test-Path $c) { $py = $c; break }
        }
        if (-not $py) {
            $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.Source -notmatch 'WindowsApps') { $py = $cmd.Source }
        }
        if (-not $py) {
            return [pscustomobject]@{ ok = $false; error = 'no_python' }
        }
        $cfg = $null
        try { $cfg = Get-BobiverseConfig } catch { }
        $ircHost = '127.0.0.1'
        $ircPort = 6697
        if ($cfg -and $cfg.host -and [string]$cfg.host -ne 'irc.libera.chat') {
            $ircHost = [string]$cfg.host
            if ($cfg.port) { $ircPort = [int]$cfg.port }
        }
        if ($env:BOB_IRC_HOST -and $env:BOB_IRC_HOST.Trim()) {
            $ircHost = $env:BOB_IRC_HOST.Trim()
        }
        $pwFile = Join-Path $env:USERPROFILE '.grok\ergo\connect.password'
        if (-not (Test-Path $pwFile)) {
            return [pscustomobject]@{ ok = $false; error = 'no_irc_password' }
        }
        $env:AGENTIC_IRC_PASSWORD = (Get-Content $pwFile -Raw).Trim()
        $env:AGENTIC_IRC_HOME = $home
        $argList = @(
            '-u', $agent,
            '--host', $ircHost,
            '--port', "$ircPort",
            '--nick', $ShopNick,
            '--channel', $ShopChannel,
            '--home', $home,
            '--hello', ('shop-' + $ShopNick)
        )
        $quoted = @($argList | ForEach-Object {
            '"' + (([string]$_) -replace '"', '\"') + '"'
        }) -join ' '
        $cmdLine = '"{0}" {1}' -f $py, $quoted
        $ircRoot = Split-Path (Split-Path $agent -Parent) -Parent
        $created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
            CommandLine      = $cmdLine
            CurrentDirectory = $ircRoot
        }
        if ($created.ReturnValue -ne 0 -or -not $created.ProcessId) {
            return [pscustomobject]@{ ok = $false; error = 'irc_spawn_failed' }
        }
        $ircPid = ConvertTo-BobRepoPairProcessId $created.ProcessId
    }

    if (-not $ircPid) {
        return [pscustomobject]@{ ok = $false; error = 'irc_join_failed' }
    }

    $manifest = [pscustomobject]@{
        channel     = $ShopChannel
        nick        = $ShopNick
        sessionId   = $SessionId
        joinedAt    = [DateTime]::UtcNow.ToString('o')
        policy      = 'shop_only_no_bobiverse'
        joinKind    = $joinKind
        ircAgentPid = $ircPid
    }
    Write-JsonFile $manifestPath $manifest
    return [pscustomobject]@{
        ok          = $true
        nick        = $ShopNick
        channel     = $ShopChannel
        manifest    = $manifestPath
        pid         = $ircPid
        joinKind    = $joinKind
    }
}

function Start-BobRepoPairSeatAgent {
    param(
        [Parameter(Mandatory)][ValidateSet('dev', 'mrb')][string]$Role,
        [Parameter(Mandatory)][string]$Cwd,
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$InvokeMode,
        [string]$Model,
        $Profile,
        [string[]]$Argv
    )
    $dir = Get-WorkerDir $SessionId
    $heartbeatPath = Join-Path $dir 'heartbeat.json'
    $agentPath = Join-Path $dir 'seat-agent.ps1'
    $moduleRoot = Get-ModuleRoot
    $psd1 = Join-Path $moduleRoot 'src\BobBridge.psd1'
    $grokExe = Get-GrokExe
    if (-not $grokExe) { $grokExe = '' }
    $argvEsc = ($Argv | ForEach-Object { [string]$_ }) -join '|'
    $cursorAgent = ''
    if ($InvokeMode -eq 'cursor-cli') {
        $ca = Get-BobCursorAgentExePath
        if ($ca) { $cursorAgent = $ca }
    }
    $cwdFull = [IO.Path]::GetFullPath($Cwd)
    $promptFile = Join-Path $dir 'outbox\initial-prompt.txt'
    [IO.File]::WriteAllText($promptFile, $Prompt)
    if ($InvokeMode -eq 'cursor-cli' -and $cursorAgent) {
        $ps1 = $cursorAgent
        if ($cursorAgent -match '\.cmd$') { $ps1 = Join-Path (Split-Path $cursorAgent) 'cursor-agent.ps1' }
        $launch = Join-Path $dir 'seat-cursor.launch.ps1'
        $launchBody = @"
`$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath '$($cwdFull.Replace("'","''"))'
`$prompt = [IO.File]::ReadAllText('$($promptFile.Replace("'","''"))')
& '$($ps1.Replace("'","''"))' -p --force --trust --output-format text --model '$($Model.Replace("'","''"))' -- `$prompt
"@
        [IO.File]::WriteAllText($launch, $launchBody)
    }

    $agentBody = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$env:BOB_BRIDGE_HOME = '$((Get-BridgeRoot).Replace("'","''"))'
Import-Module '$($psd1.Replace("'","''"))' -Force
`$sessionId = '$SessionId'
`$role = '$Role'
`$mode = '$InvokeMode'
`$hb = '$($heartbeatPath.Replace("'","''"))'
`$cwd = '$($cwdFull.Replace("'","''"))'
`$childPid = `$null

function Write-SeatHeartbeat {
    param([int]`$AgentPid)
    @{ seat = `$role; sessionId = `$sessionId; at = [DateTime]::UtcNow.ToString('o'); agentPid = `$AgentPid } |
        ConvertTo-Json -Compress | Set-Content -LiteralPath `$hb -Encoding utf8
}

function Get-SeatAgentPid {
    if (`$childPid) { return [int]`$childPid }
    return [int]`$PID
}

if (`$mode -eq 'fake-seat') {
    while (`$true) {
        Write-SeatHeartbeat -AgentPid (Get-SeatAgentPid)
        Start-Sleep -Seconds 15
    }
}

if (`$mode -eq 'grok-cli') {
    `$grok = '$($grokExe.Replace("'","''"))'
    `$argvRaw = '$($argvEsc.Replace("'","''"))'.Split('|')
    if (`$grok -and (Test-Path -LiteralPath `$grok)) {
        if (`$grok -match '\.ps1$') {
            `$p = Start-Process -FilePath (Get-Command powershell.exe).Source -ArgumentList (@('-NoProfile','-ExecutionPolicy','Bypass','-File',`$grok) + `$argvRaw) -WorkingDirectory `$cwd -PassThru -WindowStyle Hidden
            `$childPid = `$p.Id
        }
        else {
            `$quoted = @(`$argvRaw | ForEach-Object { '"' + (`$_ -replace '"','\"') + '"' }) -join ' '
            `$p = Start-Process -FilePath `$grok -ArgumentList `$quoted -WorkingDirectory `$cwd -PassThru -NoNewWindow
            `$childPid = `$p.Id
        }
    }
    while (`$true) {
        if (`$childPid) {
            `$cp = Get-Process -Id `$childPid -ErrorAction SilentlyContinue
            if (-not `$cp) { break }
        }
        Write-SeatHeartbeat -AgentPid (Get-SeatAgentPid)
        `$inbox = Join-Path (Get-WorkerDir `$sessionId) 'inbox\chair-task.txt'
        if (Test-Path -LiteralPath `$inbox) {
            try { Touch-BobRepoPairSeat -Seat `$role -WorkingOn ([IO.File]::ReadAllText(`$inbox).Trim()) | Out-Null } catch { }
        }
        Start-Sleep -Seconds 15
    }
    exit 0
}

if (`$mode -eq 'cursor-cli') {
    `$launch = Join-Path (Get-WorkerDir `$sessionId) 'seat-cursor.launch.ps1'
    if (Test-Path -LiteralPath `$launch) {
        `$p = Start-Process -FilePath (Get-Command powershell.exe).Source -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',`$launch) -WorkingDirectory `$cwd -PassThru
        `$childPid = `$p.Id
    }
    while (`$true) {
        if (`$childPid) {
            `$cp = Get-Process -Id `$childPid -ErrorAction SilentlyContinue
            if (-not `$cp) { break }
        }
        Write-SeatHeartbeat -AgentPid (Get-SeatAgentPid)
        Start-Sleep -Seconds 15
    }
    exit 0
}

while (`$true) {
    Write-SeatHeartbeat -AgentPid (Get-SeatAgentPid)
    Start-Sleep -Seconds 15
}
"@
    [IO.File]::WriteAllText($agentPath, $agentBody)

    $exe = (Get-Command powershell.exe).Source
    $cmdLine = '"{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}"' -f $exe, $agentPath
    $created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine      = $cmdLine
        CurrentDirectory = [IO.Path]::GetFullPath($Cwd)
    }
    if ($created.ReturnValue -ne 0 -or -not $created.ProcessId) {
        return [pscustomobject]@{ ok = $false; error = 'agent_spawn_failed' }
    }
    $procId = ConvertTo-BobRepoPairProcessId $created.ProcessId
    @{ seat = $Role; sessionId = $SessionId; at = [DateTime]::UtcNow.ToString('o'); agentPid = $procId } |
        ConvertTo-Json -Compress | Set-Content -LiteralPath $heartbeatPath -Encoding utf8
    return [pscustomobject]@{ ok = $true; pid = $procId; invokeMode = $InvokeMode }
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
    $invokeMode = Select-BobRepoPairInvokeMode -Role $Role -Fuel $fuel
    $model = Get-BobRepoPairWorkerModel -Role $Role -Fuel $fuel -InvokeMode $invokeMode
    $prompt = Build-BobRepoPairWorkerPrompt -Role $Role -Repo $Repo

    $dir = Get-WorkerDir $SessionId
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'outbox') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'inbox') | Out-Null

    $join = Start-BobRepoPairShopIrc -ShopChannel $ShopChannel -ShopNick $ShopNick -SessionId $SessionId
    if (-not $join.ok) {
        return [pscustomobject]@{ ok = $false; error = 'shop_join_failed'; reason = $join.error }
    }

    $argv = @()
    if ($invokeMode -eq 'grok-cli') {
        $argv = Get-BobArgv -Prompt $prompt -Cwd $cwdFull -SessionId $SessionId -Profile $prof -Model $model
    }
    elseif ($invokeMode -eq 'cursor-cli') {
        $argv = @('cursor-agent', '-p', '--model', $model)
    }
    elseif ($invokeMode -eq 'grokbot') {
        $argv = @('grokbot', 'persistent', $ShopNick)
    }
    else {
        $argv = @('fake-seat', $Role)
    }
    [IO.File]::WriteAllText((Join-Path $dir 'outbox\argv.txt'), (($argv | ForEach-Object { $_ }) -join "`n"))

    $agent = Start-BobRepoPairSeatAgent -Role $Role -Cwd $cwdFull -SessionId $SessionId -Prompt $prompt -InvokeMode $invokeMode -Model $model -Profile $prof -Argv $argv
    if (-not $agent.ok) {
        if ($join.pid) {
            try { Stop-ProcessTree -ProcessId ([int]$join.pid) } catch { }
        }
        return [pscustomobject]@{ ok = $false; error = 'spawn_failed'; reason = $agent.error }
    }
    $procId = $agent.pid

    try { Copy-BobProjectSkills | Out-Null } catch { }
    Write-Audit -SessionId $SessionId -Cwd $cwdFull -Profile $profileName -Prompt $prompt

    $now = [DateTime]::UtcNow.ToString('o')
    $status = [pscustomobject]@{
        sessionId     = $SessionId
        kind          = 'persistent'
        state         = 'running'
        cwd           = $cwdFull
        title         = $Title
        updatedAt     = $now
        pid           = $procId
        agentPid      = $procId
        lastHeartbeat = $now
        fuel          = $fuel
        model         = $model
        role          = $Role
        shopNick      = $ShopNick
        shopChannel   = $ShopChannel
        shopJoinPid   = $join.pid
        ircJoinManifest = $join.manifest
        invokeMode    = $invokeMode
        transport     = $invokeMode
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
        invokeMode  = $invokeMode
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
        invokeMode  = $invokeMode
    }
}
