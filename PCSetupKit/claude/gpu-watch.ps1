# The graphics driver, watched at every check (run by health-check.ps1):
# - Driver resets (TDR): the driver stopped responding and Windows restarted it - in a game that's a freeze or a black
#   screen for a moment, no blue screen, so nothing else notices. Counted over 7 days: 1-2 = Reminder, 3+ = WARNING;
#   when they began right after a driver update, that driver is named as the likely cause.
# - A new driver version: the old shader caches (NVIDIA/AMD/Intel and DirectX's) are cleared once, since they were
#   built for the old driver - never under a game (then at the next check). Games rebuild them on first start.
# State: gpu-state.json (driver version and since when, recent resets). Prints only what's worth saying.
# -Since: the last check; -State/-Root/-TestDriver/-TestEvents/-TestGame: tests.
param([datetime]$Since = (Get-Date).AddDays(-7), [string]$State = "$PSScriptRoot\gpu-state.json", [datetime]$Now = (Get-Date),
    [string]$Root, [string]$TestDriver, [object[]]$TestEvents, [string]$TestGame)
$ErrorActionPreference = 'SilentlyContinue'
$s = try { Get-Content $State -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { $null }
if (-not $s) { $s = [pscustomobject]@{} }
foreach ($k in 'driver', 'driverSince', 'cachePending') { if (-not ($s.PSObject.Properties.Name -contains $k)) { $s | Add-Member $k $null } }
if (-not ($s.PSObject.Properties.Name -contains 'resets')) { $s | Add-Member resets @() }

$drv = $TestDriver
if (-not $drv) { $drv = "$((Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA|AMD|Radeon|Intel\(R\) Arc' } | Select-Object -First 1).DriverVersion)" }
$prev = $s.driver
if ($drv -and $drv -ne $prev) {
    if ($prev) { $s.cachePending = $drv }   # the first check only records the version
    $s.driver = $drv; $s.driverSince = $Now.ToString('o')
}

# --- driver resets since the last check: the Display 4101 event, NVIDIA's own reset event, and the live kernel
# reports Windows writes for them (WER: LiveKernelEvent 141 / 117) - one reset often logs all three, so one per minute ---
$ev = if ($null -ne $TestEvents) { $TestEvents } else {
    @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Display'; Id = 4101; StartTime = $Since }) +
    @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'nvlddmkm'; Id = 153; StartTime = $Since }) +
    @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Windows Error Reporting'; Id = 1001; StartTime = $Since } | Where-Object { $_.Message -match 'LiveKernelEvent' -and $_.Message -match '\b(141|117)\b' })
}
$new = @($ev | Where-Object { $_ } | ForEach-Object { $_.TimeCreated.ToString('yyyy-MM-ddTHH:mm') } | Sort-Object -Unique)
$all = @(@($s.resets) + $new | Where-Object { $_ } | Sort-Object -Unique | Where-Object { [datetime]$_ -gt $Now.AddDays(-60) })
$s.resets = $all
if ($new) {
    $week = @($all | Where-Object { [datetime]$_ -gt $Now.AddDays(-7) }).Count
    $lvl = if ($week -ge 3) { 'WARNING' } else { 'Reminder' }
    $msg = "${lvl}: the graphics driver stopped responding and restarted $($new.Count) time(s) since the last check ($week in 7 days) - a freeze or black screen for a moment in a game"
    # began with the current driver: none in the 14 days before it came, and it came in the last 30 days
    $ds = if ($s.driverSince) { [datetime]$s.driverSince }
    if ($prev -ne $null -and $ds -and $ds -gt $Now.AddDays(-30) -and -not ($all | Where-Object { [datetime]$_ -lt $ds -and [datetime]$_ -gt $ds.AddDays(-14) })) {
        $msg += "; it began after driver $drv was installed on $($ds.ToString('d')) - if it keeps happening, go back to the previous graphics driver (one click in the app: Maintenance > Graphics driver)"
    }
    else { $msg += "; driver $drv - common causes: a graphics card overclock or undervolt, the power cables to the card, an overheating card" }
    $msg
}

# --- a new driver: clear the old shader caches once, never under a game ---
if ($s.cachePending) {
    $game = if ($PSBoundParameters.ContainsKey('TestGame')) { $TestGame } else { & "$PSScriptRoot\game-check.ps1" }
    if (-not $game) {
        $la = if ($Root) { "$Root\Local" } else { $env:LOCALAPPDATA }
        $lo = if ($Root) { "$Root\LocalLow" } else { "$env:USERPROFILE\AppData\LocalLow" }
        $pd = if ($Root) { "$Root\ProgramData" } else { $env:ProgramData }
        $dirs = "$la\NVIDIA\DXCache", "$la\NVIDIA\GLCache", "$la\NVIDIA Corporation\NV_Cache", "$pd\NVIDIA Corporation\NV_Cache",
            "$la\AMD\DxCache", "$la\AMD\DxcCache", "$la\AMD\VkCache", "$la\AMD\GLCache", "$lo\Intel\ShaderCache", "$la\D3DSCache"
        $freed = 0L
        foreach ($d in $dirs | Where-Object { Test-Path $_ }) {
            foreach ($f in Get-ChildItem $d -Recurse -File -Force) { $len = $f.Length; try { [IO.File]::Delete($f.FullName); $freed += $len } catch { } }   # in use: skipped
        }
        $s.cachePending = $null
        if ($freed -gt 0) { "Graphics driver updated to $drv - cleared its old shader caches ($([Math]::Round($freed / 1MB)) MB); each game rebuilds its cache on first start, so it may stutter briefly once" }
    }
}
try { $s | ConvertTo-Json -Depth 3 | Set-Content "$State.tmp" -Encoding UTF8; Move-Item "$State.tmp" $State -Force } catch {}
