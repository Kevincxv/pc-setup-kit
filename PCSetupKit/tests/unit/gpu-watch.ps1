# gpu-watch.ps1: graphics driver resets (TDR) and clearing the old shader caches once after a driver update.
# Made-up events, driver versions and cache folders (under $Work); nothing real is read or deleted.
. "$PSScriptRoot\..\lib.ps1"
$gw = "$Src\gpu-watch.ps1"
if (-not (Test-Path $gw)) { Skip 'gpu-watch' 'not installed here'; Finish }
$now = Get-Date
$st = "$Work\gpu-state.json"; $root = "$Work\root"
function Ev([datetime]$t) { [pscustomobject]@{ TimeCreated = $t } }
function GW([string]$drv = '1.0', [object[]]$ev = @(), [string]$game = '', [datetime]$at = $now, [datetime]$since = $now.AddDays(-1)) {
    @(& $gw -Since $since -State $st -Now $at -Root $root -TestDriver $drv -TestEvents $ev -TestGame $game)
}
function New-Caches { foreach ($d in 'Local\NVIDIA\DXCache', 'Local\D3DSCache\x', 'LocalLow\Intel\ShaderCache') { New-Item "$root\$d" -ItemType Directory -Force | Out-Null; [IO.File]::WriteAllBytes("$root\$d\cache.bin", (New-Object byte[] (2MB))) } }
New-Item "$root\Local\Keep" -ItemType Directory -Force | Out-Null; 'x' | Set-Content "$root\Local\Keep\other.txt"

Section 'shader caches after a driver update'
New-Caches
$o = GW '1.0' -at $now.AddDays(-70)
Check 'the first check only records the driver (caches kept)' (-not $o -and (Test-Path "$root\Local\NVIDIA\DXCache\cache.bin")) ($o -join ' / ')
$o = GW '1.0' -at $now.AddDays(-69)
Check 'the same driver: nothing' (-not $o -and (Test-Path "$root\Local\NVIDIA\DXCache\cache.bin")) ($o -join ' / ')
$o = GW '2.0' -game 'TestGame' -at $now.AddDays(-50)
Check 'a new driver while a game runs: caches kept for now' (-not $o -and (Test-Path "$root\Local\NVIDIA\DXCache\cache.bin")) ($o -join ' / ')
$o = GW '2.0' -at $now.AddDays(-49)
Check '... cleared at the next check without a game, saying how much' ("$o" -match 'updated to 2\.0 - cleared its old shader caches \(6 MB\)' -and -not (Test-Path "$root\Local\NVIDIA\DXCache\cache.bin") -and -not (Test-Path "$root\LocalLow\Intel\ShaderCache\cache.bin")) ($o -join ' / ')
Check '... other folders untouched' (Test-Path "$root\Local\Keep\other.txt") ''
New-Caches; $o = GW '2.0' -at $now.AddDays(-48)
Check '... and only once' (-not $o -and (Test-Path "$root\Local\D3DSCache\x\cache.bin")) ($o -join ' / ')

Section 'driver resets'
$m0 = $now.AddHours(-2).Date.AddHours($now.AddHours(-2).Hour).AddMinutes($now.AddHours(-2).Minute)   # the start of a minute: both events inside it
$o = GW '2.0' @((Ev $m0.AddSeconds(5)), (Ev $m0.AddSeconds(25)))
Check 'one reset (logged twice in the same minute): a Reminder counting 1' ("$o" -match '^Reminder: the graphics driver stopped responding and restarted 1 time\(s\) since the last check \(1 in 7 days\)') ($o -join ' / ')
Check '... names the usual causes (this driver came weeks before)' ("$o" -match 'common causes' -and "$o" -notmatch 'Roll Back') ($o -join ' / ')
$o = GW '2.0' @((Ev $now.AddHours(-1)), (Ev $now.AddMinutes(-30)))
Check '3 in 7 days: WARNING' ("$o" -match '^WARNING: .+restarted 2 time\(s\) since the last check \(3 in 7 days\)') ($o -join ' / ')
$o = GW '2.0'
Check 'no new reset: nothing' (-not $o) ($o -join ' / ')
Clear-Path $st
[void](GW '3.0' -at $now.AddDays(-30)); [void](GW '4.0' -at $now.AddDays(-3))
$o = GW '4.0' @(Ev $now.AddHours(-3))
Check 'resets that began right after a driver update: that driver named, with how to go back' ("$o" -match 'it began after driver 4\.0 was installed on .+Messiah goes back to the previous driver by itself \(or one click now') ($o -join ' / ')

