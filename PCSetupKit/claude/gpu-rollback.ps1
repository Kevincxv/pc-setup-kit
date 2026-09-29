# The graphics driver rollback: one click in the app ("Go back to the previous graphics driver", also the fix button on a
# graphics-driver to-do) puts the version before the current one back, when it's still on the PC (the monthly cleanup
# keeps an updated driver's previous version for 30 days). Runs elevated (through the tray).
# - a restore point first; never while a game runs (the screen goes black for a few seconds while it switches)
# - the current package is removed (pnputil /delete-driver /uninstall): Windows puts the previous one on right away
# - the version it went back from is held: listed in driver-blocklist.txt (driver-check.ps1 hides it on Windows
#   Update), and for NVIDIA in gpu-hold.txt (driver-check.ps1 waits for a version newer than that one)
# -List: only returns what it would do (one object: Device, Current, CurrentDate, Previous, PreviousDate, Can, Why) -
# the app shows it. -Yes: no question. -Test (hashtable) with -Do (gets the actions), -Blocklist, -Hold: tests.
param([switch]$List, [switch]$Yes, [hashtable]$Test, [scriptblock]$Do,
    [string]$Blocklist = "$PSScriptRoot\driver-blocklist.txt", [string]$Hold = "$PSScriptRoot\gpu-hold.txt")
$ErrorActionPreference = 'SilentlyContinue'
$T = $Test
function Act([string]$What, [scriptblock]$Real) { if ($Do) { & $Do $What } else { & $Real } }
function V($s) { $v = $null; [void][version]::TryParse(("$s" -replace '[^\d.]', ''), [ref]$v); $v }

# the graphics card with its own driver (a laptop's dedicated one before the built-in one; never Microsoft's basic driver)
$cur = if ($T) { [pscustomobject]$T.Current } else {
    Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='DISPLAY'" | Where-Object { $_.InfName -match '^oem\d+\.inf$' } |
        Sort-Object { if ($_.DeviceName -match 'NVIDIA') { 0 } elseif ($_.DeviceName -match 'Radeon|AMD') { 1 } else { 2 } } |
        Select-Object -First 1 @{ n = 'Device'; e = { $_.DeviceName } }, @{ n = 'Inf'; e = { $_.InfName } }, @{ n = 'Ver'; e = { $_.DriverVersion } },
        @{ n = 'Date'; e = { if ($_.DriverDate) { $_.DriverDate.ToString('yyyy-MM-dd') } } }, @{ n = 'Provider'; e = { $_.DriverProviderName } }
}
$r = [pscustomobject]@{ Device = "$($cur.Device)"; Current = "$($cur.Ver)"; CurrentDate = "$($cur.Date)"; Previous = $null; PreviousDate = $null; Can = $false; Why = '' }
if (-not $cur) { $r.Why = 'No graphics driver of its own on this PC (only the built-in Microsoft one)'; if ($List) { return $r }; return $r.Why }
$pk = @(if ($T) { $T.Packages | ForEach-Object { [pscustomobject]$_ } } else {
        Get-WindowsDriver -Online | Where-Object ClassName -eq 'Display' | ForEach-Object {
            [pscustomobject]@{ Pub = $_.Driver; Name = Split-Path $_.OriginalFileName -Leaf; Ver = "$($_.Version)"; Date = $(if ($_.Date) { $_.Date.ToString('yyyy-MM-dd') }) } }
    })
$mine = $pk | Where-Object Pub -eq $cur.Inf | Select-Object -First 1
$older = if ($mine) { $pk | Where-Object { $_.Name -eq $mine.Name -and $_.Pub -ne $mine.Pub -and (V $_.Ver) -lt (V $cur.Ver) } | Sort-Object { V $_.Ver } -Descending | Select-Object -First 1 }
if ($older) { $r.Previous = $older.Ver; $r.PreviousDate = $older.Date; $r.Can = $true }
else { $r.Why = "The version before $($cur.Ver) isn't on this PC any more (they're kept for 30 days after an update) - for an older one, the maker's driver page: $(if ($cur.Device -match 'NVIDIA') { 'https://www.nvidia.com/en-us/drivers/' } elseif ($cur.Device -match 'Radeon|AMD') { 'https://www.amd.com/en/support/download/drivers.html' } else { 'https://www.intel.com/content/www/us/en/download-center/home.html' })" }
if ($List) { return $r }
if (-not $r.Can) { return $r.Why }

$game = if ($T) { $T.Game } else { & "$PSScriptRoot\game-check.ps1" }
if ($game) { return "Close $game first - the screen goes black for a few seconds while the driver switches" }
if (-not $Yes -and -not $T) {
    Write-Host "Go back from the graphics driver $($cur.Ver) ($($cur.Date)) to $($older.Ver) ($($older.Date)) on $($cur.Device)?" -ForegroundColor Yellow
    Write-Host 'The screen goes black for a few seconds. A restore point is made first.'
    if ((Read-Host 'Type YES to go back') -ne 'YES') { return 'Cancelled - nothing was changed' }
}
$nv = if ($T) { $T.NvidiaVersion } elseif ($cur.Device -match 'NVIDIA') { "$(& nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>$null | Select-Object -First 1)".Trim() }
Act 'restore point' {
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $was = (Get-ItemProperty $k).SystemRestorePointCreationFrequency
    Set-ItemProperty $k SystemRestorePointCreationFrequency 0 -Type DWord
    Checkpoint-Computer -Description 'Before going back to the previous graphics driver (Messiah)' -RestorePointType DEVICE_DRIVER_INSTALL -WarningAction SilentlyContinue
    if ($null -eq $was) { Remove-ItemProperty $k SystemRestorePointCreationFrequency } else { Set-ItemProperty $k SystemRestorePointCreationFrequency $was -Type DWord }
}
$ok = $false
Act "remove $($cur.Inf)" { $null = pnputil /delete-driver $cur.Inf /uninstall /force 2>&1; $script:ok = $LASTEXITCODE -eq 0 }
if ($T) { $ok = $T.DeleteOk }
if (-not $ok) { return "WARNING: couldn't go back to the previous graphics driver - the current one ($($cur.Ver)) stays; Device Manager > Display adapters > Properties > Driver > Roll Back Driver does the same by hand" }
Act 'scan' { $null = pnputil /scan-devices 2>&1 }
"$($cur.Provider)|$($cur.Date)|$($cur.Ver)|$($mine.Name)" | Add-Content $Blocklist -Encoding UTF8
if ($nv) { $nv | Set-Content $Hold -Encoding ASCII }
"Graphics driver: back on $($older.Ver) (from $($older.Date)); $($cur.Ver) won't be installed again - a newer version than it will"
