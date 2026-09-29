# bios-info.ps1: the exact BIOS page and the maker's own update steps for each kind of board or prebuilt PC.
# Made-up boards; nothing is read from or changed on this PC.
. "$PSScriptRoot\..\lib.ps1"
$bi = "$Src\bios-info.ps1"
if (-not (Test-Path $bi)) { Skip 'bios-info' 'not installed here'; Finish }
function BI($board, $cpu = 'AMD Ryzen 5 TEST', $serial = 'ABC1234') { & $bi -Board $board -Bios '1.10|2024-01-02' -Serial $serial -Cpu $cpu }

$o = BI 'ASUSTeK COMPUTER INC.|ROG STRIX B650-A GAMING WIFI'
Check 'ASUS: its own BIOS page, EZ Flash' ($o.Url -eq 'https://www.asus.com/supportonly/ROG%20STRIX%20B650-A%20GAMING%20WIFI/helpdesk_bios/' -and $o.Tool -eq 'EZ Flash' -and $o.Steps -match 'EZ Flash 3') "$($o.Url)"
$o = BI 'ASRock|X670E Test ITX'
Check 'ASRock with an AMD CPU: the AMD board page, Instant Flash' ($o.Url -eq 'https://www.asrock.com/mb/AMD/X670E%20Test%20ITX/index.asp#BIOS' -and $o.Tool -eq 'Instant Flash') "$($o.Url)"
$o = BI 'ASRock|Z790 Pro RS' 'Intel(R) Core(TM) i7-14700K'
Check '... with an Intel CPU: the Intel board page' ($o.Url -eq 'https://www.asrock.com/mb/Intel/Z790%20Pro%20RS/index.asp#BIOS') "$($o.Url)"
$o = BI 'Micro-Star International Co., Ltd.|MAG B650 TOMAHAWK WIFI (MS-7D75)'
Check 'MSI: its support page (the model as MSI writes it), M-Flash' ($o.Url -eq 'https://www.msi.com/Motherboard/MAG-B650-TOMAHAWK-WIFI-MS-7D75/support#bios' -and $o.Tool -eq 'M-Flash') "$($o.Url)"
$o = BI 'Gigabyte Technology Co., Ltd.|B650 AORUS ELITE AX'
Check 'Gigabyte: its support page, Q-Flash' ($o.Url -eq 'https://www.gigabyte.com/Motherboard/B650-AORUS-ELITE-AX/support#support-dl-bios' -and $o.Tool -eq 'Q-Flash') "$($o.Url)"
$o = BI 'Dell Inc.|0XYZ12'
Check 'a Dell: its page by service tag, updated from Windows (no USB stick)' ($o.Url -eq 'https://www.dell.com/support/home/product-support/servicetag/ABC1234/drivers' -and $o.Steps -notmatch 'USB stick') "$($o.Url) / $($o.Steps)"
$o = BI 'Dell Inc.|0XYZ12' -serial 'To be filled by O.E.M.'
Check '... without a real service tag: Dell''s support home' ($o.Url -eq 'https://www.dell.com/support/home/') "$($o.Url)"
$o = BI 'LENOVO|LNVNB161216'
Check 'a Lenovo: its page by serial' ($o.Url -eq 'https://pcsupport.lenovo.com/products/ABC1234/downloads') "$($o.Url)"
$o = BI 'Some Maker|X-1'
Check 'an unknown maker: a web search for the board''s BIOS' ($o.Url -match '^https://www\.google\.com/search\?q=Some%20Maker%20X-1%20BIOS%20download$') "$($o.Url)"
$o = BI 'ASRock|X670E Test ITX'
Check 'the steps: what to download (newer than the installed one), the USB stick, never turn it off, EXPO afterwards' ($o.Steps -match 'newer than 1\.10 from 2024-01-02' -and $o.Steps -match 'USB stick' -and $o.Steps -match 'Never turn the PC off' -and $o.Steps -match 'EXPO/XMP') $o.Steps
Check 'never downloads or flashes anything itself' ((Get-Content $bi -Raw) -notmatch 'Invoke-WebRequest|Start-BitsTransfer|Start-Process') ''
Finish
