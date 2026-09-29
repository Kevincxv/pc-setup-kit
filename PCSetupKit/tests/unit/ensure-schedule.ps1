# ensure-schedule.ps1: the background maintenance also runs daily (PCs that stay on for days), added to existing
# installs through the task's exact XML - with the scheduled-task commands mocked.
. "$PSScriptRoot\..\lib.ps1"
$mocked = 'Get-ScheduledTask', 'Export-ScheduledTask', 'Register-ScheduledTask'
if (-not (Test-Tripwire "$Src\ensure-schedule.ps1" $mocked)) { Finish }
Import-MockTargets $mocked   # load their Windows modules BEFORE defining the mocks (see lib.ps1)
$global:ES = @{ Others = @{} }
function Get-ScheduledTask { param($TaskName) if ($TaskName -like 'PC Setup Kit *') { if ($global:ES.Others[$TaskName]) { [pscustomobject]@{ TaskName = $TaskName } }; return }; if ($global:ES.Xml) { [pscustomobject]@{ TaskName = $TaskName } } }
function Export-ScheduledTask { param($TaskName) $global:ES.Xml }
function Register-ScheduledTask { param($TaskName, $Xml, [switch]$Force) if ($global:ES.Fail) { throw 'Access is denied' }; if ($TaskName -like 'PC Setup Kit *') { $global:ES.Others[$TaskName] = $Xml; return }; $global:ES.Xml = $Xml; $global:ES.Registered++ }
if (-not (Assert-Mocks $mocked)) { Finish }
$loginOnly = '<?xml version="1.0" encoding="UTF-16"?><Task xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><Triggers><LogonTrigger><Enabled>true</Enabled><UserId>PC\owner</UserId><Delay>PT2M</Delay></LogonTrigger></Triggers><Principals><Principal id="Author"><UserId>S-1-5-21-1</UserId><RunLevel>HighestAvailable</RunLevel></Principal></Principals><Settings><Priority>7</Priority><ExecutionTimeLimit>PT4H</ExecutionTimeLimit></Settings><Actions><Exec><Command>conhost.exe</Command></Exec></Actions></Task>'
function ES { @(& "$Src\ensure-schedule.ps1" -Force) }

Section 'a PC set up before the daily run existed'
$ES.Xml = $loginOnly; $ES.Registered = 0; $o = @(ES)
$x = [xml]$ES.Xml
Check 'daily trigger added, the login trigger kept' ($x.Task.Triggers.CalendarTrigger.ScheduleByDay.DaysInterval -eq '1' -and $x.Task.Triggers.CalendarTrigger.StartBoundary -match 'T12:00:00' -and $x.Task.Triggers.LogonTrigger.Delay -eq 'PT2M') $ES.Xml
Check '... catches up after a missed start' ($x.Task.Settings.StartWhenAvailable -eq 'true') ''
Check '... everything else exactly as it was (user, rights, priority, time limit, program)' ($x.Task.Principals.Principal.UserId -eq 'S-1-5-21-1' -and $x.Task.Principals.Principal.RunLevel -eq 'HighestAvailable' -and $x.Task.Settings.Priority -eq '7' -and $x.Task.Settings.ExecutionTimeLimit -eq 'PT4H' -and $x.Task.Actions.Exec.Command -eq 'conhost.exe') ''
Check '... and said once' (@($o -match 'now also daily at 12:00').Count -eq 1) ($o -join ' / ')
$o = @(ES)
Check 'already done: nothing changes, nothing said' ($o.Count -eq 0 -and $ES.Registered -eq 1) ($o -join ' / ')

Section 'the update guard and the 4-hourly update check (every PC gets them once)'
$g = [xml]$ES.Others['PC Setup Kit Update Guard']; $c = [xml]$ES.Others['PC Setup Kit Update Check']
Check 'update guard: after every Windows Update install and driver install, 2 min later, elevated, hidden' ($g -and $g.Task.Triggers.EventTrigger.Subscription -match "WindowsUpdateClient'\] and EventID=19" -and $g.Task.Triggers.EventTrigger.Subscription -match "UserPnp'\] and EventID=20001" -and $g.Task.Triggers.EventTrigger.Delay -eq 'PT2M' -and $g.Task.Principals.Principal.RunLevel -eq 'HighestAvailable' -and $g.Task.Actions.Exec.Arguments -match '^--headless .+after-update\.ps1"$') ''
Check 'update check: every 4 hours, catching up after sleep, only with a network' ($c -and $c.Task.Triggers.CalendarTrigger.Repetition.Interval -eq 'PT4H' -and $c.Task.Settings.StartWhenAvailable -eq 'true' -and $c.Task.Settings.RunOnlyIfNetworkAvailable -eq 'true' -and $c.Task.Actions.Exec.Arguments -match 'update-check\.ps1"$') ''
$o = @(ES)
Check '... once: not registered again, nothing said' (-not ($o -match 'Update guard|Update check')) ($o -join ' / ')
Section 'special cases'
$ES.Xml = $loginOnly.Replace('<Settings>', '<Settings><StartWhenAvailable>false</StartWhenAvailable>'); [void](ES)
Check 'an explicit "don''t catch up" is switched on, not duplicated' (([regex]::Matches($ES.Xml, 'StartWhenAvailable>')).Count -eq 2 -and ([xml]$ES.Xml).Task.Settings.StartWhenAvailable -eq 'true') $ES.Xml
$ES.Xml = $loginOnly; $ES.Fail = $true; $o = @(ES)
Check 'the change is refused: says so, retries next run (task unchanged)' ($o -match 'next run' -and $ES.Xml -notmatch 'CalendarTrigger') ($o -join ' / ')
$ES.Fail = $false; $ES.Xml = $null; $ES.Others = @{ 'PC Setup Kit Update Guard' = 'x'; 'PC Setup Kit Update Check' = 'x' }; $o = @(ES)
Check 'no maintenance task on this PC: does nothing' ($o.Count -eq 0) ($o -join ' / ')
$o = @(& "$Src\ensure-schedule.ps1")
Check 'inside the test suite without -Force: does nothing' ($o.Count -eq 0) ''
Finish
