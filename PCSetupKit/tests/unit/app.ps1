# The app window (MessiahApp.exe, compiled from app\Messiah.App): its own test (--test) builds every page and the chat
# from a home folder's files and prints them - here a sandbox home: a new install, one with made-up data, and every
# state file filled with garbage (in a profile path with spaces and non-English letters). No window opens; nothing is
# read from this PC's own .claude. (tray-windows and chaos-state check it too.)
. "$PSScriptRoot\..\lib.ps1"
if (-not $AppExe) { Skip 'app' 'not built here (tools\app\build.ps1)'; Finish }
function Run-App([string]$Home_, [hashtable]$Env = @{}, [string[]]$ArgList = @()) { Invoke-App $Home_ $ArgList $Env }
function Errs($r) { ((@($r.Out -split "`r?`n" | Where-Object { $_ -match 'PAGE ERROR' }) + @($r.Err.Trim()) | Where-Object { $_ }) -join ' | ') }
$pages = 'Welcome', 'Home', 'Status', 'Activity/Checks', 'Activity/Stability', 'Activity/Trends', 'Activity/Alerts', 'Settings/General', 'Settings/Windows', 'Settings/Tools'

Section 'a new install (nothing written yet)'
$H = "$Work\new"; New-Item "$H\.claude", "$H\Documents" -ItemType Directory -Force | Out-Null
$r = Run-App $H
Check 'it runs and ends by itself' ($r.Code -eq 0) "exit $($r.Code) $($r.Err)"
$miss = @($pages | Where-Object { $r.Out -notmatch "(?m)^PAGE: $([regex]::Escape($_)) " })
Check 'every page is built' (-not $miss) "missing: $($miss -join ', ')"
Check 'no page fails' (-not (Errs $r)) (Errs $r)
Check 'tabs: Home, Status, Activity, Settings' ($r.Out -match '(?m)^NAV: Home \| Status \| Activity \| Settings\s*$') ''
Check 'Home: all good, no report yet' ($r.Out -match 'All good - nothing needs you' -and $r.Out -match 'No report yet') ''
Check 'the chat: replies, links, attachments, edit, find and speed work' ($r.Out -match 'CHAT: reply=RichTextBox' -and $r.Out -match 'CHAT FIND: found=3' -and $r.Out -match 'CHAT EDIT: .*editing=True' -and $r.Out -match 'CHAT MODE: default=Standard chosen=Deep' -and $r.Out -match 'CHAT FIND: .*marked=3 leftover=0') ''
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

Section 'break it: every state file garbage, in a profile path with spaces and non-English letters'
$H = "$Work\Jörg Müller ÄÖÜ ñ"; $C = "$H\.claude"; New-Item $C, "$H\Documents", "$C\maint-history", "$C\chats\20260101-000000" -ItemType Directory -Force | Out-Null
$states = 'actions-state.json', 'guard-state.json', 'benchmarks.json', 'display-state.json', 'files-backup-state.json', 'gaming-state.json', 'gpu-state.json',
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

Section 'the switch-over: the tray, the Start menu, installs and updates run it'
$trayText = Get-Content $env:PCKIT_TRAY -Raw
Check 'the tray opens it (--live, --page) and starts it hidden (--background)' ($trayText -match 'app\\MessiahApp\.exe' -and $trayText -match "--live' \(page" -and $trayText -match '--live --background') ''
Check '... and nothing runs the PowerShell app any more (removed 10/21; the text status.ps1 when the exe is missing)' ($trayText -notmatch 'dashboard\.ps1' -and $trayText -match 'status\.ps1') ''
Check 'the Start menu entry runs it' ((Get-Content "$Src\tray-app.ps1" -Raw) -match '\$appTarget = "\$ClaudeDir\\app\\MessiahApp\.exe"; \$appArgs = ''--live''') ''
Check 'setup and updates install it (a running copy moved aside)' ((Get-Content "$Kit\setup.ps1" -Raw) -match 'claude\\app\\MessiahApp\.exe' -and (Get-Content "$Src\kit-update.ps1" -Raw) -match 'Install-App "\$k\\claude\\app"') ''
Finish
