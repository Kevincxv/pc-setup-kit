# The PC maker's own update tool on prebuilt PCs and laptops - BIOS, firmware and drivers straight from the maker,
# installed by itself once a week (run by driver-check.ps1, before Windows Update's drivers):
# - Dell: Dell Command | Update     - HP: HP Image Assistant     - Lenovo ThinkPad / ThinkCentre / ThinkStation /
#   ThinkBook: Lenovo System Update (the tools are installed from winget the first time; all three are free)
# Never while a game runs, never on battery (a BIOS update must not lose power), a restore point first. A BIOS update
# is staged and finishes at the next restart (never restarts by itself: "REBOOT" in the report, like Windows updates).
# A model the tool doesn't support (consumer lines) is remembered: the BIOS reminder (health-check.ps1) stays then;
# on a supported one it goes, since the maker's tool keeps the BIOS current. Custom-built PCs: nothing here.
# State: vendor-state.json. -Test (hashtable: Maker, Model, Exe, ExeAfterInstall, Exit, Game, OnBattery) with -Do
# (gets the actions), -State, -Now: tests.
param([hashtable]$Test, [scriptblock]$Do, [string]$State = "$PSScriptRoot\vendor-state.json", [datetime]$Now = (Get-Date), [switch]$Force)
$ErrorActionPreference = 'SilentlyContinue'
$T = $Test
if ($env:PCKIT_IN_TESTS -and -not $T) { return }   # the self-test runs driver-check.ps1: never the real maker tool from it
function Act([string]$What, [scriptblock]$Real) { if ($Do) { & $Do $What } else { & $Real } }
$st = @{}; try { (Get-Content $State -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).PSObject.Properties | ForEach-Object { $st[$_.Name] = $_.Value } } catch {}
function Save { try { [pscustomobject]$st | ConvertTo-Json | Set-Content $State -Encoding UTF8 } catch {} }

$maker = if ($T) { $T.Maker } else { "$((Get-CimInstance Win32_ComputerSystem).Manufacturer)" }
$model = if ($T) { $T.Model } else { $p = Get-CimInstance Win32_ComputerSystemProduct; "$($p.Version) $($p.Name)".Trim() }
$sp = "$env:TEMP\messiah-maker-updates"
$tool = switch -Regex ($maker) {
    '^Dell' { @{ Name = 'Dell Command | Update'; Id = 'Dell.CommandUpdate.Universal'
            Exe = @("$env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe", "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe")
            Args = '/applyUpdates -silent -reboot=disable -autoSuspendBitLocker=enable -updateType=bios,firmware,driver'
            Ok = 0; None = 500; Reboot = 1, 5; Unsupported = 3, 7 } }
    '^(HP|Hewlett)' { @{ Name = 'HP Image Assistant'; Id = 'HP.ImageAssistant'
            Exe = @("$env:ProgramFiles\HP\HPIA\HPImageAssistant.exe", "${env:ProgramFiles(x86)}\HP\HPIA\HPImageAssistant.exe", 'C:\SWSetup\HPImageAssistant\HPImageAssistant.exe')
            Args = "/Operation:Analyze /Action:Install /Selection:All /Category:BIOS,Drivers,Firmware /Silent /Noninteractive /ReportFolder:`"$sp\report`" /SoftpaqDownloadFolder:`"$sp\softpaq`""
            Ok = 0; None = 256, 257; Reboot = 3010; Unsupported = 4096 } }
    '^Lenovo' { if ($model -match '\bThink(Pad|Centre|Station|Book)\b') { @{ Name = 'Lenovo System Update'; Id = 'Lenovo.SystemUpdate'
                Exe = @("${env:ProgramFiles(x86)}\Lenovo\System Update\tvsu.exe", "$env:ProgramFiles\Lenovo\System Update\tvsu.exe")
                Args = '/CM -search A -action INSTALL -includerebootpackages 1,3,4 -noicon -nolicense -noreboot'
                Ok = 0; None = @(); Reboot = @(); Unsupported = @() } } }
}
if (-not $tool) { return }   # a custom-built PC, or a model line the maker's tool doesn't cover
if ($st.unsupported -eq $tool.Name) { return }
$last = [datetime]::MinValue; [void][datetime]::TryParse("$($st.last)", [ref]$last)
if (-not $Force -and $last -gt $Now.AddDays(-6)) { return }
if ($g = $(if ($T) { $T.Game } else { & "$PSScriptRoot\game-check.ps1" })) { "Maker updates: held while $g is running (next check)"; return }
$battery = if ($T) { $T.OnBattery } else { $b = Get-CimInstance Win32_Battery | Select-Object -First 1; $b -and $b.BatteryStatus -eq 1 }
if ($battery) { "Maker updates: wait until the laptop is plugged in (a BIOS update must not lose power)"; return }

function Find-Exe { if ($T) { if ($T.Exe) { 'exe' } } else { $tool.Exe | Where-Object { Test-Path $_ } | Select-Object -First 1 } }
$exe = Find-Exe
if (-not $exe) {
    $tried = [datetime]::MinValue; [void][datetime]::TryParse("$($st.installTried)", [ref]$tried)
    if ($tried -gt $Now.AddDays(-30)) { return }   # didn't install last time: once a month
    $st.installTried = $Now.ToString('o'); Save
    Act "install $($tool.Id)" { $null = winget install --id $tool.Id --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 }
    $exe = if ($T) { if ($T.ExeAfterInstall) { 'exe' } } else { Find-Exe }
    if (-not $exe) { "Maker updates: couldn't install $($tool.Name) - tried again in a month"; return }
    "Maker updates: installed $($tool.Name) (the maker's own BIOS and driver updates for this $maker)"
}
Act 'restore point' {
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $was = (Get-ItemProperty $k).SystemRestorePointCreationFrequency
    Set-ItemProperty $k SystemRestorePointCreationFrequency 0 -Type DWord
    Checkpoint-Computer -Description "Before $($tool.Name) updates (Messiah)" -RestorePointType DEVICE_DRIVER_INSTALL -WarningAction SilentlyContinue
    if ($null -eq $was) { Remove-ItemProperty $k SystemRestorePointCreationFrequency } else { Set-ItemProperty $k SystemRestorePointCreationFrequency $was -Type DWord }
}
$code = $null
Act "run $($tool.Name)" { New-Item $sp -ItemType Directory -Force | Out-Null; $p = Start-Process $exe -ArgumentList $tool.Args -WindowStyle Hidden -Wait -PassThru; $script:code = $p.ExitCode }
if ($T) { $code = $T.Exit }
$st.last = $Now.ToString('o'); $st.tool = $tool.Name; $st.code = $code
if ($code -in $tool.Unsupported) {
    $st.unsupported = $tool.Name; $st.supported = $false; Save
    "Maker updates: $($tool.Name) doesn't cover this $model - the BIOS reminder stays (the maker's support page has the updates)"
    return
}
if ($code -eq $tool.Ok -or $code -in $tool.None -or $code -in $tool.Reboot) { $st.supported = $true }
Save
if ($code -in $tool.Reboot) { "Maker updates ($($tool.Name)): updates installed; REBOOT required to finish them (a BIOS update finishes at the next restart - never turn the PC off during it)" }
elseif ($code -in $tool.None) { "Maker updates ($($tool.Name)): BIOS, firmware and drivers up to date" }
elseif ($code -eq $tool.Ok) { "Maker updates ($($tool.Name)): checked and installed what was new" }
else { "Maker updates ($($tool.Name)) FAILED (exit code $code) - tried again next week" }
