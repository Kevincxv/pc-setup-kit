# The tray script's own logic (alerts, tooltip, "maintenance running", rehearsal ignore list), run in an AutoHotkey
# harness: the real functions are copied out of the tray script; the on-screen parts (fullscreen check, the alert
# window) are replaced by stand-ins that record what would be shown.
. "$PSScriptRoot\..\lib.ps1"
$ahk = "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"
if (-not (Test-Path $ahk)) { Skip 'tray logic' 'AutoHotkey not installed'; Finish }
$C = "$Work\cl"; New-Item $C -ItemType Directory -Force | Out-Null
$traySrc = Get-Content $Tray -Raw -Encoding UTF8
function Get-AhkFunction([string]$Name) {
    $m = [regex]::Match($traySrc, "(?ms)^$Name\([^)\r\n]*\)\s*\{.*?^\}")
    if (-not $m.Success) { $m = [regex]::Match($traySrc, "(?m)^$Name\([^)\r\n]*\)\s*=>.*$") }
    $m.Value
}
$funcs = foreach ($n in 'MaintRunning', 'TodoTip', 'Notify', 'RehearsalPids', 'TrayError', 'AiEnabled', 'StatusAtLogin', 'LogNote') { $f = Get-AhkFunction $n; Check "tray function $n found" ([bool]$f) ''; $f }
@"
#Requires AutoHotkey v2.0
#NoTrayIcon
CL := "$C"
NAME := "Messiah"
LNK := "$Work\no-shortcut.lnk"
AI := EnvGet("TEST_AI") != "0"
FS := A_Args.Length > 1 && A_Args[2] = "fs"
Shown := []
IsFullscreen() => FS
ShowApp() => FileAppend("OPENED", "*")
ShowNote(text, *) {
    global Shown
    Shown.Push(StrReplace(text, "``n", " \n "))
}
$($funcs -join "`n")
switch A_Args[1] {
    case "tip": TodoTip(), FileAppend(A_IconTip, "*", "UTF-8")
    case "running": FileAppend(MaintRunning() ? "yes" : "no", "*")
    case "notify":
        Notify()
        for s in Shown
            FileAppend(s "``n", "*", "UTF-8")
    case "error":   ; a window that vanished mid-look: logged, no error box, the tray keeps running
        OnError TrayError
        SetTimer () => FileAppend("still running", "*"), -300
        SetTimer () => ExitApp(), -600
        SetTimer () => WinGetPID(0x7FFFFFF0), -50
        Persistent
    case "ai": FileAppend(AiEnabled() ? "on" : "off", "*")
    case "login": StatusAtLogin()
    case "log": LogNote("First line``nsecond line")
    case "log250":
        Loop 250
            LogNote("note " A_Index " " StrReplace(Format("{:300}", ""), " ", "x"))
    case "pids":
        for k in RehearsalPids()
            FileAppend(k ",", "*")
}
"@ | Set-Content "$Work\harness.ahk" -Encoding UTF8
function T([string]$What, [string]$Extra) { $o = & $ahk /ErrorStdOut "$Work\harness.ahk" $What $Extra 2>&1 | Out-String; $o.Trim() }
$v = Start-Process $ahk -ArgumentList '/ErrorStdOut', '/Validate', "`"$Work\harness.ahk`"" -Wait -PassThru -WindowStyle Hidden
Check 'harness with the real tray functions validates' ($v.ExitCode -eq 0) "exit $($v.ExitCode)"
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
function Todo([string[]]$lines) { [IO.File]::WriteAllLines("$C\maint-todo.txt", $lines, (New-Object Text.UTF8Encoding $false)) }

Section 'tooltip'
Check 'nothing to do: "Messiah"' ((T tip) -eq 'Messiah') (T tip)
Todo 'Do one thing'; Check 'one item: "1 maintenance item needs you"' ((T tip) -eq 'Messiah - 1 maintenance item needs you') (T tip)
Todo 'One', '', 'Two', '  '; Check 'two items (blank lines ignored): "2 maintenance items need you"' ((T tip) -eq 'Messiah - 2 maintenance items need you') (T tip)
'x' | Set-Content "$C\maint-claude-running"
Check 'hidden maintenance running: tooltip says so' ((T tip) -match 'Hidden maintenance running') (T tip)

Section 'the optional Claude part'
Clear-Path "$C\kit-options.txt"; Clear-Path "$C\admin-sessions.txt"
Check 'nothing recorded, no Messiah: off (a plain PC Setup Kit tray)' ((T ai) -eq 'off') (T ai)
'claude=on' | Set-Content "$C\kit-options.txt"; Check 'claude=on: on (Messiah tray)' ((T ai) -eq 'on') (T ai)
'claude=off' | Set-Content "$C\kit-options.txt"; Check 'claude=off: off' ((T ai) -eq 'off') (T ai)
Clear-Path "$C\kit-options.txt"; 'id' | Set-Content "$C\admin-sessions.txt"; Check 'installed before the option (Messiah was used): on' ((T ai) -eq 'on') (T ai)
Clear-Path "$C\admin-sessions.txt"
'x' | Set-Content "$C\maint-claude-running"; $env:TEST_AI = '0'
Check 'without Claude the tooltip never mentions hidden Claude runs' ((T tip) -notmatch 'Hidden maintenance') (T tip)
$env:TEST_AI = $null; 'x' | Set-Content "$C\maint-claude-running"   # the next section starts from a fresh marker

Section '"maintenance running" check'
Check 'fresh marker: running' ((T running) -eq 'yes') ''
(Get-Item "$C\maint-claude-running").LastWriteTime = $boot.AddMinutes(-3); Check 'marker from before the last restart: not running' ((T running) -eq 'no') ''
(Get-Item "$C\maint-claude-running").LastWriteTime = (Get-Date).AddMinutes(-70); if ((Get-Date).AddMinutes(-70) -gt $boot) { Check 'marker older than 60 min: not running' ((T running) -eq 'no') '' }
Clear-Path "$C\maint-claude-running"; Check 'no marker: not running' ((T running) -eq 'no') ''

Section 'alerts'
Clear-Path "$C\tray-notified.ini"; Todo 'Turn EXPO back on in the BIOS'
$o = T notify; Check 'a new to-do item: alert shown' ($o -eq 'Needs you (1): Turn EXPO back on in the BIOS') $o
Check '... and recorded, so it is shown once' ((T notify) -eq '') (T notify)
Todo 'A second thing', 'Turn EXPO back on in the BIOS'; (Get-Item "$C\maint-todo.txt").LastWriteTime = (Get-Date).AddSeconds(5)
$o = T notify fs; Check 'a game is fullscreen: nothing shown...' ($o -eq '') $o
$o = T notify; Check '... and it is shown once the game is closed' ($o -match '^Needs you \(2\): A second thing \\n \+ 1 more$') $o
Todo ('x' * 150); (Get-Item "$C\maint-todo.txt").LastWriteTime = (Get-Date).AddSeconds(10)
$o = T notify; Check 'a very long item is shortened to fit the alert' ($o -match '^Needs you \(1\): x{107}\.\.\.$') $o
Todo '', '  '; (Get-Item "$C\maint-todo.txt").LastWriteTime = (Get-Date).AddSeconds(15)
$o = T notify; Check 'a to-do file with only blank lines: no alert' ($o -eq '') $o
@{ boot = '2026-09-27T09:33:24'; items = @(@{ Kind = 'update'; Id = 'a'; Name = 'A' }, @{ Kind = 'file'; Id = 'b'; Name = 'B' }) } | ConvertTo-Json -Depth 4 | Set-Content "$C\restart-ledger.json"
$o = T notify; Check 'work waiting for the next shutdown: one alert with the count' ($o -match '^2 update\(s\)/fix\(es\) will finish the next time you turn the PC off') $o
Check '... shown once' ((T notify) -eq '') ''
@{ boot = '2026-09-28T08:00:00'; items = @(@{ Kind = 'update'; Id = 'c'; Name = 'C' }) } | ConvertTo-Json -Depth 4 | Set-Content "$C\restart-ledger.json"
$o = T notify; Check 'a new batch after a restart: alerted again' ($o -match '^1 update\(s\)') $o

Section 'rehearsal ignore list'
"boot=x`nignorepids=1234, 5678,abc" | Set-Content "$C\rehearsal.txt"
Check 'fresh rehearsal file: its pids are ignored (junk skipped)' ((T pids) -eq '1234,5678,') (T pids)
(Get-Item "$C\rehearsal.txt").LastWriteTime = (Get-Date).AddMinutes(-11)
Check 'rehearsal file older than 10 min: ignored completely' ((T pids) -eq '') (T pids)

