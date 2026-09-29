# FRESH INSTALL: checks a PC right after `setup.ps1 -NoLaunch` ran on it for real - GitHub runs this on a clean
# Windows machine for every release (.github/workflows/fresh-install.yml). Never run it on a PC that is in use:
# it only reads, but the setup before it changes the whole PC.
. "$PSScriptRoot\..\lib.ps1"
$kit = 'C:\PCSetupKit'; $cl = "$env:USERPROFILE\.claude"; $src = Split-Path (Split-Path $PSScriptRoot)   # the kit setup ran from
$withClaude = $env:FRESH_WITH_CLAUDE -eq '1'   # which way setup ran (setup.ps1 -WithClaude or not)
Write-Host "  (setup ran $(if ($withClaude) { 'WITH the optional Claude part' } else { 'without AI (the default)' }))"

Section 'the kit and its log'
Check 'kit copied to C:\PCSetupKit (scripts, maintenance, tests)' ((Test-Path "$kit\setup.ps1") -and (Test-Path "$kit\tweaks.ps1") -and (Test-Path "$kit\uninstall.ps1") -and (Test-Path "$kit\claude\claude-bg-maint.ps1") -and (Test-Path "$kit\tests\run-tests.ps1")) ''
$log = Get-Content "$kit\setup.log" -Raw -ErrorAction SilentlyContinue
Check 'setup log written, it got to the end' ($log -match '=== Done') ''
Check 'no step reported a failure' ($log -notmatch 'Claude Code install failed|NVIDIA App failed') (([regex]::Matches("$log", '.*failed.*') | ForEach-Object Value) -join ' / ')

Section 'Windows tweaks'
Check 'tweaks applied and their originals recorded (for the uninstaller)' (Test-Path "$kit\tweaks-backup.json") ''
$again = @(& "$kit\tweaks.ps1")
Check 'running the tweak guard again changes nothing (it all stuck)' ($again.Count -eq 0) ($again -join ' / ')
if ((Get-CimInstance Win32_Battery) -or $env:PCKIT_TEST_BATTERY -eq '1') { Check 'a laptop: the Balanced power plan kept (Ultimate would drain the battery)' ((powercfg /getactivescheme) -match '381b4222-f694-41f0-9685-ff5bb260df2e') "$(powercfg /getactivescheme)" }
else { Check 'Ultimate Performance power plan active' ((powercfg /getactivescheme) -match '99999999-9999-9999-9999-999999999999|Ultimate Performance') "$(powercfg /getactivescheme)" }
Check 'hibernation off' (-not (Test-Path 'C:\hiberfil.sys')) ''

Section 'apps'
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
Check 'Git' ([bool](Get-Command git -ErrorAction SilentlyContinue)) ''
Check 'Google Chrome' ((Test-Path "$env:ProgramFiles\Google\Chrome\Application\chrome.exe") -or (Test-Path "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe") -or (Test-Path "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")) ''
Check 'Steam' ((Test-Path "${env:ProgramFiles(x86)}\Steam\steam.exe") -or (Test-Path "$env:ProgramFiles\Steam\steam.exe")) ''
Check 'Discord' (Test-Path "$env:LOCALAPPDATA\Discord\Update.exe") ''
Check 'WinDbg (crash-dump diagnosis)' ([bool](Get-AppxPackage Microsoft.WinDbg -ErrorAction SilentlyContinue) -or [bool](Get-Command windbgx -ErrorAction SilentlyContinue)) ''
Check 'AutoHotkey v2 (the tray icon)' (Test-Path "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe") ''

Section 'maintenance (no AI needed)'
$missing = @(Get-ChildItem "$src\claude\*.ps1" | Where-Object { -not (Test-Path "$cl\$($_.Name)") } | ForEach-Object Name)
Check 'every maintenance script installed in .claude' (-not $missing) ($missing -join ', ')
Check "the optional Claude part recorded as $(if ($withClaude) { 'on' } else { 'off' })" ((Get-Content "$cl\kit-options.txt" -ErrorAction SilentlyContinue) -eq "claude=$(if ($withClaude) { 'on' } else { 'off' })" -and (& "$cl\ai-enabled.ps1") -eq $withClaude) "$(Get-Content "$cl\kit-options.txt" -ErrorAction SilentlyContinue)"
$claude = "$env:USERPROFILE\.local\bin\claude.exe"
if (-not $withClaude) {
    Check 'no Claude Code, no skills, no hook, no session shortcut (the app is Messiah either way)' (-not (Test-Path $claude) -and -not (Test-Path "$cl\skills") -and -not (Test-Path "$cl\hooks") -and -not (Test-Path "$cl\Messiah Session.lnk")) ''
    $rep = Get-Content "$env:USERPROFILE\Documents\PC Setup Kit report.txt" -Raw -ErrorAction SilentlyContinue
    Check 'the PC was optimized by script: report in Documents (this PC, what was done incl. the maintenance, what needs you)' ($rep -match 'THIS PC' -and $rep -match 'WHAT WAS DONE' -and $rep -match 'Maintenance: running everything now' -and $rep -match 'WHAT NEEDS YOU') "$rep"
    Check '... the maintenance ran and wrote its report' ((Get-Content "$cl\maint-report.txt" -TotalCount 1 -ErrorAction SilentlyContinue) -match '^Checked ') ''
    Write-Host "`n--- optimization report ---`n$rep"
}

