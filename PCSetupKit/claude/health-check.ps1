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
# the stability record (power-log.json): every crash and power-off, the owner's "did you turn it off?" answers, and what
# changed (driver, BIOS, RAM, Driver Verifier) - the app's Home question and Activity > Stability
if (Test-Path "$PSScriptRoot\power-log.ps1") { & "$PSScriptRoot\power-log.ps1" -Update }
# CPU slowed down by the firmware (heat or power limit; event 37). A laptop on battery does this on purpose.
# (Windows logs one event per CPU thread: events in the same minute are one slowdown, not 16 on a 16-thread CPU)
$slow = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Processor-Power'; Id = 37; StartTime = $since } |
    Group-Object { $_.TimeCreated.ToString('yyyyMMddHHmm') })
$onBattery = @(Get-CimInstance Win32_Battery | Where-Object BatteryStatus -eq 1).Count -gt 0
if ($slow.Count -ge 3 -and -not $onBattery) { "Reminder: the CPU was slowed down by its firmware $($slow.Count) times since the last check (too hot or power-limited) - check the CPU cooler and case airflow" }
# Diagnose new crash dumps automatically (names the driver/module responsible)
$dumps = @(Get-ChildItem 'C:\Windows\Minidump\*.dmp', 'C:\Windows\MEMORY.DMP' | Where-Object LastWriteTime -gt $since | Sort-Object LastWriteTime -Descending)
# MEMORY.DMP is the same crash as the minidump written with it; analyzing both repeats the line and is slow
$dumps = @($dumps | Where-Object { $d = $_; $d.Name -ne 'MEMORY.DMP' -or -not ($dumps | Where-Object { $_.Name -ne 'MEMORY.DMP' -and [Math]::Abs(($_.LastWriteTime - $d.LastWriteTime).TotalMinutes) -lt 10 }) } | Select-Object -First 2)
foreach ($d in $dumps) { "WARNING: crash dump $($d.Name) - $(& "$PSScriptRoot\crash-analyze.ps1" -Dump $d.FullName)" }
# RAM stick test ('ram-stick-test' in maint-state.json, started by /maintain, for 60 days): every start and crash goes to
# .claude\ram-test.log with the sticks fitted, so blue screens are counted per stick setup. (A crash is logged at the next
# start, but the sticks can't change in between: the PC restarts by itself.)
$ramTest = try { [datetime](Get-Content "$env:USERPROFILE\.claude\maint-state.json" -Raw | ConvertFrom-Json).'ram-stick-test' } catch { $null }
if ($ramTest -and $ramTest -gt (Get-Date).AddDays(-60)) {
    $sticks = @(Get-CimInstance Win32_PhysicalMemory)
    $setup = "$($sticks.Count) stick(s), $([math]::Round(($sticks | Measure-Object Capacity -Sum).Sum / 1GB)) GB in $(@($sticks | ForEach-Object { "$($_.BankLabel)".Trim() }) -join ' + ')"
    $rlog = "$env:USERPROFILE\.claude\ram-test.log"
    $entries = @(Get-Content $rlog)
    $new = @(@($bsods) + @($hard) | Where-Object { $_ } | ForEach-Object { "$($_.TimeCreated.ToString('yyyy-MM-dd HH:mm')) | crash | $setup" })
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('yyyy-MM-dd HH:mm')
    if (-not ($entries -like "$boot | start | *")) { $new += "$boot | start | $setup" }
    if ($new) { Add-Content $rlog $new }
    $all = @($entries) + $new
    $cur = @(for ($i = $all.Count - 1; $i -ge 0 -and $all[$i] -like "* | $setup"; $i--) { $all[$i] })
    # said once a stick was taken out or moved (not while the PC still has its starting setup)
    if ($all[0] -notlike "* | $setup") { "RAM test: $setup - $(@($cur -like '* | start | *').Count) start(s), $(@($cur -like '* | crash | *').Count) crash(es) on this setup so far" }
}
# graphics driver resets (a freeze / black screen in a game, no blue screen) and old shader caches after a driver update
if (Test-Path "$PSScriptRoot\gpu-watch.ps1") { & "$PSScriptRoot\gpu-watch.ps1" -Since $since }

