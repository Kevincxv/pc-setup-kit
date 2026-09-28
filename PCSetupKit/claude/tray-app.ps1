# The tray as its own app: AutoHotkey runs the tray script under the app's name (Messiah.exe, or PC Setup Kit.exe
# without Claude). Windows keeps one tray entry per program, and every AutoHotkey script otherwise shares AutoHotkey's
# (hidden in the ^ area by default) - with its own name the tray can pin its icon next to the clock (the tray does that
# once). Also: the login task that starts it, the app's icon, and its Start menu entry (the app window, dashboard.ps1).
# Safe to run again (setup, background maintenance): changes only what's missing or outdated, one line per change.
param([string]$TrayDir = "$env:USERPROFILE\Documents\Messiah Tray", [string]$ClaudeDir = $PSScriptRoot,
    [string]$Ahk = "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe", [switch]$NoRestart, [switch]$Desktop)   # -NoRestart: setup starts the tray itself; -Desktop: also a desktop entry (setup)
$script = "$TrayDir\Messiah Tray.ahk"
if (-not (Test-Path "$ClaudeDir\dashboard.ps1")) { return }
$hasAhk = (Test-Path $Ahk) -and (Test-Path $script)   # without AutoHotkey: the app (window, icon, Start menu) but no tray icon
$ai = if (Test-Path "$ClaudeDir\ai-enabled.ps1") { & "$ClaudeDir\ai-enabled.ps1" } else { $true }
$name = if ($ai) { 'Messiah' } else { 'PC Setup Kit' }
$exe = "$TrayDir\$name.exe"
$changed = $false

# the app's icon (drawn by app-icon.ps1; drawn again when its drawing changes)
$ico = "$TrayDir\app.ico"
$iconVer = if (Test-Path "$ClaudeDir\app-icon.ps1") { (Select-String -Path "$ClaudeDir\app-icon.ps1" -Pattern '^\$version = (\d+)' | Select-Object -First 1).Matches.Groups[1].Value }
if ($iconVer -and (-not (Test-Path $ico) -or "$(Get-Content "$ico.version" -ErrorAction SilentlyContinue)" -ne "v$iconVer")) {
    try { & "$ClaudeDir\app-icon.ps1" -Path $ico -ErrorAction Stop | Out-Null; "App: new icon"; $changed = $true }
    catch { "App: couldn't draw the icon ($($_.Exception.Message)) - will retry" }
}
$iconLoc = if (Test-Path $ico) { "$ico,0" } else { "$env:SystemRoot\System32\imageres.dll,110" }

