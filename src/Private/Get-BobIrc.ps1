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



function Get-BobCursorAccountCachePath {
    try { return (Join-Path (Get-BridgeRoot) 'cursor-account.json') } catch { return $null }
}

function Save-BobCursorAccountCache {
    param([string]$Label, [string]$PeriodEnd)
    if (-not $Label -or $Label -eq 'empty') { return }
    $p = Get-BobCursorAccountCachePath
    if (-not $p) { return }
    $doc = [pscustomobject]@{
        label      = [string]$Label
        period_end = $(if ($PeriodEnd) { [string]$PeriodEnd } else { $null })
        updated_at = [DateTime]::UtcNow.ToString('o')
    }
    try { Write-JsonFile $p $doc } catch { }
}

function Read-BobCursorAccountCache {
    $p = Get-BobCursorAccountCachePath
    if (-not $p -or -not (Test-Path $p)) { return $null }
    try { return Read-JsonFile $p } catch { return $null }
}

function Get-BobCursorPoolsCachePath {
    try { return (Join-Path (Get-BridgeRoot) 'cursor-pools.json') } catch { return $null }
}

function Read-BobCursorPoolsCache {
    $p = Get-BobCursorPoolsCachePath
    if (-not $p -or -not (Test-Path $p)) {
        return [pscustomobject]@{ by_seat = @{} }
    }
    try {
        $j = Read-JsonFile $p
        $by = @{}
        if ($j.by_seat) {
            foreach ($prop in $j.by_seat.PSObject.Properties) {
                $by[$prop.Name] = $prop.Value
            }
        }
        return [pscustomobject]@{ by_seat = $by }
    }
    catch {
        return [pscustomobject]@{ by_seat = @{} }
    }
}

function Parse-BobCursorPoolLabel {
    param([string]$Label)
    if (-not $Label -or $Label -eq 'empty') { return $null }
    $l = [string]$Label.Trim()
    if ($l -match '^(\d+)%$') {
        return [pscustomobject]@{
            remaining_pct = [int]$Matches[1]
            label         = $l
            overage       = $null
        }
    }
    if (($l -match '^-') -or ($l.IndexOf([char]0x00A3) -ge 0)) {
        return [pscustomobject]@{
            remaining_pct = $null
            label         = $l
            overage       = $l
        }
    }
    return [pscustomobject]@{
        remaining_pct = $null
        label         = $l
        overage       = $null
    }
}

function Save-BobCursorPoolForSeat {
    param(
        [Parameter(Mandatory)][string]$SeatId,
        $RemainingPct,
        [string]$PeriodEnd,
        [string]$Label
    )
    $sid = [string]$SeatId
    if (-not $sid) { return }
    $p = Get-BobCursorPoolsCachePath
    if (-not $p) { return }
    $cache = Read-BobCursorPoolsCache
    $entry = $null
    if ($cache.by_seat.ContainsKey($sid)) { $entry = $cache.by_seat[$sid] }
    if (-not $entry) { $entry = [pscustomobject]@{} }
    if ($null -ne $RemainingPct -and [string]$RemainingPct -ne '') {
        $entry | Add-Member -NotePropertyName remaining_pct -NotePropertyValue ([int]$RemainingPct) -Force
    }
    if ($Label) {
        $parsed = Parse-BobCursorPoolLabel $Label
        if ($parsed) {
            if ($null -ne $parsed.remaining_pct) {
                $entry | Add-Member -NotePropertyName remaining_pct -NotePropertyValue ([int]$parsed.remaining_pct) -Force
            }
            $entry | Add-Member -NotePropertyName label -NotePropertyValue ([string]$parsed.label) -Force
            if ($parsed.overage) {
                $entry | Add-Member -NotePropertyName overage_label -NotePropertyValue ([string]$parsed.overage) -Force
            }
        }
    }
    if ($PeriodEnd) {
        $entry | Add-Member -NotePropertyName period_end -NotePropertyValue ([string]$PeriodEnd) -Force
    }
    $entry | Add-Member -NotePropertyName updated_at -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    $cache.by_seat[$sid] = $entry
    $out = [pscustomobject]@{ by_seat = $cache.by_seat }
    try { Write-JsonFile $p $out } catch { }
}

function Read-BobReportDigest {
    $home = $null
    try { $home = Get-BobIrcHome } catch { }
    if (-not $home) { return $null }
    foreach ($name in @('_report-digest.json', 'digest.json')) {
        $p = Join-Path $home (Join-Path 'bob-peers' $name)
        if (-not (Test-Path $p)) { continue }
        try {
            $j = Read-JsonFile $p
            if ($j) { return $j }
        }
        catch { }
    }
    return $null
}

function Get-BobSeatPeriodEndCachePath {
    try { return (Join-Path (Get-BridgeRoot) 'seat-period-end.json') } catch { return $null }
}

function Read-BobSeatPeriodEndCache {
    $p = Get-BobSeatPeriodEndCachePath
    if (-not $p -or -not (Test-Path $p)) {
        return [pscustomobject]@{ by_machine = @{}; by_seat = @{}; weekly_by_machine = @{}; weekly_by_seat = @{} }
    }
    try {
        $j = Read-JsonFile $p
        if (-not $j) { return [pscustomobject]@{ by_machine = @{}; by_seat = @{}; weekly_by_machine = @{}; weekly_by_seat = @{} } }
        $bm = @{}; $bs = @{}; $wm = @{}; $ws = @{}
        if ($j.by_machine) {
            foreach ($p2 in $j.by_machine.PSObject.Properties) {
                # Back-compat: string value = period_end only
                if ($p2.Value -is [string] -or $p2.Value -is [datetime]) {
                    $bm[$p2.Name] = [string]$p2.Value
                }
                elseif ($p2.Value) {
                    if ($p2.Value.period_end) { $bm[$p2.Name] = [string]$p2.Value.period_end }
                    if ($null -ne $p2.Value.weekly) { $wm[$p2.Name] = [int]$p2.Value.weekly }
                }
            }
        }
        if ($j.by_seat) {
            foreach ($p2 in $j.by_seat.PSObject.Properties) {
                if ($p2.Value -is [string] -or $p2.Value -is [datetime]) {
                    $bs[$p2.Name] = [string]$p2.Value
                }
                elseif ($p2.Value) {
                    if ($p2.Value.period_end) { $bs[$p2.Name] = [string]$p2.Value.period_end }
                    if ($null -ne $p2.Value.weekly) { $ws[$p2.Name] = [int]$p2.Value.weekly }
                }
            }
        }
        if ($j.weekly_by_machine) {
            foreach ($p2 in $j.weekly_by_machine.PSObject.Properties) {
                try { $wm[$p2.Name] = [int]$p2.Value } catch { }
            }
        }
        if ($j.weekly_by_seat) {
            foreach ($p2 in $j.weekly_by_seat.PSObject.Properties) {
                try { $ws[$p2.Name] = [int]$p2.Value } catch { }
            }
        }
        return [pscustomobject]@{ by_machine = $bm; by_seat = $bs; weekly_by_machine = $wm; weekly_by_seat = $ws }
    }
    catch {
        return [pscustomobject]@{ by_machine = @{}; by_seat = @{}; weekly_by_machine = @{}; weekly_by_seat = @{} }
    }
}

