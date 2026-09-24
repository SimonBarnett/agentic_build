# Shop backup for Jeeves GIT work (Simon 2026-09-24).
# Chair FIFO lives in agentic_irc (jeeves-git-webhook / irc_agent.py --chair).
# This file does not write the chair queue and does not write the chair outbox.
# bob-* ears do not auto-claim GIT lines on #bobiverse.
# w-* idle > 2 min says !BORED on the shop; on a later Jeeves OFFER or
# claimable GIT in that shop, the same nick says !ACCEPT and Start-BobBuild.
# Copilot stays off (no Allow switch on Start-BobBuild).

function Get-BobGitChairNicks {
    $nicks = New-Object System.Collections.Generic.List[string]
    function Add-Nick([string]$Name) {
        $t = ([string]$Name).Trim()
        if (-not $t) { return }
        foreach ($have in @($nicks)) {
            if ($have -eq $t) { return }
        }
        $nicks.Add($t) | Out-Null
    }
    Add-Nick 'Jeeves'
    $cfg = $null
    try { $cfg = Get-BobiverseConfig } catch { }
    if ($cfg -and $cfg.chairNick) { Add-Nick ([string]$cfg.chairNick) }
    if ($env:BOB_IRC_CHAIR_NICK -and $env:BOB_IRC_CHAIR_NICK.Trim()) {
        Add-Nick $env:BOB_IRC_CHAIR_NICK.Trim()
    }
    return @($nicks)
}

