function Test-SameCwd {
    param(
        [Parameter(Mandatory)][string]$Cwd,
        $Overlay
    )
    if (-not $Overlay) { $Overlay = Read-Overlay }
    $full = [IO.Path]::GetFullPath($Cwd)
    $hits = @()
    foreach ($w in @($Overlay.workers)) {
        if (-not $w.cwd) { continue }
        try {
            $other = [IO.Path]::GetFullPath($w.cwd)
        }
        catch {
            $other = [string]$w.cwd
        }
        if ([string]::Equals($other, $full, [StringComparison]::OrdinalIgnoreCase)) {
            $hits += $w
        }
    }
    return $hits
}

function Test-PromptSecrets {
    param([string]$Prompt)
    if ($Prompt -match '(?i)password\s*=') {
        return $true
    }
    if ($Prompt -match '(?i)XAI_API_KEY') {
        return $true
    }
    return $false
}
