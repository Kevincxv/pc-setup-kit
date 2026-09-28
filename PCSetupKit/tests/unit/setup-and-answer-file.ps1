# setup.ps1 and autounattend.xml: the parts that only run on a fresh install.
# (The full fresh install runs on GitHub for every release: tests\fresh, fresh-install.yml.) Online checks are skipped offline.
. "$PSScriptRoot\..\lib.ps1"
$repoRoot = Split-Path $Kit
$setup = Get-Content "$Kit\setup.ps1" -Raw

Section 'autounattend.xml'
$xmlPath = "$repoRoot\autounattend.xml"
if (-not (Test-Path $xmlPath)) { Skip 'answer file' 'not next to the kit'; Finish }
$x = $null; try { [xml]$x = Get-Content $xmlPath -Raw } catch {}
Check 'valid XML' ([bool]$x) ''
$raw = Get-Content $xmlPath -Raw
Check 'local account allowed (BypassNRO) and Microsoft-account screens hidden' ($raw -match 'BypassNRO /t REG_DWORD /d 1' -and $raw -match '<HideOnlineAccountScreens>true</HideOnlineAccountScreens>') ''
Check 'privacy page answered with all data sharing off (ProtectYourPC 3)' ($raw -match '<ProtectYourPC>3</ProtectYourPC>') ''
Check 'no disk layout: the owner picks the disk, nothing is wiped automatically' ($raw -notmatch '<DiskConfiguration|<InstallTo|<WillWipeDisk') ''
Check 'no passwords, product keys or accounts embedded' ($raw -notmatch '<Password>|<ProductKey>|<LocalAccounts>|<AutoLogon>') ''
Check 'all components for 64-bit Windows' (-not ($x.unattend.settings.component | Where-Object { $_.processorArchitecture -ne 'amd64' })) ''
$cmd = ($x.unattend.settings | Where-Object pass -eq 'oobeSystem').component.FirstLogonCommands.SynchronousCommand.CommandLine
$inner = [regex]::Match($cmd, '-Command "(.*)"$').Groups[1].Value
Check 'first login runs the kit''s setup.ps1' ($inner -match "PCSetupKit\\setup\.ps1") $cmd
# run that command's drive search against pretend drives, with the setup call replaced by a report
$probe = $inner.Replace('& $k', '"WOULD RUN $k"').Replace("Read-Host 'Press Enter'", "'(waits for Enter)'")
foreach ($drv in 'C', 'D', 'E') { New-Item "$Work\drive$drv" -ItemType Directory -Force | Out-Null }
New-Item "$Work\driveE\PCSetupKit" -ItemType Directory -Force | Out-Null; 'x' | Set-Content "$Work\driveE\PCSetupKit\setup.ps1"
function Get-PSDrive { foreach ($drv in 'C', 'D', 'E') { [pscustomobject]@{ Name = $drv; Root = "$Work\drive$drv\" } } }
$o = & ([scriptblock]::Create($probe))
Check 'finds the kit on whichever drive the USB is (E: here)' ("$o" -eq "WOULD RUN $Work\driveE\PCSetupKit\setup.ps1") "$o"
Clear-Path "$Work\driveE\PCSetupKit"
$o = & ([scriptblock]::Create($probe)) 6>&1
Check 'USB not plugged in: tells the owner what to do instead of failing silently' ("$o" -match 'PC Setup Kit USB not found') "$o"
Remove-Item Function:\Get-PSDrive

Section 'setup.ps1: structure'
$steps = [regex]::Matches($setup, "(?m)^\s*Step '([^']+)'") | ForEach-Object { $_.Groups[1].Value }
$order = 'Waiting for internet', 'Applying Windows tweaks', 'Installing apps', 'Setting up the maintenance', 'Installing Claude Code and Messiah', 'Done'
$idx = foreach ($s in $order) { [array]::FindIndex([string[]]$steps, [Predicate[string]] { param($x) $x -like "$s*" }) }
Check 'steps run in a sensible order (internet, tweaks, apps, maintenance, optional Claude part, done)' (-not ($idx -contains -1) -and (($idx | Sort-Object) -join ',') -eq ($idx -join ',')) ($steps -join ' > ')
Check 'self-elevates when not run as administrator (keeping its options)' ($setup -match 'IsInRole\(\[Security.Principal.WindowsBuiltInRole\]::Administrator\)' -and $setup -match '-Verb RunAs' -and $setup -match "if \(\`$WithClaude\) \{ '-WithClaude' \}") ''
Check 'everything setup.ps1 copies exists in the kit' ((Test-Path "$Kit\tweaks.ps1") -and (Test-Path "$Kit\claude\hooks\no-power-off.ps1") -and (Test-Path "$Kit\claude\tray\Messiah Tray.ahk") -and @(Get-ChildItem "$Kit\claude\skills\*\SKILL.md").Count -ge 3) ''
Check 'the USB install turns Claude on with a with-claude.txt next to setup.ps1' ($setup -match 'with-claude\.txt') ''
Check 'with Claude, Messiah opens with the /pc-optimize playbook at the end' ($setup -match "claude-admin-launch\.ps1``?`"`"?, '/pc-optimize'") ''

Section 'setup.ps1: the maintenance part, with and without Claude, in a sandbox profile'
$a = $setup.IndexOf("Step 'Setting up the maintenance"); $b = $setup.IndexOf("if (-not `$WithClaude) {", [Math]::Max(0, $a))   # the part ends where the Claude-free finish (optimize, done) begins
Check 'the maintenance part is found in setup.ps1' ($a -ge 0 -and $b -gt $a) "start $a, end $b"
if ($a -lt 0 -or $b -le $a) { Finish }
$part = $setup.Substring($a, $b - $a)
Set-Content "$Work\setup-part.ps1" $part
$mocked = 'Register-ScheduledTask', 'Step', 'Invoke-RestMethod'
$ok = Test-Tripwire "$Work\setup-part.ps1" $mocked -Guarded 'New-ScheduledTaskAction', 'New-ScheduledTaskTrigger', 'New-ScheduledTaskPrincipal', 'New-ScheduledTaskSettingsSet'
if (-not $ok) { Finish }
Import-MockTargets $mocked   # load their modules BEFORE defining the mocks (see lib.ps1)
function Register-ScheduledTask { param($TaskName, $Action, $Trigger, $Principal, $Settings, [switch]$Force) $global:tasks[$TaskName] = [pscustomobject]@{ Action = $Action; Settings = $Settings; Principal = $Principal; Trigger = @($Trigger) }; [pscustomobject]@{ TaskName = $TaskName } }
function Step($m) { }
function Invoke-RestMethod { param($Uri) $global:downloads += "$Uri"; '' }   # the Claude Code installer is never really downloaded here
if (-not (Assert-Mocks $mocked)) { Finish }
function Install-Part([bool]$Claude) {
    $global:tasks = @{}; $global:downloads = @()
    $H = "$Work\user-$Claude"; New-Item "$H\Desktop", "$H\AppData\Roaming\Microsoft\Windows\Start Menu\Programs" -ItemType Directory -Force | Out-Null
    $u = $env:USERPROFILE; $ap = $env:APPDATA; $env:USERPROFILE = $H; $env:APPDATA = "$H\AppData\Roaming"
    try { $kit = $Kit; $WithClaude = $Claude; & ([scriptblock]::Create($part)) | Out-Null } finally { $env:USERPROFILE = $u; $env:APPDATA = $ap }
    $H
}

# without Claude (the default): everything but the Claude part
$H = Install-Part $false; $cl = "$H\.claude"
Check 'no Claude: all maintenance scripts installed' (@(Get-ChildItem "$cl\*.ps1").Count -eq @(Get-ChildItem "$Kit\claude\*.ps1").Count) ''
Check '... Claude recorded as off (ai-enabled.ps1 says False)' ((Get-Content "$cl\kit-options.txt") -eq 'claude=off' -and -not (& "$cl\ai-enabled.ps1")) ''
Check '... Claude Code not downloaded, no skills, no hook, no Claude settings' (-not $global:downloads -and -not (Test-Path "$cl\skills") -and -not (Test-Path "$cl\hooks") -and -not (Test-Path "$cl\settings.json")) ($global:downloads -join ', ')
Check '... no Messiah shortcut' (-not (Test-Path "$H\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Messiah.lnk") -and -not (Test-Path "$H\Desktop\Messiah.lnk")) ''
$bg = $global:tasks['Claude Background Maintenance']
Check '... login maintenance task: hidden (conhost --headless), unattended, elevated, 2 min delay, 4 h limit' ($bg -and $bg.Action.Arguments -match '^--headless powershell\.exe .*claude-bg-maint\.ps1" -Force -Unattended$' -and $bg.Principal.RunLevel -eq 'Highest' -and $bg.Settings.ExecutionTimeLimit -eq 'PT4H') ''
Check '... and once a day at 12:00, catching up after a missed start (PCs that stay on for days)' ($bg.Trigger.Count -eq 2 -and ($bg.Trigger | Where-Object { $_.DaysInterval -eq 1 -and $_.StartBoundary -match 'T12:00:00$' }) -and $bg.Settings.StartWhenAvailable) ''
if (Test-Path "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe") {
    $tr = $global:tasks['Messiah Tray']
    Check '... tray task: runs the tray script at login, elevated, no time limit' ($tr -and $tr.Action.Arguments -match [regex]::Escape("$H\Documents\Messiah Tray\Messiah Tray.ahk") -and $tr.Settings.ExecutionTimeLimit -eq 'PT0S') ''
    Check '... tray script copied to Documents' (Test-Path "$H\Documents\Messiah Tray\Messiah Tray.ahk") ''
    Check '... the tray runs as its own program "PC Setup Kit.exe" (own tray entry next to the clock)' ($tr.Action.Execute -eq "$H\Documents\Messiah Tray\PC Setup Kit.exe" -and (Test-Path $tr.Action.Execute)) "$($tr.Action.Execute)"
    Check '... Start menu "PC Setup Kit Status" opens the Status window' (Test-Path "$H\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\PC Setup Kit Status.lnk") ''
} else { Skip 'tray task' 'AutoHotkey not installed here (setup installs it first)' }

# with Claude (-WithClaude / with-claude.txt): the same plus Messiah
$H = Install-Part $true; $cl = "$H\.claude"
Check 'with Claude: recorded as on (ai-enabled.ps1 says True)' ((Get-Content "$cl\kit-options.txt") -eq 'claude=on' -and (& "$cl\ai-enabled.ps1")) ''
Check '... Claude Code installed from claude.ai' ($global:downloads -contains 'https://claude.ai/install.ps1') ($global:downloads -join ', ')
Check '... skills and the no-shutdown hook installed' ((Test-Path "$cl\skills\maintain\SKILL.md") -and (Test-Path "$cl\hooks\no-power-off.ps1")) ''
$s = Get-Content "$cl\settings.json" -Raw | ConvertFrom-Json
Check '... the hook is registered in Claude''s settings' ($s.hooks.PreToolUse[0].hooks[0].command -match [regex]::Escape("$cl\hooks\no-power-off.ps1")) ''
$lnk = "$H\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Messiah.lnk"
Check '... Start menu shortcut created, set to "Run as administrator"' ((Test-Path $lnk) -and (([IO.File]::ReadAllBytes($lnk)[0x15] -band 0x20) -ne 0)) ''
$sc = if (Test-Path $lnk) { (New-Object -ComObject WScript.Shell).CreateShortcut($lnk) }
Check '... it starts the launcher in System32 with PowerShell' ($sc -and $sc.TargetPath -match 'powershell\.exe$' -and $sc.Arguments -match [regex]::Escape("$cl\claude-admin-launch.ps1") -and $sc.WorkingDirectory -match 'System32$') "$($sc.Arguments)"
Check '... desktop shortcut too' (Test-Path "$H\Desktop\Messiah.lnk") ''
Check '... the same login maintenance task' ([bool]$global:tasks['Claude Background Maintenance']) ''
if ($global:tasks['Messiah Tray']) { Check '... the tray runs as "Messiah.exe", with a "Messiah Status" Start menu entry' ($global:tasks['Messiah Tray'].Action.Execute -eq "$H\Documents\Messiah Tray\Messiah.exe" -and (Test-Path "$H\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Messiah Status.lnk")) "$($global:tasks['Messiah Tray'].Action.Execute)" }

Section 'setup.ps1: things on the internet it depends on'
if (-not (Test-Online)) { Skip 'online checks' 'offline'; Finish }
$ids = [regex]::Match($setup, "foreach \(\`$id in ([^)]+)\)").Groups[1].Value -split ',' | ForEach-Object { $_.Trim(" '") } | Where-Object { $_ }
if (Get-Command winget -ErrorAction SilentlyContinue) {
    $missing = @($ids | Where-Object { -not ((winget show --id $_ -e --accept-source-agreements --disable-interactivity 2>$null | Out-String) -match "\[$([regex]::Escape($_))\]") })
    Check "all $($ids.Count) apps setup installs still exist on winget ($($ids -join ', '))" (-not $missing) "not found: $($missing -join ', ')"
} else { Skip 'winget app ids' 'winget not available on this machine' }
try {
    $page = Invoke-WebRequest 'https://www.nvidia.com/en-us/software/nvidia-app/' -UseBasicParsing -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' -TimeoutSec 30
    $url = ([regex]::Matches($page.Content, 'https://us\.download\.nvidia\.com/nvapp/client/[^"'' ]+\.exe') | Select-Object -First 1).Value
    Check 'NVIDIA''s page still offers the NVIDIA App installer link setup looks for' ([bool]$url) 'no link found - NVIDIA changed the page; setup.ps1 needs a new pattern'
    if ($url) { $h = Invoke-WebRequest $url -Method Head -UseBasicParsing -TimeoutSec 30; Check '... and the installer is downloadable' ($h.StatusCode -eq 200 -and [int64]$h.Headers['Content-Length'] -gt 50MB) "$($h.StatusCode) $($h.Headers['Content-Length'])" }
} catch { Skip 'NVIDIA page' "could not reach nvidia.com ($($_.Exception.Message))" }
Finish
