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
        if (-not $mac) { $mac = '?' }
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
        $lines.Add(('{0}  context remaining  --' -f $tier))
        $short = '{0} {1} run' -f $tier, $jobs.Count
    }
    else {
        $lines.Add(('{0}  context remaining  {1}%' -f $tier, $remainPct))
        $short = '{0} {1} run  {2}%' -f $tier, $jobs.Count, $remainPct
    }
    if ($jobs.Count -eq 0) {
        $lines.Add('no fleet jobs running')
        if ($null -eq $remainPct) { $short = '{0} idle' -f $tier }
        else { $short = '{0} idle  {1}%' -f $tier, $remainPct }
    }
    else {
        foreach ($j in $jobs) {
            $rp = if ($null -eq $j.remaining_pct) { '--' } else { '{0}%' -f $j.remaining_pct }
            $lines.Add(('{0}  {1}  {2}  {3}  {4}  ctx {5}' -f $j.machine, $j.id8, $j.repo, $j.duration, $j.state, $rp))
        }
    }
    if ($queued -gt 0) { $lines.Add(('queued {0}' -f $queued)) }
    if ($short.Length -gt 63) { $short = $short.Substring(0, 63) }

    return [pscustomobject]@{
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
