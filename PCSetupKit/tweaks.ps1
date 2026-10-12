# PC Setup Kit - Windows 11 debloat + performance tweaks.
# Idempotent: only changes what differs from the target and prints one line per change, so it is used both
# by setup.ps1 at first logon and by health-check.ps1 as a "tweak guard" after Windows updates.
# Must run elevated, as the user who owns the PC (HKCU settings apply to that user).
# -Quick: setup's first run - the slow parts (the old Windows parts, via DISM) wait for the first maintenance
# -Audit: a preview that changes nothing - every command that would change something is swapped for a stand-in that does
#   nothing, and the run lists what it WOULD change ("Would: ..."), what Windows refuses, and how much is already in place.
#   (tests/unit/tweaks.ps1 checks that every changing command used in this file is on the list below)
# -StatusFile: where this run's result per switch (group) - or per section, for what has none - is written as JSON: how
#   many settings were already in place, what had to be put back, what Windows refuses (the app's Status tab)
# -Cause: what most likely changed things back since the last pass (update-cause.ps1: a Windows update, a driver install) -
#   kept with each change in the history and in the status
param([switch]$Quick, [switch]$Audit, [string]$StatusFile, [string]$Cause)
$ErrorActionPreference = 'SilentlyContinue'
$auditSame = 0; $auditBlocked = 0
if ($Audit) {
    $writeCmds = 'Set-ItemProperty', 'Remove-ItemProperty', 'New-Item', 'Remove-Item', 'Move-Item', 'Set-Content', 'Add-Content', 'Set-Service',
        'Stop-Service', 'Start-Service', 'Stop-Process', 'Start-Process', 'Disable-ScheduledTask', 'Enable-ScheduledTask', 'Unregister-ScheduledTask',
        'Remove-AppxPackage', 'Remove-AppxProvisionedPackage', 'Remove-WindowsCapability', 'Add-WindowsCapability', 'Disable-WindowsOptionalFeature',
        'Enable-WindowsOptionalFeature', 'Set-WindowsReservedStorageState', 'Set-CimInstance', 'Set-NetAdapterAdvancedProperty', 'Set-Acl', 'winget'
    foreach ($c in $writeCmds) { Set-Item "function:script:$c" ([scriptblock]::Create('$input | Out-Null')) }
    # powercfg: its questions are answered, its changes aren't made - by whichever powercfg was there before (the real one;
    # the tests' stand-in under tests - 10/12 on GitHub the preview asked the real one and saw the runner's own plan)
    $pcAsk = Get-Command powercfg -CommandType Function -ErrorAction SilentlyContinue
    $script:pcAsk = if ($pcAsk) { $pcAsk.ScriptBlock } else { "$env:SystemRoot\System32\powercfg.exe" }
    function script:powercfg { if ("$args" -match '^/(getactivescheme|list|q)\b') { & $script:pcAsk @args } }
}
# where it is, for whoever runs it with a time limit (setup.ps1): PCKIT_TWEAKS_TRACE names the file - a hang names itself
# (and the originals recorded so far are saved: a run stopped halfway - setup's time limit - still leaves the uninstaller
# everything it changed; 10/2 on GitHub a stopped run had saved none)
function Trace([string]$Where) { Save-Backup; Close-Section; $script:section = $Where; if ($env:PCKIT_TWEAKS_TRACE) { try { Add-Content $env:PCKIT_TWEAKS_TRACE "$((Get-Date).ToString('T')) $Where" } catch { } } }
$changes = New-Object System.Collections.Generic.List[string]
# the status per switch (-StatusFile): Set-Reg counts its own under its group (or "#<section>" without one); everything
# else a section changed or found refused is counted for the section when the next one starts (Close-Section)
$stat = @{}; $section = ''; $secMark = 0; $secBlocked = 0; $regBlocked = 0
function Add-Stat([string]$Key, [string]$What, [string]$Text, [string]$Name) {   # -Name: the setting (the Status tab lists what each switch checks)
    if (-not $stat.ContainsKey($Key)) { $stat[$Key] = @{ same = 0; fixed = @(); blocked = 0; names = @() } }
    if ($What -eq 'fixed') { $stat[$Key].fixed += $Text } else { $stat[$Key][$What]++ }
    if ($Name -and $Name -notin $stat[$Key].names) { $stat[$Key].names += $Name }
}
function Get-StatKey { if ($script:group) { $script:group } else { "#$script:section" } }
function Close-Section {
    for ($i = $script:secMark; $i -lt $changes.Count; $i++) { if ($changes[$i] -notmatch '^setting ') { Add-Stat "#$script:section" 'fixed' $changes[$i] } }
    $nb = ($script:auditBlocked - $script:secBlocked) - $script:regBlocked
    if ($nb -gt 0 -and $script:section) { for ($i = 0; $i -lt $nb; $i++) { Add-Stat "#$script:section" 'blocked' } }
    $script:secMark = $changes.Count; $script:secBlocked = $script:auditBlocked; $script:regBlocked = 0
}
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
# Opt-in groups are off until the owner turns them on ("tweak.<group>=on"): bigger changes not everyone wants
$on = @(Get-Content $optFile | Where-Object { $_ -match '^\s*tweak\.([\w-]+)\s*=\s*on\s*$' } | ForEach-Object { $Matches[1] })
$optIn = @('edge-remove', 'notifications-off', 'sysmain-off')
# Values the owner keeps their own way, one setting at a time (the app: a Status row's history > "Keep ..."): kit-options.txt
# "keep.<key>\<name>=<value>" ("(not set)": no value) - held at that value instead of Messiah's, also after updates
$keep = @{}; foreach ($kl in @(Get-Content $optFile)) { if ($kl -match '^\s*keep\.(.+?)=(.*)$') { $keep[$Matches[1].Trim()] = $Matches[2] } }
function Want([string]$Group) { if ($Group -in $optIn) { return $Group -in $on }; -not $Group -or $Group -notin $off }
$group = $null   # the group the next settings belong to (none: always applied)
# once per group turned off (reinstalling an app, turning hibernation back on): 'undone|<group>' in the backup file,
# cleared when the group is turned on again
function Undo-Once([string]$Group, [scriptblock]$Action, [string]$Said) {
    if ($bk.ContainsKey("undone|$Group")) { return }
    if (-not $Audit) { & $Action }; $bk["undone|$Group"] = @{ Date = (Get-Date).ToString('o') }; $script:bkDirty = $true; $changes.Add($Said)
}
function Redo([string]$Group) { if ($bk.ContainsKey("undone|$Group")) { $bk.Remove("undone|$Group"); $script:bkDirty = $true } }

