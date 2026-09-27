# tweaks.ps1 (the tweak guard: runs at setup and at every login on every PC) with every write mocked:
# a fresh Windows gets every tweak once (originals recorded), an already-tweaked PC gets nothing, special cases.
. "$PSScriptRoot\..\lib.ps1"
$tweaksText = Get-Content "$Kit\tweaks.ps1" -Raw
$bk = "$Work\tweaks-backup.json"
Set-Content "$Work\tweaks.ps1" $tweaksText.Replace("'C:\PCSetupKit\tweaks-backup.json'", "'$bk'")
$mocked = 'Set-ItemProperty', 'New-Item', 'Get-ItemProperty', 'Set-Service', 'Stop-Service', 'Get-Service', 'Disable-ScheduledTask', 'Unregister-ScheduledTask',
    'Get-ScheduledTask', 'Get-AppxPackage', 'Get-AppxProvisionedPackage', 'Remove-AppxPackage', 'Remove-AppxProvisionedPackage', 'Get-CimInstance', 'Set-CimInstance',
    'Get-NetAdapter', 'Get-NetAdapterAdvancedProperty', 'Set-NetAdapterAdvancedProperty', 'Get-Printer', 'Test-Path'
if (-not (Test-Tripwire "$Work\tweaks.ps1" $mocked)) { Finish }
Import-MockTargets $mocked   # load their Windows modules BEFORE defining the mocks (see lib.ps1)

