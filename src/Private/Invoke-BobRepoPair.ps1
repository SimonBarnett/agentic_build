function Get-BobRepoPairStatePath {
    Join-Path (Get-BridgeRoot) 'repo-pair.json'
}

function Get-BobRepoPairIdleSec {
    if ($env:BOB_REPO_PAIR_IDLE_SEC -and $env:BOB_REPO_PAIR_IDLE_SEC.Trim()) {
        try { return [int]$env:BOB_REPO_PAIR_IDLE_SEC } catch { }
    }
    return 300
}

function Read-BobRepoPairState {
    $p = Get-BobRepoPairStatePath
    $o = Read-JsonFile $p
    if (-not $o) { return $null }
    if (-not $o.seats) {
        $o | Add-Member -NotePropertyName seats -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    return $o
}

function Write-BobRepoPairState {
    param($State)
    if (-not $State) { return }
    $State | Add-Member -NotePropertyName updatedAt -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    Write-JsonFile (Get-BobRepoPairStatePath) $State
}

function Get-BobShopChannelForMachine {
    param([string]$MachineId)
    $mid = $MachineId
    if (-not $mid) { $mid = Get-ThisMachineId }
    if (-not $mid) { return $null }
    if ([string]$mid -eq 'ce-priority-dev1') { return '#ce-priority-dev1' }
    return ('#' + [string]$mid)
}

function Get-BobRepoPairShopNickShort {
    param([string]$MachineId)
    switch ([string]$MachineId) {
        'ionos' { return 'io' }
        'flamingo' { return 'fl' }
        'marchhare' { return 'mh' }
        'ce-priority-dev1' { return 'd1' }
        default {
            $s = [string]$MachineId
            if ($s.Length -ge 2) { return $s.Substring(0, 2) }
            return 'w'
        }
    }
}

function New-BobRepoPairSeat {
    param(
        [Parameter(Mandatory)][ValidateSet('dev', 'mrb')][string]$Role,
        [string]$SessionId,
        [string]$WorkingOn
    )
    $now = [DateTime]::UtcNow.ToString('o')
    return [pscustomobject]@{
        role              = $Role
        sessionId         = $SessionId
        workingOn         = $WorkingOn
        lastActiveAt      = $now
        idleSince         = $null
        implementedPrUrl  = $null
        activeSha         = $null
        lastComplete      = $null
    }
}

function Build-BobRepoPairWorkerPrompt {
    param(
        [Parameter(Mandatory)][ValidateSet('dev', 'mrb')][string]$Role,
        [Parameter(Mandatory)][string]$Repo
    )
    $skills = 'bob-build-dispatch, bob-job-loop, bob-irc, reinstall-agentic-build-skills'
    if ($Role -eq 'dev') {
        $skills += ', cursor-mrb-dev (hand off MRB only to the other seat)'
        return @(
            "You are the persistent DEV worker for repo $Repo on this machine shop."
            "Load skills: $skills."
            'Implement git tasks and open PRs. Never push main. Never merge.'
            'Do not mark ready for human UAT. Bob chairs UAT.'
            'After you open a PR, the other worker MUST hostile-MRB it; you take the next PR.'
            'POST working_on updates via Update-BobRepoWorkerWorkingOn (BobBridge).'
            'Do not put secrets or API key assignments in git or prompts.'
        ) -join ' '
    }
    $skills += ', bob-hostile-mrb, cursor-mrb-dev'
    return @(
        "You are the persistent MRB worker for repo $Repo on this machine shop."
        "Load skills: $skills."
        'Hostile MRB only — never implement the same PR you review.'
        'PASS-nits may merge per existing rule; FAIL spawns FIX on dev seat.'
        'Do not mark ready for human UAT. Bob chairs UAT.'
        'POST working_on updates via Update-BobRepoWorkerWorkingOn (BobBridge).'
        'Do not put secrets or API key assignments in git or prompts.'
    ) -join ' '
}

function Test-BobRepoPairSeatAlive {
    param($Seat)
    if (-not $Seat -or -not $Seat.sessionId) { return $false }
    $sid = [string]$Seat.sessionId
    foreach ($w in @(Get-BobWorkers)) {
        if ([string]$w.sessionId -eq $sid) { return $true }
    }
    return $false
}

function Ensure-BobRepoPairSeat {
    param(
        $State,
        [Parameter(Mandatory)][ValidateSet('dev', 'mrb')][string]$Role,
        [Parameter(Mandatory)][string]$Cwd,
        [Parameter(Mandatory)][string]$Repo,
        [switch]$RegisterOnly
    )
    $seat = $null
    if ($State.seats -and $State.seats.$Role) { $seat = $State.seats.$Role }
    if ($seat -and (Test-BobRepoPairSeatAlive -Seat $seat)) {
        $seat | Add-Member -NotePropertyName lastActiveAt -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
        $seat | Add-Member -NotePropertyName idleSince -NotePropertyValue $null -Force
        return $seat
    }
    $mid = [string]$State.machineId
    if (-not $mid) { $mid = Get-ThisMachineId }
    $short = Get-BobRepoPairShopNickShort -MachineId $mid
    $title = ('w-{0}-{1}' -f $short, $Role)
    $prompt = Build-BobRepoPairWorkerPrompt -Role $Role -Repo $Repo
    $sid = [guid]::NewGuid().ToString()
    if (-not $RegisterOnly) {
        $force = $true
        $r = Start-BobWorker -Cwd $Cwd -Prompt $prompt -Profile generic -Title $title -SessionId $sid -Force:$force
        if ($r.error -eq 'refuse' -or $r.error -eq 'cap') {
            return [pscustomobject]@{ ok = $false; error = 'spawn_failed'; reason = ($r.error); role = $Role }
        }
        if ($r.error -eq 'worker_exists' -and -not $r.sessionId) {
            return [pscustomobject]@{ ok = $false; error = 'spawn_failed'; reason = ($r.error); role = $Role }
        }
        if ($r.sessionId) { $sid = [string]$r.sessionId }
    }
    $seat = New-BobRepoPairSeat -Role $Role -SessionId $sid -WorkingOn $(if ($Role -eq 'dev') { 'dev idle' } else { 'mrb idle' })
    if (-not $State.seats -or ($State.seats -is [hashtable]) -or ($State.seats -is [System.Collections.Specialized.OrderedDictionary])) {
        $State | Add-Member -NotePropertyName seats -NotePropertyValue (New-Object PSObject) -Force
    }
    $State.seats | Add-Member -NotePropertyName $Role -NotePropertyValue $seat -Force
    return $seat
}

function Start-BobRepoPair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Cwd,
        [string]$MachineId,
        [switch]$RegisterOnly
    )
    $repo = [string]$Repo.Trim()
    if (-not $repo) {
        return [pscustomobject]@{ ok = $false; error = 'bad_repo' }
    }
    $cwdFull = [IO.Path]::GetFullPath($Cwd)
    $mid = $MachineId
    if (-not $mid) { $mid = Get-ThisMachineId }
    $prev = Read-BobRepoPairState
    if ($prev -and [string]$prev.repo -and [string]$prev.repo -ne $repo) {
        Set-BobShopChannelRepoDescription -Repo $repo -MachineId $mid | Out-Null
    }
    $state = [pscustomobject]@{
        repo      = $repo
        cwd       = $cwdFull
        machineId = $mid
        seats     = (New-Object PSObject)
    }
    if ($prev -and [string]$prev.repo -eq $repo -and $prev.seats) {
        $state.seats = $prev.seats
    }
    $dev = Ensure-BobRepoPairSeat -State $state -Role dev -Cwd $cwdFull -Repo $repo -RegisterOnly:$RegisterOnly
    if ($dev.error) { return [pscustomobject]@{ ok = $false; error = $dev.error; reason = $dev.reason; role = 'dev' } }
    $mrb = Ensure-BobRepoPairSeat -State $state -Role mrb -Cwd $cwdFull -Repo $repo -RegisterOnly:$RegisterOnly
    if ($mrb.error) { return [pscustomobject]@{ ok = $false; error = $mrb.error; reason = $mrb.reason; role = 'mrb' } }
    Write-BobRepoPairState $state
    Set-BobShopChannelRepoDescription -Repo $repo -MachineId $mid | Out-Null
    return [pscustomobject]@{
        ok    = $true
        repo  = $repo
        cwd   = $cwdFull
        dev   = $dev
        mrb   = $mrb
        state = $state
    }
}

