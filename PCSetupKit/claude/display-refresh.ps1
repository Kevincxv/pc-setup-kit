# Every monitor at its best: its native resolution (the one its EDID says it's built for - sharp, no scaling) and
# the highest refresh rate it supports at that resolution (Windows often leaves a new 144/165/240 Hz monitor at 60 Hz,
# or a monitor at a lower resolution after a driver install). Run at setup (optimize.ps1) and at every check
# (health-check.ps1), so a monitor plugged in later is fixed too; never while a game runs.
# - The resolution is set once per monitor (display-state.json): someone who lowers it on purpose keeps their choice.
#   Only raised, only to the EDID's own mode, and only if Windows offers it - virtual (DSR/VSR) modes never count.
# - The refresh rate is fixed at every run: drivers and cables reset it, and nobody lowers it on purpose.
# Monitors listed in .claude\health-ignore.txt (kept lower on purpose) are skipped entirely.
# Prints one line per monitor it changed or could not change; nothing when all are already at their best.
# Test overrides: -Displays (JSON list of {Device, Name, Key, Width, Height, Hz, MaxHz, NativeWidth, NativeHeight,
# NativeMaxHz}) -WhatIf (only say what it would do) -State -TestGame; -ShowMonitors: print the monitors as found (tests).
param([string]$Displays, [switch]$WhatIf, [string]$IgnoreFile = "$PSScriptRoot\health-ignore.txt", [string]$State = "$PSScriptRoot\display-state.json",
    [string]$TestGame, [switch]$ShowMonitors)
$ErrorActionPreference = 'Continue'
$game = if ($PSBoundParameters.ContainsKey('TestGame')) { $TestGame } elseif (Test-Path "$PSScriptRoot\game-check.ps1") { & "$PSScriptRoot\game-check.ps1" }
if ($game -and -not $ShowMonitors) { return }   # a mode switch blanks the screen for a moment: never under a game (next check)
$ignore = @(Get-Content $IgnoreFile -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() })
$done = @{}; try { (Get-Content $State -Raw -ErrorAction Stop | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $done[$_.Name] = $_.Value } } catch { }
if (-not $Displays) {
    Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public class KitDisp {
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
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int ChangeDisplaySettingsExW(string n, ref DEVMODE d, IntPtr h, uint f, IntPtr p);
}
'@
    function New-Mode { $m = New-Object KitDisp+DEVMODE; $m.dmSize = [uint16][Runtime.InteropServices.Marshal]::SizeOf([type][KitDisp+DEVMODE]); $m }
    # each monitor's own preferred (native) mode from its EDID, by its hardware id (e.g. AUS27FD)
    $edid = @{}
    foreach ($w in Get-CimInstance -Namespace root\wmi WmiMonitorListedSupportedSourceModes -ErrorAction SilentlyContinue) {
        $p = $w.MonitorSourceModes[$w.PreferredMonitorSourceModeIndex]
        if ($p -and $w.InstanceName -match '^DISPLAY\\([^\\]+)\\' -and -not $edid[$Matches[1]]) { $edid[$Matches[1]] = @([int]$p.HorizontalActivePixels, [int]$p.VerticalActivePixels) }
    }
    $list = for ($i = 0; $i -lt 8; $i++) {
        $a = New-Object KitDisp+DISPLAY_DEVICE; $a.cb = [Runtime.InteropServices.Marshal]::SizeOf([type][KitDisp+DISPLAY_DEVICE])
        if (-not [KitDisp]::EnumDisplayDevicesW([NullString]::Value, $i, [ref]$a, 0)) { break }   # (PowerShell passes $null as "": no monitor was ever found)
        if (($a.StateFlags -band 1) -eq 0) { continue }   # not attached to the desktop
        $mon = New-Object KitDisp+DISPLAY_DEVICE; $mon.cb = $a.cb; [void][KitDisp]::EnumDisplayDevicesW($a.DeviceName, 0, [ref]$mon, 0)
        $cur = New-Mode; [void][KitDisp]::EnumDisplaySettingsW($a.DeviceName, -1, [ref]$cur)
        $nat = if ($mon.DeviceID -match '^MONITOR\\([^\\]+)\\') { $edid[$Matches[1]] }
        $max = 0; $natMax = 0; $j = 0
        while ($true) { $n = New-Mode; if (-not [KitDisp]::EnumDisplaySettingsW($a.DeviceName, $j, [ref]$n)) { break }
            if ($n.dmPelsWidth -eq $cur.dmPelsWidth -and $n.dmPelsHeight -eq $cur.dmPelsHeight -and $n.dmDisplayFrequency -gt $max) { $max = $n.dmDisplayFrequency }
            if ($nat -and $n.dmPelsWidth -eq $nat[0] -and $n.dmPelsHeight -eq $nat[1] -and $n.dmDisplayFrequency -gt $natMax) { $natMax = $n.dmDisplayFrequency }; $j++ }
        [pscustomobject]@{ Device = $a.DeviceName; Name = $mon.DeviceString; Key = $mon.DeviceID; Width = $cur.dmPelsWidth; Height = $cur.dmPelsHeight
            Hz = $cur.dmDisplayFrequency; MaxHz = $max; NativeWidth = $(if ($nat) { $nat[0] }); NativeHeight = $(if ($nat) { $nat[1] }); NativeMaxHz = $natMax }
    }
} else { $list = @($Displays | ConvertFrom-Json | ForEach-Object { $_ }) }   # (PS 5.1 returns a JSON list as one object)
if ($ShowMonitors) { return $list }

