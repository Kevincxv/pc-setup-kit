# Sets every monitor to the highest refresh rate it supports at its current resolution (Windows often leaves a new
# 144/165/240 Hz monitor at 60 Hz). Monitors listed in .claude\health-ignore.txt (kept lower on purpose) are skipped.
# Prints one line per monitor it changed or could not change; nothing when all are already at their best.
# Test overrides: -Displays (JSON list of {Device, Name, Width, Height, Hz, MaxHz}) -WhatIf (only say what it would do).
param([string]$Displays, [switch]$WhatIf, [string]$IgnoreFile = "$PSScriptRoot\health-ignore.txt")
$ErrorActionPreference = 'Continue'
$ignore = @(Get-Content $IgnoreFile -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() })
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
    $list = for ($i = 0; $i -lt 8; $i++) {
        $a = New-Object KitDisp+DISPLAY_DEVICE; $a.cb = [Runtime.InteropServices.Marshal]::SizeOf([type][KitDisp+DISPLAY_DEVICE])
        if (-not [KitDisp]::EnumDisplayDevicesW($null, $i, [ref]$a, 0)) { break }
        if (($a.StateFlags -band 1) -eq 0) { continue }   # not attached to the desktop
        $mon = New-Object KitDisp+DISPLAY_DEVICE; $mon.cb = $a.cb; [void][KitDisp]::EnumDisplayDevicesW($a.DeviceName, 0, [ref]$mon, 0)
        $cur = New-Mode; [void][KitDisp]::EnumDisplaySettingsW($a.DeviceName, -1, [ref]$cur)
        $max = 0; $j = 0
        while ($true) { $n = New-Mode; if (-not [KitDisp]::EnumDisplaySettingsW($a.DeviceName, $j, [ref]$n)) { break }
            if ($n.dmPelsWidth -eq $cur.dmPelsWidth -and $n.dmPelsHeight -eq $cur.dmPelsHeight -and $n.dmDisplayFrequency -gt $max) { $max = $n.dmDisplayFrequency }; $j++ }
        [pscustomobject]@{ Device = $a.DeviceName; Name = $mon.DeviceString; Width = $cur.dmPelsWidth; Height = $cur.dmPelsHeight; Hz = $cur.dmDisplayFrequency; MaxHz = $max }
    }
} else { $list = @($Displays | ConvertFrom-Json | ForEach-Object { $_ }) }   # (PS 5.1 returns a JSON list as one object)

foreach ($d in $list) {
    if ($d.MaxHz -le $d.Hz + 2) { continue }                                        # already at its best
    if ($ignore | Where-Object { $d.Name -like "*$_*" }) { continue }                # kept lower on purpose
    if ($WhatIf) { "Monitor: would set $($d.Name) to $($d.MaxHz)Hz (now $($d.Hz)Hz)"; continue }
    $m = New-Mode; [void][KitDisp]::EnumDisplaySettingsW($d.Device, -1, [ref]$m)
    $m.dmDisplayFrequency = [uint32]$d.MaxHz; $m.dmFields = 0x400000                  # DM_DISPLAYFREQUENCY only: resolution stays
    $r = [KitDisp]::ChangeDisplaySettingsExW($d.Device, [ref]$m, [IntPtr]::Zero, 0x01, [IntPtr]::Zero)   # CDS_UPDATEREGISTRY: stays after a restart
    $now = New-Mode; [void][KitDisp]::EnumDisplaySettingsW($d.Device, -1, [ref]$now)
    if ($r -eq 0 -and $now.dmDisplayFrequency -ge $d.MaxHz - 1) { "Monitor: $($d.Name) set to $($now.dmDisplayFrequency)Hz (was $($d.Hz)Hz)" }
    else { "Monitor: $($d.Name) could not be set to $($d.MaxHz)Hz (Windows answered $r; it stays at $($now.dmDisplayFrequency)Hz)" }
}
