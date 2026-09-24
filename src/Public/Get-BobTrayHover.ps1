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

function ConvertTo-BobCursorUsageDoc {
    param($j)
    if (-not $j) { return $null }
    $remain = $null
    $used = $null
    $overGbp = $null
    $overUsd = $null
    $cents = $null
    # remaining_pct / used_pct are Spending Cursor Models (not Sand).
    if ($null -ne $j.remaining_pct -and [string]$j.remaining_pct -ne '') {
        $remain = [int]$j.remaining_pct
    }
    if ($null -ne $j.used_pct -and [string]$j.used_pct -ne '') { $used = [double]$j.used_pct }
    if ($null -eq $used) {
        if ($null -ne $j.percentUsed) { $used = [double]$j.percentUsed }
        elseif ($null -ne $j.creditUsagePercent) { $used = [double]$j.creditUsagePercent }
    }
    if ($null -eq $remain -and $null -ne $used) {
        $remain = [int][math]::Round(100.0 - [double]$used)
    }
    # Legacy: usagePercent without used_pct was Sand — do not map to Cursor Models remaining.
    if ($null -ne $j.overage_gbp -and [string]$j.overage_gbp -ne '') { $overGbp = [double]$j.overage_gbp }
    if ($null -ne $j.overage_usd -and [string]$j.overage_usd -ne '') { $overUsd = [double]$j.overage_usd }
    if ($null -ne $j.on_demand_used_cents -and [string]$j.on_demand_used_cents -ne '') { $cents = [int]$j.on_demand_used_cents }
    $odLimit = $null
    $odRemain = $null
    $odUsedPct = $null
    if ($null -ne $j.on_demand_limit_cents -and [string]$j.on_demand_limit_cents -ne '') {
        try { $odLimit = [int]$j.on_demand_limit_cents } catch { }
    }
    if ($null -ne $j.on_demand_remaining_pct -and [string]$j.on_demand_remaining_pct -ne '') {
        try { $odRemain = [int]$j.on_demand_remaining_pct } catch { }
    }
    if ($null -ne $j.on_demand_used_pct -and [string]$j.on_demand_used_pct -ne '') {
        try { $odUsedPct = [int]$j.on_demand_used_pct } catch { }
    }
    if ($null -eq $remain -and $null -eq $used -and $null -eq $overGbp -and $null -eq $overUsd -and $null -eq $odRemain) { return $null }
    if ($null -ne $remain) {
        if ($remain -lt 0) { $remain = 0 }
        if ($remain -gt 100) { $remain = 100 }
    }
    if ($null -eq $used -and $null -ne $remain) { $used = 100 - $remain }
    $periodEnd = $null
    if ($j.period_end) { $periodEnd = [string]$j.period_end }
    $sandUsed = $null
    $sandRemain = $null
    $sandExhausted = $null
    $sandPeriodEnd = $null
    if ($null -ne $j.sand_used_pct -and [string]$j.sand_used_pct -ne '') { $sandUsed = [int]$j.sand_used_pct }
    if ($null -ne $j.sand_remaining_pct -and [string]$j.sand_remaining_pct -ne '') { $sandRemain = [int]$j.sand_remaining_pct }
    if ($null -ne $j.sand_exhausted -and [string]$j.sand_exhausted -ne '') {
        try { $sandExhausted = [bool]$j.sand_exhausted } catch { $sandExhausted = $null }
    }
    if ($j.sand_period_end) { $sandPeriodEnd = [string]$j.sand_period_end }
    $spendGroups = @()
    if ($j.cursor_spending_groups) {
        foreach ($g in @($j.cursor_spending_groups)) {
            if (-not $g) { continue }
            $spendGroups += ,[pscustomobject]@{
                id             = $(if ($g.id) { [string]$g.id } else { $null })
                label          = $(if ($g.label) { [string]$g.label } else { $null })
                used_pct       = $(if ($null -ne $g.used_pct -and [string]$g.used_pct -ne '') { [int]$g.used_pct } else { $null })
                remaining_pct  = $(if ($null -ne $g.remaining_pct -and [string]$g.remaining_pct -ne '') { [int]$g.remaining_pct } else { $null })
                source         = $(if ($g.source) { [string]$g.source } else { $null })
            }
        }
    }
    return [pscustomobject]@{
        remaining_pct = $(if ($null -eq $remain) { $null } else { [int]$remain })
        used_pct      = $(if ($null -eq $used) { $null } else { [int][math]::Round([double]$used) })
        cursor_spending_groups = @($spendGroups)
        overage_gbp   = $overGbp
        overage_usd   = $overUsd
        on_demand_used_cents = $cents
        on_demand_limit_cents = $odLimit
        on_demand_remaining_pct = $odRemain
        on_demand_used_pct = $odUsedPct
        on_demand_enabled = $(if ($null -ne $j.on_demand_enabled -and [string]$j.on_demand_enabled -ne '') { [bool]$j.on_demand_enabled } else { $null })
        bonus_spend_cents = $(if ($null -ne $j.bonus_spend_cents -and [string]$j.bonus_spend_cents -ne '') { [int]$j.bonus_spend_cents } else { $null })
        remaining_bonus = $(if ($null -ne $j.remaining_bonus -and [string]$j.remaining_bonus -ne '') { [bool]$j.remaining_bonus } else { $null })
        bonus_tooltip = $(if ($j.bonus_tooltip) { [string]$j.bonus_tooltip } else { $null })
        overage_source = $(if ($j.overage_source) { [string]$j.overage_source } else { $null })
        period_end    = $periodEnd
        sand_used_pct = $sandUsed
        sand_remaining_pct = $sandRemain
        sand_exhausted = $sandExhausted
        sand_period_end = $sandPeriodEnd
        source        = 'cursor-agent'
        kind          = 'weekly'
    }
}

function ConvertTo-BobCursorSpendingPctPoints {
    param($Raw)
    if ($null -eq $Raw -or [string]$Raw -eq '') { return $null, $null }
    try {
        $usedF = [double]$Raw
        $usedI = [int][math]::Round($usedF)
        $remain = [int][math]::Round(100.0 - $usedF)
        return $usedI, $remain
    }
    catch { return $null, $null }
}

function ConvertTo-BobCursorSandPct {
    param($Raw)
    if ($null -eq $Raw -or [string]$Raw -eq '') { return $null, $null }
    try {
        $usedF = [double]$Raw
        if ($usedF -ge 0.0 -and $usedF -le 1.0) { $usedF = $usedF * 100.0 }
        $usedI = [int][math]::Round($usedF)
        $remain = [int][math]::Round(100.0 - $usedF)
        return $usedI, $remain
    }
    catch { return $null, $null }
}

