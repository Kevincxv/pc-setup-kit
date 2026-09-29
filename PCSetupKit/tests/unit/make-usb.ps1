# make-usb.ps1: which disk it may erase, and its plan. Made-up disks with -Plan - nothing is downloaded, no disk is
# touched. (The full build was run end to end on a virtual disk: -AllowVirtual.)
. "$PSScriptRoot\..\lib.ps1"
$mu = "$Src\make-usb.ps1"
if (-not (Test-Path $mu)) { Skip 'make-usb' 'not installed here'; Finish }
$disks = @(
    @{ Number = 0; FriendlyName = 'System NVMe'; BusType = 'NVMe'; IsBoot = $true; IsSystem = $true; Size = 2000GB },
    @{ Number = 1; FriendlyName = 'Games HDD'; BusType = 'SATA'; IsBoot = $false; IsSystem = $false; Size = 4000GB },
    @{ Number = 2; FriendlyName = 'SanDisk Ultra'; BusType = 'USB'; IsBoot = $false; IsSystem = $false; Size = 64GB },
    @{ Number = 3; FriendlyName = 'Old stick'; BusType = 'USB'; IsBoot = $false; IsSystem = $false; Size = 4GB },
    @{ Number = 4; FriendlyName = 'Msft Virtual Disk'; BusType = 'File Backed Virtual'; IsBoot = $false; IsSystem = $false; Size = 16GB },
    @{ Number = 5; FriendlyName = 'USB boot drive'; BusType = 'USB'; IsBoot = $true; IsSystem = $true; Size = 500GB })
$json = ConvertTo-Json -InputObject $disks
function MU([int]$disk, [switch]$Virtual, [string]$d = $json) { @(& $mu -Plan -Disks $d -Disk $disk -Yes -NoBackup -AllowVirtual:$Virtual 6>$null) }

$o = MU 2
Check 'a USB stick of 8 GB+: planned - erase it, one FAT32 partition (32 GB at most), Windows from Microsoft, the newest kit' ($o[0] -match '^PLAN: erase disk 2 \(SanDisk Ultra\), one FAT32 partition of 32 GB$' -and "$o" -match "Microsoft's download service" -and "$o" -match 'newest release of Kevincxv/pc-setup-kit') ($o -join ' / ')
foreach ($c in @(@(0, 'the disk Windows runs from'), @(1, 'an internal hard drive'), @(3, 'a stick under 8 GB'), @(5, 'a USB drive Windows runs from (Windows To Go)'), @(4, 'a virtual disk (tests only)'))) {
    $o = MU $c[0]
    Check "never $($c[1]): refused, nothing planned" ("$o" -eq 'NOT A USB') ($o -join ' / ')
}
$o = MU 4 -Virtual
Check '... the virtual disk only with -AllowVirtual (the end-to-end test)' ($o[0] -match '^PLAN: erase disk 4') ($o -join ' / ')
$o = MU 2 -d (ConvertTo-Json -InputObject @($disks[0], $disks[1]))
Check 'no USB stick plugged in: says so, nothing else' ("$o" -eq 'NO USB') ($o -join ' / ')
$muText = Get-Content $mu -Raw
Check 'the disk is checked again right before erasing (disk numbers can change)' ($muText -match '\$d = Get-Disk -Number \$Disk\s*\r?\n\s*if \("\$\(\$d\.BusType\)" -notin \$bus -or \$d\.IsBoot -or \$d\.IsSystem\) \{ throw') ''
Check 'Windows and the kit are downloaded and checked before the stick is erased' ($muText.IndexOf('Get-FileHash $p -Algorithm SHA1') -lt $muText.IndexOf('Clear-Disk') -and $muText.IndexOf('releases/latest') -lt $muText.IndexOf('Clear-Disk') -and $muText.IndexOf("Get-AuthenticodeSignature `"`$src\setup.exe`"") -lt $muText.IndexOf('Clear-Disk')) ''
Finish