# Change history (C:\PCSetupKit\change-history.log, next to the originals): every change with its before and after
# value, so "what did Messiah change, and when did Windows undo it" has an answer (written at the end of the run)
$changeLog = New-Object System.Collections.Generic.List[string]
function Note-Change([string]$What) { $changeLog.Add("$((Get-Date).ToString('yyyy-MM-dd HH:mm'))  $What$(if ($Cause -and $What -notmatch 'your choice') { " [after $Cause]" })") }
function Set-Reg($Path, $Name, $Value, $Type = 'DWord') {
    $cur = (Get-ItemProperty -Path $Path -Name $Name).$Name
    if (-not (Want $script:group)) {
        # turned off by the owner: back to the original (only if the kit had changed it)
        $o = $bk["reg|$Path|$Name"]; if (-not $o) { return }
        if ($o.Existed) { if ("$cur" -ne "$($o.Value)") { Set-ItemProperty -Path $Path -Name $Name -Value $o.Value -Type $(if ($o.Kind) { $o.Kind } else { 'DWord' }); Note-Change "$Path\$Name '$cur' -> '$($o.Value)' (your choice)"; $changes.Add("setting $Name back (your choice)") } }
        elseif ($null -ne (Get-ItemProperty -Path $Path -Name $Name)) { Remove-ItemProperty -Path $Path -Name $Name; Note-Change "$Path\$Name '$cur' -> (not set) (your choice)"; $changes.Add("setting $Name back (your choice)") }
        return
    }
    $kk = "$Path\$Name"
    if ($keep.ContainsKey($kk)) {   # kept the owner's way: that value, not Messiah's
        $kv = $keep[$kk]; $had = $null -ne (Get-ItemProperty -Path $Path -Name $Name)
        if ($kv -eq '(not set)') { if ($had) { Remove-ItemProperty -Path $Path -Name $Name; Note-Change "$kk '$cur' -> (not set) (your choice)"; $changes.Add("setting $Name kept as you chose") } }
        elseif ("$cur" -ne $kv) {
            $kind = if ($had) { "$((Get-Item $Path).GetValueKind($Name))" } else { $Type }
            $val = if ($kind -eq 'DWord' -and $kv -match '^\d+$' -and [uint64]$kv -le 4294967295) { [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$kv), 0) } else { $kv }
            if (-not (Test-Path $Path)) { New-Item $Path -Force | Out-Null }
            Set-ItemProperty -Path $Path -Name $Name -Value $val -Type $kind; Note-Change "$kk '$(if ($had) { $cur } else { '(not set)' })' -> '$kv' (your choice)"; $changes.Add("setting $Name kept as you chose")
        }
        Add-Stat (Get-StatKey) 'kept' -Name $kk; return
    }
    if ("$cur" -eq "$Value") { $script:auditSame++; Add-Stat (Get-StatKey) 'same' -Name "$Path\$Name" }
    else {
        # a value Windows refuses to change (its user-choice protection driver, a company policy): said once, tried again
        # on the next Windows build - not "re-applied" at every check (10/10: the Widgets policy on 26200, Winhance #780)
        $bl = $bk["blocked|$Path|$Name"]; if ($bl -and "$($bl.Build)" -eq "$([Environment]::OSVersion.Version.Build)") { $script:auditBlocked++; $script:regBlocked++; Add-Stat (Get-StatKey) 'blocked' -Name "$Path\$Name"; return }
        $had = $null -ne (Get-ItemProperty -Path $Path -Name $Name)
        if ($Audit) { $changes.Add("setting $Name ($Path): '$(if ($had) { $cur } else { '(not set)' })' -> '$Value'"); Add-Stat (Get-StatKey) 'fixed' $Name "$Path\$Name"; return }
        Save-Original "reg|$Path|$Name" @{ Existed = $had; Value = $cur; Kind = $(if ($had) { "$((Get-Item $Path).GetValueKind($Name))" }) }
        if (-not (Test-Path $Path)) { New-Item $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
        if ("$((Get-ItemProperty -Path $Path -Name $Name).$Name)" -ne "$Value") {   # read back: did it take?
            $bk["blocked|$Path|$Name"] = @{ Build = "$([Environment]::OSVersion.Version.Build)" }; $script:bkDirty = $true
            Note-Change "$Path\$Name - blocked by Windows, left at '$cur'"; $changes.Add("setting $Name blocked by Windows (left as it is)"); Add-Stat (Get-StatKey) 'blocked' -Name "$Path\$Name"; return
        }
        if ($bl) { $bk.Remove("blocked|$Path|$Name"); $script:bkDirty = $true }
        Note-Change "$Path\$Name '$(if ($had) { $cur } else { '(not set)' })' -> '$Value'"
        $changes.Add("setting $Name"); Add-Stat (Get-StatKey) 'fixed' $Name "$Path\$Name"
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
Set-Reg "$pol\WindowsAI" AllowRecallEnablement 0
# the AI parts of Notepad and Paint (24H2/25H2: Rewrite, Cocreator, generative fill/erase, background removal) - from
# Win11Debloat's maintained list, 10/10
Set-Reg 'HKLM:\SOFTWARE\Policies\WindowsNotepad' DisableAIFeatures 1
foreach ($n in 'DisableCocreator', 'DisableGenerativeFill', 'DisableImageCreator', 'DisableGenerativeErase', 'DisableRemoveBackground') {
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' $n 1 }
Set-Reg "$pol\CloudContent" DisableConsumerAccountStateContent 1   # Microsoft 365 / Copilot ads on Settings' home page
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
    'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled',
    'SubscribedContent-338393Enabled', 'SubscribedContent-353698Enabled', 'SubscribedContent-338387Enabled') { Set-Reg $CDM $n 0 }   # (last 3: suggestions in Settings and lock-screen tips)
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' ShowSyncProviderNotifications 0   # OneDrive/365 ads in File Explorer
# "suggested" toasts from Windows itself (tips, "finish setting up") - only those; apps' own notifications are their own switch
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested' Enabled 0
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' ScoobeSystemSettingEnabled 0
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' Enabled 0
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' TailoredExperiencesWithDiagnosticDataEnabled 0
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' BingSearchEnabled 0
# every app's notifications off (Discord, calendar, ...): its own switch now, opt-in - no other debloat tool does this by
# default, and it silenced more than the "telemetry" switch said (10/10, the research comparison)
$group = 'notifications-off'
$toast = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications'
Set-Reg $toast ToastEnabled 0
# (set up before the originals were kept: Windows' default - notifications on - once; the owner's own "off" later stays)
if (Want 'notifications-off') { Redo 'notifications-off' }
elseif (-not $bk.ContainsKey("reg|$toast|ToastEnabled") -and (Get-ItemProperty -Path $toast -Name ToastEnabled).ToastEnabled -eq 0) {
    Undo-Once 'notifications-off' { Remove-ItemProperty -Path $toast -Name ToastEnabled } 'app notifications back on (Windows'' default)'
}
$group = 'telemetry'

Trace 'Taskbar / Start / look'
# --- Taskbar / Start / look ---
$group = 'start-menu'
$ADV = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
Set-Reg $ADV ShowCopilotButton 0
Set-Reg $ADV ShowTaskViewButton 0
Set-Reg $ADV Start_IrisRecommendations 0
Set-Reg $ADV Start_TrackDocs 0
Set-Reg $ADV Start_AccountNotifications 0
# "End task" in a program's taskbar right-click menu: a frozen game closes without Task Manager
$group = 'end-task'
Set-Reg "$ADV\TaskbarDeveloperSettings" TaskbarEndTask 1
# File Explorer shows every folder the same way instead of guessing a type from what's inside (the guess reads the files
# first, which makes big folders - game installs, downloads - slow to open)
$group = 'folder-types'
Set-Reg 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell' FolderType 'NotSpecified' String
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
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata' PreventDeviceMetadataFromNetwork 1   # no maker "companion app" downloads for a plugged-in device (drivers still come)
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' CrashDumpEnabled 7                  # keep crash dumps for diagnosis
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' AlwaysKeepMemoryDump 1
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' DisplayParameters 1                 # a blue screen names its error and driver on screen
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' LongPathsEnabled 1                    # paths over 260 characters (deep game mod and tool folders)
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
# ...and not "Get the latest updates as soon as they're available" (the early, optional feature drops)
Set-Reg 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' IsContinuousInnovationOptedIn 0
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
# Each one belongs to a switch, so the owner can turn it back on (10/10: before, only the uninstaller could). SysMain off is
# opt-in: no measurement shows a gain on an SSD, and Atlas - the most speed-minded playbook - keeps it on. DiagTrack goes
# with telemetry (its switch says it can stop Xbox achievements).
$svcGroups = [ordered]@{ DiagTrack = 'telemetry'; dmwappushservice = 'telemetry'; WSAIFabricSvc = 'telemetry'; SysMain = 'sysmain-off'
    MapsBroker = $null; lfsvc = $null; TrkWks = $null; PcaSvc = $null; RetailDemo = $null }
$svcDefault = @{ DiagTrack = 'Automatic'; dmwappushservice = 'Manual'; WSAIFabricSvc = 'Manual'; SysMain = 'Automatic' }   # (Windows 11's own)
foreach ($n in @($svcGroups.Keys) | Where-Object { -not ($sysHdd -and $_ -eq 'SysMain') }) {
    $s = Get-Service $n; if (-not $s) { continue }
    if (Want $svcGroups[$n]) {
        if ($s.StartType -ne 'Disabled') { Save-Original "service|$n" @{ StartType = "$($s.StartType)" }; Stop-Service $n -Force; Set-Service $n -StartupType Disabled; $changes.Add("service $n off") }
    } elseif ($s.StartType -eq 'Disabled') {
        # switched off (or opt-in and never chosen): back to how it was before the kit - or, on a PC set up before the
        # originals were kept, to Windows' own default, once (one the owner turns off by hand afterwards stays off)
        $o = $bk["service|$n"]
        $to = if ($o -and "$($o.StartType)" -notin '', 'Disabled') { $o.StartType } elseif (-not $o -and $svcDefault[$n] -and -not $bk.ContainsKey("undone|service|$n")) { $svcDefault[$n] }
        if (-not $to) { continue }
        Set-Service $n -StartupType $to; if ($to -eq 'Automatic') { Start-Service $n }
        if (-not $o) { $bk["undone|service|$n"] = @{ Date = (Get-Date).ToString('d') }; $script:bkDirty = $true }
        $changes.Add("service $n back to $to $(if ($o) { '(your choice)' } else { '(Windows'' default)' })")
    }
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
# some are protected even from admins (Access is denied: UsageAndQualityInsights and the Click to Do ones on 26200) -
# skip those quietly; reporting them "off" made the guard say "Windows had reverted" them at every run (10/2)
foreach ($t in Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' -and ($_.TaskPath + $_.TaskName) -in $tasks }) {
    # (remembered per Windows build, so the preview - which can't try it - knows too; a new build tries again)
    $tk = "blocked|task|$($t.TaskPath)$($t.TaskName)"; $bld = "$([Environment]::OSVersion.Version.Build)"
    if ("$($bk[$tk].Build)" -eq $bld) { $script:auditBlocked++; continue }
    try { $t | Disable-ScheduledTask -ErrorAction Stop | Out-Null } catch { $bk[$tk] = @{ Build = $bld }; $script:bkDirty = $true; continue }
    Save-Original "task|$($t.TaskPath)$($t.TaskName)" @{ Enabled = $true }; $changes.Add("task $($t.TaskName) off")
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
# Never while Windows is halfway through an update (a restart pending): removing parts then has corrupted the component
# store (RemoveWindowsAI #77) - the next run, after the restart, does it
$restartPending = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' | Where-Object { Test-Path $_ }).Count -gt 0
# apps that hold the owner's own data: kept when they have some (a Win11Debloat user lost their notes that way, #576)
$dataApps = 'Microsoft.MicrosoftStickyNotes', 'Microsoft.Office.OneNote', 'Microsoft.Todos', 'Microsoft.MicrosoftJournal', 'microsoft.windowscommunicationsapps'
foreach ($a in $apps) {
    if ($restartPending) { break }
    $pkg = Get-AppxPackage -AllUsers $a
    if ($pkg) {
        if ($bk.ContainsKey("reinstalled|$a") -or $bk.ContainsKey("kept|$a")) { continue }
        # removed before and back for this user only (not set up for new users again): the owner reinstalled it - it
        # stays (Winhance kept removing apps people had reinstalled on purpose, #175). Windows putting it back comes
        # with the new-user copy too, and that goes again.
        if ($bk.ContainsKey("app|$a") -and -not (Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $a)) {
            $bk["reinstalled|$a"] = @{ Date = (Get-Date).ToString('d') }; $script:bkDirty = $true; $changes.Add("app $a kept (you reinstalled it)"); continue
        }
        $fam = ($pkg | Select-Object -First 1).PackageFamilyName
        if ($a -in $dataApps -and -not $bk.ContainsKey("app|$a") -and $fam -and
            (Get-ChildItem "$env:LOCALAPPDATA\Packages\$fam\LocalState" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            $bk["kept|$a"] = @{ Date = (Get-Date).ToString('d') }; $script:bkDirty = $true; $changes.Add("app $a kept (it has your data)"); continue
        }
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
    if (-not $Quick -and -not $restartPending -and "$($bk['legacy|build'].Build)" -ne $build) {   # (not mid-update: see the apps)
        $all = $true
        # (another servicing job - the first maintenance's own DISM cleanup runs alongside - holds Windows' servicing lock and
        # a removal is refused: waited for and tried again, 8 minutes (16 x 30 s) at most in all; 9/30 on GitHub only 1 of 9 went at first)
        $waits = 0
        foreach ($c in @(Get-WindowsCapability -Online | Where-Object { $_.State -eq 'Installed' -and ($_.Name -split '~')[0] -in $legacyCaps })) {
            if ($Audit) { $changes.Add("old Windows part $(($c.Name -split '~')[0]) removed"); continue }   # (no waiting for a removal that isn't made)
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
elseif ($dualX3D) {
    # AMD's dual-CCD X3D CPUs: Balanced, as AMD recommends - its driver parks the second CCD so games stay on the V-Cache
    # cores, and Ultimate Performance keeps every core unparked (reviewers follow AMD here; 10/10, the research comparison)
    $bal = '381b4222-f694-41f0-9685-ff5bb260df2e'
    if ($active -ne $bal) { Save-Original 'plan|active' @{ Guid = $active }; powercfg /setactive $bal; $changes.Add('power plan Balanced (AMD''s choice for this X3D CPU)') }
    if ((Get-AcIndex $usbSub $usbSet) -ne 0) { powercfg /setacvalueindex SCHEME_CURRENT $usbSub $usbSet 0; powercfg /setactive SCHEME_CURRENT; $changes.Add('USB sleep off') }
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
# ...and the helpers of hardware that is switched off or gone: Realtek's audio console without a working Realtek audio
# device, AMD's noise suppression and Radeon software without a working AMD graphics chip (an unused integrated GPU turned
# off - on the owner's PC both kept starting, 10/11). Only when Windows lists the graphics devices at all.
$pnp = @(Get-PnpDevice -PresentOnly -Class Display, MEDIA)
$orphanRx = if ($pnp | Where-Object Class -eq 'Display') {
    $ok = @($pnp | Where-Object Status -eq 'OK' | ForEach-Object { "$($_.FriendlyName) $($_.Manufacturer)" })
    @(if (-not ($ok -match 'Realtek')) { '^(RtkAudUService|RTHDVCPL|RtHDVBg.*)$' }
        if (-not ($ok -match 'AMD|Radeon|Advanced Micro Devices')) { '^(AMDNoiseSuppression|RadeonSoftware|AMD ?Software.*)$' }) -join '|'
}
if (Want 'startup-clutter') { foreach ($r in @(@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'),
        @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'),
        @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'))) {
    $run = Get-Item $r[0]; if (-not $run) { continue }
    foreach ($n in @($run.Property | Where-Object { $_ -match $clutter -or ($orphanRx -and $_ -match $orphanRx) })) {
        $cur = (Get-ItemProperty -Path $r[1] -Name $n).$n
        if ($cur -and ($cur[0] -band 1)) { continue }   # already off (odd first byte = disabled)
        Save-Original "startup|$($r[1])|$n" @{ Existed = $null -ne $cur; Value = $(if ($cur) { [Convert]::ToBase64String([byte[]]$cur) }) }
        if (-not (Test-Path $r[1])) { New-Item $r[1] -Force | Out-Null }
        Set-ItemProperty -Path $r[1] -Name $n -Value ([byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes((Get-Date).ToFileTime()))) -Type Binary
        $changes.Add("start-up item $n off$(if ($n -notmatch $clutter) { ' (its hardware is off)' })")
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
# its AI and ads (Copilot reading pages, AI history search, "compose", Bing chat and news on the new tab, shopping, Acrobat
# and donation upsells) - from Win11Debloat's maintained list, 10/10
foreach ($n in 'CopilotPageContext', 'CopilotCDPPageContext', 'EdgeEntraCopilotPageContext', 'EdgeHistoryAISearchEnabled', 'ComposeInlineEnabled',
    'NewTabPageBingChatEnabled', 'NewTabPageContentEnabled', 'EdgeShoppingAssistantEnabled', 'ShowRecommendationsEnabled',
    'SpotlightExperiencesAndRecommendationsEnabled', 'WalletDonationEnabled', 'ShowAcrobatSubscriptionButton') { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' $n 0 }
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' CreateDesktopShortcutDefault 0
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'CreateDesktopShortcut{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}' 0   # (Edge's own id)
# (tests: the icons and the pins live in PCKIT_EDGE_ROOT - never this PC's; none set: not touched)
$er = $env:PCKIT_EDGE_ROOT; $edgeFiles = -not $env:PCKIT_IN_TESTS -or $er
$edgeIcons = if ($er) { "$er\public\Microsoft Edge.lnk", "$er\desktop\Microsoft Edge.lnk" } else { "$env:PUBLIC\Desktop\Microsoft Edge.lnk", "$([Environment]::GetFolderPath('Desktop'))\Microsoft Edge.lnk" }
$pinned = if ($er) { "$er\pinned" } else { "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar" }
if (-not $edgeFiles) { }
elseif (Want 'edge') {
    Redo 'edge'
    foreach ($l in $edgeIcons) { if (Test-Path -LiteralPath $l) { Save-Original 'edge|desktop' @{ Removed = (Get-Date).ToString('d') }; if (-not $Audit) { [IO.File]::Delete($l) }; $changes.Add('Edge desktop icon removed') } }
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
# Edge removed altogether (opt-in, "tweak.edge-remove=on"). Only the browser: WebView2 - Edge's engine that apps such as
# game launchers show their pages with - stays and keeps updating. Edge's own uninstaller only runs once the old built-in
# Edge's file exists (winutil's way: an empty one); profiles (bookmarks, passwords) are kept. Edge Update's "don't install
# Edge" policy keeps it from coming back, and should Windows put it back anyway, the next check removes it again.
$group = 'edge-remove'
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}' 0   # (Edge's own id; WebView2's is another)
if ($edgeFiles) {
    $edgeExe = if ($er) { "$er\msedge.exe" } else { "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" }
    $edgeStub = if ($er) { "$er\SystemApps\MicrosoftEdge.exe" } else { "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\MicrosoftEdge.exe" }
    if (Want 'edge-remove') {
        Redo 'edge-remove'
        $edgeSetup = @(Get-ChildItem $(if ($er) { "$er\Installer\setup.exe" } else { "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\*\Installer\setup.exe" }) -ErrorAction SilentlyContinue | Select-Object -Last 1)
        if ((Test-Path -LiteralPath $edgeExe) -and $edgeSetup) {
            if (-not (Test-Path -LiteralPath $edgeStub)) { New-Item $edgeStub -ItemType File -Force | Out-Null }
            Start-Process $edgeSetup[0].FullName -ArgumentList '--uninstall', '--system-level', '--force-uninstall' -Wait -WindowStyle Hidden
            Save-Original 'edge|removed' @{ Date = (Get-Date).ToString('d') }
            $changes.Add($(if (Test-Path -LiteralPath $edgeExe) { 'Edge: its uninstaller did not remove it (next check tries again)' } else { 'Edge removed (WebView2 kept)' }))
        }
    } elseif ($bk.ContainsKey('edge|removed') -and -not (Test-Path -LiteralPath $edgeExe)) {
        # turned off again: Edge comes back (from winget, as winutil does it)
        Undo-Once 'edge-remove' { winget install --id Microsoft.Edge --exact --source winget --silent --accept-package-agreements --accept-source-agreements | Out-Null } 'Edge installed again (your choice)'
    }
}
$group = $null

Trace 'Registry backup'
# --- Windows stopped keeping copies of the registry in 2018 (C:\Windows\System32\config\RegBack stays empty): with this
# its own idle task saves them again - a way back for a PC that won't start after a bad driver or update. (From winutil.) ---
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager' EnablePeriodicBackup 1

Trace 'Vendor auto-installers'
# --- Razer Synapse and Logitech's download assistant: Windows installs them by itself when one of their mice or headsets
# is plugged in (the hardware works without them). An empty folder where their installers unpack, locked against writing,
# stops that - drivers still come from Windows Update (unlike winutil's version, which also turns off driver downloads).
# A folder that already has something in it (the app installed on purpose) is left alone. (From winutil, 10/10.) ---
$group = 'vendor-installers'
$vr = $env:PCKIT_VENDOR_ROOT   # (tests: their own folder; none set in a test: nothing touched)
$vendorDirs = if ($vr) { "$vr\Razer", "$vr\LogiDownloadAssistant" } elseif (-not $env:PCKIT_IN_TESTS) { "$env:SystemRoot\Installer\Razer", "$env:ProgramFiles\LogiDownloadAssistant" }
$everyone = New-Object Security.Principal.SecurityIdentifier 'S-1-1-0'
foreach ($vd in $vendorDirs) {
    $vn = Split-Path $vd -Leaf
    $acl = if (Test-Path -LiteralPath $vd) { Get-Acl -LiteralPath $vd }
    $deny = @($acl.Access | Where-Object { $_.AccessControlType -eq 'Deny' -and $(try { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]) -eq $everyone } catch { $false }) })
    if (Want 'vendor-installers') {
        if ($deny -or ($acl -and (Get-ChildItem -LiteralPath $vd -Force))) { continue }
        if (-not $acl) { New-Item $vd -ItemType Directory -Force | Out-Null; $acl = Get-Acl -LiteralPath $vd }
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($everyone, 'Write', 'Deny')))
        Set-Acl -LiteralPath $vd $acl
        Save-Original "vendor|$vn" @{ Path = $vd }; $changes.Add("$vn auto-installer blocked")
    } elseif ($deny -and $bk.ContainsKey("vendor|$vn")) {
        # the owner's choice: their installer may unpack again
        foreach ($r in $deny) { [void]$acl.RemoveAccessRule($r) }
        Set-Acl -LiteralPath $vd $acl
        if (-not (Get-ChildItem -LiteralPath $vd -Force)) { Remove-Item -LiteralPath $vd }
        $changes.Add("$vn auto-installer allowed again (your choice)")
    }
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

Trace 'Network'
# --- Network: Windows' own defaults, kept against "gaming tweak" tools (WinUtil and the like - on the owner's PC 10/10):
# network throttling off (NetworkThrottlingIndex 0xFFFFFFFF) raises network DPC latency, and Nagle off (TcpAckFrequency /
# TCPNoDelay on an adapter) gains nothing in games that already send at once - measured as more lag, not less.
# Windows' defaults: an index of 10, and neither Nagle value set. ---
$group = 'network-defaults'
$mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
if ($null -ne (Get-ItemProperty -Path $mm -Name NetworkThrottlingIndex).NetworkThrottlingIndex) { Set-Reg $mm NetworkThrottlingIndex 10 }
if (Want 'network-defaults') {
    foreach ($k in @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces')) {
        $kp = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($k.PSChildName)"
        foreach ($n in 'TcpAckFrequency', 'TCPNoDelay') {
            $v = (Get-ItemProperty -Path $kp -Name $n).$n; if ($null -eq $v) { continue }
            Save-Original "reg|$kp|$n" @{ Existed = $true; Value = $v; Kind = 'DWord' }
            Remove-ItemProperty -Path $kp -Name $n; Note-Change "$kp\$n '$v' -> (not set)"; $changes.Add("Nagle setting $n removed (Windows' default)")
        }
    }
}
$group = $null

Close-Section
# the status (-StatusFile): the run's result per switch / section, and which switches the owner turned off (the app's
# Status tab). Written directly - in a preview the usual file commands are stand-ins that do nothing.
if ($StatusFile) {
    try {
        $sj = @{ at = (Get-Date).ToString('o'); preview = [bool]$Audit; quick = [bool]$Quick; build = "$([Environment]::OSVersion.Version.Build)"
            cause = $Cause; laptop = $laptop; dualX3D = $dualX3D; off = @($off); on = @($on); optIn = $optIn; keys = $stat } | ConvertTo-Json -Depth 5
        [IO.File]::WriteAllText("$StatusFile.tmp", $sj, (New-Object Text.UTF8Encoding $false))
        if ([IO.File]::Exists($StatusFile)) { [IO.File]::Delete($StatusFile) }; [IO.File]::Move("$StatusFile.tmp", $StatusFile)
    } catch { }
}
# the preview: what would change, what Windows refuses, how much is in place - and nothing written (no originals, no history)
if ($Audit) {
    $would = @($changes | Select-Object -Unique)
    foreach ($c in $would) { "Would: $c" }
    "Preview: $($would.Count) change(s) would be made; $auditSame setting(s) already as Messiah keeps them$(if ($auditBlocked) { "; $auditBlocked blocked by Windows" }) - nothing was changed"
    try { $tmx.ReleaseMutex() } catch { }
    return
}
Trace 'done'
# the change history: the settings with their values (above), everything else as reported; the newest 3000 lines kept
foreach ($c in $changes | Select-Object -Unique) { if ($c -notmatch '^setting ') { Note-Change $c } }
if ($changeLog.Count) {
    $hist = Join-Path (Split-Path $bkFile) 'change-history.log'
    try {
        Add-Content $hist $changeLog -Encoding UTF8
        $all = @(Get-Content $hist -Encoding UTF8); if ($all.Count -gt 3000) { $all[-3000..-1] | Set-Content $hist -Encoding UTF8 }
    } catch { }
}
Save-Backup
try { $tmx.ReleaseMutex() } catch { }
$changes | Select-Object -Unique
