# The windows the tray menu opens: "Watch maintenance live" (maint-watch.ps1) and "Status" (status.ps1), in a sandbox home.
. "$PSScriptRoot\..\lib.ps1"
$H = "$Work\home"; $C = "$H\.claude"; $P = "$C\projects\C--WINDOWS-system32"
New-Item $P, "$C\maint-claude-log", "$H\.local\bin" -ItemType Directory -Force | Out-Null
Copy-Item "$Src\maint-watch.ps1", "$Src\status.ps1", "$Src\session-lib.ps1", "$Src\ai-enabled.ps1" $C; 'claude=on' | Set-Content "$C\kit-options.txt"
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
Finish
