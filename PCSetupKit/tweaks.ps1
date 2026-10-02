# PC Setup Kit - Windows 11 debloat + performance tweaks.
# Idempotent: only changes what differs from the target and prints one line per change, so it is used both
# by setup.ps1 at first logon and by health-check.ps1 as a "tweak guard" after Windows updates.
# Must run elevated, as the user who owns the PC (HKCU settings apply to that user).
# -Quick: setup's first run - the slow parts (the old Windows parts, via DISM) wait for the first maintenance
param([switch]$Quick)
$ErrorActionPreference = 'SilentlyContinue'
# where it is, for whoever runs it with a time limit (setup.ps1): PCKIT_TWEAKS_TRACE names the file - a hang names itself
# (and the originals recorded so far are saved: a run stopped halfway - setup's time limit - still leaves the uninstaller
# everything it changed; 10/2 on GitHub a stopped run had saved none)
function Trace([string]$Where) { Save-Backup; if ($env:PCKIT_TWEAKS_TRACE) { try { Add-Content $env:PCKIT_TWEAKS_TRACE "$((Get-Date).ToString('T')) $Where" } catch { } } }
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
function Save-Backup {
    if (-not $script:bkDirty) { return }
    New-Item (Split-Path $bkFile) -ItemType Directory -Force | Out-Null
    $bk | ConvertTo-Json -Depth 4 | Set-Content "$bkFile.tmp" -Encoding utf8
    Move-Item "$bkFile.tmp" $bkFile -Force; $script:bkDirty = $false
}
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

Trace 'Telemetry, ads, suggestions, AI features'
# --- Telemetry, ads, suggestions, AI features ---
$group = 'telemetry'
$pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows'   # (not $P: a later $p is the same variable in PowerShell)
Set-Reg "$pol\DataCollection" AllowTelemetry 0
Set-Reg "$pol\DataCollection" DoNotShowFeedbackNotifications 1
Set-Reg "$pol\CloudContent" DisableWindowsConsumerFeatures 1
Set-Reg "$pol\CloudContent" DisableSoftLanding 1
Set-Reg "$pol\CloudContent" DisableCloudOptimizedContent 1
Set-Reg "$pol\CloudContent" DisableTailoredExperiencesWithDiagnosticData 1
Set-Reg "$pol\System" EnableActivityFeed 0
Set-Reg "$pol\System" PublishUserActivities 0
Set-Reg "$pol\System" UploadUserActivities 0
Set-Reg "$pol\AdvertisingInfo" DisabledByGroupPolicy 1
Set-Reg "$pol\Windows Search" AllowCortana 0
Set-Reg "$pol\Windows Search" DisableWebSearch 1
Set-Reg "$pol\Windows Search" ConnectedSearchUseWeb 0
Set-Reg "$pol\WindowsCopilot" TurnOffWindowsCopilot 1
Set-Reg "$pol\WindowsAI" DisableAIDataAnalysis 1
Set-Reg "$pol\WindowsAI" DisableClickToDo 1
Set-Reg "$pol\WindowsAI" TurnOffSavingSnapshots 1
$group = 'onedrive'; Set-Reg "$pol\OneDrive" DisableFileSyncNGSC 1; $group = 'telemetry'
Set-Reg "$pol\DeliveryOptimization" DODownloadMode 1              # update sharing only with this home network
$group = 'game-recording'; Set-Reg "$pol\GameDVR" AllowGameDVR 0; $group = 'telemetry'
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' AllowNewsAndInterests 0   # Widgets
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' StartupBoostEnabled 0    # Edge stays (apps need WebView2) but stays out of the way
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' BackgroundModeEnabled 0
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' HubsSidebarEnabled 0
Set-Reg "$pol\Windows Error Reporting" DontSendAdditionalData 1   # crash reports stay local (kept on so blue screens can be diagnosed)

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

Trace 'Taskbar / Start / look'
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

