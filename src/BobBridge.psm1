$PublicDir  = Join-Path $PSScriptRoot 'Public'
$PrivateDir = Join-Path $PSScriptRoot 'Private'

Get-ChildItem -Path $PrivateDir -Filter '*.ps1' -ErrorAction Stop | ForEach-Object {
    . $_.FullName
}
Get-ChildItem -Path $PublicDir -Filter '*.ps1' -ErrorAction Stop | ForEach-Object {
    . $_.FullName
}

Export-ModuleMember -Function @(
    'Get-BobHealth',
    'Get-BobWorkers',
    'Get-BobAgents',
    'Get-BobMachines',
    'Register-BobMachine',
    'Start-BobWorker',
    'Start-BobBuild',
    'Get-BobBuild',
    'Get-BobBuilds',
    'Send-BobBuildSpec',
    'Stop-BobBuild',
    'Invoke-BobFleetTick',
    'Send-BobPrompt',
    'Get-BobStatus',
    'Get-BobResult',
    'Stop-BobWorker',
    'Export-BobTranscript',
    'Get-BobStallAlerts',
    'Get-BobTrayHover',
    'Get-BobTrayBarPaint',
    'Get-BobTrayBarFillRgb',
    'Get-BobTrayAlertKind',
    'Get-BobTrayTitle',
    'Get-BobWeeklyRemaining',
    'Get-BobTrayTipPlacement',
    'Get-BobFleetRegistry',
    'ConvertTo-BobIrcPoint',
    'ConvertFrom-BobIrcPoint',
    'Read-BobIrcPeer'
)
