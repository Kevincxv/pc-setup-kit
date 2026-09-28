# In-game performance sample: while a game runs, one minute of its real frame times (Intel's PresentMon) plus the
# graphics card's temperature, load and throttling and the SSD's temperature - so "a driver/Windows update made my
# games worse" and "it runs hot while gaming" show up as numbers (trends.ps1 compares them; the app charts them).
# Started by the tray every 5 minutes while something is fullscreen; it does nothing unless game-check.ps1 names a
# game, and samples each game at most once every 3 hours. One line per sample in perf-history.json (last 500).
# PresentMon (MIT licence, signed by Intel) is fetched once to .claude\tools; nothing else is installed.
# -TestCsv / -TestGame / -TestGpu: tests (a recorded capture, a game name, nvidia-smi rows) - nothing is captured.
param([int]$Seconds = 60, [string]$History = "$PSScriptRoot\perf-history.json", [datetime]$Now = (Get-Date),
    [string]$TestCsv, [string]$TestGame, [string[]]$TestGpu, [switch]$Force)
$ErrorActionPreference = 'SilentlyContinue'
$mx = New-Object Threading.Mutex($false, "Global\PCSetupKitGamePerf$(if ($TestCsv) { "-test-$PID" })")
if (-not $mx.WaitOne(0)) { return }   # a sample is already running (tests never wait for a real one)

$j = try { Get-Content $History -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { }
$h = @($j | ForEach-Object { $_ })   # PowerShell 5.1 hands a JSON array over as ONE item: unrolled here

# --- which game (the one in front, fullscreen, or a known one running) ---
$game = $TestGame
if (-not $game) {
    $why = "$(& "$PSScriptRoot\game-check.ps1" -Explain -NoLearn)"
    if (-not $why -or $why -match 'not a game') { return }
    $game = ($why -split ' - ')[0].Trim()
}
if (-not $game) { return }
$last = $h | Where-Object { $_.game -eq $game } | Select-Object -Last 1
if (-not $Force -and $last -and [datetime]$last.date -gt $Now.AddHours(-3)) { return }

# --- the graphics card while the game runs (every 5 s during the capture) ---
function Read-Gpu {
    if ($TestGpu) { return $TestGpu }
    $q = 'temperature.gpu,utilization.gpu,clocks_event_reasons.hw_thermal_slowdown,clocks_event_reasons.sw_thermal_slowdown,clocks_event_reasons.sw_power_cap'
    $r = "$(& nvidia-smi --query-gpu=$q --format=csv,noheader,nounits 2>$null | Select-Object -First 1)"
    if ($r -notmatch '^\d') { $r = "$(& nvidia-smi --query-gpu=$($q -replace 'clocks_event_reasons', 'clocks_throttle_reasons') --format=csv,noheader,nounits 2>$null | Select-Object -First 1)" }   # older drivers
    if ($r -match '^\d') { $r }
}
function Read-SsdTemp { if ($TestGpu) { return 50 }; (Get-Partition -DriveLetter C | Get-Disk | Get-StorageReliabilityCounter).Temperature }

$csv = $TestCsv; $gpu = @(); $ssd = @()
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
    $w = [Diagnostics.Stopwatch]::StartNew()
    while (-not $p.HasExited -and $w.Elapsed.TotalSeconds -lt $Seconds + 30) {
        $g = Read-Gpu; if ($g) { $gpu += $g }; $t = Read-SsdTemp; if ($t) { $ssd += [int]$t }
        Start-Sleep 5
    }
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
}
else { $gpu = @(Read-Gpu); $ssd = @(Read-SsdTemp) }

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
$rows = @($gpu | ForEach-Object { , ("$_" -split ',\s*') } | Where-Object { $_.Count -ge 2 -and $_[0] -match '^\d+$' })
if ($rows) {
    $e.gpuTemp = ($rows | ForEach-Object { [int]$_[0] } | Measure-Object -Maximum).Maximum
    $e.gpuUse = [int](($rows | ForEach-Object { [int]$_[1] } | Measure-Object -Average).Average)
    $thr = @(); if ($rows | Where-Object { $_.Count -ge 4 -and ($_[2] -eq 'Active' -or $_[3] -eq 'Active') }) { $thr += 'heat' }
    if ($rows | Where-Object { $_.Count -ge 5 -and $_[4] -eq 'Active' }) { $thr += 'power' }
    if ($thr) { $e.throttle = $thr -join ',' }
}
if ($ssd) { $e.ssdTemp = ($ssd | Measure-Object -Maximum).Maximum }
# what the numbers depend on: a change here explains a change in the numbers
$e.driver = "$((Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA|AMD|Radeon|Intel\(R\) Arc' } | Select-Object -First 1).DriverVersion)"
$e.build = "$([Environment]::OSVersion.Version.Build).$((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR)"
$h = @($h | Where-Object { $_.date }) + [pscustomobject]$e | Select-Object -Last 500
try { ConvertTo-Json -InputObject @($h) -Depth 3 | Set-Content "$History.tmp" -Encoding UTF8; Move-Item "$History.tmp" $History -Force } catch {}
"$game`: $($e.fps) fps average, $($e.low1) fps 1% low$(if ($null -ne $e.gpuTemp) { ", graphics card up to $($e.gpuTemp) C" })"
