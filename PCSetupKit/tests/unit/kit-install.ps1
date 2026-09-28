# The kit's own install/uninstall pieces: setup.ps1's settings merge and tray task, uninstall.ps1 end to end
# (sandbox profile), kit-update.ps1 and install.ps1 against the real GitHub release (skipped offline).
. "$PSScriptRoot\..\lib.ps1"
Section 'setup.ps1: the no-shutdown hook merged into Claude settings'
$lines = Get-Content "$Kit\setup.ps1"; $i = [array]::IndexOf($lines, ($lines | Where-Object { $_ -match '^\s*# Claude never shuts down' } | Select-Object -First 1))
Check 'the settings-merge part is found in setup.ps1' ($i -ge 0) ''
$snippet = ($lines[$i..($i + 8)]) -join "`n"
New-Item "$Work\kitsrc\claude\hooks" -ItemType Directory -Force | Out-Null; Copy-Item $Hook "$Work\kitsrc\claude\hooks\"
foreach ($case in 'none', 'existing', 'corrupt') {
    $cl = "$Work\home-$case"; New-Item $cl -ItemType Directory -Force | Out-Null
    if ($case -eq 'existing') { '{"theme":"dark","hooks":{"Stop":[{"hooks":[{"type":"command","command":"x.cmd"}]}]}}' | Set-Content "$cl\settings.json" }
    if ($case -eq 'corrupt') { '{"theme":' | Set-Content "$cl\settings.json" }
    # own scope: the snippet's $kit would otherwise overwrite the test's $Kit (PowerShell names ignore case)
    & { param($cl, $kit) . ([scriptblock]::Create($snippet)) } $cl "$Work\kitsrc"
    $j = Get-Content "$cl\settings.json" -Raw | ConvertFrom-Json; $b = [IO.File]::ReadAllBytes("$cl\settings.json")
    Check "settings $case`: hook added, valid JSON, no BOM" (($j.hooks.PreToolUse[0].hooks[0].command -match 'no-power-off') -and $b[0] -ne 0xEF) (Get-Content "$cl\settings.json" -Raw)
    if ($case -eq 'existing') { Check '... existing settings kept' ($j.theme -eq 'dark') '' }
}
Section 'tray task (tray-app.ps1) and login maintenance task (setup.ps1)'
if (Test-IsAdmin) {
    $s = Get-Content "$Kit\setup.ps1" -Raw
    $blk = [regex]::Match((Get-Content "$Kit\claude\tray-app.ps1" -Raw), '(?s)\$set = New-ScheduledTaskSettingsSet[^\r\n]*').Value   # the tray task's settings (tray-app.ps1)
    $act = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c exit'; $trg = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $prn = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    . ([scriptblock]::Create($blk))
    Register-ScheduledTask -TaskName 'PCSetupKit Tray TEST' -Action $act -Trigger $trg -Principal $prn -Settings $set -Force | Out-Null
    $t = Get-ScheduledTask 'PCSetupKit Tray TEST'
    Check 'tray task: elevated, no time limit, restarts on failure, runs on battery' ($t.Principal.RunLevel -eq 'Highest' -and $t.Settings.ExecutionTimeLimit -eq 'PT0S' -and $t.Settings.RestartCount -eq 3 -and -not $t.Settings.DisallowStartIfOnBatteries) ''
    Unregister-ScheduledTask 'PCSetupKit Tray TEST' -Confirm:$false
    Check 'login maintenance task allows 4 h (waiting for games)' ($s -match 'ExecutionTimeLimit \(New-TimeSpan -Hours 4\)') ''
} else { Skip 'tray task' 'needs administrator' }

Section 'uninstall.ps1 end to end (sandbox profile, real processes and tasks untouched)'
$H = "$Work\uhome"; $cl = "$H\.claude"; $A = "$H\AppData\Roaming"; $kf = "$Work\ukit"
New-Item "$cl\hooks", "$cl\skills\maintain", "$cl\skills\my-own-skill", "$cl\projects\p", "$A\Microsoft\Windows\Start Menu\Programs", "$H\Desktop", "$H\Documents\Messiah Tray", $kf -ItemType Directory -Force | Out-Null
foreach ($f in 'claude-admin-launch.ps1', 'health-check.ps1', 'maint-state.json', 'games.txt', 'hooks\no-power-off.ps1', 'skills\maintain\SKILL.md', 'skills\my-own-skill\SKILL.md', 'projects\p\conv.jsonl', 'CLAUDE.md') { 'x' | Set-Content "$cl\$f" }
foreach ($f in "$A\Microsoft\Windows\Start Menu\Programs\Messiah.lnk", "$H\Desktop\Messiah.lnk", "$H\Documents\Messiah Tray\Messiah Tray.ahk", "$kf\setup.log") { 'x' | Set-Content $f }
@'
{ "theme": "dark", "hooks": { "PreToolUse": [ { "matcher": "Bash|PowerShell", "hooks": [ { "type": "command", "command": "powershell.exe -File \"C:\\x\\hooks\\no-power-off.ps1\"" } ] },
                              { "matcher": "Edit", "hooks": [ { "type": "command", "command": "my-own-hook.cmd" } ] } ] } }
