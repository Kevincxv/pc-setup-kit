# Is the owner gaming right now? Prints the game's name if so, nothing otherwise. Heavy maintenance (driver installs,
# app updates, virus scans, cleanup) checks this first and waits, so nothing blacks out the screen or stutters a game.
# Signals: Windows' own "fullscreen D3D/busy" state, a foreground window covering its whole monitor (borderless games),
# or a known game running in the background (alt-tabbed). Games seen fullscreen are remembered in .claude\games.txt
# (browsers/video players are not, so fullscreen YouTube only pauses maintenance while it's actually fullscreen).
param([switch]$Explain, [switch]$NoLearn)
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
# Never learned as games: shells, browsers, video players, office/presentation apps
$notGames = 'explorer', 'ApplicationFrameHost', 'ShellExperienceHost', 'StartMenuExperienceHost', 'SearchHost', 'LockApp', 'chrome', 'msedge', 'firefox',
    'opera', 'brave', 'vivaldi', 'vlc', 'mpc-hc64', 'mpc-be64', 'PotPlayerMini64', 'mpv', 'Video.UI', 'Microsoft.Media.Player', 'POWERPNT', 'Teams',
    'Discord', 'steamwebhelper', 'powershell', 'WindowsTerminal', 'conhost', 'AutoHotkey64', 'Messiah', 'PC Setup Kit', 'obs64'

$fg = [GameCheck.W]::GetForegroundWindow(); $fgName = $null; $why = $null
if ($fg -ne [IntPtr]::Zero) {
    $procId = 0; [void][GameCheck.W]::GetWindowThreadProcessId($fg, [ref]$procId); $fgName = (Get-Process -Id $procId).ProcessName
    $cls = New-Object Text.StringBuilder 64; [void][GameCheck.W]::GetClassName($fg, $cls, 64)
    $r = New-Object GameCheck.W+RECT; [void][GameCheck.W]::GetWindowRect($fg, [ref]$r)
    $mi = New-Object GameCheck.W+MONITORINFO; $mi.cbSize = 40; [void][GameCheck.W]::GetMonitorInfo([GameCheck.W]::MonitorFromWindow($fg, 2), [ref]$mi)
    $covers = $r.Left -le $mi.rcMonitor.Left -and $r.Top -le $mi.rcMonitor.Top -and $r.Right -ge $mi.rcMonitor.Right -and $r.Bottom -ge $mi.rcMonitor.Bottom
    $state = 0; [void][GameCheck.W]::SHQueryUserNotificationState([ref]$state)   # 2 busy/fullscreen, 3 D3D fullscreen, 4 presentation
    if ($cls.ToString() -notmatch '^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$' -and ($covers -or $state -in 2, 3, 4)) { $why = "fullscreen (state $state)" }
}
$known = @(Get-Content $games -ErrorAction SilentlyContinue | ForEach-Object { ($_ -split '#')[0].Trim() } | Where-Object { $_ })
if ($why -and $fgName -and $fgName -notin $notGames) {
    if (-not $NoLearn -and $fgName -notin $known) { Add-Content $games "$fgName    # learned $(Get-Date -Format d) (seen fullscreen)"; $known += $fgName }
    if ($Explain) { "$fgName - $why" } else { $fgName }; return
}
if ($why) { if ($Explain) { "$fgName - $why (not a game, but fullscreen right now)" } else { $fgName }; return }   # fullscreen video: wait while it lasts
$bg = Get-Process -Name $known -ErrorAction SilentlyContinue | Select-Object -First 1
if ($bg) { if ($Explain) { "$($bg.ProcessName) - known game running in the background" } else { $bg.ProcessName }; return }
# Not seen fullscreen yet (new game, alt-tabbed): anything running from a launcher's game library folder is a game too.
# Launchers themselves and always-on Steam tools (Wallpaper Engine, Lossless Scaling) live elsewhere or are skipped by name.
$libs = '\\steamapps\\common\\|\\Epic Games\\(?!Launcher\\)|\\XboxGames\\(?!GameSave\\)|\\EA Games\\|\\GOG Galaxy\\Games\\|\\GOG Games\\|\\Ubisoft Game Launcher\\games\\'
$tools = 'wallpaper32', 'wallpaper64', 'webwallpaper32', 'ui32', 'LosslessScaling', 'UnityCrashHandler64', 'UnityCrashHandler32', 'CrashReportClient'
$lib = Get-Process | Where-Object { $_.Path -match $libs -and $_.ProcessName -notin $tools -and $_.ProcessName -notin $notGames } | Select-Object -First 1
if ($lib) { if ($Explain) { "$($lib.ProcessName) - running from a game library ($(Split-Path $lib.Path))" } else { $lib.ProcessName } }
elseif ($Explain) { "no game (foreground: $fgName)" }
