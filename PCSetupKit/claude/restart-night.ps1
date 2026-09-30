# Finishing updates at night: when Windows (or a driver, or the PC maker's BIOS update) waits for a restart, the PC
# restarts itself at night - but only while nobody uses it. Otherwise that work waits until the owner turns the PC off,
# which on a PC that only ever sleeps can be weeks. Run every 30 minutes from 3:30 to 5:30 AM by the task
# "Messiah Night Restart" (never woken for it; a PC asleep or off simply isn't restarted).
# All of these must hold, or nothing happens:
# - the Settings switch is on (kit-options.txt nightrestart=on; the default is on - except on the PC the kit is made on,
#   whose owner restarts it himself)
# - a restart is pending (Windows Update or servicing, or a "REBOOT" line in the last maintenance report)
# - between 2 and 6 AM, nobody touched the keyboard or mouse for an hour, no game or fullscreen app, on AC power
# - no maintenance or kit update running, not already restarted tonight
# Then a 5-minute warning on screen ("Cancel restart" in the tray menu stops it) and the restart. State:
# restart-night.log. -Test (hashtable: Option, Pending, Hour, IdleMin, Game, OnBattery, Busy, DevPc, Restarted) with -Do
# (gets the actions), -Log, -Now: tests.
param([hashtable]$Test, [scriptblock]$Do, [string]$Log = "$PSScriptRoot\restart-night.log", [datetime]$Now = (Get-Date))
$ErrorActionPreference = 'SilentlyContinue'
$T = $Test
if ($env:PCKIT_IN_TESTS -and -not $T) { return }   # never from the test suite
function Act([string]$What, [scriptblock]$Real) { if ($Do) { & $Do $What } else { & $Real } }
function Why($m) { try { Add-Content $Log "$($Now.ToString('s'))  $m" } catch {}; $m }

# the switch (default on, except the kit's own development PC)
$dev = if ($T) { $T.DevPc } else { Test-Path "$PSScriptRoot\publish-kit.ps1" }
$opt = if ($T) { $T.Option } else { $l = @(Get-Content "$PSScriptRoot\kit-options.txt") -match '^\s*nightrestart\s*=' | Select-Object -First 1; if ($l) { ($l -split '=', 2)[1].Trim() } }
if (-not $opt) { $opt = if ($dev) { 'off' } else { 'on' } }
if ($opt -ne 'on') { return }

$pending = if ($T) { $T.Pending } else {
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
    [bool](Select-String -Path "$PSScriptRoot\maint-report.txt" -Pattern '\bREBOOT\b' -Quiet)
}
if (-not $pending) { return }
$hour = if ($T) { $T.Hour } else { $Now.Hour }
if ($hour -lt 2 -or $hour -ge 6) { return }
$restarted = if ($T) { $T.Restarted } else { (Get-Content $Log -Tail 5) -match "^$($Now.ToString('yyyy-MM-dd'))T\S+  Restarting" }
if ($restarted) { return }

$idle = if ($T) { $T.IdleMin } else {
    if (-not ('Kit.Idle' -as [type])) { Add-Type -Namespace Kit -Name Idle -MemberDefinition '[StructLayout(LayoutKind.Sequential)] public struct LII { public uint cbSize; public uint dwTime; } [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LII p); public static uint Ms() { var l = new LII(); l.cbSize = 8; GetLastInputInfo(ref l); return (uint)Environment.TickCount - l.dwTime; }' }
    [Kit.Idle]::Ms() / 60000
}
if ($idle -lt 60) { return Why "Waiting: the PC was used $([int]$idle) min ago" }
$g = if ($T) { $T.Game } else { & "$PSScriptRoot\game-check.ps1" }
if ($g) { return Why "Waiting: $g is running" }
$bat = if ($T) { $T.OnBattery } else { $b = Get-CimInstance Win32_Battery | Select-Object -First 1; $b -and $b.BatteryStatus -eq 1 }
if ($bat) { return Why 'Waiting: on battery' }
$busy = if ($T) { $T.Busy } else { $m = $null; foreach ($n in 'Global\ClaudeBgMaint', 'Global\PCSetupKitUpdate', 'Global\PCSetupKitTweaks') { if ([Threading.Mutex]::TryOpenExisting($n, [ref]$m)) { $m.Dispose(); $n } } }
if ($busy) { return Why "Waiting: maintenance is running ($busy)" }

Why 'Restarting to finish updates (nobody used the PC for an hour; 5 minutes warning)' | Out-Null
Act 'restart in 5 min' { & "$env:SystemRoot\System32\shutdown.exe" /r /t 300 /d p:2:17 /c "Messiah: restarting in 5 minutes to finish updates - nobody has used the PC for an hour. To stop it: Messiah's tray menu > Cancel restart." }
'Night restart: restarting to finish updates'
