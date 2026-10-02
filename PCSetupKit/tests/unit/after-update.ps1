# after-update.ps1 (right after a Windows Update / driver install) and update-check.ps1 (every 4 hours): stand-in
# tweak guard, monitors, NVIDIA settings, updater and self-test record what runs; nothing on the PC changes.
. "$PSScriptRoot\..\lib.ps1"
if (-not (Test-Path "$Src\after-update.ps1") -or -not (Test-Path "$Src\update-check.ps1")) { Skip 'after-update / update-check' 'not installed here'; Finish }
$D = "$Work\cl"; $K = "$Work\kit"; New-Item $D, $K -ItemType Directory -Force | Out-Null
Copy-Item "$Src\after-update.ps1", "$Src\update-check.ps1" $D
'' | Set-Content "$D\game-check.ps1"
function Stub($file, $body) { $body | Set-Content $file }
function Reports { @(Get-ChildItem "$D\maint-history\report-*.txt" -ErrorAction SilentlyContinue) }

Section 'right after an update (after-update.ps1)'
Stub "$K\tweaks.ps1" '"setting AllowTelemetry"; "power plan Ultimate Performance"'
Stub "$D\display-refresh.ps1" '"Monitor: Test set to 144Hz (was 60Hz)"'
Stub "$D\nvidia-settings.ps1" ''
$o = @(& "$D\after-update.ps1" -Dir $D -Kit $K)
Check 'what the update undid is put back and said (tweaks, monitors)' ("$o" -match 'an update had reverted 2 - re-applied: setting AllowTelemetry, power plan Ultimate Performance' -and "$o" -match 'Monitor: Test set to 144Hz') ($o -join ' / ')
$r = Reports
Check '... kept in the maintenance history (the app''s History page)' ($r.Count -eq 1 -and (Get-Content $r[0].FullName)[0] -match '^Checked .+ in \d+ s \(right after an update\)$') ''
Stub "$K\tweaks.ps1" ''; Stub "$D\display-refresh.ps1" ''
$o = @(& "$D\after-update.ps1" -Dir $D -Kit $K)
Check 'an update that changed nothing: silent, no report' (-not $o -and (Reports).Count -eq 1) ($o -join ' / ')

Section 'the 4-hourly update check (update-check.ps1)'
Stub "$D\kit-update.ps1" '"PC Setup Kit updated v1 -> v2"'
Stub "$D\self-test.ps1" '"self-test ran" | Add-Content "$PSScriptRoot\calls.txt"; "Self-test (after the kit update to v2): 40 passed, 0 failed"'
$o = @(& "$D\update-check.ps1" -Dir $D -Kit $K)
Check 'a newer release: installed, then its self-test runs right away' ("$o" -match 'updated v1 -> v2' -and "$o" -match 'Self-test \(after the kit update to v2\)' -and (Get-Content "$D\calls.txt") -eq 'self-test ran') ($o -join ' / ')
Check '... kept in the maintenance history' (@(Reports | Where-Object Name -like '*update-check*').Count -eq 1) ''
Stub "$D\kit-update.ps1" ''; Clear-Path "$D\calls.txt"
$o = @(& "$D\update-check.ps1" -Dir $D -Kit $K)
Check 'nothing new: silent, no self-test' (-not $o -and -not (Test-Path "$D\calls.txt")) ($o -join ' / ')
'"TestGame"' | Set-Content "$D\game-check.ps1"; Stub "$D\kit-update.ps1" '"PC Setup Kit updated v2 -> v3"'
$o = @(& "$D\update-check.ps1" -Dir $D -Kit $K)
Check 'a game running: waits (the tray reloads on an update)' (-not $o) ($o -join ' / ')
'' | Set-Content "$D\game-check.ps1"; Stub "$D\kit-update.ps1" ''

Section 'the guard every 4 hours too (a PC left on for days)'
Stub "$K\tweaks.ps1" '"service DiagTrack Disabled"'
Stub "$D\gaming-check.ps1" '"Gaming: TestGame.exe set to the fast graphics chip"; "Reminder: Resizable BAR is off"'
Stub "$D\nvidia-settings.ps1" '"NVIDIA: the game settings had been reset (low latency, shader cache) - put back"'
$before = @(Reports).Count; [void](& "$D\update-check.ps1" -Dir $D -Kit $K); $g = @(Reports | Where-Object Name -like '*-guard.txt')
$gt = if ($g) { Get-Content $g[0].FullName -Raw }
Check 'everything is checked and put back - settings, the NVIDIA profile, the gaming fixes - with its own report' ($g.Count -eq 1 -and $gt -match 'regular check' -and $gt -match 'Windows had changed back 1 - re-applied: service DiagTrack' -and $gt -match 'had been reset' -and $gt -match 'fast graphics chip') $gt
Check '... the gaming check''s reminders stay the login check''s (not repeated every 4 hours)' ($gt -notmatch 'Resizable BAR') $gt
Stub "$K\tweaks.ps1" ''; Stub "$D\gaming-check.ps1" '"Reminder: Resizable BAR is off"'; Stub "$D\nvidia-settings.ps1" ''; $n = @(Reports).Count
[void](& "$D\update-check.ps1" -Dir $D -Kit $K)
Check '... nothing to fix: silent, no report' (@(Reports).Count -eq $n) ''
Finish
