# PC Setup Kit - first-logon setup. Started automatically by autounattend.xml (FirstLogonCommands) from the USB.
# Can also be run by hand on an existing Windows 11 PC: right-click > Run with PowerShell (it asks for admin).
# Steps: copy kit to C:\PCSetupKit > tweaks > power plan > remove OneDrive > install apps > maintenance (scripts, login
# task, tray). No AI needed: everything is scripts.
# -WithClaude: also install the optional Claude part (Messiah: Claude Code with admin rights, needs the owner's own Claude
#   account) and open it with the /pc-optimize playbook at the end. From the USB: a file "with-claude.txt" next to setup.ps1.
# -NoLaunch: open nothing at the end (the fresh-install test on GitHub: nobody is there).
param([switch]$NoLaunch, [switch]$WithClaude)
if (Test-Path "$PSScriptRoot\with-claude.txt") { $WithClaude = $true }
$ErrorActionPreference = 'Continue'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") + @(if ($NoLaunch) { '-NoLaunch' }) + @(if ($WithClaude) { '-WithClaude' }))
    exit
}

$Host.UI.RawUI.WindowTitle = 'PC Setup Kit - setting up this PC (do not close)'
$src = Split-Path -Parent $PSCommandPath
$kit = 'C:\PCSetupKit'
if ($src -ne $kit) { New-Item $kit -ItemType Directory -Force | Out-Null; Copy-Item "$src\*" $kit -Recurse -Force }
if ((Test-Path "$kit\kit-version.txt") -and (Test-Path "$kit\tests")) { Copy-Item "$kit\kit-version.txt" "$kit\tests\tests-version.txt" -Force }   # tests match this release (self-test.ps1)
Start-Transcript "$kit\setup.log" -Append | Out-Null
function Step($msg) { Write-Host "`n=== $msg" -ForegroundColor Cyan }

Step 'Waiting for internet'
for ($i = 0; $i -lt 60 -and -not (Test-NetConnection 1.1.1.1 -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue); $i++) { Start-Sleep 5 }

Step 'Applying Windows tweaks'
& "$kit\tweaks.ps1" | ForEach-Object { "  $_" }

Step 'Power plan: Ultimate Performance, no USB sleep, no hibernation'
$ult = powercfg /list | Select-String 'Ultimate Performance' | Select-Object -First 1
if (-not $ult) { powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-Null; $ult = powercfg /list | Select-String 'Ultimate Performance' | Select-Object -First 1 }
if ($ult -match '([0-9a-f-]{36})') { powercfg /setactive $Matches[1] }
powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
powercfg /setactive SCHEME_CURRENT
powercfg /hibernate off

