# game-perf.ps1: one minute of a game's frame times (PresentMon's CSV) and the graphics card's heat -> perf-history.json.
# A recorded capture and nvidia-smi rows stand in for the real ones; nothing is captured or downloaded.
. "$PSScriptRoot\..\lib.ps1"
$gp = "$Src\game-perf.ps1"
if (-not (Test-Path $gp)) { Skip 'game-perf' 'not installed here'; Finish }
$now = Get-Date
# a capture: $n frames of the game at 8 ms (125 fps) with $slow hitches of 60 ms, plus another app's frames
function New-Capture([int]$n = 900, [int]$slow = 12, [string]$app = 'TestGame.exe') {
    $f = "$Work\capture-$n-$slow-$app.csv"
    $rows = @('Application,ProcessID,MsBetweenPresents')
    for ($i = 0; $i -lt $n; $i++) { $rows += "$app,100,$(if ($i % [Math]::Max(1, [int]($n / [Math]::Max(1, $slow))) -eq 0 -and $slow) { '60.0' } else { '8.0' })" }
    for ($i = 0; $i -lt 200; $i++) { $rows += 'Browser.exe,200,2.0' }
    $rows | Set-Content $f; $f
}
$hf = "$Work\perf-history.json"
function Invoke-Sample([string]$csv, [string[]]$gpu = @('70, 98, Not Active, Not Active, Not Active'), [datetime]$at = $now, [switch]$Force, [double[]]$dpc = @(1.5, 22.4, 3.0), [string[]]$cpu = @(), [string]$game = 'TestGame', [double[]]$cpuT = @()) {
    @(& $gp -TestCsv $csv -TestGame $game -TestGpu $gpu -TestDpc $dpc -TestCpu $cpu -TestCpuTemp $cpuT -History $hf -Now $at -Force:$Force -Tune "$Work\game-tune.json" -GameSettings "$Work\game-settings.json")
}
function Hist { $j = Get-Content $hf -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json; @($j | ForEach-Object { $_ }) }   # (call as @(Hist): one item comes back bare, with no .Count in PS 5.1)

Section 'a sample'
$cap = New-Capture
$o = Invoke-Sample $cap @('70, 98, Not Active, Not Active, Not Active', '84, 99, Active, Not Active, Active')
$h = @(Hist); $s = $h[-1]
Check 'one sample recorded, saying what it measured' ($h.Count -eq 1 -and "$o" -match '^TestGame: [\d.]+ fps average, [\d.]+ fps 1% low, graphics card up to 84 C$') "$o"
Check "only the game's frames count (not another app's)" ($s.frames -eq 900) "frames: $($s.frames)"
Check 'average frame rate from the frame times' ([Math]::Abs($s.fps - 1000 / ((888 * 8 + 12 * 60) / 900)) -lt 0.2) "fps: $($s.fps)"
Check '1% low = the frame time only 1 in 100 frames is slower than' ([Math]::Abs($s.low1 - 1000 / 60) -lt 0.2) "low1: $($s.low1)"
Check 'hitches counted' ($s.stutters -eq 12) "stutters: $($s.stutters)"
Check 'the hottest reading and the average load' ($s.gpuTemp -eq 84 -and $s.gpuUse -eq 98) "$($s.gpuTemp) C, $($s.gpuUse)%"
Check 'throttling recorded (heat, power)' ($s.throttle -eq 'heat,power') "$($s.throttle)"
Check 'the minute second by second: each second''s frame rate and slowest frame (for the app''s Performance page)' (@($s.perSec).Count -eq 7 -and @($s.worstMs).Count -eq 7 -and (@($s.perSec) | Where-Object { $_ -lt 100 -or $_ -gt 130 }).Count -eq 0 -and (@($s.worstMs) | Measure-Object -Maximum).Maximum -eq 60) "$(@($s.perSec) -join ',') / $(@($s.worstMs) -join ',')"
Check 'drivers'' time on the busiest core: the worst and the average reading (the stutters an average frame rate hides)' ($s.dpcMax -eq 22.4 -and $s.dpc -eq 9) "$($s.dpcMax) / $($s.dpc)"
Check 'the RAM speed and Memory Integrity recorded (EXPO on or off, a change to compare across)' ($s.ram -match '^\d+ MT/s$' -and $s.hvci -in 'on', 'off') "$($s.ram) / $($s.hvci)"
Check 'the driver and Windows build recorded (a change there explains a change here)' ($s.build -match '^\d+\.\d+$' -and $null -ne $s.driver) "$($s.driver) / $($s.build)"