function Get-BobCursorSpendingFromApiFixture {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) { return $null }
    try {
        $fix = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch { return $null }
    $period = $fix.period
    $sand = $fix.sand
    $pu = $null
    if ($period -and $period.planUsage) { $pu = $period.planUsage }
    $autoUsed = $autoRemain = $apiUsed = $apiRemain = $null
    if ($pu) {
        $autoUsed, $autoRemain = ConvertTo-BobCursorSpendingPctPoints $pu.autoPercentUsed
        $apiUsed, $apiRemain = ConvertTo-BobCursorSpendingPctPoints $pu.apiPercentUsed
    }
    $sandUsed = $sandRemain = $null
    if ($sand) {
        $sandRaw = $sand.usagePercent
        if ($null -eq $sandRaw -or [string]$sandRaw -eq '') { $sandRaw = $sand.percentUsed }
        $sandUsed, $sandRemain = ConvertTo-BobCursorSandPct $sandRaw
    }
    $groups = @(
        [pscustomobject]@{ id = 'grok-chat'; label = 'grok chat'; used_pct = $sandUsed; remaining_pct = $sandRemain; source = 'GetSandUsageStatus.usagePercent' }
        [pscustomobject]@{ id = 'high-cost-models'; label = 'high cost models'; used_pct = $apiUsed; remaining_pct = $apiRemain; source = 'GetCurrentPeriodUsage.planUsage.apiPercentUsed' }
        [pscustomobject]@{ id = 'auto'; label = 'auto'; used_pct = $autoUsed; remaining_pct = $autoRemain; source = 'GetCurrentPeriodUsage.planUsage.autoPercentUsed' }
    )
    $periodEnd = $null
    if ($period -and $period.billingCycleEnd) { $periodEnd = [string]$period.billingCycleEnd }
    $cents = $null
    $limitCents = $null
    if ($period -and $period.spendLimitUsage) {
        if ($null -ne $period.spendLimitUsage.individualUsed) {
            try { $cents = [int][math]::Round([double]$period.spendLimitUsage.individualUsed) } catch { }
        }
        if ($null -ne $period.spendLimitUsage.individualLimit) {
            try { $limitCents = [int][math]::Round([double]$period.spendLimitUsage.individualLimit) } catch { }
        }
    }
    $overageUsd = $overageGbp = $null
    if ($null -ne $cents) {
        $overageUsd = [math]::Round($cents / 100.0, 2)
        $rateEnv = [string]$env:BOB_CURSOR_USD_GBP_RATE
        if ($rateEnv) {
            try {
                $rate = [double]$rateEnv
                if ($rate -gt 0) { $overageGbp = [math]::Round($overageUsd * $rate, 2) }
            }
            catch { }
        }
    }
    $out = [ordered]@{
        ok                     = $true
        source                 = 'cursor-agent'
        kind                   = 'weekly'
        used_pct               = $autoUsed
        remaining_pct          = $autoRemain
        cursor_models_source   = 'GetCurrentPeriodUsage.planUsage.autoPercentUsed'
        sand_used_pct          = $sandUsed
        sand_remaining_pct     = $sandRemain
        cursor_spending_groups = @($groups)
    }
    if ($periodEnd) { $out.period_end = $periodEnd }
    if ($sandRemain -ne $null -and [int]$sandRemain -le 0) { $out.sand_exhausted = $true }
    if ($null -ne $overageUsd) {
        $out.overage_usd = $overageUsd
        $out.on_demand_used_cents = $cents
        $out.overage_source = 'period.spendLimitUsage.individualUsed'
    }
    if ($null -ne $limitCents) { $out.on_demand_limit_cents = $limitCents }
    if ($null -ne $overageGbp) { $out.overage_gbp = $overageGbp }
    if ($sand -and $sand.nextResetTimestampUtc) { $out.sand_period_end = [string]$sand.nextResetTimestampUtc }
    if ($fix.cursor_spending_groups) { $out.cursor_spending_groups = @($fix.cursor_spending_groups) }
    return [pscustomobject]$out
}

function Get-BobCursorAgentWeeklyRemaining {
    # Grok Bot / Cursor-agent account. Not Grok Build (xAI) unified.jsonl.
    $fixturePath = [string]$env:BOB_CURSOR_AGENT_FIXTURE
    if ($fixturePath -and (Test-Path $fixturePath)) {
        $fromFix = Get-BobCursorSpendingFromApiFixture -Path $fixturePath
        if ($fromFix) { return ConvertTo-BobCursorUsageDoc $fromFix }
    }
    if ($env:BOB_CURSOR_USAGE_FILE) {
        if (-not (Test-Path $env:BOB_CURSOR_USAGE_FILE)) { return $null }
        try {
            $j = Get-Content $env:BOB_CURSOR_USAGE_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
            return ConvertTo-BobCursorUsageDoc $j
        }
        catch { return $null }
    }
    $cache = $null
    try { $cache = Join-Path (Get-BridgeRoot) 'cursor-agent-usage.json' } catch { }
    if ($cache -and (Test-Path $cache)) {
        try {
            $age = [datetime]::UtcNow - [IO.File]::GetLastWriteTimeUtc($cache)
            if ($age.TotalMinutes -lt 15) {
                $j = Get-Content $cache -Raw -Encoding UTF8 | ConvertFrom-Json
                $doc = ConvertTo-BobCursorUsageDoc $j
                if ($doc) { return $doc }
            }
        }
        catch { }
    }
    $py = $null
    foreach ($c in @(
            'C:\Python\Python312\python.exe',
            'C:\Python\Python313\python.exe',
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe')
        )) {
        if ($c -and (Test-Path $c)) { $py = $c; break }
    }
    $script = $null
    try {
        $root = Split-Path (Get-ModuleRoot) -Parent
        $cand = Join-Path $root 'tools\Get-CursorAgentUsage.py'
        if (Test-Path $cand) { $script = $cand }
    } catch { }
    if (-not $script) {
        $cand2 = Join-Path (Get-ModuleRoot) 'tools\Get-CursorAgentUsage.py'
        if (Test-Path $cand2) { $script = $cand2 }
    }
    if ($py -and (Test-Path $script)) {
        try {
            $raw = & $py $script 2>$null
            $j = $raw | ConvertFrom-Json
            $doc = ConvertTo-BobCursorUsageDoc $j
            if ($doc -and $cache) {
                try { Write-JsonFile $cache $doc } catch { }
            }
            if ($doc) { return $doc }
        }
        catch { }
    }
    return $null
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


function Get-BobSeatConfig {
    $candidates = @()
    try { $candidates += (Join-Path (Get-ModuleRoot) 'config\bob-seats.json') } catch { }
    if ($env:BOB_SEATS_FILE) { $candidates = @($env:BOB_SEATS_FILE) + $candidates }
    foreach ($p in $candidates) {
        if (-not $p -or -not (Test-Path $p)) { continue }
        try {
            $j = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.seats) { return @($j.seats) }
        } catch { }
    }
    return @(
        [pscustomobject]@{ id = 'smart-catalogue'; label = 'Smart Catalogue'; email = 'social@smartcatalogue.uk'; machines = @('ionos') },
        [pscustomobject]@{ id = 'club-madeira'; label = 'Club Madeira'; email = 'social@clubmadeira.uk'; machines = @('flamingo') },
        [pscustomobject]@{ id = 'ntsa'; label = 'ntsa'; email = 'si@ntsa.uk'; machines = @('marchhare', 'ce-priority-dev1') }
    )
}

function Get-BobSeatForMachine {
    param([string]$MachineId)
    $mid = [string]$MachineId
    if (-not $mid) { return $null }
    $mid = $mid.ToLowerInvariant()
    foreach ($s in @(Get-BobSeatConfig)) {
        foreach ($m in @($s.machines)) {
            if ([string]$m -and [string]$m.ToLowerInvariant() -eq $mid) { return $s }
        }
    }
    return $null
}

function Get-BobCursorOverageGbp {
    # Real on-demand spend from Get-CursorAgentUsage.py (USD cents -> GBP).
    # Never treat tip_cursor.json as pounds.
    try {
        $doc = Get-BobCursorAgentWeeklyRemaining
        if ($doc -and $null -ne $doc.overage_gbp -and [string]$doc.overage_gbp -ne '') {
            return [double]$doc.overage_gbp
        }
    } catch { }
    return $null
}
function Test-BobCursorOverageLabel {
    param([string]$Label)
    if (-not $Label) { return $false }
    return ($Label -match '^-') -or ($Label -match [char]0x00A3)
}

function Format-BobCursorAccountLabel {
    param($RemainingPct, $UsedPct)
    if ($null -ne $RemainingPct -and [string]$RemainingPct -ne '') {
        return ('{0}%' -f [int]$RemainingPct)
    }
    $gbp = Get-BobCursorOverageGbp
    if ($null -ne $gbp) {
        return ('-{0}{1:N2}' -f [char]0x00A3, [math]::Abs([double]$gbp))
    }
    if ($null -ne $UsedPct -and [double]$UsedPct -gt 100) {
        # no money figure — fall back only if tip missing
        return ('over +{0}%' -f [int][math]::Round([double]$UsedPct - 100.0))
    }
    return 'empty'
}



