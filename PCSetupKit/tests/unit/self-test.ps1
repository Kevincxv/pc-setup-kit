# self-test.ps1 (the weekly / after-update run of this suite on each PC) in a sandbox home, with a stand-in suite
# that passes, fails or hangs on request - the real suite never runs inside itself.
. "$PSScriptRoot\..\lib.ps1"
$H = "$Work\home"; $C = "$H\.claude"; $K = "$Work\kit"; $S = "$Work\suite"
New-Item $C, $K, $S, "$H\Documents\Messiah Tray" -ItemType Directory -Force | Out-Null
Copy-Item "$Src\self-test.ps1" $C
'x' | Set-Content "$H\Documents\Messiah Tray\Messiah Tray.ahk"
'if (Test-Path "$PSScriptRoot\game.txt") { Get-Content "$PSScriptRoot\game.txt" }' | Set-Content "$C\game-check.ps1"
@'
param([string]$Suite, [string]$Src, [string]$TrayFile)
"$Suite|$Src|$TrayFile" | Add-Content "$PSScriptRoot\calls.txt"
$mode = if (Test-Path "$PSScriptRoot\mode.txt") { (Get-Content "$PSScriptRoot\mode.txt").Trim() } else { 'pass' }
if ($mode -eq 'hang') { Start-Sleep 60 }
$f = if ($mode -eq 'fail') { 3 } else { 0 }
Write-Host "PC Setup Kit tests ($Suite) 9/27/2026 2:00 PM in 5s: 40 passed, $f failed, 1 skipped"
Write-Host '  launcher                 30 passed   0 failed   0 skipped     3s'
Write-Host "  restart-check            10 passed   $(if ($f) { 2 } else { 0 }) failed   0 skipped     1s"
Write-Host "  tray-logic                0 passed   $(if ($f) { 1 } else { 0 }) failed   1 skipped     1s"
exit [int]($f -gt 0)
'@ | Set-Content "$S\run-tests.ps1"
function Mode($m) { $m | Set-Content "$S\mode.txt" }
function Run([string[]]$A = @(), [hashtable]$E = @{ PCKIT_TESTS_DIR = $S }) {
    $r = Invoke-As $H "$C\self-test.ps1" (@('-KitDir', $K) + $A) ($E + @{ PCKIT_IN_TESTS = '1' })
    @($r.Out -split "`r?`n" | Where-Object { $_.Trim() })
}
function Calls { @(Get-Content "$S\calls.txt" -ErrorAction SilentlyContinue) }
function State { Get-Content "$C\self-test.json" -Raw | ConvertFrom-Json }
'v2026.09.27.4' | Set-Content "$K\kit-version.txt"

Section 'when it runs'
Mode pass; $o = @(Run)
Check 'first run: runs the unit suite and says so in one line' ($o.Count -eq 1 -and $o[0] -eq 'Self-test (first run): 40 passed, 0 failed') ($o -join ' / ')
# compared by what the paths point at (a temp folder can be spelled short, RUNNER~1, or long - seen on GitHub's runner)
$call = @(Calls)[-1] -split '\|'
Check '... against this PC''s installed scripts and tray' ($call[0] -eq 'unit' -and (Test-Path "$($call[1])\self-test.ps1") -and (Test-Path $call[2]) -and $call[2] -like '*\Documents\Messiah Tray\Messiah Tray.ahk') ((Calls) -join ' / ')
Check '... result recorded' ((State).ok -eq $true -and (State).kit -eq 'v2026.09.27.4') (Get-Content "$C\self-test.json" -Raw)
Check '... full output kept for Claude' ((Get-Content "$C\self-test.log" -Raw) -match 'restart-check') ''
$n = @(Calls).Count; $o = @(Run)
Check 'ran recently, same kit version: nothing (no run, no output)' ($o.Count -eq 0 -and @(Calls).Count -eq $n) ($o -join ' / ')
'v2026.10.02' | Set-Content "$K\kit-version.txt"; $o = @(Run)
Check 'the kit was updated: runs again' ($o -eq 'Self-test (after the kit update to v2026.10.02): 40 passed, 0 failed') ($o -join ' / ')
$st = State; $st.date = (Get-Date).AddDays(-8).ToString('o'); $st | ConvertTo-Json | Set-Content "$C\self-test.json"; $o = @(Run)
Check 'a week later: runs again' ($o -eq 'Self-test (weekly): 40 passed, 0 failed') ($o -join ' / ')
'{ broken' | Set-Content "$C\self-test.json"; $o = @(Run)
Check 'unreadable result file: runs (counts as never run)' ($o -match 'Self-test \(first run\)') ($o -join ' / ')

Section 'failures become a WARNING (so /maintain fixes them)'
Mode fail; $o = @(Run @('-Force'))
Check 'failing tests: WARNING naming the failing test files and the log' ($o.Count -eq 1 -and $o[0] -match '^WARNING: self-test \(requested\) failed: 40 passed, 3 failed in restart-check, tray-logic \(log: .*self-test\.log\)$') ($o -join ' / ')
Check '... recorded as failed' ((State).ok -eq $false -and ((State).failed -join ',') -eq 'restart-check,tray-logic') ''
Mode hang; $o = @(Run @('-Force', '-Minutes', '0.1'))
Check 'a hanging test: stopped at the limit, WARNING' ($o -match '^WARNING: self-test .*stopped after 0.1 min') ($o -join ' / ')
Mode pass; $o = @(Run @('-Force'))
Check 'after the fix: -Force confirms it passes' ($o -eq 'Self-test (requested): 40 passed, 0 failed' -and (State).ok) ($o -join ' / ')

Section 'never in the way'
Clear-Path "$C\self-test.json"; 'NBA2K17.exe' | Set-Content "$C\game.txt"; $n = @(Calls).Count; $o = @(Run)
Check 'a game is running: held, no run, no WARNING' ($o -eq 'Self-test held: NBA2K17.exe is running (next login)' -and @(Calls).Count -eq $n) ($o -join ' / ')
Clear-Path "$C\game.txt"
$o = @(Run @() @{ PCKIT_TESTS_DIR = $null })
Check 'inside a test run without a stand-in suite: does nothing (no suite-in-suite)' ($o.Count -eq 0 -and @(Calls).Count -eq $n) ($o -join ' / ')
Finish
