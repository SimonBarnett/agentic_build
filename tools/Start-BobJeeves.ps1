# NSSM service body for BobJeeves. One python, foreground, until the service stops.
# IRC --home is .agentic-irc-jeeves. BOB_DIGEST_HOME is .agentic-irc-bobiverse
# so fleet_digest_home() drains chair-outbox.txt where bobcallback writes.
# Do not call Install-BobChair.ps1 from here (that restarts this service).
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$JeevesHome,
    [string]$DigestHome,
    [string]$PasswordFile,
    [string]$IrcRoot,
    [string]$Python,
    [string]$Nick = 'Jeeves',
    [string]$IrcHost = 'irc.ntsa.uk',
    [int]$IrcPort = 6697
)

$ErrorActionPreference = 'Stop'
if (-not $JeevesHome) { $JeevesHome = Join-Path $env:USERPROFILE '.agentic-irc-jeeves' }
if (-not $DigestHome) { $DigestHome = Join-Path $env:USERPROFILE '.agentic-irc-bobiverse' }
if (-not $PasswordFile) { $PasswordFile = Join-Path $env:USERPROFILE '.grok\ergo\connect.password' }
$JeevesHome = [IO.Path]::GetFullPath($JeevesHome)
$DigestHome = [IO.Path]::GetFullPath($DigestHome)
if ($JeevesHome.TrimEnd('\') -eq $DigestHome.TrimEnd('\')) {
    throw 'Jeeves --home must be .agentic-irc-jeeves, not the bobiverse digest home'
}
if (-not $IrcRoot) {
    if (Test-Path 'C:\ai\agentic_irc') { $IrcRoot = 'C:\ai\agentic_irc' }
    elseif (Test-Path 'D:\ai\agentic_irc') { $IrcRoot = 'D:\ai\agentic_irc' }
    else { throw 'agentic_irc root not found' }
}
$IrcRoot = [IO.Path]::GetFullPath($IrcRoot)
$agent = Join-Path $IrcRoot 'scripts\irc_agent.py'
if (-not (Test-Path -LiteralPath $agent)) { throw "missing $agent" }
if (-not $Python) { throw 'python.exe path required' }
if (-not (Test-Path -LiteralPath $Python)) { throw "missing $Python" }
if (-not (Test-Path -LiteralPath $PasswordFile)) {
    throw 'missing ~/.grok/ergo/connect.password (never commit it)'
}
if (-not $Nick.Trim()) { $Nick = 'Jeeves' }
$Nick = $Nick.Trim()

New-Item -ItemType Directory -Force -Path $JeevesHome, $DigestHome | Out-Null

$nickRe = [regex]::Escape("--nick $Nick")
$jeevesRe = [regex]::Escape($JeevesHome)
$digestRe = [regex]::Escape($DigestHome)
$prior = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -and $_.CommandLine -match 'irc_agent\.py' -and (
            $_.CommandLine -match $nickRe -or
            ($_.CommandLine -match '--chair' -and (
                $_.CommandLine -match $jeevesRe -or $_.CommandLine -match $digestRe
            ))
        )
    })
foreach ($p in $prior) {
    Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue
}
if ($prior.Count -gt 0) { Start-Sleep -Seconds 2 }

$env:BOB_DIGEST_HOME = $DigestHome
$env:AGENTIC_IRC_CHAIR_NICK = $Nick
$env:AGENTIC_IRC_HOME = $JeevesHome
$env:AGENTIC_IRC_DEBUG = '1'
$env:AGENTIC_IRC_PASSWORD = (Get-Content -LiteralPath $PasswordFile -Raw).Trim()

$jobHandle = [IntPtr]::Zero
try {
    if (-not ('BobJeevesJob' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BobJeevesJob {
    [StructLayout(LayoutKind.Sequential)]
    public struct BASIC {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public long Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct EXTENDED {
        public BASIC BasicLimitInformation;
        public long ReadOperationCount;
        public long WriteOperationCount;
        public long OtherOperationCount;
        public long ReadTransferCount;
        public long WriteTransferCount;
        public long OtherTransferCount;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr CreateJobObject(IntPtr a, string name);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetInformationJobObject(IntPtr hJob, int cls, IntPtr info, uint len);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);
    public static IntPtr CreateKillOnClose() {
        IntPtr h = CreateJobObject(IntPtr.Zero, null);
        EXTENDED info = new EXTENDED();
        info.BasicLimitInformation.LimitFlags = 0x2000;
        int size = Marshal.SizeOf(typeof(EXTENDED));
        IntPtr ptr = Marshal.AllocHGlobal(size);
        try {
            Marshal.StructureToPtr(info, ptr, false);
            SetInformationJobObject(h, 9, ptr, (uint)size);
        } finally {
            Marshal.FreeHGlobal(ptr);
        }
        return h;
    }
}
'@
    }
    $jobHandle = [BobJeevesJob]::CreateKillOnClose()
} catch {
    Write-Host "BobJeeves: job object unavailable ($($_.Exception.Message)); stop still kills prior chair on next start"
    $jobHandle = [IntPtr]::Zero
}

Write-Host "BobJeeves: nick=$Nick home=$JeevesHome BOB_DIGEST_HOME=$DigestHome host=${IrcHost}:$IrcPort"

$argList = @(
    '-u', $agent,
    '--host', $IrcHost,
    '--port', "$IrcPort",
    '--nick', $Nick,
    '--channel', '#bobiverse',
    '--home', $JeevesHome,
    '--chair'
)
$proc = Start-Process -FilePath $Python -ArgumentList $argList -WorkingDirectory $IrcRoot -PassThru -NoNewWindow
if ($jobHandle -ne [IntPtr]::Zero -and $proc) {
    try { [void][BobJeevesJob]::AssignProcessToJobObject($jobHandle, $proc.Handle) } catch { }
}
Wait-Process -Id $proc.Id
exit $proc.ExitCode
