# health-check.ps1 with every system query mocked: a healthy PC, a PC with every kind of problem, and edge cases.
# Nothing on the real system is changed (tripwire: every command the script uses is mocked or read-only).
. "$PSScriptRoot\..\lib.ps1"
$H = "$Work\home"; $d = "$H\.claude"; New-Item $d -ItemType Directory -Force | Out-Null
Copy-Item "$Src\health-check.ps1" $d
'"code 0x109 | blamed: stub.sys (stub) | bucket: TEST_BUCKET"; Add-Content "$PSScriptRoot\analyzed.log" $Dump; param()' | Set-Content "$d\crash-analyze.ps1"
'param([string]$Dump) Add-Content "$PSScriptRoot\analyzed.log" $Dump; "code 0x109 | blamed: stub.sys (stub) | bucket: TEST_BUCKET"' | Set-Content "$d\crash-analyze.ps1"
'if (Test-Path "$PSScriptRoot\gaming.flag") { ''TestGame'' }' | Set-Content "$d\game-check.ps1"
'if (Test-Path "$PSScriptRoot\reverted.flag") { ''iGPU disabled again'' }' | Set-Content "$d\tweaks-local.ps1"
'' | Set-Content "$d\restart-check.ps1"
$mocked = 'Get-WinEvent', 'Get-ChildItem', 'Get-CimInstance', 'Get-MpComputerStatus', 'Start-Process', 'w32tm', 'winget', 'Get-PnpDevice', 'Get-PnpDeviceProperty',
    'Get-PSDrive', 'Get-PhysicalDisk', 'Get-StorageReliabilityCounter', 'Get-ScheduledTask', 'Get-NetAdapter', 'Get-Disk', 'Get-Partition'
if (-not (Test-Tripwire "$d\health-check.ps1" $mocked -Guarded 'C:\PCSetupKit\tweaks.ps1')) { Finish }   # (Test-Path mock hides the real tweak guard)

