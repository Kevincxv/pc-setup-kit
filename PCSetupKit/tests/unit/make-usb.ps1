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
Section 'a USB hard drive with files on it is never mistaken for an empty stick'
$one = { param($d) @(& $mu -Plan -Disks (ConvertTo-Json -InputObject @($disks[0], $d)) -Yes -NoBackup 6>$null) }
$o = & $one @{ Number = 7; FriendlyName = 'WD Elements'; BusType = 'USB'; IsBoot = $false; IsSystem = $false; Size = 2000GB; UsedGB = 850; Backup = $true }
Check 'the only USB disk holds files (the files-backup drive): not picked by itself, nothing planned' ("$o" -eq 'CHOOSE A DISK') ($o -join ' / ')
$o = & $one @{ Number = 7; FriendlyName = 'Stick with photos'; BusType = 'USB'; IsBoot = $false; IsSystem = $false; Size = 64GB; UsedGB = 12 }
Check '... any files on it: the same' ("$o" -eq 'CHOOSE A DISK') ($o -join ' / ')
$o = & $one @{ Number = 7; FriendlyName = 'Empty stick'; BusType = 'USB'; IsBoot = $false; IsSystem = $false; Size = 64GB; UsedGB = 0 }
Check '... an empty stick: picked by itself (-Yes)' ($o[0] -match '^PLAN: erase disk 7') ($o -join ' / ')
$o = @(& $mu -Plan -Disks (ConvertTo-Json -InputObject @($disks[0], @{ Number = 7; FriendlyName = 'WD Elements'; BusType = 'USB'; IsBoot = $false; IsSystem = $false; Size = 2000GB; UsedGB = 850; Backup = $true })) -Disk 7 -Yes -NoBackup 6>&1 | ForEach-Object { "$_" })
Check '... chosen by number anyway: the warning names the files and the backup before ERASE' ("$o" -match '850 GB of files on it' -and "$o" -match 'holds your backup') ($o -join ' / ')
$muText = Get-Content $mu -Raw
Check 'the disk is checked again right before erasing (disk numbers can change)' ($muText -match '\$d = Get-Disk -Number \$Disk\s*\r?\n\s*if \("\$\(\$d\.BusType\)" -notin \$bus -or \$d\.IsBoot -or \$d\.IsSystem\) \{ throw') ''
Check 'Windows and the kit are downloaded and checked before the stick is erased' ($muText.IndexOf('Get-FileHash $p -Algorithm SHA1') -lt $muText.IndexOf('Clear-Disk') -and $muText.IndexOf('releases/latest') -lt $muText.IndexOf('Clear-Disk') -and $muText.IndexOf("Get-AuthenticodeSignature `"`$src\setup.exe`"") -lt $muText.IndexOf('Clear-Disk')) ''

Section 'the slimmed-down Windows on the stick (tiny11-style)'
$km = "$Kit\claude\make-usb.ps1"   # (the kit's copy: it reads tweaks.ps1 next to it)
$ip = @(& $km -ShowImagePlan)
$img = @((($ip -match '^BLOAT ') -replace '^BLOAT ') -split ',' | Where-Object { $_ })
$ast = [Management.Automation.Language.Parser]::ParseFile("$Kit\tweaks.ps1", [ref]$null, [ref]$null)
$tw = @($ast.Find({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and "$($n.Left)" -eq '$apps' }, $true).Right.Expression.SafeGetValue())
Check 'the image leaves out every app setup removes (one list: tweaks.ps1''s)...' ($img.Count -ge 40 -and -not ($tw | Where-Object { $_ -notin $img -and $_ -ne 'Microsoft.XboxGamingOverlay' })) "image $($img.Count), tweaks $($tw.Count)"
Check '... and tiny11''s own extras on top: the Xbox sign-in parts and app, Edge' (($img -contains 'Microsoft.XboxIdentityProvider') -and ($img -contains 'Microsoft.GamingApp') -and ($img -contains 'Microsoft.MicrosoftEdge.Stable')) ''
$parts = @((($ip -match '^PARTS ') -replace '^PARTS ') -split ',' | Where-Object { $_ })
Check '... the old Windows parts, and text-to-speech, OCR, handwriting and face sign-in' (($parts -contains 'Browser.InternetExplorer') -and ($parts -contains 'Language.TextToSpeech') -and ($parts -contains 'Hello.Face')) ($parts -join ', ')
Check 'Edge, WebView2 and EdgeUpdate out of the image, Edge not reinstalled - but an app may still install WebView2 (its id is never blocked)' ((Get-Content $km -Raw) -match 'Microsoft\\EdgeWebView' -and (Get-Content $km -Raw) -match 'Install\{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062\}' -and (Get-Content $km -Raw) -notmatch 'F3017226-FE2A-4295-8BDF-00C3A9A7E4C5') ''
Check '... except the Xbox Game Bar (AMD dual-CCD X3D CPUs need it: setup decides on the new PC)' ($img -notcontains 'Microsoft.XboxGamingOverlay' -and $tw -contains 'Microsoft.XboxGamingOverlay') ''
$pins = try { ((($ip -match '^PINS ') -replace '^PINS ') | ConvertFrom-Json).pinnedList } catch { $null }
$ids = @($pins | ForEach-Object { if ($_.packagedAppId) { ($_.packagedAppId -split '_')[0] } })
Check 'a new user''s Start: Windows'' own tools, none of the removed apps (no placeholder that installs one when clicked)' (@($pins).Count -ge 6 -and ($ids -contains 'Microsoft.WindowsCalculator') -and -not ($ids | Where-Object { $_ -in $img })) ($ids -join ', ')
$mt = Get-Content $km -Raw
Check 'never what updates and repairs need: no component store, recovery or Defender removal' ($mt -notmatch '(?i)WinSxS|winre\.wim|Windows Defender\\|/Remove-Package|Remove-WindowsPackage|/ResetBase') ''
Check 'anything failing leaves that edition as Microsoft ships it (discarded, never half-changed)' ($mt -match "'/Discard'" -and $mt -match 'finally \{ \[gc\]::Collect\(\); foreach \(\$h in') ''
$oi = [Management.Automation.Language.Parser]::ParseInput($mt, [ref]$null, [ref]$null).Find({ param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq 'Optimize-Image' }, $true).Extent.Text
Check 'a harmless message from a Windows tool (a registry key that isn''t there) can''t end the slimming (9/30: under Stop, PowerShell 5.1 made it fatal)' ($oi -match '\$ErrorActionPreference = ''Continue''') ''
$ri = [Management.Automation.Language.Parser]::ParseInput($mt, [ref]$null, [ref]$null).Find({ param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq 'Remove-ImagePath' }, $true).Extent.Text
Check '... a single file is taken over without /r (an error on a file: 9/30 OneDrive''s installer stayed)' ($ri -match 'else \{ & takeown /f \$Path /a 2>') ''
Check 'Start''s layout file has no byte-order mark (Windows ignores it then - 9/30), and the pins are Windows'' Start-pins policy too, marked as the kit''s' ($oi -match 'LayoutModification\.json", \(Get-StartPins\), \(New-Object Text\.UTF8Encoding \$false\)\)' -and $oi -match 'New-ItemProperty \$rk -Name ConfigureStartPins' -and $oi -match '/v PCKit /t REG_DWORD /d 1') ''
Check '-StockImage survives the admin prompt (passed on when it restarts elevated)' ($mt -match "@\(if \(\`$StockImage\) \{ '-StockImage' \}\)") ''

Finish