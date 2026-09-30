# driver-check.ps1 with NVIDIA tools, downloads, signatures, installers and Windows Update (COM) mocked.
. "$PSScriptRoot\..\lib.ps1"
$d = "$Work\dc"; New-Item $d -ItemType Directory -Force | Out-Null
Copy-Item "$Src\driver-check.ps1" $d; '' | Set-Content "$d\game-check.ps1"
$mocked = 'nvidia-smi', 'Invoke-WebRequest', 'Get-AuthenticodeSignature', 'Start-Process', 'New-Object', 'Get-CimInstance', 'Checkpoint-Computer', 'Get-ComputerRestorePoint', 'Set-ItemProperty', 'Remove-ItemProperty'
if (-not (Test-Tripwire "$d\driver-check.ps1" $mocked)) { Finish }
Import-MockTargets $mocked   # load their Windows modules BEFORE defining the mocks (see lib.ps1)
$la = "$Work\la"; $rec = "$la\NVIDIA Corporation\NVIDIA app\NvBackend"; New-Item $rec -ItemType Directory -Force | Out-Null

function Reset-D {
    $global:DC = @{ Gpu = 'NVIDIA GeForce RTX 9090'; Installed = '617.14'; Sig = 'Valid'; Signer = 'CN=NVIDIA Corporation, O=NVIDIA Corporation'; ExitCode = 0; Updates = @(); History = @(); Results = @{}; Reboot = $false; Rps = 0; Cpu = 'Intel Core TEST'; AmdHave = '1.0'; AmdPage = '' }
    $global:DCcalls = New-Object System.Collections.Generic.List[string]
}
function Rec($updates, [int]$ageDays = 0) { @{ checkTime = (Get-Date).ToUniversalTime().AddDays(-$ageDays).ToString('o'); updates = $updates } | ConvertTo-Json -Depth 4 | Set-Content "$rec\DriverRecommendations.dat" }
function Drv($v, [switch]$Beta, $type = 0) { @{ version = $v; isBeta = [bool]$Beta; driverType = $type; downloadURL = "https://example.invalid/$v-desktop-win11-64bit-international-dch-whql.exe" } }
function Get-CimInstance { if ("$args" -match 'Win32_VideoController') { return [pscustomobject]@{ Name = $DC.Gpu } }; if ("$args" -match 'Win32_Processor') { return [pscustomobject]@{ Name = $DC.Cpu } }; CimCmdlets\Get-CimInstance @args }
function nvidia-smi { if ($DC.Installed) { $DC.Installed } }
function Invoke-WebRequest { param($Uri, $OutFile, [switch]$UseBasicParsing, $UserAgent, $Headers, $TimeoutSec) if (-not $OutFile) { return [pscustomobject]@{ Content = $DC.AmdPage } }; $global:DCcalls.Add("download $Uri"); 'fake installer' | Set-Content $OutFile }
function Get-AuthenticodeSignature { param($FilePath) [pscustomobject]@{ Status = $DC.Sig; SignerCertificate = [pscustomobject]@{ Subject = $DC.Signer } } }
function Start-Process { param($FilePath, $ArgumentList, [switch]$Wait, [switch]$PassThru) $global:DCcalls.Add("run $(Split-Path $FilePath -Leaf) $ArgumentList"); [pscustomobject]@{ ExitCode = $DC.ExitCode } }
# Windows Update COM objects
function Checkpoint-Computer { $global:DCcalls.Add('restore point'); $global:DC.Rps++ }
function Get-ComputerRestorePoint { if ($global:DC.Rps) { 1..$global:DC.Rps } }   # (1..0 counts down to 2 items)
function Set-ItemProperty { $global:DCcalls.Add("set $($args[1]) $($args[2])") }
function Remove-ItemProperty { $global:DCcalls.Add("remove $($args[1])") }
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
function DC { $u = $env:LOCALAPPDATA; $env:LOCALAPPDATA = $la; try { @(& "$d\driver-check.ps1" -TestAmdChipset $DC.AmdHave -TestAmdGpu $DC.AmdGpu) } finally { $env:LOCALAPPDATA = $u } }

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
Check '... nothing to install: no restore point' (-not ($DCcalls -contains 'restore point')) ($DCcalls -join ', ')
Reset-D; Rec @((Drv '617.14'))
$DC.Updates = @((New-WUUpdate 'Realtek - Net - 10.70'), (New-WUUpdate 'AMD - Display - 32.0'), (New-WUUpdate 'Logitech - HID - 1.2'))
$DC.History = @([pscustomobject]@{ Title = 'AMD - Display - 32.0'; ResultCode = 4 })
$DC.Results = @{ 'Realtek - Net - 10.70' = 2; 'Logitech - HID - 1.2' = 4 }; $DC.Reboot = $true
$o = DC
Check 'a driver that failed before is hidden, not retried forever' (($o -match "'AMD - Display - 32.0' failed before - hidden") -and $DC.Updates[1].IsHidden) ($o -join ' / ')
Check 'the rest are installed: success and failure reported per driver' (($o -contains 'Driver: Realtek - Net - 10.70 - installed') -and ($o -contains 'Driver: Logitech - HID - 1.2 - FAILED') -and -not ($o -match 'Driver: AMD - Display - 32.0 -')) ($o -join ' / ')
$calls = @($DCcalls)
Check 'a restore point is made right before the installs (one per run), and said' ((@($calls -eq 'restore point').Count -eq 1) -and ([array]::IndexOf($calls, 'restore point') -lt [array]::IndexOf($calls, 'install updates')) -and ($o -contains 'Restore point created before the driver install')) ($calls -join ', ')
Check '... Windows'' one-per-day limit lifted for it and put back' (($calls -contains 'set SystemRestorePointCreationFrequency 0') -and (($calls -match '^(remove|set) SystemRestorePointCreationFrequency').Count -eq 2)) ($calls -join ', ')Check 'licence terms accepted for them' ($DC.Updates[0].EulaAccepted -and $DC.Updates[2].EulaAccepted) ''
Check 'restart needed: REBOOT line (finishes at the owner''s next restart)' ([bool]($o -match '^REBOOT required to finish driver installs')) ''
Reset-D; Rec @((Drv '617.14'))
$bad = New-WUUpdate 'Realtek - Net - 10.71'; $bad | Add-Member DriverProvider 'Realtek'; $bad | Add-Member DriverVerDate ([datetime]'2026-09-01')
$other = New-WUUpdate 'Realtek - Net - 10.72'; $other | Add-Member DriverProvider 'Realtek'; $other | Add-Member DriverVerDate ([datetime]'2026-09-20')
$DC.Updates = @($bad, $other); $DC.Results = @{ 'Realtek - Net - 10.72' = 2 }
'Realtek|2026-09-01|10.71.0.0|rt640x64.inf' | Set-Content "$d\driver-blocklist.txt"
$o = DC; [IO.File]::Delete("$d\driver-blocklist.txt")
Check 'a driver rolled back after a blue screen (driver-blocklist.txt) is hidden, not installed again' ($bad.IsHidden -and ($o -match "'Realtek - Net - 10.71' was rolled back after a blue screen - hidden") -and -not ($o -match 'Driver: Realtek - Net - 10.71 -')) ($o -join ' / ')
Check '... a different version from the same maker still installs' ((-not $other.IsHidden) -and ($o -contains 'Driver: Realtek - Net - 10.72 - installed')) ($o -join ' / ')
Section 'a game is running: installs wait (moved here from game-aware: mocked, so it also runs without an NVIDIA card)'
'"TestGame"' | Set-Content "$d\game-check.ps1"
Reset-D; Rec @((Drv '620.36')); $DC.Updates = @((New-WUUpdate 'Realtek - Net - 10.70')); $o = DC
Check 'newer NVIDIA driver: install held while the game runs' ([bool]($o -match 'NVIDIA: 620.36 is available - install held while TestGame')) ($o -join ' / ')
Check 'pending Windows Update drivers: held too' ([bool]($o -match 'Other drivers: 1 update\(s\) available - held while TestGame')) ($o -join ' / ')
Check '... nothing downloaded or installed, no error line' (-not ($DCcalls -match 'download|install|^run ') -and -not ($o -match 'check failed|updating|signature')) (($DCcalls + $o) -join ' / ')
'' | Set-Content "$d\game-check.ps1"

