# claude-bg-maint.ps1 in a sandbox home with stub jobs and a stub claude-unattended.ps1.
. "$PSScriptRoot\..\lib.ps1"
$H = "$Work\home"; $C = "$H\.claude"; $trayDir = "$H\Documents\Messiah Tray"
New-Item $C, $trayDir -ItemType Directory -Force | Out-Null
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
function New-Case([hashtable]$Jobs, [string]$Unattended, [switch]$Short) {
    $t = (Get-Content "$Src\claude-bg-maint.ps1" -Raw).Replace("'Global\ClaudeBgMaint'", "'Global\ClaudeBgMaintT$PID'")
    if ($Short) { $t = $t.Replace("Script = 'driver-check.ps1'; Timeout = 1200", "Script = 'driver-check.ps1'; Timeout = 4") }
    Set-Content "$C\claude-bg-maint.ps1" $t
    Copy-Item "$Src\maint-due.ps1" $C -Force
    '' | Set-Content "$C\game-check.ps1"   # never gaming here (game-aware.ps1 tests that)
    foreach ($j in 'driver-check', 'claude-maint', 'health-check', 'periodic-maint') { $(if ($Jobs -and $Jobs.ContainsKey($j)) { $Jobs[$j] } else { "`"$j ok`"" }) | Set-Content "$C\$j.ps1" }
    Clear-Path "$C\kit-update.ps1"; Clear-Path "$C\self-test.ps1"; Clear-Path "$C\kit-updated.txt"
    $u = if ($Unattended) { $Unattended } else { @'
param([string]$Due, [string]$Mode)
$req = if (Test-Path "$PSScriptRoot\maint-requests.txt") { (Get-Content "$PSScriptRoot\maint-requests.txt" -Raw -Encoding UTF8).Trim() }
"ran $Mode due=[$Due] handled-before=$((Get-Content "$PSScriptRoot\maint-state.json" -Raw) -match 'claude-handled-report') request=[$req]" | Add-Content "$PSScriptRoot\runs.log"
if ($Mode -eq 'maintain' -and $req) { [IO.File]::Delete("$PSScriptRoot\maint-requests.txt") }
'@ }
    Set-Content "$C\claude-unattended.ps1" $u
    $now = (Get-Date).ToString('o'); @{ 'claude-quarterly' = $now; 'claude-halfyear' = $now; 'claude-yearly' = $now } | ConvertTo-Json | Set-Content "$C\maint-state.json"
    foreach ($f in 'runs.log', 'maint-requests.txt', 'maint-claude-running', 'selfimprove-last', 'maint-report.txt') { Clear-Path "$C\$f" }
}
$script:gate = $null   # the stand-in suite the self-improve gate runs (only in the gate section)
function Run([string[]]$A = @('-Force', '-Unattended')) { [void](Invoke-As $H "$C\claude-bg-maint.ps1" $A @{ PCKIT_IN_TESTS = '1'; PCKIT_TESTS_DIR = $script:gate }) }
function Runs { @(Get-Content "$C\runs.log" -ErrorAction SilentlyContinue) }

Section 'report'
New-Case -Short -Jobs @{ 'driver-check' = 'Start-Sleep 30; "never seen"'; 'health-check' = '"WARNING: blue screen 0x109"' }
Run @('-Force')
$r = Get-Content "$C\maint-report.txt"
Check 'a hung job is stopped at its limit and reported' (($r -join "`n") -match '\[Drivers\]\s+WARNING: timed out') ($r -join ' / ')
Check 'other jobs still reported' (($r -match 'claude-maint ok') -and ($r -match 'WARNING: blue screen')) ($r -join ' / ')
Check 'a copy kept in maint-history' (@(Get-ChildItem "$C\maint-history" -ErrorAction SilentlyContinue).Count -ge 1) ''
Check 'no half-written temp file left' (-not (Test-Path "$C\maint-report.txt.tmp")) ''
New-Case -Jobs @{ 'periodic-maint' = '' }
Run @('-Force')
Check 'a job with nothing to say leaves no empty section' (-not ((Get-Content "$C\maint-report.txt") -contains '[Periodic]')) ((Get-Content "$C\maint-report.txt") -join ' / ')
New-Case
'Start-Sleep 2; "updated" | Set-Content "$PSScriptRoot\kit-updated.txt"; "PC Setup Kit updated v1 -> v2"' | Set-Content "$C\kit-update.ps1"
'"WARNING: self-test (after the kit update to v2) failed: 1 failed in launcher (kit update seen: $(Test-Path "$PSScriptRoot\kit-updated.txt"))"' | Set-Content "$C\self-test.ps1"
Run
$r = Get-Content "$C\maint-report.txt"
Check 'self-test runs after the jobs (it sees the kit update of the same run)' (($r -join "`n") -match '\[Self-test\]\s+WARNING: self-test .*kit update seen: True') ($r -join ' / ')
Check '... and its WARNING wakes /maintain at the same login' ((Runs) -match 'ran maintain') ((Runs) -join ' / ')
New-Case; '' | Set-Content "$C\self-test.ps1"; Run @('-Force')
Check 'self-test with nothing to say (not due): no section' (-not ((Get-Content "$C\maint-report.txt") -contains '[Self-test]')) ''
New-Case; Run @('-Force'); $t1 = (Get-Item "$C\maint-report.txt").LastWriteTime; Start-Sleep 1; Run @()
Check 'without -Force it skips when the last run was < 30 min ago' ((Get-Item "$C\maint-report.txt").LastWriteTime -eq $t1) ''

Section 'hidden Claude runs'
New-Case -Jobs @{ 'health-check' = '"WARNING: blue screen"' }
Run; $r = Runs
Check 'warning -> /maintain first, then self-improve' ($r.Count -eq 2 -and $r[0] -match '^ran maintain due=\[warnings' -and $r[1] -match '^ran improve') ($r -join ' | ')
Check 'the warning is NOT marked handled before /maintain ran' ($r[0] -match 'handled-before=False') $r[0]
Check '... and IS marked handled after it finished' ((Get-Content "$C\maint-state.json" -Raw) -match 'claude-handled-report') ''
Check 'busy marker removed afterwards' (-not (Test-Path "$C\maint-claude-running")) ''
New-Case
Run; Check 'nothing due: only self-improve' ((Runs) -join '|' -match '^ran improve') ((Runs) -join ' | ')
Clear-Path "$C\runs.log"; Run
Check 'self-improve at most once in 20 h' (@(Runs).Count -eq 0) ((Runs) -join ' | ')
(Get-Item "$C\selfimprove-last").LastWriteTime = (Get-Date).AddHours(-21); Run
Check '... and again after 20 h' ((Runs) -join '|' -match 'ran improve') ((Runs) -join ' | ')

Section 'cut off by a shutdown'
New-Case
@('aaaa-bbbb', 'maintain', $boot.AddMinutes(-10).ToString('o')) | Set-Content "$C\maint-claude-session"
'x' | Set-Content "$C\maint-claude-running"; (Get-Item "$C\maint-claude-running").LastWriteTime = $boot.AddMinutes(-9)
Run; $r = Runs
Check 'a run cut off before this boot is handed to /maintain to finish' ($r[0] -match 'ran maintain' -and $r[0] -match 'was cut off' -and $r[0] -match 'aaaa-bbbb') ($r -join ' | ')
Check 'the one-off request is consumed' (-not (Test-Path "$C\maint-requests.txt")) ''
New-Case -Jobs @{ 'health-check' = '"WARNING: new thing"' } -Unattended @'
param([string]$Due, [string]$Mode)
if ($Mode -eq 'maintain') { Start-Sleep 60 }
'@
$u = $env:USERPROFILE; $env:USERPROFILE = $H
$p = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$C\claude-bg-maint.ps1`"", '-Force', '-Unattended' -WindowStyle Hidden -PassThru
$env:USERPROFILE = $u
Start-Sleep 10; Stop-Tree $p.Id   # the PC goes off in the middle of /maintain
Check 'PC off during /maintain: the warning is still due next login' (-not ((Get-Content "$C\maint-state.json" -Raw) -match 'claude-handled-report')) ''
Check '... and the busy marker stays, so the next login knows it was cut off' (Test-Path "$C\maint-claude-running") ''

Section 'self-improvement safety net'
New-Case -Unattended @'
param([string]$Due, [string]$Mode)
if ($Mode -eq 'improve') {
  'function Broken {' | Set-Content "$PSScriptRoot\health-check.ps1"
  'this is { not valid AHK' | Set-Content "$env:USERPROFILE\Documents\Messiah Tray\Messiah Tray.ahk"
}
'@
Copy-Item $Tray "$trayDir\Messiah Tray.ahk" -Force
Run
Check 'a script broken by self-improve is rolled back' ((Get-Content "$C\health-check.ps1" -Raw) -match 'health-check ok') (Get-Content "$C\health-check.ps1" -Raw)
if (Test-Path "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe") {
    Check 'a tray script broken by self-improve is rolled back' ((Get-Content "$trayDir\Messiah Tray.ahk" -Raw) -match 'Persistent') ''
} else { Skip 'tray rollback' 'AutoHotkey not installed' }
Check 'the rollback is written to the run log' (@(Get-ChildItem "$C\maint-claude-log\*.md" | Select-String 'ROLLED BACK').Count -ge 1) ''
Check 'a code snapshot was taken first' (@(Get-ChildItem "$C\selfimprove-backup" -Directory -ErrorAction SilentlyContinue).Count -ge 1) ''

Section 'self-improvement test gate (a change that parses but breaks behaviour)'
# stand-in test suite where the kit repo would be: fails while health-check.ps1 contains SEMANTIC-BUG
$tdir = "$H\Documents\PC Setup Kit\PCSetupKit\tests"; New-Item $tdir -ItemType Directory -Force | Out-Null
@'
param([string]$Suite, [string]$Src, [string]$TrayFile)
$bad = (Get-Content "$Src\health-check.ps1" -Raw) -match 'SEMANTIC-BUG'
"PC Setup Kit tests (unit): $(if ($bad) { '40 passed, 1 failed' } else { '41 passed, 0 failed' })" | Set-Content "$PSScriptRoot\last-run.txt"
exit [int]$bad
'@ | Set-Content "$tdir\run-tests.ps1"
'original test' | Set-Content "$tdir\some-test.ps1"
$script:gate = $tdir
New-Item "$C\skills\maintain" -ItemType Directory -Force | Out-Null; 'original skill' | Set-Content "$C\skills\maintain\SKILL.md"
New-Case -Unattended @'
param([string]$Due, [string]$Mode)
if ($Mode -eq 'improve') {
  '"health-check ok"; "SEMANTIC-BUG"' | Set-Content "$PSScriptRoot\health-check.ps1"
  '"new helper"' | Set-Content "$PSScriptRoot\new-helper.ps1"
  'changed skill' | Set-Content "$PSScriptRoot\skills\maintain\SKILL.md"
  'weakened test' | Set-Content "$env:USERPROFILE\Documents\PC Setup Kit\PCSetupKit\tests\some-test.ps1"
}
'@
Run
Check 'failing tests: the broken script is restored' ((Get-Content "$C\health-check.ps1" -Raw) -notmatch 'SEMANTIC-BUG') ''
Check '... a file it added is moved out (kept in the snapshot)' (-not (Test-Path "$C\new-helper.ps1") -and @(Get-ChildItem "$C\selfimprove-backup\*\added\new-helper.ps1").Count -ge 1) ''
Check '... a skill it changed is restored' ((Get-Content "$C\skills\maintain\SKILL.md" -Raw) -match 'original skill') ''
Check '... a test it weakened is restored' ((Get-Content "$tdir\some-test.ps1" -Raw) -match 'original test') ''
$lg = (Get-ChildItem "$C\maint-claude-log\*-improve.md" | Sort-Object Name | Select-Object -Last 1 | Get-Content -Raw)
Check '... and the log says why, with the test summary and the result after rollback' ($lg -match 'ROLLED BACK all self-improvement changes.*1 failed' -and $lg -match 'Tests after the rollback: .*0 failed') $lg
New-Case -Unattended @'
param([string]$Due, [string]$Mode)
if ($Mode -eq 'improve') { '"health-check ok"; "a good improvement"' | Set-Content "$PSScriptRoot\health-check.ps1" }
'@
Run
Check 'passing tests: a good change is kept' ((Get-Content "$C\health-check.ps1" -Raw) -match 'a good improvement') ''
$lg = (Get-ChildItem "$C\maint-claude-log\*-improve.md" | Sort-Object Name | Select-Object -Last 1 | Get-Content -Raw)
Check '... and the log records the passing test run' ($lg -match 'Tests after self-improvement: .*0 failed') $lg
$script:gate = $null
New-Case -Unattended @'
param([string]$Due, [string]$Mode)
if ($Mode -eq 'improve') { '"health-check ok"; "SEMANTIC-BUG"' | Set-Content "$PSScriptRoot\health-check.ps1" }
'@
$before = @(Get-ChildItem "$C\maint-claude-log" -Filter '*-tests.txt').Count
Run
Check 'inside a test run the gate never starts the real suite (no suite-in-suite loop)' (@(Get-ChildItem "$C\maint-claude-log" -Filter '*-tests.txt').Count -eq $before) ''
Finish
