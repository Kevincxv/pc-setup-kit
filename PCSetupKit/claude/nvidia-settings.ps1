# NVIDIA driver settings for games, on the driver's global profile (every game), kept that way: checked at every run, put back if reset (run by
# health-check.ps1; never under a game):
# - Low latency mode "On" (Maximum pre-rendered frames = 1): less input lag; games with NVIDIA Reflex use their own
# - Shader cache size "Unlimited": games don't recompile shaders (stutter) because an old 4 GB cache filled up
# Written with NVIDIA Profile Inspector (open source; not signed, so exactly one release is used, checked by its
# SHA-256) importing a .nip file in merge mode - every other setting stays as it is - then read back to confirm.
# kit-options.txt nvidiasettings=off (the app's Settings) stops it. State: nvidia-settings.txt (the driver it was
# applied for). -Test (hashtable: Gpu, Driver, Option, Game, Readback) with -Do (gets the actions) -State: tests.
param([hashtable]$Test, [scriptblock]$Do, [string]$State = "$PSScriptRoot\nvidia-settings.txt", [string]$Options = "$PSScriptRoot\kit-options.txt")
$ErrorActionPreference = 'SilentlyContinue'
$T = $Test
$want = [ordered]@{ '8102046' = @('Maximum pre-rendered frames', '1'); '11306135' = @('Shader disk cache maximum size', '4294967295') }   # 0x007BA09E, 0x00AC8497 (string keys: a number would index an ordered hashtable by position)
$npiUrl = 'https://github.com/Orbmu2k/nvidiaProfileInspector/releases/download/v3.0.2.1/nvidiaProfileInspector.zip'
$npiSha = '88DCF3514111E8DE630688467C03C36D8C2A8AD9EBC8073F27C069F82B75BB40'

