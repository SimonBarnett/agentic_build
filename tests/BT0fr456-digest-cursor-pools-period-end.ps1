# BT0 #456: digest merge publishes per-pool period_end (Sand weekly vs billing).
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
try {
    # Private helpers — not exported from BobBridge.psd1.
    . (Join-Path $RepoRoot 'src\Private\Invoke-BobDigestWebhook.ps1')
    . (Join-Path $RepoRoot 'src\Private\Get-BobIrc.ps1')

    $sandEnd = '2026-09-30T17:23:58.025Z'
    $billEnd = '2026-10-16T17:23:01Z'
    $doc = [pscustomobject]@{
        id                = 'flamingo'
        online            = $true
        status            = 'operational'
        weekly            = 70
        period_end        = '2026-10-04T00:36:16Z'
        cursor_label      = '82%'
        cursor_period_end = $billEnd
        sand_period_end   = $sandEnd
        remaining_pct     = 82
        overage_gbp       = 12.5
        pcent             = [pscustomobject]@{
            'grok-chat'        = 23
            'high-cost-models' = 100
            'cursor-models'    = 82
        }
        cursor_pools      = @(
            [pscustomobject]@{ group_id = 'grok-chat'; group_label = 'grok chat'; remaining_pct = 23; period_end = $sandEnd }
            [pscustomobject]@{ group_id = 'high-cost-models'; group_label = 'high cost models'; remaining_pct = 100; period_end = $billEnd }
            [pscustomobject]@{ group_id = 'auto'; group_label = 'Low cost models'; remaining_pct = 82; period_end = $billEnd }
        )
        running           = 0
        queued            = 0
        jobs              = @()
    }

    $payload = Build-BobDigestWebhookMergePayload $doc
    if (-not $payload) { throw 'merge payload null' }
    if (-not $payload.sand_period_end -or [string]$payload.sand_period_end -ne $sandEnd) {
        throw ('sand_period_end missing/wrong: ' + $payload.sand_period_end)
    }
    if (-not $payload.cursor_period_end -or [string]$payload.cursor_period_end -ne $billEnd) {
        throw ('cursor_period_end missing/wrong: ' + $payload.cursor_period_end)
    }
    $pools = @($payload.cursor_pools)
    if ($pools.Count -ne 3) { throw ('expected 3 cursor_pools, got ' + $pools.Count) }
    $byId = @{}
    foreach ($p in $pools) { $byId[[string]$p.group_id] = $p }
    if (-not $byId.ContainsKey('grok-chat')) { throw 'missing grok-chat pool' }
    if ([string]$byId['grok-chat'].period_end -ne $sandEnd) {
        throw ('grok-chat period_end must be Sand weekly, got ' + $byId['grok-chat'].period_end)
    }
    if ([int]$byId['grok-chat'].remaining_pct -ne 23) { throw 'grok-chat remaining wrong' }
    if ([string]$byId['high-cost-models'].period_end -ne $billEnd) {
        throw ('high-cost period_end must be billing, got ' + $byId['high-cost-models'].period_end)
    }
    if ([string]$byId['auto'].period_end -ne $billEnd) {
        throw ('auto period_end must be billing, got ' + $byId['auto'].period_end)
    }

    $fp1 = Get-BobDigestWebhookFingerprint $doc
    $doc2 = $doc | Select-Object *
    $doc2 | Add-Member -NotePropertyName sand_period_end -NotePropertyValue '2026-10-07T17:23:58.025Z' -Force
    $fp2 = Get-BobDigestWebhookFingerprint $doc2
    if ($fp1 -eq $fp2) { throw 'fingerprint must change when sand_period_end moves' }

    $doc3 = $doc | Select-Object *
    $doc3 | Add-Member -NotePropertyName cursor_pools -NotePropertyValue @(
        [pscustomobject]@{ group_id = 'grok-chat'; remaining_pct = 10; period_end = $sandEnd }
        [pscustomobject]@{ group_id = 'high-cost-models'; remaining_pct = 100; period_end = $billEnd }
        [pscustomobject]@{ group_id = 'auto'; remaining_pct = 82; period_end = $billEnd }
    ) -Force
    $fp3 = Get-BobDigestWebhookFingerprint $doc3
    if ($fp1 -eq $fp3) { throw 'fingerprint must change when pool remaining moves' }

    $src = Get-Content (Join-Path $RepoRoot 'src\Private\Get-BobIrc.ps1') -Raw
    if ($src -notmatch 'ConvertTo-BobDigestCursorPoolRows') { throw 'missing ConvertTo-BobDigestCursorPoolRows' }
    if ($src -notmatch 'sand_period_end') { throw 'missing sand_period_end wiring' }
    if ($src -notmatch 'payload\.cursor_pools') { throw 'merge payload must set cursor_pools' }

    Write-Host 'PASS BT0 #456 digest cursor_pools + sand weekly period_end'
    exit 0
}
catch {
    Write-Host ('FAIL BT0 #456: ' + $_.Exception.Message)
    exit 1
}