function Get-BobRepoPair {
    [CmdletBinding()]
    param()
    $s = Read-BobRepoPairState
    if (-not $s) {
        return [pscustomobject]@{ ok = $false; error = 'none' }
    }
    return [pscustomobject]@{ ok = $true; pair = $s }
}

function Touch-BobRepoPairSeat {
    param(
        [Parameter(Mandatory)][ValidateSet('dev', 'mrb')][string]$Seat,
        [string]$WorkingOn
    )
    $s = Read-BobRepoPairState
    if (-not $s -or -not $s.seats -or -not $s.seats.$Seat) { return $null }
    $row = $s.seats.$Seat
    $now = [DateTime]::UtcNow.ToString('o')
    $row | Add-Member -NotePropertyName lastActiveAt -NotePropertyValue $now -Force
    $row | Add-Member -NotePropertyName idleSince -NotePropertyValue $null -Force
    if ($WorkingOn) { $row | Add-Member -NotePropertyName workingOn -NotePropertyValue ([string]$WorkingOn) -Force }
    Write-BobRepoPairState $s
    return $row
}

function Update-BobRepoWorkerWorkingOn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('dev', 'mrb')][string]$Seat,
        [Parameter(Mandatory)][string]$Description
    )
    if (Test-PromptSecrets -Prompt $Description) {
        return [pscustomobject]@{ ok = $false; error = 'refuse'; reason = 'description contains secrets pattern' }
    }
    $row = Touch-BobRepoPairSeat -Seat $Seat -WorkingOn $Description
    if (-not $row) {
        return [pscustomobject]@{ ok = $false; error = 'no_pair' }
    }
    $s = Read-BobRepoPairState
    $post = Invoke-BobDigestWebhookPost -WorkingOn $Description -Repo $(if ($s.repo) { [string]$s.repo } else { $null })
    return [pscustomobject]@{
        ok         = $true
        seat       = $Seat
        working_on = $Description
        webhook    = $post
    }
}

