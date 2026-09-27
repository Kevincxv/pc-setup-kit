# Self-test: runs the kit's test suite (unit: sandboxes only, nothing on the PC changes) against this PC's installed
# maintenance scripts and tray. Run by claude-bg-maint.ps1 after its jobs - weekly, and after every kit update - so a
# broken update or a script that stopped working on this PC shows up as a WARNING that /maintain looks at.
# -Force: run now (e.g. /maintain after fixing a failure).   Output: one line; details in .claude\self-test.log.
# Test overrides: -KitDir, -Minutes; $env:PCKIT_TESTS_DIR = a stand-in suite.
param([switch]$Force, [string]$KitDir = 'C:\PCSetupKit', [double]$Minutes = 30)
$ErrorActionPreference = 'Continue'
$dir = $PSScriptRoot
# the suite: the kit repo on the PC it's developed on, else the installed kit. Never inside a test run (no suite-in-suite)
$tests = if ($env:PCKIT_TESTS_DIR) { $env:PCKIT_TESTS_DIR } elseif (-not $env:PCKIT_IN_TESTS) {
    @("$env:USERPROFILE\Documents\PC Setup Kit\PCSetupKit\tests", "$KitDir\tests") | Where-Object { Test-Path "$_\run-tests.ps1" } | Select-Object -First 1 }
if (-not $tests) { return }

$stateFile = "$dir\self-test.json"
$state = $null; try { $state = Get-Content $stateFile -Raw -ErrorAction Stop | ConvertFrom-Json } catch {}
$kit = if (Test-Path "$KitDir\kit-version.txt") { (Get-Content "$KitDir\kit-version.txt" -Raw).Trim() } else { '' }
$last = [datetime]::MinValue; if ($state) { [void][datetime]::TryParse("$($state.date)", [ref]$last) }
$why = if ($Force) { 'requested' } elseif (-not $state) { 'first run' } elseif ($kit -ne "$($state.kit)") { "after the kit update to $kit" } elseif (((Get-Date) - $last).TotalDays -ge 7) { 'weekly' }
if (-not $why) { return }
if (-not $Force -and (Test-Path "$dir\game-check.ps1") -and ($g = & "$dir\game-check.ps1")) { "Self-test held: $g is running (next login)"; return }

$log = "$dir\self-test.log"
$tray = "$env:USERPROFILE\Documents\Messiah Tray\Messiah Tray.ahk"
$argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$tests\run-tests.ps1`"", '-Suite', 'unit', '-Src', "`"$dir`"") + $(if (Test-Path $tray) { '-TrayFile', "`"$tray`"" })
$t0 = Get-Date
$p = Start-Process powershell -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -ArgumentList $argList
$null = $p.Handle   # keeps the exit code readable after the process ends
$timedOut = -not $p.WaitForExit([int]($Minutes * 60000))
if ($timedOut) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
$out = @(Get-Content $log -ErrorAction SilentlyContinue)
$sum = $out | Where-Object { $_ -match '^PC Setup Kit tests \(unit\) .*: (\d+) passed, (\d+) failed' } | Select-Object -Last 1
$failed = @($out | Where-Object { $_ -match '^\s+(\S+)\s+\d+ passed\s+([1-9]\d*) failed' } | ForEach-Object { ($_ -split '\s+')[1] })
$ok = -not $timedOut -and $p.ExitCode -eq 0 -and $sum -match ' 0 failed'
$counts = if ($sum -match ': (\d+) passed, (\d+) failed') { "$($Matches[1]) passed, $($Matches[2]) failed" } else { 'no result' }

@{ date = (Get-Date).ToString('o'); kit = $kit; ok = $ok; result = $counts; failed = $failed; reason = $why; seconds = [int]((Get-Date) - $t0).TotalSeconds } |
    ConvertTo-Json | Set-Content "$stateFile.tmp" -Encoding UTF8
Move-Item "$stateFile.tmp" $stateFile -Force
if ($ok) { "Self-test ($why): $counts" }
elseif ($timedOut) { "WARNING: self-test ($why) was stopped after $Minutes min - a test hangs (log: $log)" }
else { "WARNING: self-test ($why) failed: $counts$(if ($failed) { " in $($failed -join ', ')" }) (log: $log)" }
