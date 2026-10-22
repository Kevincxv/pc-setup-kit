# The processor's temperature (10/22, the owner's request). Windows has no way to read it on most desktops (AMD Ryzen:
# no ACPI thermal zone), so it takes a kernel driver: PawnIO (signed by its author, open source, the driver
# LibreHardwareMonitor and FanControl use since WinRing0 was flagged as unsafe) and LibreHardwareMonitor's library to
# read the CPU's own sensor (Ryzen: Tctl/Tdie). Exactly these versions, checked by SHA-256 (and PawnIO by its signature).
# -Ensure (health-check.ps1): installs both if missing - never under a game; kit-options.txt cputemp=off (the app's
#   Settings) removes them again (PawnIO only if Messiah put it on: cpu-temp.txt says so; one that was there before stays).
#   The driver shows in the stability timeline (power-log.ps1 "Hardware monitor driver") - it is a kernel driver.
# -Reader: returns a scriptblock that gives the temperature now (C, $null if it can't) - game-perf.ps1 and trends.ps1
#   call it; the library is loaded into their process once.
# -Test (hashtable: Game, Installed, Option, Reading, Before) with -Do (gets the actions) / -Options / -State: tests.
param([switch]$Ensure, [switch]$Reader, [hashtable]$Test, [scriptblock]$Do,
    [string]$Options = "$PSScriptRoot\kit-options.txt", [string]$State = "$PSScriptRoot\cpu-temp.txt", [string]$Tools = "$PSScriptRoot\tools\lhm")
$ErrorActionPreference = 'SilentlyContinue'
$T = $Test
$lhmUrl = 'https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/download/v0.9.6/LibreHardwareMonitor.zip'
$lhmSha = '086D9F1B5A99E643EDC2CFAAAC16051685B551E4C5AC0B32A57C58C0E529C001'
$pioUrl = 'https://github.com/namazso/PawnIO.Setup/releases/download/2.2.0/PawnIO_setup.exe'
$pioSha = '1F519A22E47187F70A1379A48CA604981C4FCF694F4E65B734AAA74A9FBA3032'
$uninst = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO'
function Act([string]$What, [scriptblock]$Real) { if ($Do) { & $Do $What } else { & $Real } }
function Installed { if ($T) { [bool]$T.Installed } else { [bool](Get-ItemProperty $uninst -ErrorAction SilentlyContinue) } }

# the temperature now: the CPU package sensor (Ryzen "Core (Tctl/Tdie)", Intel "CPU Package"), else the hottest core
function New-Reader {
    if ($T) { $v = $T.Reading; return { $v }.GetNewClosure() }
    if (-not (Test-Path "$Tools\LibreHardwareMonitorLib.dll") -or -not (Installed)) { return $null }
    try {
        Add-Type -Path "$Tools\LibreHardwareMonitorLib.dll" -ErrorAction Stop
        $c = New-Object LibreHardwareMonitor.Hardware.Computer; $c.IsCpuEnabled = $true; $c.Open()
        $cpu = @($c.Hardware | Where-Object { "$($_.HardwareType)" -eq 'Cpu' })[0]
        if (-not $cpu) { return $null }
        return {
            try {
                $cpu.Update()
                $t = @($cpu.Sensors | Where-Object { "$($_.SensorType)" -eq 'Temperature' -and $_.Value -gt 0 })
                $p = $t | Where-Object { $_.Name -match 'Tctl|Package' } | Select-Object -First 1
                if (-not $p) { $p = $t | Sort-Object Value -Descending | Select-Object -First 1 }
                if ($p) { [Math]::Round([double]$p.Value, 1) }
            } catch { }
        }.GetNewClosure()
    } catch { return $null }
}
if ($Reader) { return (New-Reader) }
if (-not $Ensure) { return }

$opt = if ($T) { $T.Option } else { $l = @(Get-Content $Options) -match '^\s*cputemp\s*=' | Select-Object -First 1; if ($l) { ($l -split '=', 2)[1].Trim() } }
$ours = if ($T) { $T.Ours } else { "$(Get-Content $State -TotalCount 1)".Trim() -eq 'installed' }
if ($opt -eq 'off') {
    if (-not $ours -and -not (Test-Path $Tools)) { return }
    if ($ours -and (Installed)) { Act 'uninstall PawnIO' { $q = (Get-ItemProperty $uninst).QuietUninstallString; if ($q -match '^"([^"]+)"\s*(.*)$') { Start-Process $Matches[1] -ArgumentList $Matches[2] -Wait -WindowStyle Hidden } } }
    Act 'remove the library' { Remove-Item $Tools -Recurse -Force; [IO.File]::Delete($State) }
    'CPU temperature: switched off - its driver (PawnIO) and library were removed'
    return
}
$ready = (Installed) -and ($T -or (Test-Path "$Tools\LibreHardwareMonitorLib.dll"))
if ($ready) { return }
$game = if ($T) { $T.Game } else { & "$PSScriptRoot\game-check.ps1" }
if ($game) { return }   # a driver installs: not under a game (next check)

$ProgressPreference = 'SilentlyContinue'
if ($T -or -not (Test-Path "$Tools\LibreHardwareMonitorLib.dll")) {
    $ok = Act 'library' {
        $zip = Join-Path $env:TEMP "pckit-lhm-$PID.zip"
        try { Invoke-WebRequest $lhmUrl -OutFile $zip -UseBasicParsing -TimeoutSec 120 } catch { return $false }
        if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $lhmSha) { [IO.File]::Delete($zip); return 'bad' }
        New-Item $Tools -ItemType Directory -Force | Out-Null
        Expand-Archive $zip $Tools -Force; [IO.File]::Delete($zip); $true
    }
    if ('bad' -eq $ok) { 'CPU temperature: the LibreHardwareMonitor download did not match the checked version - not used'; return }
    if (-not $ok) { return }   # offline: next check
}
if (-not (Installed)) {
    $ok = Act 'install PawnIO' {
        $exe = Join-Path $env:TEMP "pckit-pawnio-$PID.exe"
        try { Invoke-WebRequest $pioUrl -OutFile $exe -UseBasicParsing -TimeoutSec 120 } catch { return $false }
        $sig = Get-AuthenticodeSignature $exe
        if ((Get-FileHash $exe -Algorithm SHA256).Hash -ne $pioSha -or $sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=namazso') { [IO.File]::Delete($exe); return 'bad' }
        $p = Start-Process $exe -ArgumentList '-install', '-silent' -Wait -PassThru -WindowStyle Hidden
        [IO.File]::Delete($exe); $p.ExitCode -eq 0
    }
    if ('bad' -eq $ok) { 'CPU temperature: the PawnIO download did not match the checked version - not installed'; return }
    if (-not $ok) { 'CPU temperature: its driver (PawnIO) could not be installed - tried again at the next check'; return }
    if (-not $T) { 'installed' | Set-Content $State }
}
$r = New-Reader; $now = if ($r) { & $r }
if ($now) { "CPU temperature: now measured ($now C) - with the PawnIO driver and LibreHardwareMonitor (Activity > Performance: Heat and wear)" }
else { 'CPU temperature: installed, but the processor gave no reading yet - checked again next time' }
