# The app window (MessiahApp.exe, compiled from app\Messiah.App): its own test (--test) builds every page and the chat
# from a home folder's files and prints them - here a sandbox home: a new install, one with made-up data, and every
# state file filled with garbage (in a profile path with spaces and non-English letters). No window opens; nothing is
# read from this PC's own .claude. (tray-windows and chaos-state check it too.)
. "$PSScriptRoot\..\lib.ps1"
if (-not $AppExe) { Skip 'app' 'not built here (tools\app\build.ps1)'; Finish }
function Run-App([string]$Home_, [hashtable]$Env = @{}, [string[]]$ArgList = @()) { Invoke-App $Home_ $ArgList $Env }
function Errs($r) { ((@($r.Out -split "`r?`n" | Where-Object { $_ -match 'PAGE ERROR' }) + @($r.Err.Trim()) | Where-Object { $_ }) -join ' | ') }
$pages = 'Welcome', 'Home', 'Status', 'Activity/Checks', 'Activity/Stability', 'Activity/Trends', 'Activity/Performance', 'Activity/Alerts', 'Settings/General', 'Settings/Windows', 'Settings/Tools'

Section 'a new install (nothing written yet)'
$H = "$Work\new"; New-Item "$H\.claude", "$H\Documents" -ItemType Directory -Force | Out-Null
$r = Run-App $H
Check 'it runs and ends by itself' ($r.Code -eq 0) "exit $($r.Code) $($r.Err)"
Check 'Restart into an update keeps what the copy is (--live, --tray), not its page - the tray stays the tray (10/22: it lost --live)' ($r.Out -match '(?m)^RESTART ARGS: --live --tray --after 42 / --live --after 7\s*$') ''
$miss = @($pages | Where-Object { $r.Out -notmatch "(?m)^PAGE: $([regex]::Escape($_)) " })
Check 'every page is built' (-not $miss) "missing: $($miss -join ', ')"
Check 'no page fails' (-not (Errs $r)) (Errs $r)
Check 'tabs: Home, Status, Activity, Settings' ($r.Out -match '(?m)^NAV: Home \| Status \| Activity \| Settings\s*$') ''
Check 'Home: all good, no report yet' ($r.Out -match 'All good - nothing needs you' -and $r.Out -match 'No report yet') ''
Check 'every button, switch, link and field has a name a screen reader can say (the window''s own parts and every page)' ($r.Out -notmatch '(?m)^A11Y:') (($r.Out -split "?
" | Where-Object { $_ -match '^A11Y:' }) -join ' | ')
Check 'the chat: replies, links, attachments, edit, find and speed work' ($r.Out -match 'CHAT: reply=RichTextBox' -and $r.Out -match 'CHAT FIND: found=3' -and $r.Out -match 'CHAT EDIT: .*editing=True' -and $r.Out -match 'CHAT MODE: default=Standard chosen=Deep' -and $r.Out -match 'CHAT FIND: .*marked=3 leftover=0') ''
Check 'files dropped from Explorer onto the window with admin rights (the older drop way Windows lets through): attached, the chat opened for them' ($r.Out -match 'CHAT DROP: read=2 attached=2 chat=Visible') ''
Check 'Claude''s steps in a row fold into one line ("3 steps - ...") that opens to list them; a reply starts a new fold' ($r.Out -match 'CHAT STEPS: groups=2 head=\[3 steps - Running health-check\.ps1\] open=3') ''
Check 'chat tabs: a name of its own (also on the phone), back to the title when cleared; a pinned tab can''t be closed' ($r.Out -match 'CHAT TAB: named=\[My build chat\] remote=\[My build chat\] cleared=\[New chat\] pinned=True closeRefused=True unpinned=True') ''
$ram = [ordered]@{ 'not started' = 'Step 1 of 2'; 'A running' = 'Now'; 'A clean' = 'Next'; 'A crashed' = 'Only the stick in slot A Next'; 'B running' = 'Now'; 'A bad' = 'Only the stick in slot A Result'
    'both bad' = 'Only the stick in slot A Only the stick in slot B Result'; 'both clean' = 'Result'; 'back too soon' = 'Both sticks are back in, but the test isn''t finished'; 'A off by the owner' = 'Now' }
$bad = @($ram.Keys | Where-Object { $r.Out -notmatch "(?m)^RAMTEST $([regex]::Escape($_)): $([regex]::Escape($ram[$_]))\s*$" })
Check 'the RAM stick test: each stage says the right thing (a power-off by the owner is no crash)' (-not $bad) "wrong: $($bad -join ', ')"
Check 'a test writes nothing into the home folder' (-not (Get-ChildItem $H -Recurse -File)) ((Get-ChildItem $H -Recurse -File).Name -join ', ')

Section 'with data (the to-do list, a report, a guard pass, what''s new, a game running)'
$H = "$Work\data"; $C = "$H\.claude"; New-Item $C, "$H\Documents" -ItemType Directory -Force | Out-Null
'claude=off' | Set-Content "$C\kit-options.txt"
'Turn EXPO back on in the BIOS.' | Set-Content "$C\maint-todo.txt" -Encoding UTF8
'Checked 9/27/2026 12:00 PM in 18s', '[Drivers]', 'NVIDIA: 617.14 is up to date', '[PC health]', 'WARNING: blue screen 0x109 at 9/27/2026' | Set-Content "$C\maint-report.txt"
'{"at":"' + (Get-Date).ToString('o') + '","preview":false,"cause":"Windows Update (KB5099999)","optIn":[],"keys":{"telemetry":{"same":57,"fixed":[],"blocked":0},"start-menu":{"same":4,"fixed":["Start_TrackDocs"],"blocked":0}}}' | Set-Content "$C\tweak-status.json"
'{"version":"v2026.10.12","date":"' + (Get-Date).ToString('o') + '","points":["Status tab: every optimization at a glance"],"url":"https://github.com/x/y/releases/tag/v2026.10.12"}' | Set-Content "$C\whats-new.json"
$r = Run-App $H @{ PCKIT_GAME_TEST = 'Test Game'; PCKIT_REPORT_TEST = '1' }
Check 'no page fails' ($r.Code -eq 0 -and -not (Errs $r)) (Errs $r)
Check 'Home leads with what needs the owner' ($r.Out -match '1 thing needs you' -and $r.Out -match 'Turn EXPO back on in the BIOS\.') ''
Check 'Home while a game runs: maintenance waits' ($r.Out -match 'CARD: Playing Test Game') ''
Check 'Home after an update: what''s new' ($r.Out -match "CARD: What's new in Messiah v2026\.10\.12") ''
Check 'Status: what was put back, and why' ($r.Out -match 'Something had changed it: Recent files in Start - after Windows Update \(KB5099999\)') ''
Check 'the help report: status, what needs the owner, the last check - no PC or user name' ($r.Out -match 'REPORT: Messiah report - ' -and $r.Out -match 'NEEDS THE OWNER' -and $r.Out -match 'LAST CHECK:' -and $r.Out -notmatch [regex]::Escape($env:COMPUTERNAME) -and $r.Out -notmatch [regex]::Escape($H)) ''
'{"verifier":"2026-10-04"}' | Set-Content "$C\diag-state.json"
$r = Run-App $H @{ PCKIT_DIAG_TEST = (((1..18) | ForEach-Object { "d$_.sys" }) -join ' ') + '|' }
Check 'a crash-hunting mode left on (Driver Verifier): amber, since when, with its off button' ($r.Out -match 'Driver Verifier \(18 drivers\) on / On for \d+ days \(since Oct 4\)' -and $r.Out -match '\[Turn off Driver Verifier\]') ''
$r = Run-App $H @{} @('--page', 'Welcome')
Check 'after a new install: the Welcome tab first' ($r.Out -match '(?m)^NAV: Welcome \| Home \| Status \| Activity \| Settings\s*$') ''
'claude=on' | Set-Content "$C\kit-options.txt"
$r = Run-App $H
Check 'with Claude: the Claude card with Open chat' ($r.Code -eq 0 -and $r.Out -match 'CARD: Claude' -and $r.Out -match 'Open chat' -and -not (Errs $r)) (Errs $r)

Section 'Activity > Performance: each game''s last minute second by second, and what an update did to it'
$H = "$Work\perf"; $C = "$H\.claude"; New-Item $C, "$H\Documents" -ItemType Directory -Force | Out-Null
'claude=off' | Set-Content "$C\kit-options.txt"
$now = Get-Date; $rows = @(foreach ($i in 0..5) { [ordered]@{ date = $now.AddDays(-12 + $i * 2).ToString('o'); game = 'TestGame'; fps = 58 + $i; low1 = 47 + $i; frames = 3500; stutters = 2; driver = $(if ($i -lt 3) { '1.0' } else { '2.0' }); build = '26200.1'; ram = $(if ($i -lt 3) { '4800 MT/s' } else { '6000 MT/s' }) } })
$rows[-1].perSec = @(1..60 | ForEach-Object { if ($_ -eq 20) { 38 } else { 60 } }); $rows[-1].worstMs = @(1..60 | ForEach-Object { if ($_ -eq 20) { 72.5 } else { 18 } })
ConvertTo-Json -InputObject $rows -Depth 4 | Set-Content "$C\perf-history.json"
$r = Run-App $H
Check 'the page builds' ($r.Out -match '(?m)^PAGE: Activity/Performance' -and -not (Errs $r)) (Errs $r)
Check 'the game''s last minute, second by second' ($r.Out -match 'CHART: The last minute, second by second \| 60 seconds, typical 60 fps') ''
Check 'a driver update: the sessions before and after, side by side, with a plain verdict' ($r.Out -match 'TestGame - Graphics driver 1\.0 -> 2\.0: better - 59 -> 62 fps \(\+5%\), 1% low 48 -> 51 \(\+6%\)') ''
$H2 = "$Work\perf0"; New-Item "$H2\.claude", "$H2\Documents" -ItemType Directory -Force | Out-Null
Check 'EXPO turned on (RAM 4800 -> 6000): its own verdict' ($r.Out -match 'TestGame - RAM speed 4800 MT/s -> 6000 MT/s: better') ''
Check 'nothing measured yet: says how it gets measured' ((Run-App $H2).Out -match 'CARD: Nothing measured yet') ''
Section 'Activity > Performance: a setting tried both ways, a driver on test, heat and wear (10/21)'
$H = "$Work\tune"; $C = "$H\.claude"; New-Item $C, "$H\Documents" -ItemType Directory -Force | Out-Null
'claude=off' | Set-Content "$C\kit-options.txt"; $now = Get-Date
$rows = @(foreach ($i in 0..5) { [ordered]@{ date = $now.AddHours(-12 + $i).ToString('o'); game = 'cod'; fps = 200; low1 = 150; frames = 12000; stutters = 2; driver = '2.0'; gpuTemp = 70 + $i; gpuFan = 55; gpuPower = 290; cpuLimit = 100; cpuPerf = 112; tune = $(if ($i -lt 3) { 'vram:a' } else { 'vram:b' }) } })
$rows[-1].gpuBusy = 72; $rows[-1].latency = 11.4; $rows[-1].presentMode = 'Composed: Flip'
ConvertTo-Json -InputObject $rows -Depth 4 | Set-Content "$C\perf-history.json"
@{ active = @{ id = 'vram'; game = 'cod'; label = 'the video memory budget'; a = '0.850000'; b = '0.750000'; arm = 'b'; started = $now.AddDays(-1).ToString('o') }
   done = @(@{ id = 'reflex'; label = 'Reflex Boost'; a = 'Enabled + boost'; b = 'Enabled'; kept = 'Enabled'; why = 'faster'; at = $now.AddDays(-2).ToString('o'); aFps = 200; bFps = 204; aLow = 150; bLow = 165; aLatency = 12.5; bLatency = 10.9 },
            @{ id = 'workers'; label = 'the renderer thread count'; a = '9'; b = '8'; kept = '9'; why = 'the graphics driver reset during the test'; at = $now.AddDays(-3).ToString('o') }) } | ConvertTo-Json -Depth 4 | Set-Content "$C\game-tune.json"
@{ trial = @{ driver = '2.0'; from = '1.0'; since = $now.AddDays(-1).ToString('o'); verdict = $null; text = $null } } | ConvertTo-Json -Depth 3 | Set-Content "$C\gpu-state.json"
ConvertTo-Json -InputObject @(@{ date = $now.ToString('o'); ssdTemp = 49; ssdTempMax = 86; ssdWear = 3; gpuIdle = 28; gpuIdleFan = 70 }) | Set-Content "$C\health-history.json"
$r = Run-App $H
Check 'the page builds' (-not (Errs $r)) (Errs $r)
Check 'the setting being tried: both values in words, how far along, which one is on now' ($r.Out -match 'Trying now in Call of Duty: a 85% video memory budget \(as before\) against a 75% video memory budget - 6 of 8 minutes of play measured\. On now: a 75% video memory budget\.') ''
Check '... each test''s result: what was faster and by how much, what was kept' ($r.Out -match 'Reflex Boost off is faster than Reflex Boost on \(delay to the screen 12\.5 -> 10\.9 ms -13%, 1% low 150 -> 165 fps \+10%, average 200 -> 204 fps\) - switched to it' -and $r.Out -match 'the renderer thread count: stopped - the graphics driver reset during the test; 9 renderer threads kept') ''
Check 'a new driver on test: against which one, how far along, what happens if it is slower' ($r.Out -match 'CARD: Graphics driver test' -and $r.Out -match 'Driver 2\.0 \(since .+\) is on test against 1\.0: 3 of 3 minutes of play measured on it\. If your games run clearly slower on it, Messiah goes back to 1\.0 by itself\.') ''
Check 'heat and wear: the graphics card while gaming and at idle, the processor, the SSD''s hottest' ($r.Out -match 'Graphics card: up to 75 °C while gaming, fan 55%, 290 W; 28 °C at idle, fan 70%' -and $r.Out -match 'Processor: at full speed while gaming \(112% of its base speed\)' -and $r.Out -match 'SSD: 49 °C now, 86 °C at its hottest \(it slows itself down from about 80 °C - a heatsink helps\), 3% worn' -and $r.Out -match 'CHART: Graphics card while gaming \| 6 points') ''
'{"trial":{"driver":"2.0","from":"1.0","since":"' + $now.AddDays(-3).ToString('o') + '","verdict":"rolled back","text":"cod runs slower on it than on 1.0 (1% low 150 -> 128 fps) - went back to 1.0"}}' | Set-Content "$C\gpu-state.json"
$r = Run-App $H
Check 'what limits the frame rate, the delay to the screen, frames through the compositor (10/22)' ($r.Out -match 'The processor or the game is the limit \(the graphics card is busy only 72% of each frame\)' -and $r.Out -match '11\.4 ms from the game starting a frame to it on screen' -and $r.Out -match 'desktop compositor') ''
Check '... a driver that failed its test: said it was undone, and why' ($r.Out -match 'Driver 2\.0 was undone - cod runs slower on it than on 1\.0') ''
Check 'Settings: the switch for tuning by measuring' ($r.Out -match 'Tune my games by measuring') ''
Section 'the memory test and the processor''s temperature (10/22)'
$H = "$Work\mem"; $C = "$H\.claude"; New-Item $C, "$H\Documents" -ItemType Directory -Force | Out-Null
'claude=off' | Set-Content "$C\kit-options.txt"; $now = Get-Date
$two = '2 stick(s), 32 GB in P0 CHANNEL A + P0 CHANNEL B'; $oneA = '1 stick(s), 16 GB in P0 CHANNEL A'
@("2026-10-05 09:54 | start | $two", "$($now.AddDays(-2).ToString('yyyy-MM-dd HH:mm')) | stress | $two | 612 passes over 17 GB in 45 min at 4800 MT/s: 0 errors",
  "$($now.AddDays(-1).ToString('yyyy-MM-dd HH:mm')) | boottest | $oneA | Windows' extended memory test at start-up: errors found") | Set-Content "$C\ram-test.log"
'{"bootArmed":"' + $now.ToString('o') + '"}' | Set-Content "$C\ram-check.json"
ConvertTo-Json -InputObject @(@{ date = $now.AddHours(-1).ToString('o'); game = 'cod'; fps = 200; low1 = 150; cpuTemp = 78.5; cpuLimit = 100; cpuPerf = 110 }) | Set-Content "$C\perf-history.json"
ConvertTo-Json -InputObject @(@{ date = $now.ToString('o'); cpuIdle = 41.2; ssdTemp = 40 }) | Set-Content "$C\health-history.json"
$r = Run-App $H
Check 'the page builds' (-not (Errs $r)) (Errs $r)
Check 'Stability: the memory test card - each result, newest first, the one with errors flagged' ($r.Out -match 'CARD: Memory test' -and $r.Out -match 'Deep test at start-up - Windows'' extended memory test at start-up: errors found \(one stick, 16 GB in P0 CHANNEL A\)' -and $r.Out -match 'Nightly test - 612 passes over 17 GB in 45 min at 4800 MT/s: 0 errors' -and $r.Out -match 'Errors mean faulty memory') ''
Check '... the deep test set for the next start-up: said, with how to start it and a way to cancel' ($r.Out -match 'The deep test is set for the next start-up: restart the PC yourself' -and $r.Out -match 'BUTTONS: [^\r\n]*Cancel the deep test') ''
Check 'the stick test counts a memory test with errors like a crash for that stick' ($r.Out -match '(?m)^RAMTEST A memory test errors: Only the stick in slot A Next') ''
Check 'Heat and wear: the processor''s temperature while gaming and at idle' ($r.Out -match 'Processor: up to 78\.5 °C while gaming; 41\.2 °C at idle; at full speed while gaming \(110% of its base speed\)') ''
Check 'games by their names, not their programs'' ("cod" -> Call of Duty)' ($r.Out -match '(?m)^CARD: Call of Duty\s*$' -and $r.Out -notmatch '(?m)^CARD: cod\s*$') ''
'{"ram-stick-test":"' + $now.ToString('o') + '"}' | Set-Content "$C\maint-state.json"; 'Turn EXPO back on in the BIOS - OC Tweaker > DRAM Profile > EXPO1 > F10.' | Set-Content "$C\maint-todo.txt"
$r2 = Run-App $H
Check 'the RAM stick test running: a to-do that turns EXPO on says to wait for it (the test needs EXPO off)' ($r2.Out -match 'CARD: RAM stick test' -and $r2.Out -match 'Wait with this until the RAM stick test is done') ''
Check 'Settings: the switches for the processor''s temperature and the nightly memory test' ($r.Out -match 'Measure the processor''s temperature' -and $r.Out -match 'Test the memory at night') ''
Section 'Home: "Since you last looked" - what happened while the window was closed'
$H = "$Work\since"; $C = "$H\.claude"; New-Item "$C\maint-history", "$H\Documents" -ItemType Directory -Force | Out-Null
'claude=off' | Set-Content "$C\kit-options.txt"; $now = Get-Date
'Checked x in 20s', '[Periodic]', 'Updated app: Vendor.Tool', 'Tweaks: all still applied' | Set-Content "$C\maint-history\report-20261021-090000.txt"
'Checked y in 20s', 'Updated app: Ancient.Thing' | Set-Content "$C\maint-history\report-20261001-090000.txt"; (Get-Item "$C\maint-history\report-20261001-090000.txt").LastWriteTime = $now.AddDays(-20)
@{ events = @(@{ key = $now.AddHours(-3).ToString('s'); at = $now.AddHours(-3).ToString('s'); kind = 'bsod'; code = '0x109' }); changes = @(@{ at = $now.AddHours(-2).ToString('s'); what = 'Graphics driver'; from = '617.42'; to = '618.10' }) } | ConvertTo-Json -Depth 4 | Set-Content "$C\power-log.json"
$r = Run-App $H @{ PCKIT_SINCE_TEST = $now.AddDays(-1).ToString('s') }
$card = [regex]::Match($r.Out, '(?s)CARD: Since you last looked.*?(?=TILE:|CARD:(?! Since))').Value
Check 'the checks since then and what they changed (not older ones)' ($card -match '1 check ran: Updated app: Vendor\.Tool' -and $card -notmatch 'Ancient\.Thing') $card
Check '... a blue screen, a driver change' ($r.Out -match 'A blue screen [^\r\n]*\(0x109\)' -and $r.Out -match 'Graphics driver: 617\.42 -> 618\.10') ''
Check 'never closed before (no time recorded): no card' ((Run-App $H).Out -notmatch 'Since you last looked') ''
Section 'break it: every state file garbage, in a profile path with spaces and non-English letters'
$H = "$Work\Jörg Müller ÄÖÜ ñ"; $C = "$H\.claude"; New-Item $C, "$H\Documents", "$C\maint-history", "$C\chats\20260101-000000" -ItemType Directory -Force | Out-Null
$states = 'actions-state.json', 'guard-state.json', 'benchmarks.json', 'display-state.json', 'files-backup-state.json', 'gaming-state.json', 'gpu-state.json', 'game-tune.json', 'ram-check.json', 'fan-state.json', 'benchmarks.json',
    'health-history.json', 'junk-state.json', 'maint-state.json', 'net-history.json', 'perf-history.json', 'restart-ledger.json', 'self-test.json',
    'todo-scripted.json', 'update-state.json', 'vendor-state.json', 'kit-options.txt', 'maint-report.txt', 'maint-todo.txt', 'notifications.log',
    'tray-news.txt', 'tray-notified.ini', 'gpu-hold.txt', 'admin-sessions.txt', 'app-window.txt', 'tray-hwnd.txt', 'restart-night.log',
    'tweak-status.json', 'whats-new.json', 'diag-state.json', 'power-log.json', 'game-saves.json', 'live-test.json', 'app-last.txt', 'app-last-next.txt', 'app-window-place.txt',
    'chat\state.json', 'chat\events.jsonl', 'chat\mode.txt', 'chats\20260101-000000\state.json', 'chats\20260101-000000\events.jsonl', 'chats\20260101-000000\title.txt'
New-Item "$C\chat" -ItemType Directory -Force | Out-Null
$kinds = [ordered]@{
    'broken JSON'  = '{"date": "2026-01-01", "freeGB": '
    'empty'        = ''
    'wrong type'   = '[1, "two", {"three": [null]}, true]'
    'binary noise' = (-join ((1..600) | ForEach-Object { [char](Get-Random -Minimum 0 -Maximum 0xD7FF) }))
    'huge'         = 'x' * 3MB
    'bad dates'    = '[{"date":"not a date","bootAt":"99/99/9999","boot":"slow","freeGB":"lots","fps":-1,"game":null,"at":"yesterday","lastRun":5}]'
}
foreach ($k in $kinds.Keys) {
    foreach ($f in $states) { [IO.File]::WriteAllText("$C\$f", $kinds[$k]) }
    [IO.File]::WriteAllText("$C\maint-history\report-20260101-000000.txt", $kinds[$k])
    $r = Run-App $H
    $n = @([regex]::Matches("$($r.Out)", '(?m)^PAGE: ')).Count
    Check "every page builds, nothing fails ($k)" ($r.Code -eq 0 -and $n -eq $pages.Count -and -not (Errs $r)) ("exit $($r.Code), $n pages: " + (Errs $r)).Substring(0, [Math]::Min(600, ("exit $($r.Code), $n pages: " + (Errs $r)).Length))
}

Section 'an update while the window is open: offered, never swapped under the owner'
# (a copy of its own in $Work, without --live: the test names - the real app is not touched; the update the way
# kit-update does it: the running exe moved aside, the new one copied in)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$U = "$Work\upd"; New-Item $U -ItemType Directory -Force | Out-Null; Copy-Item "$(Split-Path $AppExe)\MessiahApp.exe*" $U -Force
$H = "$Work\updhome"; New-Item "$H\.claude", "$H\Documents" -ItemType Directory -Force | Out-Null
$psi = New-Object Diagnostics.ProcessStartInfo "$U\MessiahApp.exe", '--page Activity/Trends'; $psi.UseShellExecute = $false
$psi.EnvironmentVariables['USERPROFILE'] = $H; $psi.EnvironmentVariables['PCKIT_IN_TESTS'] = '1'; $psi.EnvironmentVariables.Remove('PCKIT_CLAUDE_DIR')
function UWin($procId) { for ($i = 0; $i -lt 40; $i++) { $p = Get-Process -Id $procId -ErrorAction SilentlyContinue; if ($p -and $p.MainWindowHandle -ne 0) { return [Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle) }; Start-Sleep -Milliseconds 500 } }
function UFind($w, $name) { if ($w) { $w.FindFirst([Windows.Automation.TreeScope]::Descendants, (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty, $name))) } }
$p1 = [Diagnostics.Process]::Start($psi); $w = UWin $p1.Id
if (-not $w) { Skip 'update offer' 'no window here (no desktop)' }
else {
    Start-Sleep 2
    Move-Item "$U\MessiahApp.exe" "$U\MessiahApp.exe.$PID.old" -Force; Copy-Item "$U\MessiahApp.exe.$PID.old" "$U\MessiahApp.exe"; (Get-Item "$U\MessiahApp.exe").LastWriteTime = Get-Date
    $btn = $null; for ($i = 0; $i -lt 45 -and -not $btn; $i++) { Start-Sleep 1; $btn = UFind $w 'Restart' }
    $seen = if (-not $btn) { (@($w.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition) | ForEach-Object { $_.Current.Name } | Where-Object { $_ }) | Select-Object -First 25) -join ' | ' }
    Check 'a new version while the window is open: "A new version of Messiah is ready." with a Restart button (within the 30 s check)' ($btn -and (UFind $w 'A new version of Messiah is ready.')) "exited=$($p1.HasExited) on screen: $seen"
    Check '... and the open window is left alone until then' (-not $p1.HasExited) ''
    if ($btn) {
        $btn.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke(); $p1.WaitForExit(10000) | Out-Null; Start-Sleep 2
        $p2 = Get-CimInstance Win32_Process -Filter "Name='MessiahApp.exe'" | Where-Object { $_.ExecutablePath -eq "$U\MessiahApp.exe" -and $_.ProcessId -ne $p1.Id } | Select-Object -First 1
        $w2 = if ($p2) { UWin $p2.ProcessId }
        Check 'Restart: the old copy ends, the new one opens on the same page (Activity > Trends)' ($p1.HasExited -and $p2 -and $p2.CommandLine -match "--after $($p1.Id)" -and (UFind $w2 'How this PC has been doing over time.')) "ended=$($p1.HasExited) new=$($p2.CommandLine)"
        if ($p2) { Stop-Process -Id $p2.ProcessId -Force -ErrorAction SilentlyContinue }
    }
}
if (-not $p1.HasExited) { $p1.Kill() }

