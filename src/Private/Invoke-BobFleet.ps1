function Get-FleetRoot {
    Join-Path (Get-BridgeRoot) 'fleet'
}

function Initialize-FleetRoot {
    $root = Get-FleetRoot
    foreach ($n in @('inbox', 'running', 'outbox', 'machines', 'cancel', 'followup')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $root $n) | Out-Null
    }
    return $root
}

function Get-ThisMachineId {
    if ($env:BOB_MACHINE_ID -and $env:BOB_MACHINE_ID.Trim()) {
        return $env:BOB_MACHINE_ID.Trim().ToLowerInvariant()
    }
    $path = Join-Path (Get-BridgeRoot) 'machine.json'
    $m = Read-JsonFile $path
    if ($m -and $m.id) { return ([string]$m.id).ToLowerInvariant() }
    return $null
}

function ConvertTo-MachineId {
    param([Parameter(Mandatory)][string]$Name)
    $id = $Name.Trim().ToLowerInvariant()
    if ($id -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') {
        throw "invalid machine id '$Name'"
    }
    return $id
}

function Get-FleetJobPath {
    param(
        [Parameter(Mandatory)][ValidateSet('inbox', 'running', 'outbox', 'cancel')][string]$Lane,
        [Parameter(Mandatory)][string]$Machine,
        [Parameter(Mandatory)][string]$JobId
    )
    $mid = ConvertTo-MachineId $Machine
    $dir = Join-Path (Initialize-FleetRoot) (Join-Path $Lane $mid)
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Join-Path $dir ($JobId + '.json')
}

function Read-FleetJob {
    param([Parameter(Mandatory)][string]$JobId)
    $root = Initialize-FleetRoot
    foreach ($lane in @('running', 'inbox', 'outbox')) {
        $hits = @(Get-ChildItem (Join-Path $root $lane) -Recurse -Filter ($JobId + '.json') -ErrorAction SilentlyContinue)
        if ($hits.Count -gt 0) {
            $job = Read-JsonFile $hits[0].FullName
            if ($job) {
                $job | Add-Member -NotePropertyName lane -NotePropertyValue $lane -Force
                $job | Add-Member -NotePropertyName path -NotePropertyValue $hits[0].FullName -Force
                return $job
            }
        }
    }
    return $null
}

