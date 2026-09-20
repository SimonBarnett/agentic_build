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

function Get-BobiverseMachineIds {
    $cfg = Get-BobiverseConfig
    $ids = @()
    if ($cfg -and $cfg.nicks) {
        foreach ($p in @($cfg.nicks.PSObject.Properties)) {
            $id = [string]$p.Name
            if ($id) { $ids += $id }
        }
    }
    return @($ids)
}

function Resolve-BobiverseMachineId {
    param([string]$Raw)
    if (-not $Raw) { return $null }
    $id = [string]$Raw.Trim()
    if (-not $id) { return $null }
    $cfg = Get-BobiverseConfig
    if (-not $cfg -or -not $cfg.nicks) { return $id }
    $props = @($cfg.nicks.PSObject.Properties)
    if ($props.Count -eq 0) { return $id }
    foreach ($p in $props) {
        if ([string]$p.Name -eq $id) { return [string]$p.Name }
    }
    foreach ($p in $props) {
        $nk = [string]$p.Value
        if ($nk -and $nk.ToLowerInvariant() -eq $id.ToLowerInvariant()) {
            return [string]$p.Name
        }
    }
    return $null
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

function Get-BobMootRoster {
    $cfg = Get-BobiverseConfig
    $nicks = @()
    $nickToId = @{}
    $idToNick = @{}
    if ($cfg -and $cfg.nicks) {
        foreach ($p in @($cfg.nicks.PSObject.Properties)) {
            $id = [string]$p.Name
            $nk = [string]$p.Value
            if (-not $id -or -not $nk) { continue }
            $idToNick[$id] = $nk
            $nickToId[$nk.ToLowerInvariant()] = $id
        }
    }
    $mid = $null
    if ($cfg) { $mid = [string]$cfg.mootId }
    $home = Get-BobIrcHome
    $roster = @()
    if ($mid -and $home) {
        $stPath = Join-Path $home (Join-Path 'moot' ($mid + '.json'))
        $st = Read-JsonFile $stPath
        if ($st -and $st.roster) {
            foreach ($n in @($st.roster)) {
                $s = [string]$n
                if ($s) { $roster += $s.ToLowerInvariant() }
            }
        }
        if ($st -and $st.chair) {
            $c = [string]$st.chair
            if ($c) {
                $cl = $c.ToLowerInvariant()
                if ($roster -notcontains $cl) { $roster += $cl }
            }
        }
    }
    return [pscustomobject]@{
        nicks     = $roster
        nickToId  = $nickToId
        idToNick  = $idToNick
        mootId    = $mid
    }
}

function Test-BobMachineInMoot {
    param([string]$MachineId, $Roster)
    if (-not $MachineId) { return $false }
    if (-not $Roster) { return $false }
    $self = Get-ThisMachineId
    if ($self -and $MachineId -eq $self -and @($Roster.nicks).Count -gt 0) { return $true }
    if ($Roster.idToNick.ContainsKey($MachineId)) {
        $nk = [string]$Roster.idToNick[$MachineId]
        if ($nk -and ($Roster.nicks -contains $nk.ToLowerInvariant())) { return $true }
        # Registered bobiverse seat (nicks key). Prefer irc-fallback over
        # not-in-moot even when the live MODE2 roster file is empty/stale.
        return $true
    }
    return $false
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
    $reset = '-'
    if ($Doc.period_end) {
        try {
            $rd = [datetime]::Parse([string]$Doc.period_end, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            $reset = $rd.ToUniversalTime().ToString('yyyy-MM-dd')
        } catch { $reset = '-' }
    }
    $line = "BOB v1 id=$mid weekly=$w reset=$reset running=$run queued=$q lastSeen=$seen jobs=$jobs"
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
    $periodEnd = $null
    if ($kv.ContainsKey('reset') -and [string]$kv['reset'] -ne '-') {
        $periodEnd = [string]$kv['reset']
    }
    return [pscustomobject]@{
        ok         = $true
        id         = $mid
        weekly     = $weekly
        period_end = $periodEnd
        running    = $run
        queued     = $q
        lastSeen   = $(if ($kv['lastSeen'] -and $kv['lastSeen'] -ne '-') { [string]$kv['lastSeen'] } else { $null })
        jobs       = $jobs
        source     = 'irc'
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
        ok         = $true
        id         = [string]$doc.id
        lastSeen   = $(if ($doc.lastSeen) { [string]$doc.lastSeen } else { $null })
        hostname   = $null
        jobs       = $jobs
        weekly     = $doc.weekly
        period_end = $(if ($doc.period_end) { [string]$doc.period_end } else { $null })
        source     = 'irc'
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
    $liveN = 0
    foreach ($g in @(Get-BobLiveGrokAgents)) {
        $liveN++
        $repo = 'grok.exe'
        if ($g.cwd) {
            $slug = Get-GitHubSlugFromCwd $g.cwd
            if ($slug -and $slug -ne '?' -and $slug -ne $env:USERNAME) { $repo = $slug }
        }
        $jobs += ,[pscustomobject]@{ repo = $repo; state = 'running' }
    }
    $week = $null
    $periodEnd = $null
    try {
        $w = Get-BobWeeklyRemaining
        if ($w -and $null -ne $w.remaining_pct) { $week = [int]$w.remaining_pct }
        if ($w -and $w.period_end) { $periodEnd = [string]$w.period_end }
    }
    catch { }
    $seen = [DateTime]::UtcNow.ToString('o')
    $doc = [pscustomobject]@{
        ok         = $true
        id         = $id
        weekly     = $week
        period_end = $periodEnd
        running    = @($running).Count + $liveN
        queued     = @($inbox).Count
        lastSeen   = $seen
        jobs       = $jobs
        source     = 'irc'
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

function Import-BobIrcPeerTranscript {
    $cfg = Get-BobiverseConfig
    if (-not $cfg) { return @() }
    $home = Get-BobIrcHome
    $mid = [string]$cfg.mootId
    if (-not $mid) { return @() }
    $tp = Join-Path $home (Join-Path 'moot' ($mid + '.txt'))
    if (-not (Test-Path $tp)) { return @() }
    # Last POINT per machine wins (moot transcript is append-only).
    $latest = @{}
    foreach ($raw in @(Get-Content $tp -ErrorAction SilentlyContinue)) {
        if ($raw -notmatch 'POINT' -or $raw -notmatch 'BOB v1 ') { continue }
        $idx = $raw.IndexOf('BOB v1 ')
        if ($idx -lt 0) { continue }
        $doc = ConvertFrom-BobIrcPoint $raw.Substring($idx)
        if (-not $doc) { continue }
        $resolved = Resolve-BobiverseMachineId ([string]$doc.id)
        if (-not $resolved) { continue }
        $doc | Add-Member -NotePropertyName id -NotePropertyValue $resolved -Force
        $latest[$resolved] = $doc
    }
    $updated = @()
    $dir = Join-Path $home 'bob-peers'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    foreach ($resolved in @($latest.Keys)) {
        $doc = $latest[$resolved]
        $peerPath = Join-Path $dir ($resolved + '.json')
        # Keep prior period_end when the latest POINT still lacks reset=.
        if (-not $doc.period_end -and (Test-Path $peerPath)) {
            try {
                $prev = Read-JsonFile $peerPath
                if ($prev -and $prev.period_end) {
                    $doc | Add-Member -NotePropertyName period_end -NotePropertyValue ([string]$prev.period_end) -Force
                }
            } catch { }
        }
        Write-JsonFile $peerPath $doc
        $updated += $resolved
    }
    return $updated
}
