# diag-modes.ps1 (crash-hunting modes left on: Driver Verifier, kernel debugging, test signing) and update-cause.ps1 (what
# changed settings back since the guard's last pass) - both read-only but for diag-modes' own state file, given here.
. "$PSScriptRoot\..\lib.ps1"
$st = "$Work\diag-state.json"; Clear-Path $st
function DM($vd, $opts, $today) { @(& "$Src\diag-modes.ps1" -State $st -Test @{ VerifyDrivers = $vd; StartOptions = $opts; Today = $today }) }

Section 'crash-hunting modes (diag-modes.ps1)'
$o = @(DM '' ' NOEXECUTE=OPTIN  NOVGA' '2026-10-01')
Check 'nothing on: nothing said, nothing kept' ($o.Count -eq 0 -and (-not (Test-Path $st) -or (Get-Content $st -Raw) -notmatch 'verifier')) ($o | Out-String)
$o = @(DM 'nvlddmkm.sys amdpsp.sys' ' NOEXECUTE=OPTIN' '2026-10-04')
Check 'Driver Verifier on: named with how many drivers it watches, from today' ($o.Count -eq 1 -and $o[0].Id -eq 'verifier' -and $o[0].Name -eq 'Driver Verifier (2 drivers)' -and $o[0].Days -eq 0) ($o | Out-String)
$o = @(DM 'nvlddmkm.sys amdpsp.sys' ' NOEXECUTE=OPTIN' '2026-10-20')
Check '... the day it was first seen is kept: 16 days later' ($o[0].Days -eq 16 -and $o[0].Since -eq [datetime]'2026-10-04') ($o | Out-String)
$o = @(DM '' ' NOEXECUTE=OPTIN  DEBUG  TESTSIGNING' '2026-10-21')
Check 'kernel debugging and test signing seen in the start options' (($o.Id -join ',') -eq 'debug,testsigning') ($o | Out-String)
$j = Get-Content $st -Raw | ConvertFrom-Json
Check '... Driver Verifier gone: kept as switched off, with when (it runs until the next restart)' (-not $j.verifier -and "$($j.'verifier-off')" -match '^2026-10-21T') (Get-Content $st -Raw)
$o = @(DM '*' '' '2026-10-22')
Check 'every driver watched ("*"); turned on again: its "switched off" is forgotten, counted from today' ($o[0].Name -eq 'Driver Verifier (every driver)' -and $o[0].Days -eq 0 -and -not (Get-Content $st -Raw | ConvertFrom-Json).'verifier-off') (Get-Content $st -Raw)
'{"verifier-off":"2026-08-01T10:00:00","debug":"not a date"}' | Set-Content $st
$o = @(DM '' '' '2026-10-22')
Check 'a damaged or month-old state: tidied, no error' ($o.Count -eq 0 -and (Get-Content $st -Raw) -notmatch 'verifier-off|not a date') (Get-Content $st -Raw)
'{{{' | Set-Content $st; $o = @(DM 'a.sys' '' '2026-10-22')
Check '... broken JSON: starts afresh' ($o.Count -eq 1 -and $o[0].Days -eq 0) ($o | Out-String)

Section 'what changed things back (update-cause.ps1)'
function Ev($id, $t, [string[]]$props) { [pscustomobject]@{ Id = $id; TimeCreated = [datetime]$t; Properties = @($props | ForEach-Object { [pscustomobject]@{ Value = $_ } }) } }
$since = [datetime]'2026-10-11 09:00'
$ev = @((Ev 19 '2026-10-11 09:30' '2026-10 Cumulative Update for Windows 11 Version 25H2 (KB5099999)'),
    (Ev 19 '2026-10-11 09:31' 'Security Intelligence Update for Microsoft Defender Antivirus - KB2267602 (Version 1.459.672.0)'),
    (Ev 19 '2026-10-11 09:32' '9WZDNCRFJBH4-Microsoft.Windows.Photos'),
    (Ev 20003 '2026-10-11 09:40' 'nvlddmkm', '\SystemRoot\System32\DriverStore\FileRepository\nvmdi.inf_amd64_8de67f3813b9d47d\nvlddmkm.sys', 'PCI\VEN_10DE', 'True'),
    (Ev 19 '2026-10-10 20:00' 'An older update (before the last pass)'))
$c = "$(& "$Src\update-cause.ps1" -Since $since -Events $ev)"
Check 'a Windows update and a driver install since the last pass: both named' ($c -eq 'Windows Update (2026-10 Cumulative Update for Windows 11 Version 25H2 (KB5099999)) and driver install (nvmdi.inf)') $c
Check '... Defender definitions and Store app updates left out (they change no settings), and nothing from before' ($c -notmatch 'Security Intelligence|Photos|older') $c
$c = "$(& "$Src\update-cause.ps1" -Since $since -Events @((Ev 19 '2026-10-11 09:31' 'Security Intelligence Update for Microsoft Defender Antivirus - KB2267602')))"
Check 'only Defender definitions: nothing (another program or the owner changed it)' ($c -eq '') $c
Clear-Path $st
Finish
