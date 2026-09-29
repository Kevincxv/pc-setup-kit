# ai-toggle.ps1: the AI assistant switch - on installs Claude Code (only when missing), the skills and the hook, and
# records claude=on without touching the other choices; a failed install leaves it off; off keeps Claude Code.
# A sandbox .claude folder; the installer is a stand-in; -Test: no processes stopped or started.
. "$PSScriptRoot\..\lib.ps1"
$at = "$Src\ai-toggle.ps1"
if (-not (Test-Path $at)) { Skip 'ai-toggle' 'not installed here'; Finish }
$C = "$Work\home\.claude"; $K = "$Work\kit"; $exe = "$Work\home\.local\bin\claude.exe"
New-Item $C, "$K\claude\skills\maintain", "$K\claude\hooks" -ItemType Directory -Force | Out-Null
'skill' | Set-Content "$K\claude\skills\maintain\SKILL.md"; 'hook' | Set-Content "$K\claude\hooks\no-power-off.ps1"
Copy-Item "$Src\ai-enabled.ps1" $C
'tweak.onedrive=off', 'openatlogin=on' | Set-Content "$C\kit-options.txt"
$global:installs = 0
$inst = { $global:installs++; New-Item $exe -ItemType File -Force | Out-Null }
function AT([string[]]$a, $install = $inst) { $p = @{ ClaudeDir = $C; KitDir = $K; Claude = $exe; Install = $install; Test = $true; Tray = "$Work\tray" }; foreach ($x in $a) { $p[$x] = $true }; @(& $at @p) }

$o = AT 'Setup' { $global:installs++ }
Check 'the installer ran but no Claude Code came: stays off, said' ($global:installs -eq 1 -and (& "$C\ai-enabled.ps1") -eq $false -and "$o" -match "didn't install") "$o"
$global:installs = 0; $o = AT 'On', 'NoOpen'
Check 'on: Claude Code installed, skills and the no-shutdown hook in place, recorded as on' ($global:installs -eq 1 -and (Test-Path "$C\skills\maintain\SKILL.md") -and (Test-Path "$C\hooks\no-power-off.ps1") -and (& "$C\ai-enabled.ps1") -eq $true) "$o"
$j = Get-Content "$C\settings.json" -Raw | ConvertFrom-Json
Check '... the hook in Claude''s settings' ($j.hooks.PreToolUse[0].hooks[0].command -match 'no-power-off\.ps1') ''
Check '... the owner''s other choices kept' ((Get-Content "$C\kit-options.txt") -contains 'tweak.onedrive=off' -and (Get-Content "$C\kit-options.txt") -contains 'openatlogin=on') (Get-Content "$C\kit-options.txt" -Raw)
Check '... the tray restarted (it shows the sessions)' ("$o" -match 'Tray: restarted') "$o"
$global:installs = 0; $o = AT 'On', 'NoOpen'
Check 'on again: Claude Code not downloaded a second time' ($global:installs -eq 0) "$o"
$o = AT 'Off'
Check 'off: recorded, Claude Code and its settings kept, the tray restarted' ((& "$C\ai-enabled.ps1") -eq $false -and (Test-Path $exe) -and (Test-Path "$C\settings.json") -and "$o" -match 'Tray: restarted') "$o"
Check 'neither -On nor -Off: nothing done' ("$(& $at -ClaudeDir $C -Test)" -match 'Use -On or -Off') ''
Finish