Import-MockTargets $mocked   # load their Windows modules BEFORE defining the mocks (see lib.ps1)
# ---- mocks (functions win over cmdlets/programs; the script is run in this scope so it sees them) ----
$now = Get-Date
function Ev($id, $min, $msg = '', $prov = '', $val = 0) { [pscustomobject]@{ Id = $id; TimeCreated = $now.AddMinutes(-$min); Message = $msg; ProviderName = $prov; Properties = @([pscustomobject]@{ Value = $val }) } }
function Healthy {
    $script:M = @{
        Events = @(); Dumps = @(); Reboot = $false
        Mp = [pscustomobject]@{ RealTimeProtectionEnabled = $true; QuickScanAge = 1 }
        W32 = @("Last Successful Sync Time: $($now.AddHours(-3).ToString())")
        Winget = @('No installed package found matching input criteria.')
        Gpus = @([pscustomobject]@{ FriendlyName = 'NVIDIA GeForce RTX 9090'; InstanceId = 'PCI\GPU1' }); GpuProps = @{ 'PCI\GPU1' = @(@{ Data = 16 }, @{ Data = 16 }) }
        Ram = [pscustomobject]@{ ConfiguredClockSpeed = 6000; Speed = 4800; PartNumber = 'TESTKIT-6000  ' }
        Bios = [pscustomobject]@{ ReleaseDate = $now.AddMonths(-3); SMBIOSBIOSVersion = '4.43' }
        CDrive = [pscustomobject]@{ Free = 800GB; Used = 1000GB }
        Disks = @([pscustomobject]@{ FriendlyName = 'TestNVMe'; BusType = 'NVMe'; HealthStatus = 'Healthy'; OperationalStatus = 'OK' }); Rel = @{ 'TestNVMe' = [pscustomobject]@{ Wear = 3; Temperature = 40 } }
        Nics = @([pscustomobject]@{ Name = 'Ethernet'; Status = 'Up'; MediaType = '802.3'; ReceiveLinkSpeed = 1e9; LinkSpeed = '1 Gbps'; InterfaceDescription = 'Realtek Gaming 2.5GbE' })
        AllDisks = @([pscustomobject]@{ Number = 0; FriendlyName = 'TestNVMe'; BusType = 'NVMe'; Size = 2TB })
        Tasks = @([pscustomobject]@{ TaskName = 'Messiah Tray'; TaskPath = '\'; State = 'Ready' })
    }
    $global:HCcalls = New-Object System.Collections.Generic.List[string]
}
function Get-WinEvent { param($FilterHashtable, $MaxEvents, $ErrorAction)
    $f = $FilterHashtable
    @($M.Events | Where-Object { (-not $f.Id -or $_.Id -eq $f.Id) -and (-not $f.ProviderName -or $_.ProviderName -eq $f.ProviderName) -and (-not $f.StartTime -or $_.TimeCreated -ge $f.StartTime) }) }
function Get-ChildItem { if ((@($args | ForEach-Object { $_ }) -join ' ') -match 'Minidump|MEMORY\.DMP') { return $M.Dumps }; Microsoft.PowerShell.Management\Get-ChildItem @args }
function Test-Path { $a = @($args | ForEach-Object { $_ }) -join ' '; if ($a -match 'PCSetupKit\\tweaks\.ps1') { return $false }; if ($a -match 'RebootPending|RebootRequired') { return $M.Reboot }; Microsoft.PowerShell.Management\Test-Path @args }
function Get-CimInstance { if ("$args" -match 'Win32_PhysicalMemory') { return $M.Ram }; if ("$args" -match 'Win32_BIOS') { return $M.Bios }; CimCmdlets\Get-CimInstance @args }
function Get-MpComputerStatus { $M.Mp }
function Start-Process { $global:HCcalls.Add("Start-Process $args") }
function w32tm { if ("$args" -match 'resync') { $global:HCcalls.Add('w32tm resync') } else { $M.W32 } }
function winget { $M.Winget }
function Get-PnpDevice { param([switch]$PresentOnly, $Class) $M.Gpus }
function Get-PnpDeviceProperty { param($InstanceId, $KeyName) $M.GpuProps[$InstanceId] }
function Get-PSDrive { $M.CDrive }
function Get-PhysicalDisk { $M.Disks }
function Get-StorageReliabilityCounter { $input | ForEach-Object { $M.Rel[$_.FriendlyName] } }
function Get-NetAdapter { $M.Nics }
function Get-Disk { $M.AllDisks }
function Get-Partition { [pscustomobject]@{ DiskNumber = 0 } }
function Get-ScheduledTask { $M.Tasks }
function HC { $u = $env:USERPROFILE; $env:USERPROFILE = $H; try { @(& "$d\health-check.ps1" | Where-Object { $_ -notmatch 'Hz but supports' }) } finally { $env:USERPROFILE = $u } }   # (monitor Hz = the real screens)

if (-not (Assert-Mocks $mocked)) { Finish }

Section 'a healthy PC'
Healthy; $o = HC
Check 'crashes: none, tweaks: all applied' (($o -contains 'Crashes: none since last check') -and ($o -contains 'Tweaks: all still applied')) ($o -join ' / ')
Check 'no WARNING, REBOOT or Reminder lines' (-not ($o -match 'WARNING|REBOOT|Reminder')) ($o -join ' / ')
Check 'no virus scan or clock resync started' ($global:HCcalls.Count -eq 0) ($global:HCcalls -join ', ')
Check 'the check time is remembered' (Test-Path "$d\health-check.last") ''

Section 'crashes'
Healthy
$M.Events = @((Ev 1001 30 'The computer has rebooted from a bugcheck.  The bugcheck was: 0x00000109 (0x...)' 'Microsoft-Windows-WER-SystemErrorReporting'),
    (Ev 41 40 '' 'Microsoft-Windows-Kernel-Power' 0), (Ev 41 50 '' 'Microsoft-Windows-Kernel-Power' 0x109),
    (Ev 18 20 '' 'Microsoft-Windows-WHEA-Logger'), (Ev 19 21 '' 'Microsoft-Windows-WHEA-Logger'))
$t = $now.AddMinutes(-30)
$M.Dumps = @([pscustomobject]@{ Name = '092726-1-01.dmp'; FullName = 'C:\Windows\Minidump\092726-1-01.dmp'; LastWriteTime = $t },
    [pscustomobject]@{ Name = 'MEMORY.DMP'; FullName = 'C:\Windows\MEMORY.DMP'; LastWriteTime = $t.AddMinutes(1) })
Clear-Path "$d\health-check.last"; Clear-Path "$d\analyzed.log"
$o = HC
Check 'blue screen reported with its code' ([bool]($o -match 'WARNING: blue screen 0x00000109')) ($o -join ' / ')
Check 'a hard reset without bugcheck is reported, one with a bugcheck code is not double-counted' (@($o -match 'unexpected shutdown/freeze').Count -eq 1) ($o -join ' / ')
Check 'hardware errors (WHEA) counted' ([bool]($o -match 'WARNING: 2 hardware error')) ($o -join ' / ')
Check 'the dump is analyzed once (MEMORY.DMP of the same crash skipped)' (@(Get-Content "$d\analyzed.log").Count -eq 1 -and ($o -match 'crash dump 092726-1-01.dmp - code 0x109')) ((Get-Content "$d\analyzed.log") -join ', ')
$o = HC
Check 'the next check does not report the same crashes again' (($o -contains 'Crashes: none since last check') -and -not ($o -match 'crash dump')) ($o -join ' / ')

Section 'security, clock, app updates'
Healthy; $M.Mp = [pscustomobject]@{ RealTimeProtectionEnabled = $false; QuickScanAge = 9 }; $M.W32 = @("Last Successful Sync Time: $($now.AddDays(-10).ToString())")
$M.Winget = @('Name           Id              Version  Available  Source', '----------------------------------------------------------', 'App One        Vendor.AppOne   1.0      1.1        winget', 'App Two Long   Vendor.AppTwo   2.0      2.5        winget', '2 upgrades available.')
$o = HC
Check 'Defender real-time protection off = WARNING' ([bool]($o -match 'WARNING: Defender real-time protection is OFF')) ''
Check 'a virus scan older than 7 days starts a quick scan' (($global:HCcalls -match 'MpCmdRun') -and ($o -match 'started a quick virus scan \(last one 9 days')) ($global:HCcalls -join ', ')
Check 'clock not synced for 10 days -> resync' ([bool]($global:HCcalls -contains 'w32tm resync')) ($global:HCcalls -join ', ')
Check 'app updates listed by name' ([bool]($o -match 'Apps: 2 update\(s\) available \(App One, App Two Long\)')) ($o -join ' / ')
Healthy; $M.Mp.QuickScanAge = 9; 'x' | Set-Content "$d\gaming.flag"
$o = HC
Check 'no virus scan while a game runs' (-not ($global:HCcalls -match 'MpCmdRun')) ($global:HCcalls -join ', ')
Clear-Path "$d\gaming.flag"
Healthy; $M.W32 = @('The following error occurred: The service has not been started.')
[void](HC); Check 'time service not answering -> resync (no error)' ([bool]($global:HCcalls -contains 'w32tm resync')) ''

Section 'tweak guard'
Healthy; 'x' | Set-Content "$d\reverted.flag"; $o = HC
Check 'a tweak Windows reverted is re-applied and reported' ([bool]($o -match 'Tweaks: Windows had reverted 1 - re-applied: iGPU disabled again')) ($o -join ' / ')
Clear-Path "$d\reverted.flag"

Section 'hardware reminders'
Healthy; $M.GpuProps['PCI\GPU1'] = @(@{ Data = 8 }, @{ Data = 16 }); $o = HC
Check 'GPU at PCIe x8 of x16 -> reminder' ([bool]($o -match 'Reminder: NVIDIA GeForce RTX 9090 runs at PCIe x8 \(card supports x16\)')) ($o -join ' / ')
'RTX 9090' | Set-Content "$d\health-ignore.txt"; $o = HC
Check '... unless the owner chose to ignore that GPU' (-not ($o -match 'PCIe x8')) ''
Clear-Path "$d\health-ignore.txt"
Healthy; $M.Ram = [pscustomobject]@{ ConfiguredClockSpeed = 4800; Speed = 4800; PartNumber = 'TESTKIT-6000  ' }; $o = HC
Check 'RAM at its default 4800 -> EXPO/XMP reminder' ([bool]($o -match 'Reminder: RAM runs at its default 4800 MT/s \(TESTKIT-6000\)')) ($o -join ' / ')
@{ 'expo-off-test' = $now.AddDays(-2).ToString('o') } | ConvertTo-Json | Set-Content "$d\maint-state.json"; $o = HC
Check '... silent during an EXPO-off crash test' (-not ($o -match 'RAM runs at its default')) ''
@{ 'expo-off-test' = $now.AddDays(-25).ToString('o') } | ConvertTo-Json | Set-Content "$d\maint-state.json"; $o = HC
Check '... and reminds again 21 days after the test started' ([bool]($o -match 'RAM runs at its default')) ''
Clear-Path "$d\maint-state.json"
Healthy; $M.Bios = [pscustomobject]@{ ReleaseDate = $now.AddMonths(-20); SMBIOSBIOSVersion = '1.10' }; $o = HC
Check 'BIOS older than 12 months -> reminder' ([bool]($o -match 'Reminder: BIOS 1.10 is from')) ($o -join ' / ')

Section 'system warnings'
Healthy; $M.Reboot = $true; $M.CDrive = [pscustomobject]@{ Free = 50GB; Used = 1950GB }
$M.Disks = @([pscustomobject]@{ FriendlyName = 'TestNVMe'; BusType = 'NVMe'; HealthStatus = 'Warning'; OperationalStatus = 'Predictive Failure' },
    [pscustomobject]@{ FriendlyName = 'USB stick'; BusType = 'USB'; HealthStatus = 'Unhealthy'; OperationalStatus = 'x' })
$M.Rel = @{ 'TestNVMe' = [pscustomobject]@{ Wear = 85; Temperature = 75 } }
$o = HC
Check 'restart pending -> REBOOT line (does not wake /maintain)' ([bool]($o -match '^REBOOT pending')) ''
Check 'C: under 10% free -> WARNING' ([bool]($o -match 'WARNING: C: is low on space \(50 GB free\)')) ($o -join ' / ')
Check 'SMART failure prediction -> WARNING to back up' ([bool]($o -match 'WARNING: drive TestNVMe reports Warning health')) ''
Check 'SSD wear 85% and 75 C -> WARNINGs' (($o -match 'wear at 85%') -and ($o -match 'is hot \(75 C\)')) ''
Check 'USB drives are not judged' (-not ($o -match 'USB stick')) ''

Section 'new auto-start items, network, backups'
Healthy; Clear-Path "$d\startup-baseline.txt"; [void](HC)
Check 'first run only records the baseline' (Test-Path "$d\startup-baseline.txt") ''
$M.Tasks += [pscustomobject]@{ TaskName = 'SneakyUpdater_{11111111-2222-3333-4444-555555555555}'; TaskPath = '\'; State = 'Ready' }; $o = HC
Check 'a new startup task is mentioned once (GUID suffix stripped)' ([bool]($o -match 'Reminder: new auto-start item\(s\) since last check: task: SneakyUpdater\b')) ($o -join ' / ')
$o = HC; Check '... and not again' (-not ($o -match 'SneakyUpdater')) ''
$M.Tasks += [pscustomobject]@{ TaskName = 'SneakyUpdater_{99999999-2222-3333-4444-555555555555}'; TaskPath = '\'; State = 'Ready' }; $o = HC
Check 'an updater renaming its task (new GUID) stays quiet' (-not ($o -match 'SneakyUpdater')) ''
Healthy; $M.Nics = @([pscustomobject]@{ Name = 'Ethernet'; Status = 'Up'; MediaType = '802.3'; ReceiveLinkSpeed = 100e6; LinkSpeed = '100 Mbps'; InterfaceDescription = 'Intel(R) Ethernet Controller I225-V' }); $o = HC
Check 'gigabit adapter stuck at 100 Mbps -> cable reminder' ([bool]($o -match 'Reminder: Ethernet network link is only 100 Mbps')) ($o -join ' / ')
Healthy; $M.AllDisks += [pscustomobject]@{ Number = 1; FriendlyName = 'WD Elements'; BusType = 'USB'; Size = 4TB }; $o = HC
Check 'external 4 TB drive and no backups -> offer to set them up' ([bool]($o -match 'Reminder: WD Elements \(4096 GB\) is connected and nothing is backed up')) ($o -join ' / ')
$M.Tasks += [pscustomobject]@{ TaskName = 'Nightly Backup'; TaskPath = '\'; State = 'Ready' }; $o = HC
Check '... not when a backup task exists' (-not ($o -match 'nothing is backed up')) ''

Section 'robustness'
# $Error sees every error, also one a script writes straight to the host (2>&1 missed it - this check once passed with
# the bug). It also holds errors the script silences on purpose, so: errors with a corrupt file minus a normal run's
function HCErrors { $Error.Clear(); [void](& { $u = $env:USERPROFILE; $env:USERPROFILE = $H; try { & "$d\health-check.ps1" 2>&1 } finally { $env:USERPROFILE = $u } }); @($Error | ForEach-Object { "$_" } | Sort-Object -Unique) }
Healthy; (Get-Date).AddDays(-1).ToString('o') | Set-Content "$d\health-check.last"; $base = HCErrors
Healthy; 'not a date' | Set-Content "$d\health-check.last"; $e = @(HCErrors | Where-Object { $_ -notin $base })
Check 'a corrupt last-check file causes no errors' ($e.Count -eq 0) "$e"
Check '... and is replaced by a good one' ([datetime]::TryParse((Get-Content "$d\health-check.last" -Raw).Trim(), [ref][datetime]::MinValue)) ''
Finish
