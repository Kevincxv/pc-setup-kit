# The live tests (the kit's tests\live: the real sign-in chain, real hidden Messiah sessions, a little Claude usage via
# Haiku) - what the unit tests can't reach. They restart the tray and sessions, so they only run while nobody uses the
# PC: the tray starts this after 30+ minutes without keyboard or mouse, and it runs at most once a week, never under a
# game, a chat Claude is working in, or a hidden maintenance run. A failure goes to maint-requests.txt, so /maintain
# looks at it at the next login. Only with the AI assistant on (the live tests are about the Claude sessions).
# -Force: now, whatever the conditions.   Output: one line; details in .claude\live-test.log, the result in live-test.json.
# Test overrides: -Tests (a stand-in suite folder), -Dir (the .claude folder), -IdleMinutes, -GameCheck, -Minutes.
param([switch]$Force, [string]$Tests, [string]$Dir = $PSScriptRoot, [double]$IdleMinutes = -1, [scriptblock]$GameCheck, [double]$Minutes = 40)
$ErrorActionPreference = 'Continue'
if ($env:PCKIT_IN_TESTS -and -not $Tests) { return }   # never the real live suite from inside a test run
if (-not $Tests) { $Tests = @("$env:USERPROFILE\Documents\PC Setup Kit\PCSetupKit\tests", 'C:\PCSetupKit\tests') | Where-Object { Test-Path "$_\run-tests.ps1" } | Select-Object -First 1 }
if (-not $Tests -or -not (Test-Path "$Tests\live")) { return }
$stateFile = "$Dir\live-test.json"

function Get-IdleMinutes {
    if ($IdleMinutes -ge 0) { return $IdleMinutes }
    if (-not ('KitIdle.L' -as [type])) { Add-Type -Namespace KitIdle -Name L -MemberDefinition '[StructLayout(LayoutKind.Sequential)] public struct I { public uint cb; public uint t; } [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref I i); public static uint Ms() { I i = new I(); i.cb = 8; GetLastInputInfo(ref i); return (uint)Environment.TickCount - i.t; }' }
    [KitIdle.L]::Ms() / 60000
}
if (-not $Force) {
    $ai = @(Get-Content "$Dir\kit-options.txt" -ErrorAction SilentlyContinue) -match '^\s*claude\s*=\s*on\s*$'
    if (-not $ai) { return }
    $last = [datetime]::MinValue; try { [void][datetime]::TryParse("$((Get-Content $stateFile -Raw -ErrorAction Stop | ConvertFrom-Json).date)", [ref]$last) } catch {}
    if ($last -gt (Get-Date).AddDays(-7)) { return }
    if ((Get-IdleMinutes) -lt 30) { return }
    $g = if ($GameCheck) { & $GameCheck } elseif (Test-Path "$Dir\game-check.ps1") { & "$Dir\game-check.ps1" }
    if ($g) { return }
    foreach ($d in @("$Dir\chat") + @(Get-ChildItem "$Dir\chats" -Directory -ErrorAction SilentlyContinue | ForEach-Object FullName)) {
        $s = try { Get-Content "$d\state.json" -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null }
        if ($s -and $s.busy -and $s.pid -and (Get-Process -Id $s.pid -ErrorAction SilentlyContinue)) { return }
    }
    $m = "$Dir\maint-claude-running"; if ((Test-Path $m) -and ((Get-Date) - (Get-Item $m).LastWriteTime).TotalMinutes -lt 60) { return }
}

$mx = New-Object Threading.Mutex($false, 'Global\MessiahLiveTest'); if (-not $mx.WaitOne(0)) { return }   # (one at a time: a run takes minutes)
$log = "$Dir\live-test.log"; $t0 = Get-Date
$tray = "$env:USERPROFILE\Documents\Messiah Tray\Messiah Tray.ahk"
$argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Tests\run-tests.ps1`"", '-Suite', 'live', '-Src', "`"$Dir`"") + $(if (Test-Path $tray) { '-TrayFile', "`"$tray`"" })
$p = Start-Process powershell -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -ArgumentList $argList
$null = $p.Handle
$timedOut = -not $p.WaitForExit([int]($Minutes * 60000))
if ($timedOut) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
$out = @(Get-Content $log -ErrorAction SilentlyContinue)
$sum = $out | Where-Object { $_ -match '^PC Setup Kit tests \(live\) .*: (\d+) passed, (\d+) failed' } | Select-Object -Last 1
$failed = @($out | Where-Object { $_ -match '^\s+(\S+)\s+\d+ passed\s+([1-9]\d*) failed' } | ForEach-Object { ($_ -split '\s+')[1] })
$ok = -not $timedOut -and $p.ExitCode -eq 0 -and $sum -match ' 0 failed'
$counts = if ($sum -match ': (\d+) passed, (\d+) failed') { "$($Matches[1]) passed, $($Matches[2]) failed" } else { 'no result' }
@{ date = (Get-Date).ToString('o'); ok = $ok; result = $counts; failed = $failed; seconds = [int]((Get-Date) - $t0).TotalSeconds } | ConvertTo-Json | Set-Content $stateFile -Encoding UTF8
if ($ok) { "Live self-test: $counts"; return }
$what = if ($timedOut) { "stopped after $Minutes min - a live test hangs" } else { "$counts$(if ($failed) { " in $($failed -join ', ')" })" }
Add-Content "$Dir\maint-requests.txt" "The weekly live self-test (run while the PC was idle) failed: $what. Log: .claude\live-test.log - find out what broke in the sign-in chain or the hidden sessions and fix it." -Encoding UTF8
"WARNING: live self-test failed: $what (log: $log)"