function Format-BobResetLabel {
    param($PeriodEnd)
    if (-not $PeriodEnd -or [string]::IsNullOrWhiteSpace([string]$PeriodEnd)) { return $null }
    try {
        $raw = [string]$PeriodEnd
        $dt = $null
        # ms epoch
        if ($raw -match '^\d{12,}$') {
            $dt = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$raw).UtcDateTime
        }
        else {
            $dt = [datetime]::Parse($raw, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            if ($dt.Kind -eq [DateTimeKind]::Unspecified) { $dt = [DateTime]::SpecifyKind($dt, [DateTimeKind]::Utc) }
            $dt = $dt.ToUniversalTime()
        }
        $tz = [TimeZoneInfo]::FindSystemTimeZoneById('GMT Standard Time')
        try { $tz = [TimeZoneInfo]::FindSystemTimeZoneById('Europe/London') } catch { }
        $local = [TimeZoneInfo]::ConvertTimeFromUtc($dt, $tz)
        return ('reset {0}' -f $local.ToString('d MMM', [Globalization.CultureInfo]::GetCultureInfo('en-GB')))
    }
    catch { return $null }
}

function Get-BobTrayTitle {
    param($MachineId)
    $mid = [string]$MachineId
    if (-not $mid) {
        try { $mid = Get-ThisMachineId } catch { }
    }
    if (-not $mid -and $env:BOB_MACHINE_ID) { $mid = [string]$env:BOB_MACHINE_ID }
    if (-not $mid) { $mid = 'this-machine' }
    return ('#Bobiverse ({0})' -f $mid)
}

function Get-BobLiveGrokAgents {
    # grok.exe on this box, including sessions Bob did not start. Not Grok Bot.exe.
    if ($env:BOB_SKIP_LIVE_GROK -eq '1') { return @() }
    $byPid = @{}
    $sessPath = Join-Path $env:USERPROFILE '.grok\active_sessions.json'
    if (Test-Path $sessPath) {
        try {
            foreach ($s in @(Get-Content $sessPath -Raw -Encoding UTF8 | ConvertFrom-Json)) {
                if (-not $s.pid) { continue }
                $byPid[[int]$s.pid] = $s
            }
        }
        catch { }
    }
    $out = @()
    $procs = @()
    try {
        $procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -eq 'grok.exe' -or ($_.ExecutablePath -and $_.ExecutablePath -match '[\\/]grok\.exe$')
            })
    }
    catch { return @() }
    foreach ($p in $procs) {
        $cmd = [string]$p.CommandLine
        if ($cmd -match '--type=') { continue }
        if ([string]$p.Name -match 'Grok Bot') { continue }
        $pid = [int]$p.ProcessId
        $meta = $null
        if ($byPid.ContainsKey($pid)) { $meta = $byPid[$pid] }
        $cwd = $null
        $sid = ('grok-' + $pid)
        $opened = $null
        if ($meta) {
            if ($meta.cwd) { $cwd = [string]$meta.cwd }
            if ($meta.session_id) { $sid = [string]$meta.session_id }
            if ($meta.opened_at) { $opened = [string]$meta.opened_at }
        }
        if (-not $opened -and $p.CreationDate) {
            try { $opened = [Management.ManagementDateTimeConverter]::ToDateTime($p.CreationDate).ToUniversalTime().ToString('o') } catch { }
        }
        $out += ,[pscustomobject]@{
            id        = $sid
            sessionId = $sid
            pid       = $pid
            cwd       = $cwd
            claimedAt = $opened
            machine   = $null
            state     = 'running'
            source    = 'live-grok'
        }
    }
    return $out
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

function Get-BobJobTrayFields {
    param($Job, [switch]$SkipGit)
    if (-not $Job) { return $null }
    $repo = Get-BobTrayRepoLabel -Job $Job -SkipGit:$SkipGit
    if ($repo -eq '?' -or (Test-BobTrayLooksLikeSha $repo)) { $repo = $null }
    $sha = $null
    if ($Job.sha) { $sha = [string]$Job.sha.Trim() }
    elseif (-not $SkipGit -and $Job.cwd) {
        try { $sha = Get-BobGitShortSha ([string]$Job.cwd) } catch { }
    }
    $model = $null
    if ($Job.model) { $model = [string]$Job.model }
    else {
        try { $model = Get-BobIrcModelFromJob $Job } catch { }
    }
    $desc = $null
    if ($Job.description) { $desc = [string]$Job.description }
    elseif ($Job.task) { $desc = [string]$Job.task }
    elseif ($Job.goal) {
        $g = [string]$Job.goal
        if ($g.Length -gt 48) { $g = $g.Substring(0, 45) + '...' }
        $desc = $g
    }
    $runTime = $null
    if ($Job.run_time) { $runTime = [string]$Job.run_time }
    else {
        $when = $Job.claimedAt
        if (-not $when) { $when = $Job.createdAt }
        $age = Get-BobJobAge $when
        if ($age -and $age -ne '?') { $runTime = $age }
    }
    return [pscustomobject]@{
        repo        = $repo
        sha         = $sha
        model       = $model
        description = $desc
        run_time    = $runTime
    }
}

function Format-BobTrayJobLine {
    param($Job, [switch]$SkipGit)
    if (-not $Job) { return $null }
    $f = Get-BobJobTrayFields -Job $Job -SkipGit:$SkipGit
    if (-not $f) { return $null }
    if (-not $f.repo -and -not $f.sha) { return $null }
    $st = [string]$Job.state
    if (-not $st) { $st = 'running' }
    if ($st -eq 'running') { $st = 'START' }
    elseif ($st -eq 'queued') { $st = 'QUEUED' }
    elseif ($st -eq 'stopped' -or $st -eq 'done' -or $st -eq 'complete') { $st = 'STOP' }
    else { $st = $st.ToUpperInvariant() }
    $parts = @($st)
    if ($f.repo) { $parts += $f.repo }
    if ($f.sha) { $parts += $f.sha }
    if ($f.model) { $parts += $f.model }
    if ($f.description) { $parts += $f.description }
    if ($f.run_time) { $parts += $f.run_time }
    return ($parts -join '  ')
}

