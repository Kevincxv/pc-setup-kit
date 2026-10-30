# game-tune.ps1: each speed-only setting of a game tried both ways in the owner's matches, the faster one kept.
# A made-up settings file, made-up measured minutes (perf-history.json) and made-up conditions; nothing real is read.
. "$PSScriptRoot\..\lib.ps1"
$gt = "$Src\game-tune.ps1"
if (-not (Test-Path $gt)) { Skip 'game-tune' 'not installed here'; Finish }
$now = Get-Date
$cfg = "$Work\s.1.0.cod26.txt"; $gsf = "$Work\game-settings.json"; $pf = "$Work\perf-history.json"; $sf = "$Work\game-tune.json"; $gws = "$Work\gpu-state.json"; $opt = "$Work\kit-options.txt"
$cond = 'D1|B1|6000 MT/s|off'
function New-Setup {
    @('// Enable Nvidia low latency mode', 'NvidiaReflex@0;33761;11445 = Enabled + boost // one of Disabled, Enabled, Enabled + boost',
        '// Set a target fraction of your PC''s video memory', 'VideoMemoryScaleMP@0;59710;7707 = 0.850000 // 0.000000 to 2.000000',
        '// Thread count for handling the job queue', 'RendererWorkerCount@0;51989;59387 = 9 // -1 to 16', 'ShadowQuality@0;3981;58629 = Low // one of Low, High') | Set-Content $cfg
    $kept = [ordered]@{ 'NvidiaReflex@0' = 'Enabled + boost'; 'VideoMemoryScaleMP@0' = '0.850000'; 'RendererWorkerCount@0' = '9'; 'ShadowQuality@0' = 'Low' }
    ConvertTo-Json -InputObject ([ordered]@{ $cfg = [ordered]@{ at = $now.ToString('o'); values = $kept }; driver = 'D1' }) -Depth 4 | Set-Content $gsf
    '[]' | Set-Content $pf; Clear-Path $sf; '{}' | Set-Content $gws; '' | Set-Content $opt
}
function GT([datetime]$at, [string]$run = 'no', [string]$c = $cond) { @(& $gt -Files $cfg -State $sf -Perf $pf -GameSettings $gsf -GpuState $gws -Running $run -Conditions $c -Cores 8 -Now $at -Options $opt) }
function Add-Min([datetime]$at, [string]$tune, [double]$fps, [double]$low, [string]$drv = 'D1', [double]$lat = 0) {
    $h = @(Get-Content $pf -Raw | ConvertFrom-Json | ForEach-Object { $_ })
    $m = [ordered]@{ date = $at.ToString('o'); game = 'cod'; fps = $fps; low1 = $low; stutters = 2; tune = $tune; driver = $drv; build = 'B1'; ram = '6000 MT/s'; hvci = 'off' }
    if ($lat) { $m.latency = $lat }
    $h += [pscustomobject]$m
    ConvertTo-Json -InputObject @($h) -Depth 3 | Set-Content $pf
}
function Val([string]$key) { foreach ($l in Get-Content $cfg) { if ($l -match "^$([regex]::Escape($key));\d+;\d+ = ([^/]*?)\s*(//.*)?$") { return $Matches[1].Trim() } } }
function Kept([string]$key) { (Get-Content $gsf -Raw | ConvertFrom-Json).$cfg.values.$key }
function St { Get-Content $sf -Raw | ConvertFrom-Json }

