# nvidia-settings.ps1: low latency + unlimited shader cache on the NVIDIA driver's global profile, once per driver,
# confirmed by reading the driver back. Made-up GPU/driver/read-back (-Test); the import goes to a recorder (-Do).
. "$PSScriptRoot\..\lib.ps1"
$ns = "$Src\nvidia-settings.ps1"
if (-not (Test-Path $ns)) { Skip 'nvidia-settings' 'not installed here'; Finish }
$st = "$Work\nvidia-settings.txt"
$global:acts = @()
$rec = { param($w) $global:acts += $w }
$good = @('8102046=1', '11306135=4294967295')
function Invoke-Nvidia([hashtable]$over = @{}) {
    $t = @{ Gpu = [pscustomobject]@{ Name = 'NVIDIA GeForce RTX TEST' }; Driver = '1.0'; Option = $null; Game = $null; Readback = $good }
    foreach ($k in $over.Keys) { $t[$k] = $over[$k] }
    $global:acts = @(); @(& $ns -Test $t -Do $rec -State $st)
}

$o = Invoke-Nvidia
Check 'applied and confirmed by the driver: said, recorded for this driver' ("$o" -match '^NVIDIA: low-latency mode on and an unlimited shader cache.+driver 1\.0' -and (Get-Content $st) -eq '1.0' -and $acts) ($o -join ' / ')
$o = Invoke-Nvidia
Check '... the same driver again: nothing' (-not $o -and -not $acts) ($o -join ' / ')
$o = Invoke-Nvidia @{ Driver = '2.0'; Game = 'TestGame' }
Check 'a new driver while a game runs: waits' (-not $o -and -not $acts) ($o -join ' / ')
$o = Invoke-Nvidia @{ Driver = '2.0' }
Check '... applied at the next check without a game' ("$o" -match 'driver 2\.0' -and (Get-Content $st) -eq '2.0') ($o -join ' / ')
$o = Invoke-Nvidia @{ Driver = '3.0'; Readback = @('8102046=1', '11306135=4096') }
Check "the driver didn't take it: FAILED (gets looked at), not recorded - tried again next time" ("$o" -match '^NVIDIA settings FAILED to apply' -and (Get-Content $st) -eq '2.0') ($o -join ' / ')
$o = Invoke-Nvidia @{ Driver = '3.0'; Option = 'off' }
Check "turned off in the app's Settings: nothing" (-not $o -and -not $acts) ($o -join ' / ')
$o = Invoke-Nvidia @{ Driver = '3.0'; Gpu = $null }
Check 'no NVIDIA graphics card: nothing' (-not $o -and -not $acts) ($o -join ' / ')
$bad = @('8102046=3', '11306135=4294967295')
'2.0' | Set-Content $st
$o = Invoke-Nvidia @{ Driver = '2.0'; Current = $good }
Check 'checked at every run: already as wanted - nothing done, nothing said' (-not $o -and -not $acts) ($o -join ' / ')
$o = Invoke-Nvidia @{ Driver = '2.0'; Current = $bad }
Check 'reset without a new driver (the NVIDIA app, a game''s optimizer): put back, said so' ("$o" -match 'had been reset .+ put back' -and $acts) ($o -join ' / ')
$o = Invoke-Nvidia @{ Driver = '2.0'; Current = $bad; Game = 'TestGame' }
Check '... but never while a game runs (next check)' (-not $o -and -not $acts) ($o -join ' / ')
[IO.File]::Delete($st); $o = Invoke-Nvidia @{ Driver = '4.0'; Current = $good }
Check 'a new driver that already has them (it kept the profile): only recorded, no import' (-not $o -and -not $acts -and (Get-Content $st) -eq '4.0') ($o -join ' / ')
Finish