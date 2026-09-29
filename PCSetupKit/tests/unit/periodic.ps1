# periodic-maint.ps1 with every system change mocked: weekly app updates (winget table parsing), monthly cleanup
# (restore point, DISM, Disk Cleanup categories, old drivers, orphaned firewall rules/services/tasks), TRIM check.
. "$PSScriptRoot\..\lib.ps1"
$d = "$Work\pm"; New-Item $d -ItemType Directory -Force | Out-Null
Copy-Item "$Src\periodic-maint.ps1" $d; '' | Set-Content "$d\game-check.ps1"
$mocked = 'winget', 'DISM', 'Start-Process', 'Stop-Process', 'Checkpoint-Computer', 'Get-ComputerRestorePoint', 'pnputil', 'Get-NetFirewallApplicationFilter',
    'Get-NetFirewallRule', 'Remove-NetFirewallRule', 'Optimize-Volume', 'Set-ItemProperty', 'Remove-ItemProperty', 'Get-PSDrive', 'Get-ScheduledTask',
    'Get-ScheduledTaskInfo', 'Get-CimInstance', 'Get-WindowsDriver', 'Get-Process', 'Get-ItemProperty'
if (-not (Test-Tripwire "$d\periodic-maint.ps1" $mocked -Guarded 'Get-ChildItem')) { Finish }   # (Get-ChildItem only reads the Disk Cleanup category list)

Import-MockTargets $mocked   # load their Windows modules BEFORE defining the mocks (see lib.ps1)
$now = Get-Date
function RestorePt($daysAgo) { $o = [pscustomobject]@{ CreationTime = $now.AddDays(-$daysAgo) }; $o | Add-Member ScriptMethod ConvertToDateTime { param($t) $t }; $o }
function Reset-M {
    $global:PM = @{
        Winget = @('No installed package found matching input criteria.'); WingetOk = @('Vendor.Good'); WinDrivers = @()
        Rps = @(RestorePt 10); RpWorks = $true; Reboot = $false; Free = 100GB; FreeAfter = 102GB; CleanmgrHangs = $false
        Drivers = ''; FwFilters = @(); Services = @(); Tasks = @(); DefragLast = $now.AddDays(-2); SteamPath = $null; SteamRunning = $false
    }
    $global:PMcalls = New-Object System.Collections.Generic.List[string]
}
function winget { if ("$args" -match '^source (reset|update)') { $global:PMcalls.Add("winget source $($Matches[1])"); if ($Matches[1] -eq 'update' -and $PM.FixedByRefresh) { $PM.Winget = @('No installed package found matching input criteria.') }; return }; if ("$args" -match '--id (\S+)') { $global:PMcalls.Add("winget upgrade $($Matches[1])"); if ($PM.WingetOk -contains $Matches[1]) { 'Successfully installed' } else { 'Installer failed with exit code: 1603' } } else { $PM.Winget } }
function Get-WindowsDriver { param([switch]$Online) $PM.WinDrivers }
function DISM { $global:PMcalls.Add("DISM $args") }
function Start-Process { $global:PMcalls.Add("Start-Process $args"); $p = [pscustomobject]@{ Id = 4242 }; $h = $PM.CleanmgrHangs; $p | Add-Member ScriptMethod WaitForExit ([scriptblock]::Create("param(`$ms) -not `$$h")); $p }
function Stop-Process { $global:PMcalls.Add("Stop-Process $args") }
function Get-ComputerRestorePoint { $PM.Rps }
function Checkpoint-Computer { $global:PMcalls.Add('Checkpoint-Computer'); if ($PM.RpWorks) { $PM.Rps = @($PM.Rps) + (RestorePt 0) } }
function pnputil { if ("$args" -match 'enum-drivers') { $PM.Drivers } elseif ("$args" -match 'delete-driver (\S+)') { $global:PMcalls.Add("pnputil delete $($Matches[1])"); if ($Matches[1] -eq 'oem10.inf') { 'One or more devices are presently installed using the specified INF.' } else { 'Driver package deleted successfully.' } } }
function Get-NetFirewallApplicationFilter { $PM.FwFilters }
function Get-NetFirewallRule { $input | ForEach-Object { [pscustomobject]@{ Name = "rule-$($_.Program)" } } }
function Remove-NetFirewallRule { $input | ForEach-Object { $global:PMcalls.Add("remove firewall $($_.Name)") } }
function Optimize-Volume { $global:PMcalls.Add("Optimize-Volume $args") }
function Set-ItemProperty { $global:PMcalls.Add("Set-ItemProperty $($args[0] -replace '^.*\\', '') $($args[1]) $($args[2])") }
function Remove-ItemProperty { $global:PMcalls.Add("Remove-ItemProperty $($args[0] -replace '^.*\\', '')") }
$global:psdriveCalls = 0
function Get-PSDrive { $global:psdriveCalls++; [pscustomobject]@{ Free = $(if ($global:psdriveCalls % 2) { $PM.Free } else { $PM.FreeAfter }); Used = 500GB } }
function Get-ScheduledTask { param($TaskPath, $TaskName) if ($TaskName -eq 'ScheduledDefrag') { [pscustomobject]@{ TaskName = 'ScheduledDefrag' } } else { $PM.Tasks } }
function Get-ScheduledTaskInfo { [pscustomobject]@{ LastRunTime = $PM.DefragLast } }
function Get-CimInstance { if ("$args" -match 'Win32_Service') { return $PM.Services }; CimCmdlets\Get-CimInstance @args }
function Get-Process { param($Name) if ($Name -eq 'steam' -and $PM.SteamRunning) { [pscustomobject]@{ Name = 'steam' } } }
function Get-ItemProperty { if ("$args" -match 'Valve\\Steam') { return [pscustomobject]@{ SteamPath = $PM.SteamPath } }; Microsoft.PowerShell.Management\Get-ItemProperty @args }
function Test-Path { $a = @($args | ForEach-Object { $_ }) -join ' '; if ($a -match 'RebootPending|RebootRequired') { return $PM.Reboot }; Microsoft.PowerShell.Management\Test-Path @args }
function State([hashtable]$s) { $base = @{ 'weekly-apps' = $now.ToString('o'); 'monthly-cleanup' = $now.ToString('o'); 'trim' = $now.ToString('o') }; foreach ($k in $s.Keys) { $base[$k] = $s[$k] }; $base | ConvertTo-Json | Set-Content "$d\maint-state.json" }
function PM { $global:psdriveCalls = 0; @(& "$d\periodic-maint.ps1" -TestDisplayVersion 25H2 -TestEdition Professional -TestToday $now.ToString('s')) }
function St { Get-Content "$d\maint-state.json" -Raw | ConvertFrom-Json }
$old = $now.AddDays(-40).ToString('o')

