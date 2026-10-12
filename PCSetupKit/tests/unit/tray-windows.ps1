# The windows the tray menu opens: "Watch maintenance live" (maint-watch.ps1), "Status" (the window, dashboard.ps1, and
# its text fallback status.ps1), in a sandbox home.
. "$PSScriptRoot\..\lib.ps1"
$H = "$Work\home"; $C = "$H\.claude"; $P = "$C\projects\C--WINDOWS-system32"
New-Item $P, "$C\maint-claude-log", "$H\.local\bin" -ItemType Directory -Force | Out-Null
Copy-Item "$Src\maint-watch.ps1", "$Src\status.ps1", "$Src\status-lib.ps1", "$Src\dashboard.ps1", "$Src\session-lib.ps1", "$Src\ai-enabled.ps1" $C; 'claude=on' | Set-Content "$C\kit-options.txt"
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
Check 'shows the last check with its warnings and reminders only' (($s -match 'Checked 9/27/2026 12:00 PM') -and ($s -match 'WARNING: blue screen') -and ($s -match 'Reminder: BIOS') -and ($s -notmatch 'NVIDIA: 617.14')) $s
Check 'scheduled checks: overdue = "due now", others dated, missing = "due now"' (($s -match 'Monthly cleanup:\s+due now') -and ($s -match 'App updates:\s+\w{3} \d+, \d{4}') -and ($s -match 'Yearly re-optimize:\s+due now')) $s
Check 'self-improvement: last run and when the next is allowed' ($s -match 'Self-improvement: last .*next at the first login after') $s
Get-ChildItem $C -File | Where-Object Name -in 'maint-todo.txt', 'restart-ledger.json', 'maint-report.txt', 'maint-state.json', 'selfimprove-last' | ForEach-Object { Clear-Path $_.FullName }
$r = Invoke-As $H "$C\status.ps1" @('-NoWait')
Check 'a brand-new install with no data yet: no errors, sensible defaults' ((-not $r.Err.Trim()) -and ($r.Out -match 'Needs you\s+Nothing') -and ($r.Out -match 'No report yet')) ($r.Err + $r.Out)
'claude=off' | Set-Content "$C\kit-options.txt"; (Get-Date).AddHours(-5).ToString('o') | Set-Content "$C\selfimprove-last"
$r = Invoke-As $H "$C\status.ps1" @('-NoWait')
Check 'without Claude: no Claude sections (sessions, hidden Claude runs), no errors' ((-not $r.Err.Trim()) -and ($r.Out -notmatch 'Messiah|Claude Code|Session|Self-improvement') -and ($r.Out -match 'Needs you') -and ($r.Out -match 'Scheduled checks')) ($r.Err + $r.Out)

