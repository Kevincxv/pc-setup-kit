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
Check 'resets that began right after a driver update: that driver named, with how to go back' ("$o" -match 'it began after driver 4\.0 was installed on .+Roll Back Driver') ($o -join ' / ')
Finish