# --- Health over time (start-up time, disk space, temperatures, SSD wear vs this PC's own normal) ---
if (Test-Path "$PSScriptRoot\trends.ps1") { & "$PSScriptRoot\trends.ps1" }

# --- Tweak guard (shared tweaks + this PC's own extras) ---
$fixed = @()
# (-StatusFile: each switch's result, for the app's Status tab - only when this PC's tweaks.ps1 knows it)
$tws = @{}; $twc = Get-Command 'C:\PCSetupKit\tweaks.ps1' -ErrorAction SilentlyContinue; if ($twc -and $twc.Parameters.ContainsKey('StatusFile')) { $tws.StatusFile = "$PSScriptRoot\tweak-status.json" }
# (-Cause: the updates and driver installs since the last pass - what most likely changed anything back; update-cause.ps1)
$cause = $null; if ($twc -and $twc.Parameters.ContainsKey('Cause') -and (Test-Path "$PSScriptRoot\update-cause.ps1")) {
    $last = try { [datetime]((Get-Content "$PSScriptRoot\guard-state.json" -Raw -ErrorAction Stop | ConvertFrom-Json).at) } catch { (Get-Date).AddHours(-6) }
    $cause = "$(& "$PSScriptRoot\update-cause.ps1" -Since $last)"; if ($cause) { $tws.Cause = $cause } }
if (Test-Path 'C:\PCSetupKit\tweaks.ps1') { $fixed += & 'C:\PCSetupKit\tweaks.ps1' @tws }
$local = @(if (Test-Path "$PSScriptRoot\tweaks-local.ps1") { & "$PSScriptRoot\tweaks-local.ps1" }); $fixed += $local
try { @{ at = (Get-Date).ToString('o'); fixed = @($fixed).Count; hasLocal = (Test-Path "$PSScriptRoot\tweaks-local.ps1"); local = @($local); cause = $(if ($fixed) { $cause }) } | ConvertTo-Json | Set-Content "$PSScriptRoot\guard-state.json" -Encoding UTF8 } catch { }   # (the app's Guarded tile and Status tab)
if ($fixed -and (Test-Path "$PSScriptRoot\setup-maint-running.txt")) { "Tweaks: the rest of setup's changes applied ($($fixed.Count)): $(($fixed | Select-Object -Unique) -join ', ')" }   # (the first maintenance: what setup left for it - not reverted)
elseif ($fixed) { "Tweaks: Windows had reverted $($fixed.Count) - re-applied: $(($fixed | Select-Object -Unique) -join ', ')" } else { 'Tweaks: all still applied' }

