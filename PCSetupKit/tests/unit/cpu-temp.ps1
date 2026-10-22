# cpu-temp.ps1: the processor's temperature - the PawnIO driver and LibreHardwareMonitor's library installed once (never
# under a game), removed again when switched off. Stand-ins for the downloads, the install and the reading; nothing real
# is downloaded, installed or read.
. "$PSScriptRoot\..\lib.ps1"
$ct = "$Src\cpu-temp.ps1"
if (-not (Test-Path $ct)) { Skip 'cpu-temp' 'not installed here'; Finish }
$tools = "$Work\lhm"
function CT([hashtable]$t, [object]$result = $true) {
    $global:acts = @(); $r = $result
    @(& $ct -Ensure -Test $t -Do ([scriptblock]::Create("`$global:acts += `$args[0]; `$global:ctResult")) -Tools $tools -State "$Work\cpu-temp.txt" -Options "$Work\opts.txt")
}

Section 'installed once'
$global:ctResult = $true
$o = CT @{ Installed = $false; Option = $null; Game = ''; Reading = 48.5 }
Check 'not there yet: the library and the driver installed, said with the temperature now' (($acts -join ',') -eq 'library,install PawnIO' -and "$o" -match '^CPU temperature: now measured \(48\.5 C\)') "$($acts -join ',') / $o"
$o = CT @{ Installed = $true; Option = $null; Game = ''; Reading = 48.5 }
Check 'already there: nothing done, nothing said' (-not $acts -and -not $o) "$($acts -join ',') / $o"
$o = CT @{ Installed = $false; Option = $null; Game = 'TestGame'; Reading = 48.5 }
Check 'a game running: not now (a driver installs) - at the next check' (-not $acts -and -not $o) "$($acts -join ',') / $o"
$global:ctResult = 'bad'
$o = CT @{ Installed = $false; Option = $null; Game = ''; Reading = 48.5 }
Check 'a download that does not match the checked version: not used, said' ("$o" -match 'did not match the checked version') "$o"
$global:ctResult = $false
$o = CT @{ Installed = $false; Option = $null; Game = ''; Reading = 48.5 }
Check 'offline: nothing said (next check)' (-not $o) "$o"
$global:ctResult = $true
$o = CT @{ Installed = $false; Option = $null; Game = ''; Reading = $null }
Check 'installed but no reading yet: said, checked again' ("$o" -match 'installed, but the processor gave no reading yet') "$o"

Section 'switched off'
New-Item $tools -ItemType Directory -Force | Out-Null
$o = CT @{ Installed = $true; Option = 'off'; Ours = $true }
Check 'off in Settings: the driver Messiah put on is uninstalled, the library removed, said' (($acts -join ',') -eq 'uninstall PawnIO,remove the library' -and "$o" -match 'switched off - its driver \(PawnIO\) and library were removed') "$($acts -join ',') / $o"
New-Item $tools -ItemType Directory -Force | Out-Null
$o = CT @{ Installed = $true; Option = 'off'; Ours = $false }
Check '... a PawnIO that was there before (another program''s) stays' (($acts -join ',') -eq 'remove the library') "$($acts -join ',')"
Remove-Item $tools -Recurse -Force
$o = CT @{ Installed = $false; Option = 'off'; Ours = $false }
Check '... and nothing to remove: nothing said' (-not $acts -and -not $o) "$($acts -join ',') / $o"

Section 'the reader'
$r = & $ct -Reader -Test @{ Reading = 61.2 }
Check 'a reader that gives the temperature now (game-perf and trends call it)' ($r -is [scriptblock] -and (& $r) -eq 61.2) "$(& $r)"
$r = & $ct -Reader -Tools "$Work\none"
Check 'nothing installed: no reader (nothing recorded, no error)' ($null -eq $r) ''
Finish
