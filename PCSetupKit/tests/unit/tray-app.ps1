# tray-app.ps1: the tray under its own program name (own tray entry the tray can pin), its login task and the Start
# menu Status entry - in a sandbox profile, with the scheduled-task and process commands mocked.
. "$PSScriptRoot\..\lib.ps1"
$ta = "$Src\tray-app.ps1"
if (-not (Test-Path $ta)) { Skip 'tray-app' 'not installed here'; Finish }
$mocked = 'Get-ScheduledTask', 'Register-ScheduledTask', 'Start-ScheduledTask', 'Stop-ScheduledTask', 'Get-CimInstance', 'Stop-Process'
if (-not (Test-Tripwire $ta $mocked -Guarded 'New-ScheduledTaskAction', 'New-ScheduledTaskTrigger', 'New-ScheduledTaskPrincipal', 'New-ScheduledTaskSettingsSet')) { Finish }
Import-MockTargets $mocked   # load their modules BEFORE defining the mocks (see lib.ps1)
function Get-ScheduledTask { [CmdletBinding()] param($TaskName) $global:task }
function Register-ScheduledTask { [CmdletBinding()] param($TaskName, $Action, $Trigger, $Principal, $Settings, [switch]$Force) $global:calls += "register $TaskName"; $global:reg = [pscustomobject]@{ Actions = @($Action); Principal = $Principal; Settings = $Settings; Trigger = $Trigger }; $global:reg }
function Start-ScheduledTask { [CmdletBinding()] param($TaskName) $global:calls += "start $TaskName" }
function Stop-ScheduledTask { [CmdletBinding()] param($TaskName) $global:calls += "stop $TaskName" }
function Get-CimInstance { [CmdletBinding()] param([Parameter(Position = 0)]$ClassName, $Filter) $global:procs | Where-Object { $Filter -match [regex]::Escape("'$($_.Name)'") } }
function Stop-Process { [CmdletBinding()] param($Id, [switch]$Force) $global:calls += "kill $Id" }
if (-not (Assert-Mocks $mocked)) { Finish }

$H = "$Work\home"; $C = "$H\.claude"; $TD = "$H\Documents\Messiah Tray"
New-Item $C, $TD, "$H\AppData\Roaming" -ItemType Directory -Force | Out-Null
Copy-Item "$Src\ai-enabled.ps1", $ta $C
'x' | Set-Content "$TD\Messiah Tray.ahk"
$ahk1 = "$Work\ahk-v1\AutoHotkey64.exe"; $ahk2 = "$Work\ahk-v2\AutoHotkey64.exe"   # two different programs stand in for two AutoHotkey versions
New-Item (Split-Path $ahk1), (Split-Path $ahk2) -ItemType Directory -Force | Out-Null
Copy-Item "$env:SystemRoot\System32\whoami.exe" $ahk1; Copy-Item "$env:SystemRoot\System32\hostname.exe" $ahk2
function Run-App([string]$Ahk, [switch]$NoRestart) {
    $global:calls = @(); $global:reg = $null
    $u = $env:USERPROFILE; $ap = $env:APPDATA; $env:USERPROFILE = $H; $env:APPDATA = "$H\AppData\Roaming"
    try { @(& "$C\tray-app.ps1" -TrayDir $TD -ClaudeDir $C -Ahk $Ahk -NoRestart:$NoRestart) } finally { $env:USERPROFILE = $u; $env:APPDATA = $ap }
}
$startMenu = "$H\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"

