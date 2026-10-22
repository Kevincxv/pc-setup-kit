# bench.ps1: the benchmark button - results kept and compared with the run before. Made-up results (-Test); WinSAT
# isn't run.
. "$PSScriptRoot\..\lib.ps1"
$bp = "$Src\bench.ps1"
if (-not (Test-Path $bp)) { Skip 'bench' 'not installed here'; Finish }
$hf = "$Work\benchmarks.json"; $rf = "$Work\bench-running.txt"
'[{"date":"2026-09-26","cpu":9.3,"memory":9.3,"memBandwidthMBs":63102,"biosVersion":"3.20"}]' | Set-Content $hf
function B([hashtable]$t) { @(& $bp -Test $t -History $hf -Running $rf) }
$o = B @{ Cpu = 1511.3; CpuOne = 139.1; Mem = 52985; Disk = 1001; Ram = '4800 MT/s'; Game = '' }
$h = @(Get-Content $hf -Raw | ConvertFrom-Json | ForEach-Object { $_ })
Check 'a run: kept after the ones before (the old baseline stays the first)' ($h.Count -eq 2 -and $h[0].date -eq '2026-09-26' -and $h[1].memBandwidthMBs -eq 52985 -and $h[1].ram -eq '4800 MT/s') ($h | ConvertTo-Json -Compress)
Check '... said with each number against the run before (the memory 16% under the EXPO baseline)' ("$o" -match '^Benchmark: processor 1511 MB/s all cores, 139 MB/s one core; memory 52985 MB/s \(-16% vs 63102\); SSD 1001 MB/s reading - RAM at 4800 MT/s') "$o"
$o = B @{ Cpu = 1530; CpuOne = 141; Mem = 63500; Disk = 1005; Ram = '6000 MT/s'; Game = '' }
Check 'the next run against this one (EXPO on: +20% memory)' ("$o" -match 'processor 1530 MB/s all cores \(\+1% vs 1511\).+memory 63500 MB/s \(\+20% vs 52985\)') "$o"
Check '... and the "running" mark is gone afterwards (the app shows it while it runs)' (-not (Test-Path $rf)) ''
$o = B @{ Game = 'cod' }
Check 'a game running: not run, said why' ("$o" -match '^Benchmark: close cod first') "$o"
$o = B @{ Cpu = $null; Mem = $null; Game = '' }
Check 'no results from WinSAT: said, nothing kept' ("$o" -match 'gave no results' -and @(Get-Content $hf -Raw | ConvertFrom-Json | ForEach-Object { $_ }).Count -eq 3) "$o"
Finish
