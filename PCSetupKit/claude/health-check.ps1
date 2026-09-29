# PC health check for the "Messiah" launcher (PC Setup Kit). Runs elevated in the background.
# - Reports blue screens / freezes since the last check
# - Tweak guard: re-runs C:\PCSetupKit\tweaks.ps1, which re-applies anything a Windows update undid
# - Hardware reminders until fixed: GPU link width, RAM at default speed (EXPO/XMP off), monitor below max Hz, old BIOS
# - Warnings: pending restart, low disk space, drive SMART health, SSD wear/heat
# - Mentions new auto-start items (Run keys, Startup folders, scheduled tasks) once
# Monitors (below max refresh), GPUs (below full PCIe width) or RAM (at default speed, by part number) the owner chose to accept can be listed (one name per line) in .claude\health-ignore.txt
$ErrorActionPreference = 'SilentlyContinue'
$state = "$env:USERPROFILE\.claude\health-check.last"
$ignore = @(Get-Content "$env:USERPROFILE\.claude\health-ignore.txt" | Where-Object { $_.Trim() })
$since = (Get-Date).AddDays(-7)   # first run, or an unreadable file: look back a week
if (Test-Path $state) { $prev = [datetime]::MinValue; if ([datetime]::TryParse("$(Get-Content $state -Raw)".Trim(), [ref]$prev)) { $since = $prev } }
(Get-Date).ToString('o') | Set-Content $state

# --- Crashes ---
$bsods = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; StartTime = $since }
$hard = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41; StartTime = $since } | Where-Object { $_.Properties[0].Value -eq 0 }
foreach ($b in $bsods) {
    $code = if ($b.Message -match 'bugcheck was: (0x[0-9a-fA-F]+)') { $Matches[1] } else { '?' }
    "WARNING: blue screen $code at $($b.TimeCreated.ToString('g'))"
}
foreach ($h in $hard) { "WARNING: unexpected shutdown/freeze at $($h.TimeCreated.ToString('g')) (no blue screen recorded)" }
# a blue screen right after a driver update: the previous version goes back by itself (driver-guard.ps1)
if ($bsods -and (Test-Path "$PSScriptRoot\driver-guard.ps1")) { & "$PSScriptRoot\driver-guard.ps1" -Crashes @($bsods | ForEach-Object TimeCreated) }
$whea = (Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since }).Count
if ($whea) { "WARNING: $whea hardware error(s) logged (WHEA) - possible RAM/CPU instability" }
if (-not $bsods -and -not $hard -and -not $whea) { 'Crashes: none since last check' }
# Diagnose new crash dumps automatically (names the driver/module responsible)
$dumps = @(Get-ChildItem 'C:\Windows\Minidump\*.dmp', 'C:\Windows\MEMORY.DMP' | Where-Object LastWriteTime -gt $since | Sort-Object LastWriteTime -Descending)
# MEMORY.DMP is the same crash as the minidump written with it; analyzing both repeats the line and is slow
$dumps = @($dumps | Where-Object { $d = $_; $d.Name -ne 'MEMORY.DMP' -or -not ($dumps | Where-Object { $_.Name -ne 'MEMORY.DMP' -and [Math]::Abs(($_.LastWriteTime - $d.LastWriteTime).TotalMinutes) -lt 10 }) } | Select-Object -First 2)
foreach ($d in $dumps) { "WARNING: crash dump $($d.Name) - $(& "$PSScriptRoot\crash-analyze.ps1" -Dump $d.FullName)" }
# graphics driver resets (a freeze / black screen in a game, no blue screen) and old shader caches after a driver update
if (Test-Path "$PSScriptRoot\gpu-watch.ps1") { & "$PSScriptRoot\gpu-watch.ps1" -Since $since }

# --- Health over time (start-up time, disk space, temperatures, SSD wear vs this PC's own normal) ---
if (Test-Path "$PSScriptRoot\trends.ps1") { & "$PSScriptRoot\trends.ps1" }

# --- Tweak guard (shared tweaks + this PC's own extras) ---
$fixed = @()
if (Test-Path 'C:\PCSetupKit\tweaks.ps1') { $fixed += & 'C:\PCSetupKit\tweaks.ps1' }
if (Test-Path "$PSScriptRoot\tweaks-local.ps1") { $fixed += & "$PSScriptRoot\tweaks-local.ps1" }
if ($fixed) { "Tweaks: Windows had reverted $($fixed.Count) - re-applied: $(($fixed | Select-Object -Unique) -join ', ')" } else { 'Tweaks: all still applied' }

