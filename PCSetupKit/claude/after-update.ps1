# Right after an update: 2 minutes after Windows Update installed something or a driver was installed (the scheduled
# task "PC Setup Kit Update Guard", made by ensure-schedule.ps1), everything an update can undo is put back at once
# instead of at the next login: the tweak guard (tweaks.ps1 - settings, services, tasks, removed apps, the power plan,
# OneDrive), this PC's own extras, the monitors, the NVIDIA settings. What it had to fix goes to maint-history as a
# small report (the app's History page, "What maintenance did"). Never under a game (the monitor switch is skipped
# then by display-refresh itself; the rest is invisible). -Dir / -Kit: tests.
param([string]$Dir = $PSScriptRoot, [string]$Kit = 'C:\PCSetupKit')
$ErrorActionPreference = 'SilentlyContinue'
$mx = New-Object Threading.Mutex($false, 'Global\PCSetupKitAfterUpdate')
if (-not $mx.WaitOne(0)) { return }   # a burst of update events: one run is enough
$t0 = Get-Date
$fixed = @(if (Test-Path "$Kit\tweaks.ps1") { & "$Kit\tweaks.ps1" }) + @(if (Test-Path "$Dir\tweaks-local.ps1") { & "$Dir\tweaks-local.ps1" })
$lines = @(if ($fixed) { "Tweaks: an update had reverted $($fixed.Count) - re-applied: $(($fixed | Select-Object -Unique) -join ', ')" })
foreach ($s in 'display-refresh.ps1', 'nvidia-settings.ps1') { if (Test-Path "$Dir\$s") { $lines += @(& "$Dir\$s") } }
$lines = @($lines | Where-Object { $_ })
if ($lines) {
    $h = New-Item "$Dir\maint-history" -ItemType Directory -Force
    @("Checked $($t0.ToString('g')) in $([int]((Get-Date) - $t0).TotalSeconds) s (right after an update)") + $lines | Set-Content "$h\report-$($t0.ToString('yyyyMMdd-HHmmss'))-update.txt" -Encoding UTF8
}
$lines
