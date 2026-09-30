# Optimizes this PC in one go, no AI needed (what the /pc-optimize playbook does with Claude): monitors to their best
# refresh rate, vendor background apps pointed out, a benchmark (the first one is the baseline; later ones are compared
# with it), then the full maintenance (drivers, app updates, checks, cleanup, self-test, fixes and to-do items), and a
# readable report in Documents. Run at the end of setup, from the tray ("Optimize this PC now") and yearly.
# -Benchmark: only the benchmark and its comparison (the quarterly check).  -FromMaintenance: called by the maintenance
# itself (no second maintenance run, no report window).  -NoOpen: don't open the report at the end.
# -Background (setup): the quick part now, then the full maintenance in the background - setup is done and the PC usable
# right away (the welcome page opens) instead of waiting 20+ minutes; its result goes into the report when it finishes
# (-FinishReport, that background half; setup-maint-running.txt while it runs). No self-test in that first run: the
# next maintenance runs it (and the fresh-install checks run their own).
param([switch]$Benchmark, [switch]$FromMaintenance, [switch]$NoOpen, [switch]$Background, [switch]$FinishReport)
$ErrorActionPreference = 'Continue'
$dir = $PSScriptRoot
$report = "$env:USERPROFILE\Documents\PC Setup Kit report.txt"
if (-not $FinishReport -and ($g = & "$dir\game-check.ps1")) { "Optimize held: $g is running (it runs again later)"; return }
$out = New-Object System.Collections.Generic.List[string]
function Say([string]$t) { $out.Add($t); $t }
$running = "$dir\setup-maint-running.txt"; $quick = "$dir\optimize-quick.txt"

# --- Benchmark (Windows' own WinSAT): the first result is the baseline, later ones are compared with it ---
function Invoke-Benchmark {
    $p = Start-Process winsat -ArgumentList 'formal', '-restart', 'clean' -WindowStyle Hidden -PassThru -Wait
    $w = Get-CimInstance Win32_WinSAT -ErrorAction SilentlyContinue
    if (-not $w -or -not $w.CPUScore) { Say 'Benchmark: could not run (WinSAT gave no scores)'; return }
    $now = [ordered]@{ date = (Get-Date).ToString('o'); cpu = $w.CPUScore; memory = $w.MemoryScore; d3d = $w.D3DScore; graphics = $w.GraphicsScore; disk = $w.DiskScore }
    $file = "$dir\benchmarks.json"
    $all = @(); try { $all = @(Get-Content $file -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop | ForEach-Object { $_ }) } catch {}
    $scores = "CPU $($now.cpu), memory $($now.memory), graphics $($now.d3d), disk $($now.disk)"
    if (-not $all) { Say "Benchmark: $scores (saved as the baseline to compare with later)" }
    else {
        $base = $all[0]; $worse = @()
        foreach ($k in 'cpu', 'memory', 'd3d', 'disk') { if ($base.$k -and $now[$k] -and $now[$k] -lt 0.85 * $base.$k) { $worse += "$(@{ cpu = 'CPU'; memory = 'memory'; d3d = 'graphics'; disk = 'disk' }[$k]) $($now[$k]) (was $($base.$k))" } }
        if ($worse) {
            Say "WARNING: benchmark is more than 15% lower than at setup: $($worse -join ', ')"
            & "$dir\todo.ps1" -Id 'slower' -Text "The PC scores lower than when it was set up ($($worse -join ', ')). Common causes: dust in the fans (clean them), a driver or BIOS change, or a nearly full drive. Delete this line once checked."
        } else { Say "Benchmark: $scores (as fast as at setup)"; & "$dir\todo.ps1" -Id 'slower' -Done }
    }
    ConvertTo-Json -InputObject @($all + [pscustomobject]$now) -Depth 3 | Set-Content "$file.tmp" -Encoding UTF8; Move-Item "$file.tmp" $file -Force
}
if ($Benchmark) { Invoke-Benchmark; return }

# --- System summary (for the report) ---
$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
$bb = Get-CimInstance Win32_BaseBoard | Select-Object -First 1; $bios = Get-CimInstance Win32_BIOS | Select-Object -First 1
$ram = @(Get-CimInstance Win32_PhysicalMemory)
$gpus = @(Get-CimInstance Win32_VideoController | Where-Object Name -notmatch 'Basic Display|Remote')
$os = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
$summary = @(
    "Windows: $($os.ProductName) $($os.DisplayVersion) (build $($os.CurrentBuild))"
    "CPU: $cpu"
    "Motherboard: $($bb.Manufacturer) $($bb.Product), BIOS $($bios.SMBIOSBIOSVersion) ($(if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString('d') }))"
    "RAM: $([int](($ram | Measure-Object Capacity -Sum).Sum / 1GB)) GB, $(@($ram).Count) stick(s) at $(($ram | Select-Object -First 1).ConfiguredClockSpeed) MT/s ($((($ram | Select-Object -First 1).PartNumber).Trim()))"
) + @($gpus | ForEach-Object { "Graphics: $($_.Name) (driver $($_.DriverVersion))" }) + @(Get-PhysicalDisk | ForEach-Object { "Drive: $($_.FriendlyName), $([int]($_.Size / 1GB)) GB, $($_.HealthStatus)" })

