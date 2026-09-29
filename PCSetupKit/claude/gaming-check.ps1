# Gaming checks at every check (run by health-check.ps1) - fixed where software can, said where only the owner can:
# - AMD dual-CCD X3D CPUs (Ryzen 9 7900X3D/7950X3D/9900X3D/9950X3D): the Xbox Game Bar and AMD's 3D V-Cache
#   Performance Optimizer service must be there, or games land on the wrong cores (much lower frame rate).
#   Game Bar comes back by itself; the service is started; a missing AMD chipset driver is a Reminder.
# - Resizable BAR off (NVIDIA: a 256 MB BAR1 window) - a BIOS setting worth a few % in many games: Reminder
# - Two graphics chips (gaming laptops): every game set to the fast one ("High performance"), never over the owner's choice
# - Steam games on a hard drive while the SSD has room: Reminder (slow loading, stutter)
# - The hypervisor running (WSL, virtual machines, Windows Sandbox): costs some gaming performance - Reminder naming
#   what turned it on (not while it's already set to be off at the next restart)
# - Optional (kit-options.txt defenderexclusions=on, the app's Settings): Microsoft Defender skips the game library
#   folders - less stutter while games load and compile shaders; a small security trade-off, so off by default.
#   Turned off again: the exclusions it added are removed. State: gaming-state.json.
# Test overrides: -Test (a hashtable of what would be read: Cpu, GameBar, VCacheSvc, Bar1MiB, Libraries, Hypervisor,
# HvOffNext, HvFeatures, Option, Excluded, Gpus, GameExes, GpuPrefs) with -Do (a scriptblock getting the actions instead of doing them), -State.
param([hashtable]$Test, [scriptblock]$Do, [string]$State = "$PSScriptRoot\gaming-state.json", [string]$Options = "$PSScriptRoot\kit-options.txt")
$ErrorActionPreference = 'SilentlyContinue'
$T = $Test
function Act([string]$What, [scriptblock]$Real) { if ($Do) { & $Do $What } else { & $Real } }
$st = try { Get-Content $State -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { [pscustomobject]@{} }
if (-not ($st.PSObject.Properties.Name -contains 'excluded')) { $st | Add-Member excluded @() }

# --- AMD dual-CCD X3D ---
$cpu = if ($T) { $T.Cpu } else { "$((Get-CimInstance Win32_Processor | Select-Object -First 1).Name)".Trim() }
if ($cpu -match 'Ryzen 9 \d{4}X3D') {
    $bar = if ($T) { $T.GameBar } else { [bool](Get-AppxPackage Microsoft.XboxGamingOverlay) }
    if (-not $bar) {
        Act 'install Game Bar' { $null = winget install --id 9NZKPSTSNW4P --source msstore --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 }
        $bar = if ($T) { $T.GameBarAfter } else { [bool](Get-AppxPackage Microsoft.XboxGamingOverlay) }
        if ($bar) { "Gaming: reinstalled the Xbox Game Bar - the $cpu needs it to put games on its V-Cache cores" }
        else { "Reminder: the $cpu needs the Xbox Game Bar to put games on its fast V-Cache cores, and it's missing - install `"Xbox Game Bar`" from the Microsoft Store" }
    }
    $svc = if ($T) { $T.VCacheSvc } else { $s = Get-Service amd3dvcacheSvc; if ($s) { "$($s.Status)|$($s.StartType)" } }
    if (-not $svc) { "Reminder: the $cpu needs AMD's chipset driver (it brings the 3D V-Cache Performance Optimizer that puts games on the right cores) - get it from amd.com/en/support (Chipsets > your motherboard's chipset)" }
    elseif ($svc -notmatch '^Running\|Automatic$') {
        Act 'start V-Cache service' { Set-Service amd3dvcacheSvc -StartupType Automatic; Start-Service amd3dvcacheSvc }
        "Gaming: started AMD's 3D V-Cache Performance Optimizer (it puts games on the $cpu's V-Cache cores)"
    }
}

# --- Resizable BAR (NVIDIA): BAR1 is the whole graphics memory when it's on, 256 MB when it's off ---
$bar1 = if ($T) { $T.Bar1MiB } else {
    $q = @(& nvidia-smi -q -d MEMORY 2>$null); $i = [array]::FindIndex($q, [Predicate[object]] { param($l) "$l" -match 'BAR1 Memory Usage' })
    if ($i -ge 0 -and "$($q[$i + 1])" -match 'Total\s*:\s*(\d+)\s*MiB') { [int]$Matches[1] } }
if ($bar1 -and $bar1 -le 256) { 'Reminder: Resizable BAR is off - in the BIOS turn on "Above 4G Decoding" and "Re-Size BAR Support" (often a few % more frame rate; the graphics card then sees all of its memory at once)' }

# --- games on a hard drive (Steam's libraries) ---
$libs = if ($T) { $T.Libraries } else {
    $sp = "$((Get-ItemProperty 'HKCU:\Software\Valve\Steam').SteamPath)" -replace '/', '\'
    $vdf = "$sp\steamapps\libraryfolders.vdf"; if (-not (Test-Path $vdf)) { $vdf = "$sp\config\libraryfolders.vdf" }
    foreach ($m in Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"') {
        $p = $m.Matches[0].Groups[1].Value -replace '\\\\', '\'
        $games = @(Get-ChildItem "$p\steamapps\common" -Directory)
        if (-not $games) { continue }
        $disk = Get-Partition -DriveLetter $p.Substring(0, 1) | Get-Disk | ForEach-Object { Get-PhysicalDisk -DeviceNumber $_.Number }
        [pscustomobject]@{ Path = $p; Games = $games.Count; Hdd = "$($disk.MediaType)" -eq 'HDD'; SsdFreeGB = [int](((Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter -and ((Get-Partition -DriveLetter $_.DriveLetter | Get-Disk | ForEach-Object { Get-PhysicalDisk -DeviceNumber $_.Number }).MediaType -eq 'SSD') } | Measure-Object SizeRemaining -Maximum).Maximum) / 1GB) }
    }
}
foreach ($l in @($libs) | Where-Object { $_.Hdd -and $_.SsdFreeGB -ge 100 }) {
    "Reminder: $($l.Games) Steam game(s) are on a hard drive ($($l.Path)) while the SSD has $($l.SsdFreeGB) GB free - on the SSD they load much faster and stutter less: Steam > Settings > Storage, pick the games, Move"
}

# --- two graphics chips (most gaming laptops: the built-in one and the fast one): every game on the fast one ---
# Windows picks the chip per program and sometimes picks the built-in one (much lower frame rate). The same setting as
# Settings > System > Display > Graphics > "High performance" (GpuPreference=2), for each game in the Steam libraries
# and the usual game folders; a choice the owner made there for a program is never changed. State: gaming-state.json
# "gpuPref" (the uninstaller takes them out again).
$gpus = @(if ($T) { $T.Gpus } else { Get-CimInstance Win32_VideoController | Where-Object { $_.PNPDeviceID -match '^PCI\\' -and $_.Name -notmatch 'Microsoft|Remote|Virtual|Parsec' } | ForEach-Object Name })
$fast = $gpus | Where-Object { $_ -match 'NVIDIA|Radeon RX|Radeon Pro|Arc A|Arc B' } | Select-Object -First 1
if ($gpus.Count -ge 2 -and $fast) {
    if (-not ($st.PSObject.Properties.Name -contains 'gpuPref')) { $st | Add-Member gpuPref @() }
    $exes = @(if ($T) { $T.GameExes } else {
            $roots = @(foreach ($l in @($libs)) { "$($l.Path)\steamapps\common" }) + @(foreach ($d in (Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }).DriveLetter) { "$d`:\Program Files\Epic Games", "$d`:\Epic Games", "$d`:\XboxGames", "$d`:\Games" })
            foreach ($r in $roots | Where-Object { Test-Path $_ }) {
                Get-ChildItem $r -Filter *.exe -Recurse -Depth 3 -File | Where-Object { $_.Name -notmatch 'crash|setup|unins|redist|prereq|report|helper|install|dotnet|vcredist|dxwebsetup|easyanticheat_setup|launcherpatcher' } | ForEach-Object FullName
            }
        })
    $pref = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    $have = if ($T) { $T.GpuPrefs } else { $k = Get-ItemProperty $pref; $h = @{}; if ($k) { foreach ($p in $k.PSObject.Properties | Where-Object Name -notlike 'PS*') { $h[$p.Name] = "$($p.Value)" } }; $h }
    $new = @($exes | Where-Object { -not $have.ContainsKey($_) })
    foreach ($e in $new) { Act "gpu $e" { if (-not (Test-Path $pref)) { New-Item $pref -Force | Out-Null }; New-ItemProperty $pref -Name $e -Value 'GpuPreference=2;' -PropertyType String -Force | Out-Null } }
    if ($new) {
        $st.gpuPref = @(@($st.gpuPref) + $new | Select-Object -Unique); try { $st | ConvertTo-Json -Depth 3 | Set-Content $State -Encoding UTF8 } catch { }
        "Gaming: $($new.Count) game(s) set to run on the $fast (the fast graphics chip), not the built-in one"
    }
}

# --- the hypervisor (WSL, virtual machines, Sandbox): a few % of gaming performance ---
$hv = if ($T) { $T.Hypervisor } else { (Get-CimInstance Win32_ComputerSystem).HypervisorPresent }
$offNext = if ($T) { $T.HvOffNext } else { "$(bcdedit /enum '{current}' 2>$null)" -match 'hypervisorlaunchtype\s+Off' }
if ($hv -and -not $offNext -and -not (Test-Path "$PSScriptRoot\sandbox-features-before.json")) {   # (not the kit's own Sandbox test)
    $names = @{ 'Microsoft-Hyper-V-All' = 'Hyper-V'; 'VirtualMachinePlatform' = 'WSL / Virtual Machine Platform'; 'HypervisorPlatform' = 'Windows Hypervisor Platform (emulators, VMs)'; 'Containers-DisposableClientVM' = 'Windows Sandbox' }
    $on = if ($T) { $T.HvFeatures } else { @($names.Keys | Where-Object { (Get-WindowsOptionalFeature -Online -FeatureName $_).State -eq 'Enabled' }) }
    $what = @($on | ForEach-Object { $names[$_] }) -join ', '
    "Reminder: the Windows hypervisor is running$(if ($what) { " (for $what)" }) - it costs a few % in games. If you don't use it: Start > `"Turn Windows features on or off`", untick it, restart"
}

# --- optional: Defender skips the game libraries ---
$opt = if ($T) { $T.Option } else { $l = @(Get-Content $Options) -match '^\s*defenderexclusions\s*=' | Select-Object -First 1; if ($l) { ($l -split '=', 2)[1].Trim() } }
$want = @(if ($opt -eq 'on') {
        foreach ($l in @($libs)) { "$($l.Path)\steamapps" }
        foreach ($d in (Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }).DriveLetter) { foreach ($f in "$d`:\Program Files\Epic Games", "$d`:\Epic Games", "$d`:\XboxGames", "$d`:\Games") { if (-not $T -and (Test-Path $f)) { $f } } }
    })
$had = @($st.excluded)
$add = @($want | Where-Object { $_ -notin $had }); $drop = @($had | Where-Object { $_ -notin $want })
foreach ($p in $add) { Act "exclude $p" { Add-MpPreference -ExclusionPath $p } }
foreach ($p in $drop) { Act "unexclude $p" { Remove-MpPreference -ExclusionPath $p } }
if ($add) { "Gaming: Microsoft Defender now skips the game folders ($($add -join ', ')) - less stutter while games load" }
if ($drop) { "Gaming: Defender scans the game folders again ($($drop -join ', '))" }
if ($add -or $drop) { $st.excluded = @($want); try { $st | ConvertTo-Json -Depth 3 | Set-Content $State -Encoding UTF8 } catch { } }
