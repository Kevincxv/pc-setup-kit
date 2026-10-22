# Game tuning by measurement (10/21, the owner's request): instead of general advice, each of a game's settings that
# only changes speed (never how it looks) is tried both ways on this PC, in the owner's own matches, and the faster
# one is kept. Run by health-check.ps1 (every few hours); game-perf.ps1 measures a minute every 25 minutes of play and
# tags each minute with the value being tried (perf-history.json "tune": "<id>:a" / "<id>:b").
# - One setting at a time. a = the value it has now, b = the other one. Switched only while the game is closed (it
#   writes its settings file when it closes), after 2 measured minutes on a value: a, b, a, b... - so a quiet evening
#   or a busy map doesn't decide it alone. Decided once each value has 4 minutes: b is kept only if it is clearly
#   better (the 1% low or the average 3%+ higher, the other no more than 2% lower, no more hitches); else a stays.
# - Stopped, the owner's value put back: something else changed mid-test (graphics driver, Windows, RAM speed, Memory
#   Integrity - the minutes would not compare), a driver reset during the test, a month without enough play. The
#   owner changing the setting in the game ends that test with their value - it is their choice.
# - Not while a new graphics driver is on trial (gpu-watch.ps1): that test needs the settings to stay as they were.
# - Each result is said once and kept in game-tune.json (the app's Activity > Performance shows the test and results).
# game-settings.ps1 keeps the owner's settings: a value tried or kept here is written to its kept values too.
# kit-options.txt gametune=off (the app's Settings) stops it - a test under way is ended with the owner's value back.
# -Files / -State / -Perf / -GameSettings / -GpuState / -Running / -Conditions / -Cores / -Now / -Options: tests.
param([string[]]$Files, [string]$State = "$PSScriptRoot\game-tune.json", [string]$Perf = "$PSScriptRoot\perf-history.json",
    [string]$GameSettings = "$PSScriptRoot\game-settings.json", [string]$GpuState = "$PSScriptRoot\gpu-state.json", [string]$Running,
    [string]$Conditions, [int]$Cores, [datetime]$Now = (Get-Date), [string]$Options = "$PSScriptRoot\kit-options.txt")
