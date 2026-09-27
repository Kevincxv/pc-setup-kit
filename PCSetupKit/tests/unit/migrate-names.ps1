# migrate-names.ps1 (rename "Claude (Admin)" -> "Messiah" on PCs installed before the rename), in a sandbox home with
# every scheduled-task and process command mocked.
. "$PSScriptRoot\..\lib.ps1"
$mocked = 'Get-ScheduledTask', 'Register-ScheduledTask', 'Unregister-ScheduledTask', 'Start-ScheduledTask', 'Export-ScheduledTask', 'Get-CimInstance', 'Stop-Process'
if (-not (Test-Tripwire "$Src\migrate-names.ps1" $mocked)) { Finish }
Import-MockTargets $mocked   # load their Windows modules BEFORE defining the mocks (see lib.ps1)
function Get-ScheduledTask { param($TaskName) $global:MT.Tasks[$TaskName] }
function Export-ScheduledTask { param($TaskName) $x = $global:MT.Tasks[$TaskName]
    "<Task><RegistrationInfo><URI>\$TaskName</URI></RegistrationInfo><Principals><Principal><UserId>S-1-5-21-1</UserId><RunLevel>$($x.Principal)</RunLevel></Principal></Principals><Settings>$($x.Settings)</Settings><Actions><Exec><Command>$($x.Actions[0].Execute)</Command><Arguments>$($x.Actions[0].Arguments)</Arguments></Exec></Actions></Task>" }
function Register-ScheduledTask { param($TaskName, $Xml, [switch]$Force)
    if ($global:MT.FailRegister) { throw 'Access is denied' }
    $x = [xml]$Xml; $global:MT.Xml = $Xml
    $global:MT.Tasks[$TaskName] = [pscustomobject]@{ Actions = @([pscustomobject]@{ Execute = $x.Task.Actions.Exec.Command; Arguments = $x.Task.Actions.Exec.Arguments }); Principal = $x.Task.Principals.Principal.RunLevel; Settings = $x.Task.Settings }
    $global:MT.Log.Add("register $TaskName") }
function Unregister-ScheduledTask { param($TaskName, $Confirm) $global:MT.Tasks.Remove($TaskName); $global:MT.Log.Add("unregister $TaskName") }
function Start-ScheduledTask { param($TaskName) $global:MT.Log.Add("start $TaskName") }
function Get-CimInstance { $global:MT.Procs | ForEach-Object { [pscustomobject]@{ ProcessId = $_.Id; CommandLine = $_.Cmd } } }
function Stop-Process { param($Id, [switch]$Force) $global:MT.Procs = @($global:MT.Procs | Where-Object Id -ne $Id); $global:MT.Log.Add("stop $Id") }
if (-not (Assert-Mocks $mocked)) { Finish }

$H = "$Work\home"; $A = "$H\AppData\Roaming"; $P = "$A\Microsoft\Windows\Start Menu\Programs"; $old = "$H\Documents\Claude Admin Tray"; $new = "$H\Documents\Messiah Tray"
$ahkExe = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
function OldInstall {
    Clear-Path $H; New-Item $P, "$H\Desktop", $old -ItemType Directory -Force | Out-Null
    'lnk' | Set-Content "$P\Claude (Admin).lnk"; 'lnk' | Set-Content "$H\Desktop\Claude (Admin).lnk"; 'tray v2' | Set-Content "$old\Claude Admin Tray.ahk"
    $global:MT = @{ Log = New-Object System.Collections.Generic.List[string]; FailRegister = $false
        Tasks = @{ 'Claude Admin Tray' = [pscustomobject]@{ Actions = @([pscustomobject]@{ Execute = $ahkExe; Arguments = "`"$old\Claude Admin Tray.ahk`"" }); Triggers = @('AtLogOn'); Principal = 'Highest'; Settings = 'NoLimit' } }
        Procs = @([pscustomobject]@{ Id = 4242; Cmd = "`"$ahkExe`" `"$old\Claude Admin Tray.ahk`"" }, [pscustomobject]@{ Id = 7; Cmd = "`"$ahkExe`" `"C:\Games\refocus.ahk`"" }) }
}
function Run { @(& "$Src\migrate-names.ps1" -UserHome $H -AppData $A -Force) }

Section 'an install from before the rename'
OldInstall; $o = @(Run)
Check 'shortcuts renamed (Start menu and desktop)' ((Test-Path -LiteralPath "$P\Messiah.lnk") -and (Test-Path -LiteralPath "$H\Desktop\Messiah.lnk") -and -not (Test-Path -LiteralPath "$P\Claude (Admin).lnk") -and -not (Test-Path -LiteralPath "$H\Desktop\Claude (Admin).lnk")) ''
$t = $MT.Tasks['Messiah Tray']
Check 'new tray task: runs the tray from the new folder, same trigger/rights/settings' ($t -and $t.Actions[0].Arguments -eq "`"$new\Messiah Tray.ahk`"" -and $t.Actions[0].Execute -eq $ahkExe -and $t.Principal -eq 'Highest' -and $t.Settings -eq 'NoLimit') "$($t.Actions[0].Arguments)"
Check '... copied exactly (the same user, now under the new name)' ($MT.Xml -match '<UserId>S-1-5-21-1</UserId>' -and $MT.Xml -match '<URI>\\Messiah Tray</URI>' -and $MT.Xml -notmatch 'Claude Admin') $MT.Xml
Check 'tray script moved to the new folder' ((Get-Content "$new\Messiah Tray.ahk" -Raw -ErrorAction SilentlyContinue) -match 'tray v2') ''
Check 'old tray stopped (other AutoHotkey scripts untouched), old task removed, new one started' (($MT.Log -join ',') -eq 'register Messiah Tray,stop 4242,unregister Claude Admin Tray,start Messiah Tray') ($MT.Log -join ',')
Check 'old folder removed' (-not (Test-Path $old)) ''
Check 'one line for the maintenance report' ($o.Count -eq 1 -and $o[0] -match '^Renamed Claude \(Admin\) to Messiah: shortcut.*tray task, tray folder$') ($o -join ' / ')

Section 'already moved: nothing to do'
$MT.Log.Clear(); $o = @(Run)
Check 'no output, no changes' ($o.Count -eq 0 -and $MT.Log.Count -eq 0) (($o + $MT.Log) -join ' / ')

Section 'special cases'
OldInstall; 'lnk new' | Set-Content "$P\Messiah.lnk"; [void](Run)
Check 'a Messiah shortcut already there: the old one is just removed' (-not (Test-Path -LiteralPath "$P\Claude (Admin).lnk") -and (Get-Content "$P\Messiah.lnk") -eq 'lnk new') ''
OldInstall; $MT.FailRegister = $true; $o = @(Run)
Check 'the new task cannot be created: old task, tray and folder stay (retried next login)' ($MT.Tasks['Claude Admin Tray'] -and (Test-Path "$old\Claude Admin Tray.ahk") -and -not ($MT.Log -match 'stop|unregister') -and ($o -match 'will retry next login')) ($o -join ' / ')
OldInstall; 'my notes' | Set-Content "$old\notes.txt"; [void](Run)
Check 'something else in the old folder: kept' ((Test-Path "$old\notes.txt") -and -not (Test-Path "$old\Claude Admin Tray.ahk")) ''
OldInstall; $o = @(& "$Src\migrate-names.ps1" -UserHome $H -AppData $A)
Check 'inside the test suite without -Force: does nothing' ($o.Count -eq 0 -and $MT.Log.Count -eq 0 -and (Test-Path -LiteralPath "$P\Claude (Admin).lnk")) ''
Finish
