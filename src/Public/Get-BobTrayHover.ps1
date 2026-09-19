function Get-GitHubSlugFromCwd {
    param([string]$Cwd)
    if (-not $Cwd) { return '?' }
    try {
        if (Get-Command git -ErrorAction SilentlyContinue) {
            $url = & git -C $Cwd remote get-url origin 2>$null
            if ($url -match 'github\.com[:/](.+?)(?:\.git)?\s*$') { return $Matches[1].Trim() }
            if ($url) { return ([string]$url).Trim() }
        }
    }
    catch { }
    if ($Cwd -and (Test-Path $Cwd)) { return Split-Path $Cwd -Leaf }
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

function Test-BobTrayRemainingKnown {
    param($RemainingPct)
    if ($null -eq $RemainingPct) { return $false }
    if (($RemainingPct -is [string]) -and [string]::IsNullOrWhiteSpace([string]$RemainingPct)) { return $false }
    return $true
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
            caption       = 'Context remaining  n/a'
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
    return [pscustomobject]@{
        remaining_pct = $pct
        known         = $true
        show_track    = $true
        show_fill     = ($w -gt 0)
        fill_width    = $w
        caption       = ('Context remaining    {0}%' -f $pct)
        pulse         = ($pct -lt 10)
        kind          = 'known'
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
    if ($paint.pulse) { return 'context' }
    return 'none'
}

function Get-BobTrayTitle {
    $id = $null
    try { $id = Get-ThisMachineId } catch { }
    if (-not $id) { $id = 'this-machine' }
    return ('Bob ({0})' -f $id)
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
    $title = 'Bob ({0})' -f $machineId

    $running = @()
    $queued = 0
    try { $running = @(Get-BobBuilds -Lane running -ErrorAction SilentlyContinue) } catch { }
    try { $queued = @(Get-BobBuilds -Lane inbox -ErrorAction SilentlyContinue).Count } catch { }

    $jobs = @()
    $remainings = @()
    foreach ($b in $running) {
        $id = [string]$b.id
        $sid = $id
        if ($b.sessionId) { $sid = [string]$b.sessionId }
        $ctx = Get-SessionContextRemaining -Cwd $b.cwd -SessionId $sid
        if ($ctx) { $remainings += [int]$ctx.remaining_pct }
        $mac = [string]$b.machine
        if (-not $mac) { $mac = $machineId }
        $jobs += [pscustomobject]@{
            id            = $id
            id8           = $(if ($id.Length -ge 8) { $id.Substring(0, 8) } else { $id })
            machine       = $mac
            repo          = Get-GitHubSlugFromCwd $b.cwd
            duration      = Get-BobJobAge $b.claimedAt
            state         = $(if ($b.state) { [string]$b.state } else { 'running' })
            cwd           = [string]$b.cwd
            remaining_pct = $(if ($ctx) { [int]$ctx.remaining_pct } else { $null })
        }
    }

    $remainPct = $null
    if ($remainings.Count -gt 0) {
        $remainPct = ($remainings | Measure-Object -Minimum).Minimum
    }

    $lines = New-Object System.Collections.Generic.List[string]
    if ($null -eq $remainPct) {
        $lines.Add(('{0}  context remaining  n/a' -f $tier))
        $short = '{0} {1} run' -f $tier, $jobs.Count
    }
    else {
        $lines.Add(('{0}  context remaining  {1}%' -f $tier, $remainPct))
        $short = '{0} {1} run  {2}%' -f $tier, $jobs.Count, $remainPct
    }
    if ($jobs.Count -eq 0) {
        $lines.Add('no jobs on this machine')
        if ($null -eq $remainPct) { $short = '{0} idle' -f $tier }
        else { $short = '{0} idle  {1}%' -f $tier, $remainPct }
    }
    else {
        foreach ($j in $jobs) {
            $rp = if ($null -eq $j.remaining_pct) { 'n/a' } else { '{0}%' -f $j.remaining_pct }
            $lines.Add(('{0}  {1}  {2}  {3}  {4}  ctx {5}' -f $j.machine, $j.id8, $j.repo, $j.duration, $j.state, $rp))
        }
    }
    if ($queued -gt 0) { $lines.Add(('queued {0}' -f $queued)) }
    if ($short.Length -gt 63) { $short = $short.Substring(0, 63) }

    return [pscustomobject]@{
        title          = $title
        machine        = $machineId
        scope          = 'this-machine'
        short          = $short
        body           = ($lines -join [Environment]::NewLine)
        remaining_pct  = $remainPct
        remaining_kind = 'context'
        job_count      = $jobs.Count
        queued         = $queued
        jobs           = $jobs
        tier           = $tier
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