# --- Security, clock, app updates ---
$mp = Get-MpComputerStatus
if ($mp -and -not $mp.RealTimeProtectionEnabled) { 'WARNING: Defender real-time protection is OFF' }
if ($mp -and $mp.QuickScanAge -gt 7 -and -not (& "$PSScriptRoot\game-check.ps1")) {   # never scan under a running game
    Start-Process "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -ArgumentList '-Scan', '-ScanType', '1' -WindowStyle Hidden
    "Security: started a quick virus scan (last one $(if ($mp.QuickScanAge -ge 10000) { 'never' } else { "$($mp.QuickScanAge) days ago" }))"
}
$lastSync = [datetime]::MinValue
$sync = w32tm /query /status | Select-String 'Last Successful Sync Time: (.+)$'
if ($sync) { try { $lastSync = [datetime]$sync.Matches[0].Groups[1].Value.Trim() } catch {} }
if ($lastSync -lt (Get-Date).AddDays(-8)) { w32tm /resync /force | Out-Null }
# App updates: read the Name column of winget's table (header positions tell where the Id column starts)
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}   # winget writes UTF-8
$raw = @(winget upgrade --accept-source-agreements --disable-interactivity 2>$null)
$h = [array]::FindIndex($raw, [Predicate[object]] { param($l) "$l" -match 'Name\s+Id\s+Version' })
if ($h -ge 0) {
    # rows read from the right (Id, Version, Available, Source never contain spaces): a shortened name can't shift them
    $up = @(for ($i = $h + 2; $i -lt $raw.Count -and $raw[$i] -match '\S' -and $raw[$i] -notmatch 'upgrades? available|explicit targeting'; $i++) {
        if ("$($raw[$i])" -match '^(?<name>.+?)\s+(?<id>\S+)\s+(?<ver>(<\s)?\S+)\s+(?<avail>\S+)\s+(?<src>\S+)\s*$') { $Matches['name'].Trim() } })
    if ($up) { "Apps: $($up.Count) update(s) available ($($up -join ', ')) - the weekly app update installs them" }
}

