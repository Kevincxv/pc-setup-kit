# One-page status of the zero-maintenance system (tray menu: "Status").
param([switch]$NoWait)
$cl = "$env:USERPROFILE\.claude"
$Host.UI.RawUI.WindowTitle = 'Messiah - status'
. "$cl\session-lib.ps1"
function Section($t) { Write-Host "`n$t" -ForegroundColor Cyan }
function L($t, $c = 'Gray') { Write-Host "  $t" -ForegroundColor $c }
$state = @{}; try { (Get-Content "$cl\maint-state.json" -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).PSObject.Properties | ForEach-Object { $state[$_.Name] = $_.Value } } catch {}
function Next($key, $days) { $d = [datetime]::MinValue; if ([datetime]::TryParse("$($state[$key])", [ref]$d)) { $n = $d.AddDays($days); if ($n -lt (Get-Date)) { 'due now' } else { $n.ToString('MMM d, yyyy') } } else { 'due now' } }

Section 'Messiah'
$ver = ((& "$env:USERPROFILE\.local\bin\claude.exe" --version 2>$null) -split ' ')[0]
L "Claude Code $ver"
$sess = @(Get-AdminSessions)
if (-not $sess) { L 'No session open (the tray opens one at every login; click the tray icon to open one now)' 'Yellow' }
foreach ($s in $sess) { L "Session $(if ($s.SessionId) { $s.SessionId.Substring(0, 8) } else { '(continued)' }): $(if ($s.Shown) { 'open on screen' } else { 'hidden in the tray' }), $(if ($s.ClaudeStarted) { "running since $($s.ClaudeStarted.ToString('g'))" } else { 'starting' })" }

Section 'Needs you'
$todo = @(Get-Content "$cl\maint-todo.txt" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
if ($todo) { $todo | ForEach-Object { L "- $_" 'Yellow' } } else { L 'Nothing' 'Green' }

Section 'Waiting for your next shutdown or restart'
$led = $null; try { $led = Get-Content "$cl\restart-ledger.json" -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch {}
if ($led.items) { $led.items | ForEach-Object { L "- $($_.Name)" }; L 'These finish by themselves the next time you turn the PC off; the check after that confirms it.' 'DarkGray' }
else { L 'Nothing' 'Green' }

Section 'Last background check'
$r = @(Get-Content "$cl\maint-report.txt" -Encoding UTF8 -ErrorAction SilentlyContinue)
if ($r) {
    L $r[0]
    $notable = @($r | Where-Object { $_ -match 'WARNING|FAILED|REBOOT|Reminder|Restart check|installed|Updated|re-applied' })
    if ($notable) { $notable | ForEach-Object { L $_ $(if ($_ -match 'WARNING|FAILED') { 'Yellow' } else { 'Gray' }) } } else { L 'All fine' 'Green' }
} else { L 'No report yet' }

Section 'Hidden maintenance (runs about 2 minutes after each login)'
$busy = "$cl\maint-claude-running"
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
if ((Test-Path $busy) -and (Get-Item $busy).LastWriteTime -gt $boot) { L 'Running now (tray menu > Watch maintenance live)' 'Yellow' }
$last = Get-ChildItem "$cl\maint-claude-log\*.md" -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
if ($last) { L "Last run: $($last.LastWriteTime.ToString('g')) ($($last.BaseName -replace '^\d+-\d+-?', ''))" }
$si = Get-Item "$cl\selfimprove-last" -ErrorAction SilentlyContinue
if ($si) { L "Self-improvement: last $($si.LastWriteTime.ToString('g')); next at the first login after $($si.LastWriteTime.AddHours(20).ToString('g'))" }

Section 'Scheduled checks'
L "App updates:       $(Next 'weekly-apps' 7)"
L "Monthly cleanup:   $(Next 'monthly-cleanup' 30)"
L "Quarterly check:   $(Next 'claude-quarterly' 90)  (BIOS, firmware, benchmark)"
L "Half-year check:   $(Next 'claude-halfyear' 180)  (dusting, temperatures, backup)"
L "Yearly re-audit:   $(Next 'claude-yearly' 365)"
if (-not $NoWait) { Write-Host "`nPress any key to close." -ForegroundColor DarkGray; [void][Console]::ReadKey($true) }
