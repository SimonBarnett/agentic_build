function Test-BobTrayLooksLikeSha {
    param([string]$Value)
    if (-not $Value) { return $true }
    $s = [string]$Value.Trim()
    if ($s -match '^(HEAD|[0-9a-fA-F]{7,40})$') { return $true }
    return $false
}

function Get-GitHubSlugFromCwd {
    param([string]$Cwd)
    $slug = $null
    if ($Cwd) {
        try {
            if (Get-Command git -ErrorAction SilentlyContinue) {
                $url = & git -C $Cwd remote get-url origin 2>$null
                if ($url -match 'github\.com[:/](?<slug>.+?)(?:\.git)?\s*$') {
                    $slug = $Matches['slug'].Trim().TrimEnd('/').Replace('\', '/')
                }
            }
        }
        catch { }
    }
    if ($slug -and ($slug -match '/') -and -not (Test-BobTrayLooksLikeSha $slug)) {
        return $slug
    }
    if ($Cwd) {
        try {
            $leaf = Split-Path $Cwd -Leaf
            if ($leaf -and -not (Test-BobTrayLooksLikeSha $leaf)) { return $leaf }
        }
        catch { }
    }
    return '?'
}

function Get-BobJobAge {
    param($ClaimedAt)
    if (-not $ClaimedAt) { return '?' }
    try {
        $t = [datetime]::Parse([string]$ClaimedAt, $null, [Globalization.DateTimeStyles]::RoundtripKind)
        if ($t.Kind -eq [DateTimeKind]::Unspecified) { $t = [datetime]::SpecifyKind($t, [DateTimeKind]::Utc) }
        $ts = [datetime]::UtcNow - $t.ToUniversalTime()
        if ($ts.TotalHours -ge 1) { return ('{0}h{1}m' -f [int]$ts.TotalHours, $ts.Minutes) }
        if ($ts.TotalMinutes -ge 1) { return ('{0}m' -f [int]$ts.TotalMinutes) }
        return ('{0}s' -f [int][math]::Max(0, $ts.TotalSeconds))
    }
    catch { return '?' }
}

function Get-ContextWindowTokens {
    try {
        $p = Join-Path $env:USERPROFILE '.grok\models_cache.json'
        if (-not (Test-Path $p)) { return 500000 }
        $d = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
        $m = $d.models
        foreach ($name in @('grok-4.6', 'grok-4.5', 'grok-4')) {
            if ($m.$name -and $m.$name.info -and $m.$name.info.context_window) {
                return [int]$m.$name.info.context_window
            }
        }
    }
    catch { }
    return 500000
}

function Get-SessionContextRemaining {
    param([string]$Cwd, [string]$SessionId)
    if (-not $Cwd -or -not $SessionId) { return $null }
    $leaf = ([string]$Cwd).Replace('\', '%5C').Replace(':', '%3A')
    $usagePath = Join-Path $env:USERPROFILE (Join-Path '.grok\sessions' (Join-Path $leaf (Join-Path $SessionId 'usage.json')))
    if (-not (Test-Path $usagePath)) { return $null }
    try {
        $u = Get-Content $usagePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $s = $u.session
        if (-not $s) { return $null }
        $input = [int64]$s.inputTokens
        $cached = 0
        if ($s.cachedReadTokens) { $cached = [int64]$s.cachedReadTokens }
        $used = [math]::Max(0, $input - $cached)
        $window = Get-ContextWindowTokens
        if ($window -le 0) { return $null }
        $remain = [int][math]::Round(100.0 * [math]::Max(0, $window - $used) / $window)
        if ($remain -gt 100) { $remain = 100 }
        return [pscustomobject]@{
            remaining_pct = $remain
            used          = $used
            window        = $window
        }
    }
    catch { return $null }
}

function Get-BobWeeklyLogPath {
    if ($env:BOB_WEEKLY_LOG -and $env:BOB_WEEKLY_LOG.Trim()) {
        return $env:BOB_WEEKLY_LOG.Trim()
    }
    # Isolated Fake-Grok tests must not scrape the operator CLI log.
    $exe = [string]$env:BOB_GROK_EXE
    if ($exe -and ($exe -match '(?i)Fake-Grok')) { return $null }
    return (Join-Path $env:USERPROFILE '.grok\logs\unified.jsonl')
}

function Get-BobWeeklyRemaining {
    [CmdletBinding()]
    param([string]$LogPath)
    if (-not $LogPath) { $LogPath = Get-BobWeeklyLogPath }
    if (-not $LogPath -or -not (Test-Path $LogPath)) { return $null }
    $raw = $null
    try {
        $fs = [IO.File]::Open($LogPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $pos = $fs.Length
            $chunk = 1MB
            while ($pos -gt 0 -and -not $raw) {
                $take = [int64][Math]::Min($chunk, $pos)
                $pos = $pos - $take
                [void]$fs.Seek($pos, [IO.SeekOrigin]::Begin)
                $buf = New-Object byte[] $take
                $n = $fs.Read($buf, 0, $take)
                $text = [Text.Encoding]::UTF8.GetString($buf, 0, $n)
                $lines = $text -split "`r?`n"
                $start = 0
                if ($pos -gt 0) { $start = 1 }
                for ($i = $lines.Length - 1; $i -ge $start; $i--) {
                    $ln = $lines[$i]
                    if ($ln -and $ln.Contains('billing: fetched credits config')) {
                        $raw = $ln.Trim()
                        break
                    }
                }
            }
        }
        finally { $fs.Dispose() }
    }
    catch { return $null }
    if (-not $raw) { return $null }
    try {
        $j = $raw | ConvertFrom-Json
        $cfg = $null
        if ($j.ctx -and $j.ctx.config) { $cfg = $j.ctx.config }
        elseif ($j.config) { $cfg = $j.config }
        if (-not $cfg) { return $null }
        $ptype = $null
        if ($cfg.currentPeriod -and $cfg.currentPeriod.type) { $ptype = [string]$cfg.currentPeriod.type }
        # Only the weekly period is the CLI "Weekly limit left" bar. Missing or non-weekly => n/a.
        if (-not $ptype -or ($ptype -notmatch 'WEEKLY')) { return $null }
        $usedRaw = $cfg.creditUsagePercent
        if ($null -eq $usedRaw -or [string]::IsNullOrWhiteSpace([string]$usedRaw)) { return $null }
        $used = [double]$usedRaw
        if ($used -lt 0 -or $used -gt 100) { return $null }
        $remain = [int][math]::Round(100.0 - $used)
        if ($remain -lt 0) { $remain = 0 }
        if ($remain -gt 100) { $remain = 100 }
        $periodEnd = $null
        if ($cfg.currentPeriod -and $cfg.currentPeriod.end) { $periodEnd = [string]$cfg.currentPeriod.end }
        return [pscustomobject]@{
            remaining_pct = $remain
            used_pct      = [int][math]::Round($used)
            fetched_at    = [string]$j.ts
            period_end    = $periodEnd
            source        = 'unified.jsonl:billing: fetched credits config'
            kind          = 'weekly'
        }
    }
    catch { return $null }
}

function Test-BobTrayRemainingKnown {
    param($RemainingPct)
    if ($null -eq $RemainingPct) { return $false }
    if (($RemainingPct -is [string]) -and [string]::IsNullOrWhiteSpace([string]$RemainingPct)) { return $false }
    return $true
}

function Get-BobTrayBarFillRgb {
    param([int]$Pct)
    if ($Pct -lt 0) { $Pct = 0 }
    if ($Pct -gt 100) { $Pct = 100 }
    # 0 = red, 50 = amber, 100 = green.
    $red = @{ r = 248; g = 81; b = 73 }
    $amber = @{ r = 210; g = 153; b = 34 }
    $green = @{ r = 63; g = 185; b = 80 }
    if ($Pct -ge 50) {
        $t = ($Pct - 50) / 50.0
        $a = $amber; $b = $green
    }
    else {
        $t = $Pct / 50.0
        $a = $red; $b = $amber
    }
    return [pscustomobject]@{
        r = [int][math]::Round($a.r + ($b.r - $a.r) * $t)
        g = [int][math]::Round($a.g + ($b.g - $a.g) * $t)
        b = [int][math]::Round($a.b + ($b.b - $a.b) * $t)
    }
}

function Get-BobTrayBarPaint {
    [CmdletBinding()]
    param(
        $RemainingPct,
        [int]$BarWidth = 392
    )
    if (-not (Test-BobTrayRemainingKnown $RemainingPct)) {
        return [pscustomobject]@{
            remaining_pct = $null
            known         = $false
            show_track    = $false
            show_fill     = $false
            fill_width    = $null
            fill_r        = $null
            fill_g        = $null
            fill_b        = $null
            caption       = 'Weekly remaining  n/a'
            pulse         = $false
            kind          = 'unknown'
        }
    }
    $pct = [int]$RemainingPct
    if ($pct -lt 0) { $pct = 0 }
    if ($pct -gt 100) { $pct = 100 }
    $inner = [math]::Max(0, $BarWidth - 2)
    $w = [int]($inner * $pct / 100)
    if ($w -lt 8 -and $pct -gt 0) { $w = 8 }
    if ($pct -eq 0) { $w = 0 }
    $rgb = Get-BobTrayBarFillRgb -Pct $pct
    return [pscustomobject]@{
        remaining_pct = $pct
        known         = $true
        show_track    = $true
        show_fill     = ($w -gt 0)
        fill_width    = $w
        fill_r        = [int]$rgb.r
        fill_g        = [int]$rgb.g
        fill_b        = [int]$rgb.b
        caption       = ('Weekly remaining    {0}%' -f $pct)
        pulse         = ($pct -lt 10)
        kind          = 'weekly'
    }
}

function Get-BobTrayAlertKind {
    [CmdletBinding()]
    param(
        [string[]]$Alerts,
        $RemainingPct
    )
    foreach ($a in @($Alerts)) {
        if (-not $a) { continue }
        if ($a -match 'watcher_down') { return 'watcher' }
        if ($a -match 'agent_stall') { return 'stall' }
        if ($a -match 'ACTION_REQUIRED') { return 'stall' }
    }
    $paint = Get-BobTrayBarPaint -RemainingPct $RemainingPct
    if ($paint.pulse) { return 'weekly' }
    return 'none'
}

function Get-BobTrayTitle {
    return 'Bob Fleet'
}

function Get-BobTrayRepoLabel {
    param($Job, [switch]$SkipGit)
    if ($Job -and $Job.repo) {
        $r = [string]$Job.repo
        if ($r -and $r.Trim() -and $r.Trim() -ne '?' -and -not (Test-BobTrayLooksLikeSha $r)) {
            return $r.Trim()
        }
    }
    $cwd = $null
    if ($Job) { $cwd = [string]$Job.cwd }
    if (-not $SkipGit -and $cwd) {
        $slug = Get-GitHubSlugFromCwd $cwd
        if ($slug -and $slug -ne '?' -and -not (Test-BobTrayLooksLikeSha $slug)) { return $slug }
    }
    if ($cwd) {
        try {
            $leaf = Split-Path $cwd -Leaf
            if ($leaf -and -not (Test-BobTrayLooksLikeSha $leaf)) { return $leaf }
        }
        catch { }
    }
    return '?'
}

function ConvertTo-BobTrayJobRow {
    param($Job, [string]$DefaultMachine, [string]$State, [switch]$SkipGit)
    $id = [string]$Job.id
    $sid = $id
    if ($Job.sessionId) { $sid = [string]$Job.sessionId }
    $ctx = $null
    if (-not $SkipGit) {
        $ctx = Get-SessionContextRemaining -Cwd $Job.cwd -SessionId $sid
    }
    $mac = [string]$Job.machine
    if (-not $mac) { $mac = $DefaultMachine }
    $when = $Job.claimedAt
    if (-not $when) { $when = $Job.createdAt }
    $st = $State
    if (-not $st) {
        if ($Job.state) { $st = [string]$Job.state } else { $st = 'running' }
    }
    $repo = Get-BobTrayRepoLabel -Job $Job -SkipGit:$SkipGit
    if (Test-BobTrayLooksLikeSha $repo) { $repo = '?' }
    return [pscustomobject]@{
        id                     = $id
        id8                    = $(if ($id.Length -ge 8) { $id.Substring(0, 8) } else { $id })
        machine                = $mac
        repo                   = $repo
        duration               = Get-BobJobAge $when
        state                  = $st
        cwd                    = [string]$Job.cwd
        context_remaining_pct  = $(if ($ctx) { [int]$ctx.remaining_pct } else { $null })
    }
}

function Get-BobTrayHover {
    $tier = '?'
    try {
        $path = Join-Path $env:USERPROFILE '.grok\settings_cache.json'
        if (Test-Path $path) {
            $wrap = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $payload = $wrap.payload
            if ($payload -is [string]) { $payload = $payload | ConvertFrom-Json }
            $t = [string]$payload.settings.subscription_tier_display
            if ($t -match 'Premium') { $tier = 'P+' }
            elseif ($t -match 'SuperGrok') { $tier = 'SG' }
            elseif ($t) { $tier = $t }
            if ($tier.Length -gt 8) { $tier = $tier.Substring(0, 8) }
        }
    }
    catch { }

    $machineId = $null
    try { $machineId = Get-ThisMachineId } catch { }
    if (-not $machineId) { $machineId = 'this-machine' }
    $title = Get-BobTrayTitle

    $running = @()
    $queuedJobs = @()
    try { $running = @(Get-BobBuilds -Lane running -ErrorAction SilentlyContinue) } catch { }
    try { $queuedJobs = @(Get-BobBuilds -Lane inbox -ErrorAction SilentlyContinue) } catch { }
    $queued = @($queuedJobs).Count

    $jobs = @()
    $localIds = @{}
    foreach ($b in $running) {
        $row = ConvertTo-BobTrayJobRow -Job $b -DefaultMachine $machineId -State $(if ($b.state) { [string]$b.state } else { 'running' })
        $jobs += ,$row
        if ($row.id) { $localIds[$row.id] = $true }
    }
    foreach ($b in $queuedJobs) {
        $row = ConvertTo-BobTrayJobRow -Job $b -DefaultMachine $machineId -State 'queued'
        $jobs += ,$row
        if ($row.id) { $localIds[$row.id] = $true }
    }

    $reg = $null
    try { $reg = Get-BobFleetRegistry } catch { }
    $staleAfter = 900
    $peekMs = 1500
    $shareRoot = $null
    if ($reg) {
        if ($reg.staleAfterSec) { $staleAfter = [int]$reg.staleAfterSec }
        if ($reg.peekTimeoutMs) { $peekMs = [int]$reg.peekTimeoutMs }
        if ($reg.shareRoot) { $shareRoot = [string]$reg.shareRoot }
    }

    $byMachine = @{}
    $reachBy = @{}
    $seenBy = @{}
    $specBy = @{}
    if ($reg) {
        foreach ($m in @($reg.machines)) {
            $mid = [string]$m.id
            if (-not $mid) { continue }
            if (-not $byMachine.ContainsKey($mid)) { $byMachine[$mid] = @() }
            $specBy[$mid] = $m
        }
    }
    if (-not $byMachine.ContainsKey($machineId)) {
        $byMachine[$machineId] = @()
    }
    $reachBy[$machineId] = 'local'
    $weeklyBy = @{}
    $week = Get-BobWeeklyRemaining
    $remainPct = $null
    $weekFetched = $null
    if ($week -and (Test-BobTrayRemainingKnown $week.remaining_pct)) {
        $remainPct = [int]$week.remaining_pct
        $weekFetched = [string]$week.fetched_at
        $weeklyBy[$machineId] = $remainPct
    }

    $moot = $null
    try { $moot = Get-BobMootRoster } catch { $moot = $null }

    foreach ($j in $jobs) {
        $mid = [string]$j.machine
        if (-not $mid) { $mid = $machineId }
        if (-not $byMachine.ContainsKey($mid)) {
            $byMachine[$mid] = @()
        }
        $byMachine[$mid] += ,$j
        if ($mid -ne $machineId -and -not $reachBy.ContainsKey($mid)) {
            $reachBy[$mid] = 'ok'
        }
    }

    foreach ($mid in @($byMachine.Keys)) {
        if ($mid -eq $machineId) { continue }
        if (@($byMachine[$mid]).Count -gt 0) { continue }
        $spec = $null
        if ($specBy.ContainsKey($mid)) { $spec = $specBy[$mid] }
        else { $spec = [pscustomobject]@{ id = $mid } }
        $peek = $null
        try {
            $peek = Read-BobPeerPeek -Id $mid -Spec $spec -ShareRoot $shareRoot -TimeoutMs $peekMs
        }
        catch { $peek = $null }
        $inMoot = $false
        try { $inMoot = [bool](Test-BobMachineInMoot -MachineId $mid -Roster $moot) } catch { $inMoot = $false }
        if (-not $peek -or -not $peek.ok) {
            if ($inMoot) { $reachBy[$mid] = 'irc-fallback' }
            else { $reachBy[$mid] = 'not-in-moot' }
            continue
        }
        if ($peek.lastSeen) { $seenBy[$mid] = [string]$peek.lastSeen }
        if ($null -ne $peek.weekly -and (Test-BobTrayRemainingKnown $peek.weekly)) {
            $weeklyBy[$mid] = [int]$peek.weekly
        }
        $peerJobs = @()
        if ($peek.jobs) { foreach ($one in $peek.jobs) { $peerJobs += $one } }
        foreach ($pj in $peerJobs) {
            if ($pj.id -and $localIds.ContainsKey([string]$pj.id)) { continue }
            $st = [string]$pj.state
            if (-not $st) { $st = 'running' }
            $byMachine[$mid] += ,(ConvertTo-BobTrayJobRow -Job $pj -DefaultMachine $mid -State $st -SkipGit)
        }
        $age = Get-BobLastSeenAgeSec -Record ([pscustomobject]@{ lastSeen = $peek.lastSeen })
        $empty = (@($byMachine[$mid]).Count -eq 0)
        $fromIrc = ([string]$peek.source -eq 'irc')
        if ($empty -and ($null -eq $age -or $age -gt $staleAfter)) {
            $reachBy[$mid] = 'stale'
        }
        elseif (-not $empty -and $null -ne $age -and $age -gt $staleAfter) {
            $reachBy[$mid] = 'stale'
        }
        elseif ($fromIrc) {
            $reachBy[$mid] = 'irc-fallback'
        }
        elseif ($inMoot) {
            $reachBy[$mid] = 'irc-fallback'
        }
        else {
            $reachBy[$mid] = 'ok'
        }
    }

    $order = @()
    if ($byMachine.ContainsKey($machineId)) { $order += $machineId }
    foreach ($k in ($byMachine.Keys | Sort-Object)) {
        if ($k -ne $machineId) { $order += $k }
    }

    $tiles = @()
    $jobLines = @()
    foreach ($mid in $order) {
        $rows = @($byMachine[$mid])
        if ($rows.Count -gt 1) {
            $rows = @(
                $rows | Sort-Object -Property @{
                    Expression = {
                        switch ([string]$_.state) {
                            'running' { 0 }
                            'queued' { 1 }
                            default { 2 }
                        }
                    }
                }
            )
        }
        $reach = 'ok'
        if ($reachBy.ContainsKey($mid)) { $reach = [string]$reachBy[$mid] }
        $wPct = $null
        if ($weeklyBy.ContainsKey($mid)) { $wPct = $weeklyBy[$mid] }
        $tile = New-Object psobject -Property @{
            id             = $mid
            job_count      = $rows.Count
            jobs           = $rows
            reach          = $reach
            last_seen      = $(if ($seenBy.ContainsKey($mid)) { $seenBy[$mid] } else { $null })
            remaining_pct  = $wPct
        }
        $tiles += ,$tile
        $pctLabel = 'n/a'
        if ($null -ne $wPct) { $pctLabel = ('{0}%' -f [int]$wPct) }
        $jobLines += ('  {0} ({1})' -f $mid, $pctLabel)
        if ($reach -eq 'not-in-moot' -or $reach -eq 'unreachable') {
            $jobLines += '    not in moot'
        }
        elseif ($rows.Count -eq 0) {
            if ($reach -eq 'stale') { $jobLines += '    lastSeen stale' }
            else { $jobLines += '    no jobs' }
        }
        else {
            if ($reach -eq 'stale') { $jobLines += '    lastSeen stale' }
            foreach ($j in $rows) {
                $jobLines += ('    {0}  {1}  {2}' -f $j.repo, $j.duration, $j.state)
            }
        }
    }
    $peerPeek = $order.Count -gt 1
    if (-not $peerPeek) {
        $jobLines += 'other hosts not in this store'
    }
    $acctPctLabel = 'n/a'
    if ($null -ne $remainPct) { $acctPctLabel = ('{0}%' -f [int]$remainPct) }
    $acctLine = ('cursor ({0})' -f $acctPctLabel)
    $jobsText = ($acctLine + "`n" + ($jobLines -join "`n"))

    $lines = New-Object System.Collections.Generic.List[string]
    if ($null -eq $remainPct) {
        $lines.Add(('{0}  weekly remaining  n/a' -f $tier))
        $short = '{0} {1} run' -f $tier, @($running).Count
    }
    else {
        $lines.Add(('{0}  weekly remaining  {1}%' -f $tier, $remainPct))
        $short = '{0} {1} run  {2}%' -f $tier, @($running).Count, $remainPct
    }
    foreach ($jl in $jobLines) { $lines.Add($jl) }
    if (@($running).Count -eq 0) {
        if ($null -eq $remainPct) { $short = '{0} idle' -f $tier }
        else { $short = '{0} idle  {1}%' -f $tier, $remainPct }
    }
    if ($short.Length -gt 63) { $short = $short.Substring(0, 63) }

    return [pscustomobject]@{
        title          = $title
        machine        = $machineId
        scope          = $(if ($peerPeek) { 'fleet-peek' } else { 'local-store' })
        short          = $short
        body           = ($lines -join "`n")
        jobs_text      = $jobsText
        remaining_pct  = $remainPct
        remaining_kind = 'weekly'
        weekly_fetched_at = $weekFetched
        job_count      = @($running).Count
        queued         = $queued
        jobs           = @($jobs)
        machines       = $tiles
        peer_peek      = $peerPeek
        tier           = $tier
        account_name   = 'cursor'
        account_remaining_pct = $remainPct
    }
}

function Get-BobPointCoord {
    param($Value, [string[]]$Names, $Default = 0)
    if ($null -eq $Value) { return $Default }
    foreach ($n in $Names) {
        $v = $null
        $found = $false
        if ($Value -is [System.Collections.IDictionary]) {
            foreach ($k in @($Value.Keys)) {
                if ([string]$k -ceq $n -or [string]$k -eq $n) {
                    $v = $Value[$k]
                    $found = $true
                    break
                }
            }
        }
        if (-not $found) {
            $p = $Value.PSObject.Properties[$n]
            if ($p) {
                $v = $p.Value
                $found = $true
            }
        }
        if (-not $found) {
            try {
                $v = $Value.$n
                if ($null -ne $v) { $found = $true }
            }
            catch { }
        }
        if ($found -and $null -ne $v -and "$v" -ne '') {
            try { return [int]$v } catch { }
        }
    }
    return $Default
}

function ConvertTo-BobTrayRect {
    param($Value)
    if ($null -eq $Value) { return $null }
    $x = Get-BobPointCoord $Value @('X', 'x', 'Left', 'left') -Default $null
    $y = Get-BobPointCoord $Value @('Y', 'y', 'Top', 'top') -Default $null
    $w = Get-BobPointCoord $Value @('Width', 'width') -Default $null
    $h = Get-BobPointCoord $Value @('Height', 'height') -Default $null
    if ($null -eq $w) {
        $right = Get-BobPointCoord $Value @('Right', 'right') -Default $null
        if ($null -ne $right -and $null -ne $x) { $w = $right - $x }
    }
    if ($null -eq $h) {
        $bottom = Get-BobPointCoord $Value @('Bottom', 'bottom') -Default $null
        if ($null -ne $bottom -and $null -ne $y) { $h = $bottom - $y }
    }
    if ($null -eq $x -or $null -eq $y -or $null -eq $w -or $null -eq $h) { return $null }
    if ($w -le 0 -or $h -le 0) { return $null }
    return [pscustomobject]@{
        X      = [int]$x
        Y      = [int]$y
        Width  = [int]$w
        Height = [int]$h
        Right  = [int]($x + $w)
        Bottom = [int]($y + $h)
    }
}

function Get-BobTrayTipPlacement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$TipWidth,
        [Parameter(Mandatory = $true)][int]$TipHeight,
        $IconRect,
        $Cursor,
        $WorkArea,
        [bool]$AlreadyVisible = $false,
        [int]$CurrentX = 0,
        [int]$CurrentY = 0,
        [int]$Gap = 12,
        [int]$Margin = 8
    )
    if ($AlreadyVisible) {
        return [pscustomobject]@{
            x      = [int]$CurrentX
            y      = [int]$CurrentY
            source = 'sticky'
            moved  = $false
        }
    }

    $icon = ConvertTo-BobTrayRect $IconRect
    $work = ConvertTo-BobTrayRect $WorkArea
    $cx = Get-BobPointCoord $Cursor @('X', 'x')
    $cy = Get-BobPointCoord $Cursor @('Y', 'y')
    $source = 'cursor'
    $x = $cx - $TipWidth
    $y = $cy - $TipHeight - $Gap

    if ($icon) {
        $source = 'icon'
        $workLeft = 0
        $workTop = 0
        $workRight = 0
        $workBottom = 0
        if ($work) {
            $workLeft = $work.X
            $workTop = $work.Y
            $workRight = $work.Right
            $workBottom = $work.Bottom
        }
        $fromBottom = $false
        $fromTop = $false
        $fromLeft = $false
        $fromRight = $false
        if ($work) {
            $fromBottom = ($icon.Bottom -ge ($workBottom - 2))
            $fromTop = ($icon.Y -le ($workTop + 2))
            $fromLeft = ($icon.Right -le ($workLeft + 2))
            $fromRight = ($icon.X -ge ($workRight - 2))
        }
        if ($fromTop -and -not $fromBottom) {
            $x = $icon.Right - $TipWidth
            $y = $icon.Bottom + $Gap
        }
        elseif ($fromLeft -and -not $fromRight -and -not $fromBottom) {
            $x = $icon.Right + $Gap
            $y = $icon.Bottom - $TipHeight
        }
        elseif ($fromRight -and -not $fromBottom) {
            $x = $icon.X - $TipWidth - $Gap
            $y = $icon.Bottom - $TipHeight
        }
        else {
            $x = $icon.Right - $TipWidth
            $y = $icon.Y - $TipHeight - $Gap
        }
    }

    if ($work) {
        $maxX = $work.Right - $TipWidth - $Margin
        $maxY = $work.Bottom - $TipHeight - $Margin
        $minX = $work.X + $Margin
        $minY = $work.Y + $Margin
        if ($maxX -lt $minX) { $maxX = $minX }
        if ($maxY -lt $minY) { $maxY = $minY }
        if ($x -gt $maxX) { $x = $maxX }
        if ($y -gt $maxY) { $y = $maxY }
        if ($x -lt $minX) { $x = $minX }
        if ($y -lt $minY) { $y = $minY }
    }
    else {
        if ($x -lt $Margin) { $x = $Margin }
        if ($y -lt $Margin) { $y = $Margin }
    }

    return [pscustomobject]@{
        x      = [int]$x
        y      = [int]$y
        source = $source
        moved  = $true
    }
}