# --- Security, clock, app updates ---
$mp = Get-MpComputerStatus
if (Test-Path "$PSScriptRoot\defender-check.ps1") { & "$PSScriptRoot\defender-check.ps1" }   # (switched back on when nothing else protects the PC)
elseif ($mp -and -not $mp.RealTimeProtectionEnabled) { 'WARNING: Defender real-time protection is OFF' }
if ($mp -and $mp.QuickScanAge -gt 7 -and -not (& "$PSScriptRoot\game-check.ps1")) {   # never scan under a running game
    Start-Process "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -ArgumentList '-Scan', '-ScanType', '1' -WindowStyle Hidden
    "Security: started a quick virus scan (last one $(if ($mp.QuickScanAge -ge 10000) { 'never' } else { "$($mp.QuickScanAge) days ago" }))"
}
# virus definitions normally update several times a day; 3+ days old = Windows Update stuck or offline for a while (a small download, fine under a game)
if ($mp -and $mp.AntivirusSignatureAge -gt 3) {
    Start-Process "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -ArgumentList '-SignatureUpdate' -WindowStyle Hidden
    "Security: virus definitions were $(if ($mp.AntivirusSignatureAge -ge 10000) { 'never updated' } else { "$($mp.AntivirusSignatureAge) days old" }) - started an update"
}
# the clock: synced in the last 8 days? (the Time Service's own "synchronized" events 35/37 - w32tm's text is translated
# on non-English Windows)
$synced = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Time-Service'; Id = 35, 37; StartTime = (Get-Date).AddDays(-8) } -MaxEvents 1
if (-not $synced) { w32tm /resync /force | Out-Null }
# App updates: read the Name column of winget's table (header positions tell where the Id column starts)
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}   # winget writes UTF-8
$raw = @(winget upgrade --accept-source-agreements --disable-interactivity 2>$null)
$h = [array]::FindIndex($raw, [Predicate[object]] { param($l) "$l" -match '^-{10,}\s*$' }) - 1   # the header: the line above the dashes (its words are translated on non-English Windows)
if ($h -lt 0) { $h = [array]::FindIndex($raw, [Predicate[object]] { param($l) "$l" -match 'Name\s+Id\s+Version' }) }
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
# (not where the PC maker's own tool keeps the BIOS current - vendor-updates.ps1)
$makerTool = try { (Get-Content "$PSScriptRoot\vendor-state.json" -Raw -ErrorAction Stop | ConvertFrom-Json).supported -eq $true } catch { $false }
if (-not $makerTool -and $bios.ReleaseDate -and $bios.ReleaseDate -lt (Get-Date).AddMonths(-12)) { "Reminder: BIOS $($bios.SMBIOSBIOSVersion) is from $($bios.ReleaseDate.ToString('d')) (over a year old)" }
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
# read/write errors (bad block, failed or retried I/O, NVMe controller error) often come before SMART says anything.
# Only internal drives count: a USB stick pulled out mid-copy logs the same events. (\Device\HarddiskN is the same in every language)
$internal = @{}; foreach ($pd in Get-PhysicalDisk | Where-Object BusType -ne 'USB') { $internal["$($pd.DeviceId)"] = $pd.FriendlyName }
$ioErr = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'disk'; Id = 7, 51, 153, 154; StartTime = $since } |
    ForEach-Object { if ("$($_.Message) $($_.Properties[0].Value)" -match 'Harddisk(\d+)\\DR' -and $internal.ContainsKey($Matches[1])) { $internal[$Matches[1]] } })
$nvme = @(Get-PhysicalDisk | Where-Object BusType -eq 'NVMe' | ForEach-Object FriendlyName) -join ' / '
if ($nvme) { $ioErr += @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'stornvme'; Id = 11; StartTime = $since } | ForEach-Object { $nvme }) }
foreach ($g in $ioErr | Group-Object) { "WARNING: $($g.Name) logged $($g.Count) read/write error(s) since the last check - can be a failing drive or a loose cable: back up your files" }

