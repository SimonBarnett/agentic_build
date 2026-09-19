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
    if (Test-Path $Cwd) { return Split-Path $Cwd -Leaf }
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

function Get-BobTrayHover {
    # Occupancy remaining = free worker slots / max. Token remainder is not exposed by grok CLI.
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

    $max = 2
    try {
        $root = $null
        if ($MyInvocation.MyCommand.Module) {
            $root = Split-Path $MyInvocation.MyCommand.Module.ModuleBase -Parent
        }
        foreach ($c in @($root, 'C:\ai\agentic_build', 'D:\ai\agentic_build', 'C:\src\agentic_build')) {
            if (-not $c) { continue }
            $cfgPath = Join-Path $c 'config\default.json'
            if (Test-Path $cfgPath) {
                $cobj = Get-Content $cfgPath -Raw | ConvertFrom-Json
                if ($cobj.max_workers_per_machine) { $max = [int]$cobj.max_workers_per_machine }
                break
            }
        }
    }
    catch { }

    $running = @()
    $queued = 0
    $mid = $env:BOB_MACHINE_ID
    try {
        if ($mid) { $running = @(Get-BobBuilds -Lane running -Machine $mid -ErrorAction SilentlyContinue) }
        else { $running = @(Get-BobBuilds -Lane running -ErrorAction SilentlyContinue) }
    } catch { }
    try {
        if ($mid) { $queued = @(Get-BobBuilds -Lane inbox -Machine $mid -ErrorAction SilentlyContinue).Count }
        else { $queued = @(Get-BobBuilds -Lane inbox -ErrorAction SilentlyContinue).Count }
    } catch { }

    $jobs = @()
    foreach ($b in $running) {
        $id = [string]$b.id
        $jobs += [pscustomobject]@{
            id       = $id
            id8      = $(if ($id.Length -ge 8) { $id.Substring(0, 8) } else { $id })
            repo     = Get-GitHubSlugFromCwd $b.cwd
            duration = Get-BobJobAge $b.claimedAt
            state    = $(if ($b.state) { [string]$b.state } else { 'running' })
            cwd      = [string]$b.cwd
        }
    }

    $runN = $jobs.Count
    $remainPct = 0
    if ($max -gt 0) {
        $remainPct = [int][math]::Round(100.0 * [math]::Max(0, $max - $runN) / $max)
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('{0}  remaining {1}%  (slots {2}/{3}  q:{4})' -f $tier, $remainPct, $runN, $max, $queued))
    if ($jobs.Count -eq 0) {
        $lines.Add('no fleet jobs running')
        $short = '{0} idle  {1}% slots' -f $tier, $remainPct
    }
    else {
        foreach ($j in $jobs) {
            $lines.Add(('{0}  {1}  {2}  {3}' -f $j.id8, $j.repo, $j.duration, $j.state))
        }
        $short = '{0} {1} run  {2}% left' -f $tier, $jobs.Count, $remainPct
    }
    if ($short.Length -gt 63) { $short = $short.Substring(0, 63) }

    return [pscustomobject]@{
        short          = $short
        body           = ($lines -join [Environment]::NewLine)
        remaining_pct  = $remainPct
        remaining_kind = 'worker_slots'
        job_count      = $jobs.Count
        jobs           = $jobs
        tier           = $tier
    }
}