Section 'errors never pop up (a session window closing while the tray looks at it)'
Clear-Path "$C\tray-errors.log"; $o = T error
Check 'no error message, the tray keeps running' ($o -eq 'still running') $o
$log = Get-Content "$C\tray-errors.log" -Raw -ErrorAction SilentlyContinue
Check '... and the error is logged for /self-improve' ($log -match 'WinGetPID') "$log"
Check 'the real tray turns the error handler on at start' ((Get-Content $Tray -Raw) -match '(?m)^OnError TrayError\s*$') ''
Section 'alerts are kept for the app (notifications.log)'
[IO.File]::Delete("$C\notifications.log"); [void](T log)
$l = @(Get-Content "$C\notifications.log" -Encoding UTF8)
Check 'one line per alert: "yyyy-MM-dd HH:mm|text", line breaks shown as " / "' ($l.Count -eq 1 -and $l[0] -match '^\d{4}-\d\d-\d\d \d\d:\d\d\|First line / second line$') ($l -join ' // ')
[void](T log250); $l = @(Get-Content "$C\notifications.log" -Encoding UTF8)
Check '... kept short: only the newest alerts once the file grows' ($l.Count -le 200 -and $l[-1] -match '\|note 250 ') "$($l.Count) lines, last: $($l[-1].Substring(0, 30))"
[IO.File]::Delete("$C\notifications.log")
Section 'login: the app starts in the hidden tray (no window) unless the owner turned "Open at login" on'
$saved = $env:PCKIT_IN_TESTS; $env:PCKIT_IN_TESTS = $null
try {
    [IO.File]::Delete("$C\tray-notified.ini"); 'claude=on' | Set-Content "$C\kit-options.txt"
    Check 'default: no window at login' ((T login) -eq '') (T login)
    "claude=on`nopenatlogin=off" | Set-Content "$C\kit-options.txt"
    Check 'turned off: no window' ((T login) -eq '') ''
    "claude=on`nopenatlogin=on" | Set-Content "$C\kit-options.txt"
    Check 'turned on: the window opens' ((T login) -eq 'OPENED') ''
    Check '... once per start-up (a tray restart doesn''t reopen it)' ((T login) -eq '') ''
} finally { $env:PCKIT_IN_TESTS = $saved; [IO.File]::Delete("$C\tray-notified.ini"); [IO.File]::Delete("$C\kit-options.txt") }

Finish