# --- Hardware reminders ---
foreach ($gpu in Get-PnpDevice -PresentOnly -Class Display | Where-Object { $_.FriendlyName -match 'NVIDIA|Radeon RX|Radeon Pro|Arc' }) {
    $p = Get-PnpDeviceProperty -InstanceId $gpu.InstanceId -KeyName DEVPKEY_PciDevice_CurrentLinkWidth, DEVPKEY_PciDevice_MaxLinkWidth
    if ($p[0].Data -and $p[1].Data -and $p[0].Data -lt $p[1].Data -and -not ($ignore | Where-Object { $gpu.FriendlyName -like "*$_*" })) { "Reminder: $($gpu.FriendlyName) runs at PCIe x$($p[0].Data) (card supports x$($p[1].Data)) - check BIOS slot setting / reseat card" }
}
$ram = Get-CimInstance Win32_PhysicalMemory | Select-Object -First 1
# 'expo-off-test' in maint-state.json = EXPO is off on purpose (crash test), so don't nag - for 21 days, then remind again
$expoTest = try { [datetime](Get-Content "$env:USERPROFILE\.claude\maint-state.json" -Raw | ConvertFrom-Json).'expo-off-test' -gt (Get-Date).AddDays(-21) } catch { $false }
# (RAM the owner keeps at default speed on purpose: its part number in health-ignore.txt)
if (-not $expoTest -and $ram.ConfiguredClockSpeed -and $ram.ConfiguredClockSpeed -le $ram.Speed -and $ram.Speed -in 2133, 2400, 2666, 3200, 4800, 5200, 5600 -and
    -not ($ignore | Where-Object { "$($ram.PartNumber)".Trim() -like "*$_*" })) {
    "Reminder: RAM runs at its default $($ram.ConfiguredClockSpeed) MT/s ($($ram.PartNumber.Trim())) - if it's a faster kit, turn EXPO/XMP on in BIOS"
}
$bios = Get-CimInstance Win32_BIOS
if ($bios.ReleaseDate -and $bios.ReleaseDate -lt (Get-Date).AddMonths(-12)) { "Reminder: BIOS $($bios.SMBIOSBIOSVersion) is from $($bios.ReleaseDate.ToString('d')) (over a year old)" }
# monitors: fixed first (native resolution, best refresh rate - also one plugged in later), then what's still off is said
if (Test-Path "$PSScriptRoot\display-refresh.ps1") { & "$PSScriptRoot\display-refresh.ps1" }
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public class HcDisp {
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct DEVMODE {
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
  public ushort dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public uint dmFields; public int dmPositionX, dmPositionY;
  public uint dmDisplayOrientation, dmDisplayFixedOutput; public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName; public ushort dmLogPixels;
  public uint dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency, dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight; }
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct DISPLAY_DEVICE { public int cb;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceString;
  public int StateFlags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceID; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceKey; }
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool EnumDisplaySettingsW(string n, int m, ref DEVMODE d);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool EnumDisplayDevicesW(string n, uint i, ref DISPLAY_DEVICE d, uint f);
}
'@
# (loop names unlike the tests' mock hashtables: PowerShell names ignore case, and a mock reads the nearest $M)
for ($i = 0; $i -lt 8; $i++) {
    $a = New-Object HcDisp+DISPLAY_DEVICE; $a.cb = [Runtime.InteropServices.Marshal]::SizeOf([type][HcDisp+DISPLAY_DEVICE])
    if (-not [HcDisp]::EnumDisplayDevicesW([NullString]::Value, $i, [ref]$a, 0)) { break }   # (PowerShell passes $null as "")
    if (($a.StateFlags -band 1) -eq 0) { continue }
    $mon = New-Object HcDisp+DISPLAY_DEVICE; $mon.cb = $a.cb; [void][HcDisp]::EnumDisplayDevicesW($a.DeviceName, 0, [ref]$mon, 0)
    if ($ignore | Where-Object { $mon.DeviceString -like "*$_*" }) { continue }
    $dmode = New-Object HcDisp+DEVMODE; $dmode.dmSize = [uint16][Runtime.InteropServices.Marshal]::SizeOf([type][HcDisp+DEVMODE])
    [void][HcDisp]::EnumDisplaySettingsW($a.DeviceName, -1, [ref]$dmode)
    $max = 0; $j = 0
    while ($true) { $dm2 = New-Object HcDisp+DEVMODE; $dm2.dmSize = $dmode.dmSize; if (-not [HcDisp]::EnumDisplaySettingsW($a.DeviceName, $j, [ref]$dm2)) { break }
        if ($dm2.dmPelsWidth -eq $dmode.dmPelsWidth -and $dm2.dmPelsHeight -eq $dmode.dmPelsHeight -and $dm2.dmDisplayFrequency -gt $max) { $max = $dm2.dmDisplayFrequency }; $j++ }
    if ($max -gt $dmode.dmDisplayFrequency + 2) { "Reminder: $($mon.DeviceString) runs at $($dmode.dmDisplayFrequency)Hz but supports ${max}Hz" }
}

# --- System warnings ---
if ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) { 'REBOOT pending to finish Windows updates (happens automatically when you restart)' }
# What waits for the owner's next restart, and afterwards whether it all finished (restart-ledger.json)
if (Test-Path "$PSScriptRoot\restart-check.ps1") { & "$PSScriptRoot\restart-check.ps1" }
$c = Get-PSDrive C
if ($c.Free / ($c.Used + $c.Free) -lt 0.10) { "WARNING: C: is low on space ($([int]($c.Free/1GB)) GB free)" }
foreach ($pd in Get-PhysicalDisk | Where-Object BusType -ne 'USB') {
    # HealthStatus is the drive's own SMART failure prediction (Warning/Unhealthy = back up now)
    if ($pd.HealthStatus -and $pd.HealthStatus -ne 'Healthy') { "WARNING: drive $($pd.FriendlyName) reports $($pd.HealthStatus) health ($($pd.OperationalStatus -join ', ')) - back up your files now" }
    $r = $pd | Get-StorageReliabilityCounter
    if ($r.Wear -ge 80) { "WARNING: $($pd.FriendlyName) wear at $($r.Wear)% - plan a replacement" }
    if ($r.Temperature -ge 70) { "WARNING: $($pd.FriendlyName) is hot ($($r.Temperature) C)" }
}