Section 'the last session, the benchmark, your setup, the fans, the quick panel (10/22)'
$H = "$Work\feat"; $C = "$H\.claude"; New-Item $C, "$H\Documents" -ItemType Directory -Force | Out-Null
'claude=off' | Set-Content "$C\kit-options.txt"; $now = Get-Date
$rows = @(foreach ($i in 1..4) { [ordered]@{ date = $now.AddDays(-3).AddHours($i).ToString('o'); game = 'cod'; fps = 200; low1 = 150; stutters = 1 } }) + @(foreach ($i in 0..1) { [ordered]@{ date = $now.AddHours(-2).AddMinutes($i * 25).ToString('o'); game = 'cod'; fps = 230; low1 = 120; stutters = 2; gpuTemp = 72; cpuTemp = 81.5 } })
ConvertTo-Json -InputObject $rows | Set-Content "$C\perf-history.json"
"$($now.AddHours(-2.2).ToString('s')) | $($now.AddHours(-1).ToString('s')) | cod" | Set-Content "$C\game-sessions.log"
'[{"date":"2026-09-26","memBandwidthMBs":63102},{"date":"' + $now.ToString('s') + '","cpuMulti":1510,"cpuSingle":139,"memBandwidthMBs":52937,"diskReadMBs":1175,"ram":"4800 MT/s"}]' | Set-Content "$C\benchmarks.json"
'{"last":[{"Hw":"board","Name":"CPU Fan","Rpm":1250,"Duty":40},{"Hw":"board","Name":"Pump Fan","Rpm":870,"Duty":40},{"Hw":"board","Name":"System Fan #1","Rpm":0,"Duty":0},{"Hw":"gpu","Name":"GPU Fan 1","Rpm":0,"Duty":0}]}' | Set-Content "$C\fan-state.json"
"defenderexclusions=on`r`ntweak.edge-remove=on`r`nchatwidth=900" | Add-Content "$C\kit-options.txt"
$r = Run-App $H
Check 'the page builds' (-not (Errs $r)) (Errs $r)
Check 'Home: the last session - how long, against the usual, the hottest it got' ($r.Out -match 'CARD: Last session\s+Call of Duty - 1 h 12 min, ended .+?: 230 fps average \(usual 200 - better\), 1% low 120 fps \(usual 150 - lower\), 4 hitches\.' -and $r.Out -match 'Graphics card up to 72 °C, processor up to 81\.5 °C - from 2 measured minutes\.') ''
Check 'Performance: the benchmark, each run with its RAM speed, and its button' ($r.Out -match 'CARD: Benchmark\s+today: memory 52,937 MB/s, processor 1,510 MB/s all cores / 139 MB/s one, SSD 1,175 MB/s - RAM at 4800 MT/s' -and $r.Out -match 'BUTTONS: Run the benchmark') ''
Check 'Heat and wear: the fans that spin, the graphics card''s stopped while cool' ($r.Out -match 'Fans: CPU Fan: 1250 RPM, pump: 870 RPM, graphics card: stopped') ''
Check 'Settings > Tools: your setup - how many chosen here (only Messiah''s switches and Windows choices), save, load, presets' ($r.Out -match 'CARD: Your setup\s+[^\r\n]*- 2 chosen on this PC' -and $r.Out -match 'BUTTONS: Save to a file\.\.\. \| Load a setup\.\.\. \| Everything for gaming \| Recommended') ''
Section 'the charts: hover, what changed, 7 days / 30 days / all, a session clicked open (10/22)'
Check 'a chart over 30 days starts on the last 30, with the ranges offered' ($r.Out -match '(?m)^CHARTTEST tag: CHART: Frame rate, each session \| 9 points, .*\| ranges: 7 days, 30 days\*, All' -and $r.Out -match '(?m)^CHARTTEST all: 12 points') ''
Check 'a point read: its date, its value, what else was going on (not its own value twice)' ($r.Out -match '(?m)^CHARTTEST hover first: \w{3} Sep 2\d, .+: 143 fps - 1% low 103, graphics card busy 97% of each frame, RAM 4800 MT/s\s*$') ''
Check 'what changed is marked, and said at the first session after it' ($r.Out -match '\| marks: Graphics driver 2\.0; trying GPU upload heaps on; trying GPU upload heaps off \|' -and $r.Out -match '(?m)^CHARTTEST hover after the driver: .+\(changed: Graphics driver 2\.0\)') ''
Check '... the setting being tried, by its value (said once)' ($r.Out -match '(?m)^CHARTTEST hover tested: .+trying GPU upload heaps off\s*$') ''
Check 'a session clicked: opened under the charts, its minute second by second, a way back to the latest' ($r.Out -match '(?m)^CHARTTEST clicked: Session opened: 143 fps average.+ / That minute \(.+\), second by second / Back to the latest session') ''
Check 'Trends: the most played game''s charts open a session on Performance' ($r.Out -match 'CHART: Frame rate - Call of Duty \|.*click opens a session') ''
Check 'the tray''s quick panel: status, temperatures, Game Mode, the main actions' ($r.Out -match '(?m)^QUICK: .*Processor .*\| Game Mode \|.*\[Open Messiah\] \| \[Run maintenance\] \| \[Pause 2 h\]') ''
Check 'Settings: the switch for watching the fans' ($r.Out -match 'Watch the fans') ''
Section 'the switch-over: the tray, the Start menu, installs and updates run it'
$trayText = Get-Content $env:PCKIT_TRAY -Raw
Check 'the tray opens it (--live, --page) and starts it hidden (--background)' ($trayText -match 'app\\MessiahApp\.exe' -and $trayText -match "--live' \(page" -and $trayText -match '--live --background') ''
Check '... and nothing runs the PowerShell app any more (removed 10/21; the text status.ps1 when the exe is missing)' ($trayText -notmatch 'dashboard\.ps1' -and $trayText -match 'status\.ps1') ''
Check 'the Start menu entry runs it' ((Get-Content "$Src\tray-app.ps1" -Raw) -match '\$appTarget = (Get-LongPath )?"\$ClaudeDir\\app\\MessiahApp\.exe"; \$appArgs = ''--live''') ''
Check 'setup and updates install it (a running copy moved aside)' ((Get-Content "$Kit\setup.ps1" -Raw) -match 'claude\\app\\MessiahApp\.exe' -and (Get-Content "$Src\kit-update.ps1" -Raw) -match 'Install-App "\$k\\claude\\app"') ''
Finish