if ($withClaude) {
    Section 'the optional Claude part (Messiah)'
    Check 'Claude Code installed and runs' ((Test-Path $claude) -and ((& $claude --version 2>$null) -match 'Claude Code')) "$(& $claude --version 2>&1)"
    Check 'skills and the no-shutdown hook installed' ((Test-Path "$cl\skills\maintain\SKILL.md") -and (Test-Path "$cl\skills\pc-optimize\SKILL.md") -and (Test-Path "$cl\skills\self-improve\SKILL.md") -and (Test-Path "$cl\hooks\no-power-off.ps1")) ''
    $s = Get-Content "$cl\settings.json" -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
    Check 'the hook is active in Claude settings (Bash and PowerShell calls)' (($s.hooks.PreToolUse | Where-Object { $_.matcher -eq 'Bash|PowerShell' }).hooks.command -match 'no-power-off\.ps1') ''
    $lnk = "$cl\Messiah Session.lnk"
    $sc = if (Test-Path $lnk) { (New-Object -ComObject WScript.Shell).CreateShortcut($lnk) }
    Check 'Messiah session shortcut (the app''s "New session"), starting the launcher' ($sc -and $sc.Arguments -match 'claude-admin-launch\.ps1' -and $sc.TargetPath -match 'powershell\.exe') "$($sc.Arguments)"
    Check '... set to run as administrator' ((Test-Path $lnk) -and (([IO.File]::ReadAllBytes($lnk)[0x15] -band 0x20) -ne 0)) ''

}

Section 'scheduled tasks'
$bm = Get-ScheduledTask 'Claude Background Maintenance' -ErrorAction SilentlyContinue
Check 'background maintenance at every login and once a day: 2 min delay, windowless, elevated, below-normal priority, 4 h limit' ($bm -and $bm.Triggers.Count -eq 2 -and $bm.Settings.StartWhenAvailable -and $bm.Triggers[0].Delay -eq 'PT2M' -and $bm.Actions[0].Execute -match 'conhost\.exe' -and $bm.Actions[0].Arguments -match '--headless .*claude-bg-maint\.ps1.* -Unattended' -and $bm.Principal.RunLevel -eq 'Highest' -and $bm.Settings.Priority -eq 7 -and $bm.Settings.ExecutionTimeLimit -eq 'PT4H') ''
$tt = Get-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue
Check 'tray at every login: elevated, no time limit, restarts on failure' ($tt -and $tt.Actions[0].Arguments -match 'Messiah Tray\\Messiah Tray\.ahk' -and $tt.Principal.RunLevel -eq 'Highest' -and $tt.Settings.ExecutionTimeLimit -eq 'PT0S' -and $tt.Settings.RestartCount -eq 3) ''
Check 'tray script in Documents\Messiah Tray' (Test-Path "$env:USERPROFILE\Documents\Messiah Tray\Messiah Tray.ahk") ''
$app = 'Messiah'   # one app, with or without the AI assistant
Check "the tray runs as its own program ($app.exe: its own tray entry next to the clock)" ($tt -and $tt.Actions[0].Execute -eq "$env:USERPROFILE\Documents\Messiah Tray\$app.exe" -and (Test-Path $tt.Actions[0].Execute)) "$($tt.Actions[0].Execute)"
$lnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$app.lnk"
$sc = if (Test-Path $lnk) { (New-Object -ComObject WScript.Shell).CreateShortcut($lnk) }
Check "Start menu and desktop '$app' open the app window, with the app's icon" ($sc -and $sc.Arguments -match 'dashboard\.ps1"$' -and $sc.IconLocation -match 'app\.ico,0$' -and (Test-Path "$env:USERPROFILE\Documents\Messiah Tray\app.ico") -and (Test-Path "$env:USERPROFILE\Desktop\$app.lnk")) "$($sc.Arguments) | $($sc.IconLocation)"
Check '... no separate Status entry' (-not (Test-Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$app Status.lnk")) ''
$d = & powershell -NoProfile -ExecutionPolicy Bypass -File "$cl\dashboard.ps1" -Test 2>&1 | Out-String
Check '... the app window builds on this PC' ($d -match "(?m)^WINDOW: $app\s*$" -and $d -match 'CARD: Needs you') $d
Check 'no leftovers of the old name' (-not (Get-ScheduledTask 'Claude Admin Tray' -ErrorAction SilentlyContinue) -and -not (Test-Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Claude (Admin).lnk")) ''
Finish
