# The BIOS helper: this PC's motherboard, its BIOS version and date, the exact page to get a newer one from, and the
# steps with the maker's own update tool. Used by maint-actions.ps1 (the to-do item when the BIOS is over a year old)
# and the app. It never downloads or flashes anything - a BIOS update is the owner's to start. (Makers' download pages
# are behind bot protection, so the newest version itself isn't looked up: the page shows it next to the date here.)
# Returns one object: Maker, Model, Version, Date, Url, Tool, Steps. -Board 'maker|model', -Bios 'version|yyyy-MM-dd',
# -Serial, -Cpu: tests.
param([string]$Board, [string]$Bios, [string]$Serial, [string]$Cpu)
$ErrorActionPreference = 'SilentlyContinue'
if (-not $Board) { $b = Get-CimInstance Win32_BaseBoard; $Board = "$($b.Manufacturer)|$($b.Product)" }
if (-not $Bios) { $x = Get-CimInstance Win32_BIOS; $Bios = "$($x.SMBIOSBIOSVersion)|$(if ($x.ReleaseDate) { $x.ReleaseDate.ToString('yyyy-MM-dd') })"; if (-not $Serial) { $Serial = "$($x.SerialNumber)".Trim() } }
if (-not $Cpu) { $Cpu = "$((Get-CimInstance Win32_Processor | Select-Object -First 1).Name)" }
$maker, $model = ($Board -split '\|', 2) | ForEach-Object { "$_".Trim() }
$ver, $date = ($Bios -split '\|', 2) | ForEach-Object { "$_".Trim() }
$m = [uri]::EscapeDataString($model); $dash = ($model -replace '[()]', '' -replace '\s+', '-')
$platform = if ($Cpu -match 'AMD|Ryzen') { 'AMD' } else { 'Intel' }
$hasSerial = $Serial -and $Serial -notmatch '^(Default|To be filled|System Serial|0+|None)'
$r = switch -Regex ($maker) {
    'ASUS' { @("https://www.asus.com/supportonly/$m/helpdesk_bios/", 'EZ Flash', 'press Del (or F2) while the logo shows, press F7 for Advanced Mode, then Tool > ASUS EZ Flash 3 Utility') }
    'ASRock' { @("https://www.asrock.com/mb/$platform/$m/index.asp#BIOS", 'Instant Flash', 'press F2 (or Del) while the logo shows, then Tool > Instant Flash') }
    'Micro-Star|MSI' { @("https://www.msi.com/Motherboard/$dash/support#bios", 'M-Flash', 'press Del while the logo shows, then M-Flash (bottom left); the PC restarts into the flash tool') }
    'Gigabyte' { @("https://www.gigabyte.com/Motherboard/$dash/support#support-dl-bios", 'Q-Flash', 'press End (or Del) while the logo shows, then Q-Flash') }
    'Dell' { @($(if ($hasSerial) { "https://www.dell.com/support/home/product-support/servicetag/$Serial/drivers" } else { 'https://www.dell.com/support/home/' }), 'Dell Update', 'run the downloaded BIOS file in Windows - it restarts and updates by itself (keep a laptop plugged in)') }
    'HP|Hewlett' { @('https://support.hp.com/drivers', 'HP BIOS update', "enter the serial number $(if ($hasSerial) { "($Serial) " })on the page, then run the downloaded BIOS file in Windows - it restarts and updates by itself") }
    'Lenovo' { @($(if ($hasSerial) { "https://pcsupport.lenovo.com/products/$Serial/downloads" } else { 'https://pcsupport.lenovo.com/' }), 'Lenovo BIOS update', 'run the downloaded BIOS file in Windows - it restarts and updates by itself (keep a laptop plugged in)') }
    default { @("https://www.google.com/search?q=$([uri]::EscapeDataString("$maker $model BIOS download"))", "the maker's BIOS update tool", "follow the maker's steps on the page") }
}
$inWindows = $maker -match 'Dell|HP|Hewlett|Lenovo'
$steps = if ($inWindows) {
    "1. Open $($r[0]) and download the newest BIOS (newer than $ver from $date). 2. Close your games and apps, $($r[2]). 3. Never turn the PC off while it updates (a few minutes)."
} else {
    "1. Open $($r[0]) and download the newest BIOS (newer than $ver from $date). 2. Unzip it onto a USB stick (FAT32). 3. Restart, $($r[2]), and pick the file. 4. Never turn the PC off while it updates (a few minutes; it restarts by itself). 5. Afterwards the BIOS settings are back to defaults: turn EXPO/XMP (the RAM speed) back on."
}
[pscustomobject]@{ Maker = $maker; Model = $model; Version = $ver; Date = $date; Url = $r[0]; Tool = $r[1]; Steps = $steps }