function ConvertTo-BobTrayIntOrNull {
    param($Value)
    if ($null -eq $Value) { return $null }
    if (($Value -is [string]) -and [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    try { return [int]$Value } catch { return $null }
}

function Get-BobCursorSpendingGroupCatalog {
    return @(
        [pscustomobject]@{ id = 'grok-chat'; label = 'grok chat'; pcent_source = 'grok-chat' }
        [pscustomobject]@{ id = 'high-cost-models'; label = 'high cost models'; pcent_source = 'high-cost-models' }
        # Auto model picker → planUsage.autoPercentUsed (Cursor Models / autoBucketModels).
        # Not on-demand. Legacy id low-cost-models still accepted in remain lookups.
        [pscustomobject]@{ id = 'auto'; label = 'auto'; pcent_source = 'cursor-models' }
    )
}

function Get-BobTrayCursorGroupHelpTooltip {
    param([string]$GroupId)
    switch -Regex ($GroupId) {
        '^(grok-chat|grok.chat|sand)$' {
            return @'
grok chat (Cursor Sand / Grok Bot pool)
Included: Grok Bot desktop turns (Temporal sand). Fuel for grok-bot only — not MRB/PR builds.
Source: GetSandUsageStatus.usagePercent (remaining = 100 − used). 0% means exhausted, not unknown.
'@.Trim()
        }
        '^(high-cost-models|high.cost|other-models)$' {
            return @'
high cost models (named / Other Models / API tier)
Included: specific third-party / premium API models on planUsage.apiPercentUsed.
Not the Auto meter. 0% means this bar is empty, not n/a.
'@.Trim()
        }
        '^(auto|low-cost-models|low.cost|cursor-models)$' {
            return @'
auto (Auto model / Cursor Models pool)
When the model picker is Auto, requests draw from this meter (planUsage.autoPercentUsed).
autoBucketModels includes default (Auto), Composer, Grok, Vega, etc. Docs: Auto bills at the
routed model's list price and uses the Cursor Models pool (Other Models only if the router
picks third-party). This is the cursor-models MRB/PR fuel gate. Not on-demand.
'@.Trim()
        }
        default {
            return @'
Cursor spending group. Hover a named bar (grok chat / high cost / auto) for that quota.
0% is a real remaining value — never shown as n/a.
'@.Trim()
        }
    }
}

function Get-BobCursorGroupRemainFromLocalDoc {
    param($LocalCursorDoc, [string]$GroupId)
    if (-not $LocalCursorDoc) { return $null }
    $want = [string]$GroupId
    if ($want -eq 'low-cost-models' -or $want -eq 'cursor-models') { $want = 'auto' }
    foreach ($g in @($LocalCursorDoc.cursor_spending_groups)) {
        if (-not $g) { continue }
        $gid = [string]$g.id
        if ($gid -eq 'low-cost-models' -or $gid -eq 'cursor-models') { $gid = 'auto' }
        if ($gid -ne $want) { continue }
        if ($null -ne $g.remaining_pct -and [string]$g.remaining_pct -ne '') {
            return [int]$g.remaining_pct
        }
    }
    if ($want -eq 'auto' -and $null -ne $LocalCursorDoc.remaining_pct) {
        return [int]$LocalCursorDoc.remaining_pct
    }
    if ($want -eq 'grok-chat' -and $null -ne $LocalCursorDoc.sand_remaining_pct) {
        return [int]$LocalCursorDoc.sand_remaining_pct
    }
    return $null
}

function Get-BobCursorGroupRemainFromSeatCache {
    param($SeatCacheEntry, [string]$GroupId)
    if (-not $SeatCacheEntry) { return $null }
    if ($SeatCacheEntry.groups) {
        $g = $SeatCacheEntry.groups.$GroupId
        if ($g -and $null -ne $g.remaining_pct -and [string]$g.remaining_pct -ne '') {
            try { return [int]$g.remaining_pct } catch { }
        }
    }
    if (($GroupId -eq 'low-cost-models' -or $GroupId -eq 'auto') -and $null -ne $SeatCacheEntry.remaining_pct -and [string]$SeatCacheEntry.remaining_pct -ne '') {
        try { return [int]$SeatCacheEntry.remaining_pct } catch { }
    }
    if ($SeatCacheEntry.groups -and $GroupId -eq 'auto' -and -not $SeatCacheEntry.groups.auto) {
        $g = $SeatCacheEntry.groups.'low-cost-models'
        if ($g -and $null -ne $g.remaining_pct -and [string]$g.remaining_pct -ne '') {
            try { return [int]$g.remaining_pct } catch { }
        }
    }
    return $null
}

function New-BobTrayIrcWorkerJobRow {
    param([string]$MachineId, [string]$Description, [string]$Nick)
    $desc = $Description
    if (-not $desc) { $desc = 'irc agent' }
    $model = 'irc'
    if ($Nick) { $model = [string]$Nick }
    $job = [pscustomobject]@{
        id          = ('irc-worker-' + $MachineId + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        machine     = $MachineId
        repo        = 'irc'
        sha         = $null
        model       = $model
        description = $desc
        run_time    = $null
        state       = 'START'
        source      = 'irc-worker'
    }
    return ConvertTo-BobTrayJobRow -Job $job -DefaultMachine $MachineId -State 'START' -SkipGit
}

function Expand-BobReportDigestView {
    param($Digest)
    $tasksByMachine = @{}
    $uptimeByMachine = @{}
    $pcentRows = @()
    $weeklyRows = @()
    $workersByMachine = @{}
    if (-not $Digest) {
        return [pscustomobject]@{
            tasksByMachine   = $tasksByMachine
            uptimeByMachine  = $uptimeByMachine
            pcentRows        = $pcentRows
            weeklyRows       = $weeklyRows
            workersByMachine = $workersByMachine
        }
    }

    $machineNodes = @()
    if ($Digest.machines) {
        foreach ($prop in @($Digest.machines.PSObject.Properties)) {
            $machineNodes += ,@{
                id   = [string]$prop.Name
                node = $prop.Value
            }
        }
    }

    if ($machineNodes.Count -gt 0) {
        foreach ($mn in $machineNodes) {
            $mid = Resolve-BobiverseMachineId ([string]$mn.id)
            if (-not $mid) { continue }
            $node = $mn.node
            if (-not $node) { continue }
            if ($node.task -and -not (Test-BobIrcDigestMachineReportsIdle $node)) {
                $task = $node.task
                if (-not $task.machine) {
                    $task = [pscustomobject]@{
                        machine     = $mid
                        repo        = $(if ($task.repo) { [string]$task.repo } else { $null })
                        sha         = $(if ($task.sha) { [string]$task.sha } else { $null })
                        model       = $(if ($task.model) { [string]$task.model } else { $null })
                        description = $(if ($task.description) { [string]$task.description } else { $null })
                        run_time    = $(if ($task.run_time) { [string]$task.run_time } else { $null })
                        state       = $(if ($task.state) { [string]$task.state } else { 'START' })
                    }
                }
                if (-not $tasksByMachine.ContainsKey($mid)) { $tasksByMachine[$mid] = @() }
                $tasksByMachine[$mid] += ,(ConvertFrom-BobReportDigestTask -Task $task -DefaultMachine $mid)
            }
            if ($node.uptime_since) {
                $uptimeByMachine[$mid] = [string]$node.uptime_since
            }
            # Digest weekly (xAI) — include 0 (#179).
            $weekPct = ConvertTo-BobTrayIntOrNull $node.weekly
            if ($null -ne $weekPct) {
                $weeklyRows += ,[pscustomobject]@{
                    machine = $mid
                    weekly  = $weekPct
                    period_end = $(if ($node.period_end) { [string]$node.period_end } elseif ($node.reset) { [string]$node.reset } else { $null })
                }
            }
            if ($node.pcent) {
                foreach ($pcProp in @($node.pcent.PSObject.Properties)) {
                    $src = [string]$pcProp.Name
                    if (-not $src) { continue }
                    $pct = ConvertTo-BobTrayIntOrNull $pcProp.Value
                    if ($null -eq $pct) { continue }
                    $pcentRows += ,[pscustomobject]@{
                        machine = $mid
                        source  = $src
                        pct     = $pct
                    }
                }
            }
            $wCount = 0
            $wOn = $null
            $nodeNames = @($node.PSObject.Properties.Name)
            if ($nodeNames -contains 'workers' -and $null -ne $node.workers -and [string]$node.workers -ne '') {
                if ($node.workers -is [System.Array] -or ($node.workers -is [System.Collections.IEnumerable] -and $node.workers -isnot [string])) {
                    $wCount = @($node.workers).Count
                }
                else {
                    try { $wCount = [int]$node.workers } catch { }
                }
            }
            if ($nodeNames -contains 'working_on' -and $node.working_on) { $wOn = [string]$node.working_on }
            if ($wCount -gt 0 -or $wOn) {
                $workersByMachine[$mid] = [pscustomobject]@{ count = $wCount; working_on = $wOn }
            }
        }
    }
    else {
        foreach ($t in @($Digest.tasks)) {
            if (-not $t) { continue }
            $tm = [string]$t.machine
            if (-not $tm) { continue }
            $tm = Resolve-BobiverseMachineId $tm
            if (-not $tm) { continue }
            if (-not $tasksByMachine.ContainsKey($tm)) { $tasksByMachine[$tm] = @() }
            $tasksByMachine[$tm] += ,(ConvertFrom-BobReportDigestTask -Task $t -DefaultMachine $tm)
        }
        foreach ($u in @($Digest.uptime)) {
            if (-not $u) { continue }
            $um = [string]$u.machine
            if (-not $um) { continue }
            $um = Resolve-BobiverseMachineId $um
            if (-not $um) { continue }
            if ($u.since) { $uptimeByMachine[$um] = [string]$u.since }
        }
        foreach ($pc in @($Digest.pcent)) {
            if (-not $pc) { continue }
            $src = [string]$pc.source
            if (-not $src) { continue }
            $pct = ConvertTo-BobTrayIntOrNull $pc.pct
            if ($null -eq $pct) { continue }
            $pcentRows += ,[pscustomobject]@{
                machine = $(if ($pc.machine) { [string]$pc.machine } else { $null })
                source  = $src
                pct     = $pct
            }
        }
    }

    if ($Digest.workers) {
        foreach ($wn in @($Digest.workers)) {
            if (-not $wn) { continue }
            $nick = [string]$wn
            if ($wn -is [pscustomobject] -or $wn -is [System.Collections.IDictionary]) {
                if ($wn.nick) { $nick = [string]$wn.nick }
                elseif ($wn.id) { $nick = [string]$wn.id }
            }
            $mac = Resolve-BobiverseMachineFromIrcNick $nick
            if (-not $mac) { continue }
            $desc = 'irc agent'
            if ($wn -is [pscustomobject] -and $wn.working_on) { $desc = [string]$wn.working_on }
            $cur = $workersByMachine[$mac]
            if (-not $cur) {
                $workersByMachine[$mac] = [pscustomobject]@{ count = 1; working_on = $desc; nick = $nick }
            }
            else {
                $cnt = [int]$cur.count
                if ($cnt -lt 1) { $cnt = 1 }
                $workersByMachine[$mac] = [pscustomobject]@{
                    count      = $cnt + 1
                    working_on = $(if ($cur.working_on) { [string]$cur.working_on } else { $desc })
                    nick       = $nick
                }
            }
        }
    }

    return [pscustomobject]@{
        tasksByMachine   = $tasksByMachine
        uptimeByMachine  = $uptimeByMachine
        pcentRows        = $pcentRows
        weeklyRows       = $weeklyRows
        workersByMachine = $workersByMachine
    }
}

function Test-BobTrayDigestCodingTask {
    param($Task)
    if (-not $Task) { return $false }
    if ($Task.sha) { return $true }
    $repo = $null
    if ($Task.repo) { $repo = [string]$Task.repo }
    return (Test-BobIrcRepoOk $repo)
}

function ConvertFrom-BobReportDigestTask {
    param($Task, [string]$DefaultMachine)
    if (-not $Task) { return $null }
    if (-not (Test-BobTrayDigestCodingTask $Task)) { return $null }
    $mac = [string]$Task.machine
    if (-not $mac) { $mac = $DefaultMachine }
    $repo = $null
    if ($Task.repo) { $repo = [string]$Task.repo }
    $sha = $null
    if ($Task.sha) { $sha = [string]$Task.sha }
    $st = 'running'
    if ($Task.state) { $st = [string]$Task.state }
    return [pscustomobject]@{
        id          = $(if ($Task.id) { [string]$Task.id } else { ('digest-' + [guid]::NewGuid().ToString()) })
        machine     = $mac
        repo        = $repo
        sha         = $sha
        model       = $(if ($Task.model) { [string]$Task.model } else { $null })
        description = $(if ($Task.description) { [string]$Task.description } else { $null })
        run_time    = $(if ($Task.run_time) { [string]$Task.run_time } else { $null })
        state       = $st
        source      = 'report-digest'
    }
}

function Get-BobCursorPoolsForTray {
    param(
        [string]$MachineId,
        $LocalCursorDoc,
        $PcentRows
    )
    # Cursor Spending groups are per Cursor account on this host — not xAI seat labels
    # (Smart Catalogue / Club Madeira / ntsa are Grok Build seats; see issue #151 UAT).
    $cache = Read-BobCursorPoolsCache
    $catalog = @(Get-BobCursorSpendingGroupCatalog)
    $localSeat = Get-BobSeatForMachine -MachineId $MachineId
    $localSeatId = $null
    $localSeatLabel = $null
    if ($localSeat) {
        $localSeatId = [string]$localSeat.id
        $localSeatLabel = [string]$localSeat.label
        if (-not $localSeatLabel) { $localSeatLabel = $localSeatId }
    }
    $ce = $null
    if ($localSeatId -and $cache.by_seat.ContainsKey($localSeatId)) {
        $ce = $cache.by_seat[$localSeatId]
    }
    $periodEnd = $null
    if ($LocalCursorDoc -and $LocalCursorDoc.period_end) {
        $periodEnd = [string]$LocalCursorDoc.period_end
    }
    if ($ce -and $ce.period_end -and -not $periodEnd) { $periodEnd = [string]$ce.period_end }
    $sandPeriodEnd = $null
    if ($LocalCursorDoc -and $LocalCursorDoc.sand_period_end) {
        $sandPeriodEnd = [string]$LocalCursorDoc.sand_period_end
    }
    $pools = @()
    foreach ($grp in $catalog) {
        $gid = [string]$grp.id
        $glabel = [string]$grp.label
        $remain = Get-BobCursorGroupRemainFromLocalDoc -LocalCursorDoc $LocalCursorDoc -GroupId $gid
        if ($null -eq $remain) { $remain = Get-BobCursorGroupRemainFromSeatCache -SeatCacheEntry $ce -GroupId $gid }
        # 0% is a real value (#179) — only missing/null is n/a.
        $pctLabel = 'n/a'
        if ($null -ne $remain -and [string]$remain -ne '') { $pctLabel = ('{0}%' -f [int]$remain) }
        # Per-group reset: grok chat uses Sand nextReset; spending + on-demand use billingCycleEnd.
        $pe = $periodEnd
        if ($gid -eq 'grok-chat' -and $sandPeriodEnd) { $pe = $sandPeriodEnd }
        $resetLabel = Format-BobResetLabel $pe
        $heading = ('{0}  {1}' -f $glabel, $pctLabel)
        if ($resetLabel) { $heading = ('{0}  {1}' -f $heading, $resetLabel) }
        $pools += ,[pscustomobject]@{
            seat_id         = $localSeatId
            seat_label      = $localSeatLabel
            group_id        = $gid
            group_label     = $glabel
            remaining_pct   = $remain
            period_end      = $pe
            reset_label     = $resetLabel
            pct_label       = $pctLabel
            overage_label   = $null
            heading         = $heading
            account_name    = $glabel
        }
    }
    foreach ($pc in @($PcentRows)) {
        if (-not $pc) { continue }
        $src = [string]$pc.source
        if (-not $src) { continue }
        $pct = ConvertTo-BobTrayIntOrNull $pc.pct
        if ($null -eq $pct) { continue }
        $reportMac = [string]$pc.machine
        if ($reportMac) { $reportMac = Resolve-BobiverseMachineId $reportMac }
        if ($reportMac -and [string]$reportMac -ne [string]$MachineId) { continue }
        $seatId = $localSeatId
        $groupId = $null
        if ($src -eq 'cursor-models' -or $src -eq 'low-cost-models' -or $src -eq 'auto') {
            $groupId = 'auto'
            $macForSeat = $MachineId
            if ($reportMac) { $macForSeat = $reportMac }
            $seat = Get-BobSeatForMachine -MachineId $macForSeat
            if ($seat) { $seatId = [string]$seat.id }
        }
        elseif ($src -eq 'grok-chat' -or $src -eq 'high-cost-models') {
            $groupId = $src
            $macForSeat = $MachineId
            if ($reportMac) { $macForSeat = $reportMac }
            $seat = Get-BobSeatForMachine -MachineId $macForSeat
            if ($seat) { $seatId = [string]$seat.id }
        }
        elseif ($src -match '^(smart-catalogue|club-madeira|ntsa)$') {
            $seatId = $src
            $groupId = 'low-cost-models'
        }
        if (-not $groupId) { continue }
        if ($seatId -and $localSeatId -and [string]$seatId -ne $localSeatId) { continue }
        foreach ($pool in $pools) {
            if ([string]$pool.group_id -eq $groupId) {
                $pool.remaining_pct = $pct
                $pool.pct_label = ('{0}%' -f $pct)
                $pool.heading = ('{0}  {1}' -f $pool.group_label, $pool.pct_label)
                if ($pool.reset_label) { $pool.heading = ('{0}  {1}' -f $pool.heading, $pool.reset_label) }
                break
            }
        }
        if ($seatId -match '^(smart-catalogue|club-madeira|ntsa)$') {
            Save-BobCursorPoolGroupForSeat -SeatId $seatId -GroupId $groupId -RemainingPct $pct
            if ($groupId -eq 'low-cost-models') {
                Save-BobCursorPoolForSeat -SeatId $seatId -RemainingPct $pct
            }
        }
    }
    return $pools
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
    $fields = Get-BobJobTrayFields -Job $Job -SkipGit:$SkipGit
    $repo = '?'
    if ($fields -and $fields.repo) { $repo = $fields.repo }
    $line = Format-BobTrayJobLine -Job $Job -SkipGit:$SkipGit
    return [pscustomobject]@{
        id                     = $id
        id8                    = $(if ($id.Length -ge 8) { $id.Substring(0, 8) } else { $id })
        machine                = $mac
        repo                   = $repo
        sha                    = $(if ($fields) { $fields.sha } else { $null })
        model                  = $(if ($fields) { $fields.model } else { $null })
        description            = $(if ($fields) { $fields.description } else { $null })
        run_time               = $(if ($fields) { $fields.run_time } else { $null })
        duration               = Get-BobJobAge $when
        state                  = $st
        line                   = $line
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
    $title = Get-BobTrayTitle -MachineId $machineId

    $reportDigest = $null
    try { $reportDigest = Read-BobReportDigest } catch { $reportDigest = $null }
    $digestView = Expand-BobReportDigestView -Digest $reportDigest
    $digestTasksByMachine = $digestView.tasksByMachine
    $uptimeByMachine = $digestView.uptimeByMachine
    $digestPcentRows = @($digestView.pcentRows)
    $digestWeeklyRows = @($digestView.weeklyRows)
    $digestWorkersByMachine = @{}
    if ($digestView.workersByMachine) { $digestWorkersByMachine = $digestView.workersByMachine }

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
    $fleetSessions = @{}
    foreach ($b in @($running)) {
        if ($b.sessionId) { $fleetSessions[[string]$b.sessionId] = $true }
        if ($b.id) { $fleetSessions[[string]$b.id] = $true }
    }
    foreach ($g in @(Get-BobLiveGrokAgents)) {
        if ($g.id -and ($localIds.ContainsKey([string]$g.id) -or $fleetSessions.ContainsKey([string]$g.id))) { continue }
        if ($g.sessionId -and $fleetSessions.ContainsKey([string]$g.sessionId)) { continue }
        $row = ConvertTo-BobTrayJobRow -Job $g -DefaultMachine $machineId -State 'running'
        if (-not $row.line) { continue }
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
    $seatIds = @()
    try { $seatIds = @(Get-BobiverseMachineIds) } catch { $seatIds = @() }
    $knownTile = @{}
    if ($machineId) { $knownTile[$machineId] = $true }
    foreach ($sid in $seatIds) { if ($sid) { $knownTile[$sid] = $true } }
    $restrictTiles = $knownTile.Count -gt 1 -or ($seatIds.Count -gt 0)
    if ($reg) {
        foreach ($m in @($reg.machines)) {
            $mid = [string]$m.id
            if (-not $mid) { continue }
            if ($restrictTiles -and -not $knownTile.ContainsKey($mid)) { continue }
            if (-not $byMachine.ContainsKey($mid)) { $byMachine[$mid] = @() }
            $specBy[$mid] = $m
        }
    }
    foreach ($sid in $seatIds) {
        if (-not $byMachine.ContainsKey($sid)) { $byMachine[$sid] = @() }
    }
    if (-not $byMachine.ContainsKey($machineId)) {
        $byMachine[$machineId] = @()
    }
    $reachBy[$machineId] = 'local'
    $weeklyBy = @{}
    $periodEndBy = @{}
    $week = Get-BobWeeklyRemaining
    $remainPct = $null
    $weekFetched = $null
    if ($week -and (Test-BobTrayRemainingKnown $week.remaining_pct)) {
        $remainPct = [int]$week.remaining_pct
        $weekFetched = [string]$week.fetched_at
        $weeklyBy[$machineId] = $remainPct
    }
    if ($week -and $week.period_end) {
        $periodEndBy[$machineId] = [string]$week.period_end
    }
    if ($week) {
        Save-BobSeatPeriodEnd -MachineId $machineId -PeriodEnd $(if ($week.period_end) { [string]$week.period_end } else { $null }) -Weekly $(if ($null -ne $week.remaining_pct) { [int]$week.remaining_pct } else { $null })
    }
    foreach ($pc in @($digestPcentRows)) {
        if (-not $pc) { continue }
        $src = [string]$pc.source
        $mac = [string]$pc.machine
        if ($mac) { $mac = Resolve-BobiverseMachineId $mac }
        $pct = ConvertTo-BobTrayIntOrNull $pc.pct
        if ($null -eq $pct) { continue }
        if ($src -eq 'grok-build' -and $mac) {
            $weeklyBy[$mac] = $pct
        }
    }
    # HTTP digest machine.weekly → Grok tiles (#179). 0% is valid.
    foreach ($wr in @($digestWeeklyRows)) {
        if (-not $wr) { continue }
        $mac = [string]$wr.machine
        if ($mac) { $mac = Resolve-BobiverseMachineId $mac }
        if (-not $mac) { continue }
        $pct = ConvertTo-BobTrayIntOrNull $wr.weekly
        if ($null -eq $pct) { continue }
        $weeklyBy[$mac] = $pct
        if ($wr.period_end) { $periodEndBy[$mac] = [string]$wr.period_end }
        try {
            Save-BobSeatPeriodEnd -MachineId $mac -PeriodEnd $(if ($wr.period_end) { [string]$wr.period_end } else { $null }) -Weekly $pct
        } catch { }
    }
    $cursorWeek = $null
    $cursorRemain = $null
    try { $cursorWeek = Get-BobCursorAgentWeeklyRemaining } catch { $cursorWeek = $null }
    if ($cursorWeek -and (Test-BobTrayRemainingKnown $cursorWeek.remaining_pct)) {
        $cursorRemain = [int]$cursorWeek.remaining_pct
    }

    $moot = $null
    try { $moot = Get-BobMootRoster } catch { $moot = $null }

    foreach ($j in $jobs) {
        $mid = [string]$j.machine
        if (-not $mid) { $mid = $machineId }
        if ($restrictTiles -and -not $knownTile.ContainsKey($mid)) {
            $mid = $machineId
        }
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
        if ($peek.period_end) { $periodEndBy[$mid] = [string]$peek.period_end }
        if (($null -ne $peek.weekly -and (Test-BobTrayRemainingKnown $peek.weekly)) -or $peek.period_end) {
            try {
                Save-BobSeatPeriodEnd -MachineId $mid -PeriodEnd $(if ($peek.period_end) { [string]$peek.period_end } else { $null }) -Weekly $(if ($null -ne $peek.weekly -and (Test-BobTrayRemainingKnown $peek.weekly)) { [int]$peek.weekly } else { $null })
            } catch { }
        }
        if ($peek.cursor_label -and [string]$peek.cursor_label -ne 'empty') {
            try { Save-BobCursorAccountCache -Label ([string]$peek.cursor_label) -PeriodEnd $(if ($peek.cursor_period_end) { [string]$peek.cursor_period_end } else { $null }) } catch { }
            try {
                $peekSeat = Get-BobSeatForMachine -MachineId $mid
                if ($peekSeat) {
                    Save-BobCursorPoolForSeat -SeatId ([string]$peekSeat.id) -Label ([string]$peek.cursor_label) -PeriodEnd $(if ($peek.cursor_period_end) { [string]$peek.cursor_period_end } else { $null })
                }
            }
            catch { }
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
        $fromIrc = @('irc', 'irc-tray', 'irc-digest') -contains ([string]$peek.source)
        # In-moot / IRC peer beats lastSeen-age 'stale' (good card = everyone in the moot).
        if ($inMoot -or $fromIrc) {
            $reachBy[$mid] = 'irc-fallback'
        }
        elseif ($empty -and ($null -eq $age -or $age -gt $staleAfter)) {
            $reachBy[$mid] = 'stale'
        }
        elseif (-not $empty -and $null -ne $age -and $age -gt $staleAfter) {
            $reachBy[$mid] = 'stale'
        }
        else {
            $reachBy[$mid] = 'ok'
        }
    }

    if ($restrictTiles) {
        foreach ($k in @($byMachine.Keys)) {
            if (-not $knownTile.ContainsKey($k)) { $byMachine.Remove($k) }
        }
    }

    $order = @()
    if ($byMachine.ContainsKey($machineId)) { $order += $machineId }
    foreach ($k in ($byMachine.Keys | Sort-Object)) {
        if ($k -ne $machineId) { $order += $k }
    }

    # Same xAI seat => one shared remaining % (account-level).
    foreach ($seat in @(Get-BobSeatConfig)) {
        $vals = @()
        foreach ($sm in @($seat.machines)) {
            $smid = [string]$sm
            if ($smid -and $weeklyBy.ContainsKey($smid) -and $null -ne $weeklyBy[$smid]) {
                $vals += ,([int]$weeklyBy[$smid])
            }
        }
        if ($vals.Count -gt 0) {
            $shared = ($vals | Measure-Object -Minimum).Minimum
            foreach ($sm in @($seat.machines)) {
                $smid = [string]$sm
                if ($smid) { $weeklyBy[$smid] = [int]$shared }
            }
        }
        $ends = @()
        foreach ($sm in @($seat.machines)) {
            $smid = [string]$sm
            if ($smid -and $periodEndBy.ContainsKey($smid) -and $periodEndBy[$smid]) {
                $ends += ,[string]$periodEndBy[$smid]
            }
        }
        if ($ends.Count -gt 0) {
            $sharedEnd = ($ends | Sort-Object | Select-Object -First 1)
            foreach ($sm in @($seat.machines)) {
                $smid = [string]$sm
                if ($smid) { $periodEndBy[$smid] = $sharedEnd }
            }
        }
    }

    # Durable fallback: seat-period-end.json survives IRC import wipes.
    try {
        $peCache = Read-BobSeatPeriodEndCache
        foreach ($mid2 in @($order)) {
            if ($periodEndBy.ContainsKey($mid2) -and $periodEndBy[$mid2]) { continue }
            if ($peCache.by_machine.ContainsKey($mid2) -and $peCache.by_machine[$mid2]) {
                $periodEndBy[$mid2] = [string]$peCache.by_machine[$mid2]
            }
        }
        foreach ($mid2 in @($order)) {
            if ($weeklyBy.ContainsKey($mid2) -and $null -ne $weeklyBy[$mid2]) { continue }
            if ($peCache.weekly_by_machine.ContainsKey($mid2) -and $null -ne $peCache.weekly_by_machine[$mid2]) {
                $weeklyBy[$mid2] = [int]$peCache.weekly_by_machine[$mid2]
            }
        }
        foreach ($seat in @(Get-BobSeatConfig)) {
            $sid = [string]$seat.id
            $seatEnd = $null
            $seatWeek = $null
            if ($sid -and $peCache.by_seat.ContainsKey($sid) -and $peCache.by_seat[$sid]) {
                $seatEnd = [string]$peCache.by_seat[$sid]
            }
            if ($sid -and $peCache.weekly_by_seat.ContainsKey($sid) -and $null -ne $peCache.weekly_by_seat[$sid]) {
                $seatWeek = [int]$peCache.weekly_by_seat[$sid]
            }
            foreach ($sm in @($seat.machines)) {
                $smid = [string]$sm
                if (-not $smid) { continue }
                if ($periodEndBy.ContainsKey($smid) -and $periodEndBy[$smid]) {
                    if (-not $seatEnd) { $seatEnd = [string]$periodEndBy[$smid] }
                }
                elseif ($seatEnd) { $periodEndBy[$smid] = $seatEnd }
                if ($weeklyBy.ContainsKey($smid) -and $null -ne $weeklyBy[$smid]) {
                    if ($null -eq $seatWeek) { $seatWeek = [int]$weeklyBy[$smid] }
                }
                elseif ($null -ne $seatWeek) { $weeklyBy[$smid] = [int]$seatWeek }
            }
            if ($seatEnd) {
                foreach ($sm in @($seat.machines)) {
                    $smid = [string]$sm
                    if ($smid -and (-not $periodEndBy.ContainsKey($smid) -or -not $periodEndBy[$smid])) {
                        $periodEndBy[$smid] = $seatEnd
                    }
                }
            }
            if ($null -ne $seatWeek) {
                foreach ($sm in @($seat.machines)) {
                    $smid = [string]$sm
                    if ($smid -and (-not $weeklyBy.ContainsKey($smid) -or $null -eq $weeklyBy[$smid])) {
                        $weeklyBy[$smid] = [int]$seatWeek
                    }
                }
            }
        }
        foreach ($k in @($periodEndBy.Keys)) {
            $wk = $null
            if ($weeklyBy.ContainsKey($k)) { $wk = $weeklyBy[$k] }
            if ($periodEndBy[$k] -or $null -ne $wk) {
                Save-BobSeatPeriodEnd -MachineId $k -PeriodEnd $(if ($periodEndBy[$k]) { [string]$periodEndBy[$k] } else { $null }) -Weekly $wk
            }
        }
    } catch { }

    $tiles = @()
    $jobLines = @()
    foreach ($mid in $order) {
        $rows = @($byMachine[$mid])
        if ($digestTasksByMachine.ContainsKey($mid)) {
            $digestRows = @()
            foreach ($dt in @($digestTasksByMachine[$mid])) {
                if (-not $dt) { continue }
                if (-not (Test-BobTrayDigestCodingTask $dt)) { continue }
                $dr = ConvertTo-BobTrayJobRow -Job $dt -DefaultMachine $mid -State ([string]$dt.state) -SkipGit
                if ($dr.line) { $digestRows += ,$dr }
            }
            if ($digestRows.Count -gt 0) { $rows = $digestRows }
        }
        if ($rows.Count -eq 0 -and $digestWorkersByMachine.ContainsKey($mid)) {
            $wi = $digestWorkersByMachine[$mid]
            $desc = $null
            if ($wi.working_on) { $desc = [string]$wi.working_on }
            $nick = $null
            if ($wi.nick) { $nick = [string]$wi.nick }
            $rows += ,(New-BobTrayIrcWorkerJobRow -MachineId $mid -Description $desc -Nick $nick)
        }
        if ($rows.Count -eq 0 -and $moot) {
            foreach ($nk in @($moot.nicks)) {
                $mac = Resolve-BobiverseMachineFromIrcNick $nk
                if ($mac -eq $mid) {
                    $rows += ,(New-BobTrayIrcWorkerJobRow -MachineId $mid -Description 'on #bobiverse' -Nick $nk)
                    break
                }
            }
        }
        if ($rows.Count -gt 1) {
            $rows = @(
                $rows | Sort-Object -Property @{
                    Expression = {
                        switch ([string]$_.state) {
                            'running' { 0 }
                            'queued' { 1 }
                            'START' { 0 }
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
        $seatInfo = Get-BobSeatForMachine -MachineId $mid
        $tileEnd = $null
        if ($periodEndBy.ContainsKey($mid)) { $tileEnd = [string]$periodEndBy[$mid] }
        $tileReset = Format-BobResetLabel $tileEnd
        $upSince = $null
        if ($uptimeByMachine.ContainsKey($mid)) { $upSince = [string]$uptimeByMachine[$mid] }
        $tile = New-Object psobject -Property @{
            id             = $mid
            job_count      = $rows.Count
            jobs           = $rows
            reach          = $reach
            last_seen      = $(if ($seenBy.ContainsKey($mid)) { $seenBy[$mid] } else { $null })
            remaining_pct  = $wPct
            period_end     = $tileEnd
            reset_label    = $tileReset
            up_since       = $upSince
            seat_id        = $(if ($seatInfo) { [string]$seatInfo.id } else { $null })
            seat_label     = $(if ($seatInfo) { [string]$seatInfo.label } else { $null })
            seat_email     = $(if ($seatInfo) { [string]$seatInfo.email } else { $null })
        }
        $tiles += ,$tile
        $pctLabel = 'n/a'
        if ($null -ne $wPct) { $pctLabel = ('{0}%' -f [int]$wPct) }
        $jlName = $mid
        if ($seatInfo -and $seatInfo.label) { $jlName = ('{0}  -  {1}' -f $mid, $seatInfo.label) }
        $machHeading = ('  {0} ({1})' -f $jlName, $pctLabel)
        if ($tileReset) { $machHeading = ('{0} - {1}' -f $machHeading, $tileReset) }
        $jobLines += $machHeading
        if ($upSince) { $jobLines += ('    up since {0}' -f $upSince) }
        $tileFuels = @('cursor-models', 'grok-build', 'copilot', 'grok-bot')
        if ($mid -match '2012') { $tileFuels = @() }
        $tile | Add-Member -NotePropertyName fuels -NotePropertyValue $tileFuels -Force
        if ($tileFuels.Count -gt 0) { $jobLines += ('    fuels: {0}' -f ($tileFuels -join ', ')) }
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
                $ln = $j.line
                if (-not $ln) {
                    $ln = Format-BobTrayJobLine -Job $j -SkipGit
                }
                if ($ln) { $jobLines += ('    {0}' -f $ln) }
            }
        }
    }
    $peerPeek = $order.Count -gt 1
    if (-not $peerPeek) {
        $jobLines += 'other hosts not in this store'
    }
    $cursorUsed = $null
    $cursorOver = $null
    if ($cursorWeek) {
        if ($null -ne $cursorWeek.used_pct) { $cursorUsed = $cursorWeek.used_pct }
        if ($null -ne $cursorWeek.overspend_pct) { $cursorOver = $cursorWeek.overspend_pct }
    }
    $acctPctLabel = Format-BobCursorAccountLabel -RemainingPct $cursorRemain -UsedPct $cursorUsed
    if ($acctPctLabel -eq 'empty') {
        $gbp = Get-BobCursorOverageGbp
        if ($null -ne $gbp) { $acctPctLabel = ('-{0}{1:N2}' -f [char]0x00A3, [math]::Abs([double]$gbp)) }
    }
    # Fleet-shared Cursor Sand (Grok Bot) — MarchHare etc. often have no local token.
    if (-not $acctPctLabel -or $acctPctLabel -eq 'empty') {
        try {
            $cc = Read-BobCursorAccountCache
            if ($cc -and $cc.label -and [string]$cc.label -ne 'empty') {
                $acctPctLabel = [string]$cc.label
                if (-not $cursorWeek) { $cursorWeek = [pscustomobject]@{} }
                if ($cc.period_end -and -not $cursorWeek.period_end) {
                    $cursorWeek | Add-Member -NotePropertyName period_end -NotePropertyValue ([string]$cc.period_end) -Force
                }
            }
        } catch { }
    }
    if ($acctPctLabel -and $acctPctLabel -ne 'empty') {
        $cend = $null
        if ($cursorWeek -and $cursorWeek.period_end) { $cend = [string]$cursorWeek.period_end }
        Save-BobCursorAccountCache -Label $acctPctLabel -PeriodEnd $cend
    }
    try {
        $localSeat = Get-BobSeatForMachine -MachineId $machineId
        if ($localSeat) {
            Save-BobCursorPoolForSeat -SeatId ([string]$localSeat.id) -RemainingPct $cursorRemain -PeriodEnd $(if ($cursorWeek -and $cursorWeek.period_end) { [string]$cursorWeek.period_end } else { $null }) -Label $acctPctLabel
        }
    }
    catch { }
    $cursorPools = @(Get-BobCursorPoolsForTray -MachineId $machineId -LocalCursorDoc $cursorWeek -PcentRows $digestPcentRows)
    $cursorGroups = @()
    foreach ($pool in $cursorPools) {
        if (-not $pool) { continue }
        $cursorGroups += ,[pscustomobject]@{
            seat_id        = $pool.seat_id
            seat_label     = $pool.seat_label
            group_id       = $pool.group_id
            group_label    = $pool.group_label
            remaining_pct  = $pool.remaining_pct
            pct_label      = $pool.pct_label
            heading        = $pool.heading
            source         = $(
                if ($pool.group_id -eq 'grok-chat') { 'GetSandUsageStatus.usagePercent' }
                elseif ($pool.group_id -eq 'high-cost-models') { 'GetCurrentPeriodUsage.planUsage.apiPercentUsed' }
                else { 'GetCurrentPeriodUsage.planUsage.autoPercentUsed' }
            )
        }
    }
    $poolLines = @()
    foreach ($pool in $cursorPools) {
        if ($pool.heading) { $poolLines += ('  {0}' -f $pool.heading) }
    }
    $jobsText = (($poolLines + $jobLines) -join "`n")

    $lines = New-Object System.Collections.Generic.List[string]
    if ($null -eq $remainPct) {
        $lines.Add(('{0}  weekly remaining  n/a' -f $tier))
        $short = '{0} {1} run' -f $tier, @($running).Count
    }
    else {
        $lines.Add(('{0}  weekly remaining  {1}%' -f $tier, $remainPct))
        $short = '{0} {1} run  {2}%' -f $tier, @($running).Count, $remainPct
    }
    foreach ($pl in $poolLines) { $lines.Add($pl) }
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
        cursor_pools   = @($cursorPools)
        cursor_groups  = @($cursorGroups)
        account_name   = 'auto'
        account_label  = $acctPctLabel
        account_remaining_pct = $cursorRemain
        account_overage_gbp = $(if ($null -ne (Get-BobCursorOverageGbp)) { [double](Get-BobCursorOverageGbp) } else { $null })
        account_used_pct = $cursorUsed
        account_period_end = $(if ($cursorWeek -and $cursorWeek.period_end) { [string]$cursorWeek.period_end } else { $null })
        account_reset_label = $(if ($cursorWeek -and $cursorWeek.period_end) { Format-BobResetLabel $cursorWeek.period_end } else { $null })
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

