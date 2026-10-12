# autoruns-check.ps1: the weekly startup audit (Sysinternals Autoruns) - first run records, then only new or changed
# entries are said; unsigned ones from user-writable folders are a WARNING. Made-up scans (-Csv); the download mocked.
. "$PSScriptRoot\..\lib.ps1"
$ac = "$Src\autoruns-check.ps1"
if (-not (Test-Path $ac)) { Skip 'autoruns-check' 'not installed here'; Finish }
$mocked = 'Invoke-WebRequest', 'Expand-Archive', 'Get-AuthenticodeSignature', 'Start-Process', 'Stop-Process'
if (-not (Test-Tripwire $ac $mocked @('Get-Random', 'Import-Csv'))) { Finish }   # (both only read)
Import-MockTargets $mocked   # load their Windows modules BEFORE defining the mocks (see lib.ps1)
$global:AR = @{}
function Invoke-WebRequest { param($Uri, $OutFile, [switch]$UseBasicParsing, $TimeoutSec, $ErrorAction) $global:AR.Calls += 'download'; if ($global:AR.Offline) { throw 'The remote name could not be resolved' }; 'zip' | Set-Content $OutFile }
function Expand-Archive { param($Path, $DestinationPath, [switch]$Force, $ErrorAction) New-Item $DestinationPath -ItemType Directory -Force | Out-Null; 'exe' | Set-Content "$DestinationPath\autorunsc64.exe"; 'exe' | Set-Content "$DestinationPath\autorunsc64a.exe" }
function Get-AuthenticodeSignature { param($FilePath) [pscustomobject]@{ Status = $(if ($global:AR.BadSig) { 'NotSigned' } else { 'Valid' }); SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' } } }
function Start-Process { $global:AR.Calls += 'run'; throw 'not in tests' }
function Stop-Process { }
if (-not (Assert-Mocks $mocked)) { Finish }

$D = "$Work\cl"; New-Item $D -ItemType Directory -Force | Out-Null
$hdr = 'Time,Entry Location,Entry,Enabled,Category,Profile,Description,Signer,Company,Image Path,Version,Launch String,MD5,SHA-1'
function Row($cat, $loc, $entry, $signer, $company, $path, $sha = 'AA', $enabled = 'enabled') { "1/1/2026,`"$loc`",`"$entry`",$enabled,$cat,System-wide,,`"$signer`",`"$company`",`"$path`",1.0,,,$sha" }
$known = @((Row 'Explorer' 'HKLM\Software\Classes\*\ShellEx\ContextMenuHandlers' '7-Zip' '(Not verified) Igor Pavlov' 'Igor Pavlov' 'C:\Program Files\7-Zip\7-zip.dll'),
    (Row 'Drivers' 'HKLM\System\CurrentControlSet\Services' 'logitech' '(Verified) Logitech' 'Logitech' 'C:\Windows\System32\drivers\lgbus.sys' 'L1'),
    (Row 'Logon' 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'Discord' '(Verified) Discord Inc.' 'Discord' 'C:\Users\x\AppData\Local\Discord\Update.exe'),
    (Row 'Known DLLs' 'HKLM\System\CurrentControlSet\Control\Session Manager\KnownDlls' 'wow64' '' '' 'File not found: C:\WINDOWS\Syswow64\wow64.dll'))
function Scan([string[]]$rows) { $f = "$Work\scan.csv"; @($hdr) + $rows | Set-Content $f -Encoding UTF8; $f }
function Audit-Scan([string[]]$rows) { @(& $ac -Csv (Scan $rows) -Dir $D -Force) }

Section 'first run: only records'
$o = Audit-Scan $known
Check 'the first scan records what''s there and says only that' (@($o).Count -eq 1 -and @($o)[0] -match '^Startup audit: 2 auto-start entries recorded') ($o -join ' / ')
Check '... Run keys (health-check watches them) and leftovers whose file is gone are left out' (-not ((Get-Content "$D\autoruns-baseline.json" -Raw) -match 'Discord|wow64')) ''
$o = Audit-Scan $known
Check 'nothing new: a plain line, no reminder' (@($o).Count -eq 1 -and @($o)[0] -match '^Startup audit: nothing new \(2 entries checked\)') ($o -join ' / ')

Section 'new and changed entries'
$o = Audit-Scan ($known + (Row 'Services' 'HKLM\System\CurrentControlSet\Services' 'SysHelper' '(Not verified)' '' 'C:\Users\x\AppData\Roaming\SysHelper\svc.exe'))
Check 'a new unsigned service running from AppData: a WARNING naming it' ($o -match '^WARNING: startup audit - auto-start entries not signed by their maker: SysHelper \(Services, C:\\Users\\x\\AppData') ($o -join ' / ')
$o = Audit-Scan ($known + (Row 'Drivers' 'HKLM\System\CurrentControlSet\Services' 'rgbfx' '(Not verified) RGB Co' 'RGB Co' 'C:\Windows\System32\drivers\rgbfx.sys') + (Row 'Codecs' 'HKLM\Software\Classes\CLSID' 'GoodCodec' '(Verified) Codec Corp' 'Codec Corp' 'C:\Program Files\Codec\c.dll'))
Check 'a new unsigned driver elsewhere: a reminder (fine if just installed)' ($o -match '^Reminder: startup audit - new auto-start entries not signed by their maker: rgbfx') ($o -join ' / ')
Check '... a new signed one: a plain line with its maker' ($o -match '^Startup audit: new auto-start entries \(signed\): GoodCodec \(Codec Corp\)' -and -not ($o -match '^WARNING')) ($o -join ' / ')
$changed = @($known[0], (Row 'Drivers' 'HKLM\System\CurrentControlSet\Services' 'logitech' '(Not verified)' 'Logitech' 'C:\Windows\System32\drivers\lgbus.sys' 'L2'), $known[2], $known[3])
$o = Audit-Scan $changed
Check 'a signed entry whose file changed and is no longer signed: a WARNING (tampering)' ($o -match '^WARNING: .*logitech .* it was signed by its maker before and has been changed') ($o -join ' / ')
$o = Audit-Scan ($changed + (Row 'Services' 'HKLM\System\CurrentControlSet\Services' 'OffOne' '(Not verified)' '' 'C:\Users\x\AppData\Roaming\o.exe' 'Z' 'disabled'))
Check 'a disabled entry is not news' (-not ($o -match 'OffOne')) ($o -join ' / ')

Section 'weekly, and fetching Autoruns'
$global:AR = @{ Calls = @() }; $o = @(& $ac -Csv (Scan $known) -Dir $D)
Check 'ran less than 6 days ago: nothing done' (-not $o) ($o -join ' / ')
$D2 = "$Work\cl2"; New-Item $D2 -ItemType Directory -Force | Out-Null
$global:AR = @{ Calls = @(); Offline = $true }; $o = @(& $ac -Dir $D2 -Force)
Check 'no internet: says it, tries again next week, nothing else' (($o -join ' ') -match '^Startup audit: couldn''t download Autoruns' -and ($AR.Calls -notcontains 'run')) ($o -join ' / ')
$global:AR = @{ Calls = @(); BadSig = $true }; $o = @(& $ac -Dir $D2 -Force)
Check 'a download not signed by Microsoft: never used' (($o -join ' ') -match 'isn''t signed by Microsoft - not used' -and ($AR.Calls -notcontains 'run') -and -not (Test-Path "$D2\tools\autoruns\autorunsc64.exe")) ($o -join ' / ')
Finish
