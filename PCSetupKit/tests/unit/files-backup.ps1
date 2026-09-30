# files-backup.ps1: the owner's files copied to a second drive by itself, once the drive is chosen (one click).
# Made-up drives (-Test); the copying goes to a recorder - no real files or drives are touched.
. "$PSScriptRoot\..\lib.ps1"
$fb = "$Src\files-backup.ps1"
if (-not (Test-Path $fb)) { Skip 'files-backup' 'not installed here'; Finish }
$st = "$Work\files-backup-state.json"; $opts = "$Work\kit-options.txt"
$global:acts = @()
$rec = { param($w) $global:acts += $w }
$usb = @{ Id = '\\?\Volume{1111}\'; Label = 'Samsung T7'; Letter = 'E'; SizeGB = 931 }
function FB([hashtable]$over = @{}, [string[]]$Mode = @('Check'), [datetime]$now = (Get-Date)) {
    $t = @{ Candidates = @($usb); Configured = $null; Other = $false; Exit = 1; LastRun = $null; LastSeen = $null; Game = $null }
    foreach ($k in $over.Keys) { $t[$k] = $over[$k] }
    [IO.File]::Delete($st); $p = @{ Test = $t; Do = $rec; State = $st; Options = $opts; Now = $now }; foreach ($m in $Mode) { $p[$m] = $true }
    $global:acts = @(); @(& $fb @p)
}
$o = FB
Check 'a second drive and nothing backs the files up: offered (its name, size and letter), nothing copied yet' ("$o" -match '^Reminder: Samsung T7 \(931 GB, E:\) is connected and nothing is backed up$' -and -not $acts) ($o -join ' / ')
$o = FB @{ Other = $true }
Check '... File History or another backup already there: not offered' (-not $o) ($o -join ' / ')
$o = FB @{ Candidates = @() }
Check 'no second drive: nothing' (-not $o) ''
$o = FB @{} -Mode 'Enable'
Check 'the button (Enable): all five folders copied, said' ((($acts -join ',') -eq 'copy Documents,copy Desktop,copy Pictures,copy Videos,copy Music') -and "$o" -match 'new and changed files copied to Samsung T7 \(E:\\Messiah Backup\)') ($o -join ' / ')
$o = FB @{ Configured = $usb.Id; LastRun = (Get-Date).AddDays(-2).ToString('o') }
Check 'the chosen drive connected, last backup 2 days ago: backed up again by itself' ($acts.Count -eq 5) ($o -join ' / ')
$o = FB @{ Configured = $usb.Id; LastRun = (Get-Date).AddHours(-3).ToString('o') }
Check '... 3 hours ago: not yet (at most every 20 hours)' (-not $acts -and -not $o) ''
$o = FB @{ Configured = $usb.Id; Exit = 0 }
Check '... nothing new: up to date' ("$o" -match 'is up to date') ($o -join ' / ')
$o = FB @{ Configured = $usb.Id; Exit = 8 }
Check '... some files failed (drive full, files in use): FAILED, tried again next time' ("$o" -match 'FAILED') ($o -join ' / ')
$o = FB @{ Configured = $usb.Id; Game = 'Test Game' }
Check '... a game running: waits' (-not $acts) ''
$o = FB @{ Configured = $usb.Id; Candidates = @(); LastSeen = (Get-Date).AddDays(-20).ToString('o') }
Check 'the chosen drive away for 20 days: a reminder to plug it in' ("$o" -match "hasn't been connected for 20 days") ($o -join ' / ')
$o = FB @{ Configured = $usb.Id; Candidates = @(); LastSeen = (Get-Date).AddDays(-3).ToString('o') }
Check '... away 3 days: nothing said' (-not $o) ''
$o = FB @{ Configured = 'another' } -Mode 'Arrived'
Check 'a different drive plugged in (tray): nothing' (-not $acts -and -not $o) ''
Check 'never deletes from the backup (robocopy without /MIR or /PURGE)' ((Get-Content $fb -Raw) -match 'robocopy .* /E /XO' -and (Get-Content $fb -Raw) -notmatch '/MIR|/PURGE') ''
Finish
