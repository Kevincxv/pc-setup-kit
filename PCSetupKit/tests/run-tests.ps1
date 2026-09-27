# Runs the PC Setup Kit test suite and prints a summary. Exit code 0 = everything passed.
#   -Suite unit : safe tests - sandboxes only, nothing on the PC changes (also what GitHub runs on every push)
#   -Suite live : tests against this PC's real setup (tray, hidden sessions, real Claude - uses a little usage)
#   -Suite all  : both.   -Only <name>: just the matching test files.
#   -Src  : the maintenance scripts to test (default: this PC's installed .claude if present, else the kit's copy)
#   -Kit  : the kit folder (default: the one this runner is in)
# Results also go to tests\last-run.txt.
param([ValidateSet('unit', 'live', 'all')][string]$Suite = 'unit', [string]$Only, [string]$Src, [string]$Kit, [string]$TrayFile)
$here = $PSScriptRoot
if (-not $Kit) { $Kit = Split-Path $here }
if (-not $Src) { $Src = if (Test-Path "$env:USERPROFILE\.claude\claude-admin-launch.ps1") { "$env:USERPROFILE\.claude" } else { "$Kit\claude" } }
if (-not $TrayFile) { $TrayFile = if (Test-Path "$env:USERPROFILE\Documents\Claude Admin Tray\Claude Admin Tray.ahk") { "$env:USERPROFILE\Documents\Claude Admin Tray\Claude Admin Tray.ahk" } else { "$Kit\claude\tray\Claude Admin Tray.ahk" } }
$env:PCKIT_SRC = $Src; $env:PCKIT_KIT = $Kit; $env:PCKIT_TRAY = $TrayFile
$env:PCKIT_IN_TESTS = '1'   # scripts under test know not to start the real test suite themselves (no suite-in-suite loops)

$files = @()
if ($Suite -in 'unit', 'all') { $files += Get-ChildItem "$here\unit\*.ps1" | Sort-Object Name }
if ($Suite -in 'live', 'all') { $files += Get-ChildItem "$here\live\*.ps1" | Sort-Object Name }
if ($Only) { $files = @($files | Where-Object BaseName -match $Only) }
Write-Host "PC Setup Kit tests ($Suite) - scripts: $Src" -ForegroundColor Cyan
$t0 = Get-Date; $rows = @()
foreach ($f in $files) {
    Write-Host "`n[$($f.BaseName)]" -ForegroundColor White
    $s = Get-Date
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $f.FullName 2>&1
    $out | Where-Object { "$_" -notmatch '^RESULT ' } | ForEach-Object { Write-Host "$_" }
    $r = $out | Where-Object { "$_" -match '^RESULT ' } | Select-Object -Last 1
    $row = if ("$r" -match 'pass=(\d+) fail=(\d+) skip=(\d+)') { [pscustomobject]@{ Test = $f.BaseName; Pass = [int]$Matches[1]; Fail = [int]$Matches[2]; Skip = [int]$Matches[3]; Sec = [int]((Get-Date) - $s).TotalSeconds } }
    else { [pscustomobject]@{ Test = $f.BaseName; Pass = 0; Fail = 1; Skip = 0; Sec = [int]((Get-Date) - $s).TotalSeconds } }   # crashed before finishing
    if (-not $r) { Write-Host '  FAIL  the test itself crashed (no RESULT line)' -ForegroundColor Red }
    $rows += $row
}
$p = ($rows | Measure-Object Pass -Sum).Sum; $fl = ($rows | Measure-Object Fail -Sum).Sum; $sk = ($rows | Measure-Object Skip -Sum).Sum
$summary = @("PC Setup Kit tests ($Suite) $((Get-Date).ToString('g')) in $([int]((Get-Date) - $t0).TotalSeconds)s: $p passed, $fl failed, $sk skipped") +
    ($rows | ForEach-Object { '  {0,-22} {1,4} passed {2,3} failed {3,3} skipped {4,5}s' -f $_.Test, $_.Pass, $_.Fail, $_.Skip, $_.Sec })
Write-Host ''; $summary | ForEach-Object { Write-Host $_ -ForegroundColor $(if ($fl) { 'Red' } else { 'Green' }) }
try { $summary | Set-Content "$here\last-run.txt" -Encoding utf8 } catch {}
exit [int]($fl -gt 0)