Section 'when not to sample'
[void](Invoke-Sample $cap -at $now.AddMinutes(20))
Check 'the same game again within 25 minutes: skipped' (@(Hist).Count -eq 1) ''
[void](Invoke-Sample $cap -at $now.AddMinutes(30))
Check '... and sampled after 25 minutes (a few samples of each session)' (@(Hist).Count -eq 2) ''
[void](Invoke-Sample $cap @('45, 12', '44, 15') -at $now.AddHours(2))
Check 'the graphics card hardly busy (a menu, a lobby, a kill-cam): not a sample' (@(Hist).Count -eq 2) ''
$o = Invoke-Sample (New-Capture 150 0) -at $now.AddHours(8)
Check 'too few frames (a menu, loading, alt-tabbed): not a sample' (@(Hist).Count -eq 2 -and -not $o) "$o"
[void](Invoke-Sample (New-Capture 900 0) @('55, 40') -at $now.AddHours(12))
Check 'an older driver without throttle fields: temperature and load still read' (@(Hist)[-1].gpuTemp -eq 55 -and -not @(Hist)[-1].throttle) ''
$many = @(1..40 | ForEach-Object { [ordered]@{ date = $now.AddDays(-50 + $_).ToString('o'); game = 'Old'; fps = 60; low1 = 50; frames = 3600; perSec = @(60, 60); worstMs = @(17, 17) } })
ConvertTo-Json -InputObject $many -Depth 3 | Set-Content $hf
[void](Invoke-Sample $cap -at $now.AddDays(1) -Force)
$hh = @(Hist)
Check 'the second-by-second curves are kept only on the newest 30 samples (the file stays small)' (@($hh | Where-Object { $_.perSec }).Count -eq 30 -and $hh[-1].perSec -and -not $hh[0].perSec) "$(@($hh | Where-Object { $_.perSec }).Count) with curves"
Section 'heat, the processor, and a setting being tried (10/21)'
Clear-Path $hf
$o = Invoke-Sample $cap @('70, 98, Not Active, Not Active, Not Active, 55, 280.5', '76, 99, Not Active, Not Active, Not Active, 61, 301.2') -cpu @('100,112', '87,104', '100,110') -cpuT @(71.5, 78.2, 74) -Force
$s = @(Hist)[-1]
Check 'the graphics card''s fan (average %) and power (most watts) while playing' ($s.gpuFan -eq 58 -and $s.gpuPower -eq 301) "$($s.gpuFan) / $($s.gpuPower)"
Check 'the processor: its lowest speed limit (under 100 = held back by heat or power) and its average speed against base' ($s.cpuLimit -eq 87 -and $s.cpuPerf -eq 109) "$($s.cpuLimit) / $($s.cpuPerf)"
Check 'the processor''s temperature: the hottest reading of the minute' ($s.cpuTemp -eq 78.2) "$($s.cpuTemp)"
Check '... nothing invented when a card or Windows doesn''t give them' (-not (@(Hist)[0].PSObject.Properties.Name -contains 'tune')) ''
'{"active":{"id":"reflex","game":"TestGame","arm":"b"},"keys":["Reflex@0"]}' | Set-Content "$Work\game-tune.json"
[void](Invoke-Sample $cap -at $now.AddHours(1) -Force)
Check 'a setting being tried for this game: the minute is tagged with it and its value (game-tune.ps1 reads it)' (@(Hist)[-1].tune -eq 'reflex:b') "$(@(Hist)[-1].tune)"
[void](Invoke-Sample (New-Capture 900 12 'OtherGame.exe') -at $now.AddHours(2) -Force -game 'OtherGame')
Check '... not a minute of another game' (@(Hist)[-1].game -eq 'OtherGame' -and -not @(Hist)[-1].tune) "$(@(Hist)[-1].tune)"
'{"C:\\\\g\\\\s.txt":{"at":"2026-01-01","values":{"Shadow@0":"Low","Reflex@0":"Enabled"}},"driver":"1.0"}' | Set-Content "$Work\game-settings.json"
[void](Invoke-Sample $cap -at $now.AddHours(3) -Force); $f1 = @(Hist)[-1].settings
'{"C:\\\\g\\\\s.txt":{"at":"2026-02-02","values":{"Shadow@0":"Low","Reflex@0":"Enabled + boost"}},"driver":"2.0"}' | Set-Content "$Work\game-settings.json"
[void](Invoke-Sample $cap -at $now.AddHours(4) -Force); $f2 = @(Hist)[-1].settings
'{"C:\\\\g\\\\s.txt":{"at":"2026-02-02","values":{"Shadow@0":"High","Reflex@0":"Enabled + boost"}},"driver":"2.0"}' | Set-Content "$Work\game-settings.json"
[void](Invoke-Sample $cap -at $now.AddHours(5) -Force); $f3 = @(Hist)[-1].settings
Check 'the game settings fingerprint: not changed by the driver it also keeps, nor by the setting being tried' ($f1 -and $f1 -eq $f2) "$f1 / $f2"
Check '... but by another setting' ($f3 -and $f3 -ne $f2) "$f2 / $f3"

Section 'what holds it back, the delay, the menu left out (10/22)'
Clear-Path $hf; Clear-Path "$Work\game-tune.json"
[void](Invoke-Sample $cap @('67.61, 93, Not Active, Not Active, Not Active, 48, 212.51') -Force)
Check 'a newer driver''s temperature with decimals ("67.61"): still read' (@(Hist)[-1].gpuTemp -eq 68 -and @(Hist)[-1].gpuUse -eq 93) "$(@(Hist)[-1].gpuTemp) / $(@(Hist)[-1].gpuUse)"
# PresentMon 2's columns: $menu seconds at the menu's 60 cap, then $play seconds at 125 fps (8 ms: 6 of them the card busy, 4 ms from start to present, 7 ms until shown)
function New-Capture2([int]$menu, [int]$play, [string]$mode = 'Hardware: Independent Flip') {
    $f = "$Work\capture2-$menu-$play.csv"; $rows = New-Object Collections.Generic.List[string]
    $rows.Add('Application,ProcessID,PresentMode,MsBetweenPresents,MsCPUBusy,MsGPUBusy,MsUntilDisplayed')
    for ($i = 0; $i -lt $menu * 60; $i++) { $rows.Add("TestGame.exe,100,$mode,16.6667,16.0,3.0,5.0") }
    for ($i = 0; $i -lt $play * 125; $i++) { $rows.Add("TestGame.exe,100,$mode,8.0,4.0,6.0,7.0") }
    $rows | Set-Content $f; $f
}
'{"C:\\\\g\\\\s.txt":{"values":{"MaxFpsInMenu@0":"60","MaxFpsOutOfFocus@0":"30"}}}' | Set-Content "$Work\game-settings.json"
[void](Invoke-Sample (New-Capture2 30 30) -at $now.AddHours(1) -Force); $s = @(Hist)[-1]
Check 'the seconds at the menu''s frame cap are left out: the minute reads as the play in it' ($s.frames -eq 3750 -and [Math]::Abs($s.fps - 125) -lt 0.5 -and @($s.perSec | Where-Object { $_ -lt 100 }).Count -eq 0) "$($s.frames) frames, $($s.fps) fps"
Check 'the graphics card''s busy share of each frame (75% here: not the limit)' ($s.gpuBusy -eq 75) "$($s.gpuBusy)"
Check 'the delay from the frame''s start to the screen (what Reflex lowers)' ($s.latency -eq 11) "$($s.latency)"
Check 'how the frames reach the screen' ($s.presentMode -eq 'Hardware: Independent Flip') "$($s.presentMode)"
$n = @(Hist).Count; [void](Invoke-Sample (New-Capture2 50 10) -at $now.AddHours(2) -Force)
Check 'mostly in the menu (under 20 s of play left): not a sample' (@(Hist).Count -eq $n) ''
Clear-Path "$Work\game-settings.json"
[void](Invoke-Sample (New-Capture2 30 30) -at $now.AddHours(3) -Force)
Check 'a game without known menu caps: every second counts (nothing guessed)' (@(Hist)[-1].frames -eq 5550) "$(@(Hist)[-1].frames)"