if (-not (Assert-Mocks ($mocked + 'Test-Path'))) { Finish }

Section 'weekly app updates'
Reset-M; State @{ 'weekly-apps' = $old }
$PM.Winget = @('   - \ ', 'Name                                  Id                        Version   Available  Source',
    '-------------------------------------------------------------------------------------------------------------',
    'Steam                                 Valve.Steam               2.10.91   2.10.92    winget',
    'Good App With A Long Name             Vendor.Good               1.0.0     1.1.0      winget',
    'Bad App                               Vendor.Bad                3.0       3.1        winget',
    'NVIDIA App                            Nvidia.App                11.0      11.1       winget',
    # a name winget shortened with an ellipsis, read in the wrong encoding: 3 characters instead of 1, so everything after it
    # sits 2 columns further right (seen on a real run: "App update FAILED: ¦ ImageMagick.ImageMagick")
    ('ImageMagick 7.1.2-25 Q16-HDRI (64-bit) â€¦' + ' ImageMagick.ImageMagick   7.1.2.25  7.1.2.26   winget'),
    'Old Tool                              Vendor.OldTool            < 1.0     2.0        winget',
    'Microsoft Edge                        Microsoft.Edge            140.0     141.0      winget',
    '7 upgrades available.', '', '1 package(s) have version numbers that cannot be determined.')
