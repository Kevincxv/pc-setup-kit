# PC Setup Kit - Windows 11 debloat + performance tweaks.
# Idempotent: only changes what differs from the target and prints one line per change, so it is used both
# by setup.ps1 at first logon and by health-check.ps1 as a "tweak guard" after Windows updates.
# Must run elevated, as the user who owns the PC (HKCU settings apply to that user).
$ErrorActionPreference = 'SilentlyContinue'
$changes = New-Object System.Collections.Generic.List[string]

# Originals: the first time a setting is changed, its previous state is kept in C:\PCSetupKit\tweaks-backup.json,
# so uninstall.ps1 -RevertTweaks can put everything back exactly as it was
$bkFile = 'C:\PCSetupKit\tweaks-backup.json'
$bk = @{}; try { (Get-Content $bkFile -Raw | ConvertFrom-Json -ErrorAction Stop).PSObject.Properties | ForEach-Object { $bk[$_.Name] = $_.Value } } catch {}
$bkDirty = $false
function Save-Original($Key, $Data) { if (-not $bk.ContainsKey($Key)) { $bk[$Key] = $Data; $script:bkDirty = $true } }

function Set-Reg($Path, $Name, $Value, $Type = 'DWord') {
    $cur = (Get-ItemProperty -Path $Path -Name $Name).$Name
    if ("$cur" -ne "$Value") {
        $had = $null -ne (Get-ItemProperty -Path $Path -Name $Name)
        Save-Original "reg|$Path|$Name" @{ Existed = $had; Value = $cur; Kind = $(if ($had) { "$((Get-Item $Path).GetValueKind($Name))" }) }
        if (-not (Test-Path $Path)) { New-Item $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
        $changes.Add("setting $Name")
    }
}

# --- Telemetry, ads, suggestions, AI features ---
$P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows'
Set-Reg "$P\DataCollection" AllowTelemetry 0
Set-Reg "$P\DataCollection" DoNotShowFeedbackNotifications 1
Set-Reg "$P\CloudContent" DisableWindowsConsumerFeatures 1
Set-Reg "$P\CloudContent" DisableSoftLanding 1
Set-Reg "$P\CloudContent" DisableCloudOptimizedContent 1
Set-Reg "$P\CloudContent" DisableTailoredExperiencesWithDiagnosticData 1
Set-Reg "$P\System" EnableActivityFeed 0
Set-Reg "$P\System" PublishUserActivities 0
Set-Reg "$P\System" UploadUserActivities 0
Set-Reg "$P\AdvertisingInfo" DisabledByGroupPolicy 1
Set-Reg "$P\Windows Search" AllowCortana 0
Set-Reg "$P\Windows Search" DisableWebSearch 1
Set-Reg "$P\Windows Search" ConnectedSearchUseWeb 0
Set-Reg "$P\WindowsCopilot" TurnOffWindowsCopilot 1
Set-Reg "$P\WindowsAI" DisableAIDataAnalysis 1
Set-Reg "$P\WindowsAI" DisableClickToDo 1
Set-Reg "$P\WindowsAI" TurnOffSavingSnapshots 1
Set-Reg "$P\OneDrive" DisableFileSyncNGSC 1
Set-Reg "$P\DeliveryOptimization" DODownloadMode 1              # update sharing only with this home network
Set-Reg "$P\GameDVR" AllowGameDVR 0
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' AllowNewsAndInterests 0   # Widgets
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' StartupBoostEnabled 0    # Edge stays (apps need WebView2) but stays out of the way
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' BackgroundModeEnabled 0
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' HubsSidebarEnabled 0
Set-Reg "$P\Windows Error Reporting" DontSendAdditionalData 1   # crash reports stay local (kept on so blue screens can be diagnosed)

$U = 'HKCU:\Software\Policies\Microsoft\Windows'
Set-Reg "$U\Explorer" DisableSearchBoxSuggestions 1
Set-Reg "$U\WindowsCopilot" TurnOffWindowsCopilot 1
Set-Reg "$U\WindowsAI" DisableAIDataAnalysis 1
Set-Reg "$U\WindowsAI" DisableClickToDo 1

$CDM = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
foreach ($n in 'ContentDeliveryAllowed', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled', 'PreInstalledAppsEverEnabled',
    'SilentInstalledAppsEnabled', 'SoftLandingEnabled', 'SystemPaneSuggestionsEnabled', 'RotatingLockScreenOverlayEnabled',
    'SubscribedContent-310093Enabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
    'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled') { Set-Reg $CDM $n 0 }
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' ScoobeSystemSettingEnabled 0
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' Enabled 0
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' TailoredExperiencesWithDiagnosticDataEnabled 0
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' BingSearchEnabled 0
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' ToastEnabled 0

# --- Taskbar / Start / look ---
$ADV = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
Set-Reg $ADV ShowCopilotButton 0
Set-Reg $ADV ShowTaskViewButton 0
Set-Reg $ADV Start_IrisRecommendations 0
Set-Reg $ADV Start_TrackDocs 0
Set-Reg $ADV Start_AccountNotifications 0
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' EnableTransparency 0
Set-Reg 'HKCU:\Control Panel\Mouse' MouseSpeed '0' String       # no mouse acceleration
Set-Reg 'HKCU:\Control Panel\Mouse' MouseThreshold1 '0' String
Set-Reg 'HKCU:\Control Panel\Mouse' MouseThreshold2 '0' String

# --- Gaming / performance ---
Set-Reg 'HKCU:\System\GameConfigStore' GameDVR_Enabled 0
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' AppCaptureEnabled 0
Set-Reg 'HKCU:\Software\Microsoft\GameBar' AutoGameModeEnabled 1
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' HwSchMode 2                      # hardware GPU scheduling
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' EnableVirtualizationBasedSecurity 0  # memory integrity / VBS off (gaming)
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' Enabled 0
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' DisableWpbtExecution 1          # blocks motherboard "auto driver installer" bloat
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' CrashDumpEnabled 7                  # keep crash dumps for diagnosis
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' AlwaysKeepMemoryDump 1
# Bigger event logs (64 MB instead of ~15-20): days of history to diagnose a crash, a freeze or a vanished program
# with, instead of hours (busy PowerShell scripts alone can fill the default Windows PowerShell log in an afternoon)
foreach ($log in 'Application', 'System', 'Windows PowerShell') { Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\$log" MaxSize 67108864 }

# --- Services ---
foreach ($n in 'DiagTrack', 'dmwappushservice', 'SysMain', 'MapsBroker', 'lfsvc', 'TrkWks', 'WSAIFabricSvc', 'PcaSvc', 'RetailDemo') {
    $s = Get-Service $n
    if ($s -and $s.StartType -ne 'Disabled') { Save-Original "service|$n" @{ StartType = "$($s.StartType)" }; Stop-Service $n -Force; Set-Service $n -StartupType Disabled; $changes.Add("service $n off") }
}
$manual = 'StiSvc', 'PhoneSvc', 'diagsvc'
$printers = try { Get-Printer -ErrorAction Stop } catch { @() }
if (-not ($printers | Where-Object { $_.PortName -notmatch '^(PORTPROMPT|nul|SHRFAX|XPS|PDF)' -and $_.Name -notmatch 'PDF|XPS|OneNote|Fax' })) { $manual += 'Spooler' }  # no real printer
foreach ($n in $manual) {
    $s = Get-Service $n
    if ($s -and $s.StartType -eq 'Automatic') { Save-Original "service|$n" @{ StartType = 'Automatic' }; Set-Service $n -StartupType Manual; $changes.Add("service $n manual") }
}

# --- Scheduled tasks (telemetry, feedback, compatibility scans) ---
$tasks = '\Microsoft\Windows\Application Experience\MareBackup', '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp', '\Microsoft\Windows\Application Experience\PcaPatchDbTask',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater', '\Microsoft\Windows\Application Experience\StartupAppTask',
    '\Microsoft\Windows\Autochk\Proxy', '\Microsoft\Windows\CloudExperienceHost\CreateObjectTask',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator', '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\Diagnosis\RecommendedTroubleshootingScanner', '\Microsoft\Windows\Diagnosis\Scheduled',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector', '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload', '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataFlushing',
    '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReceiver', '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReporting',
    '\Microsoft\Windows\Flighting\FeatureConfig\GovernedFeatureUsageProcessing', '\Microsoft\Windows\Maintenance\WinSAT',
    '\Microsoft\Windows\Maps\MapsToastTask', '\Microsoft\Windows\Maps\MapsUpdateTask', '\Microsoft\Windows\PerformanceTrace\ShowFeedbackToast',
    '\Microsoft\Windows\Shell\FamilySafetyRefreshTask', '\Microsoft\Windows\Shell\FamilySafetyMonitor',
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting', '\Microsoft\Windows\WwanSvc\NotificationTask'
foreach ($t in Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' -and ($_.TaskPath + $_.TaskName) -in $tasks }) {
    Save-Original "task|$($t.TaskPath)$($t.TaskName)" @{ Enabled = $true }; $t | Disable-ScheduledTask | Out-Null; $changes.Add("task $($t.TaskName) off")
}
foreach ($t in Get-ScheduledTask | Where-Object { $_.TaskName -match 'AsrAPPShop|ArmouryCrate.*Update|MSI.*LiveUpdate' -and $_.TaskPath -eq '\' }) {
    Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false; $changes.Add("motherboard installer task $($t.TaskName) removed")
}

# --- Preinstalled apps (current user, all users, and new users) ---
$apps = 'Microsoft.Copilot', 'Microsoft.Windows.Ai.Copilot.Provider', 'MicrosoftWindows.Client.WebExperience', 'Microsoft.WidgetsPlatformRuntime',
    'Microsoft.StartExperiencesApp', 'MicrosoftWindows.CrossDevice', 'Microsoft.YourPhone', 'Microsoft.BingNews', 'Microsoft.BingWeather',
    'Microsoft.BingSearch', 'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.People',
    'Microsoft.PowerAutomateDesktop', 'Microsoft.Todos', 'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps', 'Microsoft.ZuneMusic',
    'Microsoft.ZuneVideo', 'Clipchamp.Clipchamp', 'MicrosoftCorporationII.QuickAssist', 'MicrosoftCorporationII.MicrosoftFamily',
    'Microsoft.OutlookForWindows', 'MSTeams', 'MicrosoftTeams', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.Office.OneNote',
    'Microsoft.MicrosoftStickyNotes', 'Microsoft.WindowsAlarms', 'Microsoft.WindowsSoundRecorder', 'Microsoft.549981C3F5F10',
    'Microsoft.Windows.DevHome', 'Microsoft.XboxGamingOverlay', 'Microsoft.MixedReality.Portal', 'Microsoft.Wallet',
    'Microsoft.Microsoft3DViewer', 'Microsoft.SkypeApp', 'Microsoft.LinkedIn', 'SpotifyAB.SpotifyMusic', 'Disney.37853FC22B2CE',
    'Facebook.Facebook', 'Facebook.Instagram', 'BytedancePte.Ltd.TikTok', '5319275A.WhatsAppDesktop', 'AmazonVideo.PrimeVideo'
foreach ($a in $apps) {
    $pkg = Get-AppxPackage -AllUsers $a
    if ($pkg) {
        Save-Original "app|$a" @{ Name = ($pkg | Select-Object -First 1).Name; Removed = (Get-Date).ToString('d') }   # can't be put back automatically (Microsoft Store)
        $pkg | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers }
        $changes.Add("app $a removed")
        Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $a | ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName | Out-Null }
    }
}

# --- Devices: no power-saving on controllers and wired network ---
foreach ($d in Get-CimInstance -Namespace root\wmi MSPower_DeviceEnable | Where-Object { $_.Enable -and $_.InstanceName -match 'VID_045E' }) {   # Xbox controllers
    Save-Original "power|$($d.InstanceName)" @{ Enable = $true }
    Set-CimInstance -InputObject $d -Property @{ Enable = $false }; $changes.Add('controller power-saving off')
}
foreach ($nic in Get-NetAdapter -Physical | Where-Object { $_.MediaType -eq '802.3' }) {
    foreach ($prop in 'Energy-Efficient Ethernet', 'Energy Efficient Ethernet', 'Green Ethernet', 'Power Saving Mode', 'Gigabit Lite', 'Advanced EEE') {
        $v = Get-NetAdapterAdvancedProperty -Name $nic.Name -DisplayName $prop -ErrorAction SilentlyContinue
        if ($v -and $v.DisplayValue -notin 'Disabled', 'Off') {
            Save-Original "nic|$($nic.Name)|$prop" @{ DisplayValue = $v.DisplayValue }
            Set-NetAdapterAdvancedProperty -Name $nic.Name -DisplayName $prop -DisplayValue $(if ($v.ValidDisplayValues -contains 'Disabled') { 'Disabled' } else { 'Off' }) -NoRestart
            $changes.Add("ethernet $prop off")
        }
    }
    foreach ($d in Get-CimInstance -Namespace root\wmi MSPower_DeviceEnable | Where-Object { $_.Enable -and $_.InstanceName -like "$($nic.PnPDeviceID)*" }) {
        Save-Original "power|$($d.InstanceName)" @{ Enable = $true }
        Set-CimInstance -InputObject $d -Property @{ Enable = $false }; $changes.Add('ethernet power-saving off')
    }
}

if ($bkDirty) {
    New-Item (Split-Path $bkFile) -ItemType Directory -Force | Out-Null
    $bk | ConvertTo-Json -Depth 4 | Set-Content "$bkFile.tmp" -Encoding utf8
    Move-Item "$bkFile.tmp" $bkFile -Force
}
$changes | Select-Object -Unique