# --- New auto-start items (Run keys, Startup folders, non-Windows scheduled tasks) since the last check ---
# Baseline in .claude\startup-baseline.txt; the first run only records it. Each new item is mentioned once.
# Task names are normalized (GUID and version suffixes stripped) so updaters renaming their task on update stay quiet.
$auto = @(); $autoCmd = @{}   # (what each one runs: a new one is checked for its maker's signature)
foreach ($k in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run') {
    $item = Get-Item $k; if (-not $item) { continue }
    $ok = Get-Item ($k -replace 'CurrentVersion\\Run$', 'CurrentVersion\Explorer\StartupApproved\Run')
    $auto += $item.Property | Where-Object { $v = if ($ok) { $ok.GetValue($_) }; -not ($v -and ($v[0] -band 1)) } | ForEach-Object { $autoCmd[$_] = "$($item.GetValue($_))"; $_ }
}
$auto += (Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\*", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\*" -Exclude desktop.ini).BaseName
# (the kit's own tasks aren't news: the tray, the maintenance, the one-shot resume task, test runs' throwaway tasks;
# Windows' own CreateExplorerShellUnelevatedTask, made in the root folder when Explorer is started from an elevated app)
$own = '^Messiah |^(Claude Admin Tray|Claude Background Maintenance|Claude Resume After Restart)$|^PCSetupKit|^PC Setup Kit |KITTEST|^CreateExplorerShellUnelevatedTask$'
$auto += Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $_.TaskPath -notlike '\PCSetupKit*' -and $_.State -ne 'Disabled' -and $_.TaskName -notmatch $own } | ForEach-Object { $tn = "task: $($_.TaskName -replace '_?\{[0-9A-Fa-f-]+\}$' -replace '\d+(\.\d+)+$')"; $autoCmd[$tn] = "$(@($_.Actions)[0].Execute)"; $tn }
$auto = @($auto | Where-Object { $_ } | Sort-Object -Unique)
$base = "$env:USERPROFILE\.claude\startup-baseline.txt"
if (Test-Path $base) {
    $new = @($auto | Where-Object { $_ -notin @(Get-Content $base) })
    # each new one's program checked for its maker's signature (what Sysinternals Autoruns flags): an unsigned one running
    # from a folder any program can write to (AppData, Temp) is how malware starts itself - a WARNING, so it gets looked at
    $unsigned = @(); $suspect = @()
    foreach ($n in $new) {
        $c = [Environment]::ExpandEnvironmentVariables("$($autoCmd[$n])").Trim()
        $exe = if ($c -match '^"([^"]+)"') { $Matches[1] } elseif ($c -match '^(.+?\.(exe|com|bat|cmd|ps1|vbs|js|scr))(\s|$)') { $Matches[1] } else { $c }
        if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { continue }
        if ((Get-AuthenticodeSignature -LiteralPath $exe).Status -eq 'Valid') { continue }
        if ($exe -match '\\AppData\\|\\Temp\\|\\Users\\Public\\') { $suspect += "$n ($exe)" } else { $unsigned += $n }
    }
    if ($suspect) { "WARNING: new auto-start item(s) not signed by their maker, running from a folder any program can write to: $($suspect -join ', ') - if you didn't install this, it may be malware" }
    $plain = @($new | Where-Object { $n = $_; -not ($suspect | Where-Object { $_ -like "$n (*" }) })
    if ($plain) { "Reminder: new auto-start item(s) since last check: $(@($plain | ForEach-Object { if ($_ -in $unsigned) { "$_ (not signed)" } else { $_ } }) -join ', ') (turn off any you don't want: Task Manager > Startup apps)" }
}
Set-Content $base -Value $auto   # also when empty (a clean PC): no baseline file would keep the first new item unreported

# --- Wired network link speed (a gigabit+ adapter stuck at 100 Mbps / 10 Mbps usually means a bad cable or port) ---
Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' -and $_.MediaType -eq '802.3' -and $_.ReceiveLinkSpeed -lt 1e9 -and $_.InterfaceDescription -match 'Gigabit|GbE|2\.5G|5G|10G|Gaming|I2[0-9]{2}' } |
    ForEach-Object { "Reminder: $($_.Name) network link is only $($_.LinkSpeed) (adapter supports 1 Gbps or more) - check the cable (Cat5e or better) and router port" }
# Windows activation: only with this PC's own license (firmware key / digital license); otherwise a Reminder
if (Test-Path "$PSScriptRoot\activation-check.ps1") { & "$PSScriptRoot\activation-check.ps1" }
# gaming: dual-CCD X3D needs (Game Bar, V-Cache service), Resizable BAR, games on a hard drive, the hypervisor,
# optional Defender exclusions for the game folders
if (Test-Path "$PSScriptRoot\gaming-check.ps1") { & "$PSScriptRoot\gaming-check.ps1" }
# crash-hunting modes left on (Driver Verifier, kernel debugging, test signing): right while a crash is hunted, a cost in
# every game after - said once they've been on two weeks (10/11: Driver Verifier had watched the NVIDIA driver for a week
# with nothing pointing at it). (Tests: diag-modes.ps1 has its own - it keeps a state file next to it.)
if ((Test-Path "$PSScriptRoot\diag-modes.ps1") -and -not $env:PCKIT_IN_TESTS) {
    foreach ($dm in @(& "$PSScriptRoot\diag-modes.ps1" | Where-Object { $_.Days -ge 14 })) { "Reminder: $($dm.Name) has been on for $($dm.Days) days (since $($dm.Since.ToString('MMM d'))) - it is for hunting crashes and slows games; turn it off once the hunt is over (Messiah > Status)" }
}
# NVIDIA driver settings for games (low latency, unlimited shader cache) - once per driver version
if (Test-Path "$PSScriptRoot\nvidia-settings.ps1") { & "$PSScriptRoot\nvidia-settings.ps1" }
# ping, jitter, packet loss and DNS speed over time (a slow router DNS is switched to a fast public one where safe)
if (Test-Path "$PSScriptRoot\network-check.ps1") { & "$PSScriptRoot\network-check.ps1" }