Trace 'Gaming / performance'
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
# The big yearly Windows upgrade (a new version, e.g. 24H2 > 25H2) comes 45 days after its release, once the first
# problems are fixed; security and monthly updates keep coming right away. (Windows Pro and up; Home ignores it.)
$group = 'feature-delay'
Set-Reg $WU DeferFeatureUpdates 1
Set-Reg $WU DeferFeatureUpdatesPeriodInDays 45
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

Trace 'Services'
# --- Services ---
# SysMain (prefetch) only goes where Windows is on an SSD: on a hard drive it's what makes apps start quicker
$sysHdd = "$((Get-PhysicalDisk | Where-Object DeviceId -eq "$((Get-Partition -DriveLetter C -ErrorAction SilentlyContinue).DiskNumber)").MediaType)" -eq 'HDD'
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

Trace 'Scheduled tasks'
# --- Scheduled tasks (telemetry, feedback, compatibility scans) ---
$tasks = '\Microsoft\Windows\Application Experience\MareBackup', '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp', '\Microsoft\Windows\Application Experience\PcaPatchDbTask',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater', '\Microsoft\Windows\Application Experience\StartupAppTask',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator', '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\Diagnosis\RecommendedTroubleshootingScanner', '\Microsoft\Windows\Diagnosis\Scheduled',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector', '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload', '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataFlushing',
    '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReceiver', '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReporting',
    '\Microsoft\Windows\Flighting\FeatureConfig\GovernedFeatureUsageProcessing', '\Microsoft\Windows\Maintenance\WinSAT',
    '\Microsoft\Windows\Maps\MapsToastTask', '\Microsoft\Windows\Maps\MapsUpdateTask', '\Microsoft\Windows\PerformanceTrace\ShowFeedbackToast',
    '\Microsoft\Windows\Shell\FamilySafetyRefreshTask', '\Microsoft\Windows\Shell\FamilySafetyMonitor',
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting', '\Microsoft\Windows\WwanSvc\NotificationTask',
    # found still on by the 10/2 audit: more telemetry (device census, usage insights, "sustainability" reporting), the
    # settings-experiment sync, and the model downloads for Click to Do - which the kit turns off anyway
    '\Microsoft\Windows\Device Information\Device', '\Microsoft\Windows\Device Information\Device User',
    '\Microsoft\Windows\UsageAndQualityInsights\UsageAndQualityInsights-MaintenanceTask', '\Microsoft\Windows\Sustainability\SustainabilityTelemetry',
    '\Microsoft\Windows\Sustainability\PowerGridForecastTask', '\Microsoft\Windows\Flighting\OneSettings\RefreshCache',
    '\Microsoft\Windows\WindowsAI\ClickToDo\ModelCachingLimit', '\Microsoft\Windows\WindowsAI\ClickToDo\ModelCachingUpdate',
    '\GoogleUserPEH\RunPlatformExperienceHelper_Daily'   # (Chrome's "tips" pop-ups; Chrome's own updates are a separate task and stay)
