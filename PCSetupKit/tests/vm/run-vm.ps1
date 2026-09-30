# LIVE, the kit's own PC only (needs Hyper-V): the boot-from-USB test - the one part the Sandbox can't test.
#   1. a real install stick: make-usb.ps1 onto a 32 GB virtual disk, with THIS kit and the test answer file
#      (tests\vm\autounattend-test.xml: the answers a person gives - English, Windows 11 Pro, the VM's empty disk 0, a
#      local account "Tester")
#   2. a Windows 11 VM (Generation 2, Secure Boot, a virtual TPM, 8 GB, 4 cores, internet via Hyper-V's Default Switch)
#      started from it: Windows Setup installs Windows by itself, the first login runs setup.ps1 from the stick
#   3. inside the VM once setup is done (PowerShell Direct): the install checks (tests\fresh\check-install.ps1 - it waits
#      for the first full maintenance), then the installed kit's own self-test
# A screenshot of the VM's screen every 2 minutes, and of the finished desktop. Results: %USERPROFILE%\.claude\vm-test\
# (screen-*.png, make-usb.txt, check.txt, self-test.txt, result.txt). The VM and its disks are removed afterwards
# (-Keep: left, to look at in Hyper-V Manager). Never restarts this PC.
# -Resume: the VM is already running (the runner itself was stopped): carries on from waiting for setup, results kept
param([int]$Minutes = 150, [switch]$Keep, [switch]$Resume, [string]$Out = "$env:USERPROFILE\.claude\vm-test", [string]$Root = "$env:ProgramData\PCSetupKit\vm-test")
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path (Split-Path $PSScriptRoot))   # the repo root (autounattend.xml, PCSetupKit\)
$name = 'Messiah USB test'
$cred = New-Object Management.Automation.PSCredential ('Tester', (ConvertTo-SecureString 'Messiah-Test-1!' -AsPlainText -Force))
function Say($m) { $l = "$((Get-Date).ToString('T'))  $m"; Add-Content "$Out\run.log" $l; $l }
if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue) -or -not (Get-CimInstance Win32_ComputerSystem).HypervisorPresent) { 'Hyper-V is not running here (it needs a restart after being turned on)'; exit 1 }