Step 'Removing OneDrive'
Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force
foreach ($o in "$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe", (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\OneDrive\*\OneDriveSetup.exe" -ErrorAction SilentlyContinue).FullName) {
    if ($o -and (Test-Path $o)) { Start-Process $o '/uninstall' -Wait }
}
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name OneDrive -ErrorAction SilentlyContinue

Step 'Getting winget ready'
for ($i = 0; $i -lt 40 -and -not (Get-Command winget -ErrorAction SilentlyContinue); $i++) {
    if ($i -eq 0) { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue }
    Start-Sleep 15
}
winget source update --accept-source-agreements | Out-Null

Step 'Installing apps'
# WinDbg: automatic crash-dump diagnosis; AutoHotkey (v2): the tray icon
foreach ($id in 'Git.Git', 'Valve.Steam', 'Discord.Discord', 'Google.Chrome', 'Microsoft.WinDbg', 'AutoHotkey.AutoHotkey') {
    Write-Host "  $id"
    winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity | Select-Object -Last 1
}
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')

if (Get-CimInstance Win32_VideoController | Where-Object Name -match 'NVIDIA') {
    Write-Host '  NVIDIA App (NVIDIA graphics card found)'
    try {
        $page = Invoke-WebRequest 'https://www.nvidia.com/en-us/software/nvidia-app/' -UseBasicParsing -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
        $url = ([regex]::Matches($page.Content, 'https://us\.download\.nvidia\.com/nvapp/client/[^"'' ]+\.exe') | Select-Object -First 1).Value
        $exe = Join-Path $env:TEMP ([IO.Path]::GetFileName($url))
        Invoke-WebRequest $url -OutFile $exe -UseBasicParsing
        $sig = Get-AuthenticodeSignature $exe
        if ($sig.Status -eq 'Valid' -and $sig.SignerCertificate.Subject -match 'NVIDIA') { Start-Process $exe '-s -noreboot -noeula' -Wait; '  NVIDIA App installed' }
        else { '  NVIDIA App download failed its signature check - skipped (get it from nvidia.com/en-us/software/nvidia-app)' }
    } catch { "  NVIDIA App failed: $($_.Exception.Message) (get it from nvidia.com/en-us/software/nvidia-app)" }
}

Step 'Setting up the maintenance (scripts, login task, tray)'
# The maintenance scripts live in %USERPROFILE%\.claude (the folder name is historic; no AI is needed to run them)
$cl = "$env:USERPROFILE\.claude"
New-Item $cl -ItemType Directory -Force | Out-Null
Copy-Item "$kit\claude\*.ps1" $cl -Force
"claude=$(if ($WithClaude) { 'on' } else { 'off' })" | Set-Content "$cl\kit-options.txt" -Encoding ASCII   # ai-enabled.ps1 reads it

if ($WithClaude) {
    Step 'Installing Claude Code and Messiah (the optional Claude part)'
    try { & ([scriptblock]::Create((Invoke-RestMethod 'https://claude.ai/install.ps1'))) } catch { "  Claude Code install failed: $($_.Exception.Message)" }
    New-Item "$cl\skills" -ItemType Directory -Force | Out-Null
    Copy-Item "$kit\claude\skills\*" "$cl\skills" -Recurse -Force
    # Claude never shuts down or restarts the PC (hook); restart-only work finishes whenever the owner turns it off
    New-Item "$cl\hooks" -ItemType Directory -Force | Out-Null
    Copy-Item "$kit\claude\hooks\*" "$cl\hooks" -Force
    $sf = "$cl\settings.json"
    $s = $null; if (Test-Path $sf) { try { $s = Get-Content $sf -Raw | ConvertFrom-Json -ErrorAction Stop } catch {} }
    if (-not $s) { $s = [pscustomobject]@{} }
    $s | Add-Member hooks ([pscustomobject]@{ PreToolUse = @([pscustomobject]@{ matcher = 'Bash|PowerShell'; hooks = @([pscustomobject]@{
                        type = 'command'; command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$cl\hooks\no-power-off.ps1`""; timeout = 15 }) }) }) -Force
    [IO.File]::WriteAllText($sf, ($s | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding $false))   # no BOM
    $lnkPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Messiah.lnk"
    $sh = (New-Object -ComObject WScript.Shell).CreateShortcut($lnkPath)
    $sh.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $sh.Arguments = "-NoExit -NoLogo -ExecutionPolicy Bypass -File `"$cl\claude-admin-launch.ps1`""
    $sh.WorkingDirectory = "$env:SystemRoot\System32"
    $sh.IconLocation = "$env:USERPROFILE\.local\bin\claude.exe,0"
    $sh.Save()
    $b = [IO.File]::ReadAllBytes($lnkPath); $b[0x15] = $b[0x15] -bor 0x20; [IO.File]::WriteAllBytes($lnkPath, $b)   # "Run as administrator"
    Copy-Item $lnkPath "$env:USERPROFILE\Desktop\" -Force
}

# At every login, fully windowless (conhost --headless): background maintenance (with Claude also headless /maintain when
# due and /self-improve once a day; 4 h cap: also covers waiting for a game to close)
$act = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\conhost.exe" -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$cl\claude-bg-maint.ps1`" -Force -Unattended"
$trg = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"; $trg.Delay = 'PT2M'
$prn = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName 'Claude Background Maintenance' -Action $act -Trigger $trg -Principal $prn -Force `
    -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 4) -Priority 7) | Out-Null

# Tray icon (hidden icons area): status, the to-do list and small alerts when something needs the owner; with Claude
# it also keeps a Messiah session open hidden from every login and continues work a shutdown cut off
$trayDir = "$env:USERPROFILE\Documents\Messiah Tray"
New-Item $trayDir -ItemType Directory -Force | Out-Null
Copy-Item "$kit\claude\tray\Messiah Tray.ahk" $trayDir -Force
$ahk = "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"
if (Test-Path $ahk) {
    $act = New-ScheduledTaskAction -Execute $ahk -Argument "`"$trayDir\Messiah Tray.ahk`""
    $trg = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
    Register-ScheduledTask -TaskName 'Messiah Tray' -Action $act -Trigger $trg -Principal $prn -Settings $set -Force | Out-Null
} else { '  AutoHotkey is missing - no tray icon (run setup.ps1 again once winget works)' }

if (-not $WithClaude) {
    # Without Claude the optimization is a script too: monitors, benchmark baseline, drivers, app updates, checks,
    # cleanup, self-test, fixes and to-do items - and a readable report (Documents\PC Setup Kit report.txt)
    Step 'Optimizing this PC (drivers, updates, checks, benchmark - takes a few minutes)'
    & "$cl\optimize.ps1" -NoOpen:$NoLaunch | ForEach-Object { "  $_" }
    Step 'Done'
    Write-Host @'

  Setup finished. From now on the PC maintains itself at every login (updates, drivers, cleanup, crash checks).
  The report (Documents\PC Setup Kit report.txt) shows what was done and anything that needs you; the tray
  icon next to the clock (in the hidden icons) keeps showing the status.
  You can unplug the USB drive now. Log: C:\PCSetupKit\setup.log
'@ -ForegroundColor Green
    Stop-Transcript | Out-Null
    if (-not $NoLaunch) { Start-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue }
    return
}
Step 'Done - opening Messiah'
Write-Host @'

  Setup finished. Messiah is opening now.
  1. Log in with YOUR OWN Claude account (it opens a browser page).
  2. Claude then runs the /pc-optimize playbook: updates, drivers, hardware checks
     (BIOS, RAM speed, graphics card, monitors), crash checks and a benchmark.
  You can unplug the USB drive now. Log: C:\PCSetupKit\setup.log
'@ -ForegroundColor Green
Stop-Transcript | Out-Null
if ($NoLaunch) { return }
Start-Process powershell -Verb RunAs -WorkingDirectory "$env:SystemRoot\System32" -ArgumentList '-NoExit', '-NoLogo', '-ExecutionPolicy', 'Bypass', '-File', "`"$cl\claude-admin-launch.ps1`"", '/pc-optimize'
Start-Sleep 15
Start-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue   # sees the open session, so it only adds the icon