# --- New auto-start items (Run keys, Startup folders, non-Windows scheduled tasks) since the last check ---
# Baseline in .claude\startup-baseline.txt; the first run only records it. Each new item is mentioned once.
# Task names are normalized (GUID and version suffixes stripped) so updaters renaming their task on update stay quiet.
$auto = @()
foreach ($k in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run') {
    $item = Get-Item $k; if (-not $item) { continue }
    $ok = Get-Item ($k -replace 'CurrentVersion\\Run$', 'CurrentVersion\Explorer\StartupApproved\Run')
    $auto += $item.Property | Where-Object { $v = if ($ok) { $ok.GetValue($_) }; -not ($v -and ($v[0] -band 1)) }
}
$auto += (Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\*", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\*" -Exclude desktop.ini).BaseName
# (the kit's own tasks aren't news: the tray, the maintenance, the one-shot resume task, test runs' throwaway tasks)
$own = '^(Messiah Tray|Claude Admin Tray|Claude Background Maintenance|Claude Resume After Restart)$|^PCSetupKit|^PC Setup Kit |KITTEST'
$auto += Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $_.TaskPath -notlike '\PCSetupKit*' -and $_.State -ne 'Disabled' -and $_.TaskName -notmatch $own } | ForEach-Object { "task: $($_.TaskName -replace '_?\{[0-9A-Fa-f-]+\}$' -replace '\d+(\.\d+)+$')" }
$auto = @($auto | Where-Object { $_ } | Sort-Object -Unique)
$base = "$env:USERPROFILE\.claude\startup-baseline.txt"
if (Test-Path $base) {
    $new = @($auto | Where-Object { $_ -notin @(Get-Content $base) })
    if ($new) { "Reminder: new auto-start item(s) since last check: $($new -join ', ') (turn off any you don't want: Task Manager > Startup apps)" }
}
Set-Content $base -Value $auto   # also when empty (a clean PC): no baseline file would keep the first new item unreported

# --- Wired network link speed (a gigabit+ adapter stuck at 100 Mbps / 10 Mbps usually means a bad cable or port) ---
Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' -and $_.MediaType -eq '802.3' -and $_.ReceiveLinkSpeed -lt 1e9 -and $_.InterfaceDescription -match 'Gigabit|GbE|2\.5G|5G|10G|Gaming|I2[0-9]{2}' } |
    ForEach-Object { "Reminder: $($_.Name) network link is only $($_.LinkSpeed) (adapter supports 1 Gbps or more) - check the cable (Cat5e or better) and router port" }
# gaming: dual-CCD X3D needs (Game Bar, V-Cache service), Resizable BAR, games on a hard drive, the hypervisor,
# optional Defender exclusions for the game folders
if (Test-Path "$PSScriptRoot\gaming-check.ps1") { & "$PSScriptRoot\gaming-check.ps1" }
# NVIDIA driver settings for games (low latency, unlimited shader cache) - once per driver version
if (Test-Path "$PSScriptRoot\nvidia-settings.ps1") { & "$PSScriptRoot\nvidia-settings.ps1" }
# ping, jitter, packet loss and DNS speed over time (a slow router DNS is switched to a fast public one where safe)
if (Test-Path "$PSScriptRoot\network-check.ps1") { & "$PSScriptRoot\network-check.ps1" }

# --- Backups: impossible with one drive (a copy on the same disk dies with it); when a second/external drive shows up, offer it ---
$fh = Test-Path "$env:LOCALAPPDATA\Microsoft\Windows\FileHistory\Configuration\Config1.xml"
$bk = Get-ScheduledTask | Where-Object { $_.TaskName -match 'backup' -and $_.TaskPath -notlike '\Microsoft\*' -and $_.State -ne 'Disabled' }
if (-not $fh -and -not $bk) {
    $sys = (Get-Partition -DriveLetter C).DiskNumber
    foreach ($d in Get-Disk | Where-Object { $_.Number -ne $sys -and $_.BusType -ne 'File Backed Virtual' -and $_.Size -ge 64GB }) {
        "Reminder: $($d.FriendlyName) ($([int]($d.Size / 1GB)) GB) is connected and nothing is backed up"
    }
}