# the global profile's current values, read from the driver itself (NVAPI's settings database) - the tool's own export
# leaves the global profile out. "id=value" lines; a negative value: not set / no driver
function Read-NvNow {
    if (-not ('KitNvDrs' -as [type])) { Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class KitNvDrs {
  [DllImport("nvapi64.dll", EntryPoint="nvapi_QueryInterface", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr QI(uint id);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int F0();
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FSess(out IntPtr s);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int F1(IntPtr s);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FBase(IntPtr s, out IntPtr p);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FGet(IntPtr s, IntPtr p, uint id, byte[] setting);
  static T D<T>(uint id) { return (T)(object)Marshal.GetDelegateForFunctionPointer(QI(id), typeof(T)); }
  public static long Get(uint settingId) {   // a DWORD setting's current value on the global profile; negative: not set / no driver
    if (D<F0>(0x0150E828)() != 0) return -2;
    IntPtr s; if (D<FSess>(0x0694D52E)(out s) != 0) return -3;
    try {
      if (D<F1>(0x375DBD6B)(s) != 0) return -4;
      IntPtr p; if (D<FBase>(0xDA8466A0)(s, out p) != 0) return -5;
      var b = new byte[12320]; BitConverter.GetBytes((uint)(12320 | (1 << 16))).CopyTo(b, 0);   // NVDRS_SETTING v1
      if (D<FGet>(0x73BF8338)(s, p, settingId, b) != 0) return -1;
      return BitConverter.ToUInt32(b, 8220);   // currentValue
    } finally { D<F1>(0xDAD9CFF8)(s); }
  }
}
"@ }
    foreach ($id in $want.Keys) { "$id=$([KitNvDrs]::Get([uint32]$id))" }
}
$gpu = if ($T) { $T.Gpu } else { Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1 }
if (-not $gpu) { return }
$opt = if ($T) { $T.Option } else { $l = @(Get-Content $Options) -match '^\s*nvidiasettings\s*=' | Select-Object -First 1; if ($l) { ($l -split '=', 2)[1].Trim() } }
if ($opt -eq 'off') { return }
$drv = if ($T) { $T.Driver } else { "$($gpu.DriverVersion)" }
# per game (10/21: Call of Duty; 10/22: every game Messiah has learned - games.txt): the game's own driver profile -
# NVIDIA's own one when the driver has it, else one made like the NVIDIA Control Panel's "Add program" does
# ("<game> (Messiah)") - with "Prefer maximum performance" and, while G-SYNC is really on for the main screen, V-Sync on
# (with G-SYNC: no tearing on a frame spike and no added lag) and a frame cap 3 under the refresh rate - games without
# Reflex need the cap to stay in G-SYNC's range; Call of Duty gets no cap (Reflex caps it). With G-SYNC off the game
# decides V-Sync and no cap is set. Checked every run, written only while that game isn't running, read back.
# Tests: -Test Games / Gsync / Refresh / Running / Ensure (a stand-in for the driver).
$learned = if ($T) { @($T.Games) } else { @(Get-Content "$PSScriptRoot\games.txt" | ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ -and $_ -notmatch '^(javaw?|pythonw?)$' }) }
if (-not $T -and (Test-Path "$env:LOCALAPPDATA\Activision\Call of Duty\players")) { $learned = @('cod') + $learned }
$learned = @($learned | Where-Object { $_ } | Select-Object -Unique)
if ($learned) {
    try {
        if (-not $T) {
            if (-not ('KitNvApp' -as [type])) { Add-Type -TypeDefinition @"
    using System; using System.Runtime.InteropServices; using System.Text;
    public static class KitNvApp {
      [DllImport("nvapi64.dll", EntryPoint="nvapi_QueryInterface", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr QI(uint id);
      [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int F0();
      [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FSess(out IntPtr s);
      [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int F1(IntPtr s);
      [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FFind(IntPtr s, byte[] app, out IntPtr p, byte[] appInfo);
      [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FGet(IntPtr s, IntPtr p, uint id, byte[] setting);
      [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FSet(IntPtr s, IntPtr p, byte[] setting);
      [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FNewProf(IntPtr s, byte[] info, out IntPtr p);
      [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FNewApp(IntPtr s, IntPtr p, byte[] app);
      static T D<T>(uint id) { return (T)(object)Marshal.GetDelegateForFunctionPointer(QI(id), typeof(T)); }
      static byte[] U(string s, int n) { var b = new byte[n]; var x = Encoding.Unicode.GetBytes(s); Array.Copy(x, b, Math.Min(x.Length, 4094)); return b; }
      static byte[] App(string exe, string name) { var a = new byte[12296]; BitConverter.GetBytes((uint)(12296 | (1 << 16))).CopyTo(a, 0); U(exe, 4096).CopyTo(a, 8); U(name, 4096).CopyTo(a, 4104); return a; }
      // the program's profile made if missing, these DWORD settings put on it if not yet; write=false: only report.
      // "same" / "set" / "pending" (needs writing, not allowed now) / "error:<step>:<code>"
      public static string Ensure(string exe, string profile, uint[] ids, uint[] vals, bool write) {
        if (D<F0>(0x0150E828)() != 0) return "error:init:0";
        IntPtr s; if (D<FSess>(0x0694D52E)(out s) != 0) return "error:session:0";
        try {
          int r = D<F1>(0x375DBD6B)(s); if (r != 0) return "error:load:" + r;
          IntPtr p; r = D<FFind>(0xEEE566B2)(s, U(exe, 4096), out p, App("", ""));
          bool made = false;
          if (r == -166) {
            if (!write) return "pending";
            var info = new byte[4116]; BitConverter.GetBytes((uint)(4116 | (1 << 16))).CopyTo(info, 0); U(profile, 4096).CopyTo(info, 4);
            r = D<FNewProf>(0xCC176068)(s, info, out p); if (r != 0) return "error:profile:" + r;
            r = D<FNewApp>(0x4347A9DE)(s, p, App(exe, profile)); if (r != 0) return "error:app:" + r;
            made = true;
          } else if (r != 0) return "error:find:" + r;
          bool same = !made;
          for (int i = 0; i < ids.Length && same; i++) {
            var b = new byte[12320]; BitConverter.GetBytes((uint)(12320 | (1 << 16))).CopyTo(b, 0);
            same = D<FGet>(0x73BF8338)(s, p, ids[i], b) == 0 && BitConverter.ToUInt32(b, 8220) == vals[i];
          }
          if (same) return "same";
          if (!write) return "pending";
          for (int i = 0; i < ids.Length; i++) {
            var b = new byte[12320]; BitConverter.GetBytes((uint)(12320 | (1 << 16))).CopyTo(b, 0);
            BitConverter.GetBytes(ids[i]).CopyTo(b, 4100); BitConverter.GetBytes(vals[i]).CopyTo(b, 8220);
            r = D<FSet>(0x577DD202)(s, p, b); if (r != 0) return "error:set:" + r;
          }
          r = D<F1>(0xFCBC7E14)(s); if (r != 0) return "error:save:" + r;
          return "set";
        } finally { D<F1>(0xDAD9CFF8)(s); }
      }
    }
"@ }
            # V-Sync on only with G-SYNC really on for the main screen (with it: no tearing and no added lag; without it, V-Sync
            # adds lag). NVAPI's VRR info for the main display: bIsVRREnabled stays 0 with G-SYNC ticked in the control panel;
            # bIsDisplayInVRRMode is the one that follows the tick (10/21: checked by switching it off and on).
            if (-not ('KitVrr' -as [type])) { Add-Type -TypeDefinition @"
    using System; using System.Runtime.InteropServices;
    public static class KitVrr {
      [DllImport("nvapi64.dll", EntryPoint="nvapi_QueryInterface", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr QI(uint id);
      [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int F0();
      [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FPrim(out uint id);
      [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FVrr(uint id, byte[] info);
      static T D<T>(uint id) { return (T)(object)Marshal.GetDelegateForFunctionPointer(QI(id), typeof(T)); }
      // the main screen: 1 G-SYNC on, 0 off (but possible), -1 not possible / not known
      public static int Primary() {
        if (D<F0>(0x0150E828)() != 0) return -1;
        uint d; if (D<FPrim>(0x1E9D8A31)(out d) != 0) return -1;
        var b = new byte[24]; BitConverter.GetBytes((uint)(24 | (1 << 16))).CopyTo(b, 0);   // NV_GET_VRR_INFO v1
        if (D<FVrr>(0xDF8FDA57)(d, b) != 0) return -1;
        uint f = BitConverter.ToUInt32(b, 4); return (f & 0x11) != 0 ? 1 : ((f >> 1) & 1) == 1 ? 0 : -1;
      }
    }
"@ }
        }
        $gs = if ($T) { $T.Gsync } else { [KitVrr]::Primary() }
        $hz = if ($T) { $T.Refresh } else { [int](Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1).CurrentRefreshRate }
        $ensure = if ($T) { $T.Ensure } else { { param($exe, $prof, $ids, $vals, $write) [KitNvApp]::Ensure($exe, $prof, [uint32[]]$ids, [uint32[]]$vals, $write) } }
        if (-not $T) {
            # G-SYNC possible but off: said once (and again if it is switched off later)
            $gf = "$PSScriptRoot\gsync.txt"; $was = "$(Get-Content $gf -TotalCount 1 -ErrorAction SilentlyContinue)".Trim()
            if ($gs -eq 0 -and $was -ne '0') { "Reminder: G-SYNC is off for your main screen, which supports it - frames tear or stutter between refreshes. NVIDIA Control Panel > Display > Set up G-SYNC > tick Enable G-SYNC, G-SYNC Compatible > Enable for windowed and full screen mode > Apply. Messiah then sets the rest for your games." }
            if ($gs -ge 0 -and $was -ne "$gs") { "$gs" | Set-Content $gf }
        }
        foreach ($n in $learned) {
            $cod = $n -eq 'cod'; $name = if ($cod) { 'Call of Duty' } else { $n }
            $ids = @(0x00A879CF, 0x1057EB71); $vals = @($(if ($gs -eq 1) { 0x47814940 } else { 0x60925292 }), 1)   # V-Sync: on with G-SYNC, else the game decides; power: prefer maximum performance
            $cap = 0; if ($gs -eq 1 -and -not $cod -and $hz -gt 30) { $cap = $hz - 3; $ids += 0x10835002; $vals += $cap }   # the driver's frame rate limiter
            $r = & $ensure "$n.exe" "$name (Messiah)" $ids $vals $false
            $on = if ($T) { $n -in @($T.Running) } else { [bool](Get-Process -Name $n -ErrorAction SilentlyContinue) }
            if ($r -eq 'pending' -and -not $on) { $r = & $ensure "$n.exe" "$name (Messiah)" $ids $vals $true }
            if ($r -eq 'set') {
                if ($cod) { if ($gs -eq 1) { "NVIDIA: Call of Duty set up for G-SYNC - V-Sync on and maximum performance on its own profile (Reflex keeps it under the refresh rate: no added lag)" } else { "NVIDIA: Call of Duty set to maximum performance on its own profile (V-Sync left to the game while G-SYNC is off)" } }
                elseif ($cap) { "NVIDIA: $name set up like Call of Duty - maximum performance, V-Sync on and a $cap fps cap just under the $hz Hz refresh on its own profile (with G-SYNC: smooth, no tearing, no added lag)" }
                else { "NVIDIA: $name set to maximum performance on its own profile (V-Sync left to the game while G-SYNC is off)" }
            }
            elseif ($r -like 'error:*') { "NVIDIA: $name's profile could not be set ($r)" }
        }
    } catch { }
}
# checked at every run - not only once per driver: the NVIDIA app, a game's own optimizer or a driver repair can reset the
# global profile without a new driver (10/2: guarded like every other setting). Reading it is instant and changes nothing.
$done = "$(Get-Content $State -TotalCount 1)".Trim() -eq $drv
$now = if ($T) { if ($T.ContainsKey('Current')) { $T.Current } } else { @(Read-NvNow) }
$set = $now -and -not ($want.Keys | Where-Object { "$_=$($want[$_][1])" -notin @($now) })
if ($set) { if (-not $done) { $drv | Set-Content $State }; return }   # already as wanted
if ($done -and -not $now) { return }   # applied for this driver, and it can't be read here: as before
$wasReset = $done
$game = if ($T) { $T.Game } else { & "$PSScriptRoot\game-check.ps1" }
if ($game) { return }   # the driver reloads its profile: not under a game (next check)

$tool = "$PSScriptRoot\tools\npi\nvidiaProfileInspector.exe"
if (-not $T -and -not (Test-Path $tool)) {
    $zip = Join-Path $env:TEMP "pckit-npi-$PID.zip"; $ProgressPreference = 'SilentlyContinue'
    try { Invoke-WebRequest $npiUrl -OutFile $zip -UseBasicParsing -TimeoutSec 60 } catch { return }   # offline: next check
    if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $npiSha) { [IO.File]::Delete($zip); 'NVIDIA settings: the Profile Inspector download did not match the checked version - not used'; return }
    Expand-Archive $zip (Split-Path $tool) -Force; [IO.File]::Delete($zip)
}
# the .nip: a list of profiles; "Base Profile" is the global one
$x = '<?xml version="1.0" encoding="utf-16"?><ArrayOfProfile><Profile><ProfileName>Base Profile</ProfileName><Executeables /><Settings>' +
    (($want.Keys | ForEach-Object { "<ProfileSetting><SettingNameInfo>$($want[$_][0])</SettingNameInfo><SettingID>$_</SettingID><SettingValue>$($want[$_][1])</SettingValue><ValueType>Dword</ValueType></ProfileSetting>" }) -join '') +
    '</Settings></Profile></ArrayOfProfile>'
$read = if ($T) { $T.Readback } else {
    $nip = Join-Path $env:TEMP "pckit-nvidia-$PID.nip"; [IO.File]::WriteAllText($nip, $x, [Text.Encoding]::Unicode)
    $p = Start-Process $tool -ArgumentList '-silentImport', '-mergeImport', "`"$nip`"" -PassThru -WindowStyle Minimized   # (hidden, it waits 90 s for its window)
    if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force }
    [IO.File]::Delete($nip)
    # read back from the driver itself (NVAPI's settings database, the global profile) - the tool's own export leaves
    # the global profile out
    Read-NvNow
}
if ($Do) { & $Do "import $($want.Keys -join ',')" }
$ok = -not ($want.Keys | Where-Object { "$_=$($want[$_][1])" -notin @($read) })
if ($ok) { $drv | Set-Content $State; if ($wasReset) { "NVIDIA: the game settings had been reset (low latency, shader cache) - put back" } else { "NVIDIA: low-latency mode on and an unlimited shader cache, for every game (driver $drv)" } }
else { "NVIDIA settings FAILED to apply (driver $drv) - read back: $(@($read) -join ', ')" }