$ErrorActionPreference = 'SilentlyContinue'
$game = 'cod'; $name = 'Call of Duty'
if (-not $PSBoundParameters.ContainsKey('Files')) { $Files = @(Get-ChildItem "$env:LOCALAPPDATA\Activision\Call of Duty\players\s.1.0.cod*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object FullName) }
if (-not $Cores) { $Cores = [int]((Get-CimInstance Win32_Processor | Measure-Object NumberOfCores -Sum).Sum) }

# --- the settings tried: only speed, never looks (10/21: Call of Duty) ---
# alt: the value tried against the current one ($null: nothing to try); say: the value in words
$exps = @(
    @{ id = 'reflex'; key = 'NvidiaReflex@0'; label = 'Reflex Boost'
        alt = { param($v) if ($v -eq 'Enabled + boost') { 'Enabled' } elseif ($v -eq 'Enabled') { 'Enabled + boost' } }
        say = { param($v) if ($v -eq 'Enabled + boost') { 'Reflex Boost on' } else { 'Reflex Boost off' } } }
    @{ id = 'vram'; key = 'VideoMemoryScaleMP@0'; label = 'the video memory budget'
        alt = { param($v) $x = 0.0; if ([double]::TryParse($v, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$x)) { if ($x -ge 0.8) { '0.750000' } else { '0.850000' } } }
        say = { param($v) $x = 0.0; [void][double]::TryParse($v, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$x); "a $([int][Math]::Round($x * 100))% video memory budget" } }
    @{ id = 'workers'; key = 'RendererWorkerCount@0'; label = 'the renderer thread count'
        alt = { param($v) $n = 0; if ($Cores -ge 4 -and [int]::TryParse($v, [ref]$n)) { if ($n -ne $Cores) { "$Cores" } else { "$($Cores - 1)" } } }
        say = { param($v) if ($v -eq '-1') { 'automatic renderer threads' } else { "$v renderer threads" } } }
)
function Exp($id) { $exps | Where-Object { $_.id -eq $id } | Select-Object -First 1 }

$st = try { Get-Content $State -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { $null }
if ($st -isnot [Management.Automation.PSCustomObject]) { $st = [pscustomobject]@{} }
$active = $st.active; $done = @($st.done | Where-Object { $_.id })
$changed = $false
function Save {
    $o = [ordered]@{ active = $script:active; done = @($script:done); keys = @($exps | ForEach-Object { $_.key }) }
    try { ConvertTo-Json -InputObject $o -Depth 5 | Set-Content "$State.tmp" -Encoding UTF8; Move-Item "$State.tmp" $State -Force } catch { }
}

# --- the settings file: read one value, write one (and game-settings.ps1's kept copy of it) ---
function Get-Value([string]$f, [string]$key) {
    foreach ($l in [IO.File]::ReadAllLines($f)) { if ($l -match '^(\w+@\d+);\d+;\d+ = ([^/]*?)\s*(//.*)?$' -and $Matches[1] -eq $key) { return $Matches[2].Trim() } }
}
function Set-Value([string]$f, [string]$key, [string]$val) {
    $lines = [IO.File]::ReadAllLines($f); $hit = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^(\w+@\d+)(;\d+;\d+ = )([^/]*?)(\s*//.*)?$' -and $Matches[1] -eq $key) { $lines[$i] = $Matches[1] + $Matches[2] + $val + $(if ($Matches[4]) { ' ' + $Matches[4].Trim() }); $hit = $true }
    }
    if (-not $hit) { return $false }
    try { [IO.File]::WriteAllLines($f, $lines, (New-Object Text.UTF8Encoding $false)) } catch { return $false }
    $gs = try { Get-Content $GameSettings -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { $null }
    if ($gs -and $gs.$f -and $gs.$f.values -and $gs.$f.values.PSObject.Properties[$key]) {
        $gs.$f.values.$key = $val
        try { ConvertTo-Json -InputObject $gs -Depth 4 | Set-Content "$GameSettings.tmp" -Encoding UTF8; Move-Item "$GameSettings.tmp" $GameSettings -Force } catch { }
    }
    $true
}
# ends the test under way: $keep ('a' / 'b') is the value left in the game; a line in done
function End-Test([string]$keep, [string]$why, [hashtable]$nums = @{}) {
    $a = $script:active
    if ($keep -and (Test-Path $a.file)) { $want = if ($keep -eq 'b') { $a.b } else { $a.a }; if ((Get-Value $a.file $a.key) -ne $want) { [void](Set-Value $a.file $a.key $want) } }
    $r = [ordered]@{ id = $a.id; game = $a.game; label = $a.label; a = $a.a; b = $a.b; kept = $(if ($keep -eq 'b') { $a.b } elseif ($keep -eq 'a') { $a.a } else { $null }); why = $why; at = $Now.ToString('o') }
    foreach ($k in $nums.Keys) { $r[$k] = $nums[$k] }
    $script:done = @($script:done) + [pscustomobject]$r; $script:active = $null; $script:changed = $true
}

# --- switched off: a test under way ends with the owner's value back ---
$off = Select-String -Path $Options -Pattern '^\s*gametune\s*=\s*off\s*$' -Quiet
$gameOn = if ($PSBoundParameters.ContainsKey('Running')) { $Running -eq 'yes' } else { [bool](Get-Process -Name $game -ErrorAction SilentlyContinue) }
if ($gameOn) { return }   # its settings file is written when it closes: nothing now
if ($off) { if ($active) { $back = & (Exp $active.id).say $active.a; End-Test 'a' 'switched off in Settings'; Save; "$name tuning: switched off - $back is back (as before the test)" }; return }
if (-not $Files -or -not (Test-Path $Files[0])) { return }
$file = $Files[0]

# --- what the numbers depend on: a change mid-test ends it (its minutes would not compare) ---
if (-not $Conditions) {
    $drv = "$((Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA|AMD|Radeon|Intel\(R\) Arc' } | Select-Object -First 1).DriverVersion)"
    $bld = "$([Environment]::OSVersion.Version.Build).$((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR)"
    $ram = "$((Get-CimInstance Win32_PhysicalMemory | Select-Object -First 1).ConfiguredClockSpeed) MT/s"
    $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
    $Conditions = "$drv|$bld|$ram|$(if (@($dg.SecurityServicesRunning) -contains 2) { 'on' } else { 'off' })"
}
function Env-Of($r) { "$($r.driver)|$($r.build)|$($r.ram)|$($r.hvci)" }
$gw = try { Get-Content $GpuState -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { $null }
$trial = $gw.trial -and -not $gw.trial.verdict

$pj = try { Get-Content $Perf -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { }
$mins = @($pj | ForEach-Object { $_ } | Where-Object { $_ -is [Management.Automation.PSCustomObject] -and $_.game -eq $game -and $(try { [void][datetime]"$($_.date)"; $true } catch { $false }) })
function Median($v) { $s = @($v | Sort-Object); if (-not $s) { return 0 }; $m = [int][Math]::Floor($s.Count / 2); if ($s.Count % 2) { [double]$s[$m] } else { ([double]$s[$m - 1] + [double]$s[$m]) / 2 } }
function Pct($x, $y) { if ($y -gt 0) { [Math]::Round(($x - $y) / $y * 100) } else { 0 } }

if ($active) {
    $x = Exp $active.id; $sayA = & $x.say $active.a; $sayB = & $x.say $active.b; $lbl = $active.label   # (End-Test clears $active)
    $started = [datetime]$active.started
    $mine = @($mins | Where-Object { "$($_.tune)" -like "$($active.id):*" -and [datetime]$_.date -ge $started -and (Env-Of $_) -eq $active.env })
    $sa = @($mine | Where-Object { $_.tune -eq "$($active.id):a" }); $sb = @($mine | Where-Object { $_.tune -eq "$($active.id):b" })
    $is = Get-Value $file $active.key; $want = if ($active.arm -eq 'b') { $active.b } else { $active.a }
    $resets = @($gw.resets | Where-Object { $_ -and [datetime]$_ -ge $started })
    if ($is -ne $want) {
        End-Test $null "you changed it yourself in the game ($(& $x.say $is))"
        "$name tuning: you changed $lbl yourself - your choice is kept, and that test is over"
    }
    elseif ($Conditions -ne $active.env) {
        End-Test 'a' 'something else changed during the test (a graphics driver, Windows, the RAM speed or Memory Integrity)'
        "$name tuning: the $lbl test was stopped - something else changed in the middle of it (a driver, Windows, the RAM speed or Memory Integrity), so its minutes would not compare. $sayA is back; it is tried again later"
    }
    elseif ($resets) {
        End-Test 'a' 'the graphics driver reset during the test'
        "$name tuning: the graphics driver stopped responding during the $lbl test - $sayA is back to be safe"
    }
    elseif ($sa.Count -ge 4 -and $sb.Count -ge 4) {
        $fa = Median ($sa | ForEach-Object { $_.fps }); $fb = Median ($sb | ForEach-Object { $_.fps })
        $la = Median ($sa | ForEach-Object { $_.low1 }); $lb = Median ($sb | ForEach-Object { $_.low1 })
        $ha = Median ($sa | ForEach-Object { [double]$_.stutters }); $hb = Median ($sb | ForEach-Object { [double]$_.stutters })
        $bWins = (($lb -ge $la * 1.03 -and $fb -ge $fa * 0.98) -or ($fb -ge $fa * 1.03 -and $lb -ge $la * 0.98)) -and $hb -le $ha * 1.5 + 2
        $nums = @{ aFps = [Math]::Round($fa, 1); bFps = [Math]::Round($fb, 1); aLow = [Math]::Round($la, 1); bLow = [Math]::Round($lb, 1); aN = $sa.Count; bN = $sb.Count }
        $diff = "1% low $([int]$la) -> $([int]$lb) fps ($(if ((Pct $lb $la) -ge 0) { '+' })$(Pct $lb $la)%), average $([int]$fa) -> $([int]$fb) fps ($(if ((Pct $fb $fa) -ge 0) { '+' })$(Pct $fb $fa)%)"
        if ($bWins) { End-Test 'b' 'faster' $nums; "$name tuning: $sayB is faster on this PC than $sayA - $diff over $($sb.Count) minutes of play each; switched to it" }
        else { End-Test 'a' 'no faster' $nums; "$name tuning: $sayB was no faster than $sayA ($diff over $($sa.Count) minutes of play each) - kept $sayA" }
    }
    elseif ($started -lt $Now.AddDays(-30)) {
        End-Test 'a' 'not enough play in 30 days'
        "$name tuning: not enough play in a month to finish the $lbl test - $sayA is back"
    }
    else {
        # 2 minutes on this value since it was put on: the other one's turn (unless it already has its 4)
        $arm = $active.arm; $other = if ($arm -eq 'a') { 'b' } else { 'a' }
        $onArm = @($mine | Where-Object { $_.tune -eq "$($active.id):$arm" -and [datetime]$_.date -ge [datetime]$active.armSince }).Count
        $otherN = if ($other -eq 'a') { $sa.Count } else { $sb.Count }
        if ($onArm -ge 2 -and $otherN -lt 4) {
            $val = if ($other -eq 'b') { $active.b } else { $active.a }
            if (Set-Value $file $active.key $val) { $active.arm = $other; $active.armSince = $Now.ToString('o'); $changed = $true }
        }
    }
}
elseif (-not $trial) {
    # --- the next setting to try: one not tried yet (or tried before something else changed - a test stopped part-way) ---
    $tried = @($done | Where-Object { $_.why -notmatch '^something else changed' } | ForEach-Object { $_.id })
    foreach ($x in $exps) {
        if ($x.id -in $tried) { continue }
        $cur = Get-Value $file $x.key; if ($null -eq $cur) { continue }
        $alt = & $x.alt $cur; if (-not $alt) { continue }
        $active = [pscustomobject][ordered]@{ id = $x.id; game = $game; label = $x.label; key = $x.key; file = $file; a = $cur; b = $alt; arm = 'a'; started = $Now.ToString('o'); armSince = $Now.ToString('o'); env = $Conditions }
        $changed = $true
        "$name tuning: trying $($x.label) both ways in your next matches - $(& $x.say $cur) (as now) against $(& $x.say $alt); the faster one is kept (Activity > Performance)"
        break
    }
}
if ($changed) { Save }
