# trends.ps1: health over time vs this PC's own normal - start-up time (and what slowed it), C: filling up, graphics
# card warmer at idle, SSD wear - with the event log, disks and nvidia-smi mocked and a made-up history.
. "$PSScriptRoot\..\lib.ps1"
$trendsScript = "$Src\trends.ps1"
if (-not (Test-Path $trendsScript)) { Skip 'trends' 'not installed here'; Finish }
$mocked = 'Get-WinEvent', 'Get-PSDrive', 'Get-Partition', 'Get-Disk', 'Get-StorageReliabilityCounter', 'nvidia-smi', 'Get-CimInstance'
if (-not (Test-Tripwire $trendsScript $mocked)) { Finish }
Import-MockTargets $mocked
$now = Get-Date
function Ev($id, [datetime]$t, [hashtable]$data) {
    $x = '<Event><EventData>' + (($data.Keys | ForEach-Object { "<Data Name='$_'>$($data[$_])</Data>" }) -join '') + '</EventData></Event>'
    $e = [pscustomobject]@{ Id = $id; TimeCreated = $t; Xml = $x }; $e | Add-Member ScriptMethod ToXml { $this.Xml }; $e
}
function Get-WinEvent { param($FilterHashtable, $MaxEvents, $ErrorAction)
    if ($FilterHashtable.Id -eq 100) { return $TR.Boot }
    @($TR.Slowed | Where-Object { $_.TimeCreated -ge $FilterHashtable.StartTime -and $_.TimeCreated -le $FilterHashtable.EndTime }) }
function Get-PSDrive { [pscustomobject]@{ Free = $TR.FreeGB * 1GB; Used = $(if ($TR.SizeGB) { ($TR.SizeGB - $TR.FreeGB) * 1GB }) } }
function Get-Partition { 'part' }
function Get-CimInstance { [pscustomobject]@{ LoadPercentage = $TR.CpuLoad } }
function Get-Disk { 'disk' }
function Get-StorageReliabilityCounter { [pscustomobject]@{ Wear = $TR.Wear; Temperature = 45; TemperatureMax = $TR.TempMax; ReadErrorsUncorrected = $TR.Errors } }
function nvidia-smi { "$($TR.Gpu), $($TR.GpuUse)$(if ($null -ne $TR.Fan) { ", $($TR.Fan)" })" }
if (-not (Assert-Mocks $mocked)) { Finish }
$hf = "$Work\health-history.json"
# a history: one check a day for 40 days, a boot each day of about 26 s, stable disk, GPU 30 C idle, SSD 2 % worn
function New-History([double]$gpuThen = 30, [double]$gpuNow = 30, [double]$freeThen = 500, [double]$freeNow = 500) {
    $rows = for ($i = 40; $i -ge 1; $i--) {
        $d = $now.AddDays(-$i)
        [ordered]@{ date = $d.ToString('o'); bootAt = $d.AddMinutes(-2).ToString('o'); boot = 26 + ($i % 3) * 0.5
            freeGB = $freeThen + ($freeNow - $freeThen) * (40 - $i) / 39; ssdWear = 2; gpuIdle = $(if ($i -le 7) { $gpuNow } else { $gpuThen }) }
    }
    $rows | ConvertTo-Json | Set-Content $hf
}
function Reset-T { $global:TR = @{ Boot = (Ev 100 $now.AddMinutes(-3) @{ BootTime = 26500 }); Slowed = @(); FreeGB = 500; Wear = 2; Gpu = 30; GpuUse = 3; CpuLoad = 4; CpuT = $null } }
$pf = "$Work\perf-history.json"   # (games: none unless a test writes some)
function T { $v = $TR.CpuT; @(& $trendsScript -History $hf -PerfHistory $pf -Now $now -CpuReader { $v }.GetNewClosure()) }
function Hist { $j = Get-Content $hf -Raw | ConvertFrom-Json; @($j | ForEach-Object { $_ }) }   # (PowerShell 5.1 returns a JSON array as one item)