Section 'with Claude: first run'
'claude=on' | Set-Content "$C\kit-options.txt"
$global:task = $null; $global:procs = @()
$o = Run-App $ahk1
$exe = "$TD\Messiah.exe"
Check 'AutoHotkey copied under the app''s name (Messiah.exe)' ((Test-Path $exe) -and (Get-Item $exe).Length -eq (Get-Item $ahk1).Length) "$o"
Check '... and says so' ("$o" -match 'runs as Messiah\.exe') "$o"
$r = $global:reg
Check 'login task starts Messiah.exe with the tray script' ($r -and $r.Actions[0].Execute -eq $exe -and $r.Actions[0].Arguments -eq "`"$TD\Messiah Tray.ahk`"") "$($r.Actions[0].Execute) $($r.Actions[0].Arguments)"
Check '... elevated, no time limit, restarts if it stops' ($r.Principal.RunLevel -eq 'Highest' -and $r.Settings.ExecutionTimeLimit -eq 'PT0S' -and $r.Settings.RestartCount -eq 3) ''
$lnk = "$startMenu\Messiah Status.lnk"
$sc = if (Test-Path $lnk) { (New-Object -ComObject WScript.Shell).CreateShortcut($lnk) }
Check 'Start menu "Messiah Status" opens the Status window without a console' ($sc -and $sc.TargetPath -match 'conhost\.exe$' -and $sc.Arguments -match '^--headless powershell\.exe .*-File "' + [regex]::Escape("$C\dashboard.ps1") + '"$') "$($sc.TargetPath) $($sc.Arguments)"
Check 'the tray is restarted on the new program' (($global:calls -join ',') -match 'stop Messiah Tray.*start Messiah Tray') ($global:calls -join ', ')

Section 'running again'
$global:task = $global:reg
$o = Run-App $ahk1
Check 'nothing to do: silent, no task change, no restart' (-not $o -and -not $global:calls) "$o | $($global:calls -join ', ')"

Section 'after an AutoHotkey update'
$global:procs = @([pscustomobject]@{ Name = 'Messiah.exe'; ProcessId = 4242; ExecutablePath = $exe; CommandLine = "`"$exe`" `"$TD\Messiah Tray.ahk`"" })
$o = Run-App $ahk2
Check 'the running tray is stopped so its copy can be replaced' ($global:calls -contains 'kill 4242') ($global:calls -join ', ')
Check '... the copy matches the new AutoHotkey' ((Get-Item $exe).Length -eq (Get-Item $ahk2).Length) ''
Check '... the task is kept, the tray started again' (($global:calls -notmatch '^register') -and ($global:calls -contains 'start Messiah Tray')) ($global:calls -join ', ')
$global:procs = @()

Section 'an install from before (tray task on plain AutoHotkey)'
$global:task = [pscustomobject]@{ Actions = @([pscustomobject]@{ Execute = $ahk2; Arguments = "`"$TD\Messiah Tray.ahk`"" }) }
$o = Run-App $ahk2 -NoRestart
Check 'the task is moved to Messiah.exe and says so' ($global:reg.Actions[0].Execute -eq $exe -and "$o" -match 'login task now starts Messiah\.exe') "$o"
Check '-NoRestart (setup): the tray is not started' ($global:calls -notcontains 'start Messiah Tray') ($global:calls -join ', ')

Section 'without Claude'
'claude=off' | Set-Content "$C\kit-options.txt"; $global:task = $null
$o = Run-App $ahk2
$exe = "$TD\PC Setup Kit.exe"
Check 'runs as "PC Setup Kit.exe"' ((Test-Path $exe) -and $global:reg.Actions[0].Execute -eq $exe) "$o"
$sc = if (Test-Path "$startMenu\PC Setup Kit Status.lnk") { (New-Object -ComObject WScript.Shell).CreateShortcut("$startMenu\PC Setup Kit Status.lnk") }
Check '... Start menu "PC Setup Kit Status" with the kit''s gear icon' ($sc -and $sc.IconLocation -match 'imageres\.dll,110') "$($sc.IconLocation)"

Section 'nothing to run it with'
$global:task = $null
$o = Run-App "$Work\none\AutoHotkey64.exe"
Check 'AutoHotkey missing: silent, changes nothing' (-not $o -and -not $global:calls) "$o"
Finish
