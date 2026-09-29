# PC Setup Kit - Windows 11 debloat + performance tweaks.
# Idempotent: only changes what differs from the target and prints one line per change, so it is used both
# by setup.ps1 at first logon and by health-check.ps1 as a "tweak guard" after Windows updates.
# Must run elevated, as the user who owns the PC (HKCU settings apply to that user).
$ErrorActionPreference = 'SilentlyContinue'
$changes = New-Object System.Collections.Generic.List[string]
# one guard at a time (health-check, the update guard, setup, the app's choices): the originals file isn't written twice at
# once - the second waits (up to 2 min). Tests each get their own.
$tmx = New-Object Threading.Mutex($false, "Global\PCSetupKitTweaks$(if ($env:PCKIT_IN_TESTS) { "-$PID" })")
try { [void]$tmx.WaitOne(120000) } catch [Threading.AbandonedMutexException] { }

# Originals: the first time a setting is changed, its previous state is kept in C:\PCSetupKit\tweaks-backup.json,
# so uninstall.ps1 -RevertTweaks can put everything back exactly as it was
$bkFile = 'C:\PCSetupKit\tweaks-backup.json'
$bk = @{}; try { (Get-Content $bkFile -Raw | ConvertFrom-Json -ErrorAction Stop).PSObject.Properties | ForEach-Object { $bk[$_.Name] = $_.Value } } catch {}
$bkDirty = $false
function Save-Original($Key, $Data) { if (-not $bk.ContainsKey($Key)) { $bk[$Key] = $Data; $script:bkDirty = $true } }

# The owner's choices (the app's Settings > What the kit changes; kit-options.txt "tweak.<group>=off"): a group turned
# off is not applied, and what it changed goes back to how it was before the kit (the originals above) - checked at
# every run like everything else, so a choice holds after updates too. Groups: see $script:group below.
$optFile = if ($env:PCKIT_TWEAK_OPTIONS) { $env:PCKIT_TWEAK_OPTIONS } else { "$env:USERPROFILE\.claude\kit-options.txt" }
$off = @(Get-Content $optFile | Where-Object { $_ -match '^\s*tweak\.([\w-]+)\s*=\s*off\s*$' } | ForEach-Object { $Matches[1] })
function Want([string]$Group) { -not $Group -or $Group -notin $off }
$group = $null   # the group the next settings belong to (none: always applied)
# once per group turned off (reinstalling an app, turning hibernation back on): 'undone|<group>' in the backup file,
# cleared when the group is turned on again
function Undo-Once([string]$Group, [scriptblock]$Action, [string]$Said) {
    if ($bk.ContainsKey("undone|$Group")) { return }
    & $Action; $bk["undone|$Group"] = @{ Date = (Get-Date).ToString('o') }; $script:bkDirty = $true; $changes.Add($Said)
}
function Redo([string]$Group) { if ($bk.ContainsKey("undone|$Group")) { $bk.Remove("undone|$Group"); $script:bkDirty = $true } }

