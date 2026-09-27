# driver-check.ps1 with NVIDIA tools, downloads, signatures, installers and Windows Update (COM) mocked.
. "$PSScriptRoot\..\lib.ps1"
$d = "$Work\dc"; New-Item $d -ItemType Directory -Force | Out-Null
Copy-Item "$Src\driver-check.ps1" $d; '' | Set-Content "$d\game-check.ps1"
$mocked = 'nvidia-smi', 'Invoke-WebRequest', 'Get-AuthenticodeSignature', 'Start-Process', 'New-Object', 'Get-CimInstance'
if (-not (Test-Tripwire "$d\driver-check.ps1" $mocked)) { Finish }
Import-MockTargets $mocked   # load their Windows modules BEFORE defining the mocks (see lib.ps1)
$la = "$Work\la"; $rec = "$la\NVIDIA Corporation\NVIDIA app\NvBackend"; New-Item $rec -ItemType Directory -Force | Out-Null

function Reset-D {
    $global:DC = @{ Gpu = 'NVIDIA GeForce RTX 9090'; Installed = '617.14'; Sig = 'Valid'; Signer = 'CN=NVIDIA Corporation, O=NVIDIA Corporation'; ExitCode = 0; Updates = @(); History = @(); Results = @{}; Reboot = $false }
    $global:DCcalls = New-Object System.Collections.Generic.List[string]
}
function Rec($updates, [int]$ageDays = 0) { @{ checkTime = (Get-Date).ToUniversalTime().AddDays(-$ageDays).ToString('o'); updates = $updates } | ConvertTo-Json -Depth 4 | Set-Content "$rec\DriverRecommendations.dat" }
function Drv($v, [switch]$Beta, $type = 0) { @{ version = $v; isBeta = [bool]$Beta; driverType = $type; downloadURL = "https://example.invalid/$v-desktop-win11-64bit-international-dch-whql.exe" } }
function Get-CimInstance { if ("$args" -match 'Win32_VideoController') { return [pscustomobject]@{ Name = $DC.Gpu } }; CimCmdlets\Get-CimInstance @args }
function nvidia-smi { if ($DC.Installed) { $DC.Installed } }
function Invoke-WebRequest { param($Uri, $OutFile, [switch]$UseBasicParsing) $global:DCcalls.Add("download $Uri"); 'fake installer' | Set-Content $OutFile }
function Get-AuthenticodeSignature { param($FilePath) [pscustomobject]@{ Status = $DC.Sig; SignerCertificate = [pscustomobject]@{ Subject = $DC.Signer } } }
function Start-Process { param($FilePath, $ArgumentList, [switch]$Wait, [switch]$PassThru) $global:DCcalls.Add("run $(Split-Path $FilePath -Leaf) $ArgumentList"); [pscustomobject]@{ ExitCode = $DC.ExitCode } }
# Windows Update COM objects
function New-WUUpdate($title) { $u = [pscustomobject]@{ Title = $title; IsHidden = $false; EulaAccepted = $false }; $u | Add-Member ScriptMethod AcceptEula { $this.EulaAccepted = $true }; $u }
function New-Object {
    param([string]$TypeName, [switch]$ComObject, [object[]]$ArgumentList, [hashtable]$Property)
    if (-not $ComObject) { return Microsoft.PowerShell.Utility\New-Object @PSBoundParameters }
    switch ($TypeName) {
        'Microsoft.Update.Session' {
            $s = [pscustomobject]@{}
            $s | Add-Member ScriptMethod CreateUpdateSearcher {
                $q = [pscustomobject]@{}
                $q | Add-Member ScriptMethod Search { param($c) $global:DCcalls.Add('search'); [pscustomobject]@{ Updates = @($global:DC.Updates | Where-Object { -not $_.IsHidden }) } }
                $q | Add-Member ScriptMethod GetTotalHistoryCount { @($global:DC.History).Count }
                $q | Add-Member ScriptMethod QueryHistory { param($a, $b) $global:DC.History }
                $q }
            $s | Add-Member ScriptMethod CreateUpdateDownloader { $o = [pscustomobject]@{ Updates = $null }; $o | Add-Member ScriptMethod Download { $global:DCcalls.Add('download updates') }; $o }
            $s | Add-Member ScriptMethod CreateUpdateInstaller {
                $o = [pscustomobject]@{ Updates = $null }
                $o | Add-Member ScriptMethod Install {
                    $global:DCcalls.Add('install updates'); $coll = $this.Updates
                    $r = [pscustomobject]@{ RebootRequired = $global:DC.Reboot }
                    $r | Add-Member ScriptMethod GetUpdateResult { param($i) [pscustomobject]@{ ResultCode = $global:DC.Results[$coll.Item($i).Title] } }.GetNewClosure()
                    $r }
                $o }
            return $s
        }
        'Microsoft.Update.UpdateColl' {
            $c = [pscustomobject]@{ List = (Microsoft.PowerShell.Utility\New-Object System.Collections.ArrayList) }
            $c | Add-Member ScriptMethod Add { param($u) $this.List.Add($u) }
            $c | Add-Member ScriptMethod Item { param($i) $this.List[$i] }
            $c | Add-Member ScriptProperty Count { $this.List.Count }
            return $c
        }
    }
}
function DC { $u = $env:LOCALAPPDATA; $env:LOCALAPPDATA = $la; try { @(& "$d\driver-check.ps1") } finally { $env:LOCALAPPDATA = $u } }

if (-not (Assert-Mocks $mocked)) { Finish }