Section 'the app window (dashboard.ps1)'
'Turn EXPO back on in the BIOS.' | Set-Content "$C\maint-todo.txt" -Encoding UTF8
'Checked 9/27/2026 12:00 PM in 18s', '[Drivers]', 'NVIDIA: 617.14 is up to date' | Set-Content "$C\maint-report.txt"
$r = Invoke-As $H "$C\dashboard.ps1" @('-Test')
$d = $r.Out
Check 'without the AI assistant: still "Messiah", no errors' ((-not $r.Err.Trim()) -and ($d -match '(?m)^WINDOW: Messiah\s*$')) ($r.Err + $d)
Check '... tabs: Home, Status, Activity, Settings (no Claude button or card)' ($d -match '(?m)^NAV: Home \| Status \| Activity \| Settings\s*$' -and $d -notmatch 'CARD: Claude\s*$|Ask Claude') $d
Check '... Activity > Trends: a chart per measure; with no history yet it says it is collecting' (($d -match 'CHART: Start-up time \| 0 point') -and ($d -match 'CHART: Free space on C: \|') -and ($d -match 'CHART: Graphics card at idle \|') -and ($d -match 'CHART: SSD temperature \|')) $d
Check '... Activity > Alerts: none yet' ($d -match 'CARD: Alerts\s+: No alerts yet') $d
# with a history, saved reports and alerts
$now = Get-Date
$rows = for ($i = 10; $i -ge 0; $i--) { [ordered]@{ date = $now.AddDays(-$i).ToString('o'); bootAt = $now.AddDays(-$i).AddMinutes(-3).ToString('o'); boot = 26 + ($i % 2); freeGB = 500 - $i; gpuIdle = 30; ssdTemp = 45 } }
ConvertTo-Json -InputObject @($rows) | Set-Content "$C\health-history.json"
New-Item "$C\maint-history" -ItemType Directory -Force | Out-Null
'Checked 9/20/2026 9:00 AM in 30s', '[Periodic]', 'Updated app: Vendor.Tool', 'Tweaks: all still applied' | Set-Content "$C\maint-history\report-20260920-090000.txt"
"$($now.ToString('yyyy-MM-dd')) 10:00|Maintenance started in the background. / The result shows here" | Set-Content "$C\notifications.log" -Encoding UTF8
$r = Invoke-As $H "$C\dashboard.ps1" @('-Test'); $d = $r.Out
Check '... Trends: 11 start-ups charted, now and usual values' (($d -match 'CHART: Start-up time \| 11 points, now 26 s, usual 26\.\d s|CHART: Start-up time \| 11 points, now 26 s, usual 26 s') -and ($d -match 'CHART: Free space on C: \| 11 points, now 500 GB')) $d
Check '... "What maintenance did" lists what changed, not routine lines' (($d -match '(?m)^\s+\S[^\r\n]*: Updated app: Vendor\.Tool') -and ($d -notmatch 'all still applied')) $d
Check '... Alerts: past alerts with their time, and a Clear button' (($d -match 'CARD: Alerts\s+\S+ \S+ \d+, 10:00 AM: Maintenance started in the background') -and ($d -match 'BUTTONS: Clear')) $d
Clear-Path "$C\health-history.json", "$C\maint-history", "$C\notifications.log"
Check '... Home leads with what needs the owner' (($d -match 'PAGE: Home\s+CARD: -\s+1 thing needs you') -and ($d -match 'CARD: Needs you\s+Turn EXPO back on in the BIOS\.\s+ROW BUTTONS: Snooze a week \| Dismiss')) $d
Check '... Home has the main actions' ($d -match 'BUTTONS: Run maintenance now \| Optimize this PC') $d
Check '... Activity > Checks shows the last check and the to-do list; no Claude parts' (($d -match 'PAGE: Activity / Checks\s+CARD: Last background check\s+Checked \S[^\r\n]* \(took 18 s\)') -and ($d -match 'BUTTONS: Run maintenance now \| Full report') -and ($d -match 'CARD: Needs you\s+Turn EXPO back on') -and ($d -notmatch '(?m)CARD: Claude\s*$|Watch live|Claude''s own checks|Ask Claude')) $d
Check '... the schedule as a table; the settings to open at login and for corner alerts' (($d -match 'CARD: Scheduled checks\s+App updates: ') -and ($d -match 'Open Messiah when I log in') -and ($d -match 'Show alerts in the corner / .* Off \(default\): nothing pops up')) $d
Check '... every page and sub-page builds: Home, Status, Activity (Checks, Trends, Alerts), Settings (General, Windows, Tools)' ((@([regex]::Matches($d, '(?m)^PAGE: (Home|Status|Activity / (Checks|Trends|Alerts)|Settings / (General|Windows|Tools))\s*$')).Count -eq 8) -and $d -notmatch 'PAGE ERROR') $d
Check '... Status: never checked yet - each row says so' (($d -match 'PAGE: Status\s+CARD: -\s+Not checked yet') -and ($d -match 'Not checked yet / Telemetry, ads, suggestions and Windows AI off')) $d
# a guard pass's result (tweaks.ps1 -StatusFile): in place, one put back, Windows-protected ones, an opt-in never turned on
'{"at":"' + (Get-Date).ToString('o') + '","preview":false,"cause":"Windows Update (KB5099999)","optIn":["edge-remove","notifications-off","sysmain-off"],"keys":{"telemetry":{"same":57,"fixed":[],"blocked":0,"names":["HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DataCollection\\AllowTelemetry"]},"start-menu":{"same":4,"fixed":["Start_TrackDocs"],"blocked":0},"#Scheduled tasks":{"same":0,"fixed":[],"blocked":3}}}' | Set-Content "$C\tweak-status.json"
$r = Invoke-As $H "$C\dashboard.ps1" @('-Test', '-Page', 'Status'); $d2 = $r.Out
Check '... Status after a guard pass: all green, what was put back, Windows-protected, opt-ins not on' ((-not $r.Err.Trim()) -and ($d2 -match 'PAGE: Status\s+CARD: -\s+All \d+ in place') -and ($d2 -match 'In place \(57\) / Telemetry, ads') -and ($d2 -match 'Put back [^/]+ / Start menu recommendations and Task View off / Something had changed it: Recent files in Start - after Windows Update \(KB5099999\)') -and ($d2 -match 'CARD: Guarded\s+\d+ of \d+ in place') -and ($d2 -match 'Not turned on / Edge removed completely') -and ($d2 -match '3 protected by Windows')) ($r.Err + $d2)
Check '... each row''s details behind a click: what it does, the settings it checks, its last check, a way to change it' (($d2 -match 'Telemetry, ads, suggestions and Windows AI off\s+MORE: What it does  No diagnostic data[^\r\n]*\| Checks 1 setting  Telemetry level \| Last check  [^\r\n]*\| History  Never had to be put back \| \[Change in Settings\]') -and ($d2 -match 'Windows keeps registry backups\s+MORE: What it does  Windows saves copies')) $d2
'tweak.telemetry=off' | Add-Content "$C\kit-options.txt"
$r = Invoke-As $H "$C\dashboard.ps1" @('-Test', '-Page', 'Status'); $d2 = $r.Out
Check '... a switch turned off in Settings shows as the owner''s choice' ($d2 -match 'Off - your choice / Telemetry, ads') $d2
# a crash-hunting mode left on (diag-modes.ps1 - a stand-in here): amber from the start, with its off button; Home's tile says so too
'[pscustomobject]@{ Id = ''verifier''; Name = ''Driver Verifier (18 drivers)''; Since = [datetime]''2026-10-04''; Days = 7 }' | Set-Content "$C\diag-modes.ps1"
$r = Invoke-As $H "$C\dashboard.ps1" @('-Test') @{ PCKIT_DIAG_TEST = '1' }; $d2 = $r.Out
Check '... a crash-hunting mode left on (Driver Verifier): amber with its off button; Home''s tile counts it' ((-not $r.Err.Trim()) -and ($d2 -match 'Driver Verifier \(18 drivers\) on / Crash-hunting modes off / On for 7 days \(since Oct 4\)') -and ($d2 -match 'ROW BUTTONS: Turn off Driver Verifier') -and ($d2 -match 'CARD: Guarded\s+1 needs a look\s+Driver Verifier \(18 drivers\) on - see Status') -and ($d2 -match 'PAGE: Status\s+CARD: -\s+1 needs a look')) ($r.Err + $d2)
Clear-Path "$C\diag-modes.ps1"
Check '... filters on top (All / Needs a look / Put back / Off, with counts)' ($d2 -match 'FILTERS: All  \d+\* \| Needs a look  1 \| Put back  1 \| Off  \d+') $d2
'technames=on' | Add-Content "$C\kit-options.txt"; $r = Invoke-As $H "$C\dashboard.ps1" @('-Test', '-Page', 'Status'); $d2 = $r.Out
Check '... settings in plain words, or by their registry names when chosen (Settings > General)' ($d2 -match 'Checks 1 setting  AllowTelemetry \|') $d2
# Home: a game running (game-check.ps1 - a stand-in name here) and what's new after an update (whats-new.json)
'{"version":"v2026.10.12","date":"' + (Get-Date).ToString('o') + '","points":["Status tab: every optimization at a glance","Search with Ctrl+K"],"url":"https://github.com/x/y/releases/tag/v2026.10.12"}' | Set-Content "$C\whats-new.json"
$r = Invoke-As $H "$C\dashboard.ps1" @('-Test') @{ PCKIT_GAME_TEST = 'Test Game'; PCKIT_REPORT_TEST = '1' }; $d2 = $r.Out
Check 'Home while a game runs: says maintenance waits' ((-not $r.Err.Trim()) -and ($d2 -match 'CARD: Playing Test Game\s+Updates, checks and cleanup wait')) ($r.Err + $d2)
Check 'Home after an update: what''s new, with Got it and the release notes' ($d2 -match "CARD: What's new in Messiah v2026\.10\.12\s+[^\r\n]*Status tab: every optimization at a glance\s+[^\r\n]*Search with Ctrl\+K\s+BUTTONS: Got it \| All release notes") $d2
Check 'the help report: status, what needs the owner and the last check - no PC name' (($d2 -match 'REPORT: Messiah report - ') -and ($d2 -match 'STATUS: ') -and ($d2 -match 'NEEDS THE OWNER: ') -and ($d2 -match 'LAST CHECK:') -and ($d2 -notmatch [regex]::Escape($env:COMPUTERNAME))) $d2
'newsseen=v2026.10.12' | Add-Content "$C\kit-options.txt"; $r = Invoke-As $H "$C\dashboard.ps1" @('-Test'); $d2 = $r.Out
Check '... Got it: the card goes' ($d2 -notmatch "What's new in Messiah") $d2
Clear-Path "$C\whats-new.json"
# Alerts: a "Needs you" alert whose item is no longer on the to-do list moves to "Earlier and resolved"
"$((Get-Date).ToString('yyyy-MM-dd')) 09:00|Needs you (1): Something long settled that nobody needs to do any more" | Add-Content "$C\notifications.log" -Encoding UTF8
$r = Invoke-As $H "$C\dashboard.ps1" @('-Test'); $d2 = $r.Out
Check 'Alerts: a resolved "Needs you" moves to Earlier and resolved' ($d2 -match 'CARD: Earlier and resolved\s+[^\r\n]*Something long settled that nobody needs to do any more  \(resolved\)') $d2
Clear-Path "$C\notifications.log"

Clear-Path "$C\tweak-status.json"
'claude=on' | Set-Content "$C\kit-options.txt"; Clear-Path "$C\maint-todo.txt"
$r = Invoke-As $H "$C\dashboard.ps1" @('-Test') @{ FAKE_DIR = "$Work\fake" }
$d = $r.Out
Check 'with Claude: "Messiah" with the chat (Open chat on Home - no terminal sessions) and the live watch' ((-not $r.Err.Trim()) -and ($d -match '(?m)^WINDOW: Messiah\s*$') -and ($d -match 'CARD: Claude') -and ($d -match 'BUTTONS: Open chat') -and ($d -notmatch 'Show sessions|Hide sessions') -and ($d -match 'CARD: Claude''s own checks') -and ($d -match 'Watch live')) ($r.Err + $d)
Check '... nothing to do: "All good"' ($d -match 'PAGE: Home\s+CARD: -\s+All good - nothing needs you') $d
Check '... Home says what Claude is doing' ($d -match 'CARD: Claude\s+(Chat with Claude right here|Ready - |Working right now)') $d
Finish
