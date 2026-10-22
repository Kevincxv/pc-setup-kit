# The tray's own logic (alerts, tooltip, "maintenance running", the rehearsal ignore list, pausing, the welcome page and
# "Open at login", the menu and the app's admin commands) - in the app since 10/21 (MessiahApp.exe --tray-test <what>
# prints what the tray would do; before: an AutoHotkey script). On-screen parts are left out: nothing pops up here.
. "$PSScriptRoot\..\lib.ps1"
if (-not $AppExe) { Skip 'tray logic' 'the app is not built here (tools\app\build.ps1)'; Finish }
$C = "$Work\cl"; New-Item $C -ItemType Directory -Force | Out-Null
function T([string]$What, [switch]$Fs, [hashtable]$Env = @{}) {
    $psi = New-Object Diagnostics.ProcessStartInfo $AppExe, ("--tray-test $What" + $(if ($Fs) { ' --fs' }))
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.EnvironmentVariables['PCKIT_CLAUDE_DIR'] = $C; $psi.EnvironmentVariables['PCKIT_IN_TESTS'] = '1'
    foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[$k] = $Env[$k] }
    $p = [Diagnostics.Process]::Start($psi); $o = $p.StandardOutput.ReadToEnd(); [void]$p.WaitForExit(30000); $o.Trim()
}
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
'x' | Set-Content "$C\maint-claude-running"
Check 'without Claude the tooltip never mentions hidden Claude runs' ((T tip -Env @{ TEST_AI = '0' }) -notmatch 'Hidden maintenance') ''
'x' | Set-Content "$C\maint-claude-running"   # the next section starts from a fresh marker

Section '"maintenance running" check'
Check 'fresh marker: running' ((T running) -eq 'yes') ''
(Get-Item "$C\maint-claude-running").LastWriteTime = $boot.AddMinutes(-3); Check 'marker from before the last restart: not running' ((T running) -eq 'no') ''
(Get-Item "$C\maint-claude-running").LastWriteTime = (Get-Date).AddMinutes(-70); if ((Get-Date).AddMinutes(-70) -gt $boot) { Check 'marker older than 60 min: not running' ((T running) -eq 'no') '' }
Clear-Path "$C\maint-claude-running"; Check 'no marker: not running' ((T running) -eq 'no') ''

Section 'alerts: quiet by default (the owner''s rule 10/10 - Messiah never pops up by itself)'
Clear-Path "$C\tray-notified.ini"; Clear-Path "$C\kit-options.txt"; [IO.File]::Delete("$C\notifications.log"); Todo 'Turn EXPO back on in the BIOS'
$o = T notify; Check 'a new to-do item: nothing pops up' ($o -eq '') $o
Check '... it is kept for the app (Alerts) all the same' ((Get-Content "$C\notifications.log" -Raw -ErrorAction SilentlyContinue) -match '\|Needs you \(1\): Turn EXPO back on') ''
Check '... and not again (recorded as told)' ((T notify) -eq '' -and @(Get-Content "$C\notifications.log").Count -eq 1) ''
[IO.File]::Delete("$C\notifications.log")
Section 'alerts in the corner (Settings: "Show alerts in the corner" on)'
Clear-Path "$C\tray-notified.ini"; 'cornernotes=on' | Set-Content "$C\kit-options.txt"; Todo 'Turn EXPO back on in the BIOS'
$o = T notify; Check 'a new to-do item: alert shown' ($o -eq 'Needs you (1): Turn EXPO back on in the BIOS') $o
Check '... and recorded, so it is shown once' ((T notify) -eq '') (T notify)
Todo 'A second thing', 'Turn EXPO back on in the BIOS'; (Get-Item "$C\maint-todo.txt").LastWriteTime = (Get-Date).AddSeconds(5)
$o = T notify -Fs; Check 'a game is fullscreen: nothing shown...' ($o -eq '') $o
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
# what an older tray recorded (AutoHotkey's tray-notified.ini, UTF-16) still counts: nothing is told twice after the switch
Clear-Path "$C\restart-ledger.json"; $st = (Get-Item "$C\maint-todo.txt").LastWriteTime.ToString('yyyyMMddHHmmss')
Todo 'Already told'; $st = (Get-Item "$C\maint-todo.txt").LastWriteTime.ToString('yyyyMMddHHmmss')
"[shown]`r`ntodo=$st`r`n" | Set-Content "$C\tray-notified.ini" -Encoding Unicode
Check 'what the AutoHotkey tray already told is not told again' ((T notify) -eq '') (T notify)

Section 'rehearsal ignore list'
"boot=x`nignorepids=1234, 5678,abc" | Set-Content "$C\rehearsal.txt"
Check 'fresh rehearsal file: its pids are ignored (junk skipped)' ((T pids) -eq '1234,5678,') (T pids)
(Get-Item "$C\rehearsal.txt").LastWriteTime = (Get-Date).AddMinutes(-11)
Check 'rehearsal file older than 10 min: ignored completely' ((T pids) -eq '') (T pids)

