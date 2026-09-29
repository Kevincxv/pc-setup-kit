# Settings backup, so reinstalling Windows with the kit brings the PC back as it was - no setup work:
# - the look: wallpaper (the image itself), dark/light mode, accent colour, transparency, taskbar layout, Start pins,
#   mouse speed and pointers
# - game settings: Documents\My Games, Saved Games, Unreal-engine games' config folders, Steam's library list and
#   launch options (files over 10 MB are skipped - saves live in the cloud; this is about settings)
# - the kit's own memory: games list, to-do items, what the owner chose to ignore, the health and game history
# Weekly (periodic-maint.ps1), a zip to "PC Setup Kit Backup" on a second drive - or, with only one drive, on the kit
# USB when it's plugged in, else in Documents (lost with a full wipe, kept by "Reset this PC, keep my files").
# The newest 4 are kept. setup.ps1 runs -Restore on a new install: it restores only a backup made on THIS PC (the
# motherboard's id), so a kit USB used for friends' PCs never puts one person's settings on another's PC.
# Not included on purpose: resolution/scaling (display-refresh.ps1 sets the best for each monitor), desktop icon
# positions (not restorable reliably), the lock screen picture (needs a policy).
# -ToUsb: the tray runs it when a drive is plugged in - a kit USB (PCSetupKit\setup.ps1 on it) gets a fresh backup, once a day, so
# it's there for a full reinstall even on a one-drive PC.
# -Restore [-From zip]; -Force (back up even if one is recent); tests: -RegRoot -HomeDir -Dest -NoApply -MachineId
param([switch]$Restore, [string]$From, [switch]$Force, [switch]$ToUsb, [string]$RegRoot = 'HKCU:', [string]$HomeDir = $env:USERPROFILE, [string[]]$Dest,
    [switch]$NoApply, [string]$MachineId, [string]$ClaudeDir = $PSScriptRoot)
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (-not $MachineId) { $MachineId = "$((Get-CimInstance Win32_ComputerSystemProduct).UUID)" }
# a registry value, or nothing (Get-ItemPropertyValue throws when the key exists without the value - Steam's key on a
# new install has no SteamPath until Steam first runs: found by the Sandbox test)
function Get-RegValue([string]$Key, [string]$Name) { $k = Get-Item $Key -ErrorAction SilentlyContinue; if ($k) { $k.GetValue($Name) } }
# the real profile's folders (Documents may be moved) only for the real profile - [Environment]'s own answer, not
# $env:USERPROFILE: a test with a made-up USERPROFILE once restored into the owner's real registry (9/28)
$real = $HomeDir -eq [Environment]::GetFolderPath('UserProfile')
$la = if ($real) { [Environment]::GetFolderPath('LocalApplicationData') } else { "$HomeDir\AppData\Local" }
$ad = if ($real) { [Environment]::GetFolderPath('ApplicationData') } else { "$HomeDir\AppData\Roaming" }
$docs = if ($real) { [Environment]::GetFolderPath('MyDocuments') } else { "$HomeDir\Documents" }
# under tests: never the real registry or the real backup folders
if ($env:PCKIT_IN_TESTS -and ($RegRoot -eq 'HKCU:' -or $real -or -not ($Dest -or $From))) { return }
# registry values that make up the look (key under HKCU -> value names)
$reg = [ordered]@{
    'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' = 'AppsUseLightTheme', 'SystemUsesLightTheme', 'EnableTransparency', 'ColorPrevalence'
    'Software\Microsoft\Windows\DWM'                               = 'ColorPrevalence', 'AccentColor', 'ColorizationColor', 'ColorizationAfterglow', 'AccentColorInactive'
    'Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'    = 'AccentColorMenu', 'StartColorMenu', 'AccentPalette'
    'Control Panel\Desktop'                                        = 'WallpaperStyle', 'TileWallpaper'
    'Control Panel\Colors'                                         = 'Background'
    'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'  = 'TaskbarAl', 'ShowTaskViewButton', 'TaskbarMn', 'TaskbarSi', 'Start_Layout', 'HideFileExt', 'Hidden', 'LaunchTo'
    'Software\Microsoft\Windows\CurrentVersion\Search'             = 'SearchboxTaskbarMode'
    'Control Panel\Mouse'                                          = 'MouseSensitivity', 'MouseSpeed', 'MouseThreshold1', 'MouseThreshold2'
    'Control Panel\Cursors'                                        = '*'
}
$startBin = "$la\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start2.bin"
$kitFiles = 'health-ignore.txt', 'games.txt', 'todo-scripted.json', 'health-history.json', 'perf-history.json', 'net-history.json', 'benchmarks.json', 'driver-blocklist.txt'
function Get-SteamDir { $p = "$(Get-RegValue "$RegRoot\Software\Valve\Steam" SteamPath)"
    if (-not $p -and $RegRoot -eq 'HKCU:') { $p = "$(Get-RegValue 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' InstallPath)" }   # just installed, never started
    $p -replace '/', '\' }
$steam = Get-SteamDir
# game settings: (folder, where it goes back) - relative paths inside the zip under games\
function Get-GameSources {
    @{ Zip = 'MyGames'; Path = "$docs\My Games" }, @{ Zip = 'SavedGames'; Path = "$HomeDir\Saved Games" }
    foreach ($c in Get-ChildItem "$la\*\Saved\Config" -Directory) { @{ Zip = "Unreal\$($c.Parent.Parent.Name)"; Path = $c.FullName } }
}
function Get-Destinations {
    if ($Dest) { return $Dest }
    $sys = $env:SystemDrive.TrimEnd(':')
    $second = @(Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter -and "$($_.DriveLetter)" -ne $sys -and $_.SizeRemaining -gt 2GB } | ForEach-Object { "$($_.DriveLetter):\PC Setup Kit Backup" })
    if ($second) { return $second | Select-Object -First 1 }
    $usb = @(Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter -and (Test-Path "$($_.DriveLetter):\PCSetupKit\setup.ps1") } | ForEach-Object { "$($_.DriveLetter):\PC Setup Kit Backup" })
    @($usb) + "$docs\PC Setup Kit Backup"
}