# --- Backups: impossible with one drive (a copy on the same disk dies with it); when a second/external drive shows up, offer it ---
# files-backup.ps1: the one-click offer, then the backup itself whenever the chosen drive is there
if (Test-Path "$PSScriptRoot\files-backup.ps1") { & "$PSScriptRoot\files-backup.ps1" -Check }
# game-saves.ps1: every game's saves to Documents, once a day, when the owner turned it on (Settings > Game saves)
if (Test-Path "$PSScriptRoot\game-saves.ps1") { & "$PSScriptRoot\game-saves.ps1" -Check }
$fh = Test-Path "$env:LOCALAPPDATA\Microsoft\Windows\FileHistory\Configuration\Config1.xml"
$bk = Get-ScheduledTask | Where-Object { $_.TaskName -match 'backup' -and $_.TaskPath -notlike '\Microsoft\*' -and $_.State -ne 'Disabled' }
if (-not (Test-Path "$PSScriptRoot\files-backup.ps1") -and -not $fh -and -not $bk) {   # (an older copy without it)
    $sys = (Get-Partition -DriveLetter C).DiskNumber
    foreach ($d in Get-Disk | Where-Object { $_.Number -ne $sys -and $_.BusType -ne 'File Backed Virtual' -and $_.Size -ge 64GB }) {
        "Reminder: $($d.FriendlyName) ($([int]($d.Size / 1GB)) GB) is connected and nothing is backed up"
    }
}
# Restore points and the recovery environment are the undo for a bad driver or update (driver-check makes a restore
# point first). Some updates and "debloat" tools turn them off: back on, said
$sp = "$((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients' -ErrorAction SilentlyContinue).'{09F7EDC5-294E-4180-AF6A-FB0E6A0E9513}')"
if ($sp -notlike "*($($env:SystemDrive -replace ':', '%3A'))*") {
    try { Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop; 'Backups: restore points were off - turned back on' }
    catch { "WARNING: restore points are off and could not be turned back on ($($_.Exception.Message))" }
}
if ((reagentc /info 2>$null | Out-String) -match 'Windows RE status:\s+Disabled') {   # (English Windows only: the text is translated)
    reagentc /enable 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { 'Backups: the Windows recovery tools were off - turned back on' }
    else { 'WARNING: the Windows recovery tools (Startup Repair, Reset this PC) are off and could not be turned back on' }
}
# WebView2 - the engine Windows' own Start search and many apps (game launchers too) show their pages with. PCs from an
# older install USB came without it: after the 12/2025 update Start search hung on such images (tiny11builder #575) - so
# where it's missing it's installed (10/10, the research comparison)
$wv = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' -Name pv).pv
if (-not $wv -or $wv -eq '0.0.0.0') {
    $null = winget install --id Microsoft.EdgeWebView2Runtime -e --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
    if ($LASTEXITCODE -eq 0) { 'Repaired: WebView2 (the page engine Windows search and many apps need) was missing - installed' }
    else { "WARNING: WebView2 is missing and could not be installed (winget $LASTEXITCODE) - Start search and some apps may not work" }
}
# Secure Boot's 2023 certificates: Microsoft's 2011 ones expire in 2026, and a PC still on them can't take future boot
# security updates. Windows Update brings the new ones; a firmware that refuses them needs a BIOS update (Sophia checks this too)
if ((Confirm-SecureBootUEFI) -eq $true) {
    $db = try { [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI db -ErrorAction Stop).bytes) } catch { $null }
    if ($db -and $db -notmatch 'Windows UEFI CA 2023') { "Reminder: Secure Boot doesn't have Microsoft's 2023 certificate yet (the 2011 ones expire in 2026) - Windows Update installs it; if it doesn't arrive within a few weeks, a BIOS update from the motherboard maker brings it" }
}