'@ | Set-Content "$cl\settings.json"
$unText = Get-Content "$Kit\uninstall.ps1" -Raw
$a = $unText.IndexOf('    Write-Host "`n=== Stopping Messiah"'); $b = $unText.IndexOf('    Write-Host "`n=== Shortcuts and tray icon"')
$safe = ($unText.Substring(0, $a) + $unText.Substring($b)).Replace("'C:\PCSetupKit'", "'$kf'")
Check 'sandbox copy cannot touch real processes, tasks or C:\PCSetupKit' (-not ($safe -match 'Stop-Process|Unregister-ScheduledTask') -and $safe -notmatch [regex]::Escape("Stash 'C:\PCSetupKit'")) ''
Set-Content "$Work\uninstall-sandbox.ps1" $safe
$r = Invoke-As $H "$Work\uninstall-sandbox.ps1" @('-Yes') @{ APPDATA = $A }
$s = Get-Content "$cl\settings.json" -Raw | ConvertFrom-Json
Check 'our hook removed, the owner''s own hook and settings kept, settings backed up' (-not ($s.hooks.PreToolUse.hooks.command -match 'no-power-off') -and ($s.hooks.PreToolUse.hooks.command -match 'my-own-hook') -and $s.theme -eq 'dark' -and (Test-Path "$cl\settings.json.before-uninstall")) $r.Out
Check 'kit files, shortcuts, tray and kit folder gone' (-not (Test-Path "$cl\claude-admin-launch.ps1") -and -not (Test-Path "$cl\skills\maintain") -and -not (Test-Path "$A\Microsoft\Windows\Start Menu\Programs\Messiah.lnk") -and -not (Test-Path "$H\Desktop\Messiah.lnk") -and -not (Test-Path "$H\Documents\Messiah Tray") -and -not (Test-Path $kf)) $r.Out
Check 'conversations, own skills and CLAUDE.md kept' ((Test-Path "$cl\projects\p\conv.jsonl") -and (Test-Path "$cl\skills\my-own-skill") -and (Test-Path "$cl\CLAUDE.md")) ''
$st = Get-ChildItem $cl -Directory -Filter 'pc-setup-kit-removed-*'
Check 'nothing deleted: everything is in the removed-files folder' (@(Get-ChildItem $st.FullName -Recurse -File).Count -ge 9) ''
$o = & "$Kit\uninstall.ps1" -WhatIf 2>&1 | Out-String
Check 'the real uninstaller dry run (-WhatIf) changes nothing and has no errors' ($o -match 'Nothing was changed' -and $o -notmatch 'Exception|FAILED') $o