Section 'a new driver that crashes: back to the previous one by itself'
function GWR([string]$drv, [object[]]$ev = @(), [object[]]$bs = @(), [datetime]$at, [string]$res = 'Graphics driver: back on 1.0 (from 2026-01-01); 9.0 won''t be installed again') {
    $global:rolled = 0; $r = $res; @(& $gw -Since $at.AddDays(-1) -State $st -Now $at -Root $root -TestDriver $drv -TestEvents $ev -TestGame '' -TestBsods $bs -Rollback ([scriptblock]::Create("`$global:rolled++; '$($r.Replace("'", "''"))'")) -Options "$Work\opts.txt")
}
Clear-Path $st; '' | Set-Content "$Work\opts.txt"
$d0 = $now.AddDays(-5)
[void](GWR '8.0' -at $d0.AddDays(-20)); [void](GWR '9.0' -at $d0)   # 9.0 came 5 days ago, 8.0 before it had nothing
$o = GWR '9.0' -ev @((Ev $d0.AddDays(1)), (Ev $d0.AddDays(2)), (Ev $d0.AddDays(3))) -at $d0.AddDays(3).AddMinutes(5)
Check '3 driver resets in the new driver''s first days, none before: went back by itself, said why' ($global:rolled -eq 1 -and "$o" -match 'Graphics driver: 9\.0 caused 3 driver reset\(s\) since it was installed .+ went back to the previous driver by itself') ($o -join ' / ')
$o = GWR '9.0' -ev @((Ev $d0.AddDays(3).AddHours(2))) -at $d0.AddDays(3).AddHours(3)
Check '... once per driver version (never a loop)' ($global:rolled -eq 0) ($o -join ' / ')
Clear-Path $st
[void](GWR '8.0' -at $d0.AddDays(-20)); [void](GWR '9.0' -at $d0)
$o = GWR '9.0' -bs @((Ev $d0.AddDays(1)), (Ev $d0.AddDays(2))) -at $d0.AddDays(2).AddMinutes(5)
Check '2 graphics blue screens (VIDEO_TDR_FAILURE and the like) after it: went back too' ($global:rolled -eq 1 -and "$o" -match '2 blue screen\(s\)') ($o -join ' / ')
Clear-Path $st
[void](GWR '8.0' -ev @((Ev $d0.AddDays(-3))) -at $d0.AddDays(-2)); [void](GWR '9.0' -at $d0)
$o = GWR '9.0' -ev @((Ev $d0.AddDays(1)), (Ev $d0.AddDays(2)), (Ev $d0.AddDays(3))) -at $d0.AddDays(3).AddMinutes(5)
Check '... not when the old driver crashed too (then the driver isn''t the cause: overclock, cables, heat)' ($global:rolled -eq 0) ($o -join ' / ')
Clear-Path $st
[void](GWR '8.0' -at $d0.AddDays(-20)); [void](GWR '9.0' -at $d0)
$o = GWR '9.0' -ev @((Ev $d0.AddDays(1))) -at $d0.AddDays(1).AddMinutes(5)
Check '... not for one reset (it waits for a pattern)' ($global:rolled -eq 0) ($o -join ' / ')
Clear-Path $st
[void](GWR '8.0' -at $now.AddDays(-40)); [void](GWR '9.0' -at $now.AddDays(-20))
$o = GWR '9.0' -ev @((Ev $now.AddDays(-1)), (Ev $now.AddHours(-20)), (Ev $now.AddHours(-10))) -at $now
Check '... not for a driver in use for weeks without trouble (past its first 14 days)' ($global:rolled -eq 0) ($o -join ' / ')
Clear-Path $st
[void](GWR '8.0' -at $d0.AddDays(-20)); [void](GWR '9.0' -at $d0)
$o = GWR '9.0' -ev @((Ev $d0.AddDays(1)), (Ev $d0.AddDays(2)), (Ev $d0.AddDays(3))) -at $d0.AddDays(3).AddMinutes(5) -res 'Close TestGame first - the screen goes black for a few seconds while the driver switches'
$o2 = GWR '9.0' -at $d0.AddDays(3).AddHours(1)
Check 'a game running: tried again at the next check' ($global:rolled -eq 1 -and "$o2" -match 'went back to the previous driver by itself') (($o + $o2) -join ' / ')
Clear-Path $st
[void](GWR '8.0' -at $d0.AddDays(-20)); [void](GWR '9.0' -at $d0)
$o = GWR '9.0' -ev @((Ev $d0.AddDays(1)), (Ev $d0.AddDays(2)), (Ev $d0.AddDays(3))) -at $d0.AddDays(3).AddMinutes(5) -res "The version before 9.0 isn't on this PC any more"
Check 'not possible (the old version is gone): a WARNING to-do saying why' ([bool]($o -match '^WARNING: graphics driver 9\.0 caused .+ wasn''t possible: The version before')) ($o -join ' / ')
Clear-Path $st; 'autorollback=off' | Set-Content "$Work\opts.txt"
[void](GWR '8.0' -at $d0.AddDays(-20)); [void](GWR '9.0' -at $d0)
$o = GWR '9.0' -ev @((Ev $d0.AddDays(1)), (Ev $d0.AddDays(2)), (Ev $d0.AddDays(3))) -at $d0.AddDays(3).AddMinutes(5)
Check 'switched off (autorollback=off): only the warning, no rollback' ($global:rolled -eq 0) ($o -join ' / ')
Finish