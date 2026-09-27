# restart-check.ps1: records what waits for the next restart and afterwards checks it all finished (simulated boots).
. "$PSScriptRoot\..\lib.ps1"
$rc = "$Src\restart-check.ps1"; $L = "$Work\ledger.json"
function Item($k, $id, $n) { [pscustomobject]@{ Kind = $k; Id = $id; Name = $n } }
$IG = "$Work\ignore.txt"; '' | Set-Content $IG
function RC($boot, $pending) { @(& $rc -Ledger $L -BootTime $boot -Pending $pending -IgnoreFile $IG) }
$b1 = [datetime]'2026-09-27 09:33:24'; $b2 = [datetime]'2026-09-28 08:00:00'; $b3 = [datetime]'2026-09-29 08:00:00'
$upd = Item 'update' 'u-1' '2026-09 Cumulative Update for Windows 11 (KB5099999)'
$drv = Item 'device' 'PCI\VEN_10DE' 'NVIDIA GeForce RTX'
$pkg = Item 'package' 'Package_for_RollupFix' 'Package_for_RollupFix'

Section 'before a restart'
$o = RC $b1 @(); Check 'nothing pending: silent, no ledger' ($o.Count -eq 0 -and -not (Test-Path $L)) ($o -join ' / ')
$o = RC $b1 @($upd, $drv); Check 'pending work recorded, "finishes the next time you turn the PC off"' ((Test-Path $L) -and ($o -match 'will finish the next time')) ($o -join ' / ')
$o = RC $b1 @($upd, $drv, $pkg); Check 'more work queued the same boot: ledger grows to 3' ((Get-Content $L -Raw | ConvertFrom-Json).items.Count -eq 3) ($o -join ' / ')
$o = RC $b1 @($upd); Check 'an item leaving the live list is kept until a restart proves it' ((Get-Content $L -Raw | ConvertFrom-Json).items.Count -eq 3) ''
Section 'after a restart'
$o = RC $b2 @(); Check 'all applied: "3 item(s) ... finished", no WARNING' (($o -match 'finished at the restart') -and -not ($o -match 'WARNING') -and ($o -match '3 item')) ($o -join ' / ')
Check 'ledger cleared after a clean restart' (-not (Test-Path $L))
$o = RC $b2 @(); Check 'next run the same boot: silent (reported once)' ($o.Count -eq 0) ($o -join ' / ')
[void](RC $b2 @($upd, $drv)); $o = RC $b3 @($upd)
Check 'an update still pending after the restart: WARNING names it' (($o -match 'WARNING: after the restart') -and ($o -match 'KB5099999')) ($o -join ' / ')
Check '... the driver that did finish is reported finished' (($o -match '1 item\(s\) Windows had queued finished') -and ($o -match 'NVIDIA')) ($o -join ' / ')
Check '... the leftover is re-recorded for the following restart' ((Get-Content $L -Raw | ConvertFrom-Json).boot -eq $b3.ToString('s')) ''
$o = RC $b3 @($upd); Check 'no repeated WARNING in the same boot' (-not ($o -match 'WARNING: after')) ($o -join ' / ')
Section 'robustness'
'{ broken' | Set-Content $L
$o = RC $b3 @(); Check 'corrupt ledger: no error, cleaned up' ((-not ($o | Where-Object { $_ -is [Management.Automation.ErrorRecord] })) -and -not (Test-Path $L)) ($o -join ' / ')
[void](RC $b1 @($upd)); $ok = RC $b2 @(); [void](RC $b1 @($upd)); $bad = RC $b2 @($upd)
Check "success lines never contain /maintain trigger words" (-not ($ok -match 'WARNING|FAILED|timed out|DOCTOR ISSUES')) ($ok -join ' / ')
Check 'a failure line does trigger /maintain' ([bool]($bad -match 'WARNING')) ($bad -join ' / ')
Clear-Path $L
Section 'queued files (Windows drops the queue entry even when a delete fails)'
$fa = "$Work\in-use-a.dll"; $fb = "$Work\in-use-b.dll"; 'x' | Set-Content $fa; 'x' | Set-Content $fb
$o = RC $b1 @((Item 'file' $fa 'delete in-use-a.dll'))
Check 'single queued item: count says 1 (no phantom entry)' ($o -match ': 1 item\(s\) will finish') ($o -join ' / ')
[void](RC $b1 @((Item 'file' $fa 'delete in-use-a.dll'), (Item 'file' $fb 'replace in-use-b.dll')))
[IO.File]::Delete($fa)
$o = RC $b2 @()
Check 'deleted file = finished, surviving file = WARNING' (($o -match 'finished at the restart \(delete in-use-a') -and ($o -match 'WARNING.*replace in-use-b')) ($o -join ' / ')
Clear-Path $L
Section 'accepted stuck items (health-ignore.txt)'
$fs = "$Work\stuckproxy_13.dll.0"; 'x' | Set-Content $fs
[void](RC $b1 @((Item 'file' $fs 'delete stuckproxy_13.dll.0'), $upd)); $o = RC $b2 @((Item 'file' $fs 'delete stuckproxy_13.dll.0'))
Check 'not ignored: surviving file is a WARNING' ($o -match 'WARNING.*stuckproxy') ($o -join ' / ')
'stuckproxy_13.dll.0' | Set-Content $IG
$o = RC $b3 @((Item 'file' $fs 'delete stuckproxy_13.dll.0'))
Check 'ignored: no WARNING, not re-recorded' ((-not ($o -match 'WARNING')) -and -not (Test-Path $L)) ($o -join ' / ')
[void](RC $b1 @((Item 'file' $fs 'delete stuckproxy_13.dll.0'), $upd)); $o = RC $b2 @()
Check 'ignored item mixed with real work: only the real work is counted' (($o -match '1 item\(s\) Windows had queued finished') -and -not ($o -match 'stuckproxy|WARNING')) ($o -join ' / ')
'' | Set-Content $IG; Clear-Path $L
Section 'the real system can be read'
$o = @(& $rc -Ledger "$Work\probe.json" -BootTime (Get-Date).AddYears(-1) 2>&1)
Check 'scanning the real restart queue gives no errors' (-not ($o | Where-Object { $_ -is [Management.Automation.ErrorRecord] })) ($o -join ' / ')
Finish