Section 'GitHub: install.ps1 and kit-update.ps1 against the real release'
if (-not (Test-Online)) { Skip 'GitHub tests' 'offline'; Finish }
if (-not (Test-Path "$Kit\kit-source.txt")) { Skip 'GitHub tests' 'this kit has no update source (kit-source.txt)'; Finish }
$repoRoot = Split-Path $Kit
# GitHub's release API sometimes doesn't answer for a moment (the kit then quietly waits for the next login - correct).
# A step that got no answer is tried again; if GitHub stays unreachable, the rest is skipped (with the reason), never
# failed. If GitHub answers and the step still fails, that is a real failure.
$repo = ((Get-Content "$Kit\kit-source.txt") -match '^repo=' | Select-Object -First 1) -replace '^repo=\s*'
function Test-ReleaseApi { try { [void](Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'pc-setup-kit-tests' } -TimeoutSec 20); $true } catch { $false } }
function GitHubStep([scriptblock]$Action, [scriptblock]$Ok) {
    for ($i = 1; $i -le 3; $i++) { $o = & $Action; if ((& $Ok $o) -or (Test-ReleaseApi)) { return $o }; Start-Sleep 10 }
    Skip 'the rest of the GitHub tests' "GitHub's release API did not answer (3 tries)"; Finish
}
if (Test-Path "$repoRoot\install.ps1") {
    [void](GitHubStep { if (Test-Path "$Work\dl") { Clear-Path "$Work\dl" }; & "$repoRoot\install.ps1" -DownloadOnly "$Work\dl" | Out-Null } { Test-Path "$Work\dl\x\*\PCSetupKit\kit-version.txt" })
    $k = Get-ChildItem "$Work\dl\x" -Directory | ForEach-Object { "$($_.FullName)\PCSetupKit" }
    Check 'installer downloads and unpacks the latest release' ((Test-Path "$k\setup.ps1") -and (Test-Path "$k\kit-version.txt")) ''
    $bad = @(Get-ChildItem $k -Recurse -Filter *.ps1 | Where-Object { $e = $null; [void][Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e); $e })
    Check 'every script in the published release parses' (-not $bad) ($bad.Name -join ', ')
} else { Skip 'installer' 'install.ps1 not next to the kit' }
$kd = "$Work\kd"; $cd = "$Work\cd"; $td = "$Work\td"; New-Item $kd, $cd, $td -ItemType Directory -Force | Out-Null
Get-Content "$Kit\kit-source.txt" | Set-Content "$kd\kit-source.txt"; 'v2000.01.01' | Set-Content "$kd\kit-version.txt"; 'old' | Set-Content "$td\Messiah Tray.ahk"
New-Item "$kd\tests\unit" -ItemType Directory -Force | Out-Null; 'old' | Set-Content "$kd\tests\unit\removed-long-ago.ps1"
'claude=on' | Set-Content "$cd\kit-options.txt"   # this install has the optional Claude part (skills, hook)
$o = GitHubStep { & "$Src\kit-update.ps1" -KitDir $kd -ClaudeDir $cd -TrayDir $td -Force } { param($x) "$x" -match 'updated' }
Check 'an old install updates itself to the latest release' ("$o" -match 'PC Setup Kit updated v2000.01.01 -> v') "$o"
Check '... scripts, skills, hook, tray and uninstaller installed' ((@(Get-ChildItem "$cd\*.ps1").Count -ge 15) -and (Test-Path "$cd\skills\maintain\SKILL.md") -and (Test-Path "$cd\hooks\no-power-off.ps1") -and ((Get-Content "$td\Messiah Tray.ahk" -Raw) -match 'Persistent') -and (Test-Path "$kd\uninstall.ps1")) ''
Check '... the kit copy''s test suite refreshed (for the weekly self-test), removed tests gone' ((Test-Path "$kd\tests\run-tests.ps1") -and (Test-Path "$kd\tests\unit\static.ps1") -and -not (Test-Path "$kd\tests\unit\removed-long-ago.ps1")) ''
Check '... the tests are stamped with the release they belong to (self-test.ps1 checks it)' ((Get-Content "$kd\tests\tests-version.txt" -ErrorAction SilentlyContinue) -eq (Get-Content "$kd\kit-version.txt")) ''
'stale' | Set-Content "$kd\tests\tests-version.txt"; $o = GitHubStep { & "$Src\kit-update.ps1" -KitDir $kd -ClaudeDir $cd -TrayDir $td -Force -Reinstall } { param($x) "$x" -match 'updated' }
Check '-Reinstall installs the current release again (a stale test suite gets replaced)' ((Get-Content "$kd\tests\tests-version.txt") -eq (Get-Content "$kd\kit-version.txt") -and "$o" -match 'updated') "$o"
$nd = "$Work\nd"; $nc = "$Work\nc"; New-Item $nd, $nc -ItemType Directory -Force | Out-Null
Get-Content "$Kit\kit-source.txt" | Set-Content "$nd\kit-source.txt"; 'v2000.01.01' | Set-Content "$nd\kit-version.txt"; 'claude=off' | Set-Content "$nc\kit-options.txt"
$o = GitHubStep { & "$Src\kit-update.ps1" -KitDir $nd -ClaudeDir $nc -TrayDir "$Work\ntd" -Force } { param($x) "$x" -match 'updated' }
Check 'an install without Claude: updated, but no Claude skills or hook added' ("$o" -match 'updated' -and (@(Get-ChildItem "$nc\*.ps1").Count -ge 15) -and -not (Test-Path "$nc\skills") -and -not (Test-Path "$nc\hooks")) "$o"
'v2099.01.01' | Set-Content "$nd\kit-version.txt"
Check 'never back to an older release (a newer one is installed)' (-not (& "$Src\kit-update.ps1" -KitDir $nd -ClaudeDir $nc -TrayDir "$Work\ntd" -Force) -and (Get-Content "$nd\kit-version.txt") -eq 'v2099.01.01') ''
Check 'already current: silent' (-not (& "$Src\kit-update.ps1" -KitDir $kd -ClaudeDir $cd -TrayDir $td -Force)) ''
[IO.File]::Delete("$kd\kit-source.txt")
Check 'no kit-source.txt (not installed from the kit): silent' (-not (& "$Src\kit-update.ps1" -KitDir $kd -ClaudeDir $cd -TrayDir $td -Force)) ''
Finish
