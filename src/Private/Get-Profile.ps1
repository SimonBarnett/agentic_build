function Get-Profile {
    param(
        [string]$Name = 'generic'
    )
    if (-not $Name) { $Name = 'generic' }
    $root = Initialize-BridgeRoot
    $cfgPath = Join-Path $root 'config.json'
    $cfg = Read-JsonFile $cfgPath
    if (-not $cfg) {
        $bundled = Join-Path (Get-ModuleRoot) 'config\default.json'
        $cfg = Read-JsonFile $bundled
    }
    $profiles = $cfg.profiles
    $p = $null
    if ($profiles) {
        $p = $profiles.$Name
        if (-not $p) {
            foreach ($prop in $profiles.PSObject.Properties) {
                if ($prop.Name -eq $Name) { $p = $prop.Value; break }
            }
        }
    }
    if (-not $p) {
        throw "Unknown profile '$Name'. Known: formprep, teams, mud, generic."
    }
    $maxMachine = 2
    if ($cfg.max_workers_per_machine) { $maxMachine = [int]$cfg.max_workers_per_machine }
    return [pscustomobject]@{
        Name                   = $Name
        Yolo                   = [bool]$p.yolo
        TimeoutSec             = [int]$p.timeoutSec
        MaxPerCwd              = [int]$p.maxPerCwd
        Rules                  = [string]$p.rules
        MaxWorkersPerMachine   = $maxMachine
    }
}
