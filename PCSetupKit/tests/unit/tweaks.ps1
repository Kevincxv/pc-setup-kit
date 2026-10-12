# tweaks.ps1 (the tweak guard: runs at setup and at every login on every PC) with every write mocked:
# a fresh Windows gets every tweak once (originals recorded), an already-tweaked PC gets nothing, special cases.
. "$PSScriptRoot\..\lib.ps1"
$tweaksText = Get-Content "$Kit\tweaks.ps1" -Raw
$bk = "$Work\tweaks-backup.json"
Set-Content "$Work\tweaks.ps1" $tweaksText.Replace("'C:\PCSetupKit\tweaks-backup.json'", "'$bk'")
$mocked = 'Set-ItemProperty', 'Start-Service', 'New-Item', 'Get-ItemProperty', 'Set-Service', 'Stop-Service', 'Get-Service', 'Disable-ScheduledTask', 'Unregister-ScheduledTask',
    'Get-ScheduledTask', 'Get-AppxPackage', 'Get-AppxProvisionedPackage', 'Remove-AppxPackage', 'Remove-AppxProvisionedPackage', 'Get-CimInstance', 'Set-CimInstance',
    'Get-NetAdapter', 'Get-NetAdapterAdvancedProperty', 'Set-NetAdapterAdvancedProperty', 'Get-Printer', 'Test-Path', 'powercfg', 'Get-Process', 'Stop-Process', 'Start-Process', 'Remove-ItemProperty', 'winget', 'Get-PhysicalDisk', 'Get-Partition',
    'Get-WindowsCapability', 'Remove-WindowsCapability', 'Add-WindowsCapability', 'Get-WindowsOptionalFeature', 'Disable-WindowsOptionalFeature', 'Enable-WindowsOptionalFeature', 'Get-WindowsReservedStorageState', 'Set-WindowsReservedStorageState', 'Get-PnpDevice'
# (Get-Acl/Set-Acl: guarded - only on PCKIT_VENDOR_ROOT, the test's own folder; with none set in a test nothing is touched)
# (Set-Item: only -Audit's stand-in functions, on the function: drive - checked below)
# (Get-Command: only reads - -Audit asks which powercfg is there, to keep asking it)
if (-not (Test-Tripwire "$Work\tweaks.ps1" $mocked @('Get-Acl', 'Set-Acl', 'Set-Item', 'Get-Command'))) { Finish }
Import-MockTargets $mocked   # load their Windows modules BEFORE defining the mocks (see lib.ps1)

