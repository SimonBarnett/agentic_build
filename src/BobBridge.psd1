@{
    RootModule        = 'BobBridge.psm1'
    ModuleVersion     = '0.4.0'
    GUID              = '8f3c2a1e-4b6d-4e9a-9c1f-2a7b8d0e5f11'
    Author            = 'Simon Barnett'
    CompanyName       = 'Medatech'
    Copyright         = '(c) 2026 Simon Barnett'
    Description       = 'Grok Bot skill + pull fleet: start grok.exe builds on named machines as the Windows logon user (MSSQL integrated). No Windows service, no UI key injection.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-BobHealth',
        'Get-BobWorkers',
        'Get-BobAgents',
        'Get-BobMachines',
        'Register-BobMachine',
        'Start-BobWorker',
        'Start-BobBuild',
        'Get-BobCapacity',
        'Get-BobJobModel',
        'Test-BobFuelModelCompatible',
        'Test-BobPacketMissingFuel',
        'Resolve-BobGrokCliModel',
        'Select-BobGitWorker',
        'Get-ThisMachineId',
        'Copy-BobProjectSkills',
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
        'Get-BobLiveGrokAgents',
        'Get-BobTrayBarPaint',
        'Get-BobTrayBarFillRgb',
        'Get-BobTrayAlertKind',
        'Get-BobTrayTitle',
        'Get-BobTrayCursorGroupHelpTooltip',
        'Get-BobWeeklyRemaining',
        'Get-BobCursorAgentWeeklyRemaining',
        'Get-BobCursorSpendingFromApiFixture',
        'Get-BobTrayTipPlacement',
        'Get-BobFleetRegistry',
        'ConvertTo-BobIrcPoint',
        'ConvertFrom-BobIrcPoint',
        'Read-BobIrcPeer',
        'Write-BobIrcStatus',
        'Import-BobIrcPeerTranscript',
        'Import-BobIrcTrayPull',
        'Import-BobWorkerGitShop',
        'Invoke-BobWorkerShopTick',
        'ConvertFrom-BobGitAnnounce',
        'ConvertFrom-BobGitOffer',
        'Get-BobGitAcceptQueue',
        'Start-BobGitAcceptWork',
        'Test-BobGitAcceptWorkerBusy',
        'Request-BobIrcBobiversePull',
        'Sync-BobDigestWebhookAfterBobiversePull',
        'ConvertFrom-BobIrcTrayLine',
        'Get-BobJobRepoStamp',
        'Get-BobIrcShopChannel',
        'Get-BobIrcBuilderChannels',
        'Get-BobWorkerIrcNick',
        'Compact-BobIrcOutbox',
        'Write-BobJobAuditLine',
        'Write-BobJobAuditFromPacket',
        'Invoke-BobGrokTalkTick',
        'Test-BobGrokTalkFuelAllowed',
        'Select-BobGrokTalkFuel',
        'Add-BobGrokTalkCompletion',
        'ConvertTo-BobGrokTalkOutLines'
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
