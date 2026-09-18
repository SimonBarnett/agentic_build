function Register-BobMachine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [string[]]$CwdRoots,
        [string[]]$Profiles = @('formprep', 'teams', 'mud', 'generic')
    )
    $mid = ConvertTo-MachineId $Id
    Initialize-BridgeRoot | Out-Null
    $record = [pscustomobject]@{
        id           = $mid
        hostname     = $env:COMPUTERNAME
        windowsUser  = "$env:USERDOMAIN\$env:USERNAME"
        mssql        = 'integrated'
        grokBot      = $true
        cwdRoots     = @($CwdRoots)
        profiles     = @($Profiles)
        lastSeen     = [DateTime]::UtcNow.ToString('o')
    }
    Write-JsonFile (Join-Path (Get-BridgeRoot) 'machine.json') $record
    $dir = Join-Path (Initialize-FleetRoot) 'machines'
    Write-JsonFile (Join-Path $dir ($mid + '.json')) $record
    $env:BOB_MACHINE_ID = $mid
    return $record
}
