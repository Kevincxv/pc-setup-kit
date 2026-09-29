# activation-check.ps1: activation only with the PC's own license (its firmware key, its digital license); otherwise a
# Reminder. Made-up license states (-Test); actions go to a recorder (-Do) - nothing on this PC's license changes.
. "$PSScriptRoot\..\lib.ps1"
$ac = "$Src\activation-check.ps1"
if (-not (Test-Path $ac)) { Skip 'activation-check' 'not installed here'; Finish }
$st = "$Work\activation-state.txt"
$global:acts = @()
$rec = { param($w) $global:acts += $w }
function Invoke-Activation([hashtable]$over = @{}) {
    $t = @{ Status = 0; Edition = 'Core'; FwKey = $null; FwDesc = $null; AfterIpk = 1; AfterAto = 0 }
    foreach ($k in $over.Keys) { $t[$k] = $over[$k] }
    $global:acts = @(); Clear-Path $st; @(& $ac -Test $t -Do $rec -State $st)
}

$o = Invoke-Activation @{ Status = 1 }
Check 'activated: nothing done, nothing said' (-not $o -and -not $acts) ($o -join ' / ')
$o = Invoke-Activation @{ FwKey = 'XXXXX-XXXXX-XXXXX-XXXXX-TEST1'; FwDesc = '[4.0] Core OEM:DM' }
Check "the PC's own firmware key, same edition: put in and activated, said - the key never printed" (($acts -join ',') -eq 'install firmware key,activate' -and "$o" -match '^Windows activated with the license built into this PC \(Home\)$' -and "$o" -notmatch 'TEST1') ($o -join ' / ')
$o = Invoke-Activation @{ AfterAto = 1 }
Check 'no firmware key: online activation (a digital license) - activated, said' (($acts -join ',') -eq 'activate' -and "$o" -match "digital license") ($o -join ' / ')
$o = Invoke-Activation @{}
Check 'no license at all: a Reminder with what to do (Settings > Activation)' ("$o" -match "^Reminder: Windows isn't activated - open Settings > System > Activation") ($o -join ' / ')
$o = Invoke-Activation @{ Edition = 'Professional'; FwKey = 'XXXXX-XXXXX-XXXXX-XXXXX-TEST2'; FwDesc = '[4.0] Core OEM:DM' }
Check "a Home firmware license with Pro installed: the key isn't put on Pro; the Reminder says Home vs Pro" (-not ($acts -contains 'install firmware key') -and "$o" -match 'built-in license is for Windows Home, but Windows Pro is installed') ($o -join ' / ')
$global:acts = @(); $o = @(& $ac -Test @{ Status = 0; Edition = 'Core'; AfterAto = 0 } -Do $rec -State $st)
Check '... tried at most once a day (the Reminder still says it)' (-not $acts -and "$o" -match '^Reminder') ($o -join ' / ')
Check 'never an activator or someone else''s key: only this PC''s firmware key or its digital license' ((Get-Content $ac -Raw) -notmatch 'kms|/skms|slmgr\s*/ipk\s+[A-Z0-9]{5}-|HWID|TSforge|massgrave' ) ''
Finish
