# Makes a complete PC Setup Kit install USB in one go - Windows 11 from Microsoft plus the kit, so a new PC installs
# Windows and sets itself up with no other steps:
#   1. the USB stick to use: only USB disks of 8 GB or more, never the disk Windows runs from; typed ERASE to confirm
#   2. Microsoft's own Windows 11 image, in this PC's language, kept for next time: the ISO from Microsoft's download
#      service (via Fido - the open-source script by Rufus' author, one checked version), or when that service refuses,
#      the Media Creation Tool's own source (Microsoft's image catalog + SHA-1). Used only with setup.exe signed by Microsoft.
#   3. the stick: FAT32 (every PC can start from it), Windows copied on (its big install.wim split into
#      parts under 4 GB, which Windows Setup reads as one)
#   4. the kit's newest tested release: autounattend.xml + PCSetupKit\ (optionally with Messiah), and this PC's
#      settings backup when the stick is for reinstalling THIS PC
# Run from the app (Maintenance > Make an install USB) or by hand; asks for admin. Takes 20-40 minutes (a 7 GB download).
# -Disk N -Yes -WithClaude -NoBackup: no questions. -Iso <file>: a Windows 11 ISO already downloaded.
# -Plan: say what it would do, change nothing (tests); -Disks <json>: made-up disks for -Plan (tests); -AllowVirtual: a
# virtual disk (VHD) counts as a stick too (the end-to-end test).
param([int]$Disk = -1, [switch]$Yes, [switch]$WithClaude, [switch]$NoBackup, [string]$Iso, [switch]$Plan, [string]$Disks, [switch]$AllowVirtual,
    [string]$Cache = "$env:ProgramData\PCSetupKit\windows-image")
$ErrorActionPreference = 'Stop'
$repo = 'Kevincxv/pc-setup-kit'
$fidoUrl = 'https://raw.githubusercontent.com/pbatard/Fido/v1.70/Fido.ps1'
$fidoSha = '24C86067FA399D2FD75EF0693A2EC79CA8DB162827F808CAAC03541CBF640C13'
function Say($m, $color = 'Gray') { Write-Host $m -ForegroundColor $color }
function Ask($q) { if ($Yes) { return '' }; Read-Host $q }

if (-not $Plan -and -not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") + @(if ($Disk -ge 0) { '-Disk', $Disk }) + @(if ($Yes) { '-Yes' }) + @(if ($WithClaude) { '-WithClaude' }) + @(if ($NoBackup) { '-NoBackup' }) + @(if ($Iso) { '-Iso', "`"$Iso`"" })
    Start-Process powershell -Verb RunAs -ArgumentList $a; return
}
$Host.UI.RawUI.WindowTitle = 'PC Setup Kit - making an install USB'
Say "`nPC Setup Kit - install USB" 'Cyan'
Say "Makes a USB stick that installs Windows 11 and sets the new PC up by itself. The stick is ERASED.`n"

# --- 1. the stick ---
$all = if ($Disks) { @($Disks | ConvertFrom-Json | ForEach-Object { $_ }) } else { @(Get-Disk) }
$bus = @('USB') + @(if ($AllowVirtual) { 'File Backed Virtual' })
$usb = @($all | Where-Object { "$($_.BusType)" -in $bus -and -not $_.IsBoot -and -not $_.IsSystem -and $_.Size -ge 7GB } | Sort-Object Number)
if (-not $usb) { Say 'No USB stick of 8 GB or more found. Plug one in and run this again.' 'Yellow'; return 'NO USB' }
foreach ($d in $usb) { Say ("  Disk {0}: {1} ({2:N0} GB)" -f $d.Number, "$($d.FriendlyName)".Trim(), ($d.Size / 1GB)) }
if ($Disk -lt 0) { $Disk = if ($usb.Count -eq 1 -and $Yes) { $usb[0].Number } else { [int](Ask "`nWhich disk number is the USB stick") } }
$target = $usb | Where-Object { $_.Number -eq $Disk }
if (-not $target) { Say "Disk $Disk is not one of the USB sticks above - nothing was changed." 'Red'; return 'NOT A USB' }
Say ("`nEverything on disk {0} ({1}, {2:N0} GB) will be ERASED." -f $target.Number, "$($target.FriendlyName)".Trim(), ($target.Size / 1GB)) 'Yellow'
if (-not $Yes -and (Ask 'Type ERASE to continue') -ne 'ERASE') { Say 'Cancelled - nothing was changed.'; return 'CANCELLED' }
if (-not $Yes -and -not $WithClaude) { $WithClaude = (Ask 'Include Messiah, the optional Claude part (needs a Claude account)? y/N') -match '^y' }
$bk = Get-ChildItem "$([Environment]::GetFolderPath('MyDocuments'))\PC Setup Kit Backup\$env:COMPUTERNAME-*.zip" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
$withBackup = $bk -and -not $NoBackup -and ($Yes -or (Ask "Is this stick for reinstalling THIS PC? Then its settings backup goes on it too. Y/n") -notmatch '^n')

if ($Plan) {
    "PLAN: erase disk $($target.Number) ($("$($target.FriendlyName)".Trim())), one FAT32 partition of $([int]([Math]::Min($target.Size, 32GB) / 1GB)) GB"
    "PLAN: Windows 11 image: $(if ($Iso) { $Iso } else { "Microsoft's download service (Fido), else Microsoft's image catalog (the Media Creation Tool's)" }), setup.exe signed by Microsoft"
    "PLAN: kit: the newest release of $repo$(if ($WithClaude) { ', with Messiah' }); settings backup: $(if ($withBackup) { $bk.Name } else { 'no' })"
    return
}

# --- 2. Windows 11 from Microsoft (downloaded and checked before anything is erased) ---
# First choice: the ISO from Microsoft's download service (via Fido). That service sometimes refuses automated
# requests ("Sentinel"), so the fallback is the one the Media Creation Tool itself uses: Microsoft's image catalog
# (products.cab) and the Windows image (.esd) it lists on Microsoft's update servers, checked against the catalog's
# SHA-1; the stick is then built from it with DISM, as the Media Creation Tool does.
$ProgressPreference = 'SilentlyContinue'
New-Item $Cache -ItemType Directory -Force | Out-Null
$esd = $null
if (-not $Iso) {
    $cached = Join-Path $Cache 'Win11_x64.iso'
    if ((Test-Path $cached) -and (Get-Item $cached).Length -gt 4GB -and (Get-Item $cached).LastWriteTime -gt (Get-Date).AddDays(-60)) { $Iso = $cached; Say 'Windows 11 image: using the one downloaded before' }
    else {
        Say "Windows 11 image: asking Microsoft's download service..."
        $link = $null
        try {
            $fido = Join-Path $env:TEMP "pckit-fido-$PID.ps1"
            Invoke-WebRequest $fidoUrl -OutFile $fido -UseBasicParsing -TimeoutSec 60
            if ((Get-FileHash $fido -Algorithm SHA256).Hash -eq $fidoSha) {
                $lang = switch -Wildcard ((Get-UICulture).Name) { 'en-US' { 'English' } 'en-*' { 'English International' } 'pt-BR' { 'Brazilian Portuguese' } 'zh-CN' { 'Chinese Simplified' } 'zh-TW' { 'Chinese Traditional' } 'es-MX' { 'Spanish (Mexico)' } 'fr-CA' { 'French Canadian' } default { (Get-UICulture).Parent.EnglishName } }
                foreach ($l in @($lang, 'English') | Select-Object -Unique) {
                    $link = "$(& powershell -NoProfile -ExecutionPolicy Bypass -File $fido -Win 11 -Rel Latest -Ed Pro -Lang $l -Arch x64 -GetUrl 2>$null | Select-Object -Last 1)".Trim()
                    if ($link -match '^https://[^/]*microsoft\.com/') { break } else { $link = $null }
                }
            }
            [IO.File]::Delete($fido)
        } catch { $link = $null }
        if ($link) {
            Say 'Windows 11 image: downloading the ISO from Microsoft (about 7 GB - it can take a while)...'
            Start-BitsTransfer -Source $link -Destination "$cached.part" -DisplayName 'Windows 11 image' -Description 'PC Setup Kit install USB'
            Move-Item "$cached.part" $cached -Force; $Iso = $cached
        }
        else {
            Say "Windows 11 image: the download service said no right now - using Microsoft's image catalog instead..."
            $cab = Join-Path $Cache 'products.cab'; $cx = Join-Path $Cache 'catalog'
            Invoke-WebRequest 'https://go.microsoft.com/fwlink/?LinkId=2156292' -OutFile $cab -UseBasicParsing -TimeoutSec 60
            if (Test-Path $cx) { [IO.Directory]::Delete($cx, $true) }; New-Item $cx -ItemType Directory -Force | Out-Null
            & expand.exe $cab -F:* $cx | Out-Null
            # the catalog is a cab holding the XML (whatever name expand gives it); some catalogs nest one more cab
            $xmlText = $null
            foreach ($i in 1..2) {
                $f0 = Get-ChildItem $cx -File | Select-Object -First 1
                $bytes = [IO.File]::ReadAllBytes($f0.FullName)
                if ([Text.Encoding]::ASCII.GetString($bytes, 0, 4) -eq 'MSCF') { $n2 = Join-Path $Cache "catalog$i"; New-Item $n2 -ItemType Directory -Force | Out-Null; & expand.exe $f0.FullName -F:* $n2 | Out-Null; $cx = $n2 }
                else { $xmlText = [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF); break }
            }
            if (-not $xmlText) { throw "Microsoft's image catalog could not be read. Download the ISO yourself from microsoft.com/software-download/windows11 and run this with -Iso <the file>. Nothing was changed." }
            $files = @(([xml]$xmlText).SelectNodes('//File'))
            $want = (Get-UICulture).Name.ToLower()
            $pick = @($want, 'en-us') | ForEach-Object { $l = $_; $files | Where-Object { $_.LanguageCode -eq $l -and $_.Architecture -eq 'x64' -and $_.Edition -eq 'Professional' -and $_.FileName -match 'CLIENTCONSUMER' } } | Select-Object -First 1
            if (-not $pick) { throw "No Windows 11 image in Microsoft's catalog for this language. Nothing was changed." }
            $esd = Join-Path $Cache $pick.FileName
            $okSha = { param($p) (Test-Path $p) -and (Get-FileHash $p -Algorithm SHA1).Hash -eq "$($pick.Sha1)".ToUpper() }
            if (-not (& $okSha $esd)) {
                Say "Windows 11 image: downloading $($pick.FileName) from Microsoft's update servers ($([Math]::Round([double]$pick.Size / 1GB, 1)) GB)..."
                # (Microsoft's update servers serve these over http only, like the Media Creation Tool gets them: the catalog's
                # SHA-1 below and the Microsoft signature on the finished setup.exe are what make it safe)
                # a BITS job that survives this window closing: a later run picks the same download up where it stopped
                $job = Get-BitsTransfer -Name 'PCSetupKit Windows image' -ErrorAction SilentlyContinue | Where-Object { $_.FileList.RemoteName -contains "$($pick.FilePath)" } | Select-Object -First 1
                if (-not $job) { Get-BitsTransfer -Name 'PCSetupKit Windows image' -ErrorAction SilentlyContinue | Remove-BitsTransfer; $job = Start-BitsTransfer -Source "$($pick.FilePath)" -Destination "$esd.part" -DisplayName 'PCSetupKit Windows image' -Asynchronous -Priority Foreground }
                else { Say '  (continuing the download from before)'; Resume-BitsTransfer $job -Asynchronous | Out-Null }
                $shown = -1
                while ($job.JobState -in 'Queued', 'Connecting', 'Transferring', 'TransientError') {
                    if ($job.BytesTotal -gt 0 -and $job.BytesTotal -lt 1TB -and ($pc = [int][Math]::Floor(10 * $job.BytesTransferred / $job.BytesTotal) * 10) -gt $shown) { $shown = $pc; Say "  $pc% ($([Math]::Round($job.BytesTransferred / 1GB, 1)) of $([Math]::Round($job.BytesTotal / 1GB, 1)) GB)" }
                    Start-Sleep 3
                }
                if ($job.JobState -ne 'Transferred') { $state = "$($job.JobState) $($job.ErrorDescription)".Trim(); Remove-BitsTransfer $job; throw "The Windows image download stopped ($state) - run this again. Nothing was changed." }
                Complete-BitsTransfer $job
                Move-Item "$esd.part" $esd -Force
                if (-not (& $okSha $esd)) { [IO.File]::Delete($esd); throw "The downloaded Windows image doesn't match Microsoft's catalog (SHA-1) - deleted. Nothing was changed." }
            }
            Say 'Windows 11 image: matches the catalog'
        }
    }
}
$img = $null; $src = $null; $wim = $null
try {
    if ($Iso) {
        $img = Mount-DiskImage -ImagePath $Iso -PassThru
        $src = "$(($img | Get-Volume).DriveLetter):"
        $sig = Get-AuthenticodeSignature "$src\setup.exe"
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw "The Windows image isn't signed by Microsoft ($($sig.Status)) - not used. Nothing was changed." }
        $wim = Get-Item "$src\sources\install.wim", "$src\sources\install.esd" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $wim) { throw "The Windows image has no install.wim - not a Windows 11 installer. Nothing was changed." }
    }

    # --- the kit's newest tested release (downloaded before anything is erased too) ---
    Say 'PC Setup Kit: downloading the newest tested release...'
    $tag = try { (Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'pc-setup-kit' } -TimeoutSec 30).tag_name } catch { $null }
    if (-not $tag) { try { $r = Invoke-WebRequest "https://github.com/$repo/releases/latest" -Method Head -UseBasicParsing -TimeoutSec 30; if ("$($r.BaseResponse.ResponseUri)" -match '/releases/tag/([^/?#]+)$') { $tag = $Matches[1] } } catch { } }
    if (-not $tag) { throw "Couldn't reach GitHub for the kit - check the internet connection. Nothing was changed." }
    $kd = Join-Path $env:TEMP "pckit-usb-$PID"; New-Item $kd -ItemType Directory -Force | Out-Null
    Invoke-WebRequest "https://github.com/$repo/archive/refs/tags/$tag.zip" -OutFile "$kd\kit.zip" -UseBasicParsing
    Expand-Archive "$kd\kit.zip" "$kd\x" -Force
    $kroot = (Get-ChildItem "$kd\x" -Directory | Select-Object -First 1).FullName
    if (-not (Test-Path "$kroot\PCSetupKit\setup.ps1") -or -not (Test-Path "$kroot\autounattend.xml")) { throw 'The kit download is incomplete - try again later. Nothing was changed.' }
    $tag | Set-Content "$kroot\PCSetupKit\kit-version.txt"

    # --- 3. the stick: erased, one FAT32 partition (32 GB at most - the FAT32 limit in Windows), active ---
    Say "USB: erasing disk $Disk and formatting it..."
    $d = Get-Disk -Number $Disk
    if ("$($d.BusType)" -notin $bus -or $d.IsBoot -or $d.IsSystem) { throw "Disk $Disk is not a USB stick (anymore) - stopped. Nothing was changed." }   # (checked again: numbers can change)
    if ($d.PartitionStyle -ne 'RAW') { Clear-Disk -Number $Disk -RemoveData -RemoveOEM -Confirm:$false }
    Initialize-Disk -Number $Disk -PartitionStyle MBR -ErrorAction SilentlyContinue
    $part = if ($d.Size -le 32GB + 64MB) { New-Partition -DiskNumber $Disk -UseMaximumSize -IsActive -AssignDriveLetter } else { New-Partition -DiskNumber $Disk -Size 32GB -IsActive -AssignDriveLetter }
    $vol = Format-Volume -Partition $part -FileSystem FAT32 -NewFileSystemLabel 'PCKIT-WIN11' -Confirm:$false -Force
    $dst = "$($vol.DriveLetter):"
    # an install.wim over 4 GB doesn't fit FAT32: split into install.swm parts, which Windows Setup reads as one
    function Put-InstallImage([string]$From) {
        if ((Get-Item $From).Length -gt 4GB - 1MB) {
            & dism /Split-Image "/ImageFile:$From" "/SWMFile:$dst\sources\install.swm" /FileSize:3800 | Out-Null
            if ($LASTEXITCODE) { throw "Splitting install.wim failed (DISM $LASTEXITCODE)" }
        } else { Copy-Item $From "$dst\sources\" }
    }
    if ($Iso) {
        Say 'USB: copying Windows 11 (about 10 minutes)...'
        & robocopy "$src\" "$dst\" /E /R:2 /W:2 /NFL /NDL /NJH /NJS /NP /XF install.wim install.esd | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Copying Windows onto the stick failed (robocopy $LASTEXITCODE)" }
        Put-InstallImage $wim.FullName
    }
    else {
        # from the .esd, as the Media Creation Tool builds it: image 1 = the setup files, 2 + 3 = boot.wim (Windows PE
        # and Windows Setup), 4 and up = the Windows editions (Home, Pro, ...) -> install.wim
        Say 'USB: building Windows 11 from the image (about 20-30 minutes)...'
        $info = "$(& dism /Get-WimInfo "/WimFile:$esd")"
        $count = ([regex]::Matches($info, 'Index : (\d+)') | ForEach-Object { [int]$_.Groups[1].Value } | Measure-Object -Maximum).Maximum
        if ($count -lt 4) { throw "The Windows image has an unexpected layout ($count images)" }
        & dism /Apply-Image "/ImageFile:$esd" /Index:1 "/ApplyDir:$dst\" | Out-Null
        if ($LASTEXITCODE) { throw "Applying the setup files failed (DISM $LASTEXITCODE)" }
        & dism /Export-Image "/SourceImageFile:$esd" /SourceIndex:2 "/DestinationImageFile:$dst\sources\boot.wim" /Compress:max | Out-Null
        & dism /Export-Image "/SourceImageFile:$esd" /SourceIndex:3 "/DestinationImageFile:$dst\sources\boot.wim" /Compress:max /Bootable | Out-Null
        if ($LASTEXITCODE) { throw "Building boot.wim failed (DISM $LASTEXITCODE)" }
        $tmpWim = Join-Path $Cache 'install.wim'; if (Test-Path $tmpWim) { [IO.File]::Delete($tmpWim) }
        foreach ($i in 4..$count) {
            & dism /Export-Image "/SourceImageFile:$esd" "/SourceIndex:$i" "/DestinationImageFile:$tmpWim" /Compress:max | Out-Null
            if ($LASTEXITCODE) { throw "Building install.wim failed at image $i (DISM $LASTEXITCODE)" }
        }
        Put-InstallImage $tmpWim; [IO.File]::Delete($tmpWim)
        $sig = Get-AuthenticodeSignature "$dst\setup.exe"
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw "The built setup.exe isn't signed by Microsoft ($($sig.Status)) - don't use this stick." }
    }

    # --- 4. the kit, Messiah, the settings backup ---
    Say 'USB: adding the PC Setup Kit...'
    Copy-Item "$kroot\autounattend.xml" "$dst\"
    Copy-Item "$kroot\PCSetupKit" "$dst\" -Recurse
    Copy-Item "$kroot\README.txt" "$dst\PC Setup Kit README.txt" -ErrorAction SilentlyContinue
    if ($WithClaude) { '' | Set-Content "$dst\PCSetupKit\with-claude.txt" }
    if ($withBackup) { New-Item "$dst\PC Setup Kit Backup" -ItemType Directory -Force | Out-Null; Copy-Item $bk.FullName "$dst\PC Setup Kit Backup\" }
    [IO.Directory]::Delete($kd, $true)
    $ok = (Test-Path "$dst\setup.exe") -and (Test-Path "$dst\efi\boot\bootx64.efi") -and (Test-Path "$dst\sources\boot.wim") -and (Test-Path "$dst\autounattend.xml") -and (Test-Path "$dst\PCSetupKit\setup.ps1") -and
        ((Test-Path "$dst\sources\install.swm") -or (Test-Path "$dst\sources\install.wim") -or (Test-Path "$dst\sources\install.esd"))
    if (-not $ok) { throw 'The stick is missing files after copying - run this again.' }
    Say "`nDone - the install USB is ready ($dst, kit $tag$(if ($WithClaude) { ', with Messiah' })$(if ($withBackup) { ', with this PC''s settings' }))." 'Green'
    Say 'On the new PC: start it from the USB (the boot-menu key, often F8, F11 or F12), pick the drive to install on, and wait.'
    Say 'Everything else happens by itself. Keep the USB plugged in until the "Setting up this PC" window says it is finished.'
    "READY $dst $tag"
}
finally { if ($img) { Dismount-DiskImage -ImagePath $Iso -ErrorAction SilentlyContinue | Out-Null } }