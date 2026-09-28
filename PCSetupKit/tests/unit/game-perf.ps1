# game-perf.ps1: one minute of a game's frame times (PresentMon's CSV) and the graphics card's heat -> perf-history.json.
# A recorded capture and nvidia-smi rows stand in for the real ones; nothing is captured or downloaded.
. "$PSScriptRoot\..\lib.ps1"
$gp = "$Src\game-perf.ps1"
if (-not (Test-Path $gp)) { Skip 'game-perf' 'not installed here'; Finish }
$now = Get-Date
# a capture: $n frames of the game at 8 ms (125 fps) with $slow hitches of 60 ms, plus another app's frames
function New-Capture([int]$n = 900, [int]$slow = 12, [string]$app = 'TestGame.exe') {
    $f = "$Work\capture-$n-$slow.csv"
    $rows = @('Application,ProcessID,MsBetweenPresents')
    for ($i = 0; $i -lt $n; $i++) { $rows += "$app,100,$(if ($i % [Math]::Max(1, [int]($n / [Math]::Max(1, $slow))) -eq 0 -and $slow) { '60.0' } else { '8.0' })" }
    for ($i = 0; $i -lt 200; $i++) { $rows += 'Browser.exe,200,2.0' }
    $rows | Set-Content $f; $f
}
$hf = "$Work\perf-history.json"
function Invoke-Sample([string]$csv, [string[]]$gpu = @('70, 98, Not Active, Not Active, Not Active'), [datetime]$at = $now, [switch]$Force) {
    @(& $gp -TestCsv $csv -TestGame 'TestGame' -TestGpu $gpu -History $hf -Now $at -Force:$Force)
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
Check 'the driver and Windows build recorded (a change there explains a change here)' ($s.build -match '^\d+\.\d+$' -and $null -ne $s.driver) "$($s.driver) / $($s.build)"

Section 'when not to sample'
[void](Invoke-Sample $cap -at $now.AddHours(1))
Check 'the same game again within 3 hours: skipped' (@(Hist).Count -eq 1) ''
[void](Invoke-Sample $cap -at $now.AddHours(4))
Check '... and sampled after 3 hours' (@(Hist).Count -eq 2) ''
$o = Invoke-Sample (New-Capture 150 0) -at $now.AddHours(8)
Check 'too few frames (a menu, loading, alt-tabbed): not a sample' (@(Hist).Count -eq 2 -and -not $o) "$o"
[void](Invoke-Sample (New-Capture 900 0) @('55, 40') -at $now.AddHours(12))
Check 'an older driver without throttle fields: temperature and load still read' (@(Hist)[-1].gpuTemp -eq 55 -and -not @(Hist)[-1].throttle) ''
Finish
