# The windows the tray menu opens: "Watch maintenance live" (maint-watch.ps1), "Status" (the window, MessiahApp.exe, and
# its text fallback status.ps1), in a sandbox home.
. "$PSScriptRoot\..\lib.ps1"
$H = "$Work\home"; $C = "$H\.claude"; $P = "$C\projects\C--WINDOWS-system32"
New-Item $P, "$C\maint-claude-log", "$H\.local\bin" -ItemType Directory -Force | Out-Null
Copy-Item "$Src\maint-watch.ps1", "$Src\status.ps1", "$Src\status-lib.ps1", "$Src\session-lib.ps1", "$Src\ai-enabled.ps1" $C; 'claude=on' | Set-Content "$C\kit-options.txt"
Copy-Item (Get-ScriptedClaude) "$H\.local\bin\claude.exe"
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
function Asst($text, $tool, $desc) {
    $c = if ($tool) { @(@{ type = 'tool_use'; name = $tool; input = @{ description = $desc } }) } else { @(@{ type = 'text'; text = $text }) }
    @{ type = 'assistant'; timestamp = (Get-Date).ToUniversalTime().ToString('o'); message = @{ role = 'assistant'; content = $c } } | ConvertTo-Json -Depth 6 -Compress
}

Section 'Watch maintenance live'
"# improve run`nChanged: nothing" | Set-Content "$C\maint-claude-log\20260927-093549-improve.md"
$r = Invoke-As $H "$C\maint-watch.ps1"
Check 'nothing running: says so and shows the last run''s log' (($r.Out -match "isn't running right now") -and ($r.Out -match 'Last run: 20260927-093549-improve') -and ($r.Out -match 'Changed: nothing')) $r.Out
'x' | Set-Content "$C\maint-claude-running"; (Get-Item "$C\maint-claude-running").LastWriteTime = $boot.AddMinutes(-5)
$r = Invoke-As $H "$C\maint-watch.ps1"
Check 'a busy marker from before the restart counts as not running' ($r.Out -match "isn't running right now") $r.Out
$id = [guid]::NewGuid().ToString()
@($id, 'maintain', (Get-Date).ToString('o')) | Set-Content "$C\maint-claude-session"
(Asst $null 'PowerShell' 'Check crash dumps') | Set-Content "$P\$id.jsonl"
'x' | Set-Content "$C\maint-claude-running"
$u = $env:USERPROFILE; $env:USERPROFILE = $H
$w = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$C\maint-watch.ps1`"" -PassThru -WindowStyle Hidden -RedirectStandardOutput "$Work\watch.txt"
$env:USERPROFILE = $u
Start-Sleep 4
Add-Content "$P\$id.jsonl" (Asst 'Found one blue screen: 0x109, memory corruption.' $null $null)
Add-Content "$P\$id.jsonl" '{"type":"user","message":{"role":"user","content":"tool output that must not be shown"}}'
Start-Sleep 4
[IO.File]::Delete("$C\maint-claude-running")
$done = $w.WaitForExit(15000); if (-not $done) { Stop-Process -Id $w.Id -Force }
$out = Get-Content "$Work\watch.txt" -Raw
Check 'while running: header with the kind of run' ($out -match '=== Hidden maintenance: maintain \(started') $out
Check 'follows the session live: tool steps and Claude''s text as they happen' (($out -match '> Check crash dumps') -and ($out -match 'Found one blue screen: 0x109')) $out
Check 'tool output / user records are not shown' ($out -notmatch 'must not be shown') ''
Check 'ends by itself when the run finishes' ($done -and $out -match 'Finished') $out

Section 'Status'
'Blue screen test: EXPO is off. Nothing to do.' | Set-Content "$C\maint-todo.txt" -Encoding UTF8
@{ boot = '2026-09-27T09:33:24'; recorded = (Get-Date).ToString('o'); items = @(@{ Kind = 'update'; Id = 'u1'; Name = 'KB5099999 cumulative update' }) } | ConvertTo-Json -Depth 4 | Set-Content "$C\restart-ledger.json"
'Checked 9/27/2026 12:00 PM in 18s', '[Drivers]', 'NVIDIA: 617.14 is up to date', '[PC health]', 'WARNING: blue screen 0x109 at 9/27/2026', 'Reminder: BIOS 1.10 is old' | Set-Content "$C\maint-report.txt"
@{ 'weekly-apps' = (Get-Date).AddDays(-2).ToString('o'); 'monthly-cleanup' = (Get-Date).AddDays(-45).ToString('o'); 'claude-quarterly' = (Get-Date).AddDays(-10).ToString('o') } | ConvertTo-Json | Set-Content "$C\maint-state.json"
(Get-Date).AddHours(-5).ToString('o') | Set-Content "$C\selfimprove-last"
$r = Invoke-As $H "$C\status.ps1" @('-NoWait') @{ FAKE_DIR = "$Work\fake" }
New-Item "$Work\fake" -ItemType Directory -Force | Out-Null
$s = $r.Out
Check 'no errors' (-not $r.Err.Trim()) $r.Err
Check 'shows what needs the owner' ($s -match 'Needs you\s+- Blue screen test') $s
Check 'shows what waits for the next shutdown' ($s -match 'Waiting for your next shutdown or restart\s+- KB5099999') $s
Check 'says it can finish with a restart at night (Restart at night is on by default here; 10/28: always the next time you turn the PC off)' (($s -match 'at the next restart: one at night while the PC is unused \(Settings > Restart at night\), or when you turn it off') -and ($s -notmatch 'the next time you turn the PC off;')) $s
Check 'shows the last check with its warnings and reminders only' (($s -match 'Checked 9/27/2026 12:00 PM') -and ($s -match 'WARNING: blue screen') -and ($s -match 'Reminder: BIOS') -and ($s -notmatch 'NVIDIA: 617.14')) $s
Check 'scheduled checks: overdue = "due now", others dated, missing = "due now"' (($s -match 'Cleanup:\s+due now') -and ($s -match 'App updates:\s+\w{3} \d+, \d{4}') -and ($s -match 'Full tune-up:\s+due now') -and ($s -notmatch 'Quarterly|Half-year|re-optimize')) $s
Check '... each row says how often or what, as the app does (10/27)' (($s -match 'App updates:\s+[^\r\n]*\(every week\)') -and ($s -match 'Cleanup:\s+due now  \(every month: temporary files, old drivers, a restore point\)') -and ($s -notmatch 'Monthly cleanup') -and ($s -match 'Full tune-up:\s+due now  \(every year: the whole setup again\)') -and ($s -match 'Self-check:\s+at the next login  \(the app tests itself every week\)')) $s
Check 'self-improvement: last run and when the next is allowed' ($s -match 'Self-improvement: last .*next at the first login after') $s
@{ ok = $true; result = '1500 passed, 0 failed'; failed = @(); date = (Get-Date).AddDays(-2).ToString('o') } | ConvertTo-Json | Set-Content "$C\self-test.json"
$s = (Invoke-As $H "$C\status.ps1" @('-NoWait')).Out
Check "... the self-test row: the next date first, then how often and the last result (10/27: was 'passed 10/26 (...); next ...')" ($s -match "Self-check:\s+$([regex]::Escape((Get-Date).AddDays(5).ToString('MMM d, yyyy')))  \(the app tests itself every week and after updates\)\. Last run \w{3} \d+: all fine\.") (($s -split "`n" | Select-String 'Self-check') -join ' / ')
@{ ok = $false; result = '1497 passed, 3 failed'; failed = @('junk', 'tweaks'); date = (Get-Date).AddDays(-9).ToString('o') } | ConvertTo-Json | Set-Content "$C\self-test.json"
$s = (Invoke-As $H "$C\status.ps1" @('-NoWait')).Out
Check '... a failed one overdue: at the next login, what failed' ($s -match 'Self-check:\s+at the next login  \(the app tests itself every week and after updates\)\. Last run \w{3} \d+: 3 checks failed in junk, tweaks\.') (($s -split "`n" | Select-String 'Self-check') -join ' / ')
Clear-Path "$C\self-test.json"
'Checked 10/27/2026 12:19 PM in 30s', '[Drivers]', 'NVIDIA: 621.01 is up to date', 'Other drivers: all up to date (Windows Update)', 'Crashes: none since last check', 'Tweaks: all still applied', 'Call of Duty tuning: kept Reflex Boost on', 'Next: App updates Nov 3' | Set-Content "$C\maint-report.txt"
$s = (Invoke-As $H "$C\status.ps1" @('-NoWait')).Out
Check "... a check with nothing notable: 'All fine' and what it looked at, as the app's Checks (10/28)" ($s -match 'All fine\s+Looked at drivers, crashes and your tweaks\.') (($s -split "`n" | Select-String 'All fine' -Context 0, 1) -join ' ')
Get-ChildItem $C -File | Where-Object Name -in 'maint-todo.txt', 'restart-ledger.json', 'maint-report.txt', 'maint-state.json', 'selfimprove-last' | ForEach-Object { Clear-Path $_.FullName }
$r = Invoke-As $H "$C\status.ps1" @('-NoWait')
Check 'a brand-new install with no data yet: no errors, sensible defaults' ((-not $r.Err.Trim()) -and ($r.Out -match 'Needs you\s+Nothing') -and ($r.Out -match 'No report yet')) ($r.Err + $r.Out)
'claude=off' | Set-Content "$C\kit-options.txt"; (Get-Date).AddHours(-5).ToString('o') | Set-Content "$C\selfimprove-last"
$r = Invoke-As $H "$C\status.ps1" @('-NoWait')
Check 'without Claude: no Claude sections (sessions, hidden Claude runs), no errors' ((-not $r.Err.Trim()) -and ($r.Out -notmatch 'Messiah|Claude Code|Session|Self-improvement') -and ($r.Out -match 'Needs you') -and ($r.Out -match 'Scheduled checks')) ($r.Err + $r.Out)