Section 'a test from start to finish: Reflex Boost'
New-Setup; $t = $now.AddDays(-10)
$o = GT $t
Check 'the first setting to try is said, with both values (nothing changed yet: the value it has now goes first)' ("$o" -match 'trying Reflex Boost both ways .+Reflex Boost on \(as now\) against Reflex Boost off' -and (St).active.arm -eq 'a' -and (Val 'NvidiaReflex@0') -eq 'Enabled + boost') "$o"
Add-Min $t.AddMinutes(30) 'reflex:a' 200 150; $o = GT $t.AddHours(1)
Check 'one minute on it: no switch yet' ((St).active.arm -eq 'a' -and (Val 'NvidiaReflex@0') -eq 'Enabled + boost') "$o"
Add-Min $t.AddMinutes(60) 'reflex:a' 202 152
[void](GT $t.AddHours(2) -run 'yes')
Check 'two minutes, but the game is open: not switched (it writes its settings when it closes)' ((Val 'NvidiaReflex@0') -eq 'Enabled + boost') ''
$o = GT $t.AddHours(3)
Check 'two minutes and the game closed: switched to the other value, quietly' (-not $o -and (St).active.arm -eq 'b' -and (Val 'NvidiaReflex@0') -eq 'Enabled') "$o"
Check '... and the settings guard''s kept copy follows (it does not put the old value back)' ((Kept 'NvidiaReflex@0') -eq 'Enabled') "$(Kept 'NvidiaReflex@0')"
Check '... the rest of the file untouched' ((Val 'ShadowQuality@0') -eq 'Low' -and (Get-Content $cfg) -match '^NvidiaReflex@0;33761;11445 = Enabled // one of') ''
$d = $t.AddDays(1)
Add-Min $d 'reflex:b' 205 165; Add-Min $d.AddMinutes(30) 'reflex:b' 204 166; [void](GT $d.AddHours(1))
Check 'two on the other: back to the first (a, b, a, b - one evening does not decide it)' ((St).active.arm -eq 'a' -and (Val 'NvidiaReflex@0') -eq 'Enabled + boost') ''
$d = $t.AddDays(2)
Add-Min $d 'reflex:a' 198 149; Add-Min $d.AddMinutes(30) 'reflex:a' 201 151; [void](GT $d.AddHours(1))
Add-Min $d.AddHours(2) 'reflex:b' 206 167; Add-Min $d.AddHours(3) 'reflex:b' 203 164
Add-Min $d.AddHours(3).AddMinutes(30) 'reflex:a' 999 999 'D0'   # (a minute from other conditions: never counted)
$o = GT $d.AddHours(4)
Check '4 minutes each, the other value clearly smoother: switched to it, said with the numbers' ("$o" -match 'Reflex Boost off is faster on this PC than Reflex Boost on - 1% low 15\d -> 16\d fps \(\+10%\), average 20\d -> 20\d fps \(\+2%\) over 4 minutes of play each; switched to it' -and (Val 'NvidiaReflex@0') -eq 'Enabled' -and (Kept 'NvidiaReflex@0') -eq 'Enabled') "$o"
$r = @((St).done)[-1]
Check '... the result kept for the app (both values, numbers, which one stayed)' ($r.id -eq 'reflex' -and $r.kept -eq 'Enabled' -and $r.aLow -eq 150.5 -and $r.bLow -eq 165.5 -and $r.aN -eq 4 -and -not (St).active) ($r | ConvertTo-Json -Compress)

Section 'Reflex Boost judged on the delay to the screen (10/22)'
New-Setup; $t = $now.AddDays(-12)
function Run-Reflex([double]$fa, [double]$la, [double]$ya, [double]$fb, [double]$lb, [double]$yb) {
    [void](GT $t)
    foreach ($k in 0..1) { foreach ($i in 0..1) { Add-Min $t.AddDays($k * 2).AddHours($i) 'reflex:a' $fa $la 'D1' $ya }; [void](GT $t.AddDays($k * 2).AddHours(3))
        foreach ($i in 0..1) { Add-Min $t.AddDays($k * 2 + 1).AddHours($i) 'reflex:b' $fb $lb 'D1' $yb }; $script:o = GT $t.AddDays($k * 2 + 1).AddHours(3) }
}
Run-Reflex 200 150 12 199 149 10.5
Check 'the other value: about the same frame rate but clearly less delay - switched to it, said with the delay' ("$o" -match 'Reflex Boost off is faster on this PC than Reflex Boost on - delay to the screen 12 -> 10.5 ms \(-1[23]%\)' -and (Val 'NvidiaReflex@0') -eq 'Enabled' -and @((St).done)[-1].bLatency -eq 10.5) "$o"
New-Setup
Run-Reflex 200 150 12 215 165 11.8
Check 'more frames but about the same delay: no faster (the frame rate alone does not decide Reflex)' ("$o" -match 'was no faster than Reflex Boost on \(delay to the screen 12 -> 11.8 ms' -and (Val 'NvidiaReflex@0') -eq 'Enabled + boost') "$o"
New-Setup
Run-Reflex 200 150 12 190 140 10
Check 'less delay but the 1% low 3%+ lower: no faster' ("$o" -match 'was no faster' -and (Val 'NvidiaReflex@0') -eq 'Enabled + boost') "$o"

Section 'the next setting: no better, so the owner''s stays'
$t = $now.AddDays(-6)
$o = GT $t
Check 'the next one starts by itself' ("$o" -match 'trying the video memory budget both ways in your next matches - an 85% video memory budget \(as now\) against a 75% video memory budget' -and (St).active.id -eq 'vram') "$o"
foreach ($i in 0..1) { Add-Min $t.AddHours($i) 'vram:a' 200 150 }; [void](GT $t.AddHours(2))
foreach ($i in 3..4) { Add-Min $t.AddHours($i) 'vram:b' 201 151 }; [void](GT $t.AddHours(5))
foreach ($i in 6..7) { Add-Min $t.AddHours($i) 'vram:a' 199 149 }; [void](GT $t.AddHours(8))
foreach ($i in 9..10) { Add-Min $t.AddHours($i) 'vram:b' 200 150 }
$o = GT $t.AddHours(11)
Check 'about the same: kept as it was, said' ("$o" -match 'a 75% video memory budget was no faster than an 85% video memory budget .+ - kept an 85% video memory budget' -and (Val 'VideoMemoryScaleMP@0') -eq '0.850000' -and (Kept 'VideoMemoryScaleMP@0') -eq '0.850000') "$o"