Section 'AMD chipset (Ryzen)'
$amd = '<a href="https://drivers.amd.com/drivers/AMD_Chipset_Software_8.08.12.551.exe">'
Reset-D; $DC.Gpu = 'AMD Radeon RX TEST'; $DC.Cpu = 'AMD Ryzen 5 TEST'; $DC.AmdPage = $amd; $DC.AmdHave = '8.08.12.551'; $o = DC
Check 'up to date: nothing downloaded, nothing said' (-not ($o -match 'AMD chipset') -and -not ($DCcalls -match 'AMD_Chipset')) ($o -join ' / ')
Reset-D; $DC.Gpu = 'AMD Radeon RX TEST'; $DC.Cpu = 'AMD Ryzen 5 TEST'; $DC.AmdPage = $amd; $DC.AmdHave = '7.01.08.129'; $DC.Signer = 'CN=Advanced Micro Devices, O=Advanced Micro Devices, S=California, C=US'; $o = DC
Check "newer on AMD's site: downloaded, restore point first, installed silently, said" (($DCcalls -match 'download https://drivers\.amd\.com/drivers/AMD_Chipset_Software_8\.08\.12\.551\.exe') -and ($DCcalls -contains 'restore point') -and ($DCcalls -match '^run AMD_Chipset_Software_8\.08\.12\.551\.exe /S$') -and ($o -match '^AMD chipset: installed 8\.08\.12\.551 \(was 7\.01\.08\.129\) - REBOOT')) (($DCcalls + $o) -join ' / ')
Reset-D; $DC.Gpu = 'AMD Radeon RX TEST'; $DC.Cpu = 'AMD Ryzen 5 TEST'; $DC.AmdPage = $amd; $DC.AmdHave = '7.01.08.129'; $DC.Signer = 'CN=Somebody Else'; $o = DC
Check "... a download without AMD's signature: never run" (-not ($DCcalls -match '^run AMD') -and ($o -match "did not carry AMD's signature")) (($DCcalls + $o) -join ' / ')
Reset-D; $DC.Gpu = 'AMD Radeon RX TEST'; $DC.Cpu = 'AMD Ryzen 5 TEST'; $DC.AmdPage = 'a changed page'; $o = DC
Check "... AMD's page changed (no link found): nothing done, no error" (-not ($o -match 'AMD chipset') -and -not ($DCcalls -match 'AMD_Chipset')) ($o -join ' / ')

