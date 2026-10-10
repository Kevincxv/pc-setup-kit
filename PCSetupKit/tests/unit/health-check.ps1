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
    'Get-PSDrive', 'Get-PhysicalDisk', 'Get-StorageReliabilityCounter', 'Get-ScheduledTask', 'Get-NetAdapter', 'Get-Disk', 'Get-Partition',
    'Get-ItemProperty', 'Enable-ComputerRestore', 'reagentc', 'Confirm-SecureBootUEFI', 'Get-SecureBootUEFI', 'Get-AuthenticodeSignature'
if (-not (Test-Tripwire "$d\health-check.ps1" $mocked -Guarded 'C:\PCSetupKit\tweaks.ps1')) { Finish }   # (Test-Path mock hides the real tweak guard)

Import-MockTargets $mocked   # load their Windows modules BEFORE defining the mocks (see lib.ps1)
# ---- mocks (functions win over cmdlets/programs; the script is run in this scope so it sees them) ----
$now = Get-Date
function Ev($id, $min, $msg = '', $prov = '', $val = 0) { [pscustomobject]@{ Id = $id; TimeCreated = $now.AddMinutes(-$min); Message = $msg; ProviderName = $prov; Properties = @([pscustomobject]@{ Value = $val }) } }
function Healthy {
    $script:M = @{
        Events = @([pscustomobject]@{ Id = 35; ProviderName = 'Microsoft-Windows-Time-Service'; TimeCreated = $now.AddHours(-3) }); Dumps = @(); Reboot = $false   # (35: the clock was synced)
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
        Sp = '\\?\Volume{1}\:(C%3A)'; SpFail = $false; Re = 'Windows RE status:         Enabled'; WebView2 = '140.0.0.0'; WvExit = 0; SecureBoot = $true; Db = 'Microsoft Windows Production PCA 2011 ... Windows UEFI CA 2023'
    }
    $global:HCcalls = New-Object System.Collections.Generic.List[string]
}
function Get-WinEvent { param($FilterHashtable, $MaxEvents, $ErrorAction)
    $f = $FilterHashtable
    @($M.Events | Where-Object { (-not $f.Id -or $_.Id -in @($f.Id)) -and (-not $f.ProviderName -or $_.ProviderName -eq $f.ProviderName) -and (-not $f.StartTime -or $_.TimeCreated -ge $f.StartTime) }) }
function Get-ChildItem { if ((@($args | ForEach-Object { $_ }) -join ' ') -match 'Minidump|MEMORY\.DMP') { return $M.Dumps }; Microsoft.PowerShell.Management\Get-ChildItem @args }
function Test-Path { $a = @($args | ForEach-Object { $_ }) -join ' '; if ($a -match 'PCKitTest(Tool|Good)') { return $true }; if ($a -match 'PCSetupKit\\tweaks\.ps1') { return $false }; if ($a -match 'RebootPending|RebootRequired') { return $M.Reboot }; Microsoft.PowerShell.Management\Test-Path @args }
function Get-CimInstance { if ("$args" -match 'Win32_PhysicalMemory') { return $M.Ram }; if ("$args" -match 'Win32_BIOS') { return $M.Bios }; if ("$args" -match 'Win32_Battery') { return $M.Battery }
    if ("$args" -match 'Win32_OperatingSystem' -and $M.Boot) { return [pscustomobject]@{ LastBootUpTime = $M.Boot } }; CimCmdlets\Get-CimInstance @args }
