# The owner's game settings, kept (10/21: Call of Duty - its settings file, players\s.1.0.cod*.txt): a game patch or a
# new graphics driver can put a game back to its "recommended" settings - the owner's tuned ones are put back by
# themselves. Each check (health-check.ps1), only while the game is closed (it writes the file when it closes):
#   - first time: the settings as they are now are the ones kept (game-settings.json)
#   - a few changed (1-4): the owner changed them in the game - kept as the new ones, nothing said
#   - many changed at once (5+): a reset - the kept ones go back in (the file before is saved next to it), said
# Also: a new graphics driver means the game compiles its shaders again - the first matches stutter unless they're
# done at the main menu: said once per driver, while such a game is installed.
# kit-options.txt gamesettings=off (the app's Settings) stops it. Read-only otherwise. -Files / -State / -Running /
# -Driver / -Options: tests (nothing real is read).
param([string[]]$Files, [string]$State = "$PSScriptRoot\game-settings.json", [string]$Running, [string]$Driver, [string]$Options = "$PSScriptRoot\kit-options.txt")
$ErrorActionPreference = 'SilentlyContinue'
if (Select-String -Path $Options -Pattern '^\s*gamesettings\s*=\s*off\s*$' -Quiet) { return }
if (-not $Files) { $Files = @(Get-ChildItem "$env:LOCALAPPDATA\Activision\Call of Duty\players\s.1.0.cod*.txt" -ErrorAction SilentlyContinue | ForEach-Object FullName) }
if (-not $Files) { return }
# not kept: sound, devices, the window, what the game writes about the PC itself (they change on their own)
$skip = 'Volume@|Device@|^Window|Position@|DriverVersion@|^GPUName@|^Monitor@|^Resolution@|^RefreshRate@|LastUsed|Telemetry|Timestamp|Seen@'   # (Volume@: VolumetricQuality is a setting)
function Read-Settings([string]$f) {
    $o = [ordered]@{}
    foreach ($l in [IO.File]::ReadAllLines($f)) { if ($l -match '^(\w+@\d+);\d+;\d+ = ([^/]*?)\s*(//.*)?$') { $k = $Matches[1]; if ($k -notmatch $skip) { $o[$k] = $Matches[2].Trim() } } }
    $o
}
$st = @{}; try { (Get-Content $State -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).PSObject.Properties | ForEach-Object { $st[$_.Name] = $_.Value } } catch { }
$gameOn = if ($PSBoundParameters.ContainsKey('Running')) { $Running -eq 'yes' } else { [bool](Get-Process -Name cod -ErrorAction SilentlyContinue) }   # (not $running: the [string] -Running is the same variable)
$changed = $false
foreach ($f in $Files) {
    if (-not (Test-Path $f) -or $gameOn) { continue }
    $game = 'Call of Duty'
    $now = Read-Settings $f
    $kept = $st[$f]
    if (-not $kept) { $st[$f] = [pscustomobject]@{ at = (Get-Date).ToString('o'); values = [pscustomobject]$now }; $changed = $true; continue }
    $vals = @{}; $kept.values.PSObject.Properties | ForEach-Object { $vals[$_.Name] = "$($_.Value)" }
    $diff = @($vals.Keys | Where-Object { $now.Contains($_) -and $now[$_] -ne $vals[$_] })
    if ($diff.Count -eq 0) { continue }
    if ($diff.Count -lt 5) {   # the owner's own change in the game: these are the settings now
        foreach ($k in $diff) { $vals[$k] = $now[$k] }
        $st[$f] = [pscustomobject]@{ at = (Get-Date).ToString('o'); values = [pscustomobject]$vals }; $changed = $true; continue
    }
    # a reset: the kept values back in, everything else in the file as the game wrote it
    Copy-Item $f "$f.before-reset" -Force
    $lines = [IO.File]::ReadAllLines($f)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^(\w+@\d+)(;\d+;\d+ = )([^/]*?)(\s*//.*)?$' -and $vals.ContainsKey($Matches[1]) -and $Matches[3].Trim() -ne $vals[$Matches[1]]) {
            $lines[$i] = $Matches[1] + $Matches[2] + $vals[$Matches[1]] + $(if ($Matches[4]) { ' ' + $Matches[4].Trim() })
        }
    }
    try { [IO.File]::WriteAllLines($f, $lines, (New-Object Text.UTF8Encoding $false)); "$game`: $($diff.Count) of your settings had been reset (a game update or a new driver) - re-applied your tuned ones" } catch { }
}
# a new graphics driver: the shaders are compiled again at the next start - better at the main menu than in a match
$drv = if ($Driver) { $Driver } else { "$((Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA|AMD|Radeon|Intel\(R\) Arc' } | Select-Object -First 1).DriverVersion)" }
if ($drv) {
    if ($st['driver'] -and $st['driver'] -ne $drv) { "Reminder: new graphics driver ($drv) - start Call of Duty and let it finish compiling shaders at the main menu (the bar at the bottom) before your first match, or the first matches stutter" }
    if ($st['driver'] -ne $drv) { $st['driver'] = $drv; $changed = $true }
}
if ($changed) { try { ConvertTo-Json -InputObject $st -Depth 4 | Set-Content "$State.tmp" -Encoding UTF8; Move-Item "$State.tmp" $State -Force } catch { } }
