# PC Setup Kit - first-logon setup. Started automatically by autounattend.xml (FirstLogonCommands) from the USB.
# Can also be run by hand on an existing Windows 11 PC: right-click > Run with PowerShell (it asks for admin).
# Steps: copy kit to C:\PCSetupKit > tweaks (with the power plan and removing OneDrive) > install apps > maintenance (scripts, login
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

$Host.UI.RawUI.WindowTitle = 'Messiah - setting up this PC (do not close)'
$src = Split-Path -Parent $PSCommandPath
$kit = 'C:\PCSetupKit'
if ($src -ne $kit) { New-Item $kit -ItemType Directory -Force | Out-Null; Copy-Item "$src\*" $kit -Recurse -Force }
if ((Test-Path "$kit\kit-version.txt") -and (Test-Path "$kit\tests")) { Copy-Item "$kit\kit-version.txt" "$kit\tests\tests-version.txt" -Force }   # tests match this release (self-test.ps1)
Start-Transcript "$kit\setup.log" -Append | Out-Null
# each step also goes to setup-progress.txt, which the progress window (setup-progress.ps1) follows - not under tests
# or on GitHub's machines (nobody to see it)
$progress = "$kit\setup-progress.txt"; [IO.File]::WriteAllText($progress, '')
function Step($msg) { Write-Host "`n=== $msg" -ForegroundColor Cyan; Add-Content $progress "$((Get-Date).ToString('o'))|$msg" -ErrorAction SilentlyContinue }
if (-not $env:PCKIT_IN_TESTS -and -not $env:GITHUB_ACTIONS -and (Test-Path "$kit\setup-progress.ps1")) {
    Start-Process powershell -ArgumentList (@('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$kit\setup-progress.ps1`"", '-SetupPid', $PID) + @(if ($WithClaude) { '-WithClaude' }))
}

Step 'Waiting for internet'
for ($i = 0; $i -lt 60 -and -not (Test-NetConnection 1.1.1.1 -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue); $i++) { Start-Sleep 5 }

Step 'Applying Windows tweaks (with the power plan and removing OneDrive)'
& "$kit\tweaks.ps1" | ForEach-Object { "  $_" }

# (the power plan - laptops kept on Balanced - and removing OneDrive are part of tweaks.ps1 above: its guard puts
# them back after every update)

Step 'Getting winget ready'
# Windows brings winget with the Store's App Installer, which can take minutes to appear after the first login. Where
# it never comes (no Store: Windows Sandbox, LTSC, a removed or broken Store) it is installed straight from Microsoft:
# the App Installer package and the libraries it needs, both from the same winget release so they always match (winget
# 1.29 added a Windows App Runtime requirement - found by the Windows Sandbox test on 9/28). Add-AppxPackage accepts
# only Microsoft-signed packages.
function Install-Winget {
    $d = Join-Path $env:TEMP 'winget-setup'; New-Item $d -ItemType Directory -Force | Out-Null
    $ProgressPreference = 'SilentlyContinue'
    $rel = 'https://github.com/microsoft/winget-cli/releases/latest/download'
    try {
        Invoke-WebRequest "$rel/DesktopAppInstaller_Dependencies.zip" -OutFile "$d\deps.zip" -UseBasicParsing
        Expand-Archive "$d\deps.zip" "$d\deps" -Force
        foreach ($a in Get-ChildItem "$d\deps\x64\*.appx") { try { Add-AppxPackage $a.FullName -ErrorAction Stop } catch {} }   # already there: fine
        Invoke-WebRequest "$rel/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -OutFile "$d\winget.msixbundle" -UseBasicParsing
        Add-AppxPackage "$d\winget.msixbundle" -ErrorAction Stop
        '  winget installed'
    } catch { "  winget install failed: $($_.Exception.Message)" }
}
for ($i = 0; $i -lt 40 -and -not (Get-Command winget -ErrorAction SilentlyContinue); $i++) {
    if ($i -eq 0) { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue }
    if ($i -eq 12) { '  winget did not appear by itself - installing it from Microsoft'; Install-Winget }   # after 3 minutes
    Start-Sleep 15
}
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') + ";$env:LOCALAPPDATA\Microsoft\WindowsApps"
$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
if ($hasWinget) { winget source update --accept-source-agreements | Out-Null }
else { '  winget is not available - the apps are skipped; everything else is set up (run setup.ps1 again once winget works)' }

Step 'Installing apps'
# One app, retried when winget's package list isn't there yet ("No packages were found" for everything - a new PC's
# first minutes; seen on GitHub's test machines on 9/28): the list is fetched again and the install tried again.
function Install-App([string]$Id) {
    for ($try = 1; $try -le 3; $try++) {
        # --source winget: with the msstore source too, a fresh winget can find the id twice and installs nothing
        # ("Multiple packages found" - the Windows Sandbox test, 9/28)
        $out = @(winget install --id $Id -e --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | ForEach-Object { "$_" } | Where-Object { $_.Trim() -and $_ -notmatch '^\s*[-\\|/]\s*$|[\u2588\u2592]' })
        $code = $LASTEXITCODE
        # (winget's words are translated on non-English Windows: its exit code says "not found", and whether the app is
        # really there afterwards is asked with winget list)
        if ($code -ne -1978335212 -and -not ($out -match 'No package(s were)? found')) {   # 0x8A150014: no package found
            $null = winget list --id $Id -e --source winget --accept-source-agreements --disable-interactivity 2>&1
            if ($LASTEXITCODE -eq 0) { return "  $Id installed" }
            return "  $Id`: NOT installed - winget said: $(($out | Select-Object -Last 4) -join ' / ') (exit $code)"
        }
        if ($try -lt 3) {
            winget source reset --force 2>&1 | Out-Null
            winget source update --accept-source-agreements 2>&1 | Out-Null
            Start-Sleep 20
        }
    }
    "  $Id`: winget couldn't find it (its package list didn't load) - run setup.ps1 again later"
}
# WinDbg: automatic crash-dump diagnosis; AutoHotkey (v2): the tray icon
foreach ($id in 'Git.Git', 'Valve.Steam', 'Discord.Discord', 'Google.Chrome', 'Microsoft.WinDbg', 'AutoHotkey.AutoHotkey') {
    if (-not $hasWinget) { break }
    Write-Host "  $id"
    Install-App $id
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
# the AI assistant starts off (ai-enabled.ps1 reads it; -WithClaude switches it on below); running setup again keeps
# the owner's choices in kit-options.txt (the switches in the app)
$opts = "$cl\kit-options.txt"
$have = @(Get-Content $opts -ErrorAction SilentlyContinue)
if (-not ($have -match '^\s*claude\s*=')) { Add-Content $opts 'claude=off' -Encoding ASCII }
# the app's welcome page opens once the setup is done (the tray opens it; nobody to see it on GitHub's machines)
if (-not $NoLaunch -and -not ($have -match '^\s*welcome\s*=')) { Add-Content $opts 'welcome=pending' -Encoding ASCII }
# Windows reinstalled on this same PC: its settings come back from the weekly backup (the look, game settings, the
# kit's memory; only a backup made on this PC - settings-backup.ps1). Once: running setup again keeps later changes.
if (-not (Test-Path "$cl\settings-restored.txt") -and -not $env:PCKIT_IN_TESTS) {   # (never under tests: the registry is the real one)
    & "$cl\settings-backup.ps1" -Restore | ForEach-Object { "  $_" }
    (Get-Date).ToString('o') | Set-Content "$cl\settings-restored.txt"
}

if ($WithClaude) {
    Step 'Installing Claude Code and Messiah (the AI assistant)'
    # the same as the app's switch (Settings > AI assistant): Claude Code, the skills, the no-power-off hook, "claude=on";
    # the Start menu / desktop "Messiah" (the app) and the session shortcut come from tray-app.ps1 below
    & "$cl\ai-toggle.ps1" -Setup -KitDir $kit -ClaudeDir $cl | ForEach-Object { "  $_" }   # (-ClaudeDir: the same spelling of the path as here, never an 8.3 short one)
}

# At every login, fully windowless (conhost --headless): background maintenance (with Claude also headless /maintain when
# due and /self-improve once a day; 4 h cap: also covers waiting for a game to close)
$act = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\conhost.exe" -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$cl\claude-bg-maint.ps1`" -Force -Unattended"
$trg = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"; $trg.Delay = 'PT2M'
$prn = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$daily = New-ScheduledTaskTrigger -Daily -At 12:00   # also once a day: a PC that stays on for days still gets updates and checks
$daily.StartBoundary = (Get-Date -Hour 12 -Minute 0 -Second 0).ToString('s')   # local 12:00 (the default is UTC: an hour off after a clock change)
Register-ScheduledTask -TaskName 'Claude Background Maintenance' -Action $act -Trigger @($trg, $daily) -Principal $prn -Force `
    -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 4) -Priority 7) | Out-Null

# Tray icon (hidden tray, the ^ next to the clock): status, the to-do list and small alerts when something needs the owner; with Claude
# it also keeps a Messiah session open hidden from every login and continues work a shutdown cut off
$trayDir = "$env:USERPROFILE\Documents\Messiah Tray"
New-Item $trayDir -ItemType Directory -Force | Out-Null
Copy-Item "$kit\claude\tray\Messiah Tray.ahk" $trayDir -Force
# the app: its icon, Start menu and desktop entries (the app window; with Claude also the session shortcut), and the
# tray under its own program name (its own entry in the hidden tray) with its login task
& "$cl\tray-app.ps1" -TrayDir $trayDir -NoRestart -Desktop | Out-Null
if (-not (Test-Path "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe")) { '  AutoHotkey is missing - no tray icon (run setup.ps1 again once winget works)' }

if (-not $WithClaude) {
    # Without Claude the optimization is a script too: monitors, benchmark baseline, drivers, app updates, checks,
    # cleanup, self-test, fixes and to-do items - and a readable report (Documents\PC Setup Kit report.txt)
    Step 'Optimizing this PC (monitors, benchmark - the full maintenance then continues in the background)'
    & "$cl\optimize.ps1" -NoOpen -Background | ForEach-Object { "  $_" }   # (the app's welcome page shows what was done; the report stays in Documents)
    Step 'Done'
    Write-Host @'

  Setup finished - the PC is ready to use. Its first full maintenance (updates, drivers, checks) runs in the
  background now; from then on the PC maintains itself at every login (updates, drivers, cleanup, crash checks).
  The report (Documents\PC Setup Kit report.txt) shows what was done and anything that needs you; the tray
  icon in the hidden tray and the "Messiah" app (Start menu and desktop) show the status.
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