function Get-MpComputerStatus { $M.Mp }
function Start-Process { $global:HCcalls.Add("Start-Process $args") }
function w32tm { if ("$args" -match 'resync') { $global:HCcalls.Add('w32tm resync') } else { $M.W32 } }
function winget { if ("$args" -match '^install') { $global:HCcalls.Add("winget $args"); $global:LASTEXITCODE = $M.WvExit; return }; $M.Winget }
function Confirm-SecureBootUEFI { $M.SecureBoot }
function Get-AuthenticodeSignature { param($LiteralPath, $FilePath) [pscustomobject]@{ Status = $(if ("$LiteralPath$FilePath" -in @($global:Unsigned)) { 'NotSigned' } else { 'Valid' }) } }
function Get-SecureBootUEFI { param($Name, $ErrorAction) [pscustomobject]@{ bytes = [Text.Encoding]::ASCII.GetBytes($M.Db) } }
function Get-PnpDevice { param([switch]$PresentOnly, $Class) $M.Gpus }
function Get-PnpDeviceProperty { param($InstanceId, $KeyName) $M.GpuProps[$InstanceId] }
function Get-PSDrive { $M.CDrive }
function Get-PhysicalDisk { $M.Disks }
function Get-StorageReliabilityCounter { $input | ForEach-Object { $M.Rel[$_.FriendlyName] } }
function Get-NetAdapter { $M.Nics }
function Get-Disk { $M.AllDisks }
function Get-Partition { [pscustomobject]@{ DiskNumber = 0 } }
function Get-ScheduledTask { $M.Tasks }
function Get-ItemProperty { if ("$args" -match 'SPP\\Clients') { [pscustomobject]@{ '{09F7EDC5-294E-4180-AF6A-FB0E6A0E9513}' = $M.Sp } }; if ("$args" -match 'F3017226') { [pscustomobject]@{ pv = $M.WebView2 } } }
function Enable-ComputerRestore { param($Drive) $global:HCcalls.Add("Enable-ComputerRestore $Drive"); if ($M.SpFail) { throw 'The service cannot be started' } }
function reagentc { if ("$args" -match 'enable') { $global:HCcalls.Add('reagentc /enable'); $global:LASTEXITCODE = 0 } else { $M.Re } }
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
Check 'no read/write error line without disk errors' (-not ($o -match 'read/write error')) ($o -join ' / ')
Check 'the next check does not report the same crashes again' (($o -contains 'Crashes: none since last check') -and -not ($o -match 'crash dump')) ($o -join ' / ')

Section 'RAM stick test'
function Stick($bank) { [pscustomobject]@{ ConfiguredClockSpeed = 6000; Speed = 4800; PartNumber = 'TESTKIT-6000  '; Capacity = 16GB; BankLabel = $bank } }
Healthy; $M.Ram = @((Stick 'P0 CHANNEL A'), (Stick 'P0 CHANNEL B')); $M.Boot = $now.AddHours(-30)
Clear-Path "$d\ram-test.log"; Clear-Path "$d\health-check.last"; $o = HC
Check 'no test running: no log, no line' (-not (Test-Path "$d\ram-test.log") -and -not ($o -match 'RAM test')) ($o -join ' / ')
@{ 'ram-stick-test' = $now.AddDays(-1).ToString('o') } | ConvertTo-Json | Set-Content "$d\maint-state.json"
$o = HC; $o2 = HC
Check 'test running, both sticks still in: the start is logged once, nothing said' ((@(Get-Content "$d\ram-test.log") -join '/') -eq "$($M.Boot.ToString('yyyy-MM-dd HH:mm')) | start | 2 stick(s), 32 GB in P0 CHANNEL A + P0 CHANNEL B" -and -not ($o + $o2 -match 'RAM test')) ((Get-Content "$d\ram-test.log") -join ' / ')
$M.Ram = @((Stick 'P0 CHANNEL A')); $M.Boot = $now.AddHours(-5); $o = HC
Check 'one stick taken out: the line counts its starts' ([bool]($o -match 'RAM test: 1 stick\(s\), 16 GB in P0 CHANNEL A - 1 start\(s\), 0 crash\(es\)')) ($o -join ' / ')
$M.Boot = $now.AddMinutes(-31); $M.Events = @($M.Events) + @(Ev 1001 30 'The computer has rebooted from a bugcheck.  The bugcheck was: 0x00000109 (0x...)' 'Microsoft-Windows-WER-SystemErrorReporting')
Clear-Path "$d\health-check.last"; $o = HC
Check '... a blue screen on it is counted with the restart after it' ([bool]($o -match 'RAM test: 1 stick\(s\), 16 GB in P0 CHANNEL A - 2 start\(s\), 1 crash\(es\)')) ($o -join ' / ')
$o = HC
Check '... and not counted twice at the next check' ([bool]($o -match '2 start\(s\), 1 crash\(es\)')) ($o -join ' / ')
$M.Ram = @((Stick 'P0 CHANNEL A'), (Stick 'P0 CHANNEL B')); $M.Boot = $now.AddMinutes(-2); $o = HC
Check 'both sticks back in: quiet again' (-not ($o -match 'RAM test')) ($o -join ' / ')
Clear-Path "$d\maint-state.json"; Clear-Path "$d\ram-test.log"

