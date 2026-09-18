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
    'Start-BobWorker',
    'Send-BobPrompt',
    'Get-BobStatus',
    'Get-BobResult',
    'Stop-BobWorker',
    'Export-BobTranscript'
)