Section 'the card barely drawing (10/25: tabbed out at 40 fps, 3% busy, read as a slow match)'
$f = "$Work\capture-idle.csv"; $rows = New-Object Collections.Generic.List[string]; $rows.Add('Application,ProcessID,PresentMode,MsBetweenPresents,MsCPUBusy,MsGPUBusy,MsUntilDisplayed')
for ($i = 0; $i -lt 2400; $i++) { $rows.Add('TestGame.exe,100,Composed: Flip,25.0,2.0,1.0,5.0') }; $rows | Set-Content $f
$n = @(Hist).Count; [void](Invoke-Sample $f -at $now.AddHours(4) -Force)
Check 'the card busy under a quarter of each frame: not a sample (nothing recorded)' (@(Hist).Count -eq $n) "$(@(Hist)[-1].fps) fps, $(@(Hist)[-1].gpuBusy)%"

Section 'the connection while playing (10/25): pings through the minute, next to the frame rate'
$pings = @(20) * 100 + @(90, 95)   # 102 answers: steady 20 ms with two spikes
[void](& $gp -TestCsv $cap -TestGame 'TestGame' -TestGpu @('70, 98, Not Active, Not Active, Not Active') -History $hf -Now $now.AddHours(5) -Force -Tune "$Work\game-tune.json" -GameSettings "$Work\game-settings.json" `
        -TestNet @{ net = $pings; netLost = 3; gw = @(1) * 60; gwLost = 0; wifi = $false })
$s = @(Hist)[-1]
Check 'the internet: median ping, jitter, loss % and lag spikes' ($s.netPing -eq 20 -and $s.netLoss -eq 2.9 -and $s.netSpikes -eq 2 -and $s.netJitter -gt 0) "ping $($s.netPing) loss $($s.netLoss) spikes $($s.netSpikes) jitter $($s.netJitter)"
Check 'the router (the home network) and wired or Wi-Fi' ($s.gwPing -eq 1 -and $s.gwLoss -eq 0 -and $s.wifi -eq $false) "gw $($s.gwPing)/$($s.gwLoss) wifi $($s.wifi)"
[void](& $gp -TestCsv $cap -TestGame 'TestGame' -TestGpu @('70, 98, Not Active, Not Active, Not Active') -History $hf -Now $now.AddHours(6) -Force -Tune "$Work\game-tune.json" -GameSettings "$Work\game-settings.json" -TestNet @{ net = @(20, 21); netLost = 0 })
$s = @(Hist)[-1]
Check 'too few pings (offline, a firewall): nothing said about the connection' ($s.frames -eq 900 -and [datetime]$s.date -gt $now.AddHours(5.5) -and $null -eq $s.netPing -and $null -eq $s.netLoss) "$($s.netPing)"
Finish
