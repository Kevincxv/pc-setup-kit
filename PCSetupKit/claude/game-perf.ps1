# In-game performance sample: while a game runs, one minute of its real frame times (Intel's PresentMon) plus the
# graphics card's temperature, load, fan, power and throttling, the processor's temperature and speed limit, the SSD's temperature
# (and which setting game-tune.ps1 is trying out, if any) - so "a driver/Windows update made my
# games worse" and "it runs hot while gaming" show up as numbers (trends.ps1 compares them; the app charts them).
# Started by the tray every 5 minutes while something is fullscreen; it does nothing unless game-check.ps1 names a
# game, and samples a game at most every 25 minutes (a few minutes of each session, 10/21 - was every 3 hours); a minute with
# the graphics card hardly busy (a menu, a lobby, a kill-cam) is not a sample. One line per sample in perf-history.json (last 500).
# PresentMon (MIT licence, signed by Intel) is fetched once to .claude\tools; nothing else is installed.
# -TestCsv / -TestGame / -TestGpu: tests (a recorded capture, a game name, nvidia-smi rows) - nothing is captured.
param([int]$Seconds = 60, [string]$History = "$PSScriptRoot\perf-history.json", [datetime]$Now = (Get-Date),
    [string]$TestCsv, [string]$TestGame, [string[]]$TestGpu, [double[]]$TestDpc, [string[]]$TestCpu, [double[]]$TestCpuTemp, [switch]$Force,   # -TestDpc: the busiest core's driver time (%) per reading; -TestCpu: "limit,performance" readings
    [string]$Tune = "$PSScriptRoot\game-tune.json", [string]$GameSettings = "$PSScriptRoot\game-settings.json")
$ErrorActionPreference = 'SilentlyContinue'
$mx = New-Object Threading.Mutex($false, "Global\PCSetupKitGamePerf$(if ($TestCsv) { "-test-$PID" })")
if (-not $mx.WaitOne(0)) { return }   # a sample is already running (tests never wait for a real one)