Section 'a normal day'
Reset-T; New-History; $o = T
Check 'nothing unusual: says nothing' (-not $o) ($o -join ' / ')
$last = (Hist)[-1]
Check 'this check is recorded (start-up, free space, SSD, GPU at idle)' ($last.boot -eq 26.5 -and $last.freeGB -eq 500 -and $last.ssdWear -eq 2 -and $last.gpuIdle -eq 30) ($last | ConvertTo-Json -Compress)
Reset-T; New-History; $TR.GpuUse = 85; [void](T)
Check '... a busy graphics card (a game) is not recorded as idle temperature' ($null -eq (Hist)[-1].gpuIdle) ''

Section 'slow start-up'
Reset-T; New-History; $TR.Boot = Ev 100 $now.AddMinutes(-3) @{ BootTime = 48000 }
$TR.Slowed = @((Ev 101 $now.AddMinutes(-2) @{ FriendlyName = 'Steam Client WebHelper'; DegradationTime = 9400 }), (Ev 103 $now.AddMinutes(-2) @{ FriendlyName = 'Some Updater Service'; DegradationTime = 6100 }),
    (Ev 101 $now.AddHours(-5) @{ FriendlyName = 'An Old Boot'; DegradationTime = 50000 }))
$o = T
Check 'much slower than usual: a Reminder with the time and the usual time' ($o -match '^Reminder: this start-up was slow - 48 s \(usually 26\.5 s\)') ($o -join ' / ')
Check '... naming what slowed it, worst first (only this start-up''s)' ($o -match 'slowed by: Steam Client WebHelper \(\+9\.4 s\), Some Updater Service \(\+6\.1 s\)$') ($o -join ' / ')
[void](T); $TR.Boot = Ev 100 $now.AddMinutes(-1) @{ BootTime = 47000 }; [void](T); $TR.Boot = Ev 100 $now @{ BootTime = 49000 }; $o = T
Check 'slow three start-ups in a row: WARNING (it gets looked at)' ($o -match '^WARNING: start-up has been slow 3 times in a row') ($o -join ' / ')
Reset-T; New-History; $TR.Boot = Ev 100 $now.AddMinutes(-3) @{ BootTime = 33000 }; $o = T
Check 'a few seconds slower (not 1.5x and 10 s): nothing' (-not $o) ($o -join ' / ')

Section 'disk space, temperature, SSD wear'
Reset-T; New-History -freeThen 400 -freeNow 60; $TR.FreeGB = 55; $o = T
Check 'C: filling fast: WARNING with the pace and the days left' ($o -match '^WARNING: C: is filling up - 55 GB free, about \d+ GB less each week; nearly full in about \d+ days') ($o -join ' / ')
# one big install (1.1 TB between two checks, fast enough that the old pace math said "full in 27 days") with 1 TB free: not a pace; the same drop with little space left still warns
function Jump([double]$then, [double]$now2) { $r = Get-Content $hf -Raw | ConvertFrom-Json; foreach ($x in $r) { $x.freeGB = $(if ([datetime]$x.date -lt $now.AddDays(-3)) { $then } else { $now2 }) }; $r | ConvertTo-Json | Set-Content $hf }
Reset-T; New-History; Jump 2300 1150; $TR.FreeGB = 1142; $o = T
Check 'one big install with plenty of space: no filling-up line' (-not ($o -match 'filling up')) ($o -join ' / ')
Reset-T; New-History; Jump 200 90; $TR.FreeGB = 85; $o = T
Check '... but a big install leaving under 100 GB still warns' ($o -match 'C: is filling up - 85 GB free') ($o -join ' / ')
# 10/10: several big games in one week on a 2 TB drive (1262 > 1149 GB free over a few checks) said "nearly full in about 27 days"
# (several installs in the last days, none big enough to count as "one install": the old math projects under 30 days)
function Steps([double]$then, [double[]]$recent) { $r = Get-Content $hf -Raw | ConvertFrom-Json; $n = @($r).Count
    for ($i = 0; $i -lt $n; $i++) { $k = $i - ($n - $recent.Count); @($r)[$i].freeGB = $(if ($k -ge 0) { $recent[$k] } else { $then }) }; $r | ConvertTo-Json | Set-Content $hf }