Section 'CPU slowed down by the firmware'
Healthy; $cpu = 'Microsoft-Windows-Kernel-Processor-Power'
$M.Events = @($M.Events) + @((Ev 37 10 '' $cpu), (Ev 37 11 '' $cpu), (Ev 37 12 '' $cpu), (Ev 55 13 '' $cpu))
Clear-Path "$d\health-check.last"; $o = HC
Check '3 slowdowns since the last check are mentioned (other CPU power events not counted)' ([bool]($o -match 'Reminder: the CPU was slowed down by its firmware 3 times')) ($o -join ' / ')
$o = HC
Check '... not again at the next check' (-not ($o -match 'CPU was slowed')) ($o -join ' / ')
$M.Battery = @([pscustomobject]@{ BatteryStatus = 1 }); Clear-Path "$d\health-check.last"; $o = HC
Check '... a laptop on battery slows down on purpose: quiet' (-not ($o -match 'CPU was slowed')) ($o -join ' / ')
Healthy; $M.Events = @($M.Events) + @((Ev 37 10 '' $cpu)); Clear-Path "$d\health-check.last"; $o = HC
Check '... a single slowdown is not mentioned' (-not ($o -match 'CPU was slowed')) ($o -join ' / ')
# one slowdown is logged once per CPU thread (16 events at the same moment on a 16-thread CPU): still one
Healthy; $M.Events = @($M.Events) + @(1..16 | ForEach-Object { Ev 37 10 '' $cpu }); Clear-Path "$d\health-check.last"; $o = HC
Check '... one slowdown logged by every CPU thread counts once (not mentioned)' (-not ($o -match 'CPU was slowed')) ($o -join ' / ')

Section 'disk read/write errors'
Healthy
$M.Disks = @([pscustomobject]@{ DeviceId = 0; FriendlyName = 'TestNVMe'; BusType = 'NVMe'; HealthStatus = 'Healthy'; OperationalStatus = 'OK' },
    [pscustomobject]@{ DeviceId = 1; FriendlyName = 'KitUSB'; BusType = 'USB'; HealthStatus = 'Healthy'; OperationalStatus = 'OK' })
$M.Events = @($M.Events) + @((Ev 7 10 'The device, \Device\Harddisk0\DR0, has a bad block.' 'disk'), (Ev 153 11 'Gerät \Device\Harddisk0\DR0 wiederholt' 'disk'),
    (Ev 51 12 '' 'disk' '\Device\Harddisk1\DR1'), (Ev 11 13 'The driver detected a controller error on \Device\RaidPort0.' 'stornvme'))
Clear-Path "$d\health-check.last"; $o = HC
Check 'errors on an internal drive are counted (any language, NVMe controller errors too)' ([bool]($o -match 'WARNING: TestNVMe logged 3 read/write error')) ($o -join ' / ')
Check 'errors on a USB stick are not reported' (-not ($o -match 'KitUSB')) ($o -join ' / ')
$o = HC
Check 'the next check does not report the same disk errors again' (-not ($o -match 'read/write error')) ($o -join ' / ')

Section 'security, clock, app updates'
Healthy; $M.Mp = [pscustomobject]@{ RealTimeProtectionEnabled = $false; QuickScanAge = 9 }; $M.Events = @($M.Events | Where-Object ProviderName -ne 'Microsoft-Windows-Time-Service')   # no sync in 10 days
$M.Winget = @('Name           Id              Version  Available  Source', '----------------------------------------------------------', 'App One        Vendor.AppOne   1.0      1.1        winget', 'App Two Long   Vendor.AppTwo   2.0      2.5        winget', '2 upgrades available.')
$o = HC
Check 'Defender real-time protection off = WARNING' ([bool]($o -match 'WARNING: Defender real-time protection is OFF')) ''
Check 'a virus scan older than 7 days starts a quick scan' (($global:HCcalls -match 'MpCmdRun') -and ($o -match 'started a quick virus scan \(last one 9 days')) ($global:HCcalls -join ', ')
Check 'clock not synced for 10 days -> resync' ([bool]($global:HCcalls -contains 'w32tm resync')) ($global:HCcalls -join ', ')
Check 'app updates listed by name' ([bool]($o -match 'Apps: 2 update\(s\) available \(App One, App Two Long\)')) ($o -join ' / ')
Healthy; $M.Mp = [pscustomobject]@{ RealTimeProtectionEnabled = $true; QuickScanAge = 4294967295 }
$M.Winget = @('Name           Id              Version  Available  Source', '----------------------------------------------------------', ('Long App Na' + [string][char]0xE2 + [char]0x20AC + [char]0xA6 + ' Vendor.LongApp   1.0      1.1        winget'), 'Odd Version    Vendor.Odd      < 2.0    2.1        winget', '2 upgrades available.')
$o = HC
Check 'a never-run virus scan says "never" (Windows reports 4294967295 days)' ([bool]($o -match 'last one never\)')) ($o -join ' / ')
Check 'app names read right even when a shortened name shifts the columns' ([bool]($o -match 'Apps: 2 update\(s\) available \(Long App Na.+, Odd Version\)')) ($o -join ' / ')
Healthy; $M.Mp.QuickScanAge = 9; 'x' | Set-Content "$d\gaming.flag"
$o = HC
Check 'no virus scan while a game runs' (-not ($global:HCcalls -match 'MpCmdRun')) ($global:HCcalls -join ', ')
Clear-Path "$d\gaming.flag"
Healthy; $M.Mp = [pscustomobject]@{ RealTimeProtectionEnabled = $true; QuickScanAge = 1; AntivirusSignatureAge = 5 }; $o = HC
Check 'virus definitions 5 days old -> update started' (($global:HCcalls -match 'SignatureUpdate') -and ($o -match 'virus definitions were 5 days old - started an update')) (($global:HCcalls -join ', ') + ' / ' + ($o -join ' / '))
Healthy; $M.Mp = [pscustomobject]@{ RealTimeProtectionEnabled = $true; QuickScanAge = 1; AntivirusSignatureAge = 1 }; $o = HC
Check '... fresh definitions: no update, no line' (-not ($global:HCcalls -match 'SignatureUpdate') -and -not ($o -match 'virus definitions')) ($o -join ' / ')
Healthy; $M.Events = @()   # the time service never synced (not started)
[void](HC); Check 'time service not answering -> resync (no error)' ([bool]($global:HCcalls -contains 'w32tm resync')) ''

