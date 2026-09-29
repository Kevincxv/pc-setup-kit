# gpu-rollback.ps1: back to the graphics driver before the current one, only when it's still on the PC; never under a
# game; the version it went back from held. Made-up drivers (-Test); actions go to a recorder - no driver changes.
. "$PSScriptRoot\..\lib.ps1"
$gr = "$Src\gpu-rollback.ps1"
if (-not (Test-Path $gr)) { Skip 'gpu-rollback' 'not installed here'; Finish }
$bl = "$Work\blocklist.txt"; $hold = "$Work\gpu-hold.txt"
$global:acts = @()
$rec = { param($w) $global:acts += $w }
function New-T([hashtable]$over = @{}) {
    $t = @{ Current = @{ Device = 'NVIDIA GeForce TEST'; Inf = 'oem20.inf'; Ver = '32.0.15.6094'; Date = '2026-09-01'; Provider = 'NVIDIA' }
        Packages = @(@{ Pub = 'oem20.inf'; Name = 'nv_dispi.inf'; Ver = '32.0.15.6094'; Date = '2026-09-01' }, @{ Pub = 'oem11.inf'; Name = 'nv_dispi.inf'; Ver = '32.0.15.5612'; Date = '2026-07-01' },
            @{ Pub = 'oem9.inf'; Name = 'nv_dispi.inf'; Ver = '32.0.15.5000'; Date = '2026-03-01' }, @{ Pub = 'oem30.inf'; Name = 'other.inf'; Ver = '40.0.0.1'; Date = '2026-01-01' })
        Game = $null; DeleteOk = $true; NvidiaVersion = '560.94' }
    foreach ($k in $over.Keys) { $t[$k] = $over[$k] }; $t
}
function GR($t, [switch]$List) { $global:acts = @(); foreach ($f in $bl, $hold) { [IO.File]::Delete($f) }; @(& $gr -Test $t -Do $rec -Blocklist $bl -Hold $hold -List:$List) }

$o = GR (New-T) -List
Check '-List: the current driver and the one before it (the newest older version of the same driver)' ($o[0].Can -and $o[0].Previous -eq '32.0.15.5612' -and $o[0].Current -eq '32.0.15.6094' -and -not $acts) "$($o[0] | Out-String)"
$o = GR (New-T)
Check 'going back: a restore point, then the current package removed and the devices scanned' (($acts -join ',') -eq 'restore point,remove oem20.inf,scan') ($acts -join ',')
Check '... said, and held: listed in the blocklist and the NVIDIA version in gpu-hold.txt' ("$o" -match '^Graphics driver: back on 32\.0\.15\.5612' -and (Get-Content $bl) -match '^NVIDIA\|2026-09-01\|32\.0\.15\.6094\|nv_dispi\.inf$' -and (Get-Content $hold) -eq '560.94') "$o"
$o = GR (New-T @{ Packages = @(@{ Pub = 'oem20.inf'; Name = 'nv_dispi.inf'; Ver = '32.0.15.6094'; Date = '2026-09-01' }) })
Check 'no older version on the PC: nothing done, the maker''s driver page named' (-not $acts -and "$o" -match "isn't on this PC any more" -and "$o" -match 'nvidia\.com') "$o"
$o = GR (New-T @{ Game = 'Test Game' })
Check 'a game running: nothing done, asked to close it first' (-not $acts -and "$o" -match '^Close Test Game first') "$o"
$o = GR (New-T @{ DeleteOk = $false })
Check 'Windows refused: a WARNING, nothing held' ("$o" -match '^WARNING' -and -not (Test-Path $bl) -and -not (Test-Path $hold)) "$o"
$o = GR (New-T @{ Current = $null })
Check 'only the built-in Microsoft driver: said, nothing done' (-not $acts -and "$o" -match 'No graphics driver of its own') "$o"
Section 'driver-check.ps1 keeps to the hold'
Check 'NVIDIA: a version up to the one gone back from is not installed; a newer one is' ((Get-Content "$Src\driver-check.ps1" -Raw) -match 'gpu-hold\.txt' -and (Get-Content "$Src\driver-check.ps1" -Raw) -match '-le \[version\]\$held') ''
Finish
