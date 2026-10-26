# The benchmark button (10/22, the owner's request): the same short test every time, so "did EXPO / the new driver / the
# BIOS help?" gets an answer in about a minute and a half instead of a few matches. Windows' own WinSAT parts: the
# processor (all cores and one core), the memory's bandwidth, the SSD's reading speed - each run kept in benchmarks.json
# (the 9/26 baseline is the first) with what it depends on (RAM speed, BIOS, graphics driver, Windows), and compared with
# the run before and the first one. The graphics card isn't in it: the games measure it (Games > Performance).
# Started from the app (through the tray - WinSAT needs admin rights); never while a game runs.
# -Test (hashtable: Cpu, CpuOne, Mem, Disk, Ram, Game) / -History / -Running / -Now: tests (WinSAT isn't run).
param([hashtable]$Test, [string]$History = "$PSScriptRoot\benchmarks.json", [string]$Running = "$PSScriptRoot\bench-running.txt", [datetime]$Now = (Get-Date))
$ErrorActionPreference = 'SilentlyContinue'
$T = $Test
$game = if ($T) { $T.Game } else { & "$PSScriptRoot\game-check.ps1" }
if ($game) { "Benchmark: close $game first - it would skew the results"; return }
$Now.ToString('o') | Set-Content $Running
try {
    if ($T) { $cpu = $T.Cpu; $one = $T.CpuOne; $mem = $T.Mem; $disk = $T.Disk; $ram = $T.Ram }
    else {
        $w = Join-Path $env:TEMP "pckit-bench-$PID"; New-Item $w -ItemType Directory -Force | Out-Null
        function Metric([string]$file, [string]$name) { try { $x = [xml](Get-Content $file -Raw); [double]($x.SelectSingleNode("//$name").'#text') } catch { $null } }
        & winsat cpuformal -xml "$w\cpu.xml" | Out-Null
        & winsat mem -xml "$w\mem.xml" | Out-Null
        & winsat disk -seq -read -drive c -xml "$w\disk.xml" | Out-Null
        $cpu = Metric "$w\cpu.xml" 'CompressionMetric'; $one = Metric "$w\cpu.xml" 'CompressionMetricUP'
        $mem = Metric "$w\mem.xml" 'Bandwidth'; $disk = Metric "$w\disk.xml" 'AvgThroughput'
        Remove-Item $w -Recurse -Force
        $ram = "$((Get-CimInstance Win32_PhysicalMemory | Select-Object -First 1).ConfiguredClockSpeed) MT/s"
    }
    if (-not $cpu -and -not $mem) { 'Benchmark: WinSAT gave no results - try again (it needs the PC otherwise idle)'; return }
    $h = @(try { Get-Content $History -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { } ) | ForEach-Object { $_ } | Where-Object { $_.date }
    $e = [ordered]@{ date = $Now.ToString('s'); cpuMulti = [Math]::Round($cpu, 1); cpuSingle = [Math]::Round($one, 1); memBandwidthMBs = [int]$mem; diskReadMBs = [int]$disk; ram = $ram }
    if (-not $T) {
        $e.biosVersion = "$((Get-CimInstance Win32_BIOS).SMBIOSBIOSVersion)"
        $e.driver = "$((Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA|AMD|Radeon|Intel\(R\) Arc' } | Select-Object -First 1).DriverVersion)"
        $e.build = "$([Environment]::OSVersion.Version.Build).$((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR)"
    }
    $prev = $h | Select-Object -Last 1
    $all = @($h) + [pscustomobject]$e
    try { ConvertTo-Json -InputObject @($all) -Depth 3 | Set-Content "$History.tmp" -Encoding UTF8; Move-Item "$History.tmp" $History -Force } catch { }
    function Cmp($now, $then) { if ($then -and $now) { $p = [Math]::Round(($now - $then) / $then * 100); " ($(if ($p -ge 0) { '+' })$p% vs $([int]$then))" } }
    "Benchmark: processor $([int]$cpu) MB/s all cores$(Cmp $cpu $prev.cpuMulti), $([int]$one) MB/s one core$(Cmp $one $prev.cpuSingle); memory $([int]$mem) MB/s$(Cmp $mem $prev.memBandwidthMBs); SSD $([int]$disk) MB/s reading$(Cmp $disk $prev.diskReadMBs)$(if ($ram) { " - RAM at $ram" })"
}
finally { [IO.File]::Delete($Running) }
