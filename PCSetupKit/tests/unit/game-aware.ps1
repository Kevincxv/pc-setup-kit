# Game-aware maintenance: heavy work waits while a game runs (a stub game-check says "TestGame").
. "$PSScriptRoot\..\lib.ps1"
$stub = @'
$f = "$PSScriptRoot\gamecalls.txt"; $n = [int](Get-Content $f -ErrorAction SilentlyContinue); Add-Content "$PSScriptRoot\gamechecks.log" 'x'
if ($n -ne 0) { if ($n -gt 0) { $n - 1 | Set-Content $f }; 'TestGame' }
'@
Section 'game-check.ps1 itself'
$o = & "$Src\game-check.ps1" -Explain -NoLearn 2>&1
Check 'runs without errors and explains its answer' (-not ($o | Where-Object { $_ -is [Management.Automation.ErrorRecord] }) -and "$o" -match 'fullscreen|game|foreground') "$o"
$gl = "$Work\gc"; New-Item $gl -ItemType Directory -Force | Out-Null; Copy-Item "$Src\game-check.ps1" $gl
'ThisGameDoesNotRun123    # test' | Set-Content "$gl\games.txt"
$o = & "$gl\game-check.ps1" -Explain -NoLearn
Check 'a listed game that is not running is not reported' ("$o" -notmatch 'ThisGameDoesNotRun123') "$o"
# a new PC has no games.txt yet: Get-Process -Name @() is an error, which stopped the whole optimize step in the
# Windows Sandbox test (9/28) - run the way a caller's try block sees it
[IO.File]::Delete("$gl\games.txt")
$err = & { $ErrorActionPreference = 'Stop'; try { [void](& "$gl\game-check.ps1" -NoLearn); '' } catch { "$_" } }
Check 'no games list yet (a new PC): no error, even under -ErrorAction Stop' (-not $err) $err
"$((Get-Process -Id $PID).ProcessName)    # test: this PowerShell counts as a game" | Set-Content "$gl\games.txt"
$o = & "$gl\game-check.ps1" -Explain -NoLearn
if ("$o" -match 'fullscreen') { Skip 'a listed game running in the background is reported' "something is fullscreen right now ($o), which correctly wins" }
else { Check 'a listed game running in the background is reported' ("$o" -match 'known game running') "$o" }
# a game never seen fullscreen, running from a Steam library folder (a copy of ping.exe stands in for it)
'' | Set-Content "$gl\games.txt"
$fake = "$Work\Steam\steamapps\common\FakeGame"; New-Item $fake -ItemType Directory -Force | Out-Null; Copy-Item "$env:SystemRoot\System32\PING.EXE" "$fake\FakeGame123.exe"
$fp = Start-Process "$fake\FakeGame123.exe" -ArgumentList '-n', '30', '127.0.0.1' -WindowStyle Hidden -PassThru; Start-Sleep -Milliseconds 500
$o = & "$gl\game-check.ps1" -Explain -NoLearn
if ("$o" -match 'fullscreen') { Skip 'a game running from a game library folder is reported' "something is fullscreen right now ($o)" }
else { Check 'a game running from a game library folder is reported' ("$o" -match '^FakeGame123 - running from a game library') "$o" }
Stop-Process -Id $fp.Id -Force -ErrorAction SilentlyContinue; $fp.WaitForExit(5000) | Out-Null
$o = & "$gl\game-check.ps1" -NoLearn
Check '... and not once it has closed' ("$o" -notmatch 'FakeGame123') "$o"

Section 'periodic: weekly app updates while a game runs'
$d = "$Work\periodic"; New-Item $d -ItemType Directory -Force | Out-Null; Copy-Item "$Src\periodic-maint.ps1" $d; $stub | Set-Content "$d\game-check.ps1"; '-1' | Set-Content "$d\gamecalls.txt"
$old = (Get-Date).AddDays(-8).ToString('o'); @{ 'weekly-apps' = $old; 'monthly-cleanup' = (Get-Date).ToString('o'); 'trim' = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content "$d\maint-state.json"
$o = & powershell -NoProfile -ExecutionPolicy Bypass -File "$d\periodic-maint.ps1"
$held = @($o | Where-Object { $_ -match 'held while TestGame' })
Check 'app updates held, said without FAILED/WARNING' ($held -and -not ($held -match 'WARNING|FAILED')) ($o -join ' / ')
Check 'not marked done, so they run next time' ((Get-Content "$d\maint-state.json" -Raw | ConvertFrom-Json).'weekly-apps' -eq $old) ''

# (driver-check while a game runs: tests\unit\driver-check.ps1, mocked - a real run here searched Windows Update for
#  20 s and could hide real driver updates)

Section 'background run: waits for the game, then runs'
$H = "$Work\bg"; $d = "$H\.claude"; New-Item $d -ItemType Directory -Force | Out-Null
(Get-Content "$Src\claude-bg-maint.ps1" -Raw).Replace("'Global\ClaudeBgMaint'", "'Global\ClaudeBgMaintT$PID'").Replace('Start-Sleep 60', 'Start-Sleep 1') | Set-Content "$d\claude-bg-maint.ps1"
Copy-Item "$Src\maint-due.ps1" $d; $stub | Set-Content "$d\game-check.ps1"
foreach ($j in 'driver-check', 'claude-maint', 'health-check', 'periodic-maint') { "`"$j ran`"" | Set-Content "$d\$j.ps1" }
'param([string]$Due, [string]$Mode); "ran $Mode" | Add-Content "$PSScriptRoot\runs.log"' | Set-Content "$d\claude-unattended.ps1"
$now = (Get-Date).ToString('o'); @{ 'claude-quarterly' = $now; 'claude-halfyear' = $now; 'claude-yearly' = $now } | ConvertTo-Json | Set-Content "$d\maint-state.json"
'3' | Set-Content "$d\gamecalls.txt"; [void](Invoke-As $H "$d\claude-bg-maint.ps1" @('-Force', '-Unattended'))
Check 'polled while the game ran, then started' (@(Get-Content "$d\gamechecks.log").Count -ge 4) "checks: $(@(Get-Content "$d\gamechecks.log").Count)"
Check 'all jobs ran after the game closed' (@((Get-Content "$d\maint-report.txt") -match ' ran$').Count -eq 4) ((Get-Content "$d\maint-report.txt") -join ' / ')
Check 'self-improvement ran' ((Get-Content "$d\runs.log" -ErrorAction SilentlyContinue) -contains 'ran improve') ''
foreach ($f in 'runs.log', 'selfimprove-last', 'gamechecks.log') { Clear-Path "$d\$f" }
(Get-Content "$d\claude-bg-maint.ps1" -Raw).Replace('TotalMinutes -lt 45', 'TotalSeconds -lt 3').Replace('TotalMinutes -lt 30', 'TotalSeconds -lt 3') | Set-Content "$d\claude-bg-maint.ps1"
'-1' | Set-Content "$d\gamecalls.txt"; [void](Invoke-As $H "$d\claude-bg-maint.ps1" @('-Force', '-Unattended'))
$rep = Get-Content "$d\maint-report.txt"
Check 'game never closes: report says heavy steps held (no WARNING)' (($rep -match 'Game: TestGame still running') -and -not ($rep -match 'WARNING')) ($rep -join ' / ')
Check '... self-improvement skipped today' (-not ((Get-Content "$d\runs.log" -ErrorAction SilentlyContinue) -contains 'ran improve')) ''
Check '... and still due next time (no stamp)' (-not (Test-Path "$d\selfimprove-last")) ''
Finish