function Set-Reg($Path, $Name, $Value, $Type = 'DWord') {
    $cur = (Get-ItemProperty -Path $Path -Name $Name).$Name
    if (-not (Want $script:group)) {
        # turned off by the owner: back to the original (only if the kit had changed it)
        $o = $bk["reg|$Path|$Name"]; if (-not $o) { return }
        if ($o.Existed) { if ("$cur" -ne "$($o.Value)") { Set-ItemProperty -Path $Path -Name $Name -Value $o.Value -Type $(if ($o.Kind) { $o.Kind } else { 'DWord' }); $changes.Add("setting $Name back (your choice)") } }
        elseif ($null -ne (Get-ItemProperty -Path $Path -Name $Name)) { Remove-ItemProperty -Path $Path -Name $Name; $changes.Add("setting $Name back (your choice)") }
        return
    }
    if ("$cur" -ne "$Value") {
        $had = $null -ne (Get-ItemProperty -Path $Path -Name $Name)
        Save-Original "reg|$Path|$Name" @{ Existed = $had; Value = $cur; Kind = $(if ($had) { "$((Get-Item $Path).GetValueKind($Name))" }) }
        if (-not (Test-Path $Path)) { New-Item $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
        $changes.Add("setting $Name")
    }
}

# --- Telemetry, ads, suggestions, AI features ---
$group = 'telemetry'
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
$group = 'onedrive'; Set-Reg "$P\OneDrive" DisableFileSyncNGSC 1; $group = 'telemetry'
Set-Reg "$P\DeliveryOptimization" DODownloadMode 1              # update sharing only with this home network
$group = 'game-recording'; Set-Reg "$P\GameDVR" AllowGameDVR 0; $group = 'telemetry'
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
$group = 'start-menu'
$ADV = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
Set-Reg $ADV ShowCopilotButton 0
Set-Reg $ADV ShowTaskViewButton 0
Set-Reg $ADV Start_IrisRecommendations 0
Set-Reg $ADV Start_TrackDocs 0
Set-Reg $ADV Start_AccountNotifications 0
# the Sticky Keys / Filter Keys / Toggle Keys prompts (Shift five times, holding Shift, Num Lock) that throw a game out of
# fullscreen - only their keyboard shortcuts; the features stay in Settings > Accessibility
$group = 'sticky-keys'
Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' Flags '506' String
Set-Reg 'HKCU:\Control Panel\Accessibility\ToggleKeys' Flags '58' String
Set-Reg 'HKCU:\Control Panel\Accessibility\Keyboard Response' Flags '122' String
$group = 'transparency'; Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' EnableTransparency 0
$group = 'mouse-acceleration'
Set-Reg 'HKCU:\Control Panel\Mouse' MouseSpeed '0' String       # no mouse acceleration
Set-Reg 'HKCU:\Control Panel\Mouse' MouseThreshold1 '0' String
Set-Reg 'HKCU:\Control Panel\Mouse' MouseThreshold2 '0' String

# --- Gaming / performance ---
$group = 'game-recording'
Set-Reg 'HKCU:\System\GameConfigStore' GameDVR_Enabled 0
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' AppCaptureEnabled 0
$group = $null
Set-Reg 'HKCU:\Software\Microsoft\GameBar' AutoGameModeEnabled 1
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' HwSchMode 2                      # hardware GPU scheduling
$group = 'memory-integrity'
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' EnableVirtualizationBasedSecurity 0  # memory integrity / VBS off (gaming)
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' Enabled 0
$group = $null
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' DisableWpbtExecution 1          # blocks motherboard "auto driver installer" bloat
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' CrashDumpEnabled 7                  # keep crash dumps for diagnosis
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' AlwaysKeepMemoryDump 1
# Windows 11 "Optimizations for windowed games" (DX10/11 borderless games get the low-latency flip model) and
# variable refresh rate for games that don't ask for it - one string of "key=value;" pairs, other keys kept
$group = 'windowed-games'
$dxk = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$dx = "$((Get-ItemProperty -Path $dxk -Name DirectXUserGlobalSettings).DirectXUserGlobalSettings)"
$pairs = [ordered]@{}; foreach ($p in $dx -split ';' | Where-Object { $_ -match '=' }) { $kv = $p -split '=', 2; $pairs[$kv[0]] = $kv[1] }
$pairs['SwapEffectUpgradeEnable'] = '1'; $pairs['VRROptimizeEnable'] = '1'
Set-Reg $dxk DirectXUserGlobalSettings ((($pairs.Keys | ForEach-Object { "$_=$($pairs[$_])" }) -join ';') + ';') String
# Windows Update never restarts the PC by itself while someone is signed in (mid-game), and its active hours cover
# the whole gaming day (8:00-2:00) - updates still install; the restart waits for the owner's own
$group = 'restart-block'
$WU = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
Set-Reg "$WU\AU" NoAutoRebootWithLoggedOnUsers 1
Set-Reg $WU SetActiveHours 1
Set-Reg $WU ActiveHoursStart 8
Set-Reg $WU ActiveHoursEnd 2
# The page file: some "debloat" guides turn it off, and games then crash when memory runs short - with none at all,
# Windows manages it again (a size the owner chose is kept; takes effect after a restart)
$group = $null
$cs = Get-CimInstance Win32_ComputerSystem
if ($cs -and -not $cs.AutomaticManagedPagefile -and -not (Get-CimInstance Win32_PageFileSetting)) {
    Save-Original 'pagefile|auto' @{ Automatic = $false }
    Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true }; $changes.Add('page file managed by Windows again (after a restart)')
}
# Bigger event logs (64 MB instead of ~15-20): days of history to diagnose a crash, a freeze or a vanished program
# with, instead of hours (busy PowerShell scripts alone can fill the default Windows PowerShell log in an afternoon)
foreach ($log in 'Application', 'System', 'Windows PowerShell') { Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\$log" MaxSize 67108864 }

# --- Services ---
# SysMain (prefetch) only goes where Windows is on an SSD: on a hard drive it's what makes apps start quicker
$sysHdd = "$((Get-PhysicalDisk | Where-Object DeviceId -eq "$((Get-Partition -DriveLetter C).DiskNumber)").MediaType)" -eq 'HDD'
foreach ($n in @('DiagTrack', 'dmwappushservice', 'SysMain', 'MapsBroker', 'lfsvc', 'TrkWks', 'WSAIFabricSvc', 'PcaSvc', 'RetailDemo') | Where-Object { -not ($sysHdd -and $_ -eq 'SysMain') }) {
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
# AMD's dual-CCD X3D CPUs (Ryzen 9 7900X3D/7950X3D/9900X3D/9950X3D) need the Xbox Game Bar: AMD's driver uses it to
# see that a game runs and to put it on the V-Cache cores - without it games can lose a lot of frame rate
$dualX3D = "$((Get-CimInstance Win32_Processor | Select-Object -First 1).Name)" -match 'Ryzen 9 \d{4}X3D'
if ($dualX3D) { $apps = @($apps | Where-Object { $_ -ne 'Microsoft.XboxGamingOverlay' }) }
# the owner's choices: keep the preinstalled apps ('bloat-apps' off) and/or keep the Xbox Game Bar ('game-bar' off -
# brought back once from the Microsoft Store if the kit had removed it)
if (-not (Want 'bloat-apps')) { $apps = @($apps | Where-Object { $_ -eq 'Microsoft.XboxGamingOverlay' }) }
if (-not (Want 'game-bar')) {
    $apps = @($apps | Where-Object { $_ -ne 'Microsoft.XboxGamingOverlay' })
    if ($bk.ContainsKey('app|Microsoft.XboxGamingOverlay') -and -not (Get-AppxPackage Microsoft.XboxGamingOverlay)) {
        Undo-Once 'game-bar' { $null = winget install --id 9NZKPSTSNW4P --source msstore --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 } 'Xbox Game Bar reinstalled (your choice)'
    }
} else { Redo 'game-bar' }
foreach ($a in $apps) {
    $pkg = Get-AppxPackage -AllUsers $a
    if ($pkg) {
        Save-Original "app|$a" @{ Name = ($pkg | Select-Object -First 1).Name; Removed = (Get-Date).ToString('d') }   # can't be put back automatically (Microsoft Store)
        $pkg | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers }
        $changes.Add("app $a removed")
        Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $a | ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName | Out-Null }
    }
}

