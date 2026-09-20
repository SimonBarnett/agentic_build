function Get-BobFuelOrder {
    param([switch]$AllowOnDemand)
    $order = @('cursor-models', 'grok-build', 'copilot', 'grok-bot')
    if ($AllowOnDemand) { $order += 'on-demand' }
    return $order
}

function Get-BobRemainingPctValue {
    param($Owner)
    if ($null -eq $Owner) { return $null }
    $raw = $null
    if ($Owner -is [int] -or $Owner -is [long] -or $Owner -is [double]) {
        $raw = $Owner
    }
    elseif ($Owner.PSObject -and $Owner.PSObject.Properties['remaining_pct']) {
        $raw = $Owner.remaining_pct
    }
    if ($null -eq $raw -or [string]$raw -eq '') { return $null }
    try { return [int]$raw } catch { return $null }
}

function Get-BobMachineJobCount {
    param($Machine)
    if ($null -eq $Machine) { return 0 }
    $j = $Machine.jobs
    if ($null -eq $j) {
        if ($null -ne $Machine.job_count -and [string]$Machine.job_count -ne '') {
            try { return [int]$Machine.job_count } catch { return 0 }
        }
        return 0
    }
    if ($j -is [int] -or $j -is [long] -or $j -is [double]) { return [int]$j }
    if ($j -is [string]) {
        if ([string]::IsNullOrWhiteSpace($j) -or $j -eq '-') { return 0 }
        try { return [int]$j } catch { return @($j).Count }
    }
    return @($j).Count
}

function Test-BobGitEligibleMachine {
    param($Machine)
    if ($null -eq $Machine) { return $false }
    if ($null -ne $Machine.gitEligible -and [string]$Machine.gitEligible -ne '') {
        try { return [bool]$Machine.gitEligible } catch { }
    }
    $kind = [string]$Machine.kind
    $id = [string]$Machine.id
    $hostName = [string]$Machine.hostname
    if ($kind -match '(?i)dumb') { return $false }
    if ($id -match '2012' -or $hostName -match '2012') { return $false }
    $roots = @($Machine.cwdRoots)
    if ($roots.Count -eq 0) { return $false }
    return $true
}

function Get-BobMachineFuels {
    param($Machine)
    if ($null -eq $Machine) { return @() }
    if ($Machine.fuels) { return @($Machine.fuels | ForEach-Object { [string]$_ }) }
    if (-not (Test-BobGitEligibleMachine $Machine)) { return @() }
    return @('cursor-models', 'grok-build', 'copilot', 'grok-bot')
}

function Test-BobMachineCanStrikeFuel {
    param($Machine, [string]$Fuel)
    if (-not $Fuel) { return $false }
    $fuels = @(Get-BobMachineFuels $Machine)
    return ($fuels -contains $Fuel)
}

function Test-BobFuelHasIncluded {
    param(
        $Capacity,
        $Machine,
        [string]$Fuel,
        [switch]$AllowOnDemand
    )
    switch ($Fuel) {
        'cursor-models' {
            $p = Get-BobRemainingPctValue $Capacity.cursor_models
            return ($null -ne $p -and $p -gt 0)
        }
        'grok-build' {
            $p = Get-BobRemainingPctValue $Machine.grok_build
            return ($null -ne $p -and $p -gt 0)
        }
        'grok-bot' {
            $p = Get-BobRemainingPctValue $Machine.grok_bot
            return ($null -ne $p -and $p -gt 0)
        }
        'copilot' {
            $c = $Capacity.copilot
            if ($c -and $c.PSObject.Properties['available'] -and $c.available -eq $false) { return $false }
            $p = Get-BobRemainingPctValue $c
            if ($null -eq $p) { return $true }
            return ($p -gt 0)
        }
        'on-demand' {
            if (-not $AllowOnDemand) { return $false }
            $o = $Capacity.on_demand
            if (-not $o) { return $false }
            if ($o.PSObject.Properties['enabled'] -and $o.enabled -eq $false) { return $false }
            $p = Get-BobRemainingPctValue $o
            return ($null -ne $p -and $p -gt 0)
        }
        default { return $false }
    }
}

function Get-BobFuelPeriodEnd {
    param($Capacity, $Machine, [string]$Fuel)
    $owner = $null
    switch ($Fuel) {
        'cursor-models' { $owner = $Capacity.cursor_models }
        'on-demand' { $owner = $Capacity.on_demand }
        'copilot' { $owner = $Capacity.copilot }
        'grok-build' { $owner = $Machine.grok_build }
        'grok-bot' { $owner = $Machine.grok_bot }
    }
    if ($owner -and $owner.period_end) { return [string]$owner.period_end }
    return $null
}