# the VM's screen as a picture (Hyper-V's thumbnail: 16-bit RGB565)
Add-Type -AssemblyName System.Drawing
function Save-Screen([string]$File, [int]$W = 1600, [int]$H = 900) {
    try {
        $ns = 'root\virtualization\v2'
        $vm = Get-CimInstance -Namespace $ns -ClassName Msvm_ComputerSystem -Filter "ElementName='$name'"
        $sd = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_VirtualSystemSettingData | Where-Object VirtualSystemType -eq 'Microsoft:Hyper-V:System:Realized'
        $svc = Get-CimInstance -Namespace $ns -ClassName Msvm_VirtualSystemManagementService
        $r = Invoke-CimMethod -InputObject $svc -MethodName GetVirtualSystemThumbnailImage -Arguments @{ TargetSystem = $sd; WidthPixels = [uint16]$W; HeightPixels = [uint16]$H }
        if (-not $r.ImageData) { return }
        $bmp = New-Object Drawing.Bitmap $W, $H, ([Drawing.Imaging.PixelFormat]::Format16bppRgb565)
        $bd = $bmp.LockBits((New-Object Drawing.Rectangle 0, 0, $W, $H), 'WriteOnly', $bmp.PixelFormat)
        [Runtime.InteropServices.Marshal]::Copy([byte[]]$r.ImageData, 0, $bd.Scan0, [Math]::Min($r.ImageData.Length, $bd.Stride * $H))
        $bmp.UnlockBits($bd); $bmp.Save($File, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    } catch { }
}
function Remove-TestVm {
    if (Get-VM -Name $name -ErrorAction SilentlyContinue) { Stop-VM -Name $name -TurnOff -Force -ErrorAction SilentlyContinue; Remove-VM -Name $name -Force }
    foreach ($v in "$Root\usb.vhdx", "$Root\os.vhdx") { if (Test-Path $v) { Dismount-VHD -Path $v -ErrorAction SilentlyContinue; [IO.File]::Delete($v) } }
}

$usb = "$Root\usb.vhdx"
if (-not $Resume) {
if (Test-Path $Out) { [IO.Directory]::Delete($Out, $true) }
New-Item $Out, $Root -ItemType Directory -Force | Out-Null
Say "Boot-from-USB test: kit from $repo"
Remove-TestVm

# 1. the stick
New-VHD -Path $usb -SizeBytes 32GB -Dynamic | Out-Null
$disk = Mount-VHD -Path $usb -Passthru | Get-Disk
Say "Stick: virtual disk $($disk.Number) - make-usb.ps1 builds it (Windows from Microsoft, this kit)..."
$mk = @(& "$repo\PCSetupKit\claude\make-usb.ps1" -Disk $disk.Number -Yes -NoBackup -AllowVirtual -KitFrom $repo -AnswerFile "$PSScriptRoot\autounattend-test.xml" *>&1 | ForEach-Object { "$_" })
$mk | Set-Content "$Out\make-usb.txt"
Dismount-VHD -Path $usb
if (-not ($mk -match '^READY ')) { Say "Stick: make-usb.ps1 did not finish - $(($mk | Select-Object -Last 3) -join ' / ')"; 'FAILED: the stick could not be built' | Set-Content "$Out\result.txt"; if (-not $Keep) { Remove-TestVm }; exit 1 }
Say 'Stick: ready'

# 2. the VM, started from the stick
New-VM -Name $name -Generation 2 -MemoryStartupBytes 8GB -NewVHDPath "$Root\os.vhdx" -NewVHDSizeBytes 80GB -SwitchName 'Default Switch' -Path $Root | Out-Null
Set-VM -Name $name -ProcessorCount 4 -AutomaticCheckpointsEnabled $false -CheckpointType Disabled -StaticMemory
Add-VMHardDiskDrive -VMName $name -Path $usb
Set-VMKeyProtector -VMName $name -NewLocalKeyProtector; Enable-VMTPM -VMName $name
$stick = Get-VMHardDiskDrive -VMName $name | Where-Object Path -eq $usb
Set-VMFirmware -VMName $name -FirstBootDevice $stick -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
Set-VMVideo -VMName $name -HorizontalResolution 1920 -VerticalResolution 1080 -ResolutionType Single -ErrorAction SilentlyContinue
Start-VM -Name $name
Say 'VM: started from the stick - Windows Setup, then the first login runs setup.ps1'
} else { Say 'Resumed: the VM is running - waiting for setup' }
$w = [Diagnostics.Stopwatch]::StartNew(); $n = 0; $done = $false; $installedAt = $null
while ($w.Elapsed.TotalMinutes -lt $Minutes) {
    Save-Screen ("$Out\screen-{0:D3}.png" -f $n); $n++
    $st = try { Invoke-Command -VMName $name -Credential $cred -ErrorAction Stop -ScriptBlock {
            $l = Get-Content 'C:\PCSetupKit\setup.log' -Raw -ErrorAction SilentlyContinue
            [pscustomobject]@{ Windows = $true; Setup = [bool]$l; Done = $l -match '=== Done' } } } catch { $null }
    if ($st -and -not $installedAt) { $installedAt = $w.Elapsed; Say "VM: Windows is installed and signed in ($([int]$installedAt.TotalMinutes) min)" }
    if ($st.Done) { $done = $true; Say "VM: setup.ps1 finished ($([int]$w.Elapsed.TotalMinutes) min)"; break }
    Start-Sleep 120
}
if (-not $done) {
    Say "VM: setup did not finish in $Minutes min (last screen: screen-$('{0:D3}' -f ($n - 1)).png)"
    "FAILED: $(if ($installedAt) { 'Windows installed, setup.ps1 did not finish' } else { 'Windows did not finish installing' }) in $Minutes min" | Set-Content "$Out\result.txt"
    if (-not $Keep) { Remove-TestVm }; exit 1
}

# 3. the checks inside the VM (they wait for the first full maintenance), then its self-test
Start-Sleep 60; Save-Screen "$Out\screen-desktop.png"
# (a remote error must not end the test: each step's own output says what went wrong)
$chk = @(Invoke-Command -VMName $name -Credential $cred -ErrorAction Continue -ScriptBlock { $env:FRESH_WITH_CLAUDE = '0'; & powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\PCSetupKit\tests\fresh\check-install.ps1' 2>&1 | ForEach-Object { "$_" } })
$chk | Set-Content "$Out\check.txt"
$stt = @(Invoke-Command -VMName $name -Credential $cred -ErrorAction Continue -ScriptBlock { & powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\self-test.ps1" -Force 2>&1 | ForEach-Object { "$_" } })
$stt | Set-Content "$Out\self-test.txt"
Save-Screen "$Out\screen-finished.png"

# 4. the VM restarted once (the VM - never this PC): nothing setup removed came back meanwhile (the tweak guard finds
# nothing to do), no removed app is still provisioned for new users (the slimmed-down image), no drive encryption
$bloat = @(& "$repo\PCSetupKit\claude\make-usb.ps1" -ShowImagePlan | Where-Object { $_ -match '^BLOAT ' } | ForEach-Object { ($_ -replace '^BLOAT ') -split ',' })
Restart-VM -Name $name -Force; Start-Sleep 90
$after = $null; for ($t = 0; $t -lt 20 -and -not $after; $t++) {
    $after = try { Invoke-Command -VMName $name -Credential $cred -ErrorAction Stop -ScriptBlock {
            if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { return }   # (not signed in yet)
            Start-Sleep 60   # (the sign-in's own work: Windows applies the default-apps policy)
            $pin = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Microsoft Edge.lnk"
            "bloat provisioned: $((Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -in $using:bloat } | ForEach-Object DisplayName) -join ', ')"
            "drive encryption: $((Get-BitLockerVolume -MountPoint C: -ErrorAction SilentlyContinue).VolumeStatus)"
            "Edge desktop icon: $((Test-Path "$env:PUBLIC\Desktop\Microsoft Edge.lnk") -or (Test-Path "$env:USERPROFILE\Desktop\Microsoft Edge.lnk"))"
            "Edge pinned: $(Test-Path $pin)"
            "tweak guard: $((& powershell -NoProfile -ExecutionPolicy Bypass -File C:\PCSetupKit\tweaks.ps1) -join ', ')"
            "Teams: $([bool](Get-AppxPackage MSTeams))  OneDrive: $(Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe")"
        } } catch { $null }
    if (-not $after) { Start-Sleep 30 }
}
$after | Set-Content "$Out\after-restart.txt"; Save-Screen "$Out\screen-after-restart.png"
Say "After a restart: $(($after | ForEach-Object { $_ }) -join ' | ')"
$again = $after -match '^tweak guard: .+'
if (-not $after -or ($after -match '^Edge (desktop icon|pinned): True') -or $again -or ($after -match '^bloat provisioned: .+') -or ($after -match '^drive encryption: (?!FullyDecrypted)')) { $chk += 'RESULT after-restart fail=1' }
$res = ($chk -match '^RESULT ') -join ' + '; $self = "$(($stt -match 'Self-test|self-test') | Select-Object -Last 1)"
$ok = $res -match 'fail=0' -and $res -notmatch 'fail=[1-9]' -and $self -match '^Self-test \(requested\): \d+ passed, 0 failed'
"$(if ($ok) { 'PASSED' } else { 'FAILED' }): Windows installed in $([int]$installedAt.TotalMinutes) min, setup done at $([int]$w.Elapsed.TotalMinutes) min | $res | $self" | Tee-Object "$Out\result.txt" | ForEach-Object { Say $_ }
if (-not $Keep) { Remove-TestVm; Say 'VM and its disks removed' }
exit [int](-not $ok)
