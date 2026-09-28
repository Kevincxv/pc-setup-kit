# Runs the PC Setup Kit test suite and prints a summary. Exit code 0 = everything passed.
#   -Suite unit : safe tests - sandboxes only, nothing on the PC changes (also what GitHub runs on every push)
#   -Suite live : tests against this PC's real setup (tray, hidden sessions, real Claude - uses a little usage)
#   -Suite all  : both.   -Only <name>: just the matching test files.
#   -Src  : the maintenance scripts to test (default: this PC's installed .claude if present, else the kit's copy)
#   -Kit  : the kit folder (default: the one this runner is in)
#   -Jobs : unit test files run side by side, this many at a time (default: up to 8; 1 = one after another).
#           Live tests always run one at a time, after the unit tests (they share the real tray and sessions).
#   -TestMinutes : a test file still running after this long is stopped and counted as failed (default 10)
# Results also go to tests\last-run.txt.
param([ValidateSet('unit', 'live', 'all')][string]$Suite = 'unit', [string]$Only, [string]$Src, [string]$Kit, [string]$TrayFile, [int]$Jobs = 0, [int]$TestMinutes = 10)
$ErrorActionPreference = 'Continue'   # a test writing to stderr must never stop the runner (CI runs with Stop)
$here = $PSScriptRoot
if (-not $Kit) { $Kit = Split-Path $here }
if (-not $Src) { $Src = if (Test-Path "$env:USERPROFILE\.claude\claude-admin-launch.ps1") { "$env:USERPROFILE\.claude" } else { "$Kit\claude" } }
if (-not $TrayFile) { $TrayFile = if (Test-Path "$env:USERPROFILE\Documents\Messiah Tray\Messiah Tray.ahk") { "$env:USERPROFILE\Documents\Messiah Tray\Messiah Tray.ahk" } else { "$Kit\claude\tray\Messiah Tray.ahk" } }
if ($Jobs -le 0) { $Jobs = [math]::Min(8, [Environment]::ProcessorCount) }
$env:PCKIT_SRC = $Src; $env:PCKIT_KIT = $Kit; $env:PCKIT_TRAY = $TrayFile
$env:PCKIT_IN_TESTS = '1'   # scripts under test know not to start the real test suite themselves (no suite-in-suite loops)
$scratch = Join-Path $env:TEMP 'pckit-tests'
$env:PCKIT_BIN_ROOT = $scratch   # compiled stand-ins, shared by all tests (each test gets its own TEMP below)

$unit = @(); $live = @()
if ($Suite -in 'unit', 'all') { $unit = @(Get-ChildItem "$here\unit\*.ps1" | Sort-Object Name) }
if ($Suite -in 'live', 'all') { $live = @(Get-ChildItem "$here\live\*.ps1" | Sort-Object Name) }
if ($Only) { $unit = @($unit | Where-Object BaseName -match $Only); $live = @($live | Where-Object BaseName -match $Only) }
Write-Host "PC Setup Kit tests ($Suite) - scripts: $Src$(if ($unit.Count -gt 1 -and $Jobs -gt 1) { " - $Jobs at a time" })" -ForegroundColor Cyan

# scratch folders of runs more than 2 days old go (the weekly self-test would otherwise pile them up)
Get-ChildItem $scratch -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin 'bin', 'sleeper', 'scripted2', 'dbg' -and $_.LastWriteTime -lt (Get-Date).AddDays(-2) } |
    ForEach-Object { try { [IO.Directory]::Delete($_.FullName, $true) } catch {} }
# build the compiled stand-ins once, before tests start side by side (two tests compiling the same file would clash)
& powershell -NoProfile -ExecutionPolicy Bypass -Command ". '$here\lib.ps1'; [void](Get-FakeClaude); [void](Get-SleeperClaude); [void](Get-ScriptedClaude)" *> $null