if (-not $FinishReport) {
# --- Monitors at their best refresh rate ---
@(& "$dir\display-refresh.ps1") | ForEach-Object { Say $_ }

# --- What came with the PC: plain junk removed, trial antivirus / VPNs a one-click to-do (junk-apps.ps1) ---
if (Test-Path "$dir\junk-apps.ps1") { @(& "$dir\junk-apps.ps1") | ForEach-Object { Say $_ } }

# --- Benchmark, then the full maintenance (drivers, app updates, checks, cleanup, self-test, fixes, to-do items) ---
Invoke-Benchmark
}   # (the quick part)
if ($FinishReport) { foreach ($l in @(Get-Content $quick -Encoding UTF8 -ErrorAction SilentlyContinue)) { $out.Add($l) } }
if (-not $FromMaintenance -and -not $FinishReport) {
    # the scheduled checks count from today (quarterly benchmark, half-year cleaning reminder, yearly re-optimize) -
    # set first: the maintenance run below would otherwise find the yearly re-optimize "due" and start it again
    $ms = "$dir\maint-state.json"; $s = @{}; try { (Get-Content $ms -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).PSObject.Properties | ForEach-Object { $s[$_.Name] = $_.Value } } catch {}
    foreach ($k in 'claude-quarterly', 'claude-halfyear', 'claude-yearly') { $s[$k] = (Get-Date).ToString('o') }
    $s | ConvertTo-Json | Set-Content "$ms.tmp" -Encoding UTF8; Move-Item "$ms.tmp" $ms -Force
    if ($Background) {
        [IO.File]::WriteAllLines($quick, [string[]]@($out), (New-Object Text.UTF8Encoding $false))
        (Get-Date).ToString('o') | Set-Content $running
        Start-Process "$env:SystemRoot\System32\conhost.exe" -ArgumentList "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$dir\optimize.ps1`" -FinishReport"
        Say 'Maintenance: running in the background now (drivers, app updates, checks, cleanup) - the app shows it; its result is added here when it finishes'
    } else {
        Say 'Maintenance: running everything now (drivers, app updates, checks, cleanup, self-test)...'
        & "$dir\claude-bg-maint.ps1" -Force -Unattended -Now
        Get-Content "$dir\maint-report.txt" -Encoding UTF8 -ErrorAction SilentlyContinue | Select-Object -Skip 1 | ForEach-Object { $out.Add("  $_") }
    }
}
if ($FinishReport) {   # the background half: the maintenance (no self-test this once), then the full report
    try {
        $out.Add('Maintenance (in the background, right after setup):')
        & "$dir\claude-bg-maint.ps1" -Force -Unattended -Now -NoSelfTest | Out-Null
        Get-Content "$dir\maint-report.txt" -Encoding UTF8 -ErrorAction SilentlyContinue | Select-Object -Skip 1 | ForEach-Object { $out.Add("  $_") }
    } finally { foreach ($f in $running, $quick) { try { [IO.File]::Delete($f) } catch {} } }
}

# --- The report ---
$todo = @(Get-Content "$dir\maint-todo.txt" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
$text = @("PC Setup Kit - optimization report, $((Get-Date).ToString('f'))", '', 'THIS PC') + ($summary | ForEach-Object { "  $_" }) +
    @('', 'WHAT WAS DONE') + ($out | ForEach-Object { "  $_" }) +
    @('', 'WHAT NEEDS YOU') + $(if ($todo) { $todo | ForEach-Object { "  - $_" } } else { '  Nothing.' }) +
    @('', 'From now on the PC maintains itself at every login. The app (Start menu, or the hidden tray icon) shows the status and', 'anything that needs you. Log files: C:\PCSetupKit\setup.log, %USERPROFILE%\.claude\maint-report.txt')
[IO.File]::WriteAllLines($report, [string[]]$text, (New-Object Text.UTF8Encoding $false))
"Report: $report"
if (-not $FromMaintenance -and -not $NoOpen -and -not $FinishReport) { Start-Process notepad.exe "`"$report`"" }
