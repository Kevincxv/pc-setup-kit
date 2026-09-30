# junk-apps.ps1: plain junk that came with the PC removed by itself, once; trial antivirus / VPNs found for the
# one-click to-do; hardware tools never touched. Made-up app lists (-Test); uninstalls go to a recorder.
. "$PSScriptRoot\..\lib.ps1"
$ja = "$Src\junk-apps.ps1"
if (-not (Test-Path $ja)) { Skip 'junk-apps' 'not installed here'; Finish }
$st = "$Work\junk-state.json"
$global:acts = @()
$rec = { param($w) $global:acts += $w }
function App($n) { @{ DisplayName = $n; QuietUninstallString = "`"C:\x\$n\uninst.exe`" /S"; UninstallString = "`"C:\x\$n\uninst.exe`"" } }
function JA($apps, $gone = @(), [switch]$Keep) { if (-not $Keep) { [IO.File]::Delete($st) }; $global:acts = @(); @(& $ja -Test @{ Apps = $apps; Gone = $gone } -Do $rec -State $st) }

$all = @((App 'WildTangent Games'), (App 'McAfee WebAdvisor'), (App 'McAfee LiveSafe'), (App 'ExpressVPN'), (App 'ARMOURY CRATE Service'), (App 'iCUE'), (App 'Steam'), (App 'Dungeon Keeper'))
$o = JA $all @('WildTangent Games', 'McAfee WebAdvisor')
Check 'plain junk (game offers, browser add-ons) uninstalled silently, said' ((($acts -join ',') -eq 'uninstall WildTangent Games,uninstall McAfee WebAdvisor') -and "$o" -match 'Removed what came with the PC .*WildTangent Games, McAfee WebAdvisor') (($acts + $o) -join ' / ')
Check '... trial antivirus and VPN: found for the one-click to-do, not removed by itself' ("$o" -match 'Found: McAfee LiveSafe' -and "$o" -match 'Found: ExpressVPN' -and -not ($acts -match 'LiveSafe|ExpressVPN')) ($o -join ' / ')
Check '... hardware tools, Steam and a game called "Dungeon Keeper": never touched or listed' (-not ($acts -match 'ARMOURY|iCUE|Steam|Keeper') -and "$o" -notmatch 'ARMOURY|iCUE|Steam|Dungeon') ($o -join ' / ')
$o = JA @((App 'WildTangent Games')) @() -Keep
Check 'junk installed again after it was removed: the owner''s choice, left alone' (-not $acts) (($acts + $o) -join ' / ')
$o = JA @(@{ DisplayName = 'WildTangent Games'; QuietUninstallString = ''; UninstallString = 'MsiExec.exe /I{12345678-ABCD-1234-ABCD-123456789012}' }) @('WildTangent Games')
Check 'an MSI without a quiet command: uninstalled silently anyway (msiexec /x)' ($acts -contains 'uninstall WildTangent Games') ($acts -join ',')
$o = JA @((App 'WildTangent Games'))
Check 'its uninstaller didn''t remove it: not claimed as removed' ("$o" -notmatch 'Removed') ($o -join ' / ')
$global:acts = @(); $o = @(& $ja -Test @{ Apps = @((App 'McAfee LiveSafe')); Gone = @() } -Do $rec -State $st -Remove 'McAfee LiveSafe')
Check 'the app''s Uninstall button (-Remove): that app''s own uninstaller, visibly' (($acts -join ',') -eq 'uninstall (visible) McAfee LiveSafe') ($acts -join ',')
Finish