$o = PM
Check 'an app updates: "Updated app"' ([bool]($o -contains 'Updated app: Vendor.Good')) ($o -join ' / ')
Check 'a failing update: "App update FAILED" (so Claude looks at it)' ([bool]($o -contains 'App update FAILED: Vendor.Bad')) ''
Check 'self-updating apps (Steam, NVIDIA) are never touched' (-not ($PMcalls -match 'Valve.Steam|Nvidia')) ($PMcalls -join ', ')
Check 'the spinner line and footer are not parsed as apps' (@($PMcalls -match 'winget upgrade').Count -eq 4) ($PMcalls -join ', ')
Check 'a shortened, wrongly encoded name does not shift the columns (the right id is updated)' (($PMcalls -contains 'winget upgrade ImageMagick.ImageMagick') -and -not ($o -match '¦')) (($PMcalls + $o) -join ', ')
Check 'a version shown as "< 1.0" is read too' ($PMcalls -contains 'winget upgrade Vendor.OldTool') ($PMcalls -join ', ')
Check 'Edge (updates itself) is never touched' (-not ($PMcalls -match 'Microsoft.Edge')) ($PMcalls -join ', ')
Check 'marked done for this week' ((St).'weekly-apps' -ne $old) ''
Reset-M; State @{ 'weekly-apps' = $old }; $o = PM
Check 'nothing to update: no lines, still marked done' (-not ($o -match 'Updated app|FAILED') -and (St).'weekly-apps' -ne $old) ($o -join ' / ')
Reset-M; State @{ 'weekly-apps' = $now.AddDays(-8).ToString('o') }; $PM.Winget = @('No packages were found among the working sources.'); $PM.FixedByRefresh = $true; $o = PM
Check 'winget''s package list broken: fetched again, then the updates run (and marked done)' (($PMcalls -contains 'winget source reset') -and ($PMcalls -contains 'winget source update') -and ($o -match 'package list was broken - fetched it again') -and (St).'weekly-apps' -ne $now.AddDays(-8).ToString('o')) ($o -join ' / ')
$was = $now.AddDays(-8).ToString('o'); Reset-M; State @{ 'weekly-apps' = $was }; $PM.Winget = @('Failed when searching source: winget'); $o = PM
Check '... still broken: "held" (no alarm for one miss), NOT marked done - the next run tries again' (($o -match '^App updates held: winget couldn''t load') -and -not ($o -match 'FAIL') -and ([datetime]((St).'weekly-apps')) -lt $now.AddDays(-7)) "state: $((St).'weekly-apps') | $($o -join ' / ')"
Reset-M; State @{ 'weekly-apps' = $old }; $PM.Winget = @(); $o = PM
Check '... no app updates for 3+ weeks: FAILED (gets looked at)' ($o -match '^App updates FAILED: winget couldn''t load') ($o -join ' / ')

Section 'monthly cleanup'
Reset-M; State @{ 'monthly-cleanup' = $old }
$PM.Drivers = @"
Published Name:     oem7.inf
Original Name:      nvlddmkm.inf
Provider Name:      NVIDIA
Class Name:         Display
Driver Version:     07/01/2026 32.0.15.9000
Signer Name:        Microsoft Windows Hardware Compatibility Publisher

Published Name:     oem8.inf
Original Name:      nvlddmkm.inf
Provider Name:      NVIDIA
Class Name:         Display
Driver Version:     09/01/2026 32.0.16.1714
Signer Name:        Microsoft Windows Hardware Compatibility Publisher

Published Name:     oem9.inf
Original Name:      rt640x64.inf
Provider Name:      Realtek
Class Name:         Net
Driver Version:     01/01/2025 10.60.1.0
Signer Name:        Microsoft Windows Hardware Compatibility Publisher

Published Name:     oem10.inf
Original Name:      rt640x64.inf
Provider Name:      Realtek
Class Name:         Net
Driver Version:     01/01/2024 10.50.0.0
Signer Name:        Microsoft Windows Hardware Compatibility Publisher
"@
$PM.FwFilters = @([pscustomobject]@{ Program = 'C:\Games\Removed\game.exe' }, [pscustomobject]@{ Program = "$env:WINDIR\System32\svchost.exe" },
    [pscustomobject]@{ Program = '%SystemRoot%\system32\foo.exe' }, [pscustomobject]@{ Program = 'System' }, [pscustomobject]@{ Program = 'Any' })
$PM.Services = @([pscustomobject]@{ Name = 'GoneSvc'; PathName = '"C:\Program Files\Gone\gone.exe" -service' }, [pscustomobject]@{ Name = 'OkSvc'; PathName = "$env:WINDIR\System32\svchost.exe -k netsvcs" },
    [pscustomobject]@{ Name = 'DrvSvc'; PathName = '\SystemRoot\System32\drivers\gone-driver.sys' })
