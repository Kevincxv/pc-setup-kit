# The app's place in Windows: the login task that starts it with its tray icon (MessiahApp.exe --tray, in the hidden ^
# area next to the clock), the app's icon, and its Start menu entry (the app window).
# Safe to run again (setup, background maintenance): changes only what's missing or outdated, one line per change.
param([string]$TrayDir = "$env:USERPROFILE\Documents\Messiah Tray", [string]$ClaudeDir = $PSScriptRoot,
    [string]$Ahk, [switch]$NoRestart, [switch]$Desktop)   # (-Ahk: no longer used - the tray was an AutoHotkey script before 10/21)   # -NoRestart: setup starts the tray itself; -Desktop: also a desktop entry (setup)
if (-not (Test-Path "$ClaudeDir\app\MessiahApp.exe")) { return }   # (the app window; not installed: nothing to make entries for)
$ai = if (Test-Path "$ClaudeDir\ai-enabled.ps1") { & "$ClaudeDir\ai-enabled.ps1" } else { $true }
$name = 'Messiah'   # one app, with or without the AI assistant (before: "PC Setup Kit" without it - moved over below)
$changed = $false

# the app's icon (drawn by app-icon.ps1; drawn again when its drawing changes)
$ico = "$TrayDir\app.ico"
$iconVer = if (Test-Path "$ClaudeDir\app-icon.ps1") { (Select-String -Path "$ClaudeDir\app-icon.ps1" -Pattern '^\$version = (\d+)' | Select-Object -First 1).Matches.Groups[1].Value }
if ($iconVer -and (-not (Test-Path $ico) -or "$(Get-Content "$ico.version" -ErrorAction SilentlyContinue)" -ne "v$iconVer")) {
    try { & "$ClaudeDir\app-icon.ps1" -Path $ico -ErrorAction Stop | Out-Null; "App: new icon"; $changed = $true }
    catch { "App: couldn't draw the icon ($($_.Exception.Message)) - will retry" }
}
$iconLoc = if (Test-Path $ico) { "$ico,0" } else { "$env:SystemRoot\System32\imageres.dll,110" }

# One app: the Start menu entry "<name>" (and the desktop one, where there is one) opens the app window (MessiahApp.exe).
# With Claude, the elevated session launcher those entries used to open is kept as
# .claude\Messiah Session.lnk (the app's "New session" and the tray use it). The old "<name> Status" entry goes.
$sm = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
$ws = New-Object -ComObject WScript.Shell
$appTarget = "$ClaudeDir\app\MessiahApp.exe"; $appArgs = '--live'
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
    if ((Test-Path -LiteralPath $lnk) -and ($s = $ws.CreateShortcut($lnk)).Arguments -eq $appArgs -and $s.TargetPath -eq $appTarget -and $s.IconLocation -eq $iconLoc) { return $false }
    New-Item (Split-Path $lnk) -ItemType Directory -Force | Out-Null
    if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }   # a fresh one: an old launcher's "Run as administrator" flag must not stay
    $s = $ws.CreateShortcut($lnk)
    $s.TargetPath = $appTarget; $s.Arguments = $appArgs; $s.WorkingDirectory = $ClaudeDir
    $s.IconLocation = $iconLoc; $s.Description = "$name - what the PC's maintenance is doing, and anything that needs you"
    $s.Save(); $true
}
if (Set-AppShortcut "$sm\$name.lnk") { "App: Start menu entry '$name' opens the app" }
$desk = "$env:USERPROFILE\Desktop\$name.lnk"   # only where there is one (setup: -Desktop); never brought back once deleted
# the app was "PC Setup Kit" without the AI assistant: its entries become "Messiah" (a desktop one stays a desktop one)
if (Test-Path -LiteralPath "$env:USERPROFILE\Desktop\PC Setup Kit.lnk") { Remove-Item -LiteralPath "$env:USERPROFILE\Desktop\PC Setup Kit.lnk" -Force; $Desktop = $true; "App: the desktop 'PC Setup Kit' is now 'Messiah'" }
if (Test-Path -LiteralPath "$sm\PC Setup Kit.lnk") { Remove-Item -LiteralPath "$sm\PC Setup Kit.lnk" -Force; "App: the Start menu 'PC Setup Kit' is now 'Messiah'" }
if (($Desktop -or (Test-Path -LiteralPath $desk)) -and (Set-AppShortcut $desk)) { "App: desktop '$name' opens the app" }
foreach ($old in "$sm\Messiah Status.lnk", "$sm\PC Setup Kit Status.lnk") {
    if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force; "App: removed the old Start menu entry '$([IO.Path]::GetFileNameWithoutExtension($old))'" }
}

# the login task: the app with its tray icon (MessiahApp.exe --tray - before 10/21 an AutoHotkey script under the name
# Messiah.exe); elevated (it hides admin windows and starts what needs admin rights), no time limit, restarts if it stops
$t = Get-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue
if (-not $t -or $t.Actions[0].Execute -ne $appTarget -or $t.Actions[0].Arguments -ne '--live --tray') {
    $act = New-ScheduledTaskAction -Execute $appTarget -Argument '--live --tray' -WorkingDirectory $ClaudeDir
    $trg = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $prn = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
    Register-ScheduledTask -TaskName 'Messiah Tray' -Action $act -Trigger $trg -Principal $prn -Settings $set -Force | Out-Null
    "Tray: $(if ($t) { 'now part of the app (MessiahApp.exe) - AutoHotkey no longer runs it' } else { 'starts with Windows' })"
    $changed = $true
}
# the tray restarted on the app (the AutoHotkey tray before it stopped: one icon, one keeper of the sessions)
if ($changed -and -not $NoRestart) {
    Stop-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe' OR Name='Messiah.exe' OR Name='PC Setup Kit.exe'" -ErrorAction SilentlyContinue |
        Where-Object CommandLine -match 'Messiah Tray\.ahk' | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue
}
# AutoHotkey's copies under the app's old names, once nothing runs them
foreach ($old in "$TrayDir\$name.exe", "$TrayDir\PC Setup Kit.exe") {
    if ((Test-Path -LiteralPath $old) -and -not (Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object ExecutablePath -eq $old)) {
        try { [IO.File]::Delete($old); "Tray: removed $(Split-Path $old -Leaf) (AutoHotkey's copy)" } catch {}
    }
}