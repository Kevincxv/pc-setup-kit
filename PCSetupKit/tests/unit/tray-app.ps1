# tray-app.ps1: the login task that starts the app with its tray icon (MessiahApp.exe --tray; before 10/21 an AutoHotkey
# script), the app's icon and its Start menu entry - in a sandbox profile, with the scheduled-task and process commands mocked.
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
Copy-Item "$Src\ai-enabled.ps1", "$Src\app-icon.ps1", $ta $C
New-Item "$C\app" -ItemType Directory -Force | Out-Null; 'x' | Set-Content "$C\app\MessiahApp.exe"; 'x' | Set-Content "$C\claude-admin-launch.ps1"
'x' | Set-Content "$TD\Messiah Tray.ahk"
function Run-App([switch]$NoRestart) {
    $global:calls = @(); $global:reg = $null
    $u = $env:USERPROFILE; $ap = $env:APPDATA; $env:USERPROFILE = $H; $env:APPDATA = "$H\AppData\Roaming"
    try { @(& "$C\tray-app.ps1" -TrayDir $TD -ClaudeDir $C -NoRestart:$NoRestart) } finally { $env:USERPROFILE = $u; $env:APPDATA = $ap }
}
$startMenu = "$H\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"
$app = "$C\app\MessiahApp.exe"

Section 'with Claude: first run'
'claude=on' | Set-Content "$C\kit-options.txt"
$global:task = $null; $global:procs = @()
$o = Run-App
$r = $global:reg
Check 'login task starts the app with its tray icon (MessiahApp.exe --live --tray)' ($r -and $r.Actions[0].Execute -like "*\home\.claude\app\MessiahApp.exe" -and $r.Actions[0].Arguments -eq '--live --tray') "$($r.Actions[0].Execute) $($r.Actions[0].Arguments)"
Check '... elevated, no time limit, restarts if it stops; says so' ($r.Principal.RunLevel -eq 'Highest' -and $r.Settings.ExecutionTimeLimit -eq 'PT0S' -and $r.Settings.RestartCount -eq 3 -and "$o" -match 'Tray: starts with Windows') "$o"
$lnk = "$startMenu\Messiah.lnk"
$sc = if (Test-Path $lnk) { (New-Object -ComObject WScript.Shell).CreateShortcut($lnk) }
Check 'Start menu "Messiah" opens the app window (MessiahApp.exe --live)' ($sc -and $sc.TargetPath -like "*\home\.claude\app\MessiahApp.exe" -and $sc.Arguments -eq '--live') "$($sc.TargetPath) $($sc.Arguments)"
Check '... with the app''s own icon (drawn: a real .ico with 8 sizes, 16 to 256 px)' ($sc.IconLocation -match '\\Documents\\Messiah Tray\\app\.ico,0$' -and (Test-Path "$TD\app.ico") -and (Get-Item "$TD\app.ico").Length -gt 2000 -and [IO.File]::ReadAllBytes("$TD\app.ico")[4] -eq 8) "$($sc.IconLocation)"
Check '... no separate Status entry; no desktop entry unless asked (-Desktop)' (-not (Test-Path "$startMenu\Messiah Status.lnk") -and -not (Test-Path "$H\Desktop\Messiah.lnk")) ''
$sess = "$C\Messiah Session.lnk"
Check 'the session shortcut: the launcher, "Run as administrator", the app''s icon' ((Test-Path $sess) -and ((New-Object -ComObject WScript.Shell).CreateShortcut($sess).Arguments -match 'claude-admin-launch\.ps1') -and (([IO.File]::ReadAllBytes($sess)[0x15] -band 0x20) -ne 0)) ''
Check 'the tray is started' (($global:calls -join ',') -match 'stop Messiah Tray.*start Messiah Tray') ($global:calls -join ', ')

Section 'running again'
if ($global:reg) { $global:task = $global:reg }
$o = Run-App
Check 'nothing to do: silent, no task change, no restart' (-not $o -and -not $global:calls) "$o | $($global:calls -join ', ')"

