function Get-BobDigestWebhookLastPostPath {
    Join-Path (Get-BridgeRoot) 'digest-webhook-last.json'
}

function Get-BobDigestWebhookCaptureDir {
    if ($env:BOB_REPORT_CAPTURE_DIR -and $env:BOB_REPORT_CAPTURE_DIR.Trim()) {
        return [IO.Path]::GetFullPath($env:BOB_REPORT_CAPTURE_DIR.Trim())
    }
    return $null
}

function Get-BobDigestWebhookReportUrl {
    $cfg = Get-BobiverseConfig
    if ($cfg -and $cfg.reportUrl -and [string]$cfg.reportUrl.Trim()) {
        return [string]$cfg.reportUrl.Trim()
    }
    if ($env:BOB_REPORT_URL -and $env:BOB_REPORT_URL.Trim()) {
        return [string]$env:BOB_REPORT_URL.Trim()
    }
    return $null
}

function ConvertTo-BobDigestWebhookPayload {
    param(
        [string]$WorkingOn,
        [string]$Repo,
        [string]$MachineId
    )
    $id = $MachineId
    if (-not $id) { $id = Get-ThisMachineId }
    $payload = [ordered]@{
        online     = $true
        status     = 'ok'
        working_on = $WorkingOn
    }
    if ($id) { $payload['id'] = $id }
    if ($Repo) { $payload['repo'] = $Repo }
    return [pscustomobject]$payload
}

function Test-BobDigestWebhookPayloadChanged {
    param($Payload)
    $lastPath = Get-BobDigestWebhookLastPostPath
    $prev = Read-JsonFile $lastPath
    if (-not $prev) { return $true }
    $keys = @('online', 'status', 'working_on', 'repo', 'sha', 'model', 'fuel', 'weekly', 'cursor_label')
    foreach ($k in $keys) {
        $a = $null
        $b = $null
        if ($Payload.PSObject.Properties.Name -contains $k) { $a = [string]$Payload.$k }
        if ($prev.PSObject.Properties.Name -contains $k) { $b = [string]$prev.$k }
        if ($a -ne $b) { return $true }
    }
    return $false
}

function Invoke-BobDigestWebhookPost {
    [CmdletBinding()]
    param(
        [string]$WorkingOn,
        [string]$Repo,
        [string]$MachineId,
        [switch]$Force
    )
    $payload = ConvertTo-BobDigestWebhookPayload -WorkingOn $WorkingOn -Repo $Repo -MachineId $MachineId
    if (-not $Force -and -not (Test-BobDigestWebhookPayloadChanged -Payload $payload)) {
        return [pscustomobject]@{ ok = $true; posted = $false; reason = 'unchanged' }
    }
    $cap = Get-BobDigestWebhookCaptureDir
    if ($cap) {
        New-Item -ItemType Directory -Force -Path $cap | Out-Null
        $n = (Get-ChildItem $cap -Filter 'post-*.json' -ErrorAction SilentlyContinue).Count + 1
        $out = Join-Path $cap ('post-{0}.json' -f $n)
        Write-JsonFile $out $payload
        Write-JsonFile (Get-BobDigestWebhookLastPostPath) $payload
        return [pscustomobject]@{ ok = $true; posted = $true; capture = $out }
    }
    $url = Get-BobDigestWebhookReportUrl
    if (-not $url) {
        Write-JsonFile (Get-BobDigestWebhookLastPostPath) $payload
        return [pscustomobject]@{ ok = $true; posted = $false; reason = 'no_report_url' }
    }
    $secret = $null
    if ($env:BOB_REPORT_SECRET -and $env:BOB_REPORT_SECRET.Trim()) {
        $secret = [string]$env:BOB_REPORT_SECRET.Trim()
    }
    elseif ($env:BOB_IRC_HOME -and $env:BOB_IRC_HOME.Trim()) {
        $sf = Join-Path $env:BOB_IRC_HOME.Trim() 'report.secret'
        if (Test-Path $sf) {
            try { $secret = ([IO.File]::ReadAllText($sf)).Trim() } catch { }
        }
    }
    $headers = @{ 'Content-Type' = 'application/json' }
    if ($secret) { $headers['X-Bob-Secret'] = $secret }
    $json = ($payload | ConvertTo-Json -Depth 6 -Compress)
    try {
        $null = Invoke-RestMethod -Uri $url -Method Post -Body $json -Headers $headers -TimeoutSec 30
        Write-JsonFile (Get-BobDigestWebhookLastPostPath) $payload
        return [pscustomobject]@{ ok = $true; posted = $true; url = $url }
    }
    catch {
        return [pscustomobject]@{ ok = $false; posted = $false; error = $_.Exception.Message }
    }
}
