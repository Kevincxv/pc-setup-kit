# Optimizes this PC in one go, no AI needed (what the /pc-optimize playbook does with Claude): monitors to their best
# refresh rate, vendor background apps pointed out, a benchmark (the first one is the baseline; later ones are compared
# with it), then the full maintenance (drivers, app updates, checks, cleanup, self-test, fixes and to-do items), and a
# readable report in Documents. Run at the end of setup, from the tray ("Optimize this PC now") and yearly.
# -Benchmark: only the benchmark and its comparison (the quarterly check).  -FromMaintenance: called by the maintenance
# itself (no second maintenance run, no report window).  -NoOpen: don't open the report at the end.
param([switch]$Benchmark, [switch]$FromMaintenance, [switch]$NoOpen)
$ErrorActionPreference = 'Continue'
$dir = $PSScriptRoot
$report = "$env:USERPROFILE\Documents\PC Setup Kit report.txt"
if ($g = & "$dir\game-check.ps1") { "Optimize held: $g is running (it runs again later)"; return }
$out = New-Object System.Collections.Generic.List[string]
function Say([string]$t) { $out.Add($t); $t }

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

# --- Monitors at their best refresh rate ---
@(& "$dir\display-refresh.ps1") | ForEach-Object { Say $_ }

# --- Vendor background apps (pointed out, never removed: the owner may use them) ---
$known = 'Armoury Crate', 'MSI Center', 'Dragon Center', 'iCUE', 'Razer Synapse', 'APP Shop', 'Auto Driver Installer', 'AI Suite', 'GIGABYTE Control Center',
    'App Center', 'McAfee', 'Norton', 'WildTangent', 'Avast', 'AVG', 'Candy Crush', 'ExpressVPN', 'Dropbox Promotion'
$apps = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object { $n = $_.DisplayName; $n -and ($known | Where-Object { $n -like "*$_*" }) } | ForEach-Object DisplayName | Sort-Object -Unique)
if ($apps) {
    Say "Vendor/background apps found: $($apps -join ', ')"
    & "$dir\todo.ps1" -Id 'vendor-apps' -Text "These came with the PC or a trial and run in the background: $($apps -join ', '). If you don't use them, uninstall them in Settings > Apps > Installed apps. Delete this line to keep them."
}

# --- Benchmark, then the full maintenance (drivers, app updates, checks, cleanup, self-test, fixes, to-do items) ---
Invoke-Benchmark
if (-not $FromMaintenance) {
    Say 'Maintenance: running everything now (drivers, app updates, checks, cleanup, self-test)...'
    & "$dir\claude-bg-maint.ps1" -Force -Unattended
    Get-Content "$dir\maint-report.txt" -Encoding UTF8 -ErrorAction SilentlyContinue | Select-Object -Skip 1 | ForEach-Object { $out.Add("  $_") }
    # the scheduled checks count from today (quarterly benchmark, half-year cleaning reminder, yearly re-optimize)
    $ms = "$dir\maint-state.json"; $s = @{}; try { (Get-Content $ms -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).PSObject.Properties | ForEach-Object { $s[$_.Name] = $_.Value } } catch {}
    foreach ($k in 'claude-quarterly', 'claude-halfyear', 'claude-yearly') { $s[$k] = (Get-Date).ToString('o') }
    $s | ConvertTo-Json | Set-Content "$ms.tmp" -Encoding UTF8; Move-Item "$ms.tmp" $ms -Force
}

# --- The report ---
$todo = @(Get-Content "$dir\maint-todo.txt" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
$text = @("PC Setup Kit - optimization report, $((Get-Date).ToString('f'))", '', 'THIS PC') + ($summary | ForEach-Object { "  $_" }) +
    @('', 'WHAT WAS DONE') + ($out | ForEach-Object { "  $_" }) +
    @('', 'WHAT NEEDS YOU') + $(if ($todo) { $todo | ForEach-Object { "  - $_" } } else { '  Nothing.' }) +
    @('', 'From now on the PC maintains itself at every login. The tray icon (next to the clock) shows the status and', 'anything that needs you. Log files: C:\PCSetupKit\setup.log, %USERPROFILE%\.claude\maint-report.txt')
[IO.File]::WriteAllLines($report, [string[]]$text, (New-Object Text.UTF8Encoding $false))
"Report: $report"
if (-not $FromMaintenance -and -not $NoOpen) { Start-Process notepad.exe "`"$report`"" }
