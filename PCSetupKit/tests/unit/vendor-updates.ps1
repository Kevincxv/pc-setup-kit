# vendor-updates.ps1: the PC maker's own tool (Dell / HP / Lenovo Think*) for BIOS, firmware and drivers, weekly.
# Made-up PCs (-Test); actions go to a recorder - nothing is installed or run.
. "$PSScriptRoot\..\lib.ps1"
$vu = "$Src\vendor-updates.ps1"
if (-not (Test-Path $vu)) { Skip 'vendor-updates' 'not installed here'; Finish }
$st = "$Work\vendor-state.json"
$global:acts = @()
$rec = { param($w) $global:acts += $w }
function VU([hashtable]$over = @{}, [datetime]$now = (Get-Date), [switch]$Keep) {
    $t = @{ Maker = 'Dell Inc.'; Model = 'Latitude 7450'; Exe = $true; ExeAfterInstall = $true; Exit = 500; Game = $null; OnBattery = $false }
    foreach ($k in $over.Keys) { $t[$k] = $over[$k] }
    if (-not $Keep) { [IO.File]::Delete($st) }
    $global:acts = @(); @(& $vu -Test $t -Do $rec -State $st -Now $now)
}

$o = VU @{ Maker = 'ASRock'; Model = 'B650 TEST' }
Check 'a custom-built PC: nothing at all' (-not $o -and -not $acts) ($o -join ' / ')
$o = VU @{ Exit = 500 }
Check 'a Dell: Dell Command | Update runs (restore point first); nothing new: said' (($acts -join ',') -eq 'restore point,run Dell Command | Update' -and "$o" -match 'up to date') ($o -join ' / ')
$o = VU @{ Exit = 1 }
Check '... updates installed that need a restart: REBOOT said (finishes at the next restart, never restarted)' ("$o" -match 'REBOOT required') ($o -join ' / ')
$o = VU @{} (Get-Date) -Keep
Check '... once a week: the next run within 6 days does nothing' (-not $acts -and -not $o) ($o -join ' / ')
$o = VU @{ Exe = $false; ExeAfterInstall = $true; Exit = 500 }
Check 'the tool missing: installed from winget first (the maker''s own, free), then run' ($acts[0] -eq 'install Dell.CommandUpdate.Universal' -and ($acts -contains 'run Dell Command | Update') -and "$o" -match 'installed Dell Command \| Update') (($acts + $o) -join ' / ')
$o = VU @{ Exe = $false; ExeAfterInstall = $false }
Check '... it didn''t install: said, tried again in a month (not every day)' ("$o" -match "couldn't install" -and -not ($acts -match '^run')) ($o -join ' / ')
$o = VU @{ Exe = $false; ExeAfterInstall = $false } (Get-Date).AddDays(8) -Keep
Check '... a week later: not tried again yet' (-not $acts) ($acts -join ',')
$o = VU @{ Maker = 'HP'; Model = 'EliteBook 840 G10'; Exit = 3010 }
Check 'an HP: HP Image Assistant; a BIOS staged: REBOOT' (($acts -contains 'run HP Image Assistant') -and "$o" -match 'REBOOT') ($o -join ' / ')
$o = VU @{ Maker = 'HP'; Model = 'Pavilion 15'; Exit = 4096 }
Check '... a model it doesn''t cover: remembered, the BIOS reminder stays' ("$o" -match "doesn't cover" -and ((Get-Content $st -Raw | ConvertFrom-Json).supported -eq $false)) ($o -join ' / ')
$o = VU @{ Maker = 'HP'; Model = 'Pavilion 15' } (Get-Date).AddDays(10) -Keep
Check '... and never tried again on it' (-not $acts -and -not $o) ($o -join ' / ')
$o = VU @{ Maker = 'LENOVO'; Model = 'ThinkPad T14 Gen 5' ; Exit = 0 }
Check 'a ThinkPad: Lenovo System Update' ($acts -contains 'run Lenovo System Update') ($acts -join ',')
$o = VU @{ Maker = 'LENOVO'; Model = 'Legion 5 16IRX9' }
Check 'a Lenovo Legion (not covered by System Update): nothing' (-not $acts -and -not $o) ($o -join ' / ')
$o = VU @{ Game = 'Test Game' }
Check 'a game running: held' (-not $acts -and "$o" -match 'held while Test Game') ($o -join ' / ')
$o = VU @{ OnBattery = $true }
Check 'a laptop on battery: waits for power (a BIOS update must not lose power)' (-not $acts -and "$o" -match 'plugged in') ($o -join ' / ')
$o = VU @{ Exit = 2 }
Check 'the tool failed: FAILED (looked at), tried again next week' ("$o" -match 'FAILED \(exit code 2\)') ($o -join ' / ')
Section 'health-check.ps1: no BIOS reminder where the maker''s tool keeps it current'
Check 'the reminder is skipped when vendor-state.json says supported' ((Get-Content "$Src\health-check.ps1" -Raw) -match 'vendor-state\.json' -and (Get-Content "$Src\health-check.ps1" -Raw) -match '-not \$makerTool -and \$bios\.ReleaseDate') ''
Finish