Section 'the app window (MessiahApp.exe)'
'Turn EXPO back on in the BIOS.' | Set-Content "$C\maint-todo.txt" -Encoding UTF8
'Checked 9/27/2026 12:00 PM in 18s', '[Drivers]', 'NVIDIA: 617.14 is up to date' | Set-Content "$C\maint-report.txt"
$r = Invoke-App $H
$d = $r.Out
Check 'without the AI assistant: still "Messiah", no errors' ((-not $r.Err.Trim()) -and ($d -match '(?m)^WINDOW: Messiah\s*$')) ($r.Err + $d)
Check '... tabs: Home, Games, Health, Optimizations, Settings (no Claude button or card)' ($d -match '(?m)^NAV: Home \| Games \| Health \| Optimizations \| Settings\s*$' -and $d -notmatch 'CARD: Claude\s*$|Ask Claude') $d
Check '... Health > Trends: a chart per measure; with no history yet it says it is collecting' (($d -match 'CHART: Start-up time \| 0 point') -and ($d -match 'CHART: Free space on C: \|') -and ($d -match 'CHART: Graphics card at idle \|') -and ($d -match 'CHART: SSD temperature \|')) $d
Check '... Health > Alerts: none yet, a plain line saying what would show' ($d -match 'CARD: Alerts\s+No alerts yet - a crash, a drive filling up or a driver to try would show here\.') $d
# only an older alert: the Alerts card says so in a plain line, the alert sits under Earlier and resolved
"$((Get-Date).AddDays(-10).ToString('yyyy-MM-dd')) 10:00|Maintenance started in the background." | Set-Content "$C\notifications.log" -Encoding UTF8
$r = Invoke-App $H; $d2 = $r.Out
Check '... Alerts with only older ones: "Nothing new this week", the old one under Earlier and resolved' (($d2 -match 'CARD: Alerts\s+Nothing new this week - the older ones are under Earlier and resolved\.') -and ($d2 -match 'CARD: Earlier and resolved\s+[^\r\n]*Maintenance started')) $d2
Clear-Path "$C\notifications.log"
# only a power-off from before the chart's 120 days: What happened says so in a plain line (10/28: an empty-label row
# sat indented under the date column)
$at = (Get-Date).AddDays(-200).ToString('yyyy-MM-ddT03:00:00')
ConvertTo-Json -Depth 4 @{ events = @(@{ at = $at; key = $at; kind = 'off'; code = ''; answer = 'me' }) } | Set-Content "$C\power-log.json"
$r = Invoke-App $H; $d2 = $r.Out
Check '... Stability with only older events: "Nothing in the last 120 days", the old one under Show 1 more' ($d2 -match 'CARD: What happened\s+[^\r\n]*Went off without a blue screen \(you turned it off\)\s+Nothing in the last 120 days - the older one is under Show 1 more\.\s+ALIGN: stability\s+BUTTONS: Show 1 more') $d2
Clear-Path "$C\power-log.json"
# with a history, saved reports and alerts
$now = Get-Date
$rows = for ($i = 10; $i -ge 0; $i--) { [ordered]@{ date = $now.AddDays(-$i).ToString('o'); bootAt = $now.AddDays(-$i).AddMinutes(-3).ToString('o'); boot = 26 + ($i % 2); freeGB = 500 - $i; gpuIdle = 30; ssdTemp = 45 } }
ConvertTo-Json -InputObject @($rows) | Set-Content "$C\health-history.json"
New-Item "$C\maint-history" -ItemType Directory -Force | Out-Null
'Checked 9/20/2026 9:00 AM in 30s', '[Periodic]', 'Updated app: Vendor.Tool', 'Tweaks: all still applied' | Set-Content "$C\maint-history\report-20260920-090000.txt"
"$($now.ToString('yyyy-MM-dd')) 10:00|Maintenance started in the background. / The result shows here" | Set-Content "$C\notifications.log" -Encoding UTF8
@{ ok = $true; result = '1500 passed, 0 failed'; failed = @(); date = (Get-Date).AddDays(-2).ToString('o') } | ConvertTo-Json | Set-Content "$C\self-test.json"
$r = Invoke-App $H; $d = $r.Out
Check '... Trends: 11 start-ups charted, now and usual values' (($d -match 'CHART: Start-up time \| 11 points, now 26 s, usual 26\.\d s|CHART: Start-up time \| 11 points, now 26 s, usual 26 s') -and ($d -match 'CHART: Free space on C: \| 11 points, now 500 GB')) $d
Check '... "What maintenance did" lists what changed, not routine lines' (($d -match '(?m)^\s+\S[^\r\n]*: Updated app: Tool\r?$') -and ($d -notmatch 'all still applied')) $d
Check '... Alerts: past alerts with their time, and a Clear button' (($d -match 'CARD: Alerts\s+\S+ \S+ \d+, 10:00 AM: Maintenance started in the background') -and ($d -match 'BUTTONS: Clear')) $d
Check "... Scheduled checks' Self-test row: when first, like the others (10/27: was 'passed 10/26 (...); next ...')" (($d -match 'Self-check: [^\r\n]*  \(the app tests itself every week and after updates\)\. Last run \w{3} \d+: all fine\.') -and ($d -notmatch '; next |kit update')) (($d -split "`n" | Select-String 'Self-check') -join ' / ')
Clear-Path "$C\health-history.json", "$C\maint-history", "$C\notifications.log", "$C\self-test.json"
Check '... Home leads with what needs the owner' (($d -match 'PAGE: Home[^\r\n]*\s+CARD: -\s+1 thing needs you') -and ($d -match 'CARD: Needs you\s+Turn EXPO back on in the BIOS\.\s+BUTTONS: Snooze a week \| Dismiss')) $d
Check '... Home has the main actions' ($d -match 'BUTTONS: Run maintenance now \| Optimize this PC') $d
Check '... Health > Checks shows the last check and how many things need the owner (the list itself only on Home); no Claude parts' (($d -match 'PAGE: Activity/Checks[^\r\n]*\s+CARD: Last background check\s+Checked \S[^\r\n]* \(took 18 s\)') -and ($d -match 'BUTTONS: Run maintenance now \| Full report') -and ($d -match 'CARD: Needs you\s+1 thing needs you - listed on Home\.\s+BUTTONS: Open Home \| Open the to-do list') -and ($d -notmatch '(?m)CARD: Claude\s*$|Watch live|Claude''s own checks|Ask Claude')) $d
Check "... every scheduled row says how often or what, the same way (10/27: App updates and Monthly cleanup said nothing, 'yearly', 'weekly' at the end)" (($d -match 'App updates: [^\r\n]*\(every week\)') -and ($d -match 'Cleanup: [^\r\n]*\(every month: temporary files, old drivers, a restore point\)') -and ($d -match 'Full tune-up: [^\r\n]*\(every year: the whole setup again\)') -and ($d -notmatch 'yearly - |scripts, weekly')) (($d -split "`n" | Select-String 'App updates|Cleanup|Full tune-up|Self-check') -join ' / ')
Check '... the schedule as a table; the settings to open at login and for corner alerts' (($d -match 'CARD: Scheduled checks\s+App updates: ') -and ($d -match 'Open Messiah when I log in') -and ($d -match 'Show alerts in the corner\s+[^\r\n]*\s+Off \(default\): nothing pops up')) $d
Check '... every page and sub-page builds: Home, Status, Activity (Checks, Trends, Alerts), Settings (General, Windows, Tools)' ((@([regex]::Matches($d, '(?m)^PAGE: (Home|Status|Activity/(Checks|Trends|Alerts)|Settings/(General|Windows|Tools))  \(built in')).Count -eq 8) -and $d -notmatch 'PAGE ERROR') $d
Check '... Status: never checked yet - each row says so' (($d -match 'PAGE: Status[^\r\n]*\s+CARD: -\s+Not checked yet') -and ($d -match 'Telemetry, ads, suggestions and Windows AI off / Not checked yet')) $d
# a guard pass's result (tweaks.ps1 -StatusFile): in place, one put back, Windows-protected ones, an opt-in never turned on
'{"at":"' + (Get-Date).ToString('o') + '","preview":false,"cause":"Windows Update (KB5099999)","optIn":["edge-remove","notifications-off","sysmain-off"],"keys":{"telemetry":{"same":57,"fixed":[],"blocked":0,"names":["HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DataCollection\\AllowTelemetry"]},"start-menu":{"same":4,"fixed":["Start_TrackDocs"],"blocked":0},"#Scheduled tasks":{"same":0,"fixed":[],"blocked":3}}}' | Set-Content "$C\tweak-status.json"
$r = Invoke-App $H; $d2 = $r.Out
Check '... Status after a guard pass: all green, what was put back, Windows-protected, opt-ins not on' ((-not $r.Err.Trim()) -and ($d2 -match 'PAGE: Status[^\r\n]*\s+CARD: -\s+All \d+ in place') -and ($d2 -match 'Telemetry, ads[^/]+ / In place(\s|$)') -and ($d2 -match 'Start menu recommendations and Task View off / Put back [^/]+ / Something had changed it: Recent files in Start - after Windows Update \(KB5099999\)') -and ($d2 -match 'TILE: Guarded: \d+ of \d+ in place') -and ($d2 -match 'Edge removed completely / Not turned on') -and ($d2 -match '3 protected by Windows')) ($r.Err + $d2)
Check '... each row''s details behind a click: what it does, the settings it checks, its last check, a way to change it' (($d2 -match 'Telemetry, ads, suggestions and Windows AI off / [^\r\n]*\s+MORE: What it does  No diagnostic data[^\r\n]*\| Checks 1 setting  Telemetry level \| Last check  [^\r\n]*\| History  Never had to be put back \| \[Change in Settings\]') -and ($d2 -match 'Windows keeps registry backups / [^\r\n]*\s+MORE: What it does  Windows saves copies')) $d2
'tweak.telemetry=off' | Add-Content "$C\kit-options.txt"
$r = Invoke-App $H; $d2 = $r.Out
Check '... a switch turned off in Settings shows as the owner''s choice' ($d2 -match 'Telemetry, ads[^/]+ / Off - your choice') $d2
# a crash-hunting mode left on (diag-modes.ps1 - a stand-in here): amber from the start, with its off button; Home's tile says so too
'{"verifier":"2026-10-04"}' | Set-Content "$C\diag-state.json"   # (the app reads the registry itself: PCKIT_DIAG_TEST stands in for it)
$r = Invoke-App $H @() @{ PCKIT_DIAG_TEST = (((1..18) | ForEach-Object { "d$_.sys" }) -join ' ') + '|' }; $d2 = $r.Out
Check '... a crash-hunting mode left on (Driver Verifier): amber with its off button; Home''s tile counts it' ((-not $r.Err.Trim()) -and ($d2 -match 'Crash-hunting modes off / Driver Verifier \(18 drivers\) on / On for \d+ days \(since Oct 4\)[^\r\n]*\[Turn off Driver Verifier\]') -and ($d2 -match 'TILE: Guarded: 1 needs a look / Driver Verifier \(18 drivers\) on, see Optimizations') -and ($d2 -match 'PAGE: Status[^\r\n]*\s+CARD: -\s+1 needs a look')) ($r.Err + $d2)
Clear-Path "$C\diag-state.json"
Check '... filters on top (All / Needs a look / Put back / Off, with counts)' ($d2 -match 'FILTERS: All  \d+\* \| Needs a look  1 \| Put back  1 \| Off  \d+') $d2
'technames=on' | Add-Content "$C\kit-options.txt"; $r = Invoke-App $H; $d2 = $r.Out
Check '... settings in plain words, or by their registry names when chosen (Settings > General)' ($d2 -match 'Checks 1 setting  AllowTelemetry \|') $d2
# Home: a game running (game-check.ps1 - a stand-in name here) and what's new after an update (whats-new.json)
'{"version":"v2026.10.12","date":"' + (Get-Date).ToString('o') + '","points":["Status tab: every optimization at a glance","Search with Ctrl+K"],"url":"https://github.com/x/y/releases/tag/v2026.10.12"}' | Set-Content "$C\whats-new.json"
$r = Invoke-App $H @() @{ PCKIT_GAME_TEST = 'Test Game'; PCKIT_REPORT_TEST = '1' }; $d2 = $r.Out
Check 'Home while a game runs: says maintenance waits' ((-not $r.Err.Trim()) -and ($d2 -match 'CARD: Playing Test Game\s+Updates, checks and cleanup wait')) ($r.Err + $d2)
Check 'Home after an update: what''s new, with Got it and the release notes' ($d2 -match "CARD: What's new in Messiah v2026\.10\.12\s+[^\r\n]*Status tab: every optimization at a glance\s+[^\r\n]*Search with Ctrl\+K\s+BUTTONS: Got it \| All release notes") $d2
Check 'the help report: status, what needs the owner and the last check - no PC name' (($d2 -match 'REPORT: Messiah report - ') -and ($d2 -match 'STATUS: ') -and ($d2 -match 'NEEDS THE OWNER: ') -and ($d2 -match 'LAST CHECK:') -and ($d2 -notmatch [regex]::Escape($env:COMPUTERNAME))) $d2
'newsseen=v2026.10.12' | Add-Content "$C\kit-options.txt"; $r = Invoke-App $H; $d2 = $r.Out
Check '... Got it: the card goes' ($d2 -notmatch "What's new in Messiah") $d2
Clear-Path "$C\whats-new.json"
# Alerts: a "Needs you" alert whose item is no longer on the to-do list moves to "Earlier and resolved"
"$((Get-Date).ToString('yyyy-MM-dd')) 09:00|Needs you (1): Something long settled that nobody needs to do any more" | Add-Content "$C\notifications.log" -Encoding UTF8
$r = Invoke-App $H; $d2 = $r.Out
Check 'Alerts: a resolved "Needs you" moves to Earlier and resolved' ($d2 -match 'CARD: Earlier and resolved\s+[^\r\n]*Something long settled that nobody needs to do any more  \(resolved\)') $d2
Check '... and its row opens nothing (it''s done)' ($d2 -notmatch 'GO: [^\r\n]*Home#Needs you') $d2
# an alert's row opens what it's about (10/27): updates waiting and maintenance Checks, a blue screen Stability; a chat's note nothing
$t = (Get-Date).ToString('yyyy-MM-dd')
"$t 10:00|2 update(s)/fix(es) will finish the next time you turn the PC off. / No need to restart now", "$t 10:05|A blue screen last night (0x109) - details on Stability", "$t 10:10|Maintenance started in the background. / The result shows here", "$t 10:15|Claude finished: the crash is fixed" | Add-Content "$C\notifications.log" -Encoding UTF8
$r = Invoke-App $H; $d2 = $r.Out
$go = [regex]::Match($d2, 'CARD: Alerts[\s\S]*?GO: ([^\r\n]*)').Groups[1].Value
Check 'Alerts: each row opens its page - updates and maintenance Checks, a blue screen Stability, a chat''s note nothing' (($go -match '10:00 AM > Activity/Checks \(Open Health > Checks\)') -and ($go -match '10:05 AM > Activity/Stability \(Open Health > Stability\)') -and ($go -match '10:10 AM > Activity/Checks') -and ($go -notmatch '10:15 AM')) $go
# the two cards' tables share one label width, so their words start at the same place (10/27)
Check 'Alerts: both cards'' tables line up (ALIGN: alerts on each)' (([regex]::Matches($d2, '(?m)^CARD: (Alerts|Earlier and resolved)\r?$[\s\S]*?^  ALIGN: alerts\r?$')).Count -eq 2) $d2
Clear-Path "$C\notifications.log"
# Claude usage: its three tables (by kind, conversations, steps) share one label width (10/27)
'{"kinds":[{"kind":"Maintenance","share":60},{"kind":"Chat","share":40}],"sessions":[{"share":84,"title":"Fix the big file","kind":"Improving Messiah","replies":4}],"steps":[{"tokens":45000,"tool":"Read","what":"a big file","session":"Fix the big file"}]}' | Set-Content "$C\claude-usage.json"
$opts = Get-Content "$C\kit-options.txt"; @($opts) + 'claude=on' | Set-Content "$C\kit-options.txt"   # (the card is Claude's)
$r = Invoke-App $H; $d2 = $r.Out
$u = [regex]::Match($d2, '(?m)^CARD: Claude usage\r?$[\s\S]*?(?=^CARD: |\z)').Value
Check 'Claude usage: its three tables line up (ALIGN: usage)' ((-not $r.Err.Trim()) -and ($u -match '(?m)^  ALIGN: usage\r?$')) ($r.Err + $u)
Check '... a conversation''s kind mid-sentence keeps the app''s name capitalized (improving Messiah)' ($u -cmatch 'Fix the big file - improving Messiah,') $u
$opts | Set-Content "$C\kit-options.txt"; Clear-Path "$C\claude-usage.json"

Clear-Path "$C\tweak-status.json"
'claude=on' | Set-Content "$C\kit-options.txt"; Clear-Path "$C\maint-todo.txt"
$r = Invoke-App $H @() @{ FAKE_DIR = "$Work\fake" }
$d = $r.Out
Check 'with Claude: "Messiah" with the chat (Open chat on Home - no terminal sessions) and the live watch' ((-not $r.Err.Trim()) -and ($d -match '(?m)^WINDOW: Messiah\s*$') -and ($d -match 'CARD: Claude') -and ($d -match 'BUTTONS: Open chat') -and ($d -notmatch 'Show sessions|Hide sessions') -and ($d -match 'CARD: Claude''s own checks') -and ($d -match 'Watch live')) ($r.Err + $d)
Check '... nothing to do: "All good"' ($d -match 'PAGE: Home[^\r\n]*\s+CARD: -\s+All good, nothing needs you') $d
Check '... Home says what Claude is doing' ($d -match 'CARD: Claude\s+(Chat with Claude right here|Ready. |Working right now)') $d
Finish