Section 'AMD Radeon: the newest WHQL Adrenalin driver from AMD'
$rp = '<a href="https://drivers.amd.com/drivers/whql-amd-software-adrenalin-edition-26.8.1-win11-b.exe">x</a> <a href="https://drivers.amd.com/drivers/whql-amd-software-adrenalin-edition-26.9.2-win11-c.exe">y</a> <a href="https://drivers.amd.com/drivers/installer/26.10/whql/amd-software-adrenalin-edition-26.8.1-minimalsetup-260818_web.exe">z</a>'
function Radeon([hashtable]$o = @{}) { Reset-D; $DC.Gpu = 'AMD Radeon RX 7800 XT'; $DC.Cpu = 'Intel TEST'; $DC.AmdPage = $rp; $DC.Signer = 'CN=Advanced Micro Devices, Inc., O=Advanced Micro Devices, Inc.'; foreach ($k in $o.Keys) { $DC[$k] = $o[$k] }; DC }
[IO.File]::Delete("$d\gpu-hold.txt")
$o = Radeon @{ AmdGpu = '26.8.1.260818' }
Check 'an older Adrenalin: the newest WHQL package downloaded, AMD-signed, a restore point, installed silently' (($DCcalls -match 'download .*adrenalin-edition-26\.9\.2-win11-c\.exe') -and ($DCcalls -contains 'restore point') -and ($DCcalls -match '^run whql-amd-software-adrenalin-edition-26\.9\.2-win11-c\.exe -install$') -and ($o -match 'AMD Radeon: installed 26\.9\.2')) (($DCcalls + $o) -join ' / ')
$o = Radeon @{ AmdGpu = '26.9.2.260901' }
Check '... already the newest: nothing downloaded, said' (-not ($DCcalls -match 'adrenalin') -and ($o -match 'AMD Radeon: 26\.9\.2\.260901 is up to date')) (($DCcalls + $o) -join ' / ')
$o = Radeon @{ AmdGpu = 'none' }
Check '... no Adrenalin yet: installed' ($DCcalls -match '^run whql-amd-software-adrenalin-edition-26\.9\.2') (($DCcalls + $o) -join ' / ')
$o = Radeon @{ AmdGpu = '26.8.1'; Signer = 'CN=Somebody Else' }
Check "... not AMD's signature: never run" (-not ($DCcalls -match '^run whql') -and ($o -match "did not carry AMD's signature")) (($DCcalls + $o) -join ' / ')
'26.9.2' | Set-Content "$d\gpu-hold.txt"
$o = Radeon @{ AmdGpu = '26.8.1' }
Check '... went back from 26.9.2 (the app''s rollback): that version is skipped until a newer one' (-not ($DCcalls -match 'adrenalin') -and ($o -match 'up to date')) (($DCcalls + $o) -join ' / ')
[IO.File]::Delete("$d\gpu-hold.txt")
$o = Radeon @{ AmdGpu = '26.8.1'; Gpu = 'AMD Radeon RX 580' }
Check 'an old Radeon (RX 580, a different driver line): left to Windows Update' (-not ($DCcalls -match 'adrenalin')) (($DCcalls + $o) -join ' / ')
Finish