$changed = $false
foreach ($d in $list) {
    if ($ignore | Where-Object { $d.Name -like "*$_*" }) { continue }                # kept lower on purpose
    $key = if ($d.Key) { "$($d.Key)" } else { "$($d.Name)" }
    # native resolution: once per monitor, only upwards, only a mode Windows really offers for it
    $toNative = $d.NativeWidth -and $d.NativeMaxHz -and -not $done.ContainsKey($key) -and
        [long]$d.Width * $d.Height -lt [long]$d.NativeWidth * $d.NativeHeight
    $w = if ($toNative) { $d.NativeWidth } else { $d.Width }; $hh = if ($toNative) { $d.NativeHeight } else { $d.Height }
    $hz = if ($toNative) { $d.NativeMaxHz } else { $d.MaxHz }
    if ($d.NativeWidth -and -not $done.ContainsKey($key)) { $done[$key] = "$($d.NativeWidth)x$($d.NativeHeight) $(Get-Date -Format 'yyyy-MM-dd')"; $changed = $true }
    if (-not $toNative -and $hz -le $d.Hz + 2) { continue }                          # already at its best
    $what = if ($toNative) { "${w}x$hh at ${hz}Hz (was $($d.Width)x$($d.Height) at $($d.Hz)Hz)" } else { "${hz}Hz (was $($d.Hz)Hz)" }
    if ($WhatIf) { "Monitor: would set $($d.Name) to $what"; continue }
    $m = New-Mode; [void][KitDisp]::EnumDisplaySettingsW($d.Device, -1, [ref]$m)
    $m.dmDisplayFrequency = [uint32]$hz; $m.dmFields = 0x400000                      # DM_DISPLAYFREQUENCY
    if ($toNative) { $m.dmPelsWidth = [uint32]$w; $m.dmPelsHeight = [uint32]$hh; $m.dmFields = $m.dmFields -bor 0x80000 -bor 0x100000 }   # + DM_PELSWIDTH/HEIGHT
    $r = [KitDisp]::ChangeDisplaySettingsExW($d.Device, [ref]$m, [IntPtr]::Zero, 0x01, [IntPtr]::Zero)   # CDS_UPDATEREGISTRY: stays after a restart
    $now = New-Mode; [void][KitDisp]::EnumDisplaySettingsW($d.Device, -1, [ref]$now)
    if ($r -eq 0 -and $now.dmDisplayFrequency -ge $hz - 1 -and $now.dmPelsWidth -eq $w) { "Monitor: $($d.Name) set to $what" }
    else { "Monitor: $($d.Name) could not be set to ${hz}Hz$(if ($toNative) { " at ${w}x$hh" }) (Windows answered $r; it stays at $($now.dmPelsWidth)x$($now.dmPelsHeight) $($now.dmDisplayFrequency)Hz)" }
}
if ($changed -and -not $WhatIf) { try { [pscustomobject]$done | ConvertTo-Json | Set-Content $State -Encoding UTF8 } catch { } }
