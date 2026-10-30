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
    [string]$Tune = "$PSScriptRoot\game-tune.json", [string]$GameSettings = "$PSScriptRoot\game-settings.json",
    [string]$Storage = "$PSScriptRoot\storage.json", [string]$TestExe,   # -TestExe: the game's program file (nothing running is looked at)
    [hashtable]$TestNet)   # -TestNet: the minute's pings @{ net = ms[]; netLost; gw = ms[]; gwLost; wifi } - nothing is pinged
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
    # the connection while the game plays (10/25): the router and the internet (1.1.1.1) pinged every half second through
    # the minute, in the background - lag that builds up while the game uses the line shows as a higher ping than at idle
    # (net-history.json, network-check.ps1). Pings only - no data (the owner's rule).
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
    if ($route) {
        $netPs = [powershell]::Create().AddScript({
                param($gw, $sec)
                $p = New-Object Net.NetworkInformation.Ping; $o = @{ gw = New-Object Collections.Generic.List[double]; net = New-Object Collections.Generic.List[double]; gwLost = 0; netLost = 0 }
                $end = (Get-Date).AddSeconds($sec)
                while ((Get-Date) -lt $end) {
                    foreach ($t in @(, @('gw', $gw)) + @(, @('net', '1.1.1.1'))) { try { $r = $p.Send($t[1], 1000); if ($r.Status -eq 'Success') { $o[$t[0]].Add([double]$r.RoundtripTime) } else { $o["$($t[0])Lost"]++ } } catch { $o["$($t[0])Lost"]++ } }
                    Start-Sleep -Milliseconds 500
                }
                $o
            }).AddArgument($route.NextHop).AddArgument($Seconds)
        $netAsync = $netPs.BeginInvoke(); $netWifi = [bool]((Get-NetAdapter -InterfaceIndex $route.InterfaceIndex).NdisPhysicalMedium -eq 9)
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
    if ($netPs) { try { $nr = $netPs.EndInvoke($netAsync); if ($nr.Count) { $TestNet = $nr[0]; $TestNet.wifi = $netWifi } } catch { }; $netPs.Dispose() }
}
else { $gpu = @(Read-Gpu); $ssd = @(Read-SsdTemp); $dpc = @($TestDpc); $cpu = @($TestCpu); $ct = @($TestCpuTemp) }

