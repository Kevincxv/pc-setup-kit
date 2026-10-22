# The fans (10/22, the owner's request), read through LibreHardwareMonitor and the PawnIO driver (cpu-temp.ps1 installs
# them). Run by health-check.ps1:
# - The graphics card's fans stuck high while it is idle and cool (10/22: 70% - 2,500 RPM at 28 C, a manual setting left
#   behind; in automatic they stop): put back to automatic - the card's own curve, which still speeds them up as it
#   warms. Said once; if something keeps setting them again, that is said instead (another fan program).
# - The CPU fan or the water-cooling pump stopped (0 RPM while the board drives it): a WARNING - the processor has no
#   cooling. Said again only once it ran and stopped again.
# - Each check's speeds go to fan-state.json (the app's Heat and wear card shows them).
# Never writes a fan curve to the motherboard: the BIOS's own curves stay in charge of the case and CPU fans.
# kit-options.txt fancheck=off (the app's Settings) stops it. -Test (Readings: @{ Hw; Name; Rpm; Duty }, GpuUse, GpuTemp)
# with -Do (gets the actions) / -State / -Options / -Now: tests.
param([hashtable]$Test, [scriptblock]$Do, [string]$State = "$PSScriptRoot\fan-state.json", [string]$Options = "$PSScriptRoot\kit-options.txt",
    [datetime]$Now = (Get-Date), [string]$Tools = "$PSScriptRoot\tools\lhm")
$ErrorActionPreference = 'SilentlyContinue'
$T = $Test
if (Select-String -Path $Options -Pattern '^\s*fancheck\s*=\s*off\s*$' -Quiet) { return }
$st = try { Get-Content $State -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { $null }
if ($st -isnot [Management.Automation.PSCustomObject]) { $st = [pscustomobject]@{} }
foreach ($k in 'gpuReset', 'gpuResets', 'stopped', 'last') { if (-not ($st.PSObject.Properties.Name -contains $k)) { $st | Add-Member $k $null } }

# --- the readings: every fan with its speed (RPM) and how hard it is driven (%) ---
$computer = $null
if ($T) { $fans = @($T.Readings | ForEach-Object { [pscustomobject]$_ }); $gpuUse = $T.GpuUse; $gpuTemp = $T.GpuTemp }
else {
    if (-not (Test-Path "$Tools\LibreHardwareMonitorLib.dll") -or -not (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO')) { return }   # (cpu-temp.ps1 installs them)
    try {
        Add-Type -Path "$Tools\LibreHardwareMonitorLib.dll" -ErrorAction Stop
        $computer = New-Object LibreHardwareMonitor.Hardware.Computer; $computer.IsMotherboardEnabled = $true; $computer.IsGpuEnabled = $true; $computer.Open()
    } catch { return }
    $all = New-Object Collections.Generic.List[object]
    function Walk($h) { $h.Update(); foreach ($s in $h.Sensors) { $all.Add([pscustomobject]@{ Hw = "$($h.HardwareType)"; Sensor = $s }) }; foreach ($x in $h.SubHardware) { Walk $x } }
    foreach ($h in $computer.Hardware) { Walk $h }
    $fans = @($all | Where-Object { "$($_.Sensor.SensorType)" -eq 'Fan' } | ForEach-Object {
            $n = $_.Sensor.Name; $hw = if ($_.Hw -match 'Gpu') { 'gpu' } else { 'board' }
            $ctl = $all | Where-Object { "$($_.Sensor.SensorType)" -eq 'Control' -and $_.Sensor.Name -eq $n } | Select-Object -First 1
            [pscustomobject]@{ Hw = $hw; Name = $n; Rpm = [int]$_.Sensor.Value; Duty = $(if ($ctl) { [int]$ctl.Sensor.Value } else { $null }); Control = $(if ($ctl) { $ctl.Sensor.Control }) } })
    $g = "$(& nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1)" -split ',\s*'
    $gpuUse = if ($g.Count -eq 2) { [int]$g[0] }; $gpuTemp = if ($g.Count -eq 2) { [double]$g[1] }
}
function Act([string]$What, [scriptblock]$Real) { if ($Do) { & $Do $What } else { & $Real } }
$out = @()

# --- the graphics card: stuck high while idle and cool ---
$gf = @($fans | Where-Object { $_.Hw -eq 'gpu' -and $null -ne $_.Duty })
$stuck = $gf -and $null -ne $gpuUse -and $gpuUse -lt 10 -and $gpuTemp -and $gpuTemp -lt 45 -and -not ($gf | Where-Object { $_.Duty -lt 50 })
if ($stuck) {
    $was = ($gf | Measure-Object Duty -Maximum).Maximum; $rpm = ($gf | Measure-Object Rpm -Maximum).Maximum
    Act 'gpu fans automatic' { foreach ($f in $gf) { try { $f.Control.SetDefault() } catch { } } }
    $recent = @(@($st.gpuResets) | Where-Object { $_ -and [datetime]$_ -gt $Now.AddDays(-7) })
    $st.gpuResets = @($recent) + $Now.ToString('o')
    if (-not $st.gpuReset) { $out += "Fans: the graphics card's fans were stuck at $was% ($rpm RPM) while it was idle at $([int]$gpuTemp) C - put back to automatic (the card's own curve: quiet when cool, faster as it warms)" }
    elseif ($recent.Count -ge 2 -and $st.gpuReset -ne 'again') { $out += "Reminder: something keeps setting the graphics card's fans to $was% at idle (put back to automatic $($recent.Count + 1) times this week) - a fan program (MSI Afterburner, the card maker's app, an RGB tool) may hold a fixed speed; set it to automatic there"; $st.gpuReset = 'again' }
    if (-not $st.gpuReset) { $st.gpuReset = $Now.ToString('o') }
}

# --- the CPU fan and the pump: stopped while driven ---
$cool = @($fans | Where-Object { $_.Hw -eq 'board' -and $_.Name -match '^(CPU|Pump|AIO|W_PUMP|CPU_OPT)' })
$stopped = @($cool | Where-Object { $_.Rpm -eq 0 -and ($null -eq $_.Duty -or $_.Duty -ge 20) } | ForEach-Object Name)
$ranBefore = @(@($st.last) | Where-Object { $_.Rpm -gt 0 } | ForEach-Object Name)
foreach ($n in $stopped) {
    if ($n -notin $ranBefore) { continue }   # (a header with nothing on it reads 0 every time: only one that ran and stopped counts)
    if (@($st.stopped) -contains $n) { continue }
    $out += "WARNING: the $(if ($n -match 'Pump|AIO') { 'water-cooling pump' } else { 'CPU fan' }) ($n) has stopped (0 RPM) - the processor isn't being cooled. Check its cable on the motherboard; if it has failed, don't run games until it's replaced"
}
$st.stopped = @($stopped)
$st.last = @($fans | ForEach-Object { [pscustomobject]@{ Hw = $_.Hw; Name = $_.Name; Rpm = $_.Rpm; Duty = $_.Duty } })
$st | Add-Member at $Now.ToString('o') -Force
if ($computer) { try { $computer.Close() } catch { } }
try { $st | ConvertTo-Json -Depth 4 | Set-Content "$State.tmp" -Encoding UTF8; Move-Item "$State.tmp" $State -Force } catch { }
$out
