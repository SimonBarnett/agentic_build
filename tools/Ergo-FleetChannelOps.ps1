# FR #327: durable Ergo channel ops decision (pure; no live ionos / no secrets).
# ChanServ AMODE holds +o for bob-{machine} and Jeeves after registration is on.
# simon never has standing AMODE; +o is granted only when account+certfp map to a fleet machine.

function Get-BobErgoMachineFromNick {
    param([Parameter(Mandatory)][string]$Nick)
    $n = $Nick.Trim()
    if ($n -match '^(?i)bob-(.+)$') { return $Matches[1].ToLowerInvariant() }
    return $null
}

function Test-BobErgoStandingBotOp {
    <#
    Standing ChanServ founder/AMODE +o (after channels.registration is on).
    simon never has standing op.
    #>
    param(
        [Parameter(Mandatory)][string]$Channel,
        [Parameter(Mandatory)][string]$Nick
    )
    $ch = $Channel.Trim().ToLowerInvariant()
    if (-not $ch.StartsWith('#')) { $ch = '#' + $ch }
    $n = $Nick.Trim()
    if ($n -match '^(?i)jeeves$') {
        return ($ch -eq '#bobiverse')
    }
    $machine = Get-BobErgoMachineFromNick -Nick $n
    if ($machine) {
        return ($ch -eq ('#{0}' -f $machine))
    }
    return $false
}

function Test-BobErgoShouldOp {
    <#
    Dynamic +o grant decision for a JOIN (or recheck).
    Returns $true only when the connection may receive +o from the channel op bot.

    Inputs are already-resolved IRC facts (no network I/O):
      Channel, Nick, Account (empty if not logged in), CertFp (empty if none),
      Host (cloak/hostname), FleetRegistry (certfp -> machine name, case-insensitive keys),
      optional BobCloaks (machine -> expected cloak fragment for extra check).
    #>
    param(
        [Parameter(Mandatory)][string]$Channel,
        [Parameter(Mandatory)][string]$Nick,
        [string]$Account = '',
        [string]$CertFp = '',
        [string]$IrcHost = '',
        [hashtable]$FleetRegistry = @{},
        [hashtable]$BobCloaks = @{},
        [bool]$RequireCloakMatch = $false
    )
    $ch = $Channel.Trim().ToLowerInvariant()
    if (-not $ch.StartsWith('#')) { $ch = '#' + $ch }
    $acct = ([string]$Account).Trim().ToLowerInvariant()
    $fp = ([string]$CertFp).Trim().ToLowerInvariant() -replace ':', ''
    $ircHost = ([string]$IrcHost).Trim().ToLowerInvariant()

    # Standing bots: decision is ChanServ AMODE, not this grant path.
    if (Test-BobErgoStandingBotOp -Channel $ch -Nick $Nick) {
        return $true
    }

    # simon path only
    if ($acct -ne 'simon') { return $false }
    if (-not $fp) { return $false }
    if (-not $FleetRegistry -or $FleetRegistry.Count -eq 0) { return $false }

    $machine = $null
    foreach ($k in @($FleetRegistry.Keys)) {
        $kk = ([string]$k).Trim().ToLowerInvariant() -replace ':', ''
        if ($kk -eq $fp) {
            $machine = ([string]$FleetRegistry[$k]).Trim().ToLowerInvariant()
            break
        }
    }
    if (-not $machine) { return $false }

    $allowed = @('#bobiverse', ('#{0}' -f $machine))
    if ($allowed -notcontains $ch) { return $false }

    if ($RequireCloakMatch -and $BobCloaks -and $BobCloaks.ContainsKey($machine)) {
        $want = ([string]$BobCloaks[$machine]).Trim().ToLowerInvariant()
        if ($want -and ($ircHost -notlike "*$want*")) { return $false }
    }
    return $true
}

function Get-BobErgoFleetRegistry {
    param(
        [string]$Path
    )
    if (-not $Path) {
        $Path = Join-Path $env:USERPROFILE '.grok\ergo\fleet-registry.json'
    }
    if (-not (Test-Path -LiteralPath $Path)) { return @{} }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $obj = $raw | ConvertFrom-Json
    $map = @{}
    if ($obj.certfp) {
        foreach ($p in $obj.certfp.PSObject.Properties) {
            $map[[string]$p.Name] = [string]$p.Value
        }
    }
    return $map
}
