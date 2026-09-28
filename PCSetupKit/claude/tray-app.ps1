# The tray as its own app: AutoHotkey runs the tray script under the app's name (Messiah.exe, or PC Setup Kit.exe
# without Claude). Windows keeps one tray entry per program, and every AutoHotkey script otherwise shares AutoHotkey's
# (hidden in the ^ area by default) - with its own name the tray can pin its icon next to the clock (the tray does that
# once). Also: the login task that starts it, and the Start menu entry for the Status window (dashboard.ps1).
# Safe to run again (setup, background maintenance): changes only what's missing or outdated, one line per change.
param([string]$TrayDir = "$env:USERPROFILE\Documents\Messiah Tray", [string]$ClaudeDir = $PSScriptRoot,
    [string]$Ahk = "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe", [switch]$NoRestart)   # -NoRestart: setup starts the tray itself
$script = "$TrayDir\Messiah Tray.ahk"
if (-not (Test-Path $Ahk) -or -not (Test-Path $script)) { return }
$ai = if (Test-Path "$ClaudeDir\ai-enabled.ps1") { & "$ClaudeDir\ai-enabled.ps1" } else { $true }
$name = if ($ai) { 'Messiah' } else { 'PC Setup Kit' }
$exe = "$TrayDir\$name.exe"
$changed = $false

# AutoHotkey under the app's name (a plain copy, signature intact); refreshed after AutoHotkey updates
$from = Get-Item $Ahk
$have = Get-Item $exe -ErrorAction SilentlyContinue
if (-not $have -or $have.Length -ne $from.Length -or $have.VersionInfo.FileVersion -ne $from.VersionInfo.FileVersion) {
    # the running tray holds the old copy: stop it first (the task starts it again below)
    Get-CimInstance Win32_Process -Filter "Name='$name.exe'" -ErrorAction SilentlyContinue | Where-Object ExecutablePath -eq $exe | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; $changed = $true }
    try { Copy-Item $Ahk $exe -Force -ErrorAction Stop; "Tray: runs as $name.exe$(if ($have) { " (AutoHotkey $($from.VersionInfo.FileVersion))" } else { ' - its own icon next to the clock' })"; $changed = $true }
    catch { "Tray: couldn't copy AutoHotkey to $name.exe ($($_.Exception.Message)) - will retry"; return }
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

# Start menu: "<name> Status" opens the Status window (no console: conhost --headless)
$lnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$name Status.lnk"
$want = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ClaudeDir\dashboard.ps1`""
$ws = New-Object -ComObject WScript.Shell
if (-not (Test-Path $lnk) -or $ws.CreateShortcut($lnk).Arguments -ne $want) {
    New-Item (Split-Path $lnk) -ItemType Directory -Force | Out-Null
    $s = $ws.CreateShortcut($lnk)
    $s.TargetPath = "$env:SystemRoot\System32\conhost.exe"; $s.Arguments = $want; $s.WorkingDirectory = $ClaudeDir
    $s.IconLocation = if ($ai -and (Test-Path "$env:USERPROFILE\.local\bin\claude.exe")) { "$env:USERPROFILE\.local\bin\claude.exe,0" } else { "$env:SystemRoot\System32\imageres.dll,110" }
    $s.Description = "What the PC's maintenance is doing and anything that needs you"
    $s.Save()
    "Tray: Start menu entry '$name Status' (the Status window)"
}

# restart the tray on the new program (it sees an open Messiah session and won't open a second one)
if ($changed -and -not $NoRestart) {
    Stop-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe' OR Name='Messiah.exe' OR Name='PC Setup Kit.exe'" -ErrorAction SilentlyContinue |
        Where-Object CommandLine -match 'Messiah Tray\.ahk' | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue
}
