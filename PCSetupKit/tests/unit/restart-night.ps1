# restart-night.ps1: a pending update finishes with a restart at night - only while nobody uses the PC. Made-up
# situations (-Test); the restart goes to a recorder, never to Windows.
. "$PSScriptRoot\..\lib.ps1"
$rn = "$Src\restart-night.ps1"
if (-not (Test-Path $rn)) { Skip 'restart-night' 'not installed here'; Finish }
$log = "$Work\restart-night.log"
$global:acts = @()
$rec = { param($w) $global:acts += $w }
function RN([hashtable]$over = @{}) {
    $t = @{ Option = $null; Pending = $true; Hour = 4; IdleMin = 120; Game = $null; OnBattery = $false; Busy = $null; DevPc = $false; Restarted = $false }
    foreach ($k in $over.Keys) { $t[$k] = $over[$k] }
    $global:acts = @(); @(& $rn -Test $t -Do $rec -Log $log)
}
$o = RN
Check 'an update waiting, 4 AM, unused for 2 hours, plugged in: restart with a 5-minute warning' (($acts -join ',') -eq 'restart in 5 min' -and "$o" -match 'restarting to finish updates') ($o -join ' / ')
Check '... written to its log' ((Get-Content $log -Raw) -match 'Restarting to finish updates') ''
$o = RN @{ Restarted = $true }
Check '... once a night' (-not $acts) ''
$o = RN @{ Pending = $false }
Check 'nothing waiting for a restart: nothing' (-not $acts -and -not $o) ''
$o = RN @{ IdleMin = 20 }
Check 'the PC was used 20 min ago: waits (someone may be there)' (-not $acts -and "$o" -match 'used 20 min ago') ($o -join ' / ')
$o = RN @{ Game = 'Test Game' }
Check 'a game running: waits' (-not $acts -and "$o" -match 'Test Game') ($o -join ' / ')
$o = RN @{ OnBattery = $true }
Check 'on battery: waits' (-not $acts) ''
$o = RN @{ Busy = 'Global\ClaudeBgMaint' }
Check 'maintenance running: waits' (-not $acts -and "$o" -match 'maintenance is running') ''
$o = RN @{ Hour = 14 }
Check 'the afternoon: never' (-not $acts) ''
$o = RN @{ Option = 'off' }
Check 'switched off in Settings: never' (-not $acts) ''
$o = RN @{ DevPc = $true }
Check 'the PC the kit is made on: off unless its owner turns it on' (-not $acts) ''
$o = RN @{ DevPc = $true; Option = 'on' }
Check '... turned on there: works' ($acts -contains 'restart in 5 min') ''
Check 'the real restart has a 5-minute warning and the way to stop it' ((Get-Content $rn -Raw) -match '/r /t 300' -and (Get-Content $rn -Raw) -match 'Cancel restart') ''
Finish