$svcNames = 'DiagTrack', 'dmwappushservice', 'SysMain', 'MapsBroker', 'lfsvc', 'TrkWks', 'WSAIFabricSvc', 'PcaSvc', 'RetailDemo', 'StiSvc', 'PhoneSvc', 'diagsvc', 'Spooler'
function Fresh {
    $global:TW = @{
        Reg = @{ 'HKLM:\SYSTEM\CurrentControlSet\Control\Power|HibernateEnabled' = 1 }; Services = @{}; Printers = @(); Apps = @('Microsoft.Copilot', 'Microsoft.BingNews', 'MSTeams', 'SpotifyAB.SpotifyMusic', 'Microsoft.XboxGamingOverlay'); Prov = @('Microsoft.BingNews')
        Run = @(); Battery = $null; Plan = '381b4222-f694-41f0-9685-ff5bb260df2e'; Plans = @('381b4222-f694-41f0-9685-ff5bb260df2e'); Ac = @{}; Hib = 1; OneDrive = $false; Cpu = 'AMD Ryzen 7 5800X3D 8-Core Processor'; Cs = [pscustomobject]@{ AutomaticManagedPagefile = $true }; PageFiles = @()
        Tasks = @(@{ P = '\Microsoft\Windows\Application Experience\'; N = 'Microsoft Compatibility Appraiser'; S = 'Ready' }, @{ P = '\Microsoft\Windows\Feedback\Siuf\'; N = 'DmClient'; S = 'Ready' },
            @{ P = '\'; N = 'AsrAPPShopUpdate'; S = 'Ready' }, @{ P = '\Microsoft\Windows\Defrag\'; N = 'ScheduledDefrag'; S = 'Ready' }, @{ P = '\'; N = 'MyOwnTask'; S = 'Ready' })
        Power = @(@{ I = 'USB\VID_045E&PID_0B00\1_0'; E = $true }, @{ I = 'PCI\VEN_10EC&DEV_8125\X_0'; E = $true }, @{ I = 'USB\VID_046D&PID_C08B\M_0'; E = $true })
        Nic = @{ 'Energy-Efficient Ethernet' = 'Enabled'; 'Green Ethernet' = 'Enabled'; 'Jumbo Packet' = 'Disabled' }
        Caps = @{ 'Browser.InternetExplorer~~~~0.0.11.0' = 'Installed'; 'Media.WindowsMediaPlayer~~~~0.0.12.0' = 'Installed'; 'VBSCRIPT~~~~' = 'Installed'; 'Microsoft.Windows.Notepad.System~~~~0.0.1.0' = 'Installed' }
        Feats = @{ 'MicrosoftWindowsPowerShellV2Root' = 'Enabled'; 'Recall' = 'Disabled'; 'MediaPlayback' = 'Enabled' }; Reserved = 'Enabled'
    }
    foreach ($s in $svcNames) { $TW.Services[$s] = $(if ($s -in 'StiSvc', 'PhoneSvc', 'diagsvc', 'Spooler', 'SysMain', 'DiagTrack') { 'Automatic' } else { 'Manual' }) }
    $global:TWlog = New-Object System.Collections.Generic.List[string]
}
function Set-ItemProperty { param($Path, $Name, $Value, $Type) if ("$Path|$Name" -in @($global:TW.Blocked)) { $global:TWlog.Add("blocked $Name"); return }; $global:TW.Reg["$Path|$Name"] = $Value; $global:TWlog.Add("reg $Name=$Value") }
function Get-ItemProperty { param($Path, $Name) if ($global:TW.Reg.ContainsKey("$Path|$Name")) { [pscustomobject]@{ $Name = $global:TW.Reg["$Path|$Name"] } } }
function New-Item { param($Path, [switch]$Force, $ItemType) if ("$Path" -match '^HK') { $global:TWlog.Add("new key $Path") } else { Microsoft.PowerShell.Management\New-Item @PSBoundParameters } }
function Test-Path { $a = @($args | ForEach-Object { $_ }) -join ' '; if ($a -match 'RebootPending|RebootRequired') { return [bool]$global:TW.Pending }; if ($a -match '^HK') { return $true }; if ($a -match 'OneDrive(Setup)?\.exe$') { return [bool]$global:TW.OneDrive }; Microsoft.PowerShell.Management\Test-Path @args }
function Get-Service { param($Name) if ($global:TW.Services.ContainsKey($Name)) { [pscustomobject]@{ Name = $Name; StartType = $global:TW.Services[$Name] } } }
function Set-Service { param($Name, $StartupType) $global:TW.Services[$Name] = $StartupType; $global:TWlog.Add("service $Name $StartupType") }
function Start-Service { param($Name) $global:TWlog.Add("start $Name") }
function Stop-Service { param($Name, [switch]$Force) $global:TWlog.Add("stop $Name") }
function Get-ScheduledTask { param($TaskName) $global:TW.Tasks | ForEach-Object { [pscustomobject]@{ TaskPath = $_.P; TaskName = $_.N; State = $_.S } } }
function Disable-ScheduledTask { $input | ForEach-Object { $n = $_.TaskName; if (($global:TW.Tasks | Where-Object N -eq $n).D) { throw 'Access is denied.' }; ($global:TW.Tasks | Where-Object N -eq $n).S = 'Disabled'; $global:TWlog.Add("task off $n") } }
function Unregister-ScheduledTask { param($TaskName, $Confirm) $global:TW.Tasks = @($global:TW.Tasks | Where-Object N -ne $TaskName); $global:TWlog.Add("task removed $TaskName") }
function Get-AppxPackage { param([switch]$AllUsers, $Name) $n = if ($Name) { $Name } else { $args[0] }; if ($n -in $global:TW.Apps) { [pscustomobject]@{ Name = $n; PackageFullName = "$n`_1.0_x64" } } }
function Remove-AppxPackage { param($Package, [switch]$AllUsers) $n = ($Package -split '_')[0]; $global:TW.Apps = @($global:TW.Apps | Where-Object { $_ -ne $n }); $global:TWlog.Add("app removed $n") }
function Get-AppxProvisionedPackage { param([switch]$Online) $global:TW.Prov | ForEach-Object { [pscustomobject]@{ DisplayName = $_; PackageName = "$_`_prov" } } }
function Remove-AppxProvisionedPackage { param([switch]$Online, $PackageName) $global:TW.Prov = @($global:TW.Prov | Where-Object { "$_`_prov" -ne $PackageName }); $global:TWlog.Add("provisioned removed $PackageName") }
function Get-CimInstance { if ("$args" -match 'MSPower_DeviceEnable') { return $global:TW.Power | ForEach-Object { [pscustomobject]@{ InstanceName = $_.I; Enable = $_.E } } }
    if ("$args" -match 'Win32_Battery') { return $global:TW.Battery }
    if ("$args" -match 'Win32_Processor') { return [pscustomobject]@{ Name = $global:TW.Cpu } }; if ("$args" -match 'Win32_ComputerSystem') { return $global:TW.Cs }
    if ("$args" -match 'Win32_PageFileSetting') { return $global:TW.PageFiles }; CimCmdlets\Get-CimInstance @args }
function Set-CimInstance { param($InputObject, $Property) if ($Property.ContainsKey('AutomaticManagedPagefile')) { $global:TW.Cs.AutomaticManagedPagefile = $Property.AutomaticManagedPagefile; $global:TWlog.Add('pagefile auto'); return }; ($global:TW.Power | Where-Object I -eq $InputObject.InstanceName).E = $Property.Enable; $global:TWlog.Add("power off $($InputObject.InstanceName)") }
function Get-NetAdapter { param([switch]$Physical) [pscustomobject]@{ Name = 'Ethernet'; MediaType = '802.3'; PnPDeviceID = 'PCI\VEN_10EC&DEV_8125\X' } }
function Get-NetAdapterAdvancedProperty { param($Name, $DisplayName) if ($global:TW.Nic.ContainsKey($DisplayName)) { [pscustomobject]@{ DisplayName = $DisplayName; DisplayValue = $global:TW.Nic[$DisplayName]; ValidDisplayValues = @('Disabled', 'Enabled') } } }
function Set-NetAdapterAdvancedProperty { param($Name, $DisplayName, $DisplayValue, [switch]$NoRestart) $global:TW.Nic[$DisplayName] = $DisplayValue; $global:TWlog.Add("nic $DisplayName=$DisplayValue") }
$env:PCKIT_TWEAK_OPTIONS = "$Work\kit-options.txt"   # the owner's choices: this test's own file, never the real one
function winget { $global:TWlog.Add("winget $args") }
function Get-Partition { [pscustomobject]@{ DiskNumber = 0 } }
function Get-PnpDevice { param([switch]$PresentOnly, $Class) @($global:TW.Pnp) | Where-Object { $_ } }   # (none by default: the hardware rule is skipped)
function Get-PhysicalDisk { [pscustomobject]@{ DeviceId = '0'; MediaType = $(if ($global:TW.Hdd) { 'HDD' } else { 'SSD' }) } }
function Get-Printer { $global:TW.Printers }
function powercfg {
    $a = "$args"; if ($a -notmatch '^/(getactivescheme|list|q) ' -and $a -notmatch '^/(getactivescheme|list)$') { $global:TWlog.Add("powercfg $a") }
    switch -Regex ($a) {
        '^/getactivescheme' { "Power Scheme GUID: $($TW.Plan)  (active)" }
        '^/list' { $TW.Plans | ForEach-Object { "Power Scheme GUID: $_  (plan)" } }
        '^/duplicatescheme \S+ (\S+)' { $TW.Plans += $Matches[1] }
        '^/setactive (\S+)' { if ($Matches[1] -ne 'SCHEME_CURRENT') { $TW.Plan = $Matches[1] } }
        '^/q SCHEME_CURRENT (\S+) (\S+)' { $v = $TW.Ac["$($Matches[1])|$($Matches[2])"]; if ($null -eq $v) { $v = 1 }; ("    Current AC Power Setting Index: 0x{0:x8}" -f $v), '    Current DC Power Setting Index: 0x00000001' }
        '^/setacvalueindex SCHEME_CURRENT (\S+) (\S+) (\d+)' { $TW.Ac["$($Matches[1])|$($Matches[2])"] = [int]$Matches[3] }
        '^/hibernate off' { $TW.Reg['HKLM:\SYSTEM\CurrentControlSet\Control\Power|HibernateEnabled'] = 0 }
    }
}
function Get-Process { param($Name) }
function Stop-Process { $global:TWlog.Add('stop-process') }
function Start-Process { param($FilePath, $ArgumentList, [switch]$Wait, $WindowStyle) $global:TWlog.Add("run $(Split-Path $FilePath -Leaf) $ArgumentList"); $TW.OneDrive = $false
    if ($FilePath -match 'Installer\\setup\.exe$' -and $TW.EdgeGoes) { [IO.File]::Delete("$env:PCKIT_EDGE_ROOT\msedge.exe") } }   # (Edge's uninstaller)
function Remove-ItemProperty { param($Path, $Name) if ($Name -and $global:TW.Reg.ContainsKey("$Path|$Name")) { $global:TW.Reg.Remove("$Path|$Name") }; $global:TWlog.Add("remove $Path $Name") }
function Get-Item { if ("$args" -match '^HKCU:.+CurrentVersion\\Run$') { return [pscustomobject]@{ Property = $global:TW.Run } }; if ("$args" -match '^HK.+CurrentVersion\\Run$') { return $null }; Microsoft.PowerShell.Management\Get-Item @args }
function Get-WindowsCapability { param([switch]$Online, $Name) $global:TW.Caps.Keys | Where-Object { -not $Name -or $_ -eq $Name } | ForEach-Object { [pscustomobject]@{ Name = $_; State = $global:TW.Caps[$_] } } }
function Remove-WindowsCapability { param([switch]$Online, $Name) if ($global:TW.CapBusy-- -gt 0) { $global:TWlog.Add("cap refused $Name"); return }; if (-not $global:TW.CapStuck) { $global:TW.Caps[$Name] = 'NotPresent' }; $global:TWlog.Add("cap removed $Name") }
function Add-WindowsCapability { param([switch]$Online, $Name) $global:TW.Caps[$Name] = 'Installed'; $global:TWlog.Add("cap added $Name") }
function Get-WindowsOptionalFeature { param([switch]$Online) $global:TW.Feats.Keys | ForEach-Object { [pscustomobject]@{ FeatureName = $_; State = $global:TW.Feats[$_] } } }
function Disable-WindowsOptionalFeature { param([switch]$Online, $FeatureName, [switch]$NoRestart) $global:TW.Feats[$FeatureName] = 'Disabled'; $global:TWlog.Add("feature off $FeatureName") }
function Enable-WindowsOptionalFeature { param([switch]$Online, $FeatureName, [switch]$NoRestart) $global:TW.Feats[$FeatureName] = 'Enabled'; $global:TWlog.Add("feature on $FeatureName") }
function Start-Sleep { param($Seconds, $Milliseconds) if ($Seconds) { $global:TWlog.Add("sleep $Seconds") } }   # (the test helpers' own short waits: not logged)
function Get-WindowsReservedStorageState { [pscustomobject]@{ ReservedStorageState = $global:TW.Reserved } }
function Set-WindowsReservedStorageState { param($State) $global:TW.Reserved = $State; $global:TWlog.Add("reserved $State") }
if (-not (Assert-Mocks $mocked)) { Finish }
function Run { @(& "$Work\tweaks.ps1") }

Section 'a fresh Windows: every tweak applied once'
Fresh; $o = Run
$regSets = @($TWlog -match '^reg ').Count; $setRegCalls = @($TW.Reg.Keys | Where-Object { $_ -notmatch 'HibernateEnabled' }).Count   # distinct settings (some Set-Reg lines are loops)
Check "all $setRegCalls settings written, each exactly once" ($regSets -eq $setRegCalls -and $setRegCalls -ge 50) "writes: $regSets, distinct: $setRegCalls"
Check 'each change is reported (one line per kind)' (($o -match '^setting ').Count -ge 1 -and ($o -contains 'service DiagTrack off') -and ($o -contains 'task Microsoft Compatibility Appraiser off')) ($o -join ' / ')
Check 'telemetry, Copilot, Recall/Click to Do, ads and Bing search turned off' ($TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection|AllowTelemetry'] -eq 0 -and $TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot|TurnOffWindowsCopilot'] -eq 1 -and $TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI|DisableClickToDo'] -eq 1 -and $TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search|DisableWebSearch'] -eq 1) ''
Check 'crash reports stay possible (WER kept on, only extra data off)' (-not ($TW.Reg.Keys | Where-Object { $_ -match 'Windows Error Reporting\|Disabled$' })) ''
Check 'telemetry/unneeded services disabled; SysMain left as Windows has it (turning it off is opt-in)' (($TW.Services['DiagTrack'] -eq 'Disabled') -and ($TW.Services['SysMain'] -eq 'Automatic')) ''
Check 'no printer: the print spooler set to manual (not disabled)' ($TW.Services['Spooler'] -eq 'Manual') $TW.Services['Spooler']
Check 'listed telemetry tasks disabled; the owner''s own and Windows'' defrag/TRIM task untouched' (($TW.Tasks | Where-Object N -eq 'Microsoft Compatibility Appraiser').S -eq 'Disabled' -and ($TW.Tasks | Where-Object N -eq 'ScheduledDefrag').S -eq 'Ready' -and ($TW.Tasks | Where-Object N -eq 'MyOwnTask').S -eq 'Ready') ''
Check 'motherboard "app shop" auto-installer task removed' (-not ($TW.Tasks | Where-Object N -eq 'AsrAPPShopUpdate')) ''
Check 'bloat apps removed, also for new users (provisioned)' (($TW.Apps.Count -eq 0) -and ($TW.Prov.Count -eq 0)) "left: $($TW.Apps -join ', ')"
Check 'Xbox controller and Ethernet power-saving off; the mouse untouched' (-not ($TW.Power | Where-Object { $_.E -and $_.I -notmatch 'VID_046D' })) ''
Check 'Ethernet energy saving off, other adapter settings untouched' ($TW.Nic['Energy-Efficient Ethernet'] -eq 'Disabled' -and $TW.Nic['Green Ethernet'] -eq 'Disabled' -and $TW.Nic['Jumbo Packet'] -eq 'Disabled' -and -not ($TWlog -match 'Jumbo')) ''
$b = Get-Content $bk -Raw | ConvertFrom-Json
Check 'originals recorded for the uninstaller: settings, services, tasks, apps, adapters, power' ((@($b.PSObject.Properties.Name -match '^reg\|').Count -eq $setRegCalls) -and $b.'service|DiagTrack'.StartType -eq 'Automatic' -and $b.'task|\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'.Enabled -and $b.'app|MSTeams' -and $b.'nic|Ethernet|Green Ethernet'.DisplayValue -eq 'Enabled' -and $b.'power|USB\VID_045E&PID_0B00\1_0'.Enable) ''

Section 'already tweaked: nothing to do (the tweak guard at every login)'
$TWlog.Clear(); $t0 = (Get-Item $bk).LastWriteTime; Start-Sleep -Milliseconds 50
$o = Run
Check 'no output, no changes' (($o.Count -eq 0) -and ($TWlog.Count -eq 0)) (($o + $TWlog) -join ' / ')
Check 'backup file not rewritten' ((Get-Item $bk).LastWriteTime -eq $t0) ''

Section 'Windows reverted a few things after an update'
$TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection|AllowTelemetry'] = 3; $TW.Services['DiagTrack'] = 'Automatic'; $TW.Apps = @('Microsoft.Copilot'); $TW.Prov = @('Microsoft.Copilot')   # (a feature update brings an app back for new users too)
$TWlog.Clear(); $o = Run
Check 'only the reverted ones are re-applied and reported' (($TWlog.Count -eq 5) -and ($o -contains 'setting AllowTelemetry') -and ($o -contains 'service DiagTrack off') -and ($o -contains 'app Microsoft.Copilot removed')) (($o + '|' + $TWlog) -join ' / ')
Check '... and the recorded original stays the FIRST one (not the reverted value)' ((Get-Content $bk -Raw | ConvertFrom-Json).'reg|HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection|AllowTelemetry'.Existed -eq $false) ''

Section 'special cases'
Fresh; $TW.Printers = @([pscustomobject]@{ Name = 'HP LaserJet'; PortName = 'USB001' }); Clear-Path $bk; [void](Run)
Check 'a real printer: the print spooler stays automatic' ($TW.Services['Spooler'] -eq 'Automatic') $TW.Services['Spooler']
Fresh; $TW.Printers = @([pscustomobject]@{ Name = 'Microsoft Print to PDF'; PortName = 'PORTPROMPT:' }); Clear-Path $bk; [void](Run)
Check 'only "Print to PDF": counts as no printer' ($TW.Services['Spooler'] -eq 'Manual') ''
Fresh; $TW.Services.Remove('WSAIFabricSvc'); $TW.Services.Remove('RetailDemo'); Clear-Path $bk; $e = @(& "$Work\tweaks.ps1" 2>&1 | Where-Object { $_ -is [Management.Automation.ErrorRecord] })
Check 'services missing on this Windows version: skipped without errors' ($e.Count -eq 0) "$e"
$sa = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
Fresh; $TW.Run = @('AdobeGCInvoker-1.0', 'Steam', 'Discord', 'SteelSeriesGG', 'CCleaner Smart Cleaning', 'MSI LiveUpdate'); Clear-Path $bk; $o = Run
$off = @($TW.Reg.Keys | Where-Object { $_ -like "$sa|*" } | ForEach-Object { ($_ -split '\|')[1] } | Sort-Object)
Check 'start-up clutter (vendor updaters, promo tools) turned off the Task Manager way' (($off -join ',') -eq 'AdobeGCInvoker-1.0,CCleaner Smart Cleaning,MSI LiveUpdate' -and $TW.Reg["$sa|MSI LiveUpdate"][0] -eq 3) ($off -join ', ')
Check '... Steam, Discord, SteelSeries GG left alone' (-not ($off -match 'Steam|Discord|SteelSeries')) ''
Check '... recorded so the uninstaller turns them back on' ((Get-Content $bk -Raw | ConvertFrom-Json).PSObject.Properties.Name -contains "startup|$sa|MSI LiveUpdate") ''
$TWlog.Clear(); $o = Run
Check '... already off: nothing done again' (-not ($TWlog -match 'reg ')) ($TWlog -join ' / ')
$dxk = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences|DirectXUserGlobalSettings'
Fresh; Clear-Path $bk; [void](Run)
Check 'windowed-games optimization and variable refresh rate on' ($TW.Reg[$dxk] -eq 'SwapEffectUpgradeEnable=1;VRROptimizeEnable=1;') "$($TW.Reg[$dxk])"
Check 'Windows Update: no restart while signed in, active hours 8:00-2:00' ($TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU|NoAutoRebootWithLoggedOnUsers'] -eq 1 -and $TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate|ActiveHoursStart'] -eq 8 -and $TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate|ActiveHoursEnd'] -eq 2) ''
Check 'a single-CCD CPU: the Xbox Game Bar removed like the other bloat' ('Microsoft.XboxGamingOverlay' -notin $TW.Apps) ''
Fresh; $TW.Reg[$dxk] = 'AutoHDREnable=1;SwapEffectUpgradeEnable=0;'; Clear-Path $bk; [void](Run)
Check "... the owner's other DirectX settings kept (Auto HDR), ours set" ($TW.Reg[$dxk] -eq 'AutoHDREnable=1;SwapEffectUpgradeEnable=1;VRROptimizeEnable=1;') "$($TW.Reg[$dxk])"
Fresh; $TW.Cpu = 'AMD Ryzen 9 9950X3D 16-Core Processor'; Clear-Path $bk; [void](Run)
Check 'a dual-CCD X3D CPU (9950X3D): the Xbox Game Bar kept (AMD needs it to put games on the V-Cache cores)' ('Microsoft.XboxGamingOverlay' -in $TW.Apps -and 'Microsoft.Copilot' -notin $TW.Apps) ($TW.Apps -join ', ')
Fresh; $TW.Cs.AutomaticManagedPagefile = $false; Clear-Path $bk; $o = Run
Check 'no page file at all (a "debloat" guide): Windows manages it again' ($TW.Cs.AutomaticManagedPagefile -and ($o -match 'page file managed by Windows')) ($o -join ' / ')
Fresh; $TW.Cs.AutomaticManagedPagefile = $false; $TW.PageFiles = @([pscustomobject]@{ Name = 'C:\pagefile.sys'; InitialSize = 16384 }); Clear-Path $bk; [void](Run)
Check "... a page file size the owner chose: kept" (-not $TW.Cs.AutomaticManagedPagefile) ''
Section 'power plan and OneDrive (guarded: driver installers and feature updates switch them back)'
$usb = '2a737441-1930-4402-8d77-b2bebba308a3|48e6b7a6-50f5-4782-a5d4-53bb8f07e226'; $ult = '99999999-9999-9999-9999-999999999999'
Fresh; Clear-Path $bk; $o = Run
Check 'a desktop: Ultimate Performance (made under its fixed id, found in any Windows language), active' ($TW.Plans -contains $ult -and $TW.Plan -eq $ult -and ($o -contains 'power plan Ultimate Performance')) ($o -join ' / ')
Check '... no USB sleep, no hibernation' ($TW.Ac[$usb] -eq 0 -and $TW.Reg['HKLM:\SYSTEM\CurrentControlSet\Control\Power|HibernateEnabled'] -eq 0) ''
Check '... the plan it had is recorded (the uninstaller puts it back)' ((Get-Content $bk -Raw | ConvertFrom-Json).'plan|active'.Guid -eq '381b4222-f694-41f0-9685-ff5bb260df2e') ''
$TWlog.Clear(); [void](Run)
Check '... already right: no powercfg changes at all' (-not ($TWlog -match '^powercfg')) ($TWlog -join ' / ')
$TW.Plan = '381b4222-f694-41f0-9685-ff5bb260df2e'; $TW.Reg['HKLM:\SYSTEM\CurrentControlSet\Control\Power|HibernateEnabled'] = 1; $TWlog.Clear(); $o = Run
Check 'a driver install switched to Balanced and back on hibernation: both put back, said' ($TW.Plan -eq $ult -and ($o -contains 'power plan Ultimate Performance') -and ($o -contains 'hibernation off') -and @($TWlog -match 'duplicatescheme').Count -eq 0) ($o -join ' / ')
Fresh; $TW.Battery = [pscustomobject]@{ Name = 'Battery' }; $TW.Plan = $ult; Clear-Path $bk; $o = Run
Check 'a laptop: Balanced (not Ultimate - the battery), full speed and no USB sleep when plugged in, hibernation kept' ($TW.Plan -eq '381b4222-f694-41f0-9685-ff5bb260df2e' -and $TW.Ac['54533251-82be-4824-96c1-47b60b740d00|893dee8e-2bef-41e0-89c6-b55d0929964c'] -eq 100 -and $TW.Ac[$usb] -eq 0 -and $TW.Reg['HKLM:\SYSTEM\CurrentControlSet\Control\Power|HibernateEnabled'] -eq 1 -and -not ($TWlog -match 'setdcvalueindex')) ($o -join ' / ')
Check '... "Best performance" power mode when plugged in' ($TW.Reg['HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes|ActiveOverlayAcPowerScheme'] -eq 'ded574b5-45a0-4f42-8737-46345c09c238') ''
Fresh; $TW.OneDrive = $true; Clear-Path $bk; $o = Run
Check 'OneDrive back after a feature update: uninstalled again, its start-up entry removed' (($o -contains 'OneDrive removed') -and ($TWlog -match '^run OneDriveSetup\.exe /uninstall') -and ($TWlog -match '^remove .*OneDrive')) (($o + $TWlog) -join ' / ')
Section "the owner's choices (the app: What the kit changes)"
$opt = "$Work\kit-options.txt"; $vbs = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard|EnableVirtualizationBasedSecurity'
Fresh; [IO.File]::Delete($opt); Clear-Path $bk; $TW.Reg[$vbs] = 1; [void](Run)
Check 'by default: memory integrity off like everything else' ($TW.Reg[$vbs] -eq 0) ''
'tweak.memory-integrity=off' | Set-Content $opt; $o = Run
Check 'memory integrity turned back on by the owner: the original value restored, said' ($TW.Reg[$vbs] -eq 1 -and ($o -contains 'setting EnableVirtualizationBasedSecurity back (your choice)')) ($o -join ' / ')
$TWlog.Clear(); $o = Run
Check '... and it stays that way at every guard run (nothing done again)' (-not ($TWlog -match 'EnableVirtualizationBasedSecurity') -and -not $o) ($o -join ' / ')
Check '... everything else still applied' ($TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection|AllowTelemetry'] -eq 0) ''
[IO.File]::Delete($opt); $o = Run
Check 'turned on again: applied again' ($TW.Reg[$vbs] -eq 0 -and ($o -contains 'setting EnableVirtualizationBasedSecurity')) ($o -join ' / ')
Fresh; Clear-Path $bk; $TW.Apps += 'Microsoft.XboxGamingOverlay'; [void](Run)
'tweak.game-bar=off' | Set-Content $opt; $o = Run
Check 'Xbox Game Bar wanted after the kit removed it: reinstalled from the Store once' (($o -contains 'Xbox Game Bar reinstalled (your choice)') -and @($TWlog -match '^winget install --id 9NZKPSTSNW4P').Count -eq 1) ($o -join ' / ')
$TWlog.Clear(); [void](Run)
Check '... once (not at every run)' (-not ($TWlog -match '^winget')) ($TWlog -join ' / ')
Fresh; Clear-Path $bk; 'tweak.bloat-apps=off' | Set-Content $opt; [void](Run)
Check 'keep the preinstalled apps: none removed' ($TW.Apps -contains 'Microsoft.BingNews' -and $TW.Apps -contains 'MSTeams') ($TW.Apps -join ', ')
Fresh; Clear-Path $bk; [IO.File]::Delete($opt); [void](Run); $TW.Plan | Out-Null
'tweak.power-plan=off' | Set-Content $opt; $o = Run
Check 'their own power plan: the one from before the kit, once' ($TW.Plan -eq '381b4222-f694-41f0-9685-ff5bb260df2e' -and ($o -contains 'power plan back to the one from before (your choice)')) ($o -join ' / ')
$TW.Plan = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'; $TWlog.Clear(); [void](Run)
Check '... a plan they pick later is left alone' ($TW.Plan -eq '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' -and -not ($TWlog -match 'setactive')) ($TWlog -join ' / ')
'tweak.hibernation=off' | Set-Content $opt; $o = Run
Check 'hibernation wanted on a desktop: turned back on once' ([bool]($TWlog -match '^powercfg /hibernate on$') -and ($o -contains 'hibernation back on (your choice)')) ($o -join ' / ')
Fresh; Clear-Path $bk; [IO.File]::Delete($opt); $TW.OneDrive = $true; [void](Run)
'tweak.onedrive=off' | Set-Content $opt; $o = Run
Check 'OneDrive wanted after the kit removed it: reinstalled once, its sync allowed again' (($o -contains 'OneDrive reinstalled (your choice)') -and ($TWlog -match '^winget install --id Microsoft\.OneDrive') -and -not $TW.Reg.ContainsKey('HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive|DisableFileSyncNGSC')) ($o -join ' / ')
[IO.File]::Delete($opt)
Section 'more devices and keyboard prompts'
Fresh; $TW.Power += @{ I = 'USB\VID_054C&PID_0CE6\DS_0'; E = $true }; Clear-Path $bk; [void](Run)
Check 'a PlayStation controller: power-saving off too (not only Xbox)' (-not ($TW.Power | Where-Object { $_.I -match 'VID_054C' -and $_.E })) ''
Check 'the Sticky Keys / Filter Keys / Toggle Keys shortcut prompts off' ($TW.Reg['HKCU:\Control Panel\Accessibility\StickyKeys|Flags'] -eq '506' -and $TW.Reg['HKCU:\Control Panel\Accessibility\Keyboard Response|Flags'] -eq '122' -and $TW.Reg['HKCU:\Control Panel\Accessibility\ToggleKeys|Flags'] -eq '58') ''
'tweak.sysmain-off=on' | Set-Content $opt; Fresh; Clear-Path $bk; [void](Run)
Check 'Windows on an SSD, SysMain off chosen (opt-in): off' ($TW.Services['SysMain'] -eq 'Disabled') ''
'' | Set-Content $opt; $TWlog.Clear(); $o = Run
Check '... and chosen again: back as it was, started' (($TW.Services['SysMain'] -eq 'Automatic') -and ($TWlog -contains 'start SysMain') -and ($o -contains 'service SysMain back to Automatic (your choice)')) (($o + $TWlog) -join ' / ')
'tweak.sysmain-off=on' | Set-Content $opt
Fresh; $TW.Hdd = $true; Clear-Path $bk; [void](Run)
Check 'Windows on a hard drive: SysMain kept (prefetch is what makes apps start quicker there)' ($TW.Services['SysMain'] -eq 'Automatic') $TW.Services['SysMain']

Section 'old Windows parts (what tiny11 removes too - never what updates and repairs need)'
Fresh; Clear-Path $bk; '' | Set-Content $opt; $o = @(& "$Work\tweaks.ps1" -Quick)
Check 'setup''s first run (-Quick): the slow DISM part waits for the first maintenance' (-not ($TWlog -match '^cap |^feature |^reserved ')) ($TWlog -join ', ')
$o = Run
Check 'the Internet Explorer engine and the legacy Media Player removed; VBScript (old installers use it) and Notepad kept' (($o -contains 'old Windows part Browser.InternetExplorer removed') -and ($o -contains 'old Windows part Media.WindowsMediaPlayer removed') -and
    $TW.Caps['VBSCRIPT~~~~'] -eq 'Installed' -and $TW.Caps['Microsoft.Windows.Notepad.System~~~~0.0.1.0'] -eq 'Installed') ($o -join ' / ')
Check 'PowerShell 2.0 off; media playback (games play videos with it) left on' ($TW.Feats['MicrosoftWindowsPowerShellV2Root'] -eq 'Disabled' -and $TW.Feats['MediaPlayback'] -eq 'Enabled') ''
Check 'reserved storage off (about 7 GB), said' ($TW.Reserved -eq 'Disabled' -and ($o -contains 'reserved storage off (about 7 GB free again)')) ($o -join ' / ')
$TWlog.Clear(); $o = Run
Check '... after that it isn''t even looked at again on the same Windows build (DISM takes seconds every time)' (-not ($TWlog -match '^cap |^feature |^reserved ') -and -not ($o -match 'old Windows|reserved')) ($TWlog -join ', ')
Fresh; Clear-Path $bk; $TW.CapBusy = 3; $o = Run
Check 'Windows'' servicing lock held a while (DISM''s cleanup alongside): waited for, and removed in the same run' (($o -contains 'old Windows part Browser.InternetExplorer removed') -and @($TWlog -match '^sleep 30').Count -eq 3) ($TWlog -join ', ')
Fresh; Clear-Path $bk; $TW.CapStuck = $true; [void](Run); $TWlog.Clear(); $TW.CapStuck = $false; $o = Run
Check 'a removal Windows refused (an update being installed) is tried again at the next check' ($o -contains 'old Windows part Browser.InternetExplorer removed') ($o -join ' / ')
'tweak.legacy=off' | Set-Content $opt; $o = Run
Check 'switched off in Settings: each part the kit removed comes back, and reserved storage' (($o -contains 'old Windows parts back (your choice)') -and $TW.Caps['Browser.InternetExplorer~~~~0.0.11.0'] -eq 'Installed' -and
    $TW.Feats['MicrosoftWindowsPowerShellV2Root'] -eq 'Enabled' -and $TW.Reserved -eq 'Enabled') ($o -join ' / ')
'' | Set-Content $opt; $TWlog.Clear(); $o = Run
Check '... and switched on again: removed again (checked afresh)' ($o -contains 'old Windows part Browser.InternetExplorer removed') ($o -join ' / ')
Section 'the install USB''s Start pins: the policy goes once Start has them'
$sp = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start'
Fresh; Clear-Path $bk; '' | Set-Content $opt; $TW.Reg["$sp|PCKit"] = 1; $TW.Reg["$sp|ConfigureStartPins"] = '{"pinnedList":[]}'; $o = @(& "$Work\tweaks.ps1" -Quick)
Check 'not during setup (Start may still be starting)' ($TW.Reg.ContainsKey("$sp|ConfigureStartPins")) ''
$o = Run
Check 'the first maintenance takes the kit''s policy away (the pins stay, the owner''s to change)' (-not $TW.Reg.ContainsKey("$sp|ConfigureStartPins") -and -not $TW.Reg.ContainsKey("$sp|PCKit") -and ($o -contains 'Start pins from the install USB kept - yours to change now')) ($o -join ' / ')
Fresh; Clear-Path $bk; $TW.Reg["$sp|ConfigureStartPins"] = '{"pinnedList":[]}'; $o = Run
Check '... a Start-pins policy that isn''t the kit''s (a company''s) stays' ($TW.Reg.ContainsKey("$sp|ConfigureStartPins")) ''
Section 'where it is, for setup''s time limit'
Fresh; Clear-Path $bk; $env:PCKIT_TWEAKS_TRACE = "$Work\trace.txt"; Clear-Path $env:PCKIT_TWEAKS_TRACE; [void](Run); $tr = @(Get-Content $env:PCKIT_TWEAKS_TRACE -ErrorAction SilentlyContinue); $env:PCKIT_TWEAKS_TRACE = $null
Check 'each section is noted as it starts (a hang names itself), the end too' (($tr -match ' Services$') -and ($tr -match ' Preinstalled apps$') -and ($tr[-1] -match ' done$')) ($tr -join ' / ')

Section 'OneDrive''s installer in Windows'' service accounts (the 10/2 audit)'
Fresh; Clear-Path $bk; '' | Set-Content $opt; $TW.Reg['Registry::HKEY_USERS\S-1-5-19\Software\Microsoft\Windows\CurrentVersion\Run|OneDriveSetup'] = 'C:\Windows\System32\OneDriveSetup.exe /thfirstsetup'; $o = Run
Check 'its first-sign-in entry is removed there, said' (-not $TW.Reg.ContainsKey('Registry::HKEY_USERS\S-1-5-19\Software\Microsoft\Windows\CurrentVersion\Run|OneDriveSetup') -and ($o -contains 'OneDrive setup entry removed (S-1-5-19)')) ($o -join ' / ')
$TW.Reg['Registry::HKEY_USERS\S-1-5-19\Software\Microsoft\Windows\CurrentVersion\Run|OneDriveSetup'] = 'x'; 'tweak.onedrive=off' | Set-Content $opt; [void](Run)
Check '... not when the owner keeps OneDrive' ($TW.Reg.ContainsKey('Registry::HKEY_USERS\S-1-5-19\Software\Microsoft\Windows\CurrentVersion\Run|OneDriveSetup')) ''
'' | Set-Content $opt
Fresh; Clear-Path $bk; $TW.Tasks += @{ P = '\Microsoft\Windows\Sustainability\'; N = 'SustainabilityTelemetry'; S = 'Ready' }, @{ P = '\GoogleUserPEH\'; N = 'RunPlatformExperienceHelper_Daily'; S = 'Ready' }, @{ P = '\GoogleSystem\GoogleUpdater\'; N = 'GoogleUpdaterTaskSystem'; S = 'Ready' }; $o = Run
Check 'the telemetry tasks the audit found are off, and Chrome''s "tips" helper - Chrome''s own updater stays' (($o -contains 'task SustainabilityTelemetry off') -and ($o -contains 'task RunPlatformExperienceHelper_Daily off') -and -not ($o -match 'GoogleUpdaterTaskSystem')) ($o -join ' / ')
Fresh; Clear-Path $bk; $TW.Tasks += @{ P = '\Microsoft\Windows\WindowsAI\ClickToDo\'; N = 'ModelCachingLimit'; S = 'Ready'; D = $true }; $o = Run
Check 'a task Windows won''t let admins change (Access is denied) is not reported "off" (10/2: "reverted" at every run)' (-not ($o -match 'ModelCachingLimit') -and ($o -contains 'task DmClient off')) ($o -join ' / ')
Section 'a run stopped halfway (setup''s 20-minute limit) keeps what it changed'
$tt = Get-Content "$Kit\tweaks.ps1" -Raw
Check 'the originals are saved at every section, not only at the end (10/2: a stopped run on GitHub had saved none)' ($tt -match 'function Trace\(\[string\]\$Where\) \{ Save-Backup;' -and @([regex]::Matches($tt, '(?m)^Trace ''')).Count -ge 10) ''
Check '... and the taskbar unpin (the shell can wait forever) runs in its own process, 30 seconds at most' ($tt -match 'taskbarunpin' -and $tt -match 'WaitForExit\(30000\)') ''
Fresh; Clear-Path $bk; $env:PCKIT_TWEAKS_TRACE = "$Work\trace2.txt"; [void](Run); $env:PCKIT_TWEAKS_TRACE = $null
Check '... the originals file is complete after a normal run all the same' ((Test-Path $bk) -and (Get-Content $bk -Raw) -match 'DiagTrack') ''

Section 'the preview (-Audit): lists what would change, changes nothing'
# every command tweaks.ps1 uses either only reads, or is on -Audit's list of stand-ins - so a new kind of change can't
# slip past the preview (the same idea as the tripwire above)
$tast = [Management.Automation.Language.Parser]::ParseFile("$Kit\tweaks.ps1", [ref]$null, [ref]$null)
$wc = @($tast.Find({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and "$($n.Left)" -eq '$writeCmds' }, $true).Right.Expression.SafeGetValue())
$ownFn = @($tast.FindAll({ $args[0] -is [Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object Name)
$usedCmds = @($tast.FindAll({ $args[0] -is [Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique)
$readOnly = '^(Get-|Test-|Select-|Where-|ForEach-|Sort-|Measure-|Group-|ConvertFrom-|ConvertTo-|Join-Path|Split-Path|Out-Null|Out-String|New-Object|Write-Host|Add-Type|Start-Sleep|powercfg$)'
$setItems = @($tast.FindAll({ $args[0] -is [Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -eq 'Set-Item' }, $true))
Check '... Set-Item is only used for the stand-ins themselves (the function: drive)' ($setItems.Count -ge 1 -and -not ($setItems | Where-Object { "$_" -notmatch 'function:script:' })) ''
$uncovered = @($usedCmds | Where-Object { $_ -notmatch $readOnly -and $_ -notin $wc -and $_ -notin $ownFn -and $_ -ne 'Set-Item' })
Check 'every changing command in tweaks.ps1 has a preview stand-in' ($wc.Count -ge 20 -and -not $uncovered) "not covered: $($uncovered -join ', ')"
'' | Set-Content $opt; Fresh; Clear-Path $bk; $before = @($TW.Reg.Keys).Count
$o = @(& "$Work\tweaks.ps1" -Audit)
Check 'a fresh Windows: lists what would change, with the current and new value' (($o -match "^Would: setting AllowTelemetry \(HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DataCollection\): '\(not set\)' -> '0'") -and ($o -match '^Would: app Microsoft\.Copilot removed') -and ($o -match '^Would: service DiagTrack off')) ($o -join ' / ')
Check '... and changes nothing: no setting, service, app or file' ((@($TW.Reg.Keys).Count -eq $before) -and ($TW.Services['DiagTrack'] -eq 'Automatic') -and ('Microsoft.Copilot' -in $TW.Apps) -and -not (Test-Path $bk) -and -not ($TWlog -match '^(reg|service|app|task)')) (($TWlog | Select-Object -First 5) -join ' / ')
Check '... and says so in its last line' ($o[-1] -match '^Preview: \d+ change\(s\) would be made; \d+ setting\(s\) already as Messiah keeps them - nothing was changed$') $o[-1]
[void](Run); $o = @(& "$Work\tweaks.ps1" -Audit)
Check 'after a real run: nothing left to change, everything counted as in place' ($o[-1] -match '^Preview: 0 change\(s\) would be made; (\d+) setting' -and [int]$Matches[1] -ge 50) ($o -join ' / ')
Section 'from the research comparison (10/10): blocked writes, reinstalled apps, mid-update, X3D, notifications, history'
'' | Set-Content $opt
$dsh = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh|AllowNewsAndInterests'
Fresh; Clear-Path $bk; $TW.Blocked = @($dsh); $o = Run
Check 'a value Windows refuses (its protection driver): said once as blocked - not as applied' (($o -contains 'setting AllowNewsAndInterests blocked by Windows (left as it is)') -and ($o -notcontains 'setting AllowNewsAndInterests')) ($o -join ' / ')
$TWlog.Clear(); $o = Run
Check '... not tried or reported again on the same Windows build' (-not ($o -match 'AllowNewsAndInterests') -and -not ($TWlog -match 'AllowNewsAndInterests')) (($o + $TWlog) -join ' / ')
$TW.Blocked = @(); $TWlog.Clear(); $o = Run
Check '... (a new build would try again: the block is remembered per build)' ((Get-Content $bk -Raw | ConvertFrom-Json).("blocked|$dsh").Build -eq "$([Environment]::OSVersion.Version.Build)") ''
Fresh; Clear-Path $bk; [void](Run)
$TW.Apps += 'Microsoft.Copilot'; $TWlog.Clear(); $o = Run
Check 'an app the owner reinstalled (back for them, not for new users): kept, said once' (('Microsoft.Copilot' -in $TW.Apps) -and ($o -contains 'app Microsoft.Copilot kept (you reinstalled it)') -and -not ($TWlog -match 'app removed')) (($o + $TWlog) -join ' / ')
$o = Run
Check '... and left alone from then on' (('Microsoft.Copilot' -in $TW.Apps) -and -not ($o -match 'Copilot')) ($o -join ' / ')
$TW.Apps += 'Microsoft.BingNews'; $TW.Prov += 'Microsoft.BingNews'; $o = Run
Check '... while one Windows put back (for new users too) goes again' (('Microsoft.BingNews' -notin $TW.Apps) -and ($o -contains 'app Microsoft.BingNews removed')) ($o -join ' / ')
Fresh; Clear-Path $bk; $TW.Pending = $true; $o = Run
Check 'a restart pending (an update mid-install): no app or Windows part removed' (('Microsoft.Copilot' -in $TW.Apps) -and -not ($o -match 'app .* removed|old Windows part')) ($o -join ' / ')
$TW.Pending = $false; $o = Run
Check '... after the restart: removed' (('Microsoft.Copilot' -notin $TW.Apps) -and ($o -contains 'app Microsoft.Copilot removed')) ($o -join ' / ')
Fresh; $TW.Cpu = 'AMD Ryzen 9 9950X3D 16-Core Processor'; $TW.Plan = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'; Clear-Path $bk; $o = Run
Check 'a dual-CCD X3D desktop: Balanced, as AMD recommends (its driver parks the second CCD) - not Ultimate' (($TW.Plan -eq '381b4222-f694-41f0-9685-ff5bb260df2e') -and ($o -contains 'power plan Balanced (AMD''s choice for this X3D CPU)') -and -not ($TWlog -match 'duplicatescheme')) ($o -join ' / ')
Fresh; Clear-Path $bk; [void](Run)
$nt = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications|ToastEnabled'
Check 'apps'' notifications left on by default; only Windows'' own "suggested" ones off' ((-not $TW.Reg.ContainsKey($nt)) -and $TW.Reg['HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested|Enabled'] -eq 0) ''
'tweak.notifications-off=on' | Set-Content $opt; [void](Run)
Check '... all of them off when the owner chooses it (opt-in)' ($TW.Reg[$nt] -eq 0) ''
'' | Set-Content $opt; [void](Run)
Check '... and back on when they change their mind' (-not $TW.Reg.ContainsKey($nt)) ''
Check 'the AI parts of Notepad and Paint, and Edge''s AI and ads, off' ($TW.Reg['HKLM:\SOFTWARE\Policies\WindowsNotepad|DisableAIFeatures'] -eq 1 -and $TW.Reg['HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint|DisableCocreator'] -eq 1 -and $TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Edge|CopilotPageContext'] -eq 0 -and $TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Edge|ShowAcrobatSubscriptionButton'] -eq 0) ''
# a PC set up before the originals were kept (no original recorded): Windows' default, once - a later "off" by hand stays
'' | Set-Content $opt; Fresh; Clear-Path $bk; $TW.Services['SysMain'] = 'Disabled'; $TW.Reg[$nt] = 0; $o = Run
Check 'set up before originals were kept: SysMain and app notifications back to Windows'' default, said' (($TW.Services['SysMain'] -eq 'Automatic') -and -not $TW.Reg.ContainsKey($nt) -and ($o -contains 'service SysMain back to Automatic (Windows'' default)') -and ($o -contains 'app notifications back on (Windows'' default)')) ($o -join ' / ')
$TW.Services['SysMain'] = 'Disabled'; $TW.Reg[$nt] = 0; $o = Run
Check '... once: the owner turning them off by hand later is left alone' (($TW.Services['SysMain'] -eq 'Disabled') -and $TW.Reg[$nt] -eq 0 -and -not ($o -match 'SysMain|notifications')) ($o -join ' / ')
$hist = Join-Path (Split-Path $bk) 'change-history.log'
Check 'a change history next to the originals: each setting with its before and after value' ((Test-Path $hist) -and ((Get-Content $hist -Raw) -match "AllowTelemetry '\(not set\)' -> '0'") -and ((Get-Content $hist -Raw) -match 'app Microsoft\.Copilot removed')) ''
Section 'Edge kept out of the way (it stays installed: Windows and apps need it)'
$er = "$Work\edge"; $env:PCKIT_EDGE_ROOT = $er; $uc = 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice|ProgId'
$pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System|DefaultAssociationsConfiguration'
function EdgeFresh { Clear-Path $er; foreach ($d in 'public', 'desktop', 'pinned') { New-Item "$er\$d" -ItemType Directory -Force | Out-Null; '' | Set-Content "$er\$d\Microsoft Edge.lnk" }; '' | Set-Content "$er\chrome"; '' | Set-Content "$er\msedge.exe" }
Fresh; Clear-Path $bk; '' | Set-Content $opt; EdgeFresh; $TW.Reg[$uc] = 'MSEdgeHTM'; $o = Run
Check 'its desktop icons are removed, and it may not put them back when it updates' (($o -contains 'Edge desktop icon removed') -and -not (Test-Path "$er\public\Microsoft Edge.lnk") -and -not (Test-Path "$er\desktop\Microsoft Edge.lnk") -and
    $TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate|CreateDesktopShortcutDefault'] -eq 0) ($o -join ' / ')
Check 'no first-run pages, no "make Edge your default" prompts' ($TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Edge|HideFirstRunExperience'] -eq 1 -and $TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Edge|DefaultBrowserSettingEnabled'] -eq 0) ''
Check 'no default-apps policy (Windows applies it on company-domain PCs only; the Welcome page has the one-click way)' (-not $TW.Reg.ContainsKey($pol) -and -not ($o -match 'Chrome')) ($o -join ' / ')
$o = Run
Check '... done once: the next check changes nothing' (-not ($o -match 'Edge|Chrome')) ($o -join ' / ')
Fresh; Clear-Path $bk; EdgeFresh; $TW.Reg[$uc] = 'MSEdgeHTM'; [void](Run)
'tweak.edge=off' | Set-Content $opt; $o = Run
Check 'switched off in Settings: its desktop icon and prompts come back' (($o -contains 'Edge back as it was (your choice)') -and (Test-Path "$er\public\Microsoft Edge.lnk") -and
    -not $TW.Reg.ContainsKey('HKLM:\SOFTWARE\Policies\Microsoft\Edge|HideFirstRunExperience')) ($o -join ' / ')
Section 'Edge removed altogether (opt-in): only the browser, WebView2 stays'
$eu = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate|Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'
function EdgeSetup { New-Item "$er\Installer" -ItemType Directory -Force | Out-Null; '' | Set-Content "$er\Installer\setup.exe"; New-Item "$er\webview2" -ItemType Directory -Force | Out-Null }
Fresh; Clear-Path $bk; '' | Set-Content $opt; EdgeFresh; EdgeSetup; $o = Run
Check 'off unless the owner turns it on: Edge stays, no policy' ((Test-Path "$er\msedge.exe") -and -not ($TWlog -match 'setup\.exe') -and -not $TW.Reg.ContainsKey($eu)) ($o -join ' / ')
'tweak.edge-remove=on' | Set-Content $opt; $TW.EdgeGoes = $true; $TWlog.Clear(); $o = Run
Check 'turned on: Edge''s own uninstaller runs (system-wide, profiles kept) and Edge Update may not install it again' (($TWlog -match '^run setup\.exe --uninstall --system-level --force-uninstall$') -and -not ($TWlog -match 'delete-profile') -and $TW.Reg[$eu] -eq 0 -and $o -contains 'Edge removed (WebView2 kept)') (($o + $TWlog) -join ' / ')
Check '... after the old built-in Edge''s file is there (what unlocks the uninstaller); WebView2 untouched' ((Test-Path "$er\SystemApps\MicrosoftEdge.exe") -and (Test-Path "$er\webview2")) ''
$TWlog.Clear(); $o = Run
Check '... done once: the next check changes nothing' (-not ($TWlog -match 'setup\.exe') -and -not ($o -match 'Edge')) ($o -join ' / ')
'' | Set-Content "$er\msedge.exe"; $TWlog.Clear(); $o = Run
Check '... Windows put it back: removed again' (($TWlog -match '^run setup\.exe --uninstall') -and $o -contains 'Edge removed (WebView2 kept)') ($o -join ' / ')
'' | Set-Content $opt; $TWlog.Clear(); $o = Run
Check 'turned off again: Edge reinstalled (winget) and the policy gone' (($TWlog -match '^winget install --id Microsoft\.Edge') -and $o -contains 'Edge installed again (your choice)' -and -not $TW.Reg.ContainsKey($eu)) (($o + $TWlog) -join ' / ')

'' | Set-Content $opt; $env:PCKIT_EDGE_ROOT = ''
Fresh; Clear-Path $bk; $o = Run
Check 'in tests without a folder of their own, no icon or pin of this PC is touched' (-not ($o -match 'Edge desktop|unpinned')) ($o -join ' / ')

Section 'Razer / Logitech auto-installers (from winutil): an empty, write-locked folder where their installers unpack'
$vr = "$Work\vendor"; $env:PCKIT_VENDOR_ROOT = $vr; Clear-Path $vr; New-Item $vr -ItemType Directory -Force | Out-Null
$all = New-Object Security.Principal.SecurityIdentifier 'S-1-1-0'
function Locked($d) { [bool]((Test-Path $d) -and @((Get-Acl $d).Access | Where-Object { $_.AccessControlType -eq 'Deny' -and $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]) -eq $all })) }
New-Item "$vr\LogiDownloadAssistant" -ItemType Directory -Force | Out-Null; '' | Set-Content "$vr\LogiDownloadAssistant\installed-on-purpose.exe"
Fresh; Clear-Path $bk; '' | Set-Content $opt; $o = Run
Check 'Razer''s installer folder is created and locked against writing' ((Locked "$vr\Razer") -and $o -contains 'Razer auto-installer blocked') ($o -join ' / ')
Check '... a folder that already has an app in it is left alone' (-not (Locked "$vr\LogiDownloadAssistant") -and (Test-Path "$vr\LogiDownloadAssistant\installed-on-purpose.exe")) ''
Check '... recorded for the uninstaller' ((Get-Content $bk -Raw | ConvertFrom-Json).'vendor|Razer'.Path -eq "$vr\Razer") ''
$o = Run
Check '... done once: the next check changes nothing' (-not ($o -match 'auto-installer')) ($o -join ' / ')
'tweak.vendor-installers=off' | Set-Content $opt; $o = Run
Check 'switched off in Settings: unlocked and the empty folder removed' (-not (Test-Path "$vr\Razer") -and $o -contains 'Razer auto-installer allowed again (your choice)') ($o -join ' / ')
'' | Set-Content $opt; $env:PCKIT_VENDOR_ROOT = ''; Clear-Path $vr

Section 'network at Windows'' defaults: what "gaming tweak" tools change (throttling index, Nagle) is put back'
$mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; $nif = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{TEST}'
function Get-ChildItem { if ("$args" -match 'Tcpip\\Parameters\\Interfaces') { return [pscustomobject]@{ PSChildName = '{TEST}' } }; Microsoft.PowerShell.Management\Get-ChildItem @args }   # (one adapter, the test's own)
Fresh; Clear-Path $bk; '' | Set-Content $opt; $o = Run
Check 'Windows'' own values: nothing changed, nothing added' (-not $TW.Reg.ContainsKey("$mm|NetworkThrottlingIndex") -and -not ($o -match 'Nagle|NetworkThrottling')) ($o -join ' / ')
$TW.Reg["$mm|NetworkThrottlingIndex"] = 4294967295; $TW.Reg["$nif|TcpAckFrequency"] = 1; $TW.Reg["$nif|TCPNoDelay"] = 1; $o = Run
Check 'a tool turned throttling and Nagle off: Windows'' defaults back (index 10, Nagle values gone)' ($TW.Reg["$mm|NetworkThrottlingIndex"] -eq 10 -and -not $TW.Reg.ContainsKey("$nif|TcpAckFrequency") -and -not $TW.Reg.ContainsKey("$nif|TCPNoDelay") -and ($o -contains 'setting NetworkThrottlingIndex') -and ($o -match 'Nagle setting TcpAckFrequency removed')) ($o -join ' / ')
Check '... the tool''s values recorded for the uninstaller' ((Get-Content $bk -Raw | ConvertFrom-Json)."reg|$nif|TCPNoDelay".Value -eq 1) ''
'tweak.network-defaults=off' | Set-Content $opt; $o = Run
Check 'switched off in Settings: the index goes back to what it was' ($TW.Reg["$mm|NetworkThrottlingIndex"] -eq 4294967295) ($o -join ' / ')
'' | Set-Content $opt; Remove-Item function:Get-ChildItem

Section 'start-up helpers of hardware that is switched off (an unused integrated GPU, onboard audio)'
Fresh; Clear-Path $bk; '' | Set-Content $opt; $TW.Run = @('RtkAudUService', 'AMDNoiseSuppression', 'Steam')
$TW.Pnp = @([pscustomobject]@{ Class = 'Display'; FriendlyName = 'NVIDIA GeForce RTX 4070'; Manufacturer = 'NVIDIA'; Status = 'OK' }, [pscustomobject]@{ Class = 'Display'; FriendlyName = 'AMD Radeon(TM) Graphics'; Manufacturer = 'Advanced Micro Devices, Inc.'; Status = 'Error' }, [pscustomobject]@{ Class = 'MEDIA'; FriendlyName = 'Realtek(R) Audio'; Manufacturer = 'Realtek'; Status = 'Error' })
$o = Run
Check 'Realtek''s and AMD''s helpers off when their hardware is off; everything else left alone' (($o -contains 'start-up item RtkAudUService off (its hardware is off)') -and ($o -contains 'start-up item AMDNoiseSuppression off (its hardware is off)') -and -not ($o -match 'item Steam')) ($o -join ' / ')
Fresh; Clear-Path $bk; $TW.Run = @('RtkAudUService', 'AMDNoiseSuppression'); $TW.Pnp = @([pscustomobject]@{ Class = 'Display'; FriendlyName = 'AMD Radeon RX 7800 XT'; Manufacturer = 'Advanced Micro Devices, Inc.'; Status = 'OK' }, [pscustomobject]@{ Class = 'MEDIA'; FriendlyName = 'Realtek(R) Audio'; Manufacturer = 'Realtek'; Status = 'OK' }); $o = Run
Check '... working hardware: its helpers stay' (-not ($o -match 'RtkAudUService|AMDNoiseSuppression')) ($o -join ' / ')
Fresh; Clear-Path $bk; $TW.Run = @('RtkAudUService'); $o = Run
Check '... Windows lists no graphics devices (can''t tell): left alone' (-not ($o -match 'RtkAudUService')) ($o -join ' / ')
$TW.Pnp = $null

Section 'a value the owner keeps their own way (kit-options "keep.<key>\<name>=<value>" - the app''s Keep button)'
$tk = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
Fresh; Clear-Path $bk; "keep.$tk\AllowTelemetry=3" | Set-Content $opt; $o = Run
Check 'held at the owner''s value, not Messiah''s; said' ($TW.Reg["$tk|AllowTelemetry"] -eq 3 -and ($o -contains 'setting AllowTelemetry kept as you chose')) ($o -join ' / ')
$o = Run
Check '... then left alone' (-not ($o -match 'AllowTelemetry')) ($o -join ' / ')
"keep.$tk\AllowTelemetry=(not set)" | Set-Content $opt; $o = Run
Check '... kept as "(not set)": the value goes' (-not $TW.Reg.ContainsKey("$tk|AllowTelemetry")) ($o -join ' / ')
'' | Set-Content $opt; $o = Run
Check 'handed back to Messiah: its own value again' ($TW.Reg["$tk|AllowTelemetry"] -eq 0 -and ($o -contains 'setting AllowTelemetry')) ($o -join ' / ')

Section 'the status per switch (-StatusFile, the app''s Status tab)'
$sf = "$Work\tweak-status.json"; Clear-Path $sf
Fresh; Clear-Path $bk; $o = @(& "$Work\tweaks.ps1" -StatusFile $sf); $j = Get-Content $sf -Raw | ConvertFrom-Json
Check 'a fresh Windows: what each switch changed, under its own name' ((@($j.keys.telemetry.fixed) -contains 'AllowTelemetry') -and (@($j.keys.'#Services'.fixed) -contains 'service DiagTrack off') -and (@($j.keys.'#Scheduled tasks'.fixed) -contains 'task Microsoft Compatibility Appraiser off') -and -not $j.preview) (Get-Content $sf -Raw)
$o = @(& "$Work\tweaks.ps1" -StatusFile $sf); $j = Get-Content $sf -Raw | ConvertFrom-Json
Check '... the settings each switch checks, by their place in the registry (the details; its history is matched by it)' (@($j.keys.telemetry.names) -contains 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection\AllowTelemetry') (Get-Content $sf -Raw)
Check '... the next check: all in place, nothing put back' (([int]$j.keys.telemetry.same -ge 20) -and -not @($j.keys.PSObject.Properties | Where-Object { @($_.Value.fixed).Count })) (Get-Content $sf -Raw)
$TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection|AllowTelemetry'] = 3; $o = @(& "$Work\tweaks.ps1" -Audit -StatusFile $sf); $j = Get-Content $sf -Raw | ConvertFrom-Json
Check '... a preview names what drifted, and changes nothing' ($j.preview -and (@($j.keys.telemetry.fixed) -contains 'AllowTelemetry') -and $TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection|AllowTelemetry'] -eq 3) (Get-Content $sf -Raw)
$TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection|AllowTelemetry'] = 3; Clear-Path "$Work\change-history.log"; $o = @(& "$Work\tweaks.ps1" -StatusFile $sf -Cause 'Windows Update (2026-10 Cumulative Update)'); $j = Get-Content $sf -Raw | ConvertFrom-Json
Check 'what changed it back (-Cause): kept with the change in the history and in the status' ((@(Get-Content "$Work\change-history.log") -match 'AllowTelemetry ''3'' -> ''0'' \[after Windows Update \(2026-10 Cumulative Update\)\]') -and $j.cause -eq 'Windows Update (2026-10 Cumulative Update)') ((Get-Content "$Work\change-history.log" -Raw) + (Get-Content $sf -Raw))
Clear-Path $sf

Finish