Reset-T; New-History; Steps 2300 @(2000, 1700, 1400, 1160); $TR.FreeGB = 1149; $TR.SizeGB = 3726; $o = T
Check 'a week of game installs with over a quarter of the drive free: no filling-up line' (-not ($o -match 'filling up')) ($o -join ' / ')
Check '... and the drive size is recorded' ((Hist)[-1].sizeGB -eq 3726) ((Hist)[-1] | ConvertTo-Json -Compress)
Reset-T; New-History; Steps 2300 @(2000, 1700, 1400, 1160); $TR.FreeGB = 1149; $o = T
Check '... (without the drive size - an older history - it says what it said before)' ($o -match 'C: is filling up - 1149 GB free') ($o -join ' / ')
Reset-T; New-History; Steps 400 @(330, 260, 200, 160); $TR.FreeGB = 150; $TR.SizeGB = 1863; $o = T
Check '... the same pace with under a quarter free still warns' ($o -match 'C: is filling up - 150 GB free') ($o -join ' / ')
Reset-T; New-History -gpuThen 31 -gpuNow 43; $TR.Gpu = 44; $o = T
Check 'graphics card 10+ C warmer at idle than a month ago: a dust reminder' ($o -match '^Reminder: the graphics card runs \d+ C warmer at idle than a month ago \(43 C, was 31 C\)') ($o -join ' / ')
Reset-T; New-History; $TR.Wear = 9; $o = T
Check 'SSD wore 7 % in a month: a reminder' ($o -match '^Reminder: the SSD wore 7% in a month') ($o -join ' / ')
Reset-T; New-History; $TR.TempMax = 72; $TR.Fan = 30; $o = T
Check 'the SSD''s hottest ever and the card''s fan at idle are recorded; under 80 C: nothing said' (-not $o -and (Hist)[-1].ssdTempMax -eq 72 -and (Hist)[-1].gpuIdleFan -eq 30) ($o -join ' / ')
$TR.TempMax = 86; $o = T
Check 'the SSD''s hottest ever reaches 86 C: said, with what helps' ([bool]($o -match '^Reminder: the SSD has reached 86 C at its hottest - it slows itself down from about 80 C\. A heatsink')) ($o -join ' / ')
$o = T
Check '... once (the same peak again: nothing)' (-not ($o -match 'hottest')) ($o -join ' / ')
$TR.TempMax = 88; $o = T
Check '... and again when it goes higher' ([bool]($o -match 'reached 88 C')) ($o -join ' / ')
Reset-T; [IO.File]::Delete($hf); $TR.TempMax = 86; $o = T
Check 'already 80 C+ at the very first check: said (the drive has been that hot before)' ([bool]($o -match 'reached 86 C')) ($o -join ' / ')
Reset-T; New-History; $TR.Errors = 0; [void](T); $TR.Errors = 3; $o = T
Check 'data the SSD could not read back, rising: WARNING to back up' ([bool]($o -match '^WARNING: the SSD could not read back data 3 more time\(s\)')) ($o -join ' / ')
$o = T
Check '... not again while it stays the same' (-not ($o -match 'read back')) ($o -join ' / ')

Reset-T; New-History; $TR.CpuT = 41; [void](T)
Check 'the processor at idle recorded (once its temperature driver is on)' ((Hist)[-1].cpuIdle -eq 41) ((Hist)[-1] | ConvertTo-Json -Compress)
Reset-T; New-History; $TR.CpuT = 70; $TR.CpuLoad = 60; [void](T)
Check '... not while the processor is busy (it would skew it)' ($null -eq (Hist)[-1].cpuIdle) ''
Reset-T; New-History; $r = Get-Content $hf -Raw | ConvertFrom-Json; foreach ($x in $r) { $x | Add-Member cpuIdle $(if ([datetime]$x.date -gt $now.AddDays(-7)) { 53 } else { 41 }) }; $r | ConvertTo-Json | Set-Content $hf
$TR.CpuT = 54; $o = T
Check 'the processor 10+ C warmer at idle than a month ago: a dust reminder for the CPU cooler' ([bool]($o -match '^Reminder: the processor runs 12 C warmer at idle than a month ago \(53 C, was 41 C\)')) ($o -join ' / ')

Section 'first days (no history yet)'
Reset-T; [IO.File]::Delete($hf); $o = T
Check 'no history: records, says nothing, no errors (saved as a list even with one entry)' (-not $o -and (Test-Path $hf) -and (Get-Content $hf -Raw).TrimStart().StartsWith('[')) ($o -join ' / ')
'not json' | Set-Content $hf; $o = T
Check 'a broken history file: starts over, no errors' (-not $o -and @(Hist).Count -eq 1) ''

