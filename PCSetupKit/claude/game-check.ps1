# Is the owner gaming right now? Prints the game's name if so, nothing otherwise. Heavy maintenance (driver installs,
# app updates, virus scans, cleanup) checks this first and waits, so nothing blacks out the screen or stutters a game.
# Signals: Windows' own "fullscreen D3D/busy" state, a foreground window covering its whole monitor (borderless games),
# or a known game running in the background (alt-tabbed). Games seen fullscreen are remembered in .claude\games.txt
# (browsers/video players are not, so fullscreen YouTube only pauses maintenance while it's actually fullscreen).
param([switch]$Explain, [switch]$NoLearn, [hashtable]$T)   # -T: tests give the window in front (@{ Name; Covers; State }) and what runs (Procs)
$ErrorActionPreference = 'SilentlyContinue'
$games = "$PSScriptRoot\games.txt"
if (-not ('GameCheck.W' -as [type])) {
    Add-Type -Namespace GameCheck -Name W -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shell32.dll")] public static extern int SHQueryUserNotificationState(out int state);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr h, out RECT r);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern System.IntPtr MonitorFromWindow(System.IntPtr h, uint f);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool GetMonitorInfo(System.IntPtr m, ref MONITORINFO mi);
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)] public static extern int GetClassName(System.IntPtr h, System.Text.StringBuilder s, int n);
public struct RECT { public int Left, Top, Right, Bottom; }
public struct MONITORINFO { public int cbSize; public RECT rcMonitor, rcWork; public uint dwFlags; }
'@
}
# The window that really covers a monitor behind the one in front (a launcher in front of its borderless game): the first
# in z-order that is visible, not cloaked, not click-through or no-activate (overlays: the NVIDIA overlay, a cursor
# overlay - always "fullscreen", never a game), not the desktop. Its program's name, or ''.
if (-not ('GameCheck.Cover' -as [type])) {
    Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices;
namespace GameCheck { public static class Cover {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, uint f);
  [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr m, ref MI mi);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  struct R { public int L, T, Rt, B; } struct MI { public int cb; public R M, W; public uint F; }
  public static string Behind(IntPtr front, string[] skip) {
    string found = "";
    EnumWindows((h, l) => {
      if (h == front || !IsWindowVisible(h) || IsIconic(h)) return true;
      int ex = GetWindowLong(h, -20); if ((ex & 0x20) != 0 || (ex & 0x08000000) != 0) return true;
      int cl = 0; DwmGetWindowAttribute(h, 14, out cl, 4); if (cl != 0) return true;
      var c = new StringBuilder(64); GetClassName(h, c, 64); var cs = c.ToString();
      if (cs == "Progman" || cs == "WorkerW" || cs == "Shell_TrayWnd" || cs == "Shell_SecondaryTrayWnd") return true;
      R r; GetWindowRect(h, out r); var mi = new MI(); mi.cb = 40; GetMonitorInfo(MonitorFromWindow(h, 2), ref mi);
      if (!(r.L <= mi.M.L && r.T <= mi.M.T && r.Rt >= mi.M.Rt && r.B >= mi.M.B)) return true;
      uint pid; GetWindowThreadProcessId(h, out pid); string n = "";
      try { using (var p = System.Diagnostics.Process.GetProcessById((int)pid)) n = p.ProcessName; } catch { return true; }
      if (Array.IndexOf(skip, n) >= 0) return true;
      found = n; return false; }, IntPtr.Zero);
    return found; } } }
'@
}
# Never learned as games: shells, browsers, video players, office/presentation apps
$notGames = 'explorer', 'ApplicationFrameHost', 'ShellExperienceHost', 'StartMenuExperienceHost', 'SearchHost', 'LockApp', 'chrome', 'msedge', 'firefox',
    'opera', 'brave', 'vivaldi', 'vlc', 'mpc-hc64', 'mpc-be64', 'PotPlayerMini64', 'mpv', 'Video.UI', 'Microsoft.Media.Player', 'POWERPNT', 'Teams',
    'Discord', 'steamwebhelper', 'powershell', 'WindowsTerminal', 'conhost', 'AutoHotkey64', 'Messiah', 'MessiahApp', 'PC Setup Kit', 'obs64',
    # game launchers: open next to their game, or hidden in the tray all day - never the game itself
    'steam', 'EpicGamesLauncher', 'Battle.net', 'EADesktop', 'GalaxyClient', 'upc', 'RiotClientServices', 'Better2k', 'SaveTheGame', 'revival-client', 'Slums 2K Launcher'

