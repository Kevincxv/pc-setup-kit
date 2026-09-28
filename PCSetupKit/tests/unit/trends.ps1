# trends.ps1: health over time vs this PC's own normal - start-up time (and what slowed it), C: filling up, graphics
# card warmer at idle, SSD wear - with the event log, disks and nvidia-smi mocked and a made-up history.
. "$PSScriptRoot\..\lib.ps1"
$trendsScript = "$Src\trends.ps1"
if (-not (Test-Path $trendsScript)) { Skip 'trends' 'not installed here'; Finish }
$mocked = 'Get-WinEvent', 'Get-PSDrive', 'Get-Partition', 'Get-Disk', 'Get-StorageReliabilityCounter', 'nvidia-smi'
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
function Get-PSDrive { [pscustomobject]@{ Free = $TR.FreeGB * 1GB } }
function Get-Partition { 'part' }
function Get-Disk { 'disk' }
function Get-StorageReliabilityCounter { [pscustomobject]@{ Wear = $TR.Wear; Temperature = 45 } }
function nvidia-smi { "$($TR.Gpu), $($TR.GpuUse)" }
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
function Reset-T { $global:TR = @{ Boot = (Ev 100 $now.AddMinutes(-3) @{ BootTime = 26500 }); Slowed = @(); FreeGB = 500; Wear = 2; Gpu = 30; GpuUse = 3 } }
function T { @(& $trendsScript -History $hf -Now $now) }
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
Reset-T; New-History -gpuThen 31 -gpuNow 43; $TR.Gpu = 44; $o = T
Check 'graphics card 10+ C warmer at idle than a month ago: a dust reminder' ($o -match '^Reminder: the graphics card runs \d+ C warmer at idle than a month ago \(43 C, was 31 C\)') ($o -join ' / ')
Reset-T; New-History; $TR.Wear = 9; $o = T
Check 'SSD wore 7 % in a month: a reminder' ($o -match '^Reminder: the SSD wore 7% in a month') ($o -join ' / ')

Section 'first days (no history yet)'
Reset-T; [IO.File]::Delete($hf); $o = T
Check 'no history: records, says nothing, no errors (saved as a list even with one entry)' (-not $o -and (Test-Path $hf) -and (Get-Content $hf -Raw).TrimStart().StartsWith('[')) ($o -join ' / ')
'not json' | Set-Content $hf; $o = T
Check 'a broken history file: starts over, no errors' (-not $o -and @(Hist).Count -eq 1) ''
Finish