# --- Power: part of the guard because chipset/graphics driver installers and Windows feature updates switch it back.
# A desktop: Ultimate Performance (made from Windows' own template under a fixed id - found in any language), no USB
# sleep, no hibernation. A laptop (a battery): Balanced kept - Ultimate would drain it - with hibernation (a flat
# battery saves open work), and flat out when plugged in (processor 100%, "Best performance", no USB sleep). ---
# the plugged-in value of a setting: of the last two "...: 0x..." lines (plugged in, then battery) - by position, since the
# labels are translated on non-English Windows
function Get-AcIndex($Sub, $Setting) { $v = @(powercfg /q SCHEME_CURRENT $Sub $Setting | Where-Object { $_ -match ':\s*0x[0-9a-fA-F]{8}\s*$' }); if ($v.Count -ge 2 -and $v[-2] -match '0x([0-9a-fA-F]{8})') { [Convert]::ToInt32($Matches[1], 16) } }
$usbSub = '2a737441-1930-4402-8d77-b2bebba308a3'; $usbSet = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
$active = if ("$(powercfg /getactivescheme)" -match '([0-9a-fA-F-]{36})') { $Matches[1].ToLower() }
$laptop = [bool]((Get-CimInstance Win32_Battery) -or $env:PCKIT_TEST_BATTERY -eq '1')   # (PCKIT_TEST_BATTERY: the Windows Sandbox laptop test)
# the owner's choices: their own power plan ('power-plan' off: the one from before the kit, once) and hibernation
# on a desktop ('hibernation' off: turned back on, once)
if (-not (Want 'power-plan')) {
    if ($bk['plan|active'].Guid) { Undo-Once 'power-plan' { powercfg /setactive $bk['plan|active'].Guid } 'power plan back to the one from before (your choice)' }
} else { Redo 'power-plan' }
if (-not $laptop -and -not (Want 'hibernation')) { Undo-Once 'hibernation' { powercfg /hibernate on } 'hibernation back on (your choice)' } else { Redo 'hibernation' }
$group = 'power-plan'
if (-not (Want 'power-plan')) { if ($laptop) { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' ActiveOverlayAcPowerScheme 'ded574b5-45a0-4f42-8737-46345c09c238' String } }   # (off: Set-Reg puts it back)
elseif ($laptop) {
    $bal = '381b4222-f694-41f0-9685-ff5bb260df2e'
    if ($active -ne $bal) { Save-Original 'plan|active' @{ Guid = $active }; powercfg /setactive $bal; $changes.Add('power plan Balanced (a laptop)') }
    if ((Get-AcIndex '54533251-82be-4824-96c1-47b60b740d00' '893dee8e-2bef-41e0-89c6-b55d0929964c') -ne 100) {
        powercfg /setacvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 893dee8e-2bef-41e0-89c6-b55d0929964c 100; powercfg /setactive SCHEME_CURRENT; $changes.Add('processor at full speed when plugged in')
    }
    if ((Get-AcIndex $usbSub $usbSet) -ne 0) { powercfg /setacvalueindex SCHEME_CURRENT $usbSub $usbSet 0; powercfg /setactive SCHEME_CURRENT; $changes.Add('USB sleep off when plugged in') }
    # Settings > Power mode "Best performance" when plugged in (Windows keeps it here; there's no powercfg switch)
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' ActiveOverlayAcPowerScheme 'ded574b5-45a0-4f42-8737-46345c09c238' String
}
else {
    $ult = '99999999-9999-9999-9999-999999999999'
    if ("$(powercfg /list)" -notmatch $ult) { powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 $ult | Out-Null }
    if ($active -ne $ult) { Save-Original 'plan|active' @{ Guid = $active }; powercfg /setactive $ult; $changes.Add('power plan Ultimate Performance') }
    if ((Get-AcIndex $usbSub $usbSet) -ne 0) { powercfg /setacvalueindex SCHEME_CURRENT $usbSub $usbSet 0; powercfg /setactive SCHEME_CURRENT; $changes.Add('USB sleep off') }
}
$group = $null
if (-not $laptop -and (Want 'hibernation') -and (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled).HibernateEnabled -ne 0) { powercfg /hibernate off; $changes.Add('hibernation off') }

# --- OneDrive: a feature update can bring it back - removed again (its sync is also off by policy, above) ---
$od = @("$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe", "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe") | Where-Object { Test-Path $_ }
if (-not (Want 'onedrive')) {   # the owner wants OneDrive: back once (winget), its sync allowed again (the policy, above)
    if (-not $od) { Undo-Once 'onedrive' { $null = winget install --id Microsoft.OneDrive -e --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 } 'OneDrive reinstalled (your choice)' }
}
elseif ($od) {
    Redo 'onedrive'
    Get-Process OneDrive | Stop-Process -Force
    foreach ($o in "$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe", (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\OneDrive\*\OneDriveSetup.exe").FullName, (Get-ChildItem "$env:ProgramFiles\Microsoft OneDrive\*\OneDriveSetup.exe").FullName) {
        if ($o -and (Test-Path $o)) { Start-Process $o '/uninstall' -Wait; break }
    }
    Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name OneDrive
    $changes.Add('OneDrive removed')
}

# --- Start-up clutter: vendor updaters, promo tools and OEM "assistants" that start with Windows for nothing -
# turned off the way Task Manager does it (StartupApproved), so they're still installed and can be turned back on in
# Task Manager > Startup apps. Never games, launchers, chat, audio, RGB or mouse/keyboard software. ---
$clutter = '^(AdobeGCInvoker(-1\.0)?|Adobe ARM|AdobeAAMUpdater-1\.0|Adobe Acrobat Synchronizer|Adobe Updater Startup Utility|SunJavaUpdateSched|jusched|CCleaner.*|' +
    'Avast.*Browser.*Update.*|McAfee ?WebAdvisor|WebAdvisor|AsusUpdate.*|ASUS ?(Live ?Update|Promo).*|ArmouryCrate\.(Update|Notif).*|MSI ?(Live ?Update|Promo).*|' +
    'GigabyteUpdateService|HP ?(JumpStart|Registration|Support Solutions).*|Dell ?SupportAssist.*|Lenovo ?(Welcome|Notification).*|Opera Browser Assistant|Skype.*|Cortana)$'
if (-not (Want 'startup-clutter')) {   # the owner wants them: each one the kit turned off goes back on, once
    $sus = @($bk.Keys | Where-Object { $_ -like 'startup|*' })
    if ($sus) {
        Undo-Once 'startup-clutter' {
            foreach ($k in $sus) { $p = $k -split '\|'; $o = $bk[$k]
                if ($o.Existed -and $o.Value) { Set-ItemProperty -Path $p[1] -Name $p[2] -Value ([Convert]::FromBase64String($o.Value)) -Type Binary } else { Remove-ItemProperty -Path $p[1] -Name $p[2] } }
        } "start-up items back on (your choice): $(($sus | ForEach-Object { ($_ -split '\|')[2] }) -join ', ')"
    }
} else { Redo 'startup-clutter' }
if (Want 'startup-clutter') { foreach ($r in @(@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'),
        @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'),
        @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'))) {
    $run = Get-Item $r[0]; if (-not $run) { continue }
    foreach ($n in @($run.Property | Where-Object { $_ -match $clutter })) {
        $cur = (Get-ItemProperty -Path $r[1] -Name $n).$n
        if ($cur -and ($cur[0] -band 1)) { continue }   # already off (odd first byte = disabled)
        Save-Original "startup|$($r[1])|$n" @{ Existed = $null -ne $cur; Value = $(if ($cur) { [Convert]::ToBase64String([byte[]]$cur) }) }
        if (-not (Test-Path $r[1])) { New-Item $r[1] -Force | Out-Null }
        Set-ItemProperty -Path $r[1] -Name $n -Value ([byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes((Get-Date).ToFileTime()))) -Type Binary
        $changes.Add("start-up item $n off")
    }
} }

# --- Devices: no power-saving on controllers and wired network ---
# game controllers: Xbox (045E), PlayStation (054C), Nintendo (057E), 8BitDo (2DC8), Hori (0F0D), PowerA (20D6), PDP (0E6F)
foreach ($d in Get-CimInstance -Namespace root\wmi MSPower_DeviceEnable | Where-Object { $_.Enable -and $_.InstanceName -match 'VID_(045E|054C|057E|2DC8|0F0D|20D6|0E6F)' }) {
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

# a desktop on Wi-Fi: no power-saving on the Wi-Fi adapter either (it causes lag spikes); laptops keep it (the battery)
if (-not $laptop) {
    foreach ($nic in Get-NetAdapter -Physical | Where-Object { $_.NdisPhysicalMedium -eq 9 }) {   # 9 = native 802.11
        foreach ($d in Get-CimInstance -Namespace root\wmi MSPower_DeviceEnable | Where-Object { $_.Enable -and $_.InstanceName -like "$($nic.PnPDeviceID)*" }) {
            Save-Original "power|$($d.InstanceName)" @{ Enable = $true }
            Set-CimInstance -InputObject $d -Property @{ Enable = $false }; $changes.Add('Wi-Fi power-saving off')
        }
    }
}

if ($bkDirty) {
    New-Item (Split-Path $bkFile) -ItemType Directory -Force | Out-Null
    $bk | ConvertTo-Json -Depth 4 | Set-Content "$bkFile.tmp" -Encoding utf8
    Move-Item "$bkFile.tmp" $bkFile -Force
}
try { $tmx.ReleaseMutex() } catch { }
$changes | Select-Object -Unique