Section 'errors never pop up'
Clear-Path "$C\tray-errors.log"; $o = T error
Check 'no error message, the tray keeps running' ($o -eq 'still running') $o
Check '... and the error is logged for /self-improve' ((Get-Content "$C\tray-errors.log" -Raw -ErrorAction SilentlyContinue) -match 'vanished') ''
Section 'alerts are kept for the app (notifications.log)'
[IO.File]::Delete("$C\notifications.log"); [void](T log)
$l = @(Get-Content "$C\notifications.log" -Encoding UTF8)
Check 'one line per alert: "yyyy-MM-dd HH:mm|text", line breaks shown as " / "' ($l.Count -eq 1 -and $l[0] -match '^\d{4}-\d\d-\d\d \d\d:\d\d\|First line / second line$') ($l -join ' // ')
[void](T log250); $l = @(Get-Content "$C\notifications.log" -Encoding UTF8)
Check '... kept short: only the newest alerts once the file grows' ($l.Count -le 200 -and $l[-1] -match '\|note 250 ') "$($l.Count) lines"
[IO.File]::Delete("$C\notifications.log")
Section 'login: the app starts in the hidden tray (no window) unless the owner turned "Open at login" on'
$lt = @{ PCKIT_LOGIN_TEST = '1' }
[IO.File]::Delete("$C\tray-notified.ini"); 'claude=on' | Set-Content "$C\kit-options.txt"
Check 'default: no window at login' ((T login -Env $lt) -eq '') ''
"claude=on`nopenatlogin=off" | Set-Content "$C\kit-options.txt"; Check 'turned off: no window' ((T login -Env $lt) -eq '') ''
"claude=on`nopenatlogin=on" | Set-Content "$C\kit-options.txt"; Check 'turned on: the window opens' ((T login -Env $lt) -eq 'OPENED') ''
Check '... once per start-up (a tray restart doesn''t reopen it)' ((T login -Env $lt) -eq '') ''
[IO.File]::Delete("$C\tray-notified.ini"); "claude=on`nwelcome=pending" | Set-Content "$C\kit-options.txt"
Check 'right after a new install (welcome=pending): the welcome page' ((T login -Env $lt) -eq 'OPENED Welcome') ''
Check '... once' ((T login -Env $lt) -eq '') ''
[IO.File]::Delete("$C\tray-notified.ini"); [IO.File]::Delete("$C\kit-options.txt")

Section "what's new / the weekly summary (tray-news.txt), pausing, the menu and the app's commands"
'cornernotes=on' | Set-Content "$C\kit-options.txt"; Clear-Path "$C\maint-todo.txt"; Clear-Path "$C\restart-ledger.json"; [void](T notify)
'Updated to v2026.10.01 - new: faster monitor fix. Details: the app > Maintenance.' | Set-Content "$C\tray-news.txt" -Encoding UTF8
$o = T notify; Check 'a message from the maintenance (what''s new, the weekly summary): shown as a note' ($o -match '^Updated to v2026\.10\.01 - new: faster monitor fix') $o
Check '... once' ((T notify) -eq '') ''
'claude=on', 'cornernotes=on' | Set-Content "$C\kit-options.txt"
$o = T pause:2; $opts = @(Get-Content "$C\kit-options.txt")
$pu = [datetime]::MinValue; $okDate = ($opts -match '^pause-until=') -and [datetime]::TryParse(((@($opts -match '^pause-until=')[0]) -split '=', 2)[1], [ref]$pu)
Check 'Pause maintenance > For 2 hours: recorded (about 2 hours from now), other options kept, said' ($okDate -and [Math]::Abs(($pu - (Get-Date).AddHours(2)).TotalMinutes) -lt 3 -and ($opts -contains 'claude=on') -and $o -match '^Maintenance paused until') ($opts -join ' | ')
$o = T pause:0
Check '... Resume now: the pause is gone, said' (-not (@(Get-Content "$C\kit-options.txt") -match '^pause-until') -and (@(Get-Content "$C\kit-options.txt") -contains 'claude=on') -and $o -match 'runs again') ((Get-Content "$C\kit-options.txt") -join ' | ')
$m = T menu
Check 'the menu: Open Messiah, the sessions, Run maintenance now, Pause (2 hours / until tomorrow / resume), Cancel restart' ($m -match '(?s)^Open Messiah\s+-\s+New session\s+Show sessions\s+Hide sessions\s+-\s+Run maintenance now\s+Pause maintenance\s+For 2 hours\s+Until tomorrow\s+Resume now\s+Cancel restart') $m
Check '... without the AI assistant: no session entries' ((T menu -Env @{ TEST_AI = '0' }) -notmatch 'session') ''
$bl = T boost
Check 'while a game runs, browsers and the AI sessions step back - never voice chat, music or audio' ($bl -match 'chrome' -and $bl -match 'claude' -and $bl -notmatch 'Discord|Spotify|Sonar|audiodg') $bl
Check 'a hotkey opens the app (Ctrl+Alt+M)' ((T hotkey) -eq 'Ctrl+Alt+M') ''
$cm = T commands
Check "the app's admin commands: the AI assistant on (10) / off (11), the driver rollback (12), apply the tweak choices now (7), repair (8), undo the last update (9), the chat (13)" ($cm -match '10 AiOn: plain ai-toggle\.ps1 -On' -and $cm -match '11 AiOff: hidden ai-toggle\.ps1 -Off' -and $cm -match '12 GpuRollback: window gpu-rollback\.ps1' -and $cm -match '7 ApplyTweaks: hidden after-update\.ps1 -Now' -and $cm -match '8 Repair: window kit-update\.ps1 -Reinstall' -and $cm -match '9 Rollback: window kit-update\.ps1 -Rollback' -and $cm -match '13 ChatHost: hidden chat-host\.ps1') $cm
Finish