function Test-CwdAllowed {
    param(
        [Parameter(Mandatory)][string]$Cwd,
        $MachineRecord
    )
    if (-not $MachineRecord -or -not $MachineRecord.cwdRoots) { return $true }
    $full = [IO.Path]::GetFullPath($Cwd)
    foreach ($root in @($MachineRecord.cwdRoots)) {
        if (-not $root) { continue }
        try { $r = [IO.Path]::GetFullPath([string]$root) }
        catch { continue }
        if ($full.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function New-FleetPrompt {
    param($Packet)
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("Goal: $($Packet.goal)")
    if ($Packet.success) { [void]$lines.Add("Success: $($Packet.success)") }
    $cons = @($Packet.constraints)
    if ($cons.Count -gt 0) {
        [void]$lines.Add('Constraints:')
        foreach ($c in $cons) { [void]$lines.Add("- $c") }
    }
    [void]$lines.Add("Machine: $($Packet.machine)")
    [void]$lines.Add("Cwd: $($Packet.cwd)")
    [void]$lines.Add("Profile: $($Packet.profile)")
    [void]$lines.Add('MSSQL: Windows integrated auth as the logon user. No SQL passwords.')
    return ($lines -join "`n")
}

function Write-FleetHeartbeat {
    $id = Get-ThisMachineId
    if (-not $id) { return }
    $path = Join-Path (Get-BridgeRoot) 'machine.json'
    $rec = Read-JsonFile $path
    if (-not $rec) { return }
    $rec | Add-Member -NotePropertyName lastSeen -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    $rec | Add-Member -NotePropertyName windowsUser -NotePropertyValue "$env:USERDOMAIN\$env:USERNAME" -Force
    Write-JsonFile $path $rec
    Write-JsonFile (Join-Path (Initialize-FleetRoot) (Join-Path 'machines' ($id + '.json'))) $rec
}

function Test-FleetCancel {
    param([string]$Machine, [string]$JobId)
    Test-Path (Get-FleetJobPath -Lane cancel -Machine $Machine -JobId $JobId)
}

function Complete-FleetJob {
    param(
        $Packet,
        [string]$FromPath,
        [string]$State,
        $Completion,
        [string]$SessionId
    )
    Write-FleetHeartbeat
    $packet = $Packet
    $packet | Add-Member -NotePropertyName state -NotePropertyValue $State -Force
    $packet | Add-Member -NotePropertyName completedAt -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    if ($Completion) { $packet | Add-Member -NotePropertyName completion -NotePropertyValue $Completion -Force }
    if ($SessionId) { $packet | Add-Member -NotePropertyName sessionId -NotePropertyValue $SessionId -Force }
    $out = Get-FleetJobPath -Lane outbox -Machine $packet.machine -JobId $packet.id
    Write-JsonFile $out $packet
    if ($FromPath -and (Test-Path $FromPath)) {
        Remove-Item -Force $FromPath -ErrorAction SilentlyContinue
    }
    $follow = Join-Path (Initialize-FleetRoot) (Join-Path 'followup' (Join-Path $packet.machine ($packet.id + '.json')))
    if (Test-Path $follow) { Remove-Item -Force $follow -ErrorAction SilentlyContinue }
    Send-FleetReply -ReplyChannel $packet.reply_channel -Text "$($packet.machine) $State $($packet.id): $(if ($Completion) { $Completion.summary } else { $State })"
    return $packet
}

function Invoke-BobFleetTick {
    Invoke-BobFleetOnce
}

function Invoke-BobFleetOnce {
    $thisId = Get-ThisMachineId
    if (-not $thisId) {
        return [pscustomobject]@{ ok = $false; error = 'machine_unregistered' }
    }
    Write-FleetHeartbeat
    $inboxDir = Join-Path (Initialize-FleetRoot) (Join-Path 'inbox' $thisId)
    New-Item -ItemType Directory -Force -Path $inboxDir | Out-Null
    $files = @(Get-ChildItem $inboxDir -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($files.Count -eq 0) {
        return [pscustomobject]@{ ok = $true; claimed = $false }
    }
    $file = $files[0]
    $packet = Read-JsonFile $file.FullName
    if (-not $packet) {
        Remove-Item -Force $file.FullName
        return [pscustomobject]@{ ok = $false; error = 'bad_packet' }
    }

    if (Test-FleetCancel -Machine $thisId -JobId $packet.id) {
        return Complete-FleetJob -Packet $packet -FromPath $file.FullName -State 'stopped'
    }

    $self = Read-JsonFile (Join-Path (Get-BridgeRoot) 'machine.json')
    if (-not (Test-CwdAllowed -Cwd $packet.cwd -MachineRecord $self)) {
        $comp = [pscustomobject]@{ status = 'failed'; summary = 'cwd_not_allowed'; needs_human = $true }
        return Complete-FleetJob -Packet $packet -FromPath $file.FullName -State 'failed' -Completion $comp
    }

    $runningPath = Get-FleetJobPath -Lane running -Machine $thisId -JobId $packet.id
    Move-Item -Force $file.FullName $runningPath
    $packet | Add-Member -NotePropertyName state -NotePropertyValue 'running' -Force
    $packet | Add-Member -NotePropertyName claimedAt -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    Write-JsonFile $runningPath $packet
    Send-FleetReply -ReplyChannel $packet.reply_channel -Text "$thisId running $($packet.id)"

    $prompt = New-FleetPrompt -Packet $packet
    $start = Start-BobWorker -Cwd $packet.cwd -Prompt $prompt -Profile $packet.profile -Title "fleet-$($packet.id)" -SessionId $packet.id -Force
    $sessionId = $start.sessionId

    $followPath = Join-Path (Initialize-FleetRoot) (Join-Path 'followup' (Join-Path $thisId ($packet.id + '.json')))
    if ((Test-Path $followPath) -and $sessionId) {
        $follows = Read-JsonFile $followPath
        foreach ($item in @($follows)) {
            if (Test-FleetCancel -Machine $thisId -JobId $packet.id) { break }
            $p = $item.prompt
            if (-not $p) { $p = [string]$item }
            if ($p) { Send-BobPrompt -SessionId $sessionId -Prompt $p | Out-Null }
        }
    }

    if (Test-FleetCancel -Machine $thisId -JobId $packet.id) {
        try { Stop-BobWorker -SessionId $sessionId | Out-Null } catch { }
        return Complete-FleetJob -Packet $packet -FromPath $runningPath -State 'stopped' -Completion $start.completion -SessionId $sessionId
    }

    $state = 'done'
    if ($start.completion -and $start.completion.status -eq 'stopped') { $state = 'stopped' }
    elseif ($start.completion -and $start.completion.status -eq 'failed') { $state = 'failed' }
    elseif ($start.completion -and $start.completion.status -eq 'blocked') { $state = 'blocked' }
    elseif (-not $start.ok) { $state = 'failed' }
    return Complete-FleetJob -Packet $packet -FromPath $runningPath -State $state -Completion $start.completion -SessionId $sessionId
}

function Send-FleetReply {
    param(
        [string]$ReplyChannel,
        [string]$Text
    )
    if (-not $ReplyChannel) { return }
    if (Test-BobUsesFakeGrok) { return }
    if (-not (Test-GrokBotAvailable)) { return }
    try {
        Invoke-GrokBotApi -Action send -Agent $ReplyChannel -Text $Text -TimeoutSec 60 | Out-Null
    }
    catch { }
}
