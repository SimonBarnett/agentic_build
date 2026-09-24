# Stop hung talk-seat python on one --home, optionally roll a replacement.
# See .grok/skills/killproc/SKILL.md. Never print connect.password.
param(
    [Parameter(Mandatory = $true)]
    [string]$IrcHome,
    [string]$Nick = '',
    [switch]$Roll
)
$ErrorActionPreference = 'Stop'
$resolved = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($IrcHome))
if (-not (Test-Path -LiteralPath $resolved)) {
    Write-Error "home missing: $resolved"
}
$coord = Join-Path $resolved 'coordinator.pid'
if (-not $Nick -and (Test-Path -LiteralPath $coord)) {
    Get-Content -LiteralPath $coord | ForEach-Object {
        if ($_ -match '^nick=(.+)$') { $Nick = $Matches[1].Trim() }
    }
}
$hits = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object {
    $_.CommandLine -match 'irc_(agent|listen)\.py' -and
    $_.CommandLine -match [regex]::Escape($resolved)
})
foreach ($h in $hits) {
    $cl = [string]$h.CommandLine
    $snip = $cl.Substring(0, [Math]::Min(120, $cl.Length))
    Stop-Process -Id ([int]$h.ProcessId) -Force -ErrorAction SilentlyContinue
    Write-Output ("INFO killed {0} {1}" -f $h.ProcessId, $snip)
}
if (-not $Roll) {
    Write-Output "INFO killed=$($hits.Count) home=$resolved nick=$Nick (no roll)"
    return
}
if (-not $Nick) { Write-Error '-Roll needs -Nick or coordinator.pid nick=' }
$mid = $Nick.Trim()
if ($mid -match '^bob-(.+)$') { $mid = $Matches[1] }
elseif ($mid -match '^(.*)-\d+$') { $mid = $Matches[1] }
if (-not $mid) { $mid = 'flamingo' }
$channel = "#bobiverse,#$mid"
$seat = ''
if (Test-Path -LiteralPath $coord) {
    Get-Content -LiteralPath $coord | ForEach-Object {
        if ($_ -match '^seat=(.+)$') { $seat = $Matches[1].Trim() }
    }
}
$pwFile = Join-Path $env:USERPROFILE '.grok\ergo\connect.password'
if (-not (Test-Path -LiteralPath $pwFile)) { Write-Error "missing $pwFile" }
$env:AGENTIC_IRC_PASSWORD = (Get-Content -LiteralPath $pwFile -Raw).Trim()
$env:AGENTIC_IRC_DEBUG = '1'
$env:AGENTIC_IRC_HOME = $resolved
if ($seat) { $env:AGENTIC_IRC_SEAT_PID = $seat }
$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONUNBUFFERED = '1'
$py = (Get-Command python -ErrorAction Stop).Source
$scripts = if (Test-Path 'C:\ai\agentic_irc\scripts\irc_agent.py') {
    'C:\ai\agentic_irc\scripts'
} else {
    Join-Path $env:USERPROFILE '.grok\skills\agentic-irc\scripts'
}
$agent = Start-Process -FilePath $py -ArgumentList @(
    '-u', (Join-Path $scripts 'irc_agent.py'),
    '--host', 'irc.ntsa.uk', '--port', '6697',
    '--nick', $Nick, '--channel', $channel,
    '--home', $resolved, '--announce-key'
) -WorkingDirectory (Split-Path $scripts -Parent) -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 3
$listenLog = Join-Path $resolved 'listen.stdout.log'
$listen = Start-Process -FilePath $py -ArgumentList @(
    '-u', (Join-Path $scripts 'irc_listen.py'), '--home', $resolved
) -WorkingDirectory $resolved -WindowStyle Hidden -RedirectStandardOutput $listenLog -PassThru
@(
    "nick=$Nick"
    $(if ($seat) { "seat=$seat" } else { 'seat=' })
    "listen=$($listen.Id)"
    "agent=$($agent.Id)"
    "home=$resolved"
) | Set-Content -LiteralPath $coord -Encoding utf8
Write-Output "INFO rolled nick=$Nick agent=$($agent.Id) listen=$($listen.Id) home=$resolved"
