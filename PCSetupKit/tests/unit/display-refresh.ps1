# display-refresh.ps1: every monitor at its native resolution (once) and its best refresh rate, never under a game.
# Made-up monitors with -WhatIf: nothing on the real screens changes.
. "$PSScriptRoot\..\lib.ps1"
$dr = "$Src\display-refresh.ps1"
if (-not (Test-Path $dr)) { Skip 'display-refresh' 'not installed here'; Finish }
$st = "$Work\display-state.json"; $ig = "$Work\health-ignore.txt"
function Mon($name, $w, $h, $hz, $max, $nw, $nh, $nmax) { [ordered]@{ Device = '\\.\DISPLAYX'; Name = $name; Key = "MONITOR\$name\x"; Width = $w; Height = $h; Hz = $hz; MaxHz = $max; NativeWidth = $nw; NativeHeight = $nh; NativeMaxHz = $nmax } }
function DR([object[]]$mons, [string]$game = '') { @(& $dr -Displays (ConvertTo-Json -InputObject @($mons)) -WhatIf -State $st -IgnoreFile $ig -TestGame $game) }

Section 'the real monitors (read only)'
Add-Type -AssemblyName System.Windows.Forms
$screens = [Windows.Forms.Screen]::AllScreens.Count
$found = @(& $dr -ShowMonitors)
if ($screens -lt 1) { Skip 'finds every monitor' 'no screen on this machine' }
else { Check "finds every monitor Windows reports ($screens), with its current mode" ($found.Count -eq $screens -and -not ($found | Where-Object { -not $_.Width -or -not $_.Hz })) "found $($found.Count): $(($found | ForEach-Object { "$($_.Name) $($_.Width)x$($_.Height) $($_.Hz)Hz" }) -join ', ')" }

Section 'what it sets'
$o = DR @(Mon 'LowRes' 1920 1080 60 144 2560 1440 165)
Check 'below native: native resolution at its best refresh rate' ("$o" -eq 'Monitor: would set LowRes to 2560x1440 at 165Hz (was 1920x1080 at 60Hz)') "$o"
$o = DR @(Mon 'SlowHz' 2560 1440 60 144 2560 1440 144)
Check 'native already, refresh low: only the refresh rate' ("$o" -eq 'Monitor: would set SlowHz to 144Hz (was 60Hz)') "$o"
$o = DR @(Mon 'Fine' 2560 1440 144 144 2560 1440 144)
Check 'already at its best: nothing' (-not $o) "$o"
$o = DR @(Mon 'NoEdid' 1920 1080 60 75 $null $null 0)
Check 'no EDID native mode: the resolution is left alone, the refresh still fixed' ("$o" -eq 'Monitor: would set NoEdid to 75Hz (was 60Hz)') "$o"
$o = DR @(Mon 'Dsr' 3840 2160 60 60 2560 1440 144)
Check 'above native (DSR/VSR chosen on purpose): never lowered' (-not $o) "$o"
$o = DR @(Mon 'NotOffered' 1920 1080 60 60 2560 1440 0)
Check 'a native mode Windows does not offer: not tried' (-not $o) "$o"

Section 'respecting the owner'
'{"MONITOR\\LowRes\\x":"2560x1440 2026-01-01"}' | Set-Content $st
$o = DR @(Mon 'LowRes' 1920 1080 60 144 2560 1440 165)
Check 'resolution set once already (the owner lowered it later): kept, only the refresh fixed' ("$o" -eq 'Monitor: would set LowRes to 144Hz (was 60Hz)') "$o"
'LowRes' | Set-Content $ig
$o = DR @(Mon 'LowRes' 1920 1080 60 144 2560 1440 165)
Check 'a monitor in health-ignore.txt: left alone' (-not $o) "$o"
Clear-Path $ig
$o = DR @(Mon 'SlowHz' 2560 1440 60 144 2560 1440 144) 'TestGame'
Check 'a game running: nothing changes (a mode switch blanks the screen)' (-not $o) "$o"
Finish
