# DO NOT EDIT — ionos IRC TSR watchdog (restart if dead/stale).
$env:BOB_MACHINE_ID = 'ionos'
& 'C:\ai\agentic_build\tools\Watch-IrcTsr.ps1' -PollSec 30 -SilenceSec 60 -RestartAfterSec 600
