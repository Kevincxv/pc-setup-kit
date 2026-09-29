# setup-progress.ps1: the "Setting up this PC" window - steps, progress, time left, finished / stopped. Built with -Test
# from a made-up progress file (nothing is shown on screen).
. "$PSScriptRoot\..\lib.ps1"
$sp = "$Kit\setup-progress.ps1"
if (-not (Test-Path $sp)) { Skip 'setup-progress' 'not in this kit'; Finish }
$pf = "$Work\setup-progress.txt"
function Steps([int]$minsAgo, [string[]]$names) { $t = (Get-Date).AddMinutes(-$minsAgo); $names | ForEach-Object { "$($t.ToString('o'))|$_"; $t = $t.AddMinutes(1) } | Set-Content $pf }
function Invoke-Progress([string[]]$more) { @(& powershell -NoProfile -STA -ExecutionPolicy Bypass -File $sp -ProgressFile $pf -Test @more 2>&1 | ForEach-Object { "$_" }) }
$first = 'Waiting for internet', 'Applying Windows tweaks', 'Power plan: Ultimate Performance', 'Removing OneDrive', 'Getting winget ready', 'Installing apps'

Steps 9 $first; $o = Invoke-Progress
$bar = if ("$o" -match 'BAR: (\d+)') { [int]$Matches[1] } else { -1 }
Check 'halfway (installing apps): the bar in the middle, time so far and left' ($bar -gt 20 -and $bar -lt 80 -and "$o" -match 'TIME: \d+ min so far \| about \d+ min left') ($o -join ' / ')
Check '... done steps ticked, the running one bold, the rest waiting' (($o -match '^STEP: 59198 Getting winget ready Normal$') -and ($o -match '^STEP: 59240 Installing apps SemiBold$') -and ($o -match '^STEP: 59679 Setting up the maintenance Normal$')) ($o -join ' / ')
Check '... without Claude: no Claude step listed' (-not ($o -match 'Installing Claude Code')) ($o -join ' / ')
$o = Invoke-Progress '-WithClaude'
Check '... with Claude: its step listed' ([bool]($o -match 'STEP: \d+ Installing Claude Code')) ($o -join ' / ')
Steps 25 ($first + 'Setting up the maintenance (scripts, login task, tray)', 'Optimizing this PC (drivers...)', 'Done'); $o = Invoke-Progress
Check 'finished: full bar, "Finished", what happens now' ("$o" -match 'BAR: 100' -and "$o" -match '\| Finished' -and "$o" -match 'SUB: All done') ($o -join ' / ')
Steps 9 $first; $o = Invoke-Progress '-SetupPid', '999999'
Check 'setup stopped before finishing: says so and where the log is' ("$o" -match 'SUB: Setup stopped before it finished.+setup\.log') ($o -join ' / ')
Finish