foreach ($t in Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' -and ($_.TaskPath + $_.TaskName) -in $tasks }) {
    Save-Original "task|$($t.TaskPath)$($t.TaskName)" @{ Enabled = $true }; $t | Disable-ScheduledTask | Out-Null; $changes.Add("task $($t.TaskName) off")
}
foreach ($t in Get-ScheduledTask | Where-Object { $_.TaskName -match 'AsrAPPShop|ArmouryCrate.*Update|MSI.*LiveUpdate' -and $_.TaskPath -eq '\' }) {
    Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false; $changes.Add("motherboard installer task $($t.TaskName) removed")
}

Trace 'Preinstalled apps'
# --- Preinstalled apps (current user, all users, and new users) ---
$apps = 'Microsoft.Copilot', 'Microsoft.Windows.Ai.Copilot.Provider', 'MicrosoftWindows.Client.WebExperience', 'Microsoft.WidgetsPlatformRuntime',
    'Microsoft.StartExperiencesApp', 'MicrosoftWindows.CrossDevice', 'Microsoft.YourPhone', 'Microsoft.BingNews', 'Microsoft.BingWeather',
    'Microsoft.BingSearch', 'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.People',
    'Microsoft.PowerAutomateDesktop', 'Microsoft.Todos', 'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps', 'Microsoft.ZuneMusic',
    'Microsoft.ZuneVideo', 'Clipchamp.Clipchamp', 'MicrosoftCorporationII.QuickAssist', 'MicrosoftCorporationII.MicrosoftFamily',
    'Microsoft.OutlookForWindows', 'MSTeams', 'MicrosoftTeams', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.Office.OneNote',
    'Microsoft.MicrosoftStickyNotes', 'Microsoft.WindowsAlarms', 'Microsoft.WindowsSoundRecorder', 'Microsoft.549981C3F5F10',
    'Microsoft.Windows.DevHome', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.MixedReality.Portal', 'Microsoft.Wallet',
    'Microsoft.Microsoft3DViewer', 'Microsoft.SkypeApp', 'Microsoft.LinkedIn', 'SpotifyAB.SpotifyMusic', 'Disney.37853FC22B2CE',
    'Facebook.Facebook', 'Facebook.Instagram', 'BytedancePte.Ltd.TikTok', '5319275A.WhatsAppDesktop', 'AmazonVideo.PrimeVideo',
    # older Windows images and PC makers' extras (a new Windows 11 has none of them - removed where they are)
    'Microsoft.BingFinance', 'Microsoft.BingSports', 'Microsoft.BingTravel', 'Microsoft.BingHealthAndFitness', 'Microsoft.BingFoodAndDrink',
    'Microsoft.News', 'Microsoft.Messaging', 'Microsoft.OneConnect', 'Microsoft.Print3D', 'Microsoft.MSPaint', 'Microsoft.Office.Sway',
    'Microsoft.NetworkSpeedTest', 'microsoft.windowscommunicationsapps', 'Microsoft.MicrosoftPCManager', 'Microsoft.MicrosoftJournal',
    'king.com.CandyCrushSaga', 'king.com.CandyCrushSodaSaga', 'king.com.BubbleWitch3Saga'   # (Microsoft.MSPaint is Paint 3D - Paint itself stays)
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

Trace 'Old Windows parts'
# --- Old Windows parts - what tiny11 removes too, but never what Windows needs to update and repair itself (its component
# store, recovery, Defender - tiny11 "core" deletes those, and then no security update installs again): Internet
# Explorer's engine, the legacy Media Player, WordPad, Steps Recorder, the math input recognizer, the XPS viewer;
# PowerShell 2.0 (an old way around PowerShell's security) and Recall off; Windows' reserved storage (about 7 GB kept
# for updates - they use free space instead). Newer Windows versions come without most of them. Slow (DISM): not during
# setup (-Quick: the first maintenance does it minutes later), and checked again only on a new Windows build (a feature
# update can bring them back) ---
$group = 'legacy'
$build = "$([Environment]::OSVersion.Version.Build)"
$legacyCaps = 'Browser.InternetExplorer', 'Media.WindowsMediaPlayer', 'Microsoft.Windows.WordPad', 'App.StepsRecorder', 'MathRecognizer', 'XPS.Viewer',
    'Microsoft.Windows.PowerShell.ISE', 'Microsoft.Wallpapers.Extended', 'Language.Speech'   # (kept: handwriting - pen laptops; text-to-speech - Narrator; face sign-in)
$legacyFeats = 'MicrosoftWindowsPowerShellV2Root', 'MicrosoftWindowsPowerShellV2', 'Recall'
if (Want 'legacy') {
    Redo 'legacy'
    if (-not $Quick -and "$($bk['legacy|build'].Build)" -ne $build) {
        $all = $true
        # (another servicing job - the first maintenance's own DISM cleanup runs alongside - holds Windows' servicing lock and
        # a removal is refused: waited for and tried again, 8 minutes (16 x 30 s) at most in all; 9/30 on GitHub only 1 of 9 went at first)
        $waits = 0
        foreach ($c in @(Get-WindowsCapability -Online | Where-Object { $_.State -eq 'Installed' -and ($_.Name -split '~')[0] -in $legacyCaps })) {
            for ($try = 0; ; $try++) {
                Remove-WindowsCapability -Online -Name $c.Name | Out-Null
                if ((Get-WindowsCapability -Online -Name $c.Name).State -ne 'Installed' -or $waits -ge 16) { break }
                Start-Sleep 30; $waits++
            }
            if ((Get-WindowsCapability -Online -Name $c.Name).State -ne 'Installed') { Save-Original "cap|$($c.Name)" @{ Installed = $true }; $changes.Add("old Windows part $(($c.Name -split '~')[0]) removed") } else { $all = $false }
        }
        foreach ($f in @(Get-WindowsOptionalFeature -Online | Where-Object { $_.State -eq 'Enabled' -and $_.FeatureName -in $legacyFeats })) {
            Disable-WindowsOptionalFeature -Online -FeatureName $f.FeatureName -NoRestart -WarningAction SilentlyContinue | Out-Null
            Save-Original "feature|$($f.FeatureName)" @{ Enabled = $true }; $changes.Add("Windows feature $($f.FeatureName) off")
        }
        if ("$((Get-WindowsReservedStorageState).ReservedStorageState)" -eq 'Enabled') {   # (an enum: the same in every language)
            Set-WindowsReservedStorageState -State Disabled | Out-Null   # (refused while an update is being installed: tried again next time)
            if ("$((Get-WindowsReservedStorageState).ReservedStorageState)" -eq 'Disabled') { Save-Original 'reserved|storage' @{ Enabled = $true }; $changes.Add('reserved storage off (about 7 GB free again)') } else { $all = $false }
        }
        if ($all) { $bk['legacy|build'] = @{ Build = $build }; $script:bkDirty = $true }   # (anything refused: tried again at the next check)
    }
} else {
    # the owner wants them: each one the kit removed comes back (from Windows Update), once
    Undo-Once 'legacy' {
        foreach ($n in @($bk.Keys | Where-Object { $_ -like 'cap|*' })) { Add-WindowsCapability -Online -Name $n.Substring(4) | Out-Null }
        foreach ($n in @($bk.Keys | Where-Object { $_ -like 'feature|*' })) { Enable-WindowsOptionalFeature -Online -FeatureName $n.Substring(8) -NoRestart -WarningAction SilentlyContinue | Out-Null }
        if ($bk.ContainsKey('reserved|storage')) { Set-WindowsReservedStorageState -State Enabled | Out-Null }
    } 'old Windows parts back (your choice)'
    if ($bk.ContainsKey('legacy|build')) { $bk.Remove('legacy|build'); $script:bkDirty = $true }
}
$group = $null
Trace 'Power'
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

Trace 'OneDrive'
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
# OneDrive's first-sign-in installer also sits in Windows' own service accounts (LocalService, NetworkService, the default
# profile): it'd install OneDrive for them - gone too (the 10/2 audit; tiny11 does the same)
if (Want 'onedrive') {
    foreach ($h in 'S-1-5-19', 'S-1-5-20', '.DEFAULT') {
        $rk = "Registry::HKEY_USERS\$h\Software\Microsoft\Windows\CurrentVersion\Run"
        if ($null -ne (Get-ItemProperty -Path $rk -Name OneDriveSetup).OneDriveSetup) { Remove-ItemProperty -Path $rk -Name OneDriveSetup; $changes.Add("OneDrive setup entry removed ($h)") }
    }
}

Trace 'Start-up clutter'
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

Trace 'Edge'
# --- Edge: it stays (Windows and many apps show their pages with it - WebView2 - and Windows Update puts a removed Edge
# back), but out of the way: no desktop icon (not after its own updates either), not pinned to the taskbar, no first-run
# pages or "make Edge your default" prompts. (The default browser can't be switched by a program on a home PC - Windows 11
# ignores its default-apps policy outside company domains and blocks everything else: Messiah's Welcome page has the
# one-click way, Windows' own Chrome page - the VM test, 9/30) ---
$group = 'edge'
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' HideFirstRunExperience 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' DefaultBrowserSettingEnabled 0
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' CreateDesktopShortcutDefault 0
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'CreateDesktopShortcut{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}' 0   # (Edge's own id)
# (tests: the icons and the pins live in PCKIT_EDGE_ROOT - never this PC's; none set: not touched)
$er = $env:PCKIT_EDGE_ROOT; $edgeFiles = -not $env:PCKIT_IN_TESTS -or $er
$edgeIcons = if ($er) { "$er\public\Microsoft Edge.lnk", "$er\desktop\Microsoft Edge.lnk" } else { "$env:PUBLIC\Desktop\Microsoft Edge.lnk", "$([Environment]::GetFolderPath('Desktop'))\Microsoft Edge.lnk" }
$pinned = if ($er) { "$er\pinned" } else { "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar" }
if (-not $edgeFiles) { }
elseif (Want 'edge') {
    Redo 'edge'
    foreach ($l in $edgeIcons) { if (Test-Path -LiteralPath $l) { Save-Original 'edge|desktop' @{ Removed = (Get-Date).ToString('d') }; [IO.File]::Delete($l); $changes.Add('Edge desktop icon removed') } }
    # (only with a desktop shell in this session: without one the shell's unpin can wait forever - a service, a test machine)
    if ((Test-Path -LiteralPath "$pinned\Microsoft Edge.lnk") -and (Get-Process explorer -ErrorAction SilentlyContinue | Where-Object SessionId -eq (Get-Process -Id $PID).SessionId)) {
        # (Windows 11 lets a program unpin, not pin: the taskbar's own "Unpin" on the pinned shortcut)
        # (in a process of its own, 30 seconds at most: the shell's verb can wait forever - 10/2 on GitHub it held setup for 20 minutes)
        $up = "try { (New-Object -ComObject Shell.Application).Namespace('$($pinned.Replace("'", "''"))').ParseName('Microsoft Edge.lnk').InvokeVerb('taskbarunpin') } catch { }"
        $upp = Start-Process powershell -ArgumentList '-NoProfile', '-STA', '-Command', $up -WindowStyle Hidden -PassThru
        if ($upp -and -not $upp.WaitForExit(30000)) { try { $upp.Kill() } catch { } }
        if (-not (Test-Path -LiteralPath "$pinned\Microsoft Edge.lnk")) { Save-Original 'edge|pinned' @{ Removed = (Get-Date).ToString('d') }; $changes.Add('Edge unpinned from the taskbar') }
    }
} else {
    # the owner wants Edge as it was: its desktop icon back (a pin can't be put back by a program - right-click Edge in Start)
    Undo-Once 'edge' {
        $exe = if ($er) { "$er\msedge.exe" } else { "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" }
        if ($bk.ContainsKey('edge|desktop') -and (Test-Path $exe)) { $s = (New-Object -ComObject WScript.Shell).CreateShortcut($edgeIcons[0]); $s.TargetPath = $exe; $s.Save() }
    } 'Edge back as it was (your choice)'
}
$group = $null

Trace 'The install USBs Start pins'
# --- The install USB's Start pins (make-usb.ps1: Windows' Start-pins policy, marked PCKit=1) are applied by now: the policy
# goes, so the pins are the owner's to change (while it stays, Windows would put them back). Anyone else's policy stays. ---
$sp = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start'
if (-not $Quick -and (Get-ItemProperty $sp -Name PCKit).PCKit -eq 1) {
    foreach ($n in 'ConfigureStartPins', 'ConfigureStartPins_ProviderSet', 'ConfigureStartPins_WinningProvider', 'PCKit') { Remove-ItemProperty $sp -Name $n }
    Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\PolicyManager\providers\B5292708-1619-419B-9923-E5D9F3925E71\default\Device\Start' -Name ConfigureStartPins
    $changes.Add('Start pins from the install USB kept - yours to change now')
}

Trace 'Devices'
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

Trace 'done'
Save-Backup
try { $tmx.ReleaseMutex() } catch { }
$changes | Select-Object -Unique