$fgName = $null; $why = $null; $own = $false; $covers = $false; $state = 0
$fg = if ($T) { [IntPtr]::Zero } else { [GameCheck.W]::GetForegroundWindow() }
if ($fg -ne [IntPtr]::Zero) {
    $procId = 0; [void][GameCheck.W]::GetWindowThreadProcessId($fg, [ref]$procId); $fgName = (Get-Process -Id $procId).ProcessName
    $cls = New-Object Text.StringBuilder 64; [void][GameCheck.W]::GetClassName($fg, $cls, 64)
    $r = New-Object GameCheck.W+RECT; [void][GameCheck.W]::GetWindowRect($fg, [ref]$r)
    $mi = New-Object GameCheck.W+MONITORINFO; $mi.cbSize = 40; [void][GameCheck.W]::GetMonitorInfo([GameCheck.W]::MonitorFromWindow($fg, 2), [ref]$mi)
    $covers = $r.Left -le $mi.rcMonitor.Left -and $r.Top -le $mi.rcMonitor.Top -and $r.Right -ge $mi.rcMonitor.Right -and $r.Bottom -ge $mi.rcMonitor.Bottom
    $state = 0; [void][GameCheck.W]::SHQueryUserNotificationState([ref]$state)   # 2 busy/fullscreen, 3 D3D fullscreen, 4 presentation
    if ($cls.ToString() -match '^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$') { $covers = $false; $state = 0 }   # the desktop itself
}
if ($T) { $fgName = $T.Name; $covers = [bool]$T.Covers; $state = [int]$T.State }
# States 2 (busy) and 4 (presentation) say a fullscreen app is open somewhere - or only an overlay that is always
# "fullscreen" (10/21: the NVIDIA / a cursor overlay held all maintenance with Steam in front). So with the window in front
# not covering its monitor: the window that really covers one behind it is the fullscreen app (-T: Behind), else nothing.
# Only that window, one covering its monitor, or Direct3D exclusive fullscreen (3: the app in front) is learned as a game
# (10/10 the 2K20 launcher, in front of the borderless game, was learned - and then held all maintenance from the tray).
$overlays = 'TextInputHost', 'ShellExperienceHost', 'StartMenuExperienceHost', 'SearchHost', 'LockApp', 'NVIDIA Overlay', 'GameBar', 'XboxGameBar', 'codex-computer-use'
$behind = if (-not $covers -and $state -in 2, 4) { if ($T) { "$($T.Behind)" } else { [GameCheck.Cover]::Behind($fg, [string[]]$overlays) } }
if ($covers -or $state -eq 3) { $why = "fullscreen (state $state)"; $own = $true }
elseif ($behind) { $why = "fullscreen behind $fgName (state $state)"; $own = $true; $fgName = $behind }
# (a launcher learned by an older version is ignored)
$known = @(Get-Content $games -ErrorAction SilentlyContinue | ForEach-Object { ($_ -split '#')[0].Trim() } | Where-Object { $_ -and $_ -notin $notGames })
if ($why -and $own -and $fgName -and $fgName -notin $notGames) {
    if (-not $NoLearn -and $fgName -notin $known) { Add-Content $games "$fgName    # learned $(Get-Date -Format d) (seen fullscreen)"; $known += $fgName }
    if ($Explain) { "$fgName - $why" } else { $fgName }; return
}
if ($why) { if ($Explain) { "$fgName - $why (not a game, but fullscreen right now)" } else { $fgName }; return }   # fullscreen video: wait while it lasts
# (tests: the processes running are theirs - @{ Procs = @(@{ ProcessName; Path }) } - never this PC's: 10/22 a real game
# running broke the "no game" tests)
$procs = if ($T) { @($T.Procs | Where-Object { $_ } | ForEach-Object { [pscustomobject]$_ }) } else { $null }
$bg = if ($known) { if ($T) { $procs | Where-Object { $_.ProcessName -in $known } | Select-Object -First 1 } else { Get-Process -Name $known -ErrorAction SilentlyContinue | Select-Object -First 1 } }   # none known yet (a new PC): -Name @() is an error
if ($bg) { if ($Explain) { "$($bg.ProcessName) - known game running in the background" } else { $bg.ProcessName }; return }
# Not seen fullscreen yet (new game, alt-tabbed): anything running from a launcher's game library folder is a game too.
# Launchers themselves and always-on Steam tools (Wallpaper Engine, Lossless Scaling) live elsewhere or are skipped by name.
$libs = '\\steamapps\\common\\|\\Epic Games\\(?!Launcher\\)|\\XboxGames\\(?!GameSave\\)|\\EA Games\\|\\GOG Galaxy\\Games\\|\\GOG Games\\|\\Ubisoft Game Launcher\\games\\'
$tools = 'wallpaper32', 'wallpaper64', 'webwallpaper32', 'ui32', 'LosslessScaling', 'UnityCrashHandler64', 'UnityCrashHandler32', 'CrashReportClient'
$lib = $(if ($T) { $procs } else { Get-Process }) | Where-Object { $_.Path -match $libs -and $_.ProcessName -notin $tools -and $_.ProcessName -notin $notGames } | Select-Object -First 1
if ($lib) { if ($Explain) { "$($lib.ProcessName) - running from a game library ($(Split-Path $lib.Path))" } else { $lib.ProcessName } }
elseif ($Explain) { "no game (foreground: $fgName)" }