Section 'games (perf-history.json from game-perf.ps1)'
# samples of one game, one a day: $changeAt days ago the driver (or Windows build) changed and the numbers with it
function New-Perf([int]$changeAt = 3, [double]$fpsAfter = 118, [double]$lowAfter = 70, [int]$tempAfter = 72, [string]$thrAfter, [switch]$Build, [int]$days = 10) {
    $rows = for ($i = $days; $i -ge 1; $i--) {
        $new = $i -le $changeAt
        [ordered]@{ date = $now.AddDays(-$i).ToString('o'); game = 'TestGame'; fps = $(if ($new) { $fpsAfter } else { 140 }); low1 = $(if ($new) { $lowAfter } else { 92 })
            gpuTemp = $(if ($new) { $tempAfter } else { 72 }); throttle = $(if ($new) { $thrAfter }); ssdTemp = 50
            driver = $(if ($new -and -not $Build) { '2.0' } else { '1.0' }); build = $(if ($new -and $Build) { '26200.2' } else { '26200.1' }) }
    }
    ConvertTo-Json -InputObject @($rows) | Set-Content $pf
}
Reset-T; New-History
New-Perf -changeAt 0; $o = T
Check 'steady games: nothing said' (-not $o) ($o -join ' / ')
New-Perf; $o = T
Check 'slower since a driver update: named, with before -> after' ([bool]($o -match '^Reminder: TestGame runs slower since the graphics driver update to 2\.0 - 1% lows 92 -> 70 fps, average 140 -> 118 fps')) ($o -join ' / ')
New-Perf -Build; $o = T
Check '... or since a Windows update' ([bool]($o -match 'runs slower since the Windows update to build 26200\.2')) ($o -join ' / ')
New-Perf -fpsAfter 136 -lowAfter 88; $o = T
Check 'a small change (normal variation): nothing' (-not ($o -match 'runs slower')) ($o -join ' / ')
New-Perf -changeAt 1; $o = T
Check 'only one sample since the change: not judged yet' (-not ($o -match 'runs slower')) ($o -join ' / ')
New-Perf -changeAt 20 -days 30; $o = T
Check 'a change weeks ago: no longer repeated' (-not ($o -match 'runs slower')) ($o -join ' / ')
New-Perf -changeAt 3 -fpsAfter 140 -lowAfter 92 -tempAfter 87 -thrAfter 'heat'; $o = T
Check 'hot and throttling while gaming: said, with what to do' ([bool]($o -match '^Reminder: the graphics card gets hot while gaming \(up to 87 C, and slows itself down to cool off\) - clean the dust')) ($o -join ' / ')
function Cpu-Perf([int[]]$limits) {
    $i = $limits.Count; $rows = foreach ($l in $limits) { [ordered]@{ date = $now.AddHours(- $i--).ToString('o'); game = 'TestGame'; fps = 140; low1 = 92; gpuTemp = 70; cpuLimit = $l; driver = '1.0'; build = '26200.1' } }
    ConvertTo-Json -InputObject @($rows) | Set-Content $pf
}
Cpu-Perf @(100, 100, 100, 100); $o = T
Check 'the processor at full speed while gaming: nothing' (-not ($o -match 'processor')) ($o -join ' / ')
Cpu-Perf @(100, 84, 100, 76); $o = T
Check 'the processor held back while gaming in 2+ minutes: said, with what to check' ([bool]($o -match '^Reminder: the processor was held back to 76% of its speed while gaming \(2 of the last 4 measured minutes\) - nearly always heat')) ($o -join ' / ')
Cpu-Perf @(100, 84, 100, 100); $o = T
Check '... not for one minute' (-not ($o -match 'processor')) ($o -join ' / ')
$rows = @(foreach ($v in 75, 90, 91) { [ordered]@{ date = $now.AddHours(-1).ToString('o'); game = 'TestGame'; fps = 140; low1 = 92; gpuTemp = 70; cpuTemp = $v; driver = '1.0'; build = '26200.1' } }); ConvertTo-Json -InputObject $rows | Set-Content $pf
$o = T
Check 'the processor at its heat limit (88 C+) in 2+ minutes while gaming: said, with what to check' ([bool]($o -match '^Reminder: the processor reaches 91 C while gaming - at its limit')) ($o -join ' / ')
Clear-Path $pf
Finish
