# The graphics driver, watched at every check (run by health-check.ps1):
# - Driver resets (TDR): the driver stopped responding and Windows restarted it - in a game that's a freeze or a black
#   screen for a moment, no blue screen, so nothing else notices. Counted over 7 days: 1-2 = Reminder, 3+ = WARNING;
#   when they began right after a driver update, that driver is named as the likely cause.
# - A new driver version: the old shader caches (NVIDIA/AMD/Intel and DirectX's) are cleared once, since they were
#   built for the old driver - never under a game (then at the next check). Games rebuild them on first start.
# - A new driver that crashes (10/2): 3+ driver resets, or 2+ graphics blue screens, within its first 14 days - when the
#   previous driver had none in its last 14 days - and Messiah goes back to the previous driver by itself (gpu-rollback.ps1
#   -Yes: a restore point first, never under a game, the bad version held back until a newer one comes). Once per driver
#   version; kit-options.txt autorollback=off stops it (then it stays a WARNING with the one-click button).
# - A new driver on trial (10/21): the owner's games measured on it (perf-history.json) against the driver before; clearly
#   slower - back to the one before the same way. The result is kept for the app (gpu-state.json trial).
# State: gpu-state.json (driver version and since when, recent resets and graphics blue screens). Prints only what's worth saying.
# -Since: the last check; -State/-Root/-TestDriver/-TestEvents/-TestGame: tests.
param([datetime]$Since = (Get-Date).AddDays(-7), [string]$State = "$PSScriptRoot\gpu-state.json", [datetime]$Now = (Get-Date),
    [string]$Root, [string]$TestDriver, [object[]]$TestEvents, [string]$TestGame, [object[]]$TestBsods, [scriptblock]$Rollback, [string]$Options = "$PSScriptRoot\kit-options.txt",
    [string]$PerfHistory = "$PSScriptRoot\perf-history.json")
$ErrorActionPreference = 'SilentlyContinue'
$s = try { Get-Content $State -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { $null }
if ($s -isnot [Management.Automation.PSCustomObject]) { $s = [pscustomobject]@{} }   # (valid JSON of the wrong shape - a number, a list - counts as no state, never as an error)
foreach ($k in 'driver', 'driverSince', 'cachePending') { if (-not ($s.PSObject.Properties.Name -contains $k)) { $s | Add-Member $k $null } }
foreach ($k in 'resets', 'bsods') { if (-not ($s.PSObject.Properties.Name -contains $k)) { $s | Add-Member $k @() } }
if (-not ($s.PSObject.Properties.Name -contains 'rolledBack')) { $s | Add-Member rolledBack $null }
if (-not ($s.PSObject.Properties.Name -contains 'trial')) { $s | Add-Member trial $null }

$drv = $TestDriver
if (-not $drv) { $drv = "$((Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA|AMD|Radeon|Intel\(R\) Arc' } | Select-Object -First 1).DriverVersion)" }
$prev = $s.driver
if ($drv -and $drv -ne $prev) {
    if ($prev) { $s.cachePending = $drv; $s.trial = [pscustomobject]@{ driver = $drv; from = $prev; since = $Now.ToString('o'); verdict = $null; text = $null } }   # the first check only records the version
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
        $msg += "; it began after driver $drv was installed on $($ds.ToString('d')) - if it keeps happening, Messiah goes back to the previous driver by itself (or one click now: Maintenance > Graphics driver)"
    }
    else { $msg += "; driver $drv - common causes: a graphics card overclock or undervolt, the power cables to the card, an overheating card" }
    $msg
}

# --- blue screens that are the graphics driver's (by Windows' bug check code: VIDEO_TDR_FAILURE 0x116, its timeout 0x117,
# VIDEO_SCHEDULER_INTERNAL_ERROR 0x119, VIDEO_DXGKRNL_FATAL_ERROR 0x113, VIDEO_MEMORY_MANAGEMENT_INTERNAL 0x10e) ---
$bev = if ($null -ne $TestBsods) { $TestBsods } elseif ($null -ne $TestEvents) { @() } else {   # (tests: made-up events only)
    @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $Since } |
        Where-Object { $_.Message -match '0x0000(0116|0117|0119|0113|010e)\b' })
}
$s.bsods = @(@($s.bsods) + @($bev | Where-Object { $_ } | ForEach-Object { $_.TimeCreated.ToString('yyyy-MM-ddTHH:mm') }) | Where-Object { $_ } | Sort-Object -Unique | Where-Object { [datetime]$_ -gt $Now.AddDays(-60) })

