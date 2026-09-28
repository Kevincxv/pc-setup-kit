# driver-guard.ps1: a blue screen soon after a driver update puts the previous version back - with the driver list,
# the event log and pnputil mocked (nothing on this PC is touched).
. "$PSScriptRoot\..\lib.ps1"
$guardScript = "$Src\driver-guard.ps1"
if (-not (Test-Path $guardScript)) { Skip 'driver guard' 'not installed here'; Finish }
$mocked = 'Get-WindowsDriver', 'Get-WinEvent', 'pnputil'
if (-not (Test-Tripwire $guardScript $mocked)) { Finish }
Import-MockTargets ($mocked + 'Get-Item')
$crash = (Get-Date).Date.AddHours(12)
function Pkg($pub, $name, $ver, $class, [double]$stagedDaysBeforeCrash) {
    [pscustomobject]@{ Driver = $pub; OriginalFileName = "X:\Store\$name`_$pub\$name"; ClassName = $class; ProviderName = 'Realtek'; Date = [datetime]'2026-09-01'; Version = $ver
        Staged = $crash.AddDays(-$stagedDaysBeforeCrash) }
}
function Get-WindowsDriver { param([switch]$Online) $global:DG.Drivers }
function Get-Item { param([Parameter(Position = 0)]$Path, $LiteralPath) $p = "$Path$LiteralPath"
    $m = $global:DG.Drivers | Where-Object { (Split-Path $_.OriginalFileName) -eq $p } | Select-Object -First 1
    if ($m) { [pscustomobject]@{ CreationTime = $m.Staged } } else { Microsoft.PowerShell.Management\Get-Item @PSBoundParameters } }
function Get-WinEvent { param($FilterHashtable, $ErrorAction) @($global:DG.Earlier | Where-Object { $_ -ge $FilterHashtable.StartTime -and $_ -lt $FilterHashtable.EndTime } | ForEach-Object { [pscustomobject]@{ TimeCreated = $_ } }) }
function pnputil { $global:DG.Calls += "$args"; $global:DG.PnpOut }
if (-not (Assert-Mocks ($mocked + 'Get-Item'))) { Finish }
$bl = "$Work\driver-blocklist.txt"
function Reset-G { $global:DG = @{ Drivers = @(); Earlier = @(); Calls = @(); PnpOut = 'Driver package deleted successfully.' }; [IO.File]::Delete($bl) }
function G([switch]$WhatIf) { @(& $guardScript -Crashes @($crash) -Blocklist $bl -WhatIf:$WhatIf) }

Section 'a network driver updated the day before a blue screen, nothing before it'
Reset-G; $DG.Drivers = @((Pkg 'oem50.inf' 'rt640x64.inf' '10.70.0.0' 'Net' 40), (Pkg 'oem61.inf' 'rt640x64.inf' '10.71.0.0' 'Net' 1), (Pkg 'oem62.inf' 'other.inf' '1.0' 'HIDClass' 20))
$o = G -WhatIf
Check '-WhatIf: says what it would do, changes nothing' (($o -match 'would roll back Realtek rt640x64 10\.71\.0\.0 -> 10\.70\.0\.0') -and -not $DG.Calls -and -not (Test-Path $bl)) ($o -join ' / ')
$o = G
Check 'the new package is removed from the device (it goes back to the older one right away)' ($DG.Calls -contains '/delete-driver oem61.inf /uninstall /force') ($DG.Calls -join ' / ')
Check '... only that one' ($DG.Calls.Count -eq 1) ($DG.Calls -join ' / ')
Check '... said plainly' ($o -match '^Driver rolled back: Realtek rt640x64 10\.71\.0\.0 \(a blue screen came 24 h after it arrived\) - back on 10\.70\.0\.0') ($o -join ' / ')
Check '... and blocked from coming back (provider|date|version|inf)' ((Get-Content $bl) -eq 'Realtek|2026-09-01|10.71.0.0|rt640x64.inf') "$(Get-Content $bl)"

Section 'not the driver''s fault, or nothing to go back to'
Reset-G; $DG.Drivers = @((Pkg 'oem50.inf' 'rt640x64.inf' '10.70.0.0' 'Net' 40), (Pkg 'oem61.inf' 'rt640x64.inf' '10.71.0.0' 'Net' 1)); $DG.Earlier = @($crash.AddDays(-6))
$o = G; Check 'blue screens already happened before it arrived: left alone' (-not $DG.Calls -and -not $o) ($o -join ' / ')
Reset-G; $DG.Drivers = @((Pkg 'oem50.inf' 'rt640x64.inf' '10.70.0.0' 'Net' 40), (Pkg 'oem61.inf' 'rt640x64.inf' '10.71.0.0' 'Net' 5))
$o = G; Check 'it arrived more than 3 days before: left alone' (-not $DG.Calls -and -not $o) ($o -join ' / ')
Reset-G; $DG.Drivers = @((Pkg 'oem61.inf' 'rt640x64.inf' '10.71.0.0' 'Net' 1))
$o = G; Check 'no older version on the PC: left alone' (-not $DG.Calls -and -not $o) ($o -join ' / ')
Reset-G; $DG.Drivers = @((Pkg 'oem50.inf' 'rt640x64.inf' '10.70.0.0' 'Net' 40), (Pkg 'oem61.inf' 'rt640x64.inf' '10.71.0.0' 'Net' -1))
$o = G; Check 'it arrived after the blue screen: left alone' (-not $DG.Calls -and -not $o) ($o -join ' / ')

Section 'graphics, and when removing fails'
Reset-G; $DG.Drivers = @((Pkg 'oem7.inf' 'nv_dispi.inf' '32.0.15.8100' 'Display' 60), (Pkg 'oem9.inf' 'nv_dispi.inf' '32.0.15.8157' 'Display' 0.5))
$o = G; Check 'graphics driver: reported, never swapped by itself' (-not $DG.Calls -and ($o -match '^Driver guard: a blue screen came 12 h after the graphics driver .* - not swapped automatically')) ($o -join ' / ')
Reset-G; $DG.Drivers = @((Pkg 'oem50.inf' 'rt640x64.inf' '10.70.0.0' 'Net' 40), (Pkg 'oem61.inf' 'rt640x64.inf' '10.71.0.0' 'Net' 1)); $DG.PnpOut = 'Failed to delete driver package: Access is denied.'
$o = G; Check 'removal refused: a WARNING (it gets looked at), nothing blocked' (($o -match '^WARNING: couldn''t roll back the driver Realtek rt640x64 10\.71\.0\.0') -and -not (Test-Path $bl)) ($o -join ' / ')
Reset-G; $o = @(& $guardScript -Crashes @() -Blocklist $bl); Check 'no blue screens: does nothing' (-not $o -and -not $DG.Calls) ''
Finish