function Register-BobRepoPairDevComplete {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PrUrl,
        [string]$Sha
    )
    $s = Read-BobRepoPairState
    if (-not $s -or -not $s.seats -or -not $s.seats.dev) {
        return [pscustomobject]@{ ok = $false; error = 'no_pair' }
    }
    $dev = $s.seats.dev
    $dev | Add-Member -NotePropertyName implementedPrUrl -NotePropertyValue ([string]$PrUrl) -Force
    $dev | Add-Member -NotePropertyName activeSha -NotePropertyValue $null -Force
    $dev | Add-Member -NotePropertyName lastComplete -NotePropertyValue 'dev_complete' -Force
    $dev | Add-Member -NotePropertyName workingOn -NotePropertyValue ('dev complete ' + $PrUrl) -Force
    $dev | Add-Member -NotePropertyName lastActiveAt -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    Write-BobRepoPairState $s
    Update-BobRepoWorkerWorkingOn -Seat dev -Description ('dev complete ' + $PrUrl) | Out-Null
    return [pscustomobject]@{ ok = $true; prUrl = $PrUrl; sha = $Sha }
}

function Register-BobRepoPairMrbComplete {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PrUrl,
        [ValidateSet('PASS-nits', 'PASS', 'FAIL')][string]$Verdict = 'PASS-nits'
    )
    $s = Read-BobRepoPairState
    if (-not $s -or -not $s.seats -or -not $s.seats.mrb) {
        return [pscustomobject]@{ ok = $false; error = 'no_pair' }
    }
    $mrb = $s.seats.mrb
    $tag = 'mrb_complete'
    if ($Verdict -eq 'FAIL') { $tag = 'mrb_fail' }
    $mrb | Add-Member -NotePropertyName lastComplete -NotePropertyValue $tag -Force
    $mrb | Add-Member -NotePropertyName workingOn -NotePropertyValue ("$tag $PrUrl") -Force
    $mrb | Add-Member -NotePropertyName lastActiveAt -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    Write-BobRepoPairState $s
    Update-BobRepoWorkerWorkingOn -Seat mrb -Description ("$tag $PrUrl") | Out-Null
    return [pscustomobject]@{ ok = $true; prUrl = $PrUrl; verdict = $Verdict }
}

function Test-BobRepoPairSelfMrb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('dev', 'mrb')][string]$Seat,
        [Parameter(Mandatory)][string]$PrUrl
    )
    $s = Read-BobRepoPairState
    if (-not $s -or -not $s.seats) {
        return [pscustomobject]@{ ok = $true; allowed = $true; reason = 'no_pair_state' }
    }
    $impl = $null
    if ($s.seats.dev -and $s.seats.dev.implementedPrUrl) {
        $impl = [string]$s.seats.dev.implementedPrUrl
    }
    if (-not $impl) {
        return [pscustomobject]@{ ok = $true; allowed = $true; reason = 'no_implementer_pr' }
    }
    $same = ($impl -eq [string]$PrUrl)
    if ($Seat -eq 'dev' -and $same) {
        return [pscustomobject]@{ ok = $true; allowed = $false; reason = 'implementer_cannot_mrb_own_pr' }
    }
    if ($Seat -eq 'mrb' -and $same) {
        return [pscustomobject]@{ ok = $true; allowed = $true; reason = 'mrb_seat_reviews_implementer_pr' }
    }
    return [pscustomobject]@{ ok = $true; allowed = $true; reason = 'different_pr' }
}

