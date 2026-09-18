@{
    RootModule        = 'BobBridge.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = '8f3c2a1e-4b6d-4e9a-9c1f-2a7b8d0e5f11'
    Author            = 'Simon Barnett'
    CompanyName       = 'Medatech'
    Copyright         = '(c) 2026 Simon Barnett'
    Description       = 'Thin Bob adapter. Named Grok Bots (Bob/Haitch/Merc) go through Grok Bot API; grok.exe oneshot remains for Fake-Grok and Form Prep. No Windows service, no UI key injection.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
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
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags = @('grok', 'bob', 'bridge', 'formprep')
        }
    }
}
