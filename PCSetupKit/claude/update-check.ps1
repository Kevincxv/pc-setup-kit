# Every 4 hours (the scheduled task "PC Setup Kit Update Check", made by ensure-schedule.ps1) on top of the login and
# daily maintenance: is there a newer tested release? One small request to GitHub. If one is installed, its self-test
# runs right away - and a release that fails it on this PC goes back to the version before (self-test.ps1 +
# kit-update.ps1 -Rollback). No restart needed: everything is scripts; the tray reloads itself. What happened goes to
# maint-history (the app's History page). Waits while a game runs (the check itself is invisible, but the tray reloads).
param([string]$Dir = $PSScriptRoot)
$ErrorActionPreference = 'SilentlyContinue'
# the background maintenance running right now updates the kit itself: nothing to do. (Only looked at - holding its lock
# would make a maintenance starting meanwhile skip its whole run.)
$bm = $null; if (-not $env:PCKIT_IN_TESTS -and [Threading.Mutex]::TryOpenExisting('Global\ClaudeBgMaint', [ref]$bm)) { $bm.Dispose(); return }
$mx = New-Object Threading.Mutex($false, 'Global\PCSetupKitUpdateCheck')
if (-not $mx.WaitOne(0)) { return }
try {
    if ((Test-Path "$Dir\game-check.ps1") -and (& "$Dir\game-check.ps1")) { return }   # next check
    if ((Test-Path "$Dir\paused.ps1") -and (& "$Dir\paused.ps1")) { return }           # paused by the owner
    $t0 = Get-Date
    $lines = @(& "$Dir\kit-update.ps1")
    if ($lines -match '^PC Setup Kit updated') { $lines += @(& "$Dir\self-test.ps1") }   # (self-test sees the new version and runs)
    $lines = @($lines | Where-Object { $_ })
    if ($lines) {
        $h = New-Item "$Dir\maint-history" -ItemType Directory -Force
        @("Checked $($t0.ToString('g')) in $([int]((Get-Date) - $t0).TotalSeconds) s (update check)") + $lines | Set-Content "$h\report-$($t0.ToString('yyyyMMdd-HHmmss'))-update-check.txt" -Encoding UTF8
    }
    $lines
}
finally { $mx.ReleaseMutex() }