function ConvertTo-BobCapacitySnapshot {
    param($Raw)
    if ($null -eq $Raw) { return $null }
    if ($Raw -is [string]) {
        if (-not (Test-Path $Raw)) { return $null }
        $Raw = Get-Content $Raw -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $Raw
}

function Get-BobCapacity {
    [CmdletBinding()]
    param()
    if ($env:BOB_CAPACITY_FILE -and (Test-Path $env:BOB_CAPACITY_FILE)) {
        return ConvertTo-BobCapacitySnapshot $env:BOB_CAPACITY_FILE
    }

    $cursor = $null
    try { $cursor = Get-BobCursorAgentWeeklyRemaining } catch { $cursor = $null }
    $cursorPct = Get-BobRemainingPctValue $cursor
    $localWeek = $null
    try { $localWeek = Get-BobWeeklyRemaining } catch { $localWeek = $null }
    $thisId = $null
    try { $thisId = Get-ThisMachineId } catch { }

    $hover = $null
    try { $hover = Get-BobTrayHover } catch { $hover = $null }

    $byId = @{}
    foreach ($m in @(Get-BobMachines)) {
        if ($m -and $m.id) { $byId[[string]$m.id] = $m }
    }
    if ($hover -and $hover.machines) {
        foreach ($t in @($hover.machines)) {
            $tid = [string]$t.id
            if (-not $tid) { continue }
            if (-not $byId.ContainsKey($tid)) {
                $byId[$tid] = [pscustomobject]@{
                    id       = $tid
                    kind     = 'windows'
                    cwdRoots = @('C:\ai')
                    hostname = $tid
                }
            }
        }
    }

    $jobCount = @{}
    foreach ($j in @(Get-BobBuilds)) {
        $mid = [string]$j.machine
        if (-not $mid) { continue }
        if (-not $jobCount.ContainsKey($mid)) { $jobCount[$mid] = 0 }
        if ([string]$j.lane -eq 'inbox' -or [string]$j.lane -eq 'running' -or [string]$j.state -eq 'running' -or [string]$j.state -eq 'queued') {
            $jobCount[$mid] = [int]$jobCount[$mid] + 1
        }
    }

    $machines = @()
    foreach ($id in @($byId.Keys | Sort-Object)) {
        $rec = $byId[$id]
        $tile = $null
        if ($hover) { $tile = @($hover.machines | Where-Object { [string]$_.id -eq $id })[0] }
        $alive = $true
        if ($tile -and $tile.reach -eq 'not-in-moot') { $alive = $false }
        $gBuildPct = $null
        $gBuildEnd = $null
        if ($tile -and $null -ne $tile.remaining_pct -and [string]$tile.remaining_pct -ne '') {
            $gBuildPct = [int]$tile.remaining_pct
            $gBuildEnd = [string]$tile.period_end
        }
        elseif ($thisId -and $id -eq $thisId -and $localWeek) {
            $gBuildPct = Get-BobRemainingPctValue $localWeek
            if ($localWeek.period_end) { $gBuildEnd = [string]$localWeek.period_end }
        }
        $jobs = 0
        if ($jobCount.ContainsKey($id)) { $jobs = [int]$jobCount[$id] }
        elseif ($tile -and $null -ne $tile.job_count) { $jobs = [int]$tile.job_count }
        $row = [pscustomobject]@{
            id          = $id
            kind        = $(if ($rec.kind) { [string]$rec.kind } else { 'windows' })
            hostname    = [string]$rec.hostname
            gitEligible = $null
            alive       = $alive
            jobs        = $jobs
            cwdRoots    = @($rec.cwdRoots)
            grok_build  = [pscustomobject]@{ remaining_pct = $gBuildPct; period_end = $gBuildEnd }
            grok_bot    = [pscustomobject]@{ remaining_pct = $null; period_end = $null }
            fuels       = @()
        }
        $row.gitEligible = Test-BobGitEligibleMachine $row
        $row.fuels = @(Get-BobMachineFuels $row)
        $machines += $row
    }

    $onDemandPct = $null
    $onDemandEnabled = $false
    if ($cursor -and $null -ne $cursor.overage_gbp) {
        $onDemandEnabled = $true
    }

    return [pscustomobject]@{
        cursor_models = [pscustomobject]@{
            remaining_pct = $cursorPct
            period_end    = $(if ($cursor -and $cursor.period_end) { [string]$cursor.period_end } else { $null })
            source        = 'account'
        }
        on_demand     = [pscustomobject]@{
            remaining_pct = $onDemandPct
            enabled       = $onDemandEnabled
        }
        copilot       = [pscustomobject]@{
            remaining_pct = $null
            available     = $true
        }
        machines      = $machines
    }
}

function Select-BobGitWorker {
    [CmdletBinding()]
    param(
        $Capacity,
        [string]$Machine,
        [string]$Fuel,
        [switch]$AllowOnDemand,
        [string]$Repo
    )
    if (-not $Capacity) {
        $Capacity = Get-BobCapacity
    }
    else {
        $Capacity = ConvertTo-BobCapacitySnapshot $Capacity
    }
    if (-not $Capacity) {
        return [pscustomobject]@{ wait = $true; machine = $null; fuel = $null; reason = 'no capacity snapshot' }
    }

    $wantMachine = $null
    if ($Machine) {
        try { $wantMachine = ConvertTo-MachineId $Machine } catch { $wantMachine = $Machine.ToLowerInvariant() }
    }
    $wantFuel = $null
    if ($Fuel) { $wantFuel = $Fuel.Trim().ToLowerInvariant() }

    $rows = @($Capacity.machines)
    function Find-BobCapacityMachine {
        param([string]$Id)
        foreach ($m in $rows) {
            if ([string]$m.id -and [string]$m.id.ToLowerInvariant() -eq $Id) { return $m }
        }
        return $null
    }

    if ($wantMachine -and $wantFuel) {
        $m = Find-BobCapacityMachine $wantMachine
        if (-not $m -or -not (Test-BobGitEligibleMachine $m)) {
            return [pscustomobject]@{ wait = $true; machine = $null; fuel = $null; reason = 'pin rejected (dumb or missing)' }
        }
        if (-not (Test-BobMachineCanStrikeFuel -Machine $m -Fuel $wantFuel)) {
            return [pscustomobject]@{ wait = $true; machine = $null; fuel = $null; reason = 'pin rejected (ineligible fuel)' }
        }
        return [pscustomobject]@{ wait = $false; machine = [string]$m.id; fuel = $wantFuel }
    }

    $fuelOrder = @(Get-BobFuelOrder -AllowOnDemand:$AllowOnDemand)
    if ($wantFuel) { $fuelOrder = @($wantFuel) }

    foreach ($fuelName in $fuelOrder) {
        $candidates = @()
        foreach ($m in $rows) {
            if ($wantMachine -and [string]$m.id.ToLowerInvariant() -ne $wantMachine) { continue }
            if (-not (Test-BobGitEligibleMachine $m)) { continue }
            $alive = $true
            if ($null -ne $m.alive -and [string]$m.alive -ne '') {
                try { $alive = [bool]$m.alive } catch { $alive = $true }
            }
            if (-not $alive) { continue }
            if ((Get-BobMachineJobCount $m) -ne 0) { continue }
            if (-not (Test-BobMachineCanStrikeFuel -Machine $m -Fuel $fuelName)) { continue }
            if (-not (Test-BobFuelHasIncluded -Capacity $Capacity -Machine $m -Fuel $fuelName -AllowOnDemand:$AllowOnDemand)) { continue }
            $candidates += $m
        }
        if ($candidates.Count -eq 0) { continue }

        $sorted = @($candidates | Sort-Object -Property @(
                @{ Expression = {
                        $end = Get-BobFuelPeriodEnd -Capacity $Capacity -Machine $_ -Fuel $fuelName
                        if ($end) {
                            try { return [datetime]$end } catch { return [datetime]::MinValue }
                        }
                        return [datetime]::MinValue
                    }; Descending = $true }
                @{ Expression = {
                        if ($Repo -and $_.hasRepo -eq $true) { 0 } else { 1 }
                    } }
                @{ Expression = {
                        $p = $null
                        if ($fuelName -eq 'cursor-models') { $p = Get-BobRemainingPctValue $Capacity.cursor_models }
                        elseif ($fuelName -eq 'grok-build') { $p = Get-BobRemainingPctValue $_.grok_build }
                        elseif ($fuelName -eq 'grok-bot') { $p = Get-BobRemainingPctValue $_.grok_bot }
                        elseif ($fuelName -eq 'on-demand') { $p = Get-BobRemainingPctValue $Capacity.on_demand }
                        elseif ($fuelName -eq 'copilot') { $p = Get-BobRemainingPctValue $Capacity.copilot }
                        if ($null -eq $p) { return -1 }
                        return $p
                    }; Descending = $true }
                @{ Expression = { $g = Get-BobRemainingPctValue $_.grok_build; if ($null -eq $g) { -1 } else { $g } }; Descending = $true }
                @{ Expression = { [string]$_.id } }
            ))
        $pick = $sorted[0]
        return [pscustomobject]@{ wait = $false; machine = [string]$pick.id; fuel = $fuelName }
    }

    return [pscustomobject]@{ wait = $true; machine = $null; fuel = $null; reason = 'no eligible worker' }
}