Section 'NVIDIA'
Reset-D; $DC.Gpu = 'AMD Radeon RX 9070 XT'; Rec @((Drv '620.36')); $o = DC
Check 'a PC without an NVIDIA card: no NVIDIA line, nothing downloaded' (-not ($o -match 'NVIDIA') -and -not ($DCcalls -match 'download https')) ($o -join ' / ')
Check '... and nothing that would wake /maintain at every login' (-not ($o -match 'WARNING|FAILED|timed out|DOCTOR ISSUES')) ($o -join ' / ')
Reset-D; $DC.Installed = $null; $o = DC
Check 'nvidia-smi not answering: says so' ([bool]($o -match 'NVIDIA: could not read installed driver version')) ($o -join ' / ')
Reset-D; Clear-Path "$rec\DriverRecommendations.dat"; $o = DC
Check 'no NVIDIA app recommendation file: says so, no download' (($o -match 'no NVIDIA app recommendation file') -and -not ($DCcalls -match 'download https')) ($o -join ' / ')
Reset-D; Rec @((Drv '620.00' -Beta), (Drv '621.00' -type 1)); $o = DC
Check 'only beta/Studio drivers offered: nothing installed' (($o -match 'no Game Ready recommendation') -and -not ($DCcalls -match 'download https')) ($o -join ' / ')
Reset-D; Rec @((Drv '617.14')) 5; $o = DC
Check 'up to date, and says when the NVIDIA app last checked' ([bool]($o -match 'NVIDIA: 617.14 is up to date \(NVIDIA app last checked 5 days ago\)')) ($o -join ' / ')
Reset-D; Rec @((Drv '620.36')); $o = DC
Check 'newer Game Ready driver: downloaded, signature checked, installed silently' (($DCcalls -match 'download https.*620.36') -and ($DCcalls -match 'run 620.36.*-s -noreboot -noeula') -and ($o -match 'NVIDIA: installed 620.36')) ($DCcalls -join ', ')
Check '... and the installer file is deleted afterwards' (-not (Get-ChildItem $env:TEMP -Filter '620.36-desktop*.exe' -ErrorAction SilentlyContinue)) ''
Reset-D; Rec @((Drv '620.36')); $DC.Sig = 'HashMismatch'; $o = DC
Check 'download fails the signature check: not installed' (($o -match 'failed signature check - not installing') -and -not ($DCcalls -match '^run ')) ($o -join ' / ')
Reset-D; Rec @((Drv '620.36')); $DC.Signer = 'CN=Evil Corp'; $o = DC
Check 'validly signed but not by NVIDIA: not installed' (($o -match 'failed signature check') -and -not ($DCcalls -match '^run ')) ($o -join ' / ')
Reset-D; Rec @((Drv '620.36')); $DC.ExitCode = 1; $o = DC
Check 'installer error: exit code reported' ([bool]($o -match 'NVIDIA: installer exit code 1')) ($o -join ' / ')
Reset-D; $DC.Installed = '99.99'; Rec @((Drv '100.10')); $o = DC
Check 'versions compared as numbers (100.10 is newer than 99.99)' ([bool]($o -match 'NVIDIA: installed 100.10')) ($o -join ' / ')
Get-ChildItem $env:TEMP -Filter '*-desktop-win11-64bit-international-dch-whql.exe' -ErrorAction SilentlyContinue | ForEach-Object { Clear-Path $_.FullName }

Section 'other drivers (Windows Update)'
Reset-D; Rec @((Drv '617.14')); $o = DC
Check 'none pending: all up to date' ([bool]($o -match 'Other drivers: all up to date')) ($o -join ' / ')
Reset-D; Rec @((Drv '617.14'))
$DC.Updates = @((New-WUUpdate 'Realtek - Net - 10.70'), (New-WUUpdate 'AMD - Display - 32.0'), (New-WUUpdate 'Logitech - HID - 1.2'))
$DC.History = @([pscustomobject]@{ Title = 'AMD - Display - 32.0'; ResultCode = 4 })
$DC.Results = @{ 'Realtek - Net - 10.70' = 2; 'Logitech - HID - 1.2' = 4 }; $DC.Reboot = $true
$o = DC
Check 'a driver that failed before is hidden, not retried forever' (($o -match "'AMD - Display - 32.0' failed before - hidden") -and $DC.Updates[1].IsHidden) ($o -join ' / ')
Check 'the rest are installed: success and failure reported per driver' (($o -contains 'Driver: Realtek - Net - 10.70 - installed') -and ($o -contains 'Driver: Logitech - HID - 1.2 - FAILED') -and -not ($o -match 'Driver: AMD - Display - 32.0 -')) ($o -join ' / ')
Check 'licence terms accepted for them' ($DC.Updates[0].EulaAccepted -and $DC.Updates[2].EulaAccepted) ''
Check 'restart needed: REBOOT line (finishes at the owner''s next restart)' ([bool]($o -match '^REBOOT required to finish driver installs')) ''
Section 'a game is running: installs wait (moved here from game-aware: mocked, so it also runs without an NVIDIA card)'
'"TestGame"' | Set-Content "$d\game-check.ps1"
Reset-D; Rec @((Drv '620.36')); $DC.Updates = @((New-WUUpdate 'Realtek - Net - 10.70')); $o = DC
Check 'newer NVIDIA driver: install held while the game runs' ([bool]($o -match 'NVIDIA: 620.36 is available - install held while TestGame')) ($o -join ' / ')
Check 'pending Windows Update drivers: held too' ([bool]($o -match 'Other drivers: 1 update\(s\) available - held while TestGame')) ($o -join ' / ')
Check '... nothing downloaded or installed, no error line' (-not ($DCcalls -match 'download|install|^run ') -and -not ($o -match 'check failed|updating|signature')) (($DCcalls + $o) -join ' / ')
'' | Set-Content "$d\game-check.ps1"
Finish
