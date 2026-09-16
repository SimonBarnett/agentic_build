function Get-BobHealth {
    [CmdletBinding()]
    param()

    $root = Initialize-BridgeRoot
    $overlay = Read-Overlay
    $exe = Get-GrokExe
    $installed = [bool]($exe -and (Test-Path $exe))
    $version = $null
    $loggedIn = $false
    if ($installed) {
        try {
            $r = Invoke-Grok -Args @('version') -WorkingDirectory $root -TimeoutSec 30
            if ($r.ExitCode -eq 0 -and $r.Stdout) {
                $version = ($r.Stdout.Trim() -split "`r?`n")[0]
                $loggedIn = $true
            }
            else {
                $r2 = Invoke-Grok -Args @('--version') -WorkingDirectory $root -TimeoutSec 30
                if ($r2.ExitCode -eq 0 -and $r2.Stdout) {
                    $version = ($r2.Stdout.Trim() -split "`r?`n")[0]
                    $loggedIn = $true
                }
            }
        }
        catch {
            $installed = $false
        }
    }

    $ok = $installed -and $loggedIn
    return [pscustomobject]@{
        ok             = $ok
        grok_installed = $installed
        logged_in      = $loggedIn
        grok_version   = $version
        worker_count   = @($overlay.workers).Count
        leader_up      = $null
        machine        = $env:COMPUTERNAME
    }
}
