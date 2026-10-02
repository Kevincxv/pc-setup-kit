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