function Start-Test($f) {
    $tmp = Join-Path $scratch "tmp-$($f.BaseName)-$PID-$(Get-Random -Maximum 9999)"; New-Item $tmp -ItemType Directory -Force | Out-Null
    $psi = New-Object Diagnostics.ProcessStartInfo 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($f.FullName)`""
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true   # shares this console (no new windows)
    $psi.StandardOutputEncoding = [Console]::OutputEncoding; $psi.StandardErrorEncoding = [Console]::OutputEncoding
    $psi.EnvironmentVariables['TEMP'] = $tmp; $psi.EnvironmentVariables['TMP'] = $tmp   # its own TEMP: tests run side by side
    $p = [Diagnostics.Process]::Start($psi)
    [pscustomobject]@{ File = $f; Proc = $p; Out = $p.StandardOutput.ReadToEndAsync(); Err = $p.StandardError.ReadToEndAsync(); Start = Get-Date; Sec = 0; Text = $null }
}
function Stop-Tree([int]$ProcId) {
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcId" | ForEach-Object { Stop-Tree $_.ProcessId }
    Stop-Process -Id $ProcId -Force -ErrorAction SilentlyContinue
}
function Complete($t) {
    $t.Sec = [int]((Get-Date) - $t.Start).TotalSeconds
    $t.Text = @(($t.Out.Result + $t.Err.Result) -split "`r?`n" | Where-Object { $_ -ne '' })
    $t | Add-Member ErrText ($t.Err.Result.Trim()) -Force
}
# Runs the files at most $Max at a time, longest first (last run's times); prints each test's output in name order
function Invoke-Files($files, [int]$Max) {
    $prev = @{}; Get-Content "$here\last-run.txt" -ErrorAction SilentlyContinue | ForEach-Object { if ($_ -match '^\s+(\S+)\s+\d+ passed.*?(\d+)s\s*$') { $prev[$Matches[1]] = [int]$Matches[2] } }
    $queue = New-Object Collections.Queue; $files | Sort-Object { - [int]$prev[$_.BaseName] } | ForEach-Object { $queue.Enqueue($_) }
    $running = @(); $done = @{}; $next = 0
    while ($queue.Count -or $running) {
        while ($queue.Count -and $running.Count -lt $Max) { $running += Start-Test $queue.Dequeue() }
        # a hung test is stopped at the limit and named, instead of silently holding up everything after it
        foreach ($t in @($running | Where-Object { -not $_.Proc.HasExited -and ((Get-Date) - $_.Start).TotalMinutes -ge $TestMinutes })) {
            Stop-Tree $t.Proc.Id; $t | Add-Member TimedOut $true -Force; [void]$t.Proc.WaitForExit(10000)
        }
        foreach ($t in @($running | Where-Object { $_.Proc.HasExited })) { Complete $t; $done[$t.File.FullName] = $t }
        $running = @($running | Where-Object { -not $done.ContainsKey($_.File.FullName) })
        while ($next -lt $files.Count -and $done.ContainsKey($files[$next].FullName)) {
            $t = $done[$files[$next].FullName]; $next++
            Write-Host "`n[$($t.File.BaseName)]" -ForegroundColor White
            $t.Text | Where-Object { $_ -notmatch '^RESULT ' } | ForEach-Object { Write-Host $_ }
            if ($t.TimedOut) { Write-Host "  FAIL  still running after $TestMinutes min - stopped (it hangs; the last lines above show where)" -ForegroundColor Red }
            elseif (-not ($t.Text -match '^RESULT ')) { Write-Host '  FAIL  the test itself crashed (no RESULT line)' -ForegroundColor Red }
            # errors a test didn't handle (e.g. one that ended a try block early) land on stderr: never a silent pass
            if ($t.ErrText) { Write-Host "  FAIL  the test wrote errors: $(($t.ErrText -split '`r?`n' | Select-Object -First 2) -join ' | ')" -ForegroundColor Red }
        }
        if ($running) { Start-Sleep -Milliseconds 100 }
    }
    foreach ($f in $files) {
        $t = $done[$f.FullName]; $r = $t.Text | Where-Object { $_ -match '^RESULT ' } | Select-Object -Last 1
        if ("$r" -match 'pass=(\d+) fail=(\d+) skip=(\d+)') { [pscustomobject]@{ Test = $f.BaseName; Pass = [int]$Matches[1]; Fail = [int]$Matches[2] + [int][bool]$t.ErrText; Skip = [int]$Matches[3]; Sec = $t.Sec } }
        else { [pscustomobject]@{ Test = $f.BaseName; Pass = 0; Fail = 1; Skip = 0; Sec = $t.Sec } }   # crashed before finishing
    }
}

$t0 = Get-Date
$rows = @(if ($unit) { Invoke-Files $unit $Jobs }) + @(if ($live) { Invoke-Files $live 1 })
$p = ($rows | Measure-Object Pass -Sum).Sum; $fl = ($rows | Measure-Object Fail -Sum).Sum; $sk = ($rows | Measure-Object Skip -Sum).Sum
$summary = @("PC Setup Kit tests ($Suite) $((Get-Date).ToString('g')) in $([int]((Get-Date) - $t0).TotalSeconds)s: $p passed, $fl failed, $sk skipped") +
    ($rows | ForEach-Object { '  {0,-22} {1,4} passed {2,3} failed {3,3} skipped {4,5}s' -f $_.Test, $_.Pass, $_.Fail, $_.Skip, $_.Sec })
Write-Host ''; $summary | ForEach-Object { Write-Host $_ -ForegroundColor $(if ($fl) { 'Red' } else { 'Green' }) }
try { $summary | Set-Content "$here\last-run.txt" -Encoding utf8 } catch {}
exit [int]($fl -gt 0)