if (-not $Restore) {
    $dests = @(Get-Destinations)
    if ($ToUsb) {
        $dests = @(if ($Dest) { $Dest } else { Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter -and (Test-Path "$($_.DriveLetter):\PCSetupKit\setup.ps1") } | ForEach-Object { "$($_.DriveLetter):\PC Setup Kit Backup" } })
        if (-not $dests -or ($dests | Where-Object { Test-Path "$_\$env:COMPUTERNAME-$(Get-Date -Format 'yyyy-MM-dd').zip" })) { return }   # no kit USB, or already today's
        $Force = $true
    }
    $newest = $dests | ForEach-Object { Get-ChildItem "$_\*.zip" } | Sort-Object LastWriteTime | Select-Object -Last 1
    if (-not $Force -and $newest -and $newest.LastWriteTime -gt (Get-Date).AddDays(-6)) { return }
    $st = Join-Path $env:TEMP "pckit-backup-$PID"; New-Item $st -ItemType Directory -Force | Out-Null
    # the look
    $look = [ordered]@{}
    foreach ($k in $reg.Keys) {
        $item = Get-Item "$RegRoot\$k"; if (-not $item) { continue }
        $names = if ($reg[$k] -eq '*') { $item.Property } else { $reg[$k] }
        $vals = [ordered]@{}
        foreach ($n in $names) {
            $v = $item.GetValue($n, $null, 'DoNotExpandEnvironmentNames'); if ($null -eq $v) { continue }
            $vals[$n] = @{ kind = "$($item.GetValueKind($n))"; value = $(if ($v -is [byte[]]) { [Convert]::ToBase64String($v) } else { $v }) }
        }
        if ($vals.Count) { $look[$k] = $vals }
    }
    $wp = "$(Get-RegValue "$RegRoot\Control Panel\Desktop" WallPaper)"
    if (-not (Test-Path $wp)) { $wp = "$ad\Microsoft\Windows\Themes\TranscodedWallpaper" }   # Windows' own copy (the original may be gone)
    if ($wp -and (Test-Path $wp)) { Copy-Item $wp "$st\wallpaper$(if ([IO.Path]::GetExtension($wp)) { [IO.Path]::GetExtension($wp) } else { '.jpg' })" }
    if (Test-Path $startBin) { Copy-Item $startBin "$st\start2.bin" }
    [ordered]@{ machine = $MachineId; computer = $env:COMPUTERNAME; date = (Get-Date).ToString('o'); look = $look } | ConvertTo-Json -Depth 5 | Set-Content "$st\backup.json" -Encoding UTF8
    # the kit's memory
    New-Item "$st\kit" -ItemType Directory -Force | Out-Null
    foreach ($f in $kitFiles) { if (Test-Path "$ClaudeDir\$f") { Copy-Item "$ClaudeDir\$f" "$st\kit\" } }
    # game settings (10 MB per file, 300 MB in all)
    $total = 0L
    foreach ($g in Get-GameSources) {
        if (-not (Test-Path $g.Path)) { continue }
        $base = (Get-Item -LiteralPath $g.Path -Force).FullName   # the long form: a short 8.3 path (RUNNER~1) would shift every relative path
        foreach ($f in Get-ChildItem -LiteralPath $base -Recurse -File -Force | Where-Object { $_.Length -le 10MB }) {
            if (($total += $f.Length) -gt 300MB) { break }
            $to = Join-Path "$st\games\$($g.Zip)" $f.FullName.Substring($base.Length).TrimStart('\')
            New-Item (Split-Path $to) -ItemType Directory -Force | Out-Null; Copy-Item $f.FullName $to
        }
    }
    if ($steam -and (Test-Path "$steam\config\libraryfolders.vdf")) {
        New-Item "$st\steam" -ItemType Directory -Force | Out-Null; Copy-Item "$steam\config\libraryfolders.vdf" "$st\steam\"
        foreach ($u in Get-ChildItem "$steam\userdata\*\config\localconfig.vdf") { New-Item "$st\steam\$($u.Directory.Parent.Name)" -ItemType Directory -Force | Out-Null; Copy-Item $u.FullName "$st\steam\$($u.Directory.Parent.Name)\" }
    }
    $zip = "$env:COMPUTERNAME-$(Get-Date -Format 'yyyy-MM-dd').zip"; $ok = @()
    foreach ($d in $dests) {
        try {
            New-Item $d -ItemType Directory -Force -ErrorAction Stop | Out-Null
            if (Test-Path "$d\$zip") { [IO.File]::Delete("$d\$zip") }
            [IO.Compression.ZipFile]::CreateFromDirectory($st, "$d\$zip"); $ok += $d
            Get-ChildItem "$d\$env:COMPUTERNAME-*.zip" | Sort-Object Name -Descending | Select-Object -Skip 4 | ForEach-Object { [IO.File]::Delete($_.FullName) }
        } catch { }
    }
    [IO.Directory]::Delete($st, $true)
    if ($ok) { "Backup: settings saved (look, game settings, the kit's memory) to $($ok -join ', ')" } else { 'Backup FAILED: no place to save the settings to' }
    return
}

# ---------- restore (setup.ps1, on a new install) ----------
if (-not $From) {
    $roots = @(Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object { "$($_.DriveLetter):\PC Setup Kit Backup" }) + "$docs\PC Setup Kit Backup" + @($Dest)
    $cands = @($roots | Where-Object { $_ -and (Test-Path $_) } | ForEach-Object { Get-ChildItem "$_\*.zip" } | Sort-Object LastWriteTime -Descending)
    foreach ($c in $cands) {
        try {
            $z = [IO.Compression.ZipFile]::OpenRead($c.FullName)
            $meta = (New-Object IO.StreamReader($z.GetEntry('backup.json').Open())).ReadToEnd() | ConvertFrom-Json; $z.Dispose()
            if ($meta.machine -and $meta.machine -eq $MachineId) { $From = $c.FullName; break }
        } catch { try { $z.Dispose() } catch { } }
    }
    if (-not $From) { if ($cands) { 'Restore: the settings backups found were made on other PCs - not used here' }; return }
}
$st = Join-Path $env:TEMP "pckit-restore-$PID"
try { [IO.Compression.ZipFile]::ExtractToDirectory($From, $st) } catch { "Restore FAILED: $From could not be opened"; return }
$meta = Get-Content "$st\backup.json" -Raw | ConvertFrom-Json
if ($meta.machine -ne $MachineId) { [IO.Directory]::Delete($st, $true); 'Restore: that backup was made on another PC - not used'; return }
$done = @()
# the look
foreach ($k in $meta.look.PSObject.Properties) {
    if (-not (Test-Path "$RegRoot\$($k.Name)")) { New-Item "$RegRoot\$($k.Name)" -Force | Out-Null }   # (never -Force on an existing key: that empties it)
    foreach ($v in $k.Value.PSObject.Properties) {
        $val = if ($v.Value.kind -eq 'Binary') { [Convert]::FromBase64String($v.Value.value) } else { $v.Value.value }
        Set-ItemProperty "$RegRoot\$($k.Name)" -Name $v.Name -Value $val -Type $v.Value.kind
    }
}
if ($meta.look) { $done += 'colours and dark mode, taskbar, mouse' }
$wpf = Get-ChildItem "$st\wallpaper*" | Select-Object -First 1
if ($wpf) {
    $keep = "$ad\Microsoft\Windows\Themes\PC Setup Kit wallpaper$($wpf.Extension)"
    New-Item (Split-Path $keep) -ItemType Directory -Force | Out-Null; Copy-Item $wpf.FullName $keep -Force
    if (-not (Test-Path "$RegRoot\Control Panel\Desktop")) { New-Item "$RegRoot\Control Panel\Desktop" -Force | Out-Null }
    Set-ItemProperty "$RegRoot\Control Panel\Desktop" -Name WallPaper -Value $keep; $done += 'wallpaper'
}
if ((Test-Path "$st\start2.bin") -and (Test-Path (Split-Path $startBin))) { Copy-Item "$st\start2.bin" $startBin -Force; $done += 'Start pins' }
# the kit's memory: only what a new install doesn't have yet
foreach ($f in Get-ChildItem "$st\kit" -File) { if (-not (Test-Path "$ClaudeDir\$($f.Name)")) { Copy-Item $f.FullName $ClaudeDir } }
if (Get-ChildItem "$st\kit" -File) { $done += "the kit's memory (games, to-do, history)" }
# game settings: never over a file that's already there
$map = @{ MyGames = "$docs\My Games"; SavedGames = "$HomeDir\Saved Games" }
$n = 0
foreach ($g in Get-ChildItem "$st\games" -Directory) {
    $subs = if ($g.Name -eq 'Unreal') { Get-ChildItem $g.FullName -Directory | ForEach-Object { @{ From = $_.FullName; To = "$la\$($_.Name)\Saved\Config" } } } else { @{ From = $g.FullName; To = $map[$g.Name] } }
    foreach ($s in $subs | Where-Object { $_.To }) {
        foreach ($f in Get-ChildItem $s.From -Recurse -File -Force) {
            $to = Join-Path $s.To $f.FullName.Substring($s.From.Length).TrimStart('\')
            if (-not (Test-Path $to)) { New-Item (Split-Path $to) -ItemType Directory -Force | Out-Null; Copy-Item $f.FullName $to; $n++ }
        }
    }
}
if ($n) { $done += "game settings ($n files)" }
# Steam: the library list only if Steam is installed, closed, and every library in it exists on this PC
$steam = Get-SteamDir
if ($steam -and (Test-Path "$st\steam\libraryfolders.vdf") -and -not (Get-Process steam)) {
    $libs = @(Select-String -Path "$st\steam\libraryfolders.vdf" -Pattern '"path"\s+"([^"]+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' })
    if ($libs -and -not ($libs | Where-Object { -not (Test-Path $_) })) { New-Item "$steam\config" -ItemType Directory -Force | Out-Null; Copy-Item "$st\steam\libraryfolders.vdf" "$steam\config\" -Force; $done += "Steam's game libraries ($($libs.Count))" }
    foreach ($u in Get-ChildItem "$st\steam" -Directory) { $to = "$steam\userdata\$($u.Name)\config"; if (-not (Test-Path "$to\localconfig.vdf")) { New-Item $to -ItemType Directory -Force | Out-Null; Copy-Item "$($u.FullName)\localconfig.vdf" $to } }
}
[IO.Directory]::Delete($st, $true)
# make the look take effect now: wallpaper, colours, mouse, then the taskbar and Start (Explorer restarts itself)
if (-not $NoApply -and $done) {
    Add-Type -Namespace KitBk -Name W -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool SystemParametersInfo(uint a, uint b, string c, uint d);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool SystemParametersInfo(uint a, uint b, IntPtr c, uint d);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, string l, uint f, uint t, out IntPtr r);
'@
    if ($wpf) { [void][KitBk.W]::SystemParametersInfo(0x14, 0, $keep, 3) }                           # SPI_SETDESKWALLPAPER
    $ms = "$(Get-RegValue "$RegRoot\Control Panel\Mouse" MouseSensitivity)"
    if ($ms -match '^\d+$') { [void][KitBk.W]::SystemParametersInfo(0x71, 0, [IntPtr][int]$ms, 3) }   # SPI_SETMOUSESPEED
    [void][KitBk.W]::SystemParametersInfo(0x57, 0, [IntPtr]::Zero, 3)                                  # SPI_SETCURSORS (reload)
    $r = [IntPtr]::Zero; [void][KitBk.W]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [IntPtr]::Zero, 'ImmersiveColorSet', 2, 2000, [ref]$r)
    Get-Process explorer, StartMenuExperienceHost | Stop-Process -Force
}
if ($done) { "Restore: brought back from the backup of $(([datetime]$meta.date).ToString('d')) - $($done -join ', ')" }
