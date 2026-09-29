# gaming-check.ps1: dual-CCD X3D needs, Resizable BAR, games on a hard drive, the hypervisor, the optional Defender
# exclusions. Made-up readings (-Test); actions go to a recorder (-Do), never to the real PC.
. "$PSScriptRoot\..\lib.ps1"
$gc = "$Src\gaming-check.ps1"
if (-not (Test-Path $gc)) { Skip 'gaming-check' 'not installed here'; Finish }
$st = "$Work\gaming-state.json"
$global:acts = @()
$rec = { param($w) $global:acts += $w }
function Pc([hashtable]$over = @{}) {
    $h = @{ Cpu = 'AMD Ryzen 7 5800X3D 8-Core Processor'; GameBar = $true; VCacheSvc = 'Stopped|Automatic'; Bar1MiB = 16384; Hypervisor = $false; HvOffNext = $false; HvFeatures = @(); Option = $null
        Libraries = @([pscustomobject]@{ Path = 'C:\Steam'; Games = 4; Hdd = $false; SsdFreeGB = 900 }) }
    foreach ($k in $over.Keys) { $h[$k] = $over[$k] }; $h
}
function Invoke-Gaming([hashtable]$t) { $global:acts = @(); @(& $gc -Test $t -Do $rec -State $st) }

Section 'a well set-up PC'
$o = Invoke-Gaming (Pc)
Check 'nothing to say or do' (-not $o -and -not $acts) (($o + $acts) -join ' / ')

Section 'AMD dual-CCD X3D'
$x3d = 'AMD Ryzen 9 7950X3D 16-Core Processor'
$o = Invoke-Gaming (Pc @{ Cpu = $x3d; GameBar = $false; GameBarAfter = $true; VCacheSvc = 'Running|Automatic' })
Check 'Game Bar missing: reinstalled, and said why' (($acts -contains 'install Game Bar') -and "$o" -match 'reinstalled the Xbox Game Bar - the AMD Ryzen 9 7950X3D') ($o -join ' / ')
$o = Invoke-Gaming (Pc @{ Cpu = $x3d; GameBar = $false; GameBarAfter = $false; VCacheSvc = 'Running|Automatic' })
Check '... the reinstall failed (no Store): a Reminder with what to do' ("$o" -match '^Reminder: .+needs the Xbox Game Bar.+Microsoft Store') ($o -join ' / ')
$o = Invoke-Gaming (Pc @{ Cpu = $x3d; VCacheSvc = 'Stopped|Manual' })
Check "V-Cache optimizer service not running: started" (($acts -contains 'start V-Cache service') -and "$o" -match "started AMD's 3D V-Cache Performance Optimizer") ($o -join ' / ')
$o = Invoke-Gaming (Pc @{ Cpu = $x3d; VCacheSvc = $null })
Check 'no V-Cache service at all: the chipset driver is missing - Reminder' ("$o" -match "^Reminder: .+needs AMD's chipset driver") ($o -join ' / ')
$o = Invoke-Gaming (Pc @{ VCacheSvc = $null; GameBar = $false })
Check 'a single-CCD X3D (5800X3D): none of this applies' (-not $o -and -not $acts) ($o -join ' / ')

Section 'Resizable BAR, games on a hard drive, the hypervisor'
$o = Invoke-Gaming (Pc @{ Bar1MiB = 256 })
Check 'Resizable BAR off (256 MB BAR1): the BIOS reminder' ("$o" -match '^Reminder: Resizable BAR is off - in the BIOS') ($o -join ' / ')
$o = Invoke-Gaming (Pc @{ Libraries = @([pscustomobject]@{ Path = 'D:\SteamLibrary'; Games = 12; Hdd = $true; SsdFreeGB = 500 }) })
Check 'Steam games on a hard drive, the SSD has room: Reminder with how to move them' ("$o" -match '^Reminder: 12 Steam game\(s\) are on a hard drive \(D:\\SteamLibrary\) while the SSD has 500 GB free') ($o -join ' / ')
$o = Invoke-Gaming (Pc @{ Libraries = @([pscustomobject]@{ Path = 'D:\SteamLibrary'; Games = 12; Hdd = $true; SsdFreeGB = 40 }) })
Check '... the SSD nearly full: not said (nowhere to move them)' (-not $o) ($o -join ' / ')
$o = Invoke-Gaming (Pc @{ Hypervisor = $true; HvFeatures = @('VirtualMachinePlatform') })
Check 'the hypervisor running: Reminder naming what turned it on' ("$o" -match '^Reminder: the Windows hypervisor is running \(for WSL / Virtual Machine Platform\)') ($o -join ' / ')
$o = Invoke-Gaming (Pc @{ Hypervisor = $true; HvOffNext = $true })
Check '... already set to be off at the next restart: not said' (-not $o) ($o -join ' / ')

Section 'optional: Defender skips the game folders'
Clear-Path $st
$o = Invoke-Gaming (Pc @{ Option = 'on' })
Check 'turned on: the Steam library excluded, and said' (($acts -contains 'exclude C:\Steam\steamapps') -and "$o" -match 'Defender now skips the game folders') ($o -join ' / ')
$o = Invoke-Gaming (Pc @{ Option = 'on' })
Check '... next check: nothing more' (-not $o -and -not $acts) ($o -join ' / ')
$o = Invoke-Gaming (Pc @{ Option = $null })
Check 'turned off again: exactly the exclusions it added are removed' (($acts -join ',') -eq 'unexclude C:\Steam\steamapps' -and "$o" -match 'scans the game folders again') (($o + $acts) -join ' / ')

Section 'two graphics chips (gaming laptops): every game on the fast one'
Clear-Path $st
$g2 = @{ Gpus = @('Intel(R) Iris(R) Xe Graphics', 'NVIDIA GeForce RTX 4060 Laptop GPU'); GameExes = @('C:\Steam\steamapps\common\A\a.exe', 'C:\Steam\steamapps\common\B\b.exe'); GpuPrefs = @{ 'C:\Steam\steamapps\common\B\b.exe' = 'GpuPreference=1;' } }
$o = Invoke-Gaming (Pc $g2)
Check 'a game without a choice: set to High performance, said with the fast chip''s name' (($acts -join ',') -eq 'gpu C:\Steam\steamapps\common\A\a.exe' -and "$o" -match '1 game\(s\) set to run on the NVIDIA GeForce RTX 4060 Laptop GPU') (($o + $acts) -join ' / ')
Check '... a choice the owner made for a game is kept' (-not ($acts -match 'b\.exe')) ($acts -join ',')
Check '... recorded for the uninstaller' (@((Get-Content $st -Raw | ConvertFrom-Json).gpuPref) -contains 'C:\Steam\steamapps\common\A\a.exe') (Get-Content $st -Raw)
$o = Invoke-Gaming (Pc @{ Gpus = @('NVIDIA GeForce RTX 4080'); GameExes = @('C:\x.exe'); GpuPrefs = @{} })
Check 'one graphics card (a desktop): nothing set' (-not $acts -and -not $o) (($o + $acts) -join ' / ')
$o = Invoke-Gaming (Pc @{ Gpus = @('Intel(R) UHD Graphics', 'AMD Radeon(TM) Graphics'); GameExes = @('C:\x.exe'); GpuPrefs = @{} })
Check 'two built-in chips, no fast one: nothing set' (-not $acts -and -not $o) (($o + $acts) -join ' / ')
Finish
