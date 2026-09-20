function Get-BobiverseConfigPath {
    $envp = [string]$env:BOB_IRC_CONFIG
    if ($envp -and $envp.Trim() -and (Test-Path $envp.Trim())) { return $envp.Trim() }
    Join-Path (Get-ModuleRoot) 'config\bobiverse.json'
}

function Get-BobiverseConfig {
    $p = Get-BobiverseConfigPath
    if (-not (Test-Path $p)) { return $null }
    return (Read-JsonFile $p)
}

function Get-BobIrcHome {
    if ($env:BOB_IRC_HOME -and $env:BOB_IRC_HOME.Trim()) {
        return [IO.Path]::GetFullPath($env:BOB_IRC_HOME.Trim())
    }
    if ($env:AGENTIC_IRC_HOME -and $env:AGENTIC_IRC_HOME.Trim()) {
        return [IO.Path]::GetFullPath($env:AGENTIC_IRC_HOME.Trim())
    }
    return [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.agentic-irc-bobiverse'))
}

function Get-BobIrcNick {
    param($Config, [string]$MachineId)
    if ($env:BOB_IRC_NICK -and $env:BOB_IRC_NICK.Trim()) { return $env:BOB_IRC_NICK.Trim() }
    if ($Config -and $Config.nicks) {
        $n = $Config.nicks.$MachineId
        if ($n) { return [string]$n }
    }
    if ($MachineId) { return ('bob-' + $MachineId) }
    return $null
}

function ConvertTo-BobIrcPoint {
    param($Doc)
    $mid = [string]$Doc.id
    $w = '-'
    if ($null -ne $Doc.weekly -and [string]$Doc.weekly -ne '') { $w = [string][int]$Doc.weekly }
    $jobParts = @()
    foreach ($j in @($Doc.jobs)) {
        $repo = ([string]$j.repo).Replace(' ', '')
        $st = ([string]$j.state).Replace(' ', '')
        if (-not $repo -or $repo -eq '?' -or (Test-BobTrayLooksLikeSha $repo)) { continue }
        if ($repo -and $st) { $jobParts += ($repo + ':' + $st) }
    }
    $jobs = '-'
    if ($jobParts.Count -gt 0) { $jobs = ($jobParts -join ',') }
    $seen = [string]$Doc.lastSeen
    if (-not $seen) { $seen = '-' }
    $run = 0
    $q = 0
    if ($Doc.running) { $run = [int]$Doc.running }
    if ($Doc.queued) { $q = [int]$Doc.queued }
    $line = "BOB v1 id=$mid weekly=$w running=$run queued=$q lastSeen=$seen jobs=$jobs"
    if ($line.Length -gt 350) { $line = $line.Substring(0, 349) + '-' }
    return $line
}

function ConvertFrom-BobIrcPoint {
    param([string]$Text)
    if (-not $Text -or $Text -notmatch '^BOB v1 ') { return $null }
    $body = $Text.Substring(7).Trim()
    $kv = @{}
    foreach ($tok in $body.Split(' ')) {
        if ($tok -notmatch '=') { return $null }
        $k, $v = $tok.Split('=', 2)
        $kv[$k] = $v
    }
    $mid = [string]$kv['id']
    if ($mid -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { return $null }
    $jobs = @()
    $jr = [string]$kv['jobs']
    if ($jr -and $jr -ne '-') {
        foreach ($part in $jr.Split(',')) {
            if ($part -notmatch ':') { continue }
            $repo, $st = $part.Split(':', 2)
            if ($repo -and $st) {
                $jobs += ,[pscustomobject]@{ repo = $repo; state = $st; machine = $mid; id = ($mid + '-' + $jobs.Count) }
            }
        }
    }
    $weekly = $null
    if ($kv.ContainsKey('weekly') -and [string]$kv['weekly'] -ne '-') {
        try { $weekly = [int]$kv['weekly'] } catch { $weekly = $null }
    }
    $run = 0
    $q = 0
    try { $run = [int]$kv['running'] } catch { }
    try { $q = [int]$kv['queued'] } catch { }
    return [pscustomobject]@{
        ok       = $true
        id       = $mid
        weekly   = $weekly
        running  = $run
        queued   = $q
        lastSeen = $(if ($kv['lastSeen'] -and $kv['lastSeen'] -ne '-') { [string]$kv['lastSeen'] } else { $null })
        jobs     = $jobs
        source   = 'irc'
    }
}

function Read-BobIrcPeer {
    param([Parameter(Mandatory)][string]$Id)
    $home = Get-BobIrcHome
    $p = Join-Path $home (Join-Path 'bob-peers' ($Id + '.json'))
    if (-not (Test-Path $p)) { return $null }
    $doc = Read-JsonFile $p
    if (-not $doc -or -not $doc.id) { return $null }
    $jobs = @()
    foreach ($j in @($doc.jobs)) { $jobs += ,$j }
    return [pscustomobject]@{
        ok       = $true
        id       = [string]$doc.id
        lastSeen = $(if ($doc.lastSeen) { [string]$doc.lastSeen } else { $null })
        hostname = $null
        jobs     = $jobs
        weekly   = $doc.weekly
        source   = 'irc'
    }
}

function Write-BobIrcStatus {
    $id = Get-ThisMachineId
    if (-not $id) { return }
    $cfg = Get-BobiverseConfig
    if (-not $cfg) { return }
    $home = Get-BobIrcHome
    $running = @(Get-BobPeerLaneJobs -BridgeRoot (Get-BridgeRoot) -MachineId $id -Lane running -StampRepo)
    if ($null -eq $running) { $running = @() }
    $inbox = @(Get-BobPeerLaneJobs -BridgeRoot (Get-BridgeRoot) -MachineId $id -Lane inbox -StampRepo)
    if ($null -eq $inbox) { $inbox = @() }
    $jobs = @()
    foreach ($j in @($running)) {
        $jobs += ,[pscustomobject]@{ repo = (Get-BobJobRepoStamp $j); state = 'running' }
    }
    foreach ($j in @($inbox)) {
        $jobs += ,[pscustomobject]@{ repo = (Get-BobJobRepoStamp $j); state = 'queued' }
    }
    $week = $null
    try {
        $w = Get-BobWeeklyRemaining
        if ($w -and $null -ne $w.remaining_pct) { $week = [int]$w.remaining_pct }
    }
    catch { }
    $seen = [DateTime]::UtcNow.ToString('o')
    $doc = [pscustomobject]@{
        ok       = $true
        id       = $id
        weekly   = $week
        running  = @($running).Count
        queued   = @($inbox).Count
        lastSeen = $seen
        jobs     = $jobs
        source   = 'irc'
    }
    $dir = Join-Path $home 'bob-peers'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Write-JsonFile (Join-Path $dir ($id + '.json')) $doc
    $mid = [string]$cfg.mootId
    if (-not $mid) { return }
    $point = ConvertTo-BobIrcPoint $doc
    $line = "MOOT v1 POINT $mid :$point"
    $outbox = Join-Path $home 'outbox.txt'
    Add-Content -Path $outbox -Value $line -Encoding utf8
}