# One app: the Start menu entry "<name>" (and the desktop one, where there is one) opens the app window (dashboard.ps1,
# no console: conhost --headless). With Claude, the elevated session launcher those entries used to open is kept as
# .claude\Messiah Session.lnk (the app's "New session" and the tray use it). The old "<name> Status" entry goes.
$sm = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
$ws = New-Object -ComObject WScript.Shell
$appArgs = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ClaudeDir\dashboard.ps1`""
$session = "$ClaudeDir\Messiah Session.lnk"
$launcher = "$ClaudeDir\claude-admin-launch.ps1"
if ($ai -and (Test-Path $launcher)) {
    foreach ($old in "$sm\Messiah.lnk", "$env:USERPROFILE\Desktop\Messiah.lnk", "$sm\Claude (Admin).lnk") {
        if ((Test-Path -LiteralPath $old) -and $ws.CreateShortcut($old).Arguments -match 'claude-admin-launch\.ps1' -and -not (Test-Path $session)) {
            Copy-Item -LiteralPath $old $session   # keeps "Run as administrator"
        }
    }
    $s = if (Test-Path $session) { $ws.CreateShortcut($session) }
    if (-not $s -or $s.Arguments -notmatch 'claude-admin-launch\.ps1' -or $s.IconLocation -ne $iconLoc) {
        $s = $ws.CreateShortcut($session)
        $s.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $s.Arguments = "-NoExit -NoLogo -ExecutionPolicy Bypass -File `"$launcher`""
        $s.WorkingDirectory = "$env:SystemRoot\System32"; $s.IconLocation = $iconLoc; $s.Description = 'A new Messiah session (Claude Code with admin rights)'
        $s.Save()
        $b = [IO.File]::ReadAllBytes($session); $b[0x15] = $b[0x15] -bor 0x20; [IO.File]::WriteAllBytes($session, $b)   # "Run as administrator"
    }
}
function Set-AppShortcut($lnk) {
    if ((Test-Path -LiteralPath $lnk) -and ($s = $ws.CreateShortcut($lnk)).Arguments -eq $appArgs -and $s.IconLocation -eq $iconLoc) { return $false }
    New-Item (Split-Path $lnk) -ItemType Directory -Force | Out-Null
    if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }   # a fresh one: an old launcher's "Run as administrator" flag must not stay
    $s = $ws.CreateShortcut($lnk)
    $s.TargetPath = "$env:SystemRoot\System32\conhost.exe"; $s.Arguments = $appArgs; $s.WorkingDirectory = $ClaudeDir
    $s.IconLocation = $iconLoc; $s.Description = "$name - what the PC's maintenance is doing, and anything that needs you"
    $s.Save(); $true
}
if (Set-AppShortcut "$sm\$name.lnk") { "App: Start menu entry '$name' opens the app" }
$desk = "$env:USERPROFILE\Desktop\$name.lnk"   # only where there is one (setup: -Desktop); never brought back once deleted
if (($Desktop -or (Test-Path -LiteralPath $desk)) -and (Set-AppShortcut $desk)) { "App: desktop '$name' opens the app" }
foreach ($old in "$sm\Messiah Status.lnk", "$sm\PC Setup Kit Status.lnk") {
    if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force; "App: removed the old Start menu entry '$([IO.Path]::GetFileNameWithoutExtension($old))'" }
}

if ($hasAhk) {
    # AutoHotkey under the app's name (a plain copy, signature intact); refreshed after AutoHotkey updates
    $from = Get-Item $Ahk
    $have = Get-Item $exe -ErrorAction SilentlyContinue
    if (-not $have -or $have.Length -ne $from.Length -or $have.VersionInfo.FileVersion -ne $from.VersionInfo.FileVersion) {
        # the running tray holds the old copy: stop it first (the task starts it again below)
        Get-CimInstance Win32_Process -Filter "Name='$name.exe'" -ErrorAction SilentlyContinue | Where-Object ExecutablePath -eq $exe | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; $changed = $true }
        try { Copy-Item $Ahk $exe -Force -ErrorAction Stop; "Tray: runs as $name.exe$(if ($have) { " (AutoHotkey $($from.VersionInfo.FileVersion))" } else { ' - its own icon next to the clock' })"; $changed = $true }
        catch {
            "Tray: couldn't copy AutoHotkey to $name.exe ($($_.Exception.Message)) - will retry"
            if ($have -and -not $NoRestart) { Start-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue }   # the old copy still works: never leave the tray off
            return
        }
    }

    # the login task: elevated (it hides admin windows), no time limit, restarts if it ever stops
    $arg = "`"$script`""
    $t = Get-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue
    if (-not $t -or $t.Actions[0].Execute -ne $exe -or $t.Actions[0].Arguments -ne $arg) {
        $act = New-ScheduledTaskAction -Execute $exe -Argument $arg
        $trg = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
        $prn = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
        Register-ScheduledTask -TaskName 'Messiah Tray' -Action $act -Trigger $trg -Principal $prn -Settings $set -Force | Out-Null
        if ($t) { "Tray: login task now starts $name.exe" }
        $changed = $true
    }
}

# restart the tray on the new program (it sees an open Messiah session and won't open a second one)
if ($hasAhk -and $changed -and -not $NoRestart) {
    Stop-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe' OR Name='Messiah.exe' OR Name='PC Setup Kit.exe'" -ErrorAction SilentlyContinue |
        Where-Object CommandLine -match 'Messiah Tray\.ahk' | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue
}