# --- the new driver crashes, the one before didn't: back to the one before, by itself ---
$ds = if ($s.driverSince) { [datetime]$s.driverSince }
$optOff = @(Get-Content $Options -ErrorAction SilentlyContinue) -match '^\s*autorollback\s*=\s*off\s*$'
if ($ds -and $prev -ne $null -and $drv -and $s.rolledBack -ne $drv -and -not $optOff -and $Now -lt $ds.AddDays(14)) {
    $after = @($s.resets | Where-Object { [datetime]$_ -ge $ds }).Count; $afterB = @($s.bsods | Where-Object { [datetime]$_ -ge $ds }).Count
    $before = @(@($s.resets) + @($s.bsods) | Where-Object { [datetime]$_ -lt $ds -and [datetime]$_ -gt $ds.AddDays(-14) }).Count
    if (($after -ge 3 -or $afterB -ge 2) -and $before -eq 0) {
        $why = "$(@(if ($after) { "$after driver reset(s)" }) + @(if ($afterB) { "$afterB blue screen(s)" }) -join ' and ') since it was installed on $($ds.ToString('d'))"
        # (never the real one under tests: they pass -Rollback)
        $res = @(if ($Rollback) { & $Rollback } elseif (-not $env:PCKIT_IN_TESTS -and $null -eq $TestEvents) { & "$PSScriptRoot\gpu-rollback.ps1" -Yes })
        if ("$res" -match '^Graphics driver: back on') {
            $s.rolledBack = $drv; if ($s.trial -and $s.trial.driver -eq $drv) { $s.trial.verdict = 'rolled back'; $s.trial.text = "it caused $why - went back to $($s.trial.from)" }
            "Graphics driver: $drv caused $why - went back to the previous driver by itself ($res). The faulty version is held back until a newer one comes"
        }
        elseif (-not $res -or "$res" -match '^Close ') { }   # a game runs (or a test without a stand-in): at the next check
        else { $s.rolledBack = $drv; "WARNING: graphics driver $drv caused $why, and going back by itself wasn't possible: $res" }
    }
}
# --- a new driver on trial (10/21): the owner's games on it against the driver before. game-perf.ps1 measures a minute
# every 25 minutes of play; once a game has 3 on each driver (under the same Windows, RAM speed, Memory Integrity and game
# settings - else the driver is not what changed), the most-played one decides: clearly slower (1% low 10%+ down, or the
# average 8%+ down) - back to the driver before, like a crashing one (autorollback=off: a WARNING instead); else it
# passed. game-tune.ps1 tries no setting while a driver is on trial. Not enough play within 14 days: left as it is. ---
$tr = $s.trial
if ($tr -and -not $tr.verdict -and $tr.driver -eq $drv) {
    $trSince = [datetime]$tr.since
    $pj = try { Get-Content $PerfHistory -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { }
    $mins = @($pj | ForEach-Object { $_ } | Where-Object { $_ -is [Management.Automation.PSCustomObject] -and $_.game -and "$($_.tune)" -notlike '*:b' -and $(try { [void][datetime]"$($_.date)"; $true } catch { $false }) })
    function Median($v) { $q = @($v | Sort-Object); if (-not $q) { return 0 }; $m = [int][Math]::Floor($q.Count / 2); if ($q.Count % 2) { [double]$q[$m] } else { ([double]$q[$m - 1] + [double]$q[$m]) / 2 } }
    $res = foreach ($g in $mins | Group-Object game) {
        $key = { param($r) "$($r.build)|$($r.ram)|$($r.hvci)|$($r.settings)" }
        $aft = @($g.Group | Where-Object { $_.driver -eq $tr.driver -and [datetime]$_.date -ge $trSince })
        if ($aft.Count -lt 3) { continue }
        $k = ($aft | Group-Object { & $key $_ } | Sort-Object Count -Descending | Select-Object -First 1).Name
        $aft = @($aft | Where-Object { (& $key $_) -eq $k })
        $bef = @($g.Group | Where-Object { $_.driver -eq $tr.from -and [datetime]$_.date -lt $trSince -and [datetime]$_.date -gt $trSince.AddDays(-45) -and (& $key $_) -eq $k } | Select-Object -Last 10)
        if ($aft.Count -lt 3 -or $bef.Count -lt 3) { continue }
        [pscustomobject]@{ Game = $g.Name; N = $aft.Count; F0 = Median ($bef | ForEach-Object { $_.fps }); F1 = Median ($aft | ForEach-Object { $_.fps }); L0 = Median ($bef | ForEach-Object { $_.low1 }); L1 = Median ($aft | ForEach-Object { $_.low1 }) }
    }
    $main = @($res) | Sort-Object N -Descending | Select-Object -First 1
    if ($main) {
        $nums = "1% low $([int]$main.L0) -> $([int]$main.L1) fps, average $([int]$main.F0) -> $([int]$main.F1) fps"
        if ($main.L1 -le $main.L0 * 0.90 -or $main.F1 -le $main.F0 * 0.92) {
            $why = "$($main.Game) runs slower on it than on $($tr.from) ($nums)"
            if ($optOff) { $tr.verdict = 'slower'; $tr.text = $why; "WARNING: graphics driver $drv - $why; going back is one click (Settings > Tools > Go back to the previous graphics driver)" }
            else {
                $r = @(if ($Rollback) { & $Rollback } elseif (-not $env:PCKIT_IN_TESTS -and $null -eq $TestEvents) { & "$PSScriptRoot\gpu-rollback.ps1" -Yes })
                if ("$r" -match '^Graphics driver: back on') { $s.rolledBack = $drv; $tr.verdict = 'rolled back'; $tr.text = "$why - went back to $($tr.from)"; "Graphics driver: $drv failed its test - $why. Went back to the previous driver by itself ($r); $drv is held back until a newer one comes" }
                elseif (-not $r -or "$r" -match '^Close ') { }   # a game runs: at the next check
                else { $tr.verdict = 'slower'; $tr.text = $why; "WARNING: graphics driver $drv - $why, and going back by itself wasn't possible: $r" }
            }
        }
        else { $tr.verdict = 'passed'; $tr.text = "$($main.Game): $nums against $($tr.from)"; "Graphics driver $drv passed its test - $($main.Game) runs as well as on $($tr.from) or better ($nums)" }
    }
    elseif ($Now -gt $trSince.AddDays(14)) { $tr.verdict = 'not tested'; $tr.text = 'not enough play in its first 2 weeks to compare' }
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
