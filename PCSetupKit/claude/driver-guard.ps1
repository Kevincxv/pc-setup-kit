# A blue screen soon after a driver update: put the previous version back, by itself. Run by health-check.ps1 when it
# finds new blue screens (elevated). A driver package counts as the likely cause when all of this holds:
# - it arrived on the PC (from any source: Windows Update, the kit's driver check, a vendor app) at most 3 days
#   before the blue screen,
# - the 14 days before it arrived had no blue screen (a PC that already crashed has another cause - the crash
#   escalation ladder in the maintain skill handles that),
# - an older version of the same driver is still on the PC to go back to (monthly cleanup keeps it for 30 days).
# Then the new package is removed (pnputil /uninstall: the device goes back to the older version right away) and
# listed in driver-blocklist.txt, so driver-check.ps1 hides it on Windows Update instead of installing it again.
# Graphics drivers are never swapped while the PC is in use (the screen goes black for a moment and games crash):
# that one is reported instead. Prints one line per action.
# -WhatIf: only say what would happen.
param([datetime[]]$Crashes, [switch]$WhatIf, [string]$Blocklist = "$PSScriptRoot\driver-blocklist.txt")
$ErrorActionPreference = 'SilentlyContinue'
if (-not $Crashes) { return }
$first = ($Crashes | Sort-Object)[0]

$pk = @(Get-WindowsDriver -Online | ForEach-Object {
        $dir = Split-Path $_.OriginalFileName
        [pscustomobject]@{ Pub = $_.Driver; Name = Split-Path $_.OriginalFileName -Leaf; Class = $_.ClassName; Provider = $_.ProviderName
            Date = $_.Date; Ver = $_.Version; Staged = (Get-Item -LiteralPath $dir).CreationTime }
    } | Where-Object Staged)
$suspects = @($pk | Where-Object { $_.Staged -lt $first -and $_.Staged -gt $first.AddDays(-3) } | Sort-Object Staged -Descending)
foreach ($s in $suspects) {
    $older = $pk | Where-Object { $_.Name -eq $s.Name -and $_.Pub -ne $s.Pub -and [version]$_.Ver -lt [version]$s.Ver } | Sort-Object { [version]$_.Ver } -Descending | Select-Object -First 1
    if (-not $older) { continue }   # nothing to go back to (a first install, or the same version again)
    $before = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; StartTime = $s.Staged.AddDays(-14); EndTime = $s.Staged })
    if ($before) { continue }       # it was already crashing before this driver came
    $hours = [int]($first - $s.Staged).TotalHours
    $what = "$($s.Provider) $($s.Name -replace '\.inf$') $($s.Ver)"
    if ($s.Class -eq 'Display') {
        "Driver guard: a blue screen came $hours h after the graphics driver $what arrived - not swapped automatically (graphics); the previous version $($older.Ver) is still on the PC"
        continue
    }
    if ($WhatIf) { "would roll back $what -> $($older.Ver)"; continue }
    $o = pnputil /delete-driver $s.Pub /uninstall /force 2>&1 | Out-String
    if ($o -match 'deleted successfully|Driver package deleted') {
        "$($s.Provider)|$($s.Date.ToString('yyyy-MM-dd'))|$($s.Ver)|$($s.Name)" | Add-Content $Blocklist -Encoding UTF8
        "Driver rolled back: $what (a blue screen came $hours h after it arrived) - back on $($older.Ver); this version won't be installed again"
    } else { "WARNING: couldn't roll back the driver $what after the blue screen ($("$o".Trim() -split "`n" | Select-Object -Last 1))" }
}
