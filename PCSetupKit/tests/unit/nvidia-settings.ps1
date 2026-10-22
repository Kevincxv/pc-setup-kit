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
Section 'every game gets the Call of Duty setup: its own profile (10/22)'
# a stand-in for the driver's profiles: exe -> @{ id = value }; Ensure answers like KitNvApp.Ensure
$global:prof = @{}
$ens = {
    param($exe, $name, $ids, $vals, $write)
    $p = $global:prof[$exe]; $same = $p -and -not (@(0..($ids.Count - 1)) | Where-Object { $p["$($ids[$_])"] -ne $vals[$_] })
    if ($same) { return 'same' }; if (-not $write) { return 'pending' }
    if (-not $p) { $p = @{ name = $name }; $global:prof[$exe] = $p }
    for ($i = 0; $i -lt $ids.Count; $i++) { $p["$($ids[$i])"] = $vals[$i] }; 'set'
}
$vsOn = "$(0x47814940)"; $fr = "$(0x10835002)"; $vs = "$(0x00A879CF)"; $pw = "$(0x1057EB71)"
$o = Invoke-Nvidia @{ Current = $good; Games = @('cod', 'NBA2K17'); Gsync = 1; Refresh = 240; Ensure = $ens; Running = @() }
$n = $global:prof['NBA2K17.exe']; $c = $global:prof['cod.exe']
Check 'G-SYNC on: a learned game gets maximum performance, V-Sync on and a cap 3 under the refresh rate, said' ($n[$pw] -eq 1 -and $n[$vs] -eq $vsOn -and $n[$fr] -eq 237 -and "$o" -match 'NVIDIA: NBA2K17 set up like Call of Duty - maximum performance, V-Sync on and a 237 fps cap just under the 240 Hz refresh') ($o -join ' / ')
Check '... Call of Duty the same, without a cap (Reflex caps it), and its own profile name' ($c[$vs] -eq $vsOn -and -not $c.ContainsKey($fr) -and $c.name -eq 'Call of Duty (Messiah)' -and $n.name -eq 'NBA2K17 (Messiah)') ''
$o = Invoke-Nvidia @{ Current = $good; Games = @('cod', 'NBA2K17'); Gsync = 1; Refresh = 240; Ensure = $ens; Running = @() }
Check '... already so: nothing said' (-not $o) ($o -join ' / ')
$global:prof['NBA2K17.exe'][$pw] = 0
$o = Invoke-Nvidia @{ Current = $good; Games = @('NBA2K17'); Gsync = 1; Refresh = 240; Ensure = $ens; Running = @('NBA2K17') }
Check 'changed back while the game runs: not written under it' ($global:prof['NBA2K17.exe'][$pw] -eq 0 -and -not $o) ($o -join ' / ')
$o = Invoke-Nvidia @{ Current = $good; Games = @('NBA2K17'); Gsync = 1; Refresh = 240; Ensure = $ens; Running = @() }
Check '... put back once it is closed' ($global:prof['NBA2K17.exe'][$pw] -eq 1 -and "$o" -match 'NBA2K17 set up like Call of Duty') ($o -join ' / ')
$global:prof = @{}
$o = Invoke-Nvidia @{ Current = $good; Games = @('NBA2K20'); Gsync = 0; Refresh = 240; Ensure = $ens; Running = @() }
$n = $global:prof['NBA2K20.exe']
Check 'G-SYNC off: maximum performance, V-Sync left to the game, no cap' ($n[$pw] -eq 1 -and $n[$vs] -eq "$(0x60925292)" -and -not $n.ContainsKey($fr) -and "$o" -match 'NBA2K20 set to maximum performance .+V-Sync left to the game') ($o -join ' / ')
$o = Invoke-Nvidia @{ Current = $good; Games = @('NBA2K20'); Gsync = 1; Refresh = 240; Ensure = { 'error:set:-5' }; Running = @() }
Check 'the driver refusing: said with its error' ("$o" -match "NBA2K20's profile could not be set \(error:set:-5\)") ($o -join ' / ')
Finish