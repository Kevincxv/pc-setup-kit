# Also sets up the update guard task (below). Makes sure the background maintenance also runs once a day (12:00, or as soon as the PC is on after a missed start),
# not only at login - so a PC that stays on for days still gets its kit updates, drivers and checks. PCs set up before
# this (login trigger only) get the daily trigger added here. Run by claude-bg-maint.ps1 at the end of each run.
# The task is changed through its exact XML (handing PowerShell's principal object back fails when the user name
# equals the computer name). Prints a line only when it changed something.
# -Force: tests (mocked scheduled-task commands); otherwise it never runs inside the test suite.
param([string]$TaskName = 'Claude Background Maintenance', [string]$GuardTask = 'PC Setup Kit Update Guard', [string]$CheckTask = 'PC Setup Kit Update Check', [string]$NightTask = 'Messiah Night Restart', [string]$TrayTask = 'Messiah Tray', [switch]$Force)
if ($env:PCKIT_IN_TESTS -and -not $Force) { return }
$ErrorActionPreference = 'Continue'
# The update guard: 2 minutes after Windows Update installed something (WindowsUpdateClient 19) or a driver was installed
# (UserPnp 20001), after-update.ps1 puts back what the update undid - instead of waiting for the next login. As the
# owner (the settings are theirs), elevated, hidden, one run per burst of events.
# every kit task that was switched off goes back on - by a "cleaner" app, an update or a click in Task Scheduler (no Settings
# switch works by disabling a task, so this never overrides the owner). Run by the maintenance AND the 4-hourly check:
# each repairs the other's task (10/2)
$kitTasks = @($TaskName, $GuardTask, $CheckTask, $NightTask, $TrayTask)
foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -in $kitTasks -and $_.State -eq 'Disabled' })) {
    try { Enable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null; "Schedule: the task $($t.TaskName) had been switched off - on again" }
    catch { "Schedule: couldn't switch the task $($t.TaskName) back on ($($_.Exception.Message)) - next run" }
}
if ((Test-Path "$PSScriptRoot\after-update.ps1") -and -not (Get-ScheduledTask -TaskName $GuardTask -ErrorAction SilentlyContinue)) {
    $sub = "&lt;QueryList&gt;&lt;Query Id='0' Path='System'&gt;&lt;Select Path='System'&gt;*[System[(Provider[@Name='Microsoft-Windows-WindowsUpdateClient'] and EventID=19) or (Provider[@Name='Microsoft-Windows-UserPnp'] and EventID=20001)]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;"
    $gx = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>PC Setup Kit: puts back the tweaks an update or driver install undid, right away.</Description></RegistrationInfo>
  <Triggers><EventTrigger><Enabled>true</Enabled><Delay>PT2M</Delay><Subscription>$sub</Subscription></EventTrigger></Triggers>
  <Principals><Principal id="Author"><UserId>$env:USERDOMAIN\$env:USERNAME</UserId><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><ExecutionTimeLimit>PT30M</ExecutionTimeLimit><Priority>7</Priority></Settings>
  <Actions Context="Author"><Exec><Command>$env:SystemRoot\System32\conhost.exe</Command><Arguments>--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\after-update.ps1"</Arguments></Exec></Actions>
</Task>
"@
    try { Register-ScheduledTask -TaskName $GuardTask -Xml $gx -Force -ErrorAction Stop | Out-Null; 'Update guard: settings an update undoes are now put back right after each update or driver install' }
    catch { "Update guard: couldn't set it up ($($_.Exception.Message)) - next run" }
}
# The update check: every 4 hours (catching up after sleep), a newer tested release installs right away - not only at
# login or at noon (update-check.ps1). Not on the PC the kit is developed on (it publishes; kit-update skips it too).
if ((Test-Path "$PSScriptRoot\update-check.ps1") -and -not (Get-ScheduledTask -TaskName $CheckTask -ErrorAction SilentlyContinue)) {
    $cx = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>PC Setup Kit: installs a newer tested release of the kit (every 4 hours).</Description></RegistrationInfo>
  <Triggers><CalendarTrigger><StartBoundary>2026-01-01T02:00:00</StartBoundary><Enabled>true</Enabled><Repetition><Interval>PT4H</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay></CalendarTrigger></Triggers>
  <Principals><Principal id="Author"><UserId>$env:USERDOMAIN\$env:USERNAME</UserId><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><StartWhenAvailable>true</StartWhenAvailable><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><RunOnlyIfNetworkAvailable>true</RunOnlyIfNetworkAvailable><ExecutionTimeLimit>PT1H</ExecutionTimeLimit><Priority>7</Priority></Settings>
  <Actions Context="Author"><Exec><Command>$env:SystemRoot\System32\conhost.exe</Command><Arguments>--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\update-check.ps1"</Arguments></Exec></Actions>
</Task>
"@
    try { Register-ScheduledTask -TaskName $CheckTask -Xml $cx -Force -ErrorAction Stop | Out-Null; 'Update check: a newer kit release now installs within 4 hours (not only at login)' }
    catch { "Update check: couldn't set it up ($($_.Exception.Message)) - next run" }
}
# The night restart: every 30 minutes from 3:30 to 5:30 AM, restart-night.ps1 finishes pending updates with a restart -
# only while nobody uses the PC (its own checks, and the Settings switch). Never wakes the PC, never catches up later.
if ((Test-Path "$PSScriptRoot\restart-night.ps1") -and -not (Get-ScheduledTask -TaskName $NightTask -ErrorAction SilentlyContinue)) {
    $nx = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>Messiah: finishes pending updates with a restart at night, only while nobody uses the PC (Settings: Restart at night to finish updates).</Description></RegistrationInfo>
  <Triggers><CalendarTrigger><StartBoundary>2026-01-01T03:30:00</StartBoundary><Enabled>true</Enabled><Repetition><Interval>PT30M</Interval><Duration>PT2H</Duration><StopAtDurationEnd>false</StopAtDurationEnd></Repetition><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay></CalendarTrigger></Triggers>
  <Principals><Principal id="Author"><UserId>$env:USERDOMAIN\$env:USERNAME</UserId><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><StartWhenAvailable>false</StartWhenAvailable><WakeToRun>false</WakeToRun><DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>true</StopIfGoingOnBatteries><ExecutionTimeLimit>PT10M</ExecutionTimeLimit><Enabled>true</Enabled></Settings>
  <Actions Context="Author"><Exec><Command>$env:SystemRoot\System32\conhost.exe</Command><Arguments>--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\restart-night.ps1"</Arguments></Exec></Actions>
</Task>
"@
    try { Register-ScheduledTask -TaskName $NightTask -Xml $nx -Force -ErrorAction Stop | Out-Null; 'Night restart: pending updates now finish with a restart at night while nobody uses the PC (a switch in Settings)' }
    catch { "Night restart: couldn't set it up ($($_.Exception.Message)) - next run" }
}
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