$svcNames = 'DiagTrack', 'dmwappushservice', 'SysMain', 'MapsBroker', 'lfsvc', 'TrkWks', 'WSAIFabricSvc', 'PcaSvc', 'RetailDemo', 'StiSvc', 'PhoneSvc', 'diagsvc', 'Spooler'
function Fresh {
    $global:TW = @{
        Reg = @{}; Services = @{}; Printers = @(); Apps = @('Microsoft.Copilot', 'Microsoft.BingNews', 'MSTeams', 'SpotifyAB.SpotifyMusic'); Prov = @('Microsoft.BingNews')
        Tasks = @(@{ P = '\Microsoft\Windows\Application Experience\'; N = 'Microsoft Compatibility Appraiser'; S = 'Ready' }, @{ P = '\Microsoft\Windows\Feedback\Siuf\'; N = 'DmClient'; S = 'Ready' },
            @{ P = '\'; N = 'AsrAPPShopUpdate'; S = 'Ready' }, @{ P = '\Microsoft\Windows\Defrag\'; N = 'ScheduledDefrag'; S = 'Ready' }, @{ P = '\'; N = 'MyOwnTask'; S = 'Ready' })
        Power = @(@{ I = 'USB\VID_045E&PID_0B00\1_0'; E = $true }, @{ I = 'PCI\VEN_10EC&DEV_8125\X_0'; E = $true }, @{ I = 'USB\VID_046D&PID_C08B\M_0'; E = $true })
        Nic = @{ 'Energy-Efficient Ethernet' = 'Enabled'; 'Green Ethernet' = 'Enabled'; 'Jumbo Packet' = 'Disabled' }
    }
    foreach ($s in $svcNames) { $TW.Services[$s] = $(if ($s -in 'StiSvc', 'PhoneSvc', 'diagsvc', 'Spooler', 'SysMain', 'DiagTrack') { 'Automatic' } else { 'Manual' }) }
    $global:TWlog = New-Object System.Collections.Generic.List[string]
}
function Set-ItemProperty { param($Path, $Name, $Value, $Type) $global:TW.Reg["$Path|$Name"] = $Value; $global:TWlog.Add("reg $Name=$Value") }
function Get-ItemProperty { param($Path, $Name) if ($global:TW.Reg.ContainsKey("$Path|$Name")) { [pscustomobject]@{ $Name = $global:TW.Reg["$Path|$Name"] } } }
function New-Item { param($Path, [switch]$Force, $ItemType) if ("$Path" -match '^HK') { $global:TWlog.Add("new key $Path") } else { Microsoft.PowerShell.Management\New-Item @PSBoundParameters } }
function Test-Path { $a = @($args | ForEach-Object { $_ }) -join ' '; if ($a -match '^HK') { return $true }; Microsoft.PowerShell.Management\Test-Path @args }
function Get-Service { param($Name) if ($global:TW.Services.ContainsKey($Name)) { [pscustomobject]@{ Name = $Name; StartType = $global:TW.Services[$Name] } } }
function Set-Service { param($Name, $StartupType) $global:TW.Services[$Name] = $StartupType; $global:TWlog.Add("service $Name $StartupType") }
function Stop-Service { param($Name, [switch]$Force) $global:TWlog.Add("stop $Name") }
function Get-ScheduledTask { param($TaskName) $global:TW.Tasks | ForEach-Object { [pscustomobject]@{ TaskPath = $_.P; TaskName = $_.N; State = $_.S } } }
function Disable-ScheduledTask { $input | ForEach-Object { $n = $_.TaskName; ($global:TW.Tasks | Where-Object N -eq $n).S = 'Disabled'; $global:TWlog.Add("task off $n") } }
function Unregister-ScheduledTask { param($TaskName, $Confirm) $global:TW.Tasks = @($global:TW.Tasks | Where-Object N -ne $TaskName); $global:TWlog.Add("task removed $TaskName") }
function Get-AppxPackage { param([switch]$AllUsers, $Name) $n = if ($Name) { $Name } else { $args[0] }; if ($n -in $global:TW.Apps) { [pscustomobject]@{ Name = $n; PackageFullName = "$n`_1.0_x64" } } }
function Remove-AppxPackage { param($Package, [switch]$AllUsers) $n = ($Package -split '_')[0]; $global:TW.Apps = @($global:TW.Apps | Where-Object { $_ -ne $n }); $global:TWlog.Add("app removed $n") }
function Get-AppxProvisionedPackage { param([switch]$Online) $global:TW.Prov | ForEach-Object { [pscustomobject]@{ DisplayName = $_; PackageName = "$_`_prov" } } }
function Remove-AppxProvisionedPackage { param([switch]$Online, $PackageName) $global:TW.Prov = @($global:TW.Prov | Where-Object { "$_`_prov" -ne $PackageName }); $global:TWlog.Add("provisioned removed $PackageName") }
function Get-CimInstance { if ("$args" -match 'MSPower_DeviceEnable') { return $global:TW.Power | ForEach-Object { [pscustomobject]@{ InstanceName = $_.I; Enable = $_.E } } }; CimCmdlets\Get-CimInstance @args }
function Set-CimInstance { param($InputObject, $Property) ($global:TW.Power | Where-Object I -eq $InputObject.InstanceName).E = $Property.Enable; $global:TWlog.Add("power off $($InputObject.InstanceName)") }
function Get-NetAdapter { param([switch]$Physical) [pscustomobject]@{ Name = 'Ethernet'; MediaType = '802.3'; PnPDeviceID = 'PCI\VEN_10EC&DEV_8125\X' } }
function Get-NetAdapterAdvancedProperty { param($Name, $DisplayName) if ($global:TW.Nic.ContainsKey($DisplayName)) { [pscustomobject]@{ DisplayName = $DisplayName; DisplayValue = $global:TW.Nic[$DisplayName]; ValidDisplayValues = @('Disabled', 'Enabled') } } }
function Set-NetAdapterAdvancedProperty { param($Name, $DisplayName, $DisplayValue, [switch]$NoRestart) $global:TW.Nic[$DisplayName] = $DisplayValue; $global:TWlog.Add("nic $DisplayName=$DisplayValue") }
function Get-Printer { $global:TW.Printers }
if (-not (Assert-Mocks $mocked)) { Finish }
function Run { @(& "$Work\tweaks.ps1") }

Section 'a fresh Windows: every tweak applied once'
Fresh; $o = Run
$regSets = @($TWlog -match '^reg ').Count; $setRegCalls = $TW.Reg.Count   # distinct settings (some Set-Reg lines are loops)
Check "all $setRegCalls settings written, each exactly once" ($regSets -eq $setRegCalls -and $setRegCalls -ge 50) "writes: $regSets, distinct: $setRegCalls"
Check 'each change is reported (one line per kind)' (($o -match '^setting ').Count -ge 1 -and ($o -contains 'service DiagTrack off') -and ($o -contains 'task Microsoft Compatibility Appraiser off')) ($o -join ' / ')
Check 'telemetry, Copilot, Recall/Click to Do, ads and Bing search turned off' ($TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection|AllowTelemetry'] -eq 0 -and $TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot|TurnOffWindowsCopilot'] -eq 1 -and $TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI|DisableClickToDo'] -eq 1 -and $TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search|DisableWebSearch'] -eq 1) ''
Check 'crash reports stay possible (WER kept on, only extra data off)' (-not ($TW.Reg.Keys | Where-Object { $_ -match 'Windows Error Reporting\|Disabled$' })) ''
Check 'telemetry/unneeded services disabled' (($TW.Services['DiagTrack'] -eq 'Disabled') -and ($TW.Services['SysMain'] -eq 'Disabled')) ''
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
$TW.Reg['HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection|AllowTelemetry'] = 3; $TW.Services['SysMain'] = 'Automatic'; $TW.Apps = @('Microsoft.Copilot')
$TWlog.Clear(); $o = Run
Check 'only the reverted ones are re-applied and reported' (($TWlog.Count -eq 4) -and ($o -contains 'setting AllowTelemetry') -and ($o -contains 'service SysMain off') -and ($o -contains 'app Microsoft.Copilot removed')) (($o + '|' + $TWlog) -join ' / ')
Check '... and the recorded original stays the FIRST one (not the reverted value)' ((Get-Content $bk -Raw | ConvertFrom-Json).'reg|HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection|AllowTelemetry'.Existed -eq $false) ''

Section 'special cases'
Fresh; $TW.Printers = @([pscustomobject]@{ Name = 'HP LaserJet'; PortName = 'USB001' }); Clear-Path $bk; [void](Run)
Check 'a real printer: the print spooler stays automatic' ($TW.Services['Spooler'] -eq 'Automatic') $TW.Services['Spooler']
Fresh; $TW.Printers = @([pscustomobject]@{ Name = 'Microsoft Print to PDF'; PortName = 'PORTPROMPT:' }); Clear-Path $bk; [void](Run)
Check 'only "Print to PDF": counts as no printer' ($TW.Services['Spooler'] -eq 'Manual') ''
Fresh; $TW.Services.Remove('WSAIFabricSvc'); $TW.Services.Remove('RetailDemo'); Clear-Path $bk; $e = @(& "$Work\tweaks.ps1" 2>&1 | Where-Object { $_ -is [Management.Automation.ErrorRecord] })
Check 'services missing on this Windows version: skipped without errors' ($e.Count -eq 0) "$e"
Finish
