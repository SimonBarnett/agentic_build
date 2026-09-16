function Export-BobTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [string]$Output
    )
    $dir = Get-WorkerDir $SessionId
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'outbox') | Out-Null
    if (-not $Output) {
        $Output = Join-Path $dir 'outbox\transcript.md'
    }
    $r = Invoke-Grok -Args @('export', $SessionId, $Output) -WorkingDirectory $dir -TimeoutSec 60
    return [pscustomobject]@{
        ok        = ($r.ExitCode -eq 0)
        path      = $Output
        exitCode  = $r.ExitCode
        stderr    = $r.Stderr
    }
}
