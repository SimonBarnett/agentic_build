function Start-BobBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Machine,
        [Parameter(Mandatory)][string]$Cwd,
        [Parameter(Mandatory)][string]$Goal,
        [string]$Profile = 'generic',
        [string]$From = 'agent',
        [string]$ReplyChannel,
        [string[]]$Constraints,
        [string]$Success = 'Job completes with completion.status=ok',
        [string]$JobId
    )
    if (Test-PromptSecrets -Prompt $Goal) {
        return [pscustomobject]@{ ok = $false; error = 'refuse'; reason = 'goal contains password= or XAI_API_KEY' }
    }
    $null = Get-Profile -Name $Profile
    $mid = ConvertTo-MachineId $Machine
    if (-not $JobId) { $JobId = [guid]::NewGuid().ToString() }
    $cwdVal = $Cwd
    try { $cwdVal = [IO.Path]::GetFullPath($Cwd) } catch { $cwdVal = $Cwd }

    $thisId = Get-ThisMachineId
    if ($thisId -and $thisId -eq $mid) {
        $self = Read-JsonFile (Join-Path (Get-BridgeRoot) 'machine.json')
        if (-not (Test-CwdAllowed -Cwd $cwdVal -MachineRecord $self)) {
            return [pscustomobject]@{ ok = $false; error = 'cwd_not_allowed'; cwd = $cwdVal }
        }
    }

    $packet = [pscustomobject]@{
        id             = $JobId
        from           = $From
        to_session     = $JobId
        goal           = $Goal
        constraints    = @($Constraints)
        success        = $Success
        reply_channel  = $ReplyChannel
        machine        = $mid
        cwd            = $cwdVal
        profile        = $Profile
        createdAt      = [DateTime]::UtcNow.ToString('o')
        windowsUser    = "$env:USERDOMAIN\$env:USERNAME"
        mssql          = 'integrated'
    }
    $path = Get-FleetJobPath -Lane inbox -Machine $mid -JobId $JobId
    Write-JsonFile $path $packet
    Write-Audit -SessionId $JobId -Cwd $cwdVal -Profile $Profile -Prompt $Goal
    Send-FleetReply -ReplyChannel $ReplyChannel -Text "queued $JobId on $mid ($Profile)"
    return [pscustomobject]@{
        ok      = $true
        jobId   = $JobId
        machine = $mid
        path    = $path
        lane    = 'inbox'
    }
}
