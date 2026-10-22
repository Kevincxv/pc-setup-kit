# fan-watch.ps1: the graphics card's fans stuck high at idle put back to automatic; the CPU fan or the pump stopping.
# Made-up readings (-Test); the fan change goes to a recorder (-Do) - nothing real is read or changed.
. "$PSScriptRoot\..\lib.ps1"
$fw = "$Src\fan-watch.ps1"
if (-not (Test-Path $fw)) { Skip 'fan-watch' 'not installed here'; Finish }
$now = Get-Date; $sf = "$Work\fan-state.json"; $opt = "$Work\opts.txt"; '' | Set-Content $opt
function Fan($hw, $name, $rpm, $duty) { @{ Hw = $hw; Name = $name; Rpm = $rpm; Duty = $duty } }
$board = @((Fan 'board' 'CPU Fan' 1200 40), (Fan 'board' 'Pump Fan' 850 40), (Fan 'board' 'System Fan #1' 0 0))
function Watch-Fans([object[]]$gpu, [int]$use = 2, [double]$temp = 30, [object[]]$b = $board, [datetime]$at = $now) {
    $global:acts = @(); @(& $fw -Test @{ Readings = @($b) + @($gpu); GpuUse = $use; GpuTemp = $temp } -Do { $global:acts += $args[0] } -State $sf -Options $opt -Now $at)
}
$stuck = @((Fan 'gpu' 'GPU Fan 1' 2530 70), (Fan 'gpu' 'GPU Fan 2' 2530 70)); $auto = @((Fan 'gpu' 'GPU Fan 1' 0 0), (Fan 'gpu' 'GPU Fan 2' 0 0))

Section 'the graphics card''s fans'
$o = Watch-Fans $stuck
Check 'stuck at 70% while idle and cool: put back to automatic, said with what it was' ($acts -contains 'gpu fans automatic' -and "$o" -match '^Fans: the graphics card''s fans were stuck at 70% \(2530 RPM\) while it was idle at 30 C - put back to automatic') "$o"
$o = Watch-Fans $auto
Check 'in automatic (stopped while cool): nothing' (-not $acts -and -not $o) "$o"
$o = Watch-Fans $stuck -use 95 -temp 70
Check 'high while gaming: the card''s own business, nothing done' (-not $acts -and -not $o) "$o"
$o = Watch-Fans $stuck -at $now.AddDays(1)
Check 'stuck again: put back again, quietly' ($acts -contains 'gpu fans automatic' -and -not $o) "$o"
$o = Watch-Fans $stuck -at $now.AddDays(2)
Check '... a third time in a week: names the likely cause (another fan program), once' ($acts -contains 'gpu fans automatic' -and "$o" -match '^Reminder: something keeps setting the graphics card''s fans to 70% at idle') "$o"
$o = Watch-Fans $stuck -at $now.AddDays(3)
Check '... and not again' (-not $o) "$o"

Section 'the CPU fan and the pump'
Clear-Path $sf
[void](Watch-Fans $auto)
$o = Watch-Fans $auto -b @((Fan 'board' 'CPU Fan' 1200 40), (Fan 'board' 'Pump Fan' 0 40), (Fan 'board' 'System Fan #1' 0 0))
Check 'the pump stops while driven: WARNING (the processor has no cooling)' ("$o" -match '^WARNING: the water-cooling pump \(Pump Fan\) has stopped \(0 RPM\)') "$o"
$o = Watch-Fans $auto -b @((Fan 'board' 'CPU Fan' 1200 40), (Fan 'board' 'Pump Fan' 0 40), (Fan 'board' 'System Fan #1' 0 0))
Check '... said once while it stays stopped' (-not $o) "$o"
[void](Watch-Fans $auto)
$o = Watch-Fans $auto -b @((Fan 'board' 'CPU Fan' 0 40), (Fan 'board' 'Pump Fan' 850 40), (Fan 'board' 'System Fan #1' 0 0))
Check 'the CPU fan stops: WARNING' ("$o" -match '^WARNING: the CPU fan \(CPU Fan\) has stopped') "$o"
Clear-Path $sf
$o = Watch-Fans $auto -b @((Fan 'board' 'CPU Fan' 1200 40), (Fan 'board' 'CPU_OPT' 0 40))
Check 'a header with nothing on it (0 RPM from the start): never a warning' (-not ($o -match 'WARNING')) "$o"
'fancheck=off' | Set-Content $opt
$o = Watch-Fans $stuck
Check 'switched off in Settings: nothing read or done' (-not $acts -and -not $o) "$o"
Finish
