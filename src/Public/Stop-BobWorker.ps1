function Stop-BobWorker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId
    )
    $overlay = Read-Overlay
    $overlay.workers = @($overlay.workers | Where-Object { $_.sessionId -ne $SessionId })
    Write-Overlay $overlay

    $dir = Get-WorkerDir $SessionId
    $statusPath = Join-Path $dir 'status.json'
    $status = Read-JsonFile $statusPath
    if ($status -and $status.pid) {
        try { Stop-ProcessTree -ProcessId ([int]$status.pid) } catch { }
    }
    if ($status) {
        $status.state = 'stopped'
        $status.updatedAt = [DateTime]::UtcNow.ToString('o')
        Write-JsonFile $statusPath $status
    }
    return [pscustomobject]@{ ok = $true; sessionId = $SessionId; state = 'stopped' }
}
