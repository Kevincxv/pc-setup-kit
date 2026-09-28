# Makes sure the background maintenance also runs once a day (12:00, or as soon as the PC is on after a missed start),
# not only at login - so a PC that stays on for days still gets its kit updates, drivers and checks. PCs set up before
# this (login trigger only) get the daily trigger added here. Run by claude-bg-maint.ps1 at the end of each run.
# The task is changed through its exact XML (handing PowerShell's principal object back fails when the user name
# equals the computer name). Prints a line only when it changed something.
# -Force: tests (mocked scheduled-task commands); otherwise it never runs inside the test suite.
param([string]$TaskName = 'Claude Background Maintenance', [switch]$Force)
if ($env:PCKIT_IN_TESTS -and -not $Force) { return }
$ErrorActionPreference = 'Continue'
if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) { return }
$xml = [string](Export-ScheduledTask -TaskName $TaskName)
$changed = @()
if ($xml -notmatch '<CalendarTrigger>') {
    $daily = '<CalendarTrigger><StartBoundary>2026-01-01T12:00:00</StartBoundary><Enabled>true</Enabled><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay></CalendarTrigger>'
    $xml = $xml -replace '</Triggers>', "$daily</Triggers>"; $changed += 'daily at 12:00'
}
if ($xml -notmatch '<StartWhenAvailable>true</StartWhenAvailable>') {
    if ($xml -match '<StartWhenAvailable>false</StartWhenAvailable>') { $xml = $xml -replace '<StartWhenAvailable>false</StartWhenAvailable>', '<StartWhenAvailable>true</StartWhenAvailable>' }
    else { $xml = $xml -replace '<Settings>', '<Settings><StartWhenAvailable>true</StartWhenAvailable>' }
    $changed += 'catches up after a missed start'
}
if (-not $changed) { return }
try {
    Register-ScheduledTask -TaskName $TaskName -Xml $xml -Force -ErrorAction Stop | Out-Null
    "Maintenance schedule: now also $($changed -join ', ') (not only at login)"
} catch { "Maintenance schedule: couldn't add the daily run ($($_.Exception.Message)) - next run" }
