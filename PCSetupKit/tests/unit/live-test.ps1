# live-test.ps1: the weekly live self-test - only while nobody uses the PC (30+ min idle), with the AI assistant on, a
# week after the last one, never under a game, a busy chat or a hidden maintenance run; a failure goes to /maintain
# (maint-requests.txt). A stand-in live suite - no real tray, session or Claude is touched.
. "$PSScriptRoot\..\lib.ps1"
$lt = "$Src\live-test.ps1"
if (-not (Test-Path $lt)) { Skip 'live-test' 'not installed here'; Finish }
$D = "$Work\claude"; $S = "$Work\suite"; New-Item "$D\chat", "$S\live" -ItemType Directory -Force | Out-Null
Set-Content "$S\run-tests.ps1" @'
param($Suite, $Src, $TrayFile)
Add-Content "$env:LT_LOG" "ran $Suite"
if ($env:LT_FAIL) { "  tray-x                   3 passed   1 failed   0 skipped     1s"; "PC Setup Kit tests (live) now in 1s: 3 passed, 1 failed, 0 skipped"; exit 1 }
"PC Setup Kit tests (live) now in 1s: 4 passed, 0 failed, 0 skipped"; exit 0
'@
$env:LT_LOG = "$Work\ran.log"
function LT([hashtable]$p) { $p.Tests = $S; $p.Dir = $D; if (-not $p.ContainsKey('IdleMinutes')) { $p.IdleMinutes = 45 }; if (-not $p.GameCheck) { $p.GameCheck = { $null } }; @(& $lt @p) }
function Ran { @(Get-Content $env:LT_LOG -ErrorAction SilentlyContinue).Count }
function Fresh { Clear-Path "$D\live-test.json"; Clear-Path $env:LT_LOG; Clear-Path "$D\maint-requests.txt" }

Section 'when it runs'
Set-Content "$D\kit-options.txt" 'claude=off'; Fresh
[void](LT @{}); Check 'the AI assistant off: never' ((Ran) -eq 0) ''
Set-Content "$D\kit-options.txt" 'claude=on'
[void](LT @{ IdleMinutes = 5 }); Check 'someone using the PC (5 min idle): not now' ((Ran) -eq 0) ''
[void](LT @{ GameCheck = { 'NBA 2K17' } }); Check 'a game running: not now' ((Ran) -eq 0) ''
'{"pid":' + $PID + ',"busy":true}' | Set-Content "$D\chat\state.json"
[void](LT @{}); Check 'a chat Claude is working in: not now' ((Ran) -eq 0) ''
Clear-Path "$D\chat\state.json"
$o = LT @{}
Check 'idle, nothing going on: the live suite runs, the result said and kept' ((Ran) -eq 1 -and ($o -join ' ') -match '^Live self-test: 4 passed, 0 failed' -and (Get-Content "$D\live-test.json" -Raw | ConvertFrom-Json).ok) ($o -join ' / ')
[void](LT @{}); Check 'once a week: not again the next time' ((Ran) -eq 1) ''
$o = LT @{ Force = $true; IdleMinutes = 0 }; Check '-Force: now, whatever the conditions' ((Ran) -eq 2) ''

Section 'a failure'
Fresh; $env:LT_FAIL = '1'; $o = LT @{}; $env:LT_FAIL = $null
Check 'a WARNING naming the test file' (($o -join ' ') -match '^WARNING: live self-test failed: 3 passed, 1 failed in tray-x') ($o -join ' / ')
Check '... and handed to /maintain (maint-requests.txt) for the next login' ((Get-Content "$D\maint-requests.txt" -Raw) -match 'weekly live self-test .* failed: 3 passed, 1 failed in tray-x') ''
Finish
