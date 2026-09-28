# Launcher (claude-admin-launch.ps1), due check (maint-due.ps1) and resume-after-restart.ps1 in a sandbox home with a
# fake claude.exe that records how it was started: manual/autostart, resume after a shutdown, mid-task detection, edge cases.
. "$PSScriptRoot\..\lib.ps1"
$sb = $Work
$home2 = "$sb\home"; $cl = "$home2\.claude"; $proj = "$cl\projects\C--WINDOWS-system32"
$real = $Src
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
New-Item "$home2\.local\bin", $proj -ItemType Directory -Force | Out-Null
Copy-Item (Get-FakeClaude) "$home2\.local\bin\claude.exe" -Force

function Reset([hashtable]$state, [string[]]$report, [string[]]$todo) {
    # the previous launch's fire-and-forget bg-maint stand-in may still be starting (it holds its script open): let it finish
    $w = [Diagnostics.Stopwatch]::StartNew()
    while ($w.Elapsed.TotalSeconds -lt 10 -and (Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*$cl\claude-bg-maint.ps1*" })) { Start-Sleep -Milliseconds 100 }
    Get-ChildItem $cl -File | Remove-Item -Force
    Get-ChildItem $proj -File | Remove-Item -Force
    Copy-Item "$real\claude-admin-launch.ps1", "$real\maint-due.ps1", "$real\resume-after-restart.ps1", "$real\session-lib.ps1" $cl
    # the stub records WHICH launch started it: a late one from an earlier launch must not count for the next
    '$env:PCKIT_LAUNCH_TOKEN | Set-Content "$PSScriptRoot\bgmaint-was-kicked"' | Set-Content "$cl\claude-bg-maint.ps1"
    $now = (Get-Date).ToString('o')
    $s = @{ 'claude-quarterly' = $now; 'claude-halfyear' = $now; 'claude-yearly' = $now }
    if ($state) { foreach ($k in $state.Keys) { if ($null -eq $state[$k]) { $s.Remove($k) } else { $s[$k] = $state[$k] } } }
    $s | ConvertTo-Json | Set-Content "$cl\maint-state.json" -Encoding utf8
    if ($report) { $report | Set-Content "$cl\maint-report.txt" -Encoding utf8 }
    if ($todo) { $todo | Set-Content "$cl\maint-todo.txt" -Encoding utf8 }
}
function Transcript($id, [datetime]$when) { $f = "$proj\$id.jsonl"; '{}' | Set-Content $f; (Get-Item $f).LastWriteTime = $when; $f }

# Runs the launcher like the tray (-Auto) or the Start menu shortcut; returns the fake claude's recorded args
function Launch([switch]$Auto, [string[]]$LaunchArgs) {
    $log = "$sb\fake.log"; Remove-Item $log -ErrorAction SilentlyContinue
    $psi = New-Object Diagnostics.ProcessStartInfo 'powershell.exe'
    $a = '-NoProfile -NoLogo -ExecutionPolicy Bypass -File "' + "$cl\claude-admin-launch.ps1" + '"'
    foreach ($x in $LaunchArgs) { $a += ' "' + $x + '"' }
    $psi.Arguments = $a; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['USERPROFILE'] = $home2; $psi.EnvironmentVariables['FAKE_LOG'] = $log
    $token = [guid]::NewGuid().ToString(); $psi.EnvironmentVariables['PCKIT_LAUNCH_TOKEN'] = $token
    if ($Auto) { $psi.EnvironmentVariables['CLAUDE_ADMIN_AUTOSTART'] = '1' } else { $psi.EnvironmentVariables.Remove('CLAUDE_ADMIN_AUTOSTART') }
    $p = [Diagnostics.Process]::Start($psi); $out = $p.StandardOutput.ReadToEnd(); $err = $p.StandardError.ReadToEnd(); [void]$p.WaitForExit(30000)
    $r = [pscustomobject]@{ Args = @(); Env = $null; Out = $out; Err = $err }
    # bg-maint is fire-and-forget: its marker can appear a moment later - only the checks that ask wait for it (up to 2 s)
    $r | Add-Member NoteProperty Token $token
    $r | Add-Member ScriptProperty Kicked { $m = "$cl\bgmaint-was-kicked"; $w = [Diagnostics.Stopwatch]::StartNew()
        while (-not ((Test-Path $m) -and (Get-Content $m -ErrorAction SilentlyContinue) -eq $this.Token) -and $w.ElapsedMilliseconds -lt 3000) { Start-Sleep -Milliseconds 50 }
        (Test-Path $m) -and (Get-Content $m -ErrorAction SilentlyContinue) -eq $this.Token }
    if (Test-Path $log) { $l = Get-Content $log -Encoding UTF8; $r.Args = @($l | ? { $_ -like 'ARG=*' } | % { $_.Substring(4) }); $r.Env = ($l | ? { $_ -like 'AUTOSTART_ENV=*' }).Substring(14) }
    $r
}
function Has($r, $flag) { $r.Args -contains $flag }
function After($r, $flag) { $i = [array]::IndexOf($r.Args, $flag); if ($i -ge 0 -and $i + 1 -lt $r.Args.Count) { $r.Args[$i + 1] } }
function Sessions { @(Get-Content "$cl\admin-sessions.txt" -ErrorAction SilentlyContinue) }

Write-Host "`n== Launcher: manual (Start menu / tray click) ==" -ForegroundColor Cyan
Reset
$r = Launch
Check 'manual, nothing due: fresh --session-id' ((Has $r '--session-id') -and -not (Has $r '--resume')) ($r.Args -join ' ')
Check 'manual: session id recorded' ((Sessions) -contains (After $r '--session-id')) ((Sessions) -join ',')
Check 'manual: kicks bg-maint' $r.Kicked
Check 'manual: no stderr' (-not $r.Err.Trim()) $r.Err
Check 'claude does not inherit AUTOSTART env' (-not $r.Env) $r.Env

Reset -state @{ 'claude-quarterly' = (Get-Date).AddDays(-91).ToString('o') }
$r = Launch
Check 'manual, quarterly due: /maintain prompt' ($r.Args | ? { $_ -like '/maintain Due now: quarterly check*' }) ($r.Args -join ' | ')

Reset -todo 'Do the thing'
$r = Launch
Check 'manual, new to-do: walkthrough prompt' ($r.Args | ? { $_ -like '/maintain The owner just opened*' }) ($r.Args -join ' | ')
$r = Launch
Check 'manual, same to-do second time: no prompt' (-not ($r.Args | ? { $_ -like '/maintain*' })) ($r.Args -join ' | ')

Reset
$r = Launch -LaunchArgs '--continue', 'hello'
Check 'manual --continue: no --session-id added' (-not (Has $r '--session-id') -and (Has $r '--continue') -and (Has $r 'hello')) ($r.Args -join ' ')

Reset
$r = Launch -LaunchArgs '--resume', 'abc-123'
Check 'manual --resume id: recorded' ((Sessions) -contains 'abc-123') ((Sessions) -join ',')

Reset
1..25 | % { [guid]::NewGuid() } | Set-Content "$cl\admin-sessions.txt"
$r = Launch
Check 'sessions list capped at 20, newest last' ((Sessions).Count -eq 20 -and (Sessions)[-1] -eq (After $r '--session-id')) "count $((Sessions).Count)"

Write-Host "`n== Launcher: autostart (tray at login) ==" -ForegroundColor Cyan
Reset -state @{ 'claude-quarterly' = (Get-Date).AddDays(-91).ToString('o') } -report 'Checked x', 'WARNING: y' -todo 'Do the thing'
$r = Launch -Auto
Check 'autostart, maintenance due + todo: NO /maintain' (-not ($r.Args | ? { $_ -like '/maintain*' })) ($r.Args -join ' | ')
Check 'autostart: does not kick bg-maint' (-not $r.Kicked)
Check 'autostart: does not mark report handled' (-not ((Get-Content "$cl\maint-state.json" -Raw) -match 'claude-handled-report'))
Check 'autostart, no recent session: fresh' ((Has $r '--session-id') -and -not (Has $r '--resume')) ($r.Args -join ' ')

Reset
$id = [guid]::NewGuid().ToString(); $id | Set-Content "$cl\admin-sessions.txt"; Transcript $id $boot.AddMinutes(-2) | Out-Null
$r = Launch -Auto
Check 'autostart, session active 2 min before boot: resumed' ((After $r '--resume') -eq $id -and -not (Has $r '--session-id')) ($r.Args -join ' ')
Check 'autostart resume: no prompt sent (idle, no tokens)' ($r.Args.Count -eq 9) ($r.Args -join ' ')

Reset
$id = [guid]::NewGuid().ToString(); $id | Set-Content "$cl\admin-sessions.txt"; Transcript $id $boot.AddMinutes(-45) | Out-Null
# pin a clean shutdown 1 min before boot (the real last log can be much older - e.g. after a power cut)
"boot=$($boot.ToString('o'))", "shutdown=$($boot.AddMinutes(-1).ToString('o'))" | Set-Content "$cl\rehearsal.txt"
$r = Launch -Auto; Clear-Path "$cl\rehearsal.txt"
Check 'autostart, session 45 min before boot: fresh' (-not (Has $r '--resume')) ($r.Args -join ' ')

Reset
$id = [guid]::NewGuid().ToString(); $id | Set-Content "$cl\admin-sessions.txt"; Transcript $id (Get-Date) | Out-Null
$r = Launch -Auto
Check 'autostart, session written AFTER boot (tray restarted mid-day): fresh' (-not (Has $r '--resume')) ($r.Args -join ' ')

Reset
$a = [guid]::NewGuid().ToString(); $b = [guid]::NewGuid().ToString(); $a, $b | Set-Content "$cl\admin-sessions.txt"
Transcript $a $boot.AddMinutes(-1) | Out-Null; Transcript $b $boot.AddMinutes(-20) | Out-Null
$r = Launch -Auto
Check 'autostart, two sessions: resumes the most recently active' ((After $r '--resume') -eq $a) ($r.Args -join ' ')

Reset
'00000000-dead-beef-0000-000000000000' | Set-Content "$cl\admin-sessions.txt"
$r = Launch -Auto
Check 'autostart, listed session has no transcript: fresh' (-not (Has $r '--resume')) ($r.Args -join ' ')

Write-Host "`n== resume-after-restart -> autostart ==" -ForegroundColor Cyan
Reset
$id = [guid]::NewGuid().ToString(); Transcript $id (Get-Date) | Out-Null
$prompt = "Verify the ""25H2"" upgrade's result`tthen report - café ✓"
$sidBefore = $env:CLAUDE_CODE_SESSION_ID; $env:CLAUDE_CODE_SESSION_ID = $id
$hadTray = [bool](Get-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue)
$u = $env:USERPROFILE; $env:USERPROFILE = $home2; $o = & "$cl\resume-after-restart.ps1" -Prompt $prompt 2>&1; $env:USERPROFILE = $u
$env:CLAUDE_CODE_SESSION_ID = $sidBefore
if ($hadTray) { Check 'resume script: tray PC - uses the tray, no task registered' (("$o" -match 'tray') -and -not (Get-ScheduledTask 'Claude Resume After Restart' -ErrorAction SilentlyContinue)) "$o" }
else {   # a PC without the tray: falls back to a one-time logon task (removed again here)
    Check 'resume script: no tray - registers the one-time logon task' ([bool](Get-ScheduledTask 'Claude Resume After Restart' -ErrorAction SilentlyContinue)) "$o"
    Unregister-ScheduledTask 'Claude Resume After Restart' -Confirm:$false -ErrorAction SilentlyContinue
}
Check 'resume file written' (Test-Path "$cl\resume-after-login.txt")
$r = Launch -Auto
Check 'autostart consumes resume file: --resume <that session>' ((After $r '--resume') -eq $id) ($r.Args -join ' ')
Check 'resume prompt passed intact (quotes/unicode, tab flattened)' ($r.Args[-1] -eq "Verify the 25H2 upgrades result then report - café ✓") "got: [$($r.Args[-1])]"
Check 'resume file deleted after use' (-not (Test-Path "$cl\resume-after-login.txt"))
Check 'resumed id recorded for next time' ((Sessions) -contains $id)

Reset
"nonexistent-id`tdo stuff" | Set-Content "$cl\resume-after-login.txt"
$r = Launch -Auto
Check 'resume file with unknown session: fresh, file removed' (-not (Has $r '--resume') -and -not (Test-Path "$cl\resume-after-login.txt")) ($r.Args -join ' ')

Reset
$id = [guid]::NewGuid().ToString(); Transcript $id (Get-Date) | Out-Null
"$id`tdo stuff" | Set-Content "$cl\resume-after-login.txt"
$r = Launch
Check 'manual launch leaves a pending resume file alone' ((Test-Path "$cl\resume-after-login.txt") -and -not (Has $r '--resume'))

Reset
$id = [guid]::NewGuid().ToString(); Transcript $id (Get-Date).AddDays(-3) | Out-Null
"$id`tcheck the upgrade" | Set-Content "$cl\resume-after-login.txt"; (Get-Item "$cl\resume-after-login.txt").LastWriteTime = (Get-Date).AddDays(-3)
$r = Launch -Auto
Check 'stale resume request (3 days old) is not replayed' (-not (Has $r '--resume')) ($r.Args -join ' ')

Write-Host "`n== maint-due edge cases ==" -ForegroundColor Cyan
function Due([switch]$Mark) { @(& powershell -NoProfile -ExecutionPolicy Bypass -File "$cl\maint-due.ps1" $(if ($Mark) { '-MarkHandled' }) 2>&1) }
Reset; Check 'fresh state: nothing due' ((Due).Count -eq 0) ((Due) -join ',')
Reset; Remove-Item "$cl\maint-state.json"; $d = Due; Check 'no state file: 3 periodic checks due' ($d.Count -eq 3) ($d -join ',')
Reset; '' | Set-Content "$cl\maint-state.json"; $d = Due; Check 'empty state file: no error, all due' ($d.Count -eq 3 -and -not ($d | ? { $_ -is [Management.Automation.ErrorRecord] })) ($d -join ',')
Reset; '{"claude-quarterly": "2026-09' | Set-Content "$cl\maint-state.json"; $d = Due; Check 'corrupt state file: no error, all due' ($d.Count -eq 3 -and -not ($d | ? { $_ -is [Management.Automation.ErrorRecord] })) ($d -join ',')
Reset -state @{ 'claude-yearly' = 'garbage' }; $d = Due; Check 'unparseable date: treated as due, no error' (($d -contains 'yearly re-audit') -and -not ($d | ? { $_ -is [Management.Automation.ErrorRecord] })) ($d -join ',')
Reset -report 'Checked A', 'WARNING: x'
$d1 = Due -Mark; $d2 = Due
Check 'report warning: due once, then handled' (($d1 -contains 'warnings in the maintenance report') -and $d2.Count -eq 0) "1st: $($d1 -join ','); 2nd: $($d2 -join ',')"
Check 'MarkHandled keeps other keys' ((Get-Content "$cl\maint-state.json" -Raw) -match 'claude-quarterly')
Reset -state @{ 'claude-handled-report' = @{ value = 'Checked A'; PSPath = 'x' } } -report 'Checked A', 'FAILED: x'
Check 'handled saved as Get-Content object still matches' ((Due).Count -eq 0) ((Due) -join ',')
Reset -report 'Checked A', 'Claude Code: got no response in 45 s, skipped'
Check "'got no response' does not trigger /maintain" ((Due).Count -eq 0) ((Due) -join ',')

Write-Host "`n== Turned off mid-task -> resumed and continued ==" -ForegroundColor Cyan
# when the PC went down = the last System event before this boot (same rule as the launcher)
$down = Get-WinEvent -FilterHashtable @{ LogName = 'System'; EndTime = $boot } -MaxEvents 1 -ErrorAction SilentlyContinue | ForEach-Object TimeCreated
if (-not $down -or ($boot - $down).TotalHours -gt 12) { $down = $boot.AddSeconds(-30) }   # e.g. a CI machine booted from an old image
Write-Host "  (last shutdown $down, boot $boot)"
$rec = @{
    done      = @('{"type":"user","message":{"role":"user","content":"fix it"}}', '{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"Done."}]}}', '{"type":"system","subtype":"turn_duration"}')
    endturn   = @('{"type":"user","message":{"role":"user","content":"hi"}}', '{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"Hi"}]}}', '{"type":"attachment"}')
    tooluse   = @('{"type":"user","message":{"role":"user","content":"fix it"}}', '{"type":"assistant","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","name":"PowerShell"}]}}')
    toolres   = @('{"type":"assistant","message":{"stop_reason":"tool_use","content":[{"type":"tool_use"}]}}', '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}', '{"type":"attachment"}')
    unanswered = @('{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"Hi"}]}}', '{"type":"system","subtype":"turn_duration"}', '{"type":"user","message":{"role":"user","content":"now update drivers"}}')
    slashexit = @('{"type":"system","subtype":"turn_duration"}', '{"type":"user","message":{"role":"user","content":"<command-name>/exit</command-name>"}}', '{"type":"user","message":{"role":"user","content":"<local-command-stdout>Bye!</local-command-stdout>"}}')
    garbage   = @('not json {{{', '')
}
$expectMid = @{ done = $false; endturn = $false; tooluse = $true; toolres = $true; unanswered = $true; slashexit = $false; garbage = $false }
foreach ($k in $rec.Keys) {
    Reset
    $id = [guid]::NewGuid().ToString(); $id | Set-Content "$cl\admin-sessions.txt"
    $f = "$proj\$id.jsonl"; [IO.File]::WriteAllLines($f, [string[]]$rec[$k]); (Get-Item $f).LastWriteTime = $down.AddMinutes(-1)
    $r = Launch -Auto
    $cont = [bool]($r.Args | Where-Object { $_ -like 'The PC was turned off while*' })
    Check "transcript '$k': resumed, continue prompt = $($expectMid[$k])" (((After $r '--resume') -eq $id) -and $cont -eq $expectMid[$k]) ($r.Args -join ' | ')
}
Reset
$id = [guid]::NewGuid().ToString(); $id | Set-Content "$cl\admin-sessions.txt"; Transcript $id $down.AddMinutes(-20) | Out-Null
$r = Launch -Auto
Check 'active 20 min before SHUTDOWN (window counts from shutdown, not boot): resumed' ((After $r '--resume') -eq $id) ($r.Args -join ' ')
Reset
$id = [guid]::NewGuid().ToString(); $id | Set-Content "$cl\admin-sessions.txt"; Transcript $id $down.AddMinutes(-40) | Out-Null
$r = Launch -Auto
Check 'active 40 min before shutdown: fresh session instead' (-not (Has $r '--resume')) ($r.Args -join ' ')

Write-Host "`n== the last logged shutdown is older than the conversation (crash, power cut, old image) ==" -ForegroundColor Cyan
$realDown = Get-WinEvent -FilterHashtable @{ LogName = 'System'; EndTime = $boot } -MaxEvents 1 -ErrorAction SilentlyContinue | ForEach-Object TimeCreated
if ($realDown -and ($boot - $realDown).TotalMinutes -gt 50) {   # this machine's last log before boot is old (like a CI runner)
    Reset; $id = [guid]::NewGuid().ToString(); $id | Set-Content "$cl\admin-sessions.txt"; Transcript $id $boot.AddMinutes(-45) | Out-Null
    $r = Launch -Auto
    Check 'conversation 45 min before boot, written after the old log: boot time is used -> fresh' (-not (Has $r '--resume')) ($r.Args -join ' ')
} else {
    Reset; $id = [guid]::NewGuid().ToString(); $id | Set-Content "$cl\admin-sessions.txt"; Transcript $id $boot.AddMinutes(-2) | Out-Null
    "boot=$($boot.ToString('o'))", "shutdown=$($boot.AddDays(-3).ToString('o'))" | Set-Content "$cl\rehearsal.txt"
    $r = Launch -Auto
    Check 'last shutdown 3 days ago, conversation 2 min before boot (crash): resumed via boot time' ((After $r '--resume') -eq $id) ($r.Args -join ' ')
    Reset; $id = [guid]::NewGuid().ToString(); $id | Set-Content "$cl\admin-sessions.txt"; Transcript $id $boot.AddMinutes(-45) | Out-Null
    "boot=$($boot.ToString('o'))", "shutdown=$($boot.AddDays(-3).ToString('o'))" | Set-Content "$cl\rehearsal.txt"
    $r = Launch -Auto
    Check 'last shutdown 3 days ago, conversation 45 min before boot: not treated as recent -> fresh' (-not (Has $r '--resume')) ($r.Args -join ' ')
    Clear-Path "$cl\rehearsal.txt"
}
Reset
'x' | Set-Content "$cl\maint-claude-running"; (Get-Item "$cl\maint-claude-running").LastWriteTime = $boot.AddMinutes(-5)
Reset -state @{ 'claude-quarterly' = (Get-Date).AddDays(-91).ToString('o') }
'x' | Set-Content "$cl\maint-claude-running"; (Get-Item "$cl\maint-claude-running").LastWriteTime = $boot.AddMinutes(-5)
$r = Launch
Check 'stale "hidden run busy" marker from before shutdown is ignored (manual launch still handles due work)' ($r.Args | ? { $_ -like '/maintain Due now*' }) ($r.Args -join ' | ')

Write-Host "`n== never resume a conversation another Claude has open ==" -ForegroundColor Cyan
$sleeper = Get-SleeperClaude
Reset
$id = [guid]::NewGuid().ToString(); $id | Set-Content "$cl\admin-sessions.txt"; Transcript $id $down.AddMinutes(-2) | Out-Null
$holder = Start-Process $sleeper -ArgumentList '--resume', $id -WindowStyle Hidden -PassThru; Start-Sleep 1
$r = Launch -Auto
Check 'conversation open in another claude.exe: not resumed (fresh instead)' (-not (Has $r '--resume')) ($r.Args -join ' ')
Stop-Process -Id $holder.Id -Force; Start-Sleep 1
$r = Launch -Auto
Check '... and once that process is gone, it is resumed as usual' ((After $r '--resume') -eq $id) ($r.Args -join ' ')

Finish
