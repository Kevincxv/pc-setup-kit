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
# (a copy of ping.exe stands in for the game: PowerShell itself is on the never-a-game list, which games.txt is checked against)
$bgDir = "$Work\bggame"; New-Item $bgDir -ItemType Directory -Force | Out-Null; Copy-Item "$env:SystemRoot\System32\PING.EXE" "$bgDir\BgGame123.exe"
$bgp = Start-Process "$bgDir\BgGame123.exe" -ArgumentList '-n', '30', '127.0.0.1' -WindowStyle Hidden -PassThru; Start-Sleep -Milliseconds 500
'BgGame123    # test' | Set-Content "$gl\games.txt"
$o = & "$gl\game-check.ps1" -Explain -NoLearn
if ("$o" -match 'fullscreen') { Skip 'a listed game running in the background is reported' "something is fullscreen right now ($o), which correctly wins" }
else { Check 'a listed game running in the background is reported' ("$o" -match '^BgGame123 - known game running') "$o" }
Stop-Process -Id $bgp.Id -Force -ErrorAction SilentlyContinue; $bgp.WaitForExit(5000) | Out-Null
# a game never seen fullscreen, running from a Steam library folder (a copy of ping.exe stands in for it)
'' | Set-Content "$gl\games.txt"
$fake = "$Work\Steam\steamapps\common\FakeGame"; New-Item $fake -ItemType Directory -Force | Out-Null; Copy-Item "$env:SystemRoot\System32\PING.EXE" "$fake\FakeGame123.exe"
$fp = Start-Process "$fake\FakeGame123.exe" -ArgumentList '-n', '30', '127.0.0.1' -WindowStyle Hidden -PassThru; Start-Sleep -Milliseconds 500
$o = & "$gl\game-check.ps1" -Explain -NoLearn
if ("$o" -match 'fullscreen') { Skip 'a game running from a game library folder is reported' "something is fullscreen right now ($o)" }
elseif ("$o" -notmatch '^FakeGame123' -and "$o" -match 'running from a game library|known game') { Skip 'a game running from a game library folder is reported' "a real game is running on this PC ($o)" }
else { Check 'a game running from a game library folder is reported' ("$o" -match '^FakeGame123 - running from a game library') "$o" }
Stop-Process -Id $fp.Id -Force -ErrorAction SilentlyContinue; $fp.WaitForExit(5000) | Out-Null
$o = & "$gl\game-check.ps1" -NoLearn
Check '... and not once it has closed' ("$o" -notmatch 'FakeGame123') "$o"

Section 'game-check.ps1: what is learned as a game (10/10: a launcher in front of a borderless game was learned)'
function Learned { @(Get-Content "$gl\games.txt" -ErrorAction SilentlyContinue | ForEach-Object { ($_ -split '#')[0].Trim() } | Where-Object { $_ }) }
'' | Set-Content "$gl\games.txt"
$o = & "$gl\game-check.ps1" -T @{ Name = 'SomeLauncher123'; Covers = $false; State = 2; Behind = 'BehindGame123' }
Check 'a window in front of a fullscreen app (state 2, not covering its monitor): maintenance waits for the app behind it, learned - not the window in front' ($o -eq 'BehindGame123' -and 'BehindGame123' -in (Learned) -and 'SomeLauncher123' -notin (Learned)) "$o / $(Learned)"
$o = & "$gl\game-check.ps1" -Explain -T @{ Name = 'steamwebhelper'; Covers = $false; State = 2; Behind = '' }
Check 'state 2 with nothing really fullscreen (an always-on overlay - 10/21): no game, nothing learned' ("$o" -match '^no game' -and 'steamwebhelper' -notin (Learned)) "$o / $(Learned)"
$o = & "$gl\game-check.ps1" -T @{ Name = 'POWERPNT'; Covers = $false; State = 4; Behind = '' }
Check '... the same for presentation mode (state 4) with nothing fullscreen' (-not $o) "$o"
# the real window search, with a real window covering the screen - invisible (opacity 0), for a moment: found as
# itself; made click-through like an overlay: not found
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Namespace GA -Name W -MemberDefinition '[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i); [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);'
$me = (Get-Process -Id $PID).ProcessName
$fm = New-Object Windows.Forms.Form -Property @{ FormBorderStyle = 'None'; ShowInTaskbar = $false; Opacity = 0; StartPosition = 'Manual'; Bounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds; TopMost = $true }
try {
    $fm.Show(); [Windows.Forms.Application]::DoEvents()
    $b1 = [GameCheck.Cover]::Behind([IntPtr]::Zero, [string[]]@())
    $h = $fm.Handle; [void][GA.W]::SetWindowLong($h, -20, ([GA.W]::GetWindowLong($h, -20) -bor 0x20))
    $b2 = [GameCheck.Cover]::Behind([IntPtr]::Zero, [string[]]@())
    $b3 = [GameCheck.Cover]::Behind([IntPtr]::Zero, [string[]]@($me))
} finally { $fm.Close(); $fm.Dispose() }
Check 'the window search: a window covering the screen is found' ($b1 -eq $me) "found [$b1]"
Check '... the same window click-through (an overlay): not found' ($b2 -ne $me) "found [$b2]"
Check '... and a program on the skip list is passed over' ($b3 -ne $me) "found [$b3]"
$o = & "$gl\game-check.ps1" -T @{ Name = 'BorderlessGame123'; Covers = $true; State = 2 }
Check 'a window covering its whole monitor is learned' ($o -eq 'BorderlessGame123' -and 'BorderlessGame123' -in (Learned)) "$o / $(Learned)"
$o = & "$gl\game-check.ps1" -T @{ Name = 'ExclusiveGame123'; Covers = $false; State = 3 }
Check 'Direct3D exclusive fullscreen (state 3) is learned' ($o -eq 'ExclusiveGame123' -and 'ExclusiveGame123' -in (Learned)) "$o / $(Learned)"
$o = & "$gl\game-check.ps1" -T @{ Name = 'Better2k'; Covers = $true; State = 2 }
Check 'a game launcher is never learned, even covering the screen' ('Better2k' -notin (Learned)) "$(Learned)"
# a launcher an older version learned, running hidden all day (ping.exe stands in for it): not a game
'Better2k    # learned by an older version' | Set-Content "$gl\games.txt"
$lp = "$Work\launcher"; New-Item $lp -ItemType Directory -Force | Out-Null; Copy-Item "$env:SystemRoot\System32\PING.EXE" "$lp\Better2k.exe"
$bp = Start-Process "$lp\Better2k.exe" -ArgumentList '-n', '30', '127.0.0.1' -WindowStyle Hidden -PassThru; Start-Sleep -Milliseconds 500
$o = & "$gl\game-check.ps1" -Explain -NoLearn -T @{ Name = 'explorer'; Covers = $false; State = 0 }
Check 'a launcher learned by an older version no longer holds maintenance while it runs in the tray' ("$o" -notmatch 'Better2k') "$o"
Stop-Process -Id $bp.Id -Force -ErrorAction SilentlyContinue; $bp.WaitForExit(5000) | Out-Null

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