Section 'tweak guard'
Healthy; 'x' | Set-Content "$d\reverted.flag"; $o = HC
Check 'a tweak Windows reverted is re-applied and reported' ([bool]($o -match 'Tweaks: Windows had reverted 1 - re-applied: iGPU disabled again')) ($o -join ' / ')
'x' | Set-Content "$d\setup-maint-running.txt"; $o = HC
Check '... in the first maintenance right after setup: what setup left for it, not called reverted' ([bool]($o -match "Tweaks: the rest of setup's changes applied \(1\): iGPU disabled again") -and -not ($o -match 'had reverted')) ($o -join ' / ')
Clear-Path "$d\setup-maint-running.txt"
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
$M.Tasks += [pscustomobject]@{ TaskName = 'Claude Resume After Restart'; TaskPath = '\'; State = 'Ready' }, [pscustomobject]@{ TaskName = 'PCSetupKit Tray TEST'; TaskPath = '\'; State = 'Ready' }, [pscustomobject]@{ TaskName = 'PCSetupKitRevertTest'; TaskPath = '\PCSetupKitTest\'; State = 'Ready' }, [pscustomobject]@{ TaskName = 'Messiah Night Restart'; TaskPath = '\'; State = 'Ready' }; $o = HC
Check 'the kit''s own tasks (one-shot resume task, test runs'' throwaway tasks) are not reported as new' (-not ($o -match 'auto-start')) ($o -join ' / ')
# a new one's program: checked for its maker's signature (what Autoruns flags; 10/10, the research comparison)
# (the two in Program Files are stand-ins the Test-Path mock reports as there: the test's own folder is under Temp)
$evil = "$Work\AppData\Roaming\Evil\evil.exe"; $tool = 'C:\Program Files\PCKitTestTool\tool.exe'; $good = 'C:\Program Files\PCKitTestGood\good.exe'
New-Item (Split-Path $evil) -ItemType Directory -Force | Out-Null; '' | Set-Content $evil
$global:Unsigned = @($evil, $tool)
$M.Tasks += [pscustomobject]@{ TaskName = 'EvilUpdate'; TaskPath = '\'; State = 'Ready'; Actions = @([pscustomobject]@{ Execute = $evil }) },
    [pscustomobject]@{ TaskName = 'ToolHelper'; TaskPath = '\'; State = 'Ready'; Actions = @([pscustomobject]@{ Execute = "`"$tool`"" }) },
    [pscustomobject]@{ TaskName = 'GoodUpdater'; TaskPath = '\'; State = 'Ready'; Actions = @([pscustomobject]@{ Execute = $good }) }
$o = HC
Check 'a new unsigned one running from AppData: a WARNING naming it (gets looked at)' ($o -match '^WARNING: new auto-start item\(s\) not signed .*task: EvilUpdate') ($o -join ' / ')
Check '... an unsigned one elsewhere: the usual reminder, marked "not signed"; a signed one as before' (($o -match 'task: ToolHelper \(not signed\)') -and ($o -match 'task: GoodUpdater(,|\s\()') -and -not ($o -match 'GoodUpdater \(not signed\)') -and -not ($o -match 'Reminder: .*EvilUpdate')) ($o -join ' / ')
Healthy; $M.Nics = @([pscustomobject]@{ Name = 'Ethernet'; Status = 'Up'; MediaType = '802.3'; ReceiveLinkSpeed = 100e6; LinkSpeed = '100 Mbps'; InterfaceDescription = 'Intel(R) Ethernet Controller I225-V' }); $o = HC
Check 'gigabit adapter stuck at 100 Mbps -> cable reminder' ([bool]($o -match 'Reminder: Ethernet network link is only 100 Mbps')) ($o -join ' / ')
Healthy; $M.AllDisks += [pscustomobject]@{ Number = 1; FriendlyName = 'WD Elements'; BusType = 'USB'; Size = 4TB }; $o = HC
Check 'external 4 TB drive and no backups -> offer to set them up' ([bool]($o -match 'Reminder: WD Elements \(4096 GB\) is connected and nothing is backed up')) ($o -join ' / ')
$M.Tasks += [pscustomobject]@{ TaskName = 'Nightly Backup'; TaskPath = '\'; State = 'Ready' }; $o = HC
Check '... not when a backup task exists' (-not ($o -match 'nothing is backed up')) ''
Healthy; $M.Sp = ''; $M.Re = 'Windows RE status:         Disabled'; $o = HC
Check 'restore points and recovery tools turned off (an update, a debloat tool) -> both back on, said' (($global:HCcalls -contains "Enable-ComputerRestore $env:SystemDrive\") -and ($global:HCcalls -contains 'reagentc /enable') -and ($o -contains 'Backups: restore points were off - turned back on') -and ($o -contains 'Backups: the Windows recovery tools were off - turned back on')) (($global:HCcalls -join ', ') + ' / ' + ($o -join ' / '))
Healthy; $M.Sp = ''; $M.SpFail = $true; $o = HC
Check '... restore points that can''t be turned on -> a WARNING' ([bool]($o -match '^WARNING: restore points are off and could not')) ($o -join ' / ')

Section 'robustness'
# $Error sees every error, also one a script writes straight to the host (2>&1 missed it - this check once passed with
# the bug). It also holds errors the script silences on purpose, so: errors with a corrupt file minus a normal run's
function HCErrors { $Error.Clear(); [void](& { $u = $env:USERPROFILE; $env:USERPROFILE = $H; try { & "$d\health-check.ps1" 2>&1 } finally { $env:USERPROFILE = $u } }); @($Error | ForEach-Object { "$_" } | Sort-Object -Unique) }
Healthy; (Get-Date).AddDays(-1).ToString('o') | Set-Content "$d\health-check.last"; $base = HCErrors
Healthy; 'not a date' | Set-Content "$d\health-check.last"; $e = @(HCErrors | Where-Object { $_ -notin $base })
Check 'a corrupt last-check file causes no errors' ($e.Count -eq 0) "$e"
Check '... and is replaced by a good one' ([datetime]::TryParse((Get-Content "$d\health-check.last" -Raw).Trim(), [ref][datetime]::MinValue)) ''
Section 'WebView2 and Secure Boot''s 2023 certificate (10/10, the research comparison)'
Healthy; $M.WebView2 = $null; $global:HCcalls.Clear(); Clear-Path "$d\health-check.last"; $o = HC
Check 'WebView2 missing (an older install USB): installed with winget, said' (($HCcalls -match 'winget install --id Microsoft\.EdgeWebView2Runtime') -and ($o -match '^Repaired: WebView2')) (($o + $HCcalls) -join ' / ')
Healthy; $M.WebView2 = $null; $M.WvExit = 1; $global:HCcalls.Clear(); Clear-Path "$d\health-check.last"; $o = HC
Check '... the install failing: a WARNING (gets looked at)' ($o -match '^WARNING: WebView2 is missing') ($o -join ' / ')
Healthy; $global:HCcalls.Clear(); Clear-Path "$d\health-check.last"; $o = HC
Check '... there: nothing installed, nothing said' (-not ($HCcalls -match 'WebView2') -and -not ($o -match 'WebView2|Secure Boot')) (($o + $HCcalls) -join ' / ')
Healthy; $M.Db = 'Microsoft Windows Production PCA 2011 / Microsoft Corporation UEFI CA 2011'; Clear-Path "$d\health-check.last"; $o = HC
Check 'Secure Boot without the 2023 certificate: a reminder' ($o -match '^Reminder: Secure Boot doesn''t have Microsoft''s 2023 certificate') ($o -join ' / ')
$M.SecureBoot = $false; Clear-Path "$d\health-check.last"; $o = HC
Check '... Secure Boot off: nothing said about it' (-not ($o -match 'Secure Boot doesn')) ($o -join ' / ')
Finish
