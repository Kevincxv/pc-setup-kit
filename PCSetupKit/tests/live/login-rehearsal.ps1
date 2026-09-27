# LIVE: the real sign-in chain without restarting (rehearse-login.ps1): tray task -> hidden launcher -> real Claude.
# Scenarios: cut off mid-task, resume armed by an agent, nothing to resume. Uses a little Claude usage.
. "$PSScriptRoot\..\lib.ps1"
if (-not (Get-ScheduledTask 'Claude Admin Tray' -ErrorAction SilentlyContinue)) { Skip 'login rehearsal' 'Claude (Admin) tray is not installed on this PC'; Finish }
$proj = "$env:USERPROFILE\.claude\projects\C--WINDOWS-system32"
$mine = Get-ChildItem "$proj\*.jsonl" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1   # the session running this, if any
$strayBefore = if ($mine) { @(Select-String -Path $mine.FullName -Pattern '"content":"The PC was turned off while').Count } else { 0 }
$o = @(& "$Src\rehearse-login.ps1" *>&1 | ForEach-Object { "$_" })   # it reports with Write-Host (stream 6)
$o | Where-Object { "$_" -match 'PASS|FAIL|^\[' } | ForEach-Object { Write-Host "  $_" }
$m = [regex]::Match(($o -join "`n"), 'Rehearsal: (\d+) passed, (\d+) failed')
Check 'rehearsal ran to the end' $m.Success (($o | Select-Object -Last 5) -join ' / ')
if ($m.Success) { Check "all $($m.Groups[1].Value) rehearsal checks passed" ([int]$m.Groups[2].Value -eq 0) "$($m.Groups[2].Value) failed" }
if ($mine) { Check 'the session running the tests was not resumed by mistake' (@(Select-String -Path $mine.FullName -Pattern '"content":"The PC was turned off while').Count -eq $strayBefore) '' }
Finish