Section 'an install from before 10/21 (the tray an AutoHotkey script, as Messiah.exe)'
'x' | Set-Content "$TD\Messiah.exe"
$global:task = [pscustomobject]@{ Actions = @([pscustomobject]@{ Execute = "$TD\Messiah.exe"; Arguments = "`"$TD\Messiah Tray.ahk`"" }) }
$global:procs = @([pscustomobject]@{ Name = 'Messiah.exe'; ProcessId = 4242; ExecutablePath = "$TD\Messiah.exe"; CommandLine = "`"$TD\Messiah.exe`" `"$TD\Messiah Tray.ahk`"" })
$o = Run-App
Check 'the task now starts the app, and it says so' ($global:reg.Actions[0].Execute -like "*\home\.claude\app\MessiahApp.exe" -and $global:reg.Actions[0].Arguments -eq '--live --tray' -and "$o" -match 'now part of the app') "$o"
Check '... the AutoHotkey tray is stopped (one icon), the app''s tray started' ($global:calls -contains 'kill 4242' -and ($global:calls -join ',') -match 'start Messiah Tray') ($global:calls -join ', ')
$global:procs = @()
Check '... AutoHotkey''s copy (Messiah.exe) is removed' (-not (Test-Path "$TD\Messiah.exe") -and "$o" -match 'removed Messiah\.exe') "$o"
$global:task = [pscustomobject]@{ Actions = @([pscustomobject]@{ Execute = "$TD\Messiah.exe"; Arguments = "`"$TD\Messiah Tray.ahk`"" }) }
$o = Run-App -NoRestart
Check '-NoRestart (setup): the tray is not started' ($global:calls -notcontains 'start Messiah Tray') ($global:calls -join ', ')
Section 'an install from before the app (Start menu and desktop "Messiah" started a session; a "Messiah Status" entry)'
$ws = New-Object -ComObject WScript.Shell
[IO.File]::Delete("$C\Messiah Session.lnk")
foreach ($l in "$startMenu\Messiah.lnk", "$H\Desktop\Messiah.lnk") {
    New-Item (Split-Path $l) -ItemType Directory -Force | Out-Null; [IO.File]::Delete($l)
    $s = $ws.CreateShortcut($l); $s.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"; $s.Arguments = "-NoExit -File `"$C\claude-admin-launch.ps1`""; $s.Save()
    $b = [IO.File]::ReadAllBytes($l); $b[0x15] = $b[0x15] -bor 0x20; [IO.File]::WriteAllBytes($l, $b)
}
'x' | Set-Content "$startMenu\Messiah Status.lnk"
if ($global:reg) { $global:task = $global:reg }
$o = Run-App -NoRestart
Check 'the session shortcut is kept in .claude, still "Run as administrator"' ((Test-Path "$C\Messiah Session.lnk") -and $ws.CreateShortcut("$C\Messiah Session.lnk").Arguments -match 'claude-admin-launch' -and (([IO.File]::ReadAllBytes("$C\Messiah Session.lnk")[0x15] -band 0x20) -ne 0)) "$o"
$sm = $ws.CreateShortcut("$startMenu\Messiah.lnk"); $dk = $ws.CreateShortcut("$H\Desktop\Messiah.lnk")
Check 'Start menu and desktop "Messiah" now open the app, no longer elevated (no UAC prompt)' ($sm.TargetPath -like "*\home\.claude\app\MessiahApp.exe" -and $dk.TargetPath -like "*\home\.claude\app\MessiahApp.exe" -and (([IO.File]::ReadAllBytes("$startMenu\Messiah.lnk")[0x15] -band 0x20) -eq 0)) "$o"
Check '... the old "Messiah Status" entry is gone, and it says what changed' (-not (Test-Path "$startMenu\Messiah Status.lnk") -and "$o" -match "Start menu entry 'Messiah' opens the app" -and "$o" -match "removed the old Start menu entry 'Messiah Status'") "$o"
if ($global:reg) { $global:task = $global:reg }
$o = Run-App -NoRestart
Check '... running again: silent' (-not $o) "$o"
[IO.File]::Delete("$H\Desktop\Messiah.lnk"); $o = Run-App -NoRestart
Check '... a desktop entry the owner deleted is not brought back' (-not (Test-Path "$H\Desktop\Messiah.lnk")) "$o"

Section 'without Claude'
'claude=off' | Set-Content "$C\kit-options.txt"; $global:task = $null
$o = Run-App
Check 'the same app and tray (one app)' ($global:reg.Actions[0].Execute -like "*\home\.claude\app\MessiahApp.exe") "$o"
$sc = if (Test-Path "$startMenu\Messiah.lnk") { (New-Object -ComObject WScript.Shell).CreateShortcut("$startMenu\Messiah.lnk") }
Check '... Start menu "Messiah" opens the app, with the app''s icon' ($sc -and $sc.TargetPath -like "*\home\.claude\app\MessiahApp.exe" -and $sc.IconLocation -match '\\Documents\\Messiah Tray\\app\.ico,0$') "$($sc.IconLocation)"

Section 'an older install without the AI assistant: "PC Setup Kit" becomes "Messiah"'
New-Item "$H\Desktop" -ItemType Directory -Force | Out-Null
[IO.File]::Delete("$startMenu\Messiah.lnk"); [IO.File]::Delete("$H\Desktop\Messiah.lnk")
'x' | Set-Content "$startMenu\PC Setup Kit.lnk"; 'x' | Set-Content "$H\Desktop\PC Setup Kit.lnk"; 'x' | Set-Content "$TD\PC Setup Kit.exe"
$global:task = $null; $global:procs = @()
$o = Run-App -NoRestart
Check 'the Start menu and desktop "PC Setup Kit" become "Messiah" (a desktop one stays on the desktop)' (-not (Test-Path "$startMenu\PC Setup Kit.lnk") -and -not (Test-Path "$H\Desktop\PC Setup Kit.lnk") -and (Test-Path "$startMenu\Messiah.lnk") -and (Test-Path "$H\Desktop\Messiah.lnk")) "$o"
Check '... the old PC Setup Kit.exe goes (nothing runs it)' (-not (Test-Path "$TD\PC Setup Kit.exe") -and "$o" -match 'removed PC Setup Kit\.exe') "$o"

Section 'the app not installed (a broken install)'
Remove-Item "$C\app" -Recurse -Force; [IO.File]::Delete("$startMenu\Messiah.lnk"); $global:task = $null
$o = Run-App -NoRestart
Check 'no app: nothing made, no task, nothing said' (-not (Test-Path "$startMenu\Messiah.lnk") -and -not $global:reg -and -not $o) "$o"
Finish