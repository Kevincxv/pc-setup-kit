# defender-check.ps1: Defender's real-time protection back on by itself when nothing else protects the PC.
# Made-up states (-Test); the switch goes to a recorder - Defender on this PC is never touched.
. "$PSScriptRoot\..\lib.ps1"
$dc = "$Src\defender-check.ps1"
if (-not (Test-Path $dc)) { Skip 'defender-check' 'not installed here'; Finish }
$global:acts = @()
$rec = { param($w) $global:acts += $w }
function DC([hashtable]$t) { $global:acts = @(); @(& $dc -Test $t -Do $rec) }
$o = DC @{ Rtp = $true }
Check 'on: nothing done, nothing said' (-not $o -and -not $acts) ''
$o = DC @{ Rtp = $null }
Check 'no Defender here (Windows Server, Sandbox): nothing' (-not $o -and -not $acts) ''
$o = DC @{ Rtp = $false; OtherAv = ''; Policy = $false; After = $true }
Check 'off with no other antivirus: switched back on, said' (($acts -join ',') -eq 'defender on' -and "$o" -match '^Security: .*turned it back on$') ($o -join ' / ')
$o = DC @{ Rtp = $false; OtherAv = 'Norton 360'; Policy = $false }
Check 'another antivirus active: left alone, said (not a warning)' (-not $acts -and "$o" -match '^Security: Norton 360 protects this PC') ($o -join ' / ')
$o = DC @{ Rtp = $false; OtherAv = ''; Policy = $true }
Check 'a policy keeps it off: not touched, the WARNING (the to-do item) says so' (-not $acts -and "$o" -match '^WARNING: Defender real-time protection is OFF \(a policy keeps it off') ($o -join ' / ')
$o = DC @{ Rtp = $false; OtherAv = ''; Policy = $false; After = $false }
Check 'switched on but it didn''t stay on (Tamper Protection): the WARNING' (($acts -join ',') -eq 'defender on' -and "$o" -match '^WARNING: Defender real-time protection is OFF \(it did not stay on') ($o -join ' / ')
Finish