$act = { param($e) [pscustomobject]@{ Execute = $e } }
$PM.Tasks = @([pscustomobject]@{ TaskName = 'GoneUpdater'; TaskPath = '\'; State = 'Ready'; Actions = @(& $act 'C:\Program Files\Gone\updater.exe') },
    [pscustomobject]@{ TaskName = 'MsTask'; TaskPath = '\Microsoft\Windows\X\'; State = 'Ready'; Actions = @(& $act 'C:\nope\ms.exe') },
    [pscustomobject]@{ TaskName = 'OffTask'; TaskPath = '\'; State = 'Disabled'; Actions = @(& $act 'C:\nope\off.exe') },
    [pscustomobject]@{ TaskName = 'OkTask'; TaskPath = '\'; State = 'Ready'; Actions = @(& $act "$env:WINDIR\System32\cmd.exe") })
$o = PM
Check 'a restore point is created (none in the last 24 h)' (($PMcalls -contains 'Checkpoint-Computer') -and ($o -contains 'Created a monthly restore point')) ($o -join ' / ')
Check 'component cleanup (DISM) runs when no restart is pending' ([bool]($PMcalls -match 'DISM .*StartComponentCleanup')) ''
$sets = @($PMcalls -match '^Set-ItemProperty' | ForEach-Object { ($_ -replace '^Set-ItemProperty ', '') -replace ' StateFlags0078 2$', '' })
$never = 'Recycle Bin', 'DownloadsFolder', 'D3D Shader Cache', 'Previous Installations', 'Windows Error Reporting Files', 'Update Cleanup', 'Device Driver Packages', 'Language Pack', 'System error memory dump files', 'System error minidump files'
Check "Disk Cleanup: only safe categories selected ($($sets.Count) on this PC)" ($sets.Count -ge 3 -and -not ($sets | Where-Object { $_ -in $never })) ($sets -join ', ')
Check '... never Recycle Bin, Downloads, shader cache, crash dumps, previous Windows' (-not ($sets | Where-Object { $_ -in $never })) ''
Check '... Disk Cleanup started with the kit''s own preset' ([bool]($PMcalls -match 'cleanmgr.exe.*sagerun:78')) ''
Check 'old driver version removed, the newest kept' (($PMcalls -contains 'pnputil delete oem7.inf') -and -not ($PMcalls -contains 'pnputil delete oem8.inf') -and ($o -match 'Removed old driver nvlddmkm.inf 32.0.15.9000')) ($PMcalls -join ', ')
Check 'a driver still in use is not reported as removed' (-not ($o -match 'rt640x64')) ($o -join ' / ')
# the NVIDIA driver was updated 5 days ago (its driver store folder is new): the previous version stays, so
# driver-guard.ps1 can go back to it after a blue screen
$store = "$Work\store\nvlddmkm.inf_amd64_new"; New-Item $store -ItemType Directory -Force | Out-Null; (Get-Item $store).CreationTime = (Get-Date).AddDays(-5)
$PM.WinDrivers = @([pscustomobject]@{ Driver = 'oem8.inf'; OriginalFileName = "$store\nvlddmkm.inf" }); $PM.Reboot = $false
$global:PMcalls.Clear(); State @{ 'monthly-cleanup' = $old }; $o = PM
Check 'a driver updated in the last 30 days keeps its previous version (rollback after a blue screen)' (-not ($PMcalls -contains 'pnputil delete oem7.inf') -and -not ($o -match 'Removed old driver nvlddmkm')) ($PMcalls -join ', ')
(Get-Item $store).CreationTime = (Get-Date).AddDays(-31); $global:PMcalls.Clear(); State @{ 'monthly-cleanup' = $old }; $o = PM
Check '... after 30 days it is cleaned up as usual' ($PMcalls -contains 'pnputil delete oem7.inf') ($PMcalls -join ', ')
$PM.WinDrivers = @()
Check 'only the firewall rule of the deleted program is removed' ((@($PMcalls -match '^remove firewall').Count -eq 1) -and ($PMcalls -match 'remove firewall rule-C:\\Games\\Removed') -and ($o -match 'Removed 1 firewall rules')) ($PMcalls -join ', ')
$w = @($o -match 'WARNING: leftovers')
Check 'orphaned service and task reported for Claude' (($w -match 'service GoneSvc') -and ($w -match 'task \\GoneUpdater') -and ($w -match 'service DrvSvc')) ($w -join ' / ')
Check '... but not Microsoft, disabled or healthy ones' (-not ($w -match 'MsTask|OffTask|OkTask|OkSvc')) ($w -join ' / ')
Check 'space freed is reported' ([bool]($o -match 'Monthly cleanup done, freed 2.0 GB')) ($o -join ' / ')
Check 'marked done for this month' ((St).'monthly-cleanup' -ne $old) ''
Reset-M; State @{ 'monthly-cleanup' = $old }; $PM.Rps = @(RestorePt 0.5); $PM.Reboot = $true; $PM.CleanmgrHangs = $true; $o = PM
Check 'a restore point from today already exists: no second one' (-not ($PMcalls -contains 'Checkpoint-Computer')) ''
Check 'restart pending: DISM skipped (it would hang)' (-not ($PMcalls -match 'DISM')) ''
Check 'Disk Cleanup hanging: stopped after 15 min and said so' (($PMcalls -match 'Stop-Process') -and ($o -match 'Disk Cleanup: stopped after 15 min')) ($o -join ' / ')
Reset-M; State @{ 'monthly-cleanup' = $old }; $PM.Rps = @(); $PM.RpWorks = $false; $o = PM
Check 'System Protection off: restore point FAILED is reported' ([bool]($o -match 'Restore point FAILED')) ($o -join ' / ')

Section 'Steam cleanup (monthly, Steam closed)'
$sl = "$Work\Steam"; foreach ($p in 'steamapps\downloading\111', 'steamapps\downloading\222', 'steamapps\common\Installed Game', 'steamapps\common\Uninstalled Game', 'steamapps\common\Small Leftover') { New-Item "$sl\$p" -ItemType Directory -Force | Out-Null }
'"AppState" { "installdir" "Installed Game" }' | Set-Content "$sl\steamapps\appmanifest_1.acf"
foreach ($p in 'steamapps\downloading\111\part.bin', 'steamapps\common\Installed Game\game.pak', 'steamapps\common\Uninstalled Game\data.pak') { $fs = [IO.File]::Create("$sl\$p"); $fs.SetLength(300MB); $fs.Close() }
'x' | Set-Content "$sl\steamapps\common\Small Leftover\a.txt"
foreach ($p in 'steamapps\downloading\111', 'steamapps\common\Installed Game', 'steamapps\common\Uninstalled Game', 'steamapps\common\Small Leftover') { (Get-Item "$sl\$p").LastWriteTime = $now.AddDays(-30) }
$rb = Join-Path $env:TEMP 'pckit-test-recycle'; if (Test-Path $rb) { Clear-Path $rb }
Reset-M; $PM.SteamPath = $sl -replace '\\', '/'; $PM.SteamRunning = $true; State @{ 'monthly-cleanup' = $old }; $o = PM
Check 'Steam running: its folders are not touched' ((Test-Path "$sl\steamapps\downloading\111") -and (Test-Path "$sl\steamapps\common\Uninstalled Game") -and -not ($o -match '^Steam:')) ($o -join ' / ')
Reset-M; $PM.SteamPath = $sl -replace '\\', '/'; State @{ 'monthly-cleanup' = $old }; $o = PM
Check 'an abandoned download (untouched 14+ days): removed; a recent one kept' (-not (Test-Path "$sl\steamapps\downloading\111") -and (Test-Path "$sl\steamapps\downloading\222") -and ($o -match '^Steam: removed 0\.3 GB of abandoned downloads')) ($o -join ' / ')
Check "an uninstalled game's leftover folder: to the Recycle Bin, said with its size" (-not (Test-Path "$sl\steamapps\common\Uninstalled Game") -and (Test-Path "$rb\Uninstalled Game") -and ($o -match 'Recycle Bin: Uninstalled Game \(0\.3 GB\)')) ($o -join ' / ')
Check '... an installed game and a tiny leftover: kept' ((Test-Path "$sl\steamapps\common\Installed Game\game.pak") -and (Test-Path "$sl\steamapps\common\Small Leftover")) ''
if (Test-Path $rb) { Clear-Path $rb }
Section 'TRIM and the next-run line'
Reset-M; State @{ 'trim' = $old }; $PM.DefragLast = $now.AddDays(-20); $o = PM
Check 'Windows has not trimmed the SSD in 2+ weeks: TRIM is run' (($PMcalls -match 'Optimize-Volume.*ReTrim') -and ($o -match 'SSD TRIM run')) ($PMcalls -join ', ')
Reset-M; State @{ 'trim' = $old }; $PM.DefragLast = $now.AddDays(-3); [void](PM)
Check '... not when Windows did it recently' (-not ($PMcalls -match 'Optimize-Volume')) ''
Reset-M; State @{}; $o = PM
$o = @($o | Where-Object { $_ })
Check 'nothing due: only the next-run dates' (($o.Count -eq 1) -and ($o[0] -match '^Next: App updates \w{3} \d+, cleanup \w{3} \d+')) ($o -join ' / ')
Check 'nothing due: no system changes at all' ($PMcalls.Count -eq 0) ($PMcalls -join ', ')
Finish