# --- frame rate: the average and the 1% low (the frame time only 1 frame in 100 is slower than) ---
function Num($s) { $v = 0.0; if ([double]::TryParse("$s", [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { $v } else { $null } }
$rowsF = @(Import-Csv $csv | Where-Object { $_.Application -like "$game*" -and (Num $_.MsBetweenPresents) -gt 0 })
if (-not $TestCsv) { [IO.File]::Delete($csv) }
# the seconds spent in the game's menu or tabbed out (10/22): a game that caps those (Call of Duty: 60 in menus, 30 out
# of focus - its own settings, kept by game-settings.ps1) runs flat at that cap there - those seconds are left out, so
# a minute half in the menu doesn't read as a slow minute (and doesn't decide a game-tune test). A menu that's loading
# runs a little under its cap (10/23: 113-118 at a 120 cap), so up to 8 under and 2 over the cap counts as the menu.
$gsj = try { Get-Content $GameSettings -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { }
$caps = @(foreach ($p in $gsj.PSObject.Properties) { foreach ($k in 'MaxFpsInMenu@0', 'MaxFpsOutOfFocus@0') { $c = Num $p.Value.values.$k; if ($c -ge 10) { $c } } })
# ... and the game's own file as it is now (10/23: a game update set the menu cap to 120 while the kept copy still said 60,
# so every minute in the menu read as a 120 fps match minute)
if (-not $TestCsv) {
    foreach ($f in Get-ChildItem "$env:LOCALAPPDATA\Activision\Call of Duty\players\s.1.0.cod*.txt" -ErrorAction SilentlyContinue) {
        foreach ($l in [IO.File]::ReadLines($f.FullName)) { if ($l -match '^(MaxFpsInMenu|MaxFpsOutOfFocus)@0;\d+;\d+ = (\d+)') { $c = [double]$Matches[2]; if ($c -ge 10) { $caps += $c } } }
    }
}
$caps = @($caps | Sort-Object -Unique)
if ($caps -and $rowsF.Count) {
    $keep = New-Object Collections.ArrayList; $sec = New-Object Collections.ArrayList; $acc = 0.0
    foreach ($r in $rowsF) {
        [void]$sec.Add($r); $acc += Num $r.MsBetweenPresents
        if ($acc -ge 1000) { $f = $sec.Count * 1000 / $acc; if (-not ($caps | Where-Object { $f -ge $_ - 8 -and $f -le $_ + 2 })) { [void]$keep.AddRange($sec) }; $sec.Clear(); $acc = 0.0 }
    }
    if ($sec.Count) { [void]$keep.AddRange($sec) }
    if ($keep.Count -lt $rowsF.Count -and ($keep | ForEach-Object { Num $_.MsBetweenPresents } | Measure-Object -Sum).Sum -lt 20000) { return }   # under 20 s of actual play left
    $rowsF = $keep.ToArray()
}
$ms = @($rowsF | ForEach-Object { Num $_.MsBetweenPresents })
if ($ms.Count -lt 300) { return }   # under ~5 s of frames: a menu, a loading screen or alt-tabbed - not a sample
$sorted = @($ms | Sort-Object)
$avgFps = 1000 / (($ms | Measure-Object -Average).Average)
$p99 = $sorted[[int][Math]::Min($sorted.Count - 1, [Math]::Ceiling($sorted.Count * 0.99) - 1)]
$e = [ordered]@{ date = $Now.ToString('o'); game = $game; fps = [Math]::Round($avgFps, 1); low1 = [Math]::Round(1000 / $p99, 1); frames = $ms.Count }
# the game's own name when its program's says little (10/27: 'HuntGame' read that way in the app): the storage scan's game
# whose folder holds the program, else its Steam folder ('steamapps\common\Hunt Showdown')
$exe = if ($TestExe) { $TestExe } elseif (-not $TestGame) { "$((Get-Process -Name $game -ErrorAction SilentlyContinue | Select-Object -First 1).Path)" }
if ($exe) {
    $st = try { Get-Content $Storage -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { }
    $hit = @($st.games) | Where-Object { $_.name -and $_.path -and $exe.StartsWith("$("$($_.path)".TrimEnd('\'))\", [StringComparison]::OrdinalIgnoreCase) } | Sort-Object { "$($_.path)".Length } -Descending | Select-Object -First 1
    $title = if ($hit) { "$($hit.name)" } elseif ($exe -match '\\steamapps\\common\\([^\\]+)\\') { $Matches[1] }
    $title = "$title" -replace '[®™]', '' -replace '\s+', ' '
    if ($title.Trim() -and $title.Trim() -ne $game) { $e.title = $title.Trim() }
}
# the connection through the minute (the pings above): the internet's median ping, jitter (the average change between two
# pings), loss % and spikes (pings 50+ ms over the median - a lag spike you feel); the router's ping and loss (the home
# network: the cable or Wi-Fi); wifi. The app compares them with the ping at idle and says network or PC.
if ($TestNet) {
    foreach ($k in 'net', 'gw') {
        $v = @($TestNet[$k] | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ }); $lost = [int]$TestNet["$($k)Lost"]
        if ($v.Count + $lost -lt 10) { continue }   # (too few pings to say anything)
        $s = @($v | Sort-Object); $m = if ($s.Count) { $s[[int]($s.Count / 2)] }
        $pre = if ($k -eq 'net') { 'net' } else { 'gw' }
        $e["$($pre)Loss"] = [Math]::Round(100 * $lost / ($v.Count + $lost), 1)
        if ($s.Count -ge 2) {
            $e["$($pre)Ping"] = [Math]::Round($m, 0)
            $e["$($pre)Jitter"] = [Math]::Round((@(for ($i = 1; $i -lt $v.Count; $i++) { [Math]::Abs($v[$i] - $v[$i - 1]) }) | Measure-Object -Average).Average, 1)
            if ($k -eq 'net') { $e.netSpikes = @($v | Where-Object { $_ -ge $m + 50 }).Count }
        }
    }
    if ($null -ne $TestNet.wifi) { $e.wifi = [bool]$TestNet.wifi }
}
# stutters: frames over 2.5x the typical frame time and slower than 20 fps - the hitches you feel
$med = $sorted[[int]($sorted.Count / 2)]
$e.stutters = @($ms | Where-Object { $_ -gt [Math]::Max($med * 2.5, 50) }).Count
# the minute second by second (the app's Performance page draws it): each second's frame rate and its slowest frame
$fs = New-Object Collections.Generic.List[int]; $ws = New-Object Collections.Generic.List[double]; $acc = 0.0; $cnt = 0; $worst = 0.0
foreach ($v in $ms) { $acc += $v; $cnt++; if ($v -gt $worst) { $worst = $v }; if ($acc -ge 1000) { $fs.Add([int][Math]::Round($cnt * 1000 / $acc)); $ws.Add([Math]::Round($worst, 1)); $acc = 0.0; $cnt = 0; $worst = 0.0 } }
if ($fs.Count) { $e.perSec = $fs.ToArray(); $e.worstMs = $ws.ToArray() }
# what holds the frame rate back, and the delay to the screen (10/22; PresentMon 2's columns - an older capture has neither):
# gpuBusy = the share of each frame's time the graphics card was working (median; ~95+ = the card is the limit, lower =
# the processor, the game or a frame cap); latency = from the game starting a frame to it being on screen (median ms) -
# what Reflex lowers, so its test is judged on this; presentMode: how frames reach the screen ("Composed: Flip" = through
# the desktop compositor, a frame of extra delay; "Independent Flip" = straight to the screen)
function Med($v) { $s = @($v | Where-Object { $null -ne $_ } | Sort-Object); if ($s) { $s[[int]($s.Count / 2)] } }
if ($rowsF.Count -and $rowsF[0].PSObject.Properties['MsGPUBusy']) {
    $gb = Med ($rowsF | ForEach-Object { $b = Num $_.MsGPUBusy; $f = Num $_.MsBetweenPresents; if ($null -ne $b -and $f -gt 0) { [Math]::Min(100, $b / $f * 100) } })
    if ($null -ne $gb) { $e.gpuBusy = [int][Math]::Round($gb) }
    if ($null -ne $gb -and $gb -lt 25) { return }   # (the card barely drawing the frames: tabbed out or a menu at its cap - 10/25: a 43 fps "minute" at 3% read as a slow match)
    $lat = Med ($rowsF | ForEach-Object { $c = Num $_.MsCPUBusy; $d = Num $_.MsUntilDisplayed; if ($null -ne $c -and $null -ne $d -and $d -gt 0) { $c + $d } })
    if ($null -ne $lat) { $e.latency = [Math]::Round($lat, 1) }
}
if ($rowsF.Count -and $rowsF[0].PSObject.Properties['PresentMode']) { $e.presentMode = "$(@($rowsF | Group-Object PresentMode | Sort-Object Count -Descending)[0].Name)" }
# (10/22: newer drivers give the temperature with decimals, "67.61" - read as a number, not only whole ones)
$rows = @($gpu | ForEach-Object { , ("$_" -split ',\s*') } | Where-Object { $_.Count -ge 2 -and $_[0] -match '^\d+(\.\d+)?$' -and $_[1] -match '^\d+(\.\d+)?$' })
if ($rows) {
    $e.gpuTemp = [int][Math]::Round(($rows | ForEach-Object { Num $_[0] } | Measure-Object -Maximum).Maximum)
    $e.gpuUse = [int](($rows | ForEach-Object { Num $_[1] } | Measure-Object -Average).Average)
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