function Test-BobRepoPairMayEnqueueBuild {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Sha)
    $s = Read-BobRepoPairState
    if (-not $s -or -not $s.seats -or -not $s.seats.dev) {
        return [pscustomobject]@{ ok = $true; allowed = $true }
    }
    $active = $null
    if ($s.seats.dev.activeSha) { $active = [string]$s.seats.dev.activeSha }
    if ($active -and $active -ne [string]$Sha) {
        return [pscustomobject]@{ ok = $true; allowed = $true; reason = 'different_sha' }
    }
    if ($active -and $active -eq [string]$Sha) {
        return [pscustomobject]@{ ok = $true; allowed = $false; reason = 'dev_already_building_sha' }
    }
    return [pscustomobject]@{ ok = $true; allowed = $true }
}

function Set-BobRepoPairDevActiveSha {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Sha)
    $s = Read-BobRepoPairState
    if (-not $s -or -not $s.seats -or -not $s.seats.dev) {
        return [pscustomobject]@{ ok = $false; error = 'no_pair' }
    }
    $check = Test-BobRepoPairMayEnqueueBuild -Sha $Sha
    if (-not $check.allowed) {
        return [pscustomobject]@{ ok = $false; error = 'duplicate_build'; reason = $check.reason }
    }
    $s.seats.dev | Add-Member -NotePropertyName activeSha -NotePropertyValue ([string]$Sha) -Force
    Write-BobRepoPairState $s
    return [pscustomobject]@{ ok = $true; sha = $Sha }
}

function Invoke-BobRepoPairTick {
    [CmdletBinding()]
    param()
    $s = Read-BobRepoPairState
    if (-not $s -or -not $s.seats) {
        return [pscustomobject]@{ ok = $true; idleStop = @() }
    }
    $idleSec = Get-BobRepoPairIdleSec
    $stopped = @()
    foreach ($role in @('dev', 'mrb')) {
        $seat = $s.seats.$role
        if (-not $seat) { continue }
        if (-not (Test-BobRepoPairSeatAlive -Seat $seat)) { continue }
        $last = $null
        if ($seat.lastActiveAt) {
            try { $last = [DateTime]::Parse([string]$seat.lastActiveAt, $null, [Globalization.DateTimeStyles]::RoundtripKind) } catch { }
        }
        if (-not $last) { continue }
        $age = ([DateTime]::UtcNow - $last.ToUniversalTime()).TotalSeconds
        if ($age -lt $idleSec) {
            $seat | Add-Member -NotePropertyName idleSince -NotePropertyValue $null -Force
            continue
        }
        if ($seat.sessionId) {
            Stop-BobWorker -SessionId ([string]$seat.sessionId) | Out-Null
            $stopped += $role
            $seat | Add-Member -NotePropertyName sessionId -NotePropertyValue $null -Force
        }
    }
    if ($stopped.Count -gt 0) { Write-BobRepoPairState $s }
    return [pscustomobject]@{ ok = $true; idleStop = @($stopped) }
}

function Get-BobRepoPairBobiverseReport {
    [CmdletBinding()]
    param()
    $s = Read-BobRepoPairState
    if (-not $s) { return @() }
    $lines = New-Object System.Collections.Generic.List[string]
    $repo = [string]$s.repo
    foreach ($role in @('dev', 'mrb')) {
        $seat = $null
        if ($s.seats) { $seat = $s.seats.$role }
        if (-not $seat) { continue }
        $lc = [string]$seat.lastComplete
        if (-not $lc) { continue }
        if ($lc -match 'dev_complete') {
            [void]$lines.Add("Bob digest: dev complete for $repo ($($seat.workingOn)).")
        }
        elseif ($lc -match 'mrb_complete') {
            [void]$lines.Add("Bob digest: MRB complete for $repo ($($seat.workingOn)).")
        }
        elseif ($lc -match 'mrb_fail') {
            [void]$lines.Add("Bob digest: MRB FAIL for $repo ($($seat.workingOn)).")
        }
    }
    return @($lines)
}

function Set-BobShopChannelRepoDescription {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Repo,
        [string]$MachineId
    )
    $mid = $MachineId
    if (-not $mid) { $mid = Get-ThisMachineId }
    $chan = Get-BobShopChannelForMachine -MachineId $mid
    if (-not $chan) {
        return [pscustomobject]@{ ok = $false; error = 'no_machine' }
    }
    $home = Get-BobIrcHome
    if (-not $home) {
        return [pscustomobject]@{ ok = $false; error = 'no_irc_home' }
    }
    New-Item -ItemType Directory -Force -Path $home | Out-Null
    $path = Join-Path $home 'pending-shop-topic.txt'
    $line = ($chan + "`t" + [string]$Repo)
    [IO.File]::WriteAllText($path, $line)
    $s = Read-BobRepoPairState
    if ($s) {
        $s | Add-Member -NotePropertyName channelDescription -NotePropertyValue ([string]$Repo) -Force
        Write-BobRepoPairState $s
    }
    return [pscustomobject]@{ ok = $true; channel = $chan; repo = [string]$Repo; path = $path }
}
