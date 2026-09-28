# ensure-schedule.ps1: the background maintenance also runs daily (PCs that stay on for days), added to existing
# installs through the task's exact XML - with the scheduled-task commands mocked.
. "$PSScriptRoot\..\lib.ps1"
$mocked = 'Get-ScheduledTask', 'Export-ScheduledTask', 'Register-ScheduledTask'
if (-not (Test-Tripwire "$Src\ensure-schedule.ps1" $mocked)) { Finish }
Import-MockTargets $mocked   # load their Windows modules BEFORE defining the mocks (see lib.ps1)
$global:ES = @{}
function Get-ScheduledTask { param($TaskName) if ($global:ES.Xml) { [pscustomobject]@{ TaskName = $TaskName } } }
function Export-ScheduledTask { param($TaskName) $global:ES.Xml }
function Register-ScheduledTask { param($TaskName, $Xml, [switch]$Force) if ($global:ES.Fail) { throw 'Access is denied' }; $global:ES.Xml = $Xml; $global:ES.Registered++ }
if (-not (Assert-Mocks $mocked)) { Finish }
$loginOnly = '<?xml version="1.0" encoding="UTF-16"?><Task xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><Triggers><LogonTrigger><Enabled>true</Enabled><UserId>PC\owner</UserId><Delay>PT2M</Delay></LogonTrigger></Triggers><Principals><Principal id="Author"><UserId>S-1-5-21-1</UserId><RunLevel>HighestAvailable</RunLevel></Principal></Principals><Settings><Priority>7</Priority><ExecutionTimeLimit>PT4H</ExecutionTimeLimit></Settings><Actions><Exec><Command>conhost.exe</Command></Exec></Actions></Task>'
function ES { @(& "$Src\ensure-schedule.ps1" -Force) }

Section 'a PC set up before the daily run existed'
$ES.Xml = $loginOnly; $ES.Registered = 0; $o = @(ES)
$x = [xml]$ES.Xml
Check 'daily trigger added, the login trigger kept' ($x.Task.Triggers.CalendarTrigger.ScheduleByDay.DaysInterval -eq '1' -and $x.Task.Triggers.CalendarTrigger.StartBoundary -match 'T12:00:00' -and $x.Task.Triggers.LogonTrigger.Delay -eq 'PT2M') $ES.Xml
Check '... catches up after a missed start' ($x.Task.Settings.StartWhenAvailable -eq 'true') ''
Check '... everything else exactly as it was (user, rights, priority, time limit, program)' ($x.Task.Principals.Principal.UserId -eq 'S-1-5-21-1' -and $x.Task.Principals.Principal.RunLevel -eq 'HighestAvailable' -and $x.Task.Settings.Priority -eq '7' -and $x.Task.Settings.ExecutionTimeLimit -eq 'PT4H' -and $x.Task.Actions.Exec.Command -eq 'conhost.exe') ''
Check '... and said once' ($o.Count -eq 1 -and $o[0] -match 'now also daily at 12:00') ($o -join ' / ')
$o = @(ES)
Check 'already done: nothing changes, nothing said' ($o.Count -eq 0 -and $ES.Registered -eq 1) ($o -join ' / ')

Section 'special cases'
$ES.Xml = $loginOnly.Replace('<Settings>', '<Settings><StartWhenAvailable>false</StartWhenAvailable>'); [void](ES)
Check 'an explicit "don''t catch up" is switched on, not duplicated' (([regex]::Matches($ES.Xml, 'StartWhenAvailable>')).Count -eq 2 -and ([xml]$ES.Xml).Task.Settings.StartWhenAvailable -eq 'true') $ES.Xml
$ES.Xml = $loginOnly; $ES.Fail = $true; $o = @(ES)
Check 'the change is refused: says so, retries next run (task unchanged)' ($o -match 'next run' -and $ES.Xml -notmatch 'CalendarTrigger') ($o -join ' / ')
$ES.Fail = $false; $ES.Xml = $null; $o = @(ES)
Check 'no maintenance task on this PC: does nothing' ($o.Count -eq 0) ($o -join ' / ')
$o = @(& "$Src\ensure-schedule.ps1")
Check 'inside the test suite without -Force: does nothing' ($o.Count -eq 0) ''
Finish