function Save-BobSeatPeriodEnd {
    param(
        [string]$MachineId,
        [string]$PeriodEnd,
        [string]$SeatId,
        $Weekly
    )
    $p = Get-BobSeatPeriodEndCachePath
    if (-not $p) { return }
    $cache = Read-BobSeatPeriodEndCache
    if ($MachineId -and $PeriodEnd) { $cache.by_machine[$MachineId] = [string]$PeriodEnd }
    if ($MachineId -and $null -ne $Weekly -and [string]$Weekly -ne '') {
        try { $cache.weekly_by_machine[$MachineId] = [int]$Weekly } catch { }
    }
    if (-not $SeatId -and $MachineId) {
        try {
            $s = Get-BobSeatForMachine -MachineId $MachineId
            if ($s) { $SeatId = [string]$s.id }
        } catch { }
    }
    if ($SeatId -and $PeriodEnd) { $cache.by_seat[$SeatId] = [string]$PeriodEnd }
    if ($SeatId -and $null -ne $Weekly -and [string]$Weekly -ne '') {
        try { $cache.weekly_by_seat[$SeatId] = [int]$Weekly } catch { }
    }
    if (-not $PeriodEnd -and $null -eq $Weekly) { return }
    $doc = [pscustomobject]@{
        by_machine         = [pscustomobject]$cache.by_machine
        by_seat            = [pscustomobject]$cache.by_seat
        weekly_by_machine  = [pscustomobject]$cache.weekly_by_machine
        weekly_by_seat     = [pscustomobject]$cache.weekly_by_seat
        updated_at         = [DateTime]::UtcNow.ToString('o')
    }
    try { Write-JsonFile $p $doc } catch { }
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
    $cur = '-'
    if ($Doc.cursor_label -and [string]$Doc.cursor_label -ne '' -and [string]$Doc.cursor_label -ne 'empty') {
        $cur = ([string]$Doc.cursor_label).Replace(' ', '')
    }
    $crst = '-'
    if ($Doc.cursor_period_end) {
        try {
            $cd = [datetime]::Parse([string]$Doc.cursor_period_end, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            $crst = $cd.ToUniversalTime().ToString('yyyy-MM-dd')
        } catch { $crst = '-' }
    }
    $line = "BOB v1 id=$mid weekly=$w reset=$reset cur=$cur crst=$crst running=$run queued=$q lastSeen=$seen jobs=$jobs"
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
            if ((Test-BobIrcRepoOk $repo) -and $st) {
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
    $cursorLabel = $null
    if ($kv.ContainsKey('cur') -and [string]$kv['cur'] -ne '-') {
        $cursorLabel = [string]$kv['cur']
    }
    $cursorPeriodEnd = $null
    if ($kv.ContainsKey('crst') -and [string]$kv['crst'] -ne '-') {
        $cursorPeriodEnd = [string]$kv['crst']
    }
    return [pscustomobject]@{
        ok                = $true
        id                = $mid
        weekly            = $weekly
        period_end        = $periodEnd
        cursor_label      = $cursorLabel
        cursor_period_end = $cursorPeriodEnd
        running           = $run
        queued            = $q
        lastSeen          = $(if ($kv['lastSeen'] -and $kv['lastSeen'] -ne '-') { [string]$kv['lastSeen'] } else { $null })
        jobs              = $jobs
        source            = 'irc'
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
        ok                = $true
        id                = [string]$doc.id
        lastSeen          = $(if ($doc.lastSeen) { [string]$doc.lastSeen } else { $null })
        hostname          = $null
        jobs              = $jobs
        weekly            = $doc.weekly
        period_end        = $(if ($doc.period_end) { [string]$doc.period_end } else { $null })
        cursor_label      = $(if ($doc.cursor_label) { [string]$doc.cursor_label } else { $null })
        cursor_period_end = $(if ($doc.cursor_period_end) { [string]$doc.cursor_period_end } else { $null })
        repo              = $(if ($doc.repo) { [string]$doc.repo } else { $null })
        kind              = $(if ($doc.kind) { [string]$doc.kind } else { $null })
        model             = $(if ($doc.model) { [string]$doc.model } else { $null })
        sha               = $(if ($doc.sha) { [string]$doc.sha } else { $null })
        source            = $(if ($doc.source) { [string]$doc.source } else { 'irc' })
    }
}

function Get-BobIrcPointDedupeKey {
    param([string]$Line)
    if (-not $Line) { return '' }
    # lastSeen changes every Watch tick; ignore it so identical status does not pile up.
    return ([string]$Line).Trim() -replace '\s+lastSeen=\S+', ''
}

function Test-BobIrcOutboxDuplicatePoint {
    param([string]$Path, [string]$Line)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $false }
    $last = $null
    try { $last = Get-Content -LiteralPath $Path -Tail 1 -ErrorAction SilentlyContinue } catch { return $false }
    if (-not $last) { return $false }
    return ((Get-BobIrcPointDedupeKey $last) -eq (Get-BobIrcPointDedupeKey $Line))
}

function Compact-BobIrcOutbox {
    param(
        [string]$Home,
        [int]$ThresholdBytes = 32768
    )
    if (-not $Home) { $Home = Get-BobIrcHome }
    if (-not $Home) { return }
    $outbox = Join-Path $Home 'outbox.txt'
    if (-not (Test-Path -LiteralPath $outbox)) { return }
    $item = Get-Item -LiteralPath $outbox -ErrorAction SilentlyContinue
    if (-not $item -or [int64]$item.Length -le [int64]$ThresholdBytes) { return }
    $lines = @(Get-Content -LiteralPath $outbox -ErrorAction SilentlyContinue)
    if ($lines.Count -eq 0) { return }
    $points = @($lines | Where-Object { $_ -and ($_ -match 'MOOT v1 POINT' -or $_ -match 'POINT .+BOB v1 ') })
    $other = @($lines | Where-Object { $_ -and $_ -notmatch 'MOOT v1 POINT' -and $_ -notmatch 'POINT .+BOB v1 ' })
    $pointBytes = [Text.Encoding]::UTF8.GetByteCount(($points -join "`n"))
    if ($pointBytes -le $ThresholdBytes) { return }
    $keep = @()
    if ($other.Count -gt 0) { $keep += $other }
    $selfId = $null
    try { $selfId = Get-ThisMachineId } catch { }
    $selfPoints = $points
    if ($selfId) {
        $idRe = 'id=' + [regex]::Escape([string]$selfId) + '\b'
        $mine = @($points | Where-Object { $_ -match $idRe })
        if ($mine.Count -gt 0) { $selfPoints = $mine }
    }
    if ($selfPoints.Count -gt 0) { $keep += $selfPoints[-1] }
    elseif ($points.Count -gt 0) { $keep += $points[-1] }
    Set-Content -LiteralPath $outbox -Value $keep -Encoding utf8
}

function Get-BobIrcTrayPrefix { return 'BOB TRAY v1 ' }

function Test-BobIrcSkipPeerTranscriptOverwrite {
    param($Existing, $Incoming, [Parameter(Mandatory)][string]$ResolvedId)
    $selfId = $null
    try { $selfId = Get-ThisMachineId } catch { }
    if ($selfId -and [string]$ResolvedId -eq [string]$selfId) { return $true }
    if (-not $Existing) { return $false }
    if ([string]$Existing.source -in @('irc-tray', 'irc-digest')) { return $true }
    $exSeen = $null
    $inSeen = $null
    if ($Existing.lastSeen) {
        try {
            $exSeen = [datetime]::Parse([string]$Existing.lastSeen, $null, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        }
        catch { }
    }
    if ($Incoming.lastSeen) {
        try {
            $inSeen = [datetime]::Parse([string]$Incoming.lastSeen, $null, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        }
        catch { }
    }
    if ($exSeen -and $inSeen -and $exSeen -gt $inSeen) { return $true }
    return $false
}

function Test-BobIrcRepoOk {
    param([string]$Repo)
    $s = [string]$Repo
    if (-not $s -or -not $s.Trim()) { return $false }
    return ($s.Trim() -notin @('?', '-'))
}

function Get-BobIrcDisplayMachineId {
    param([string]$MachineId)
    $mid = [string]$MachineId
    if ($mid -eq 'ce-priority-dev1') { return 'dev1' }
    return $mid
}

function Get-BobGitShortSha {
    param([string]$Cwd)
    if (-not $Cwd -or -not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    try {
        if (-not (Test-Path (Join-Path $Cwd '.git'))) { return $null }
        $sha = & git -C $Cwd rev-parse --short HEAD 2>$null
        if ($sha) { return [string]$sha.Trim() }
    }
    catch { }
    return $null
}

function Get-BobIrcModelFromJob {
    param($Job)
    if (-not $Job) { return $null }
    $fuel = [string]$Job.fuel
    switch ($fuel) {
        'cursor-models' { return 'Cursor Models' }
        'copilot' { return 'Copilot' }
        'grok-bot' { return 'Grok Bot' }
        'grok-build' { return 'grok.exe' }
        'on-demand' { return 'grok.exe' }
    }
    if ($Job.model) { return [string]$Job.model }
    return $null
}

function Get-BobIrcKindFromJob {
    param($Job)
    if (-not $Job) { return $null }
    $k = [string]$Job.kind
    if ($k -eq 'mrb') { return 'mrb' }
    if ($k -eq 'uat') { return 'uat' }
    if ($k -eq 'build') { return 'worker' }
    if ($Job.mrb) { return 'mrb' }
    return $null
}

function Get-BobIrcEffectiveRepo {
    param($Doc, $RunningJob)
    if ($Doc -and (Test-BobIrcRepoOk $Doc.repo)) { return [string]$Doc.repo.Trim() }
    if ($RunningJob -and (Test-BobIrcRepoOk $RunningJob.repo)) { return [string]$RunningJob.repo.Trim() }
    foreach ($j in @($Doc.jobs)) {
        if ($j -and (Test-BobIrcRepoOk $j.repo)) { return [string]$j.repo.Trim() }
    }
    return $null
}

function Get-BobIrcRunningJobFromDoc {
    param($Doc)
    foreach ($j in @($Doc.jobs)) {
        if ($j -and [string]$j.state -eq 'running') { return $j }
    }
    return $null
}

function Get-BobIrcTalkSignature {
    param($Doc)
    if (-not $Doc) { return '' }
    $job = Get-BobIrcRunningJobFromDoc $Doc
    $parts = @(
        [string]$Doc.model
        [string]$Doc.kind
        [string]$Doc.repo
        [string]$Doc.sha
        [string]$Doc.hung
        [string]$Doc.responding
        [string]([int]$Doc.running)
        [string]([int]$Doc.queued)
        [string](Get-BobIrcEffectiveRepo $Doc $job)
    )
    return ($parts -join '|')
}

function Format-BobIrcPeerTalkLine {
    param($Doc)
    if (-not $Doc) { return $null }
    $mid = Get-BobIrcDisplayMachineId ([string]$Doc.id)
    $running = [int]$Doc.running
    $queued = [int]$Doc.queued
    $job = Get-BobIrcRunningJobFromDoc $Doc
    $busy = ($running -gt 0) -or ($queued -gt 0) -or $null -ne $job
    if (-not $busy) { return "$mid is idle." }
    if ($Doc.model) { return "$mid is on $([string]$Doc.model) now." }
    $repo = Get-BobIrcEffectiveRepo $Doc $job
    $kind = [string]$Doc.kind
    if ($kind -eq 'mrb' -and $repo) { return "That's an MRB of $repo." }
    if ($kind -eq 'uat' -and $repo) { return "That's UAT on $repo." }
    if ($kind -eq 'worker' -and $repo) { return "That's a worker on $repo." }
    if ($repo) { return "Working on $repo." }
    return "$mid is busy."
}

function Get-BobIrcChangeTalkLine {
    param($Before, $After)
    if (-not $After) { return $null }
    if (-not $Before) { return $null }
    if ((Get-BobIrcTalkSignature $Before) -eq (Get-BobIrcTalkSignature $After)) { return $null }
    return (Format-BobIrcPeerTalkLine $After)
}

function Get-BobIrcWarnStatePath {
    Join-Path (Get-BobIrcHome) (Join-Path 'bob-peers' '_irc-warn.json')
}

function Get-BobIrcLongRunningTalkLine {
    param($Doc, $PrimaryJob)
    if (-not $Doc -or -not $PrimaryJob) { return $null }
    $when = $PrimaryJob.claimedAt
    if (-not $when) { $when = $PrimaryJob.createdAt }
    if (-not $when) { return $null }
    try {
        $t = [datetime]::Parse([string]$when, $null, [Globalization.DateTimeStyles]::RoundtripKind)
        $secs = [int]([datetime]::UtcNow - $t.ToUniversalTime()).TotalSeconds
    }
    catch { return $null }
    $kind = Get-BobIrcKindFromJob $PrimaryJob
    $bar = 1800
    if ($kind -eq 'mrb' -or $kind -eq 'uat') { $bar = 1200 }
    if ($secs -lt $bar) { return $null }
    $warnPath = Get-BobIrcWarnStatePath
    $warn = @{}
    if (Test-Path $warnPath) {
        try {
            $wj = Read-JsonFile $warnPath
            if ($wj) {
                foreach ($p in $wj.PSObject.Properties) { $warn[$p.Name] = $p.Value }
            }
        }
        catch { }
    }
    $key = [string]$PrimaryJob.id
    if (-not $key) { $key = 'running' }
    if ($warn.ContainsKey($key)) { return $null }
    $mid = Get-BobIrcDisplayMachineId ([string]$Doc.id)
    $repo = Get-BobIrcEffectiveRepo $Doc $PrimaryJob
    $mins = $secs / 60
    $dur = if ($mins -ge 90) { 'over an hour' } elseif ($mins -ge 60) { 'about an hour' } else { "$([int]$mins) minutes" }
    $warn[$key] = [DateTime]::UtcNow.ToString('o')
    try { Write-JsonFile $warnPath ([pscustomobject]$warn) } catch { }
    if ($kind -eq 'mrb' -and $repo) {
        return "$mid has been on that MRB of $repo for $dur - still responding, but that's a long time."
    }
    if ($repo) {
        return "$mid has been on $repo for $dur - still responding, but that's a long time."
    }
    return "$mid has been running for $dur - still responding, but that's a long time."
}

function Add-BobIrcOutboxChannelLine {
    param([string]$Line)
    if (-not $Line) { return }
    $home = Get-BobIrcHome
    $outbox = Join-Path $home 'outbox.txt'
    $last = $null
    try { $last = Get-Content -LiteralPath $outbox -Tail 1 -ErrorAction SilentlyContinue } catch { }
    if ($last -and ([string]$last).Trim() -eq [string]$Line.Trim()) { return }
    Add-Content -Path $outbox -Value ([string]$Line).Trim() -Encoding utf8
}

function ConvertFrom-BobIrcTrayLine {
    param([string]$Text)
    $prefix = Get-BobIrcTrayPrefix
    $raw = ([string]$Text).Trim()
    if (-not $raw.StartsWith($prefix)) { return $null }
    $body = $raw.Substring($prefix.Length).Trim()
    $kv = @{}
    foreach ($tok in $body.Split(' ')) {
        if ($tok -notmatch '=') { return $null }
        $k, $v = $tok.Split('=', 2)
        $kv[$k] = $v
    }
    $mid = [string]$kv['id']
    if (-not $mid -or $mid -eq '-') { return $null }
    if ($mid -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { return $null }
    $jobs = @()
    $jr = [string]$kv['jobs']
    if ($jr -and $jr -ne '-') {
        foreach ($part in $jr.Split(',')) {
            if ($part -notmatch ':') { continue }
            $repo, $st = $part.Split(':', 2)
            if ((Test-BobIrcRepoOk $repo) -and $st) {
                $jobs += ,[pscustomobject]@{ repo = $repo; state = $st; machine = $mid }
            }
        }
    }
    $weekly = $null
    if ($kv.ContainsKey('weekly') -and [string]$kv['weekly'] -ne '-') {
        try { $weekly = [int]$kv['weekly'] } catch { }
    }
    $repo = $null
    if (Test-BobIrcRepoOk $kv['repo']) { $repo = [string]$kv['repo'] }
    $kind = $null
    if ($kv.ContainsKey('kind') -and [string]$kv['kind'] -ne '-') { $kind = [string]$kv['kind'] }
    $model = $null
    if ($kv.ContainsKey('model') -and [string]$kv['model'] -ne '-') { $model = [string]$kv['model'] }
    return [pscustomobject]@{
        ok         = $true
        id         = $mid
        weekly     = $weekly
        running    = $(try { [int]$kv['running'] } catch { 0 })
        queued     = $(try { [int]$kv['queued'] } catch { 0 })
        lastSeen   = $(if ($kv['lastSeen'] -and $kv['lastSeen'] -ne '-') { [string]$kv['lastSeen'] } else { $null })
        jobs       = $jobs
        repo       = $repo
        kind       = $kind
        model      = $model
        source     = 'irc-tray'
    }
}

function Get-BobIrcTrayLogPosPath {
    Join-Path (Get-BobIrcHome) (Join-Path 'bob-peers' '_tray-log.pos')
}

function Get-BobIrcBobiverseLastPath {
    Join-Path (Get-BobIrcHome) (Join-Path 'bob-peers' '_bobiverse-last.txt')
}

function Get-BobIrcDigestPrefix { return 'BOB DIGEST v1 ' }

function Get-BobIrcDigestChunkStatePath {
    Join-Path (Get-BobIrcHome) (Join-Path 'bob-peers' '_digest-chunks.json')
}

function Test-BobIrcDigestBlobSafe {
    param([string]$Text)
    $lower = ([string]$Text).ToLowerInvariant()
    if (-not $lower) { return $true }
    foreach ($m in @('password=', 'xai_api_key=', 'connect.password', 'bob_report_secret')) {
        if ($lower.Contains($m)) { return $false }
    }
    return $true
}

function Parse-BobIrcDigestWhisperBody {
    param([string]$Body)
    $raw = ([string]$Body).Trim()
    if (-not $raw) { return $null }
    if ($raw.StartsWith('{')) {
        return [pscustomobject]@{ kind = 'json'; text = $raw }
    }
    $prefix = Get-BobIrcDigestPrefix
    if (-not $raw.StartsWith($prefix)) { return $null }
    $rest = $raw.Substring($prefix.Length).Trim()
    if ($rest -match '^(\d+)/(\d+)\s+(.*)$') {
        return [pscustomobject]@{
            kind  = 'chunk'
            index = [int]$Matches[1]
            total = [int]$Matches[2]
            text  = [string]$Matches[3]
        }
    }
    return $null
}

function Read-BobIrcDigestChunkState {
    $p = Get-BobIrcDigestChunkStatePath
    if (-not (Test-Path $p)) {
        return [pscustomobject]@{ total = 0; parts = @{} }
    }
    try {
        $j = Read-JsonFile $p
        $parts = @{}
        if ($j.parts) {
            foreach ($prop in @($j.parts.PSObject.Properties)) {
                $parts[[string]$prop.Name] = [string]$prop.Value
            }
        }
        $total = 0
        try { $total = [int]$j.total } catch { }
        return [pscustomobject]@{ total = $total; parts = $parts }
    }
    catch {
        return [pscustomobject]@{ total = 0; parts = @{} }
    }
}

function Write-BobIrcDigestChunkState {
    param($State)
    $p = Get-BobIrcDigestChunkStatePath
    $dir = Split-Path $p -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $partsHt = @{}
    foreach ($k in @($State.parts.Keys)) {
        $partsHt[[string]$k] = [string]$State.parts[$k]
    }
    Write-JsonFile $p ([pscustomobject]@{ total = [int]$State.total; parts = $partsHt })
}

function Clear-BobIrcDigestChunkState {
    $p = Get-BobIrcDigestChunkStatePath
    if (Test-Path $p) {
        try { Remove-Item -LiteralPath $p -Force } catch { }
    }
}

function Add-BobIrcDigestChunk {
    param([int]$Index, [int]$Total, [string]$Piece)
    if ($Index -lt 1 -or $Total -lt 1 -or $Index -gt $Total) { return $null }
    $state = Read-BobIrcDigestChunkState
    if ($Index -eq 1 -or $state.total -ne $Total) {
        $state = [pscustomobject]@{ total = $Total; parts = @{} }
    }
    $state.parts[[string]$Index] = [string]$Piece
    $haveAll = $true
    for ($i = 1; $i -le $Total; $i++) {
        if (-not $state.parts.ContainsKey([string]$i)) { $haveAll = $false; break }
    }
    if (-not $haveAll) {
        Write-BobIrcDigestChunkState $state
        return $null
    }
    Clear-BobIrcDigestChunkState
    $sb = New-Object System.Text.StringBuilder
    for ($i = 1; $i -le $Total; $i++) {
        [void]$sb.Append([string]$state.parts[[string]$i])
    }
    return $sb.ToString()
}

function Resolve-BobCursorPoolSeatId {
    param([string]$PoolId)
    $rawId = [string]$PoolId
    if (-not $rawId) { return $null }
    foreach ($seat in @(Get-BobSeatConfig)) {
        if ([string]$seat.id -eq $rawId) { return [string]$seat.id }
        foreach ($sm in @($seat.machines)) {
            if ([string]$sm -eq $rawId) { return [string]$seat.id }
        }
    }
    return $rawId
}

function Apply-BobIrcDigestCursorPools {
    param($Pools)
    foreach ($pool in @($Pools)) {
        if (-not $pool) { continue }
        $poolId = [string]$pool.id
        if (-not $poolId) { $poolId = [string]$pool.seat }
        if (-not $poolId) { continue }
        $seatId = Resolve-BobCursorPoolSeatId $poolId
        if (-not $seatId) { continue }
        $rem = $null
        if ($null -ne $pool.remaining -and [string]$pool.remaining -ne '') {
            try { $rem = [int]$pool.remaining } catch { }
        }
        elseif ($null -ne $pool.remaining_pct -and [string]$pool.remaining_pct -ne '') {
            try { $rem = [int]$pool.remaining_pct } catch { }
        }
        $period = $null
        if ($pool.period_end) { $period = [string]$pool.period_end }
        elseif ($pool.reset) { $period = [string]$pool.reset }
        $label = $null
        if ($pool.label) { $label = [string]$pool.label }
        if ($pool.overage) {
            $ov = [string]$pool.overage
            if ($label) { $label = ('{0} {1}' -f $label, $ov) }
            else { $label = $ov }
        }
        Save-BobCursorPoolForSeat -SeatId $seatId -RemainingPct $rem -PeriodEnd $period -Label $label
    }
}

function Get-BobIrcDigestMachinePropertyNames {
    param($Ent)
    if (-not $Ent) { return @() }
    return @($Ent.PSObject.Properties.Name)
}

function Get-BobIrcDigestJobSourcesFromMachine {
    param($Ent)
    if (-not $Ent) { return @() }
    $names = Get-BobIrcDigestMachinePropertyNames $Ent
    $raw = @()
    if ($names -contains 'jobs') {
        foreach ($j in @($Ent.jobs)) { if ($j) { $raw += ,$j } }
    }
    if ($raw.Count -eq 0 -and ($names -contains 'task') -and $Ent.task) {
        $raw += ,$Ent.task
    }
    return $raw
}

function Test-BobIrcDigestMachineHasJobPayload {
    param($Ent)
    foreach ($j in @(Get-BobIrcDigestJobSourcesFromMachine $Ent)) {
        if (-not $j) { continue }
        if ($j.sha) { return $true }
        if ($j.repo -and (Test-BobIrcRepoOk ([string]$j.repo))) { return $true }
    }
    return $false
}

function Merge-BobIrcDigestPeerWithPrevious {
    param($Ent, $Doc, $Prev)
    if (-not $Doc -or -not $Prev) { return $Doc }
    $names = Get-BobIrcDigestMachinePropertyNames $Ent
    if ($names -notcontains 'weekly' -and $null -ne $Prev.weekly) {
        $Doc | Add-Member -NotePropertyName weekly -NotePropertyValue $Prev.weekly -Force
    }
    if ($names -notcontains 'period_end' -and -not ($names -contains 'reset' -and $Ent.reset) -and $Prev.period_end) {
        $Doc | Add-Member -NotePropertyName period_end -NotePropertyValue ([string]$Prev.period_end) -Force
    }
    if ($names -notcontains 'cursor_label' -and $Prev.cursor_label) {
        $Doc | Add-Member -NotePropertyName cursor_label -NotePropertyValue ([string]$Prev.cursor_label) -Force
    }
    if ($names -notcontains 'cursor_period_end' -and $Prev.cursor_period_end) {
        $Doc | Add-Member -NotePropertyName cursor_period_end -NotePropertyValue ([string]$Prev.cursor_period_end) -Force
    }
    if (-not (Test-BobIrcDigestMachineHasJobPayload $Ent)) {
        $prevJobs = @()
        foreach ($j in @($Prev.jobs)) { if ($j) { $prevJobs += ,$j } }
        if ($prevJobs.Count -gt 0) {
            $Doc | Add-Member -NotePropertyName jobs -NotePropertyValue $prevJobs -Force
        }
    }
    foreach ($fld in @('sha', 'repo', 'model', 'kind')) {
        if ($names -notcontains $fld) {
            $pv = $Prev.$fld
            if ($pv -and -not $Doc.$fld) {
                $Doc | Add-Member -NotePropertyName $fld -NotePropertyValue ([string]$pv) -Force
            }
        }
    }
    return $Doc
}

function ConvertTo-BobIrcPeerFromDigestMachine {
    param([string]$MachineId, $Ent)
    if (-not $Ent) { return $null }
    $mid = Resolve-BobiverseMachineId $MachineId
    if (-not $mid) { return $null }
    $jobs = @()
    foreach ($j in @(Get-BobIrcDigestJobSourcesFromMachine $Ent)) {
        if (-not $j) { continue }
        $repo = $null
        if ($j.repo -and (Test-BobIrcRepoOk ([string]$j.repo))) { $repo = [string]$j.repo }
        $st = 'running'
        if ($j.state) { $st = [string]$j.state }
        $row = [pscustomobject]@{
            repo        = $repo
            state       = $st
            machine     = $mid
            sha         = $(if ($j.sha) { [string]$j.sha } else { $null })
            model       = $(if ($j.model) { [string]$j.model } else { $null })
            description = $(if ($j.description) { [string]$j.description } else { $null })
            run_time    = $(if ($j.run_time) { [string]$j.run_time } else { $null })
        }
        if ($repo -or $row.sha) { $jobs += ,$row }
    }
    $names = Get-BobIrcDigestMachinePropertyNames $Ent
    $weekly = $null
    if ($names -contains 'weekly' -and $null -ne $Ent.weekly -and [string]$Ent.weekly -ne '') {
        try { $weekly = [int]$Ent.weekly } catch { }
    }
    $periodEnd = $null
    if ($Ent.period_end) { $periodEnd = [string]$Ent.period_end }
    elseif ($Ent.reset) { $periodEnd = [string]$Ent.reset }
    $primaryJob = Get-BobIrcDigestTaskFromJobs @(Get-BobIrcDigestJobSourcesFromMachine $Ent)
    $topRepo = $null
    if ($names -contains 'repo' -and $Ent.repo -and (Test-BobIrcRepoOk ([string]$Ent.repo))) { $topRepo = [string]$Ent.repo }
    elseif ($primaryJob -and $primaryJob.repo -and (Test-BobIrcRepoOk ([string]$primaryJob.repo))) {
        $topRepo = [string]$primaryJob.repo
    }
    $topSha = $null
    if ($names -contains 'sha' -and $Ent.sha) { $topSha = [string]$Ent.sha }
    elseif ($primaryJob -and $primaryJob.sha) { $topSha = [string]$primaryJob.sha }
    $topModel = $null
    if ($names -contains 'model' -and $Ent.model) { $topModel = [string]$Ent.model }
    elseif ($primaryJob -and $primaryJob.model) { $topModel = [string]$primaryJob.model }
    return [pscustomobject]@{
        ok                = $true
        id                = $mid
        weekly            = $weekly
        period_end        = $periodEnd
        cursor_label      = $(if ($names -contains 'cursor_label' -and $Ent.cursor_label) { [string]$Ent.cursor_label } else { $null })
        cursor_period_end = $(if ($names -contains 'cursor_period_end' -and $Ent.cursor_period_end) { [string]$Ent.cursor_period_end } else { $null })
        running           = $(try { [int]$Ent.running } catch { 0 })
        queued            = $(try { [int]$Ent.queued } catch { 0 })
        lastSeen          = $(if ($Ent.lastSeen) { [string]$Ent.lastSeen } else { $null })
        jobs              = $jobs
        model             = $topModel
        kind              = $(if ($names -contains 'kind' -and $Ent.kind) { [string]$Ent.kind } else { $null })
        repo              = $topRepo
        sha               = $topSha
        fuel              = $(if ($Ent.fuel) { [string]$Ent.fuel } else { $null })
        source            = 'irc-digest'
    }
}

function Get-BobIrcDigestTaskFromJobs {
    param($Jobs)
    foreach ($j in @($Jobs)) {
        if (-not $j) { continue }
        $st = [string]$j.state
        if ($st -match '^(?i)(running|start|queued)$') { return $j }
    }
    if (@($Jobs).Count -gt 0) { return $Jobs[0] }
    return $null
}

function Get-BobIrcDigestReportPatchFromMachine {
    param($Ent)
    if (-not $Ent) { return $null }
    $names = Get-BobIrcDigestMachinePropertyNames $Ent
    $node = [ordered]@{}
    $primary = Get-BobIrcDigestTaskFromJobs @(Get-BobIrcDigestJobSourcesFromMachine $Ent)
    if ($primary) {
        $node.task = [pscustomobject]@{
            repo        = $(if ($primary.repo) { [string]$primary.repo } else { $null })
            sha         = $(if ($primary.sha) { [string]$primary.sha } else { $null })
            model       = $(if ($primary.model) { [string]$primary.model } else { $null })
            description = $(if ($primary.description) { [string]$primary.description } else { $null })
            run_time    = $(if ($primary.run_time) { [string]$primary.run_time } else { $null })
            state       = $(if ($primary.state) { [string]$primary.state } else { 'START' })
        }
    }
    if ($names -contains 'pcent' -and $Ent.pcent) { $node.pcent = $Ent.pcent }
    if ($names -contains 'uptime_since' -and $Ent.uptime_since) {
        $node.uptime_since = [string]$Ent.uptime_since
    }
    if ($node.Count -eq 0) { return $null }
    return [pscustomobject]$node
}

function Build-BobIrcReportDigestFromBobiverse {
    param($DigestObj)
    $prev = Read-BobReportDigest
    $machinesOut = [ordered]@{}
    if ($prev -and $prev.machines) {
        foreach ($p in @($prev.machines.PSObject.Properties)) {
            $machinesOut[[string]$p.Name] = $p.Value
        }
    }
    $nodes = $DigestObj.machines
    if (-not $nodes) {
        if ($machinesOut.Count -gt 0) {
            return [pscustomobject]@{ machines = [pscustomobject]$machinesOut }
        }
        return [pscustomobject]@{ machines = [pscustomobject]@{} }
    }
    $anyPatch = $false
    foreach ($prop in @($nodes.PSObject.Properties)) {
        $mid = Resolve-BobiverseMachineId ([string]$prop.Name)
        if (-not $mid) { continue }
        $ent = $prop.Value
        if (-not $ent) { continue }
        $patch = Get-BobIrcDigestReportPatchFromMachine $ent
        if (-not $patch) { continue }
        $anyPatch = $true
        $merged = [ordered]@{}
        $existing = $null
        if ($machinesOut.Contains($mid)) { $existing = $machinesOut[$mid] }
        if ($existing) {
            if ($existing.task) { $merged.task = $existing.task }
            if ($existing.pcent) { $merged.pcent = $existing.pcent }
            if ($existing.uptime_since) { $merged.uptime_since = [string]$existing.uptime_since }
        }
        if ($patch.task) { $merged.task = $patch.task }
        if ($patch.pcent) { $merged.pcent = $patch.pcent }
        $patchNames = Get-BobIrcDigestMachinePropertyNames $ent
        if ($patchNames -contains 'uptime_since' -and $patch.uptime_since) {
            $merged.uptime_since = [string]$patch.uptime_since
        }
        $machinesOut[$mid] = [pscustomobject]$merged
    }
    if (-not $anyPatch -and $prev) { return $prev }
    return [pscustomobject]@{ machines = [pscustomobject]$machinesOut }
}

function Import-BobIrcDigestJson {
    param($DigestObj)
    if (-not $DigestObj) { return @() }
    $home = Get-BobIrcHome
    $dir = Join-Path $home 'bob-peers'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $updated = @()
    if ($DigestObj.cursor_pools) {
        Apply-BobIrcDigestCursorPools -Pools @($DigestObj.cursor_pools)
    }
    $report = Build-BobIrcReportDigestFromBobiverse -DigestObj $DigestObj
    Write-JsonFile (Join-Path $dir '_report-digest.json') $report
    $nodes = $DigestObj.machines
    if (-not $nodes) { return $updated }
    foreach ($prop in @($nodes.PSObject.Properties)) {
        $doc = ConvertTo-BobIrcPeerFromDigestMachine -MachineId ([string]$prop.Name) -Ent $prop.Value
        if (-not $doc) { continue }
        $resolved = [string]$doc.id
        $peerPath = Join-Path $dir ($resolved + '.json')
        $prev = $null
        if (Test-Path $peerPath) {
            try { $prev = Read-JsonFile $peerPath } catch { }
        }
        if ($prev) {
            $doc = Merge-BobIrcDigestPeerWithPrevious -Ent $prop.Value -Doc $doc -Prev $prev
        }
        Save-BobSeatPeriodEnd -MachineId $resolved -PeriodEnd $(if ($doc.period_end) { [string]$doc.period_end } else { $null }) -Weekly $doc.weekly
        if ($doc.cursor_label -and [string]$doc.cursor_label -ne 'empty') {
            $seat = Get-BobSeatForMachine -MachineId $resolved
            if ($seat) {
                Save-BobCursorPoolForSeat -SeatId ([string]$seat.id) -Label ([string]$doc.cursor_label) -PeriodEnd $(if ($doc.cursor_period_end) { [string]$doc.cursor_period_end } else { $null })
            }
        }
        Write-JsonFile $peerPath $doc
        $updated += $resolved
    }
    return $updated
}

function Import-BobIrcDigestWhisperBody {
    param([string]$Body)
    $parsed = Parse-BobIrcDigestWhisperBody $Body
    if (-not $parsed) { return @() }
    $jsonText = $null
    if ($parsed.kind -eq 'json') {
        $jsonText = [string]$parsed.text
    }
    elseif ($parsed.kind -eq 'chunk') {
        $jsonText = Add-BobIrcDigestChunk -Index $parsed.index -Total $parsed.total -Piece ([string]$parsed.text)
    }
    if (-not $jsonText) { return @() }
    if (-not (Test-BobIrcDigestBlobSafe $jsonText)) { return @() }
    try {
        $obj = $jsonText | ConvertFrom-Json
    }
    catch { return @() }
    return @(Import-BobIrcDigestJson -DigestObj $obj)
}

function Request-BobIrcBobiversePull {
    param([int]$MinIntervalSec = 120)
    $home = Get-BobIrcHome
    $stampPath = Get-BobIrcBobiverseLastPath
    $now = [DateTime]::UtcNow
    if (Test-Path $stampPath) {
        try {
            $prev = [datetime]::Parse((Get-Content $stampPath -Raw).Trim(), $null, [Globalization.DateTimeStyles]::RoundtripKind)
            if (($now - $prev.ToUniversalTime()).TotalSeconds -lt $MinIntervalSec) { return $false }
        }
        catch { }
    }
    Add-BobIrcOutboxChannelLine '!bobiverse'
    Set-Content -Path $stampPath -Value $now.ToString('o') -Encoding utf8 -NoNewline
    return $true
}

function Import-BobIrcTrayPull {
    $home = Get-BobIrcHome
    $logPath = Join-Path $home 'irc.log'
    if (-not (Test-Path $logPath)) { return @() }
    $posPath = Get-BobIrcTrayLogPosPath
    $pos = 0
    if (Test-Path $posPath) {
        try { $pos = [int](Get-Content $posPath -Raw).Trim() } catch { $pos = 0 }
    }
    $bytes = [IO.File]::ReadAllBytes($logPath)
    if ($pos -gt $bytes.Length) { $pos = 0 }
    $chunk = $bytes[$pos..($bytes.Length - 1)]
    $text = [Text.Encoding]::UTF8.GetString($chunk)
    $nick = $null
    try {
        $cfg = Get-BobiverseConfig
        $id = Get-ThisMachineId
        if ($cfg -and $id) { $nick = Get-BobIrcNick $cfg $id }
    }
    catch { }
    if (-not $nick -and $env:BOB_IRC_NICK -and $env:BOB_IRC_NICK.Trim()) {
        $nick = $env:BOB_IRC_NICK.Trim()
    }
    if (-not $nick) {
        try {
            $id = Get-ThisMachineId
            if ($id) { $nick = 'bob-' + $id }
        }
        catch { }
    }
    if (-not $nick) { return @() }
    $nickEsc = [regex]::Escape($nick)
    $updated = @()
    $dir = Join-Path $home 'bob-peers'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $trayPrefix = Get-BobIrcTrayPrefix
    $digestPrefix = Get-BobIrcDigestPrefix
    foreach ($line in @($text -split "`n")) {
        $t = $line.Trim()
        if (-not $t) { continue }
        if ($t -notmatch "(?i)PRIVMSG\s+$nickEsc\s+:(?<ircbody>.*)$") { continue }
        $body = [string]$Matches['ircbody'].Trim()
        if ($body.StartsWith($digestPrefix) -or $body.StartsWith('{')) {
            foreach ($id in @(Import-BobIrcDigestWhisperBody $body)) {
                if ($id -and $updated -notcontains $id) { $updated += $id }
            }
            continue
        }
        if (-not $body.StartsWith($trayPrefix)) { continue }
        $doc = ConvertFrom-BobIrcTrayLine $body
        if (-not $doc) { continue }
        $resolved = Resolve-BobiverseMachineId ([string]$doc.id)
        if (-not $resolved) { continue }
        $doc | Add-Member -NotePropertyName id -NotePropertyValue $resolved -Force
        $peerPath = Join-Path $dir ($resolved + '.json')
        if (-not $doc.period_end -and (Test-Path $peerPath)) {
            try {
                $prev = Read-JsonFile $peerPath
                if ($prev -and $prev.period_end) {
                    $doc | Add-Member -NotePropertyName period_end -NotePropertyValue ([string]$prev.period_end) -Force
                }
                if ($prev -and $prev.cursor_label -and -not $doc.cursor_label) {
                    $doc | Add-Member -NotePropertyName cursor_label -NotePropertyValue ([string]$prev.cursor_label) -Force
                }
                if ($prev -and $prev.cursor_period_end -and -not $doc.cursor_period_end) {
                    $doc | Add-Member -NotePropertyName cursor_period_end -NotePropertyValue ([string]$prev.cursor_period_end) -Force
                }
            }
            catch { }
        }
        Save-BobSeatPeriodEnd -MachineId $resolved -PeriodEnd $(if ($doc.period_end) { [string]$doc.period_end } else { $null }) -Weekly $doc.weekly
        Write-JsonFile $peerPath $doc
        $updated += $resolved
    }
    Set-Content -Path $posPath -Value $bytes.Length -Encoding utf8 -NoNewline
    return $updated
}

function Write-BobIrcStatus {
    $id = Get-ThisMachineId
    if (-not $id) { return }
    $cfg = Get-BobiverseConfig
    if (-not $cfg) { return }
    $home = Get-BobIrcHome
    $bridge = Get-BridgeRoot
    $running = @(Get-BobPeerLaneJobs -BridgeRoot $bridge -MachineId $id -Lane running -StampRepo)
    if ($null -eq $running) { $running = @() }
    $inbox = @(Get-BobPeerLaneJobs -BridgeRoot $bridge -MachineId $id -Lane inbox -StampRepo)
    if ($null -eq $inbox) { $inbox = @() }
    $jobs = @()
    foreach ($j in @($running)) {
        $repo = Get-BobJobRepoStamp $j
        if (Test-BobIrcRepoOk $repo) {
            $jobs += ,[pscustomobject]@{ repo = $repo; state = 'running' }
        }
    }
    foreach ($j in @($inbox)) {
        $repo = Get-BobJobRepoStamp $j
        if (Test-BobIrcRepoOk $repo) {
            $jobs += ,[pscustomobject]@{ repo = $repo; state = 'queued' }
        }
    }
    $primary = $null
    if (@($running).Count -gt 0) { $primary = $running[0] }
    $liveN = 0
    foreach ($g in @(Get-BobLiveGrokAgents)) {
        $liveN++
        $repo = 'grok.exe'
        if ($g.cwd) {
            $slug = Get-GitHubSlugFromCwd $g.cwd
            if ($slug -and $slug -ne '?' -and $slug -ne $env:USERNAME) { $repo = $slug }
        }
        if (Test-BobIrcRepoOk $repo) {
            $jobs += ,[pscustomobject]@{ repo = $repo; state = 'running' }
        }
        if (-not $primary) { $primary = $g }
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
    Save-BobSeatPeriodEnd -MachineId $id -PeriodEnd $periodEnd -Weekly $week
    $cursorLabel = $null
    $cursorPeriodEnd = $null
    try {
        $cw = Get-BobCursorAgentWeeklyRemaining
        if ($cw) {
            $cursorLabel = Format-BobCursorAccountLabel -RemainingPct $cw.remaining_pct -UsedPct $cw.used_pct
            if ($cursorLabel -eq 'empty') {
                $gbp = $null
                try { $gbp = Get-BobCursorOverageGbp } catch { }
                if ($null -eq $gbp -and $null -ne $cw.overage_gbp) { $gbp = [double]$cw.overage_gbp }
                if ($null -ne $gbp) { $cursorLabel = ('-{0}{1:N2}' -f [char]0x00A3, [math]::Abs([double]$gbp)) }
            }
            if ($cw.period_end) { $cursorPeriodEnd = [string]$cw.period_end }
            if ($cursorLabel -and $cursorLabel -ne 'empty') {
                Save-BobCursorAccountCache -Label $cursorLabel -PeriodEnd $cursorPeriodEnd
            }
        }
    } catch { }
    $model = Get-BobIrcModelFromJob $primary
    if (-not $model -and $cursorLabel -and $cursorLabel -ne 'empty') { $model = 'Cursor Models' }
    $kind = Get-BobIrcKindFromJob $primary
    $topRepo = $null
    if ($primary) { $topRepo = Get-BobJobRepoStamp $primary }
    if (-not (Test-BobIrcRepoOk $topRepo)) { $topRepo = $null }
    $sha = $null
    if ($primary -and $primary.cwd) { $sha = Get-BobGitShortSha ([string]$primary.cwd) }
    $responding = $null
    if ($primary -and $primary.sessionId) {
        try { $responding = Test-BobJobProcess -SessionId ([string]$primary.sessionId) } catch { }
    }
    $startedAt = $null
    if ($primary) {
        if ($primary.claimedAt) { $startedAt = [string]$primary.claimedAt }
        elseif ($primary.createdAt) { $startedAt = [string]$primary.createdAt }
    }
    $doc = [pscustomobject]@{
        ok                = $true
        id                = $id
        weekly            = $week
        period_end        = $periodEnd
        cursor_label      = $cursorLabel
        cursor_period_end = $cursorPeriodEnd
        running           = @($running).Count + $liveN
        queued            = @($inbox).Count
        lastSeen          = $seen
        jobs              = $jobs
        model             = $model
        kind              = $kind
        repo              = $topRepo
        sha               = $sha
        started_at        = $startedAt
        responding        = $responding
        source            = 'irc'
    }
    $dir = Join-Path $home 'bob-peers'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $peerPath = Join-Path $dir ($id + '.json')
    $before = $null
    if (Test-Path $peerPath) {
        try { $before = Read-JsonFile $peerPath } catch { }
    }
    Write-JsonFile $peerPath $doc
    $talk = Get-BobIrcChangeTalkLine -Before $before -After $doc
    if ($talk) { Add-BobIrcOutboxChannelLine $talk }
    $warn = Get-BobIrcLongRunningTalkLine -Doc $doc -PrimaryJob $primary
    if ($warn) { Add-BobIrcOutboxChannelLine $warn }
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
        $prev = $null
        if (Test-Path $peerPath) {
            try { $prev = Read-JsonFile $peerPath } catch { }
        }
        if (Test-BobIrcSkipPeerTranscriptOverwrite -Existing $prev -Incoming $doc -ResolvedId $resolved) { continue }
        # Keep prior period_end when the latest POINT still lacks reset=.
        if (-not $doc.period_end -and $prev -and $prev.period_end) {
            $doc | Add-Member -NotePropertyName period_end -NotePropertyValue ([string]$prev.period_end) -Force
        }
        Save-BobSeatPeriodEnd -MachineId $resolved -PeriodEnd $(if ($doc.period_end) { [string]$doc.period_end } else { $null }) -Weekly $doc.weekly
        if ($doc.cursor_label -and [string]$doc.cursor_label -ne 'empty') {
            Save-BobCursorAccountCache -Label ([string]$doc.cursor_label) -PeriodEnd $(if ($doc.cursor_period_end) { [string]$doc.cursor_period_end } else { $null })
        }
        Write-JsonFile $peerPath $doc
        $updated += $resolved
    }
    return $updated
}
