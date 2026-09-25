# BT0 FR #341: static + source guards (full Write-BobIrcStatus path is Test-Pack BT0fr341).
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
try {
    . (Join-Path $RepoRoot 'src\Private\Get-BobIrc.ps1')
    if (Format-BobIrcPeerTalkLine -Doc ([pscustomobject]@{ id = 't'; running = 0; queued = 0 })) {
        throw 'Format idle must null'
    }
    if (Format-BobIrcPeerTalkLine -Doc ([pscustomobject]@{ id = 't'; running = 1; queued = 0; model = 'x' })) {
        throw 'Format busy must null'
    }
    if (Get-BobIrcChangeTalkLine -Before $null -After ([pscustomobject]@{ id = 't' })) {
        throw 'ChangeTalk must null'
    }
    if (Get-BobIrcLongRunningTalkLine -Doc ([pscustomobject]@{ id = 't' }) -PrimaryJob ([pscustomobject]@{ id = 'j' })) {
        throw 'LongRunning must null'
    }
    $src = Get-Content (Join-Path $RepoRoot 'src\Private\Get-BobIrc.ps1') -Raw
    if ($src -match 'Add-BobIrcOutboxChannelLine \$talk') { throw 'still appends $talk' }
    if ($src -match 'Add-BobIrcOutboxChannelLine \$warn') { throw 'still appends $warn' }
    if ($src -match 'return "\$mid is idle\."') { throw 'still returns is idle' }
    if ($src -match 'return "\$mid is busy\."') { throw 'still returns is busy' }
    if ($src -match 'return "\$mid is operational\."') { throw 'still returns is operational' }
    if ($src -notmatch 'FR #341') { throw 'missing FR #341 comment' }
    if ($src -notmatch 'Send-BobDigestWebhookIfChanged') { throw 'must keep digest webhook' }
    if ($src -notmatch 'function Add-BobIrcOutboxChannelLine') { throw 'must keep outbox helper for ASSIGN' }
    Write-Host 'PASS BT0 FR #341 no IRC idle/busy status talk'
    exit 0
}
catch {
    Write-Host ('FAIL BT0 FR #341: ' + $_.Exception.Message)
    exit 1
}
