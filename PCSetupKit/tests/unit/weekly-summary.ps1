# weekly-summary.ps1: once a week, one short note (tray-news.txt) of what the maintenance did; nothing in a quiet week.
# Made-up reports and game samples.
. "$PSScriptRoot\..\lib.ps1"
$ws = "$Src\weekly-summary.ps1"
if (-not (Test-Path $ws)) { Skip 'weekly-summary' 'not installed here'; Finish }
$D = "$Work\cl"; New-Item "$D\maint-history" -ItemType Directory -Force | Out-Null
$now = Get-Date
function Report([string[]]$l, [int]$daysAgo = 1) { $f = "$D\maint-history\report-$($now.AddDays(-$daysAgo).ToString('yyyyMMdd-HHmmss')).txt"; $l | Set-Content $f; (Get-Item $f).LastWriteTime = $now.AddDays(-$daysAgo) }
function WS { @(& $ws -Dir $D -Now $now) }
function News { Get-Content "$D\tray-news.txt" -Raw -ErrorAction SilentlyContinue }

$o = WS
Check 'a quiet week: nothing said' (-not $o -and -not (News)) ($o -join ' / ')
Clear-Path "$D\weekly-summary.last"
Report @('Checked', 'Updated app: Git.Git', 'Updated app: Discord.Discord', 'NVIDIA: 620.01 installed', 'Tweaks: Windows had reverted 2 - re-applied: x', 'PC Setup Kit updated v1 -> v2')
Report @('Updated app: Old.App') 12
ConvertTo-Json -InputObject @(@{ date = $now.AddDays(-2).ToString('o'); game = 'TestGame' }) | Set-Content "$D\perf-history.json"
$o = WS
Check 'a busy week: counted from the last 7 days only (older reports left out)' ("$o" -match '^This week: the kit updated itself, 2 app updates, 1 driver installed, settings an update undid put back 1 time\. No crashes\. 1 game played, running as usual\.$') ($o -join ' / ')
Check '... as the tray''s note' ((News) -match '^This week:') (News)
$o = WS
Check '... once a week (not at every run)' (-not $o) ($o -join ' / ')
Clear-Path "$D\weekly-summary.last"; Report @('WARNING: blue screen 0x109 at 9/28/2026') 0; Report @('Reminder: TestGame runs slower since the graphics driver update to 2.0') 2
$o = WS
Check 'crashes and a slower game are pointed out' ("$o" -match '1 crash - see the app' -and "$o" -match 'one runs slower since an update') ($o -join ' / ')
Finish