function ConvertFrom-BobGitOffer {
    param([string]$Body)
    $raw = ([string]$Body).Trim()
    if ($raw -notmatch '^(?i)OFFER\s+(\S+)\s+(PR|MRB|BUILD)\s+(\d+)\s*$') { return $null }
    $repo = [string]$Matches[1]
    $task = ([string]$Matches[2]).ToUpperInvariant()
    $id = [string]$Matches[3]
    if ($repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { return $null }
    return [pscustomobject]@{
        repo   = $repo
        task   = $task
        id     = $id
        event  = $null
        action = $null
        source = 'offer'
    }
}

function ConvertFrom-BobGitAnnounce {
    <#
      Claimable Jeeves GIT lines only. ping, push, and unknown actions return null.
      issues opened -> PR (issue to PR). labeled only with label=FR|build|feature-request
      (live Jeeves text does not include the label name).
      pull_request opened|ready_for_review|synchronize -> MRB.
    #>
    param([string]$Body)
    $raw = ([string]$Body).Trim()
    if (-not $raw.StartsWith('GIT ')) { return $null }
    $rest = $raw.Substring(4).Trim()
    if (-not $rest) { return $null }
    $parts = @($rest -split '\s+' | Where-Object { $_ })
    if ($parts.Count -lt 2) { return $null }
    $event = ([string]$parts[0]).ToLowerInvariant()
    if ($event -eq 'ping') { return $null }
    $repo = [string]$parts[1]
    if ($repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { return $null }
    $action = $null
    $id = $null
    $tail = @()
    if ($parts.Count -gt 2) { $tail = @($parts[2..($parts.Count - 1)]) }
    foreach ($tok in $tail) {
        if (-not $action -and $tok -notmatch '^#' -and $tok -ne 'by') {
            $action = ([string]$tok).ToLowerInvariant()
            continue
        }
        if ($tok -match '^#(\d+)$') { $id = [string]$Matches[1] }
    }
    if (-not $id -or -not $action) { return $null }
    $task = $null
    if ($event -eq 'issues' -and $action -eq 'opened') {
        $task = 'PR'
    }
    elseif ($event -eq 'issues' -and $action -eq 'labeled') {
        $blob = ($tail -join ' ')
        if ($blob -match '(?i)(?:^|\s)label=(FR|build|feature-request)(?:\s|$)') { $task = 'PR' }
    }
    elseif ($event -eq 'pull_request') {
        if (@('opened', 'ready_for_review', 'synchronize') -contains $action) { $task = 'MRB' }
    }
    if (-not $task) { return $null }
    return [pscustomobject]@{
        repo   = $repo
        task   = $task
        id     = $id
        event  = $event
        action = $action
        source = 'git'
    }
}

function ConvertFrom-BobShopWorkLine {
    param([string]$Body)
    $offer = ConvertFrom-BobGitOffer $Body
    if ($offer) { return $offer }
    return (ConvertFrom-BobGitAnnounce $Body)
}

function Get-BobGitAcceptQueuePath {
    param([string]$Path)
    if ($Path -and $Path.Trim()) { return $Path.Trim() }
    $home = $null
    try { $home = Get-BobIrcHome } catch { }
    if (-not $home) { return $null }
    return (Join-Path $home 'git-accept-queue.json')
}

function Get-BobGitAcceptQueue {
    <#
      Read-only. Chair (agentic_irc) writes git-accept-queue.json.
      Missing or malformed file yields an empty list. Never creates the file.
    #>
    param([string]$Path)
    $p = Get-BobGitAcceptQueuePath -Path $Path
    if (-not $p -or -not (Test-Path -LiteralPath $p)) { return @() }
    try {
        $doc = Read-JsonFile $p
    }
    catch { return @() }
    if (-not $doc -or -not $doc.pending) { return @() }
    $rows = @()
    foreach ($item in @($doc.pending)) {
        if (-not $item) { continue }
        $repo = [string]$item.repo
        $task = ([string]$item.task).ToUpperInvariant()
        $id = [string]$item.id
        if ($repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { continue }
        if (@('PR', 'MRB', 'BUILD') -notcontains $task) { continue }
        if ($id -notmatch '^\d+$') { continue }
        $rows += [pscustomobject]@{
            repo     = $repo
            task     = $task
            id       = $id
            enqueued = $(if ($item.enqueued) { [string]$item.enqueued } else { $null })
        }
    }
    return $rows
}

function Add-BobWorkerShopOutboxLine {
    param(
        [Parameter(Mandatory)][string]$WorkerHome,
        [Parameter(Mandatory)][string]$Line
    )
    $text = $Line.Trim()
    if (-not $text) { return }
    if (-not (Test-Path -LiteralPath $WorkerHome)) {
        New-Item -ItemType Directory -Force -Path $WorkerHome | Out-Null
    }
    $outbox = Join-Path $WorkerHome 'outbox.txt'
    $last = $null
    if (Test-Path -LiteralPath $outbox) {
        try { $last = Get-Content -LiteralPath $outbox -Tail 1 -ErrorAction SilentlyContinue } catch { }
    }
    if ($last -and ([string]$last).Trim() -eq $text) { return }
    Add-Content -LiteralPath $outbox -Value $text -Encoding utf8
}

function Get-BobWorkerBoredStatePath {
    param([Parameter(Mandatory)][string]$WorkerHome)
    Join-Path $WorkerHome 'bored-state.json'
}

function Read-BobWorkerBoredState {
    param([Parameter(Mandatory)][string]$WorkerHome)
    $p = Get-BobWorkerBoredStatePath $WorkerHome
    $idleSince = $null
    $boredSent = $false
    $boredAtBytes = 0
    if (Test-Path -LiteralPath $p) {
        try {
            $j = Read-JsonFile $p
            if ($j) {
                if ($j.idleSince) {
                    try {
                        $idleSince = [datetime]::Parse([string]$j.idleSince, $null, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
                    }
                    catch { $idleSince = $null }
                }
                if ($j.boredSent) { $boredSent = [bool]$j.boredSent }
                if ($null -ne $j.boredAtBytes -and [string]$j.boredAtBytes -ne '') {
                    try { $boredAtBytes = [int]$j.boredAtBytes } catch { $boredAtBytes = 0 }
                }
            }
        }
        catch { }
    }
    return [pscustomobject]@{
        idleSince    = $idleSince
        boredSent    = $boredSent
        boredAtBytes = $boredAtBytes
    }
}

function Write-BobWorkerBoredState {
    param(
        [Parameter(Mandatory)][string]$WorkerHome,
        [datetime]$IdleSince,
        [bool]$BoredSent,
        [int]$BoredAtBytes = 0
    )
    $doc = [ordered]@{
        boredSent    = [bool]$BoredSent
        boredAtBytes = [int]$BoredAtBytes
    }
    if ($IdleSince -and $IdleSince -ne [datetime]::MinValue) {
        $doc.idleSince = $IdleSince.ToUniversalTime().ToString('o')
    }
    else {
        $doc.idleSince = $null
    }
    Write-JsonFile (Get-BobWorkerBoredStatePath $WorkerHome) ([pscustomobject]$doc)
}

function Get-BobWorkerIrcLogSnapshot {
    param([Parameter(Mandatory)][string]$WorkerHome)
    $logPath = Join-Path $WorkerHome 'irc.log'
    if (-not (Test-Path -LiteralPath $logPath)) {
        return [pscustomobject]@{ text = ''; length = 0 }
    }
    $raw = [IO.File]::ReadAllBytes($logPath)
    return [pscustomobject]@{
        text   = [Text.Encoding]::UTF8.GetString($raw)
        length = $raw.Length
    }
}

function Get-BobShopPrivmsgLines {
    param([string]$Text)
    $rows = @()
    if (-not $Text) { return $rows }
    foreach ($line in @($Text -split "`n")) {
        $t = ([string]$line).Trim()
        if (-not $t) { continue }
        if ($t -match '^:(?<nick>[^!\s]+)![^\s]*\s+PRIVMSG\s+(?<target>\S+)\s+:(?<body>.*)$') {
            $rows += [pscustomobject]@{
                nick   = [string]$Matches['nick']
                target = [string]$Matches['target']
                body   = ([string]$Matches['body']).Trim()
            }
        }
    }
    return $rows
}

function Test-BobGitChairNick {
    param([string]$Nick, [string[]]$ChairNicks)
    if (-not $Nick) { return $false }
    foreach ($c in @($ChairNicks)) {
        if ($c -and ($c.ToLowerInvariant() -eq $Nick.ToLowerInvariant())) { return $true }
    }
    return $false
}

function Test-BobShopOfferTarget {
    param([string]$Target, [string]$ShopChannel, [string]$WorkerNick)
    $tg = ([string]$Target).Trim().ToLowerInvariant()
    if (-not $tg) { return $false }
    if ($tg -eq '#bobiverse') { return $false }
    if ($ShopChannel -and $tg -eq $ShopChannel.Trim().ToLowerInvariant()) { return $true }
    if ($WorkerNick -and $tg -eq $WorkerNick.Trim().ToLowerInvariant()) { return $true }
    return $false
}

function Get-BobGitAcceptClaimPath {
    param([Parameter(Mandatory)][string]$WorkerHome)
    $parent = Split-Path -Parent $WorkerHome
    if (-not $parent) { return $null }
    Join-Path $parent '_git-accept-claims.json'
}

function Get-BobGitAcceptClaimKey {
    param([string]$Repo, [string]$Task, [string]$Id)
    return ($Repo + '|' + $Task.ToUpperInvariant() + '|' + $Id)
}

function Test-BobGitAcceptLocalClaim {
    param(
        [Parameter(Mandatory)][string]$WorkerHome,
        [string]$Repo,
        [string]$Task,
        [string]$Id
    )
    $p = Get-BobGitAcceptClaimPath $WorkerHome
    if (-not $p -or -not (Test-Path -LiteralPath $p)) { return $false }
    try {
        $j = Read-JsonFile $p
    }
    catch { return $false }
    if (-not $j) { return $false }
    $key = Get-BobGitAcceptClaimKey -Repo $Repo -Task $Task -Id $Id
    foreach ($prop in @($j.PSObject.Properties)) {
        if ($prop.Name -eq $key) { return $true }
    }
    return $false
}

function Set-BobGitAcceptLocalClaim {
    param(
        [Parameter(Mandatory)][string]$WorkerHome,
        [string]$Repo,
        [string]$Task,
        [string]$Id,
        [string]$WorkerNick
    )
    $p = Get-BobGitAcceptClaimPath $WorkerHome
    if (-not $p) { return }
    $map = [ordered]@{}
    if (Test-Path -LiteralPath $p) {
        try {
            $j = Read-JsonFile $p
            if ($j) {
                foreach ($prop in @($j.PSObject.Properties)) { $map[$prop.Name] = [string]$prop.Value }
            }
        }
        catch { }
    }
    $key = Get-BobGitAcceptClaimKey -Repo $Repo -Task $Task -Id $Id
    $map[$key] = $(if ($WorkerNick) { $WorkerNick } else { 'w' })
    $dir = Split-Path -Parent $p
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Write-JsonFile $p ([pscustomobject]$map)
}

function Remove-BobGitAcceptLocalClaim {
    param(
        [Parameter(Mandatory)][string]$WorkerHome,
        [string]$Repo,
        [string]$Task,
        [string]$Id
    )
    $p = Get-BobGitAcceptClaimPath $WorkerHome
    if (-not $p -or -not (Test-Path -LiteralPath $p)) { return }
    $key = Get-BobGitAcceptClaimKey -Repo $Repo -Task $Task -Id $Id
    $map = [ordered]@{}
    try {
        $j = Read-JsonFile $p
        if ($j) {
            foreach ($prop in @($j.PSObject.Properties)) {
                if ($prop.Name -ne $key) { $map[$prop.Name] = [string]$prop.Value }
            }
        }
    }
    catch { return }
    Write-JsonFile $p ([pscustomobject]$map)
}

function Test-BobGitAcceptAlreadySpoken {
    param(
        [string]$LogText,
        [string]$Repo,
        [string]$Task,
        [string]$Id
    )
    if (-not $LogText) { return $false }
    $re = '(?i)(?:^|[\s:])!ACCEPT\s+' + [regex]::Escape($Repo) + '\s+' + [regex]::Escape($Task) + '\s+' + [regex]::Escape($Id) + '\b'
    return [bool]($LogText -match $re)
}

function Get-BobGitAcceptBusyPath {
    param([Parameter(Mandatory)][string]$WorkerHome)
    Join-Path $WorkerHome 'git-accept-busy.json'
}

function Test-BobGitAcceptWorkerBusy {
    <#
      True while the accepted fleet job is still inbox or running.
      A missing job drops the local busy stamp (activity clear). Does not touch the chair queue.
    #>
    param([Parameter(Mandatory)][string]$WorkerHome)
    $p = Get-BobGitAcceptBusyPath $WorkerHome
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    $jobId = $null
    try {
        $j = Read-JsonFile $p
        if ($j -and $j.jobId) { $jobId = [string]$j.jobId }
    }
    catch { return $true }
    if (-not $jobId) {
        Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        return $false
    }
    $live = $false
    try {
        foreach ($row in @(Get-BobBuilds)) {
            if (-not $row) { continue }
            if ([string]$row.id -ne $jobId) { continue }
            $lane = [string]$row.lane
            if ($lane -eq 'inbox' -or $lane -eq 'running') { $live = $true; break }
        }
    }
    catch { return $true }
    if ($live) { return $true }
    Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    return $false
}

function Write-BobGitAcceptBusy {
    param(
        [Parameter(Mandatory)][string]$WorkerHome,
        [Parameter(Mandatory)][string]$JobId,
        $Claim
    )
    $doc = [ordered]@{
        jobId = $JobId
        repo  = [string]$Claim.repo
        task  = [string]$Claim.task
        id    = [string]$Claim.id
        at    = [datetime]::UtcNow.ToString('o')
    }
    Write-JsonFile (Get-BobGitAcceptBusyPath $WorkerHome) ([pscustomobject]$doc)
}

function Start-BobGitAcceptWork {
    <#
      Enqueue on this machine via Start-BobBuild. Copilot stays off.
      Cursor Models then grok-build (Get-BobFuelOrder inside the picker).
      The inbox job is the activity row; Write-BobIrcStatus drops it when the job leaves inbox/running.
    #>
    param(
        [Parameter(Mandatory)]$Claim,
        [string]$MachineId,
        [string]$WorkerHome
    )
    if (-not $MachineId) {
        return [pscustomobject]@{ ok = $false; wait = $true; jobId = $null; reason = 'machine_required' }
    }
    $task = ([string]$Claim.task).ToUpperInvariant()
    $kind = 'build'
    if ($task -eq 'MRB') { $kind = 'mrb' }
    $repo = [string]$Claim.repo
    $id = [string]$Claim.id
    $url = 'https://github.com/' + $repo
    $goal = "Shop !ACCEPT $repo $task $id. Work item $url . Finish with the existing git job. Do not use Copilot. Do not use Other Models. Do not merge."
    if ($task -eq 'MRB') {
        $goal = "Shop !ACCEPT $repo MRB $id. Hostile MRB of $url/pull/$id . Follow skill bob-hostile-mrb. Do not use Copilot. Do not use Other Models."
    }
    $buildArgs = @{
        Task    = 'git'
        Machine = $MachineId
        Kind    = $kind
        Repo    = $url
        Goal    = $goal
        From    = 'git-accept'
    }
    if ($task -eq 'MRB') { $buildArgs['PrUrl'] = ($url + '/pull/' + $id) }
    return (Start-BobBuild @buildArgs)
}

function Invoke-BobWorkerShopTick {
    <#
      One w-* home. Idle >= BoredAfterSeconds (default 120) appends
      PRIVMSG <shop> :!BORED once per idle stretch.
      After that byte offset, a chair OFFER or claimable GIT on the shop
      (never #bobiverse) starts work, then appends !ACCEPT. A failed start
      does not ACCEPT. FILE v1 ACCEPT is not a git claim.
    #>
    param(
        [Parameter(Mandatory)][string]$WorkerHome,
        [Parameter(Mandatory)][string]$ShopChannel,
        [bool]$IsBusy = $false,
        [datetime]$Now = ([datetime]::UtcNow),
        [string[]]$ChairNicks,
        [string]$WorkerNick,
        [string]$MachineId,
        [scriptblock]$StartWork,
        [int]$BoredAfterSeconds = 120,
        [switch]$SkipActivity
    )
    if (-not $ChairNicks -or @($ChairNicks).Count -eq 0) { $ChairNicks = @(Get-BobGitChairNicks) }
    $nowUtc = $Now.ToUniversalTime()
    $result = [pscustomobject]@{
        bored    = $false
        accepted = $false
        claim    = $null
        start    = $null
    }
    if ($IsBusy) {
        Write-BobWorkerBoredState -WorkerHome $WorkerHome -BoredSent $false -BoredAtBytes 0
        return $result
    }
    $state = Read-BobWorkerBoredState $WorkerHome
    if (-not $state.idleSince) {
        Write-BobWorkerBoredState -WorkerHome $WorkerHome -IdleSince $nowUtc -BoredSent $false -BoredAtBytes 0
        return $result
    }
    $snap = Get-BobWorkerIrcLogSnapshot $WorkerHome
    if (-not $state.boredSent) {
        $elapsed = ($nowUtc - $state.idleSince.ToUniversalTime()).TotalSeconds
        if ($elapsed -lt $BoredAfterSeconds) { return $result }
        $line = 'PRIVMSG ' + $ShopChannel.Trim() + ' :!BORED'
        Add-BobWorkerShopOutboxLine -WorkerHome $WorkerHome -Line $line
        Write-BobWorkerBoredState -WorkerHome $WorkerHome -IdleSince $state.idleSince -BoredSent $true -BoredAtBytes $snap.length
        $result.bored = $true
        return $result
    }
    $suffix = ''
    if ($state.boredAtBytes -le 0) { $suffix = [string]$snap.text }
    elseif ($state.boredAtBytes -lt $snap.length) {
        $raw = [IO.File]::ReadAllBytes((Join-Path $WorkerHome 'irc.log'))
        $suffix = [Text.Encoding]::UTF8.GetString($raw, $state.boredAtBytes, ($raw.Length - $state.boredAtBytes))
    }
    $claim = $null
    foreach ($row in @(Get-BobShopPrivmsgLines $suffix)) {
        if (-not (Test-BobGitChairNick -Nick $row.nick -ChairNicks $ChairNicks)) { continue }
        if (-not (Test-BobShopOfferTarget -Target $row.target -ShopChannel $ShopChannel -WorkerNick $WorkerNick)) { continue }
        $parsed = ConvertFrom-BobShopWorkLine $row.body
        if (-not $parsed) { continue }
        $claim = $parsed
        break
    }
    if (-not $claim) { return $result }
    if (Test-BobGitAcceptAlreadySpoken -LogText $snap.text -Repo $claim.repo -Task $claim.task -Id $claim.id) {
        Write-BobWorkerBoredState -WorkerHome $WorkerHome -IdleSince $nowUtc -BoredSent $false -BoredAtBytes $snap.length
        return $result
    }
    if (Test-BobGitAcceptLocalClaim -WorkerHome $WorkerHome -Repo $claim.repo -Task $claim.task -Id $claim.id) {
        Write-BobWorkerBoredState -WorkerHome $WorkerHome -IdleSince $nowUtc -BoredSent $false -BoredAtBytes $snap.length
        return $result
    }
    Set-BobGitAcceptLocalClaim -WorkerHome $WorkerHome -Repo $claim.repo -Task $claim.task -Id $claim.id -WorkerNick $WorkerNick
    $started = $null
    if ($StartWork) {
        $started = & $StartWork $claim
    }
    else {
        $started = Start-BobGitAcceptWork -Claim $claim -MachineId $MachineId -WorkerHome $WorkerHome
    }
    $result.start = $started
    $result.claim = $claim
    $ok = $false
    if ($started -and $started.ok -and -not $started.wait) { $ok = $true }
    if (-not $ok) {
        Remove-BobGitAcceptLocalClaim -WorkerHome $WorkerHome -Repo $claim.repo -Task $claim.task -Id $claim.id
        Write-BobWorkerBoredState -WorkerHome $WorkerHome -IdleSince $nowUtc -BoredSent $false -BoredAtBytes $snap.length
        return $result
    }
    $accept = 'PRIVMSG ' + $ShopChannel.Trim() + ' :!ACCEPT ' + $claim.repo + ' ' + $claim.task + ' ' + $claim.id
    Add-BobWorkerShopOutboxLine -WorkerHome $WorkerHome -Line $accept
    if ($started.jobId) {
        Write-BobGitAcceptBusy -WorkerHome $WorkerHome -JobId ([string]$started.jobId) -Claim $claim
    }
    if (-not $SkipActivity) {
        try { Write-BobIrcStatus | Out-Null } catch { }
    }
    Write-BobWorkerBoredState -WorkerHome $WorkerHome -BoredSent $false -BoredAtBytes $snap.length
    $result.accepted = $true
    return $result
}

function Import-BobWorkerGitShop {
    <#
      Watch-Bobiverse calls this. Local w-* homes only. Read-only toward the chair queue.
    #>
    param(
        [string]$MachineId,
        [datetime]$Now = ([datetime]::UtcNow),
        [scriptblock]$StartWork,
        [int]$BoredAfterSeconds = 120,
        [switch]$SkipActivity
    )
    if (-not $MachineId) {
        try { $MachineId = Get-ThisMachineId } catch { }
    }
    if (-not $MachineId) { return @() }
    $ircHome = $null
    try { $ircHome = Get-BobIrcHome } catch { }
    if (-not $ircHome) { return @() }
    $root = Join-Path $ircHome (Join-Path 'workers' $MachineId)
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    $shop = $null
    try { $shop = Get-BobIrcShopChannel -MachineId $MachineId } catch { }
    if (-not $shop) { return @() }
    $chairs = @(Get-BobGitChairNicks)
    $done = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        if ($dir.Name -notmatch '^\d+$') { continue }
        $pid = [int]$dir.Name
        if ($pid -le 0) { continue }
        $nick = $null
        try { $nick = Get-BobWorkerIrcNick -MachineId $MachineId -WorkerPid $pid } catch { $nick = $null }
        $busy = Test-BobGitAcceptWorkerBusy -WorkerHome $dir.FullName
        try {
            $tick = Invoke-BobWorkerShopTick -WorkerHome $dir.FullName -ShopChannel $shop -IsBusy:$busy -Now $Now `
                -ChairNicks $chairs -WorkerNick $nick -MachineId $MachineId -StartWork $StartWork `
                -BoredAfterSeconds $BoredAfterSeconds -SkipActivity:$SkipActivity
            if ($tick -and ($tick.bored -or $tick.accepted)) { $done += $tick }
        }
        catch { }
    }
    return $done
}