$j = try { Get-Content $History -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { }
$h = @($j | ForEach-Object { $_ } | Where-Object { $_ -is [Management.Automation.PSCustomObject] -and $(try { [void][datetime]"$($_.date)"; $true } catch { $false }) })   # PowerShell 5.1 hands a JSON array over as ONE item: unrolled here (a damaged entry is dropped)

# --- which game (the one in front, fullscreen, or a known one running) ---
$game = $TestGame
if (-not $game) {
    $why = "$(& "$PSScriptRoot\game-check.ps1" -Explain -NoLearn)"
    if (-not $why -or $why -match 'not a game') { return }
    $game = ($why -split ' - ')[0].Trim()
}
if (-not $game) { return }
$last = $h | Where-Object { $_.game -eq $game } | Select-Object -Last 1
if (-not $Force -and $last -and [datetime]$last.date -gt $Now.AddMinutes(-25)) { return }

# --- the graphics card while the game runs (every 5 s during the capture) ---
function Read-Gpu {
    if ($TestGpu) { return $TestGpu }
    # (fan and power last: a card or driver without them still gives the rest)
    $q = 'temperature.gpu,utilization.gpu,clocks_event_reasons.hw_thermal_slowdown,clocks_event_reasons.sw_thermal_slowdown,clocks_event_reasons.sw_power_cap'
    foreach ($qq in "$q,fan.speed,power.draw", ($q -replace 'clocks_event_reasons', 'clocks_throttle_reasons'), $q) {   # (older drivers: the throttle names)
        $r = "$(& nvidia-smi --query-gpu=$qq --format=csv,noheader,nounits 2>$null | Select-Object -First 1)"
        if ($r -match '^\d') { return $r }
    }
}
# the processor held back (10/21): Windows' "% Performance Limit" drops under 100 when the CPU is kept from its full
# speed - by heat (this PC's CPU has no temperature Windows can read without a kernel driver) or by power; and how fast
# it runs against its base speed. English counter names; elsewhere: not measured
function Read-Cpu {
    if ($TestCpu) { return $TestCpu }
    try {
        $s = (Get-Counter '\Processor Information(_Total)\% Performance Limit', '\Processor Information(_Total)\% Processor Performance' -ErrorAction Stop).CounterSamples
        "$([Math]::Round(($s | Where-Object Path -match 'limit').CookedValue)),$([Math]::Round(($s | Where-Object Path -match 'processor performance').CookedValue))"
    } catch { }
}
# drivers' time on the busiest core (interrupts + deferred calls, %): high = a driver steals time from the game - the
# stutters a frame-rate average hides (audio, network, USB). English counter names; elsewhere: not measured
function Read-Dpc {
    try {
        $s = (Get-Counter '\Processor(*)\% DPC Time', '\Processor(*)\% Interrupt Time' -ErrorAction Stop).CounterSamples | Where-Object InstanceName -ne '_total'
        ($s | Group-Object InstanceName | ForEach-Object { ($_.Group | Measure-Object CookedValue -Sum).Sum } | Measure-Object -Maximum).Maximum
    } catch { $null }
}function Read-SsdTemp { if ($TestGpu) { return 50 }; (Get-Partition -DriveLetter C | Get-Disk | Get-StorageReliabilityCounter).Temperature }

$csv = $TestCsv; $gpu = @(); $ssd = @(); $dpc = @(); $cpu = @(); $ct = @()
if (-not $csv) {
    $pm = "$PSScriptRoot\tools\PresentMon.exe"
    if (-not (Test-Path $pm)) {
        # the newest release's console exe; used only while it carries Intel's valid signature
        New-Item "$PSScriptRoot\tools" -ItemType Directory -Force | Out-Null
        $ProgressPreference = 'SilentlyContinue'
        try {
            $rel = Invoke-RestMethod 'https://api.github.com/repos/GameTechDev/PresentMon/releases/latest' -TimeoutSec 20
            $asset = $rel.assets | Where-Object { $_.name -match '^PresentMon-[\d.]+-x64\.exe$' } | Select-Object -First 1
            Invoke-WebRequest $asset.browser_download_url -OutFile "$pm.download" -UseBasicParsing -TimeoutSec 120
            $sig = Get-AuthenticodeSignature "$pm.download"
            if ($sig.Status -eq 'Valid' -and $sig.SignerCertificate.Subject -match 'O=Intel Corporation') { Move-Item "$pm.download" $pm -Force }
            else { [IO.File]::Delete("$pm.download") }
        } catch { }
        if (-not (Test-Path $pm)) { return }   # offline: next time
    }
    $csv = Join-Path $env:TEMP "pckit-perf-$PID.csv"
    $p = Start-Process $pm -ArgumentList '--process_name', "$game.exe", '--timed', $Seconds, '--terminate_after_timed', '--no_console_stats',
        '--session_name', 'PCSetupKitPerf', '--stop_existing_session', '--output_file', "`"$csv`"" -WindowStyle Hidden -PassThru
    try { $p.PriorityClass = 'BelowNormal' } catch { }
    # the processor's temperature (cpu-temp.ps1: the PawnIO driver and LibreHardwareMonitor, once installed)
    $readT = & "$PSScriptRoot\cpu-temp.ps1" -Reader
    $w = [Diagnostics.Stopwatch]::StartNew()
    while (-not $p.HasExited -and $w.Elapsed.TotalSeconds -lt $Seconds + 30) {
        $g = Read-Gpu; if ($g) { $gpu += $g }; $t = Read-SsdTemp; if ($t) { $ssd += [int]$t }; $d = Read-Dpc; if ($null -ne $d) { $dpc += $d }; $c = Read-Cpu; if ($c) { $cpu += $c }; if ($readT) { $tc = & $readT; if ($tc) { $ct += $tc } }
        Start-Sleep 5
    }
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
}
else { $gpu = @(Read-Gpu); $ssd = @(Read-SsdTemp); $dpc = @($TestDpc); $cpu = @($TestCpu); $ct = @($TestCpuTemp) }

# --- frame rate: the average and the 1% low (the frame time only 1 frame in 100 is slower than) ---
$ms = @(Import-Csv $csv | Where-Object { $_.Application -like "$game*" } | ForEach-Object { $v = 0.0; if ([double]::TryParse($_.MsBetweenPresents, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v) -and $v -gt 0) { $v } })
if (-not $TestCsv) { [IO.File]::Delete($csv) }
if ($ms.Count -lt 300) { return }   # under ~5 s of frames: a menu, a loading screen or alt-tabbed - not a sample
$sorted = @($ms | Sort-Object)
$avgFps = 1000 / (($ms | Measure-Object -Average).Average)
$p99 = $sorted[[int][Math]::Min($sorted.Count - 1, [Math]::Ceiling($sorted.Count * 0.99) - 1)]
$e = [ordered]@{ date = $Now.ToString('o'); game = $game; fps = [Math]::Round($avgFps, 1); low1 = [Math]::Round(1000 / $p99, 1); frames = $ms.Count }
# stutters: frames over 2.5x the typical frame time and slower than 20 fps - the hitches you feel
$med = $sorted[[int]($sorted.Count / 2)]
$e.stutters = @($ms | Where-Object { $_ -gt [Math]::Max($med * 2.5, 50) }).Count
# the minute second by second (the app's Performance page draws it): each second's frame rate and its slowest frame
$fs = New-Object Collections.Generic.List[int]; $ws = New-Object Collections.Generic.List[double]; $acc = 0.0; $cnt = 0; $worst = 0.0
foreach ($v in $ms) { $acc += $v; $cnt++; if ($v -gt $worst) { $worst = $v }; if ($acc -ge 1000) { $fs.Add([int][Math]::Round($cnt * 1000 / $acc)); $ws.Add([Math]::Round($worst, 1)); $acc = 0.0; $cnt = 0; $worst = 0.0 } }
if ($fs.Count) { $e.perSec = $fs.ToArray(); $e.worstMs = $ws.ToArray() }
$rows = @($gpu | ForEach-Object { , ("$_" -split ',\s*') } | Where-Object { $_.Count -ge 2 -and $_[0] -match '^\d+$' })
if ($rows) {
    $e.gpuTemp = ($rows | ForEach-Object { [int]$_[0] } | Measure-Object -Maximum).Maximum
    $e.gpuUse = [int](($rows | ForEach-Object { [int]$_[1] } | Measure-Object -Average).Average)
    if ($e.gpuUse -lt 25) { return }   # the card hardly busy for the minute: a menu, a lobby or a kill-cam - not the game being played
    $thr = @(); if ($rows | Where-Object { $_.Count -ge 4 -and ($_[2] -eq 'Active' -or $_[3] -eq 'Active') }) { $thr += 'heat' }
    if ($rows | Where-Object { $_.Count -ge 5 -and $_[4] -eq 'Active' }) { $thr += 'power' }
    if ($thr) { $e.throttle = $thr -join ',' }
    # its fan (average %) and power (most watts) while playing - the Performance page's heat and wear
    $fan = @($rows | Where-Object { $_.Count -ge 7 -and $_[5] -match '^\d+$' } | ForEach-Object { [int]$_[5] })
    if ($fan) { $e.gpuFan = [int](($fan | Measure-Object -Average).Average) }
    $pw = @($rows | Where-Object { $_.Count -ge 7 -and $_[6] -match '^\d' } | ForEach-Object { [double]$_[6] })
    if ($pw) { $e.gpuPower = [int](($pw | Measure-Object -Maximum).Maximum) }
}
$cr = @($cpu | ForEach-Object { , ("$_" -split ',') } | Where-Object { $_.Count -eq 2 -and $_[0] -match '^\d+$' -and $_[1] -match '^\d+$' })
if ($ct) { $e.cpuTemp = ($ct | Measure-Object -Maximum).Maximum }   # (the hottest reading of the minute)
if ($cr) { $e.cpuLimit = ($cr | ForEach-Object { [int]$_[0] } | Measure-Object -Minimum).Minimum; $e.cpuPerf = [int](($cr | ForEach-Object { [int]$_[1] } | Measure-Object -Average).Average) }
if ($ssd) { $e.ssdTemp = ($ssd | Measure-Object -Maximum).Maximum }
# what the numbers depend on: a change here explains a change in the numbers
$e.driver = "$((Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA|AMD|Radeon|Intel\(R\) Arc' } | Select-Object -First 1).DriverVersion)"
$e.build = "$([Environment]::OSVersion.Version.Build).$((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR)"
if ($dpc.Count) { $e.dpcMax = [Math]::Round(($dpc | Measure-Object -Maximum).Maximum, 1); $e.dpc = [Math]::Round(($dpc | Measure-Object -Average).Average, 1) }
$e.ram = "$((Get-CimInstance Win32_PhysicalMemory | Select-Object -First 1).ConfiguredClockSpeed) MT/s"   # (EXPO on/off shows here)
$dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
$e.hvci = if (@($dg.SecurityServicesRunning) -contains 2) { 'on' } else { 'off' }   # Memory Integrity
# a setting being tested right now (game-tune.ps1): which one, and which of its two values - the test reads its samples by this
$tj = try { Get-Content $Tune -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { }
if ($tj.active -and $tj.active.game -eq $game) { $e.tune = "$($tj.active.id):$($tj.active.arm)" }
# the game's tuned settings (game-settings.ps1): a short fingerprint - a change to them is a change to compare across.
# Only the settings' values (10/21: not the driver it also keeps, nor a setting game-tune.ps1 is trying out - those
# are compared on their own)
$gj = try { Get-Content $GameSettings -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { }
if ($gj) {
    $tk = @($tj.keys)
    $flat = @(foreach ($p in $gj.PSObject.Properties) { if ($p.Value.values) { foreach ($v in $p.Value.values.PSObject.Properties) { if ($v.Name -notin $tk) { "$($v.Name)=$($v.Value)" } } } }) | Sort-Object
    if ($flat) { $md5 = [Security.Cryptography.MD5]::Create(); $e.settings = (($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($flat -join "`n"))) | Select-Object -First 4 | ForEach-Object { $_.ToString('x2') }) -join '' }
}
$h = @($h | Where-Object { $_.date }) + [pscustomobject]$e | Select-Object -Last 500
# (the second-by-second curves only on the newest 30: the file stays small)
for ($i = 0; $i -lt $h.Count - 30; $i++) { foreach ($p in 'perSec', 'worstMs') { if ($h[$i].PSObject.Properties[$p]) { $h[$i].PSObject.Properties.Remove($p) } } }
try { ConvertTo-Json -InputObject @($h) -Depth 3 | Set-Content "$History.tmp" -Encoding UTF8; Move-Item "$History.tmp" $History -Force } catch {}
"$game`: $($e.fps) fps average, $($e.low1) fps 1% low$(if ($null -ne $e.gpuTemp) { ", graphics card up to $($e.gpuTemp) C" })"