Section 'stopped part-way'
$t = $now.AddDays(-3)
$o = GT $t
Check 'the third one (renderer threads: tried with one per core)' ("$o" -match '9 renderer threads \(as now\) against 8 renderer threads') "$o"
Add-Min $t.AddHours(1) 'workers:a' 200 150; Add-Min $t.AddHours(2) 'workers:a' 200 150; [void](GT $t.AddHours(3))
Check '... on its second value' ((Val 'RendererWorkerCount@0') -eq '8') ''
$o = GT $t.AddHours(4) -c 'D2|B1|6000 MT/s|off'
Check 'a new graphics driver mid-test: stopped, the owner''s value back, said why' ("$o" -match 'test was stopped - something else changed' -and (Val 'RendererWorkerCount@0') -eq '9' -and (Kept 'RendererWorkerCount@0') -eq '9' -and -not (St).active) "$o"
$o = GT $t.AddHours(5) -c 'D2|B1|6000 MT/s|off'
Check '... and it is tried again (not counted as done)' ("$o" -match 'trying the renderer thread count' -and (St).active.env -eq 'D2|B1|6000 MT/s|off') "$o"
Add-Min $t.AddHours(6) 'workers:a' 200 150 'D2'; Add-Min $t.AddHours(7) 'workers:a' 200 150 'D2'; [void](GT $t.AddHours(8) -c 'D2|B1|6000 MT/s|off')
(Get-Content $cfg) -replace '^(RendererWorkerCount@0;\d+;\d+ = )8', '${1}12' | Set-Content $cfg
$o = GT $t.AddHours(9) -c 'D2|B1|6000 MT/s|off'
Check 'the owner changes it in the game: their value stays, that test ends' ("$o" -match 'you changed the renderer thread count yourself - your choice is kept' -and (Val 'RendererWorkerCount@0') -eq '12' -and -not (St).active) "$o"
$o = GT $t.AddHours(10) -c 'D2|B1|6000 MT/s|off'
Check 'everything tried: nothing more to do, nothing said' (-not $o -and -not (St).active) "$o"

Section 'when not to test'
New-Setup; $t = $now.AddDays(-2)
'{"trial":{"driver":"D2","from":"D1","since":"2026-01-01T00:00:00","verdict":null}}' | Set-Content $gws
$o = GT $t
Check 'a new graphics driver on trial: no test starts (its comparison needs the settings as they were)' (-not $o -and -not (Test-Path $sf)) "$o"
'{}' | Set-Content $gws
[void](GT $t); Add-Min $t.AddHours(1) 'reflex:a' 200 150; Add-Min $t.AddHours(2) 'reflex:a' 200 150; [void](GT $t.AddHours(3))
'{"resets":["' + $t.AddHours(4).ToString('yyyy-MM-ddTHH:mm') + '"]}' | Set-Content $gws
$o = GT $t.AddHours(5)
Check 'a driver reset during a test: the owner''s value back to be safe' ("$o" -match 'stopped responding during the Reflex Boost test - Reflex Boost on is back' -and (Val 'NvidiaReflex@0') -eq 'Enabled + boost') "$o"
New-Setup; $t = $now.AddDays(-40)
[void](GT $t); Add-Min $t.AddHours(1) 'reflex:a' 200 150; Add-Min $t.AddHours(2) 'reflex:a' 200 150; [void](GT $t.AddHours(3))
$o = GT $now
Check 'a month without enough play: ended, the owner''s value back' ("$o" -match 'not enough play in a month' -and (Val 'NvidiaReflex@0') -eq 'Enabled + boost') "$o"
New-Setup; $t = $now.AddDays(-2)
[void](GT $t); Add-Min $t.AddHours(1) 'reflex:a' 200 150; Add-Min $t.AddHours(2) 'reflex:a' 200 150; [void](GT $t.AddHours(3))
'gametune=off' | Set-Content $opt
$o = GT $t.AddHours(4)
Check 'switched off in Settings: a test under way ends with the owner''s value back' ("$o" -match 'switched off - Reflex Boost on is back' -and (Val 'NvidiaReflex@0') -eq 'Enabled + boost' -and (Kept 'NvidiaReflex@0') -eq 'Enabled + boost') "$o"
$o = GT $t.AddHours(5)
Check '... and nothing more while it is off' (-not $o -and -not (St).active) "$o"
'' | Set-Content $opt
New-Setup; Add-Content $cfg 'GPUUploadHeaps@0;57752;20945 = true'
$o = GT $now.AddDays(-1)
Check 'GPU upload heaps (10/22): tried first, on against off' ("$o" -match 'trying GPU upload heaps both ways .+GPU upload heaps on \(as now\) against GPU upload heaps off' -and (St).active.id -eq 'uploadheaps') "$o"
$o = @(& $gt -Files @("$Work\missing.txt") -State "$Work\none.json" -Perf $pf -GameSettings $gsf -GpuState $gws -Running 'no' -Conditions $cond -Cores 8 -Now $now -Options $opt)
Check 'the game not installed: nothing' (-not $o -and -not (Test-Path "$Work\none.json")) "$o"
Finish
