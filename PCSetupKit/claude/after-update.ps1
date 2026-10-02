# Right after an update: 2 minutes after Windows Update installed something or a driver was installed (the scheduled
# task "PC Setup Kit Update Guard", made by ensure-schedule.ps1), everything an update can undo is put back at once
# instead of at the next login: the tweak guard (tweaks.ps1 - settings, services, tasks, removed apps, the power plan,
# OneDrive), this PC's own extras, the monitors, the NVIDIA settings. What it had to fix goes to maint-history as a
# small report (the app's History page, "What maintenance did"). Never under a game (the monitor switch is skipped
# then by display-refresh itself; the rest is invisible). -Dir / -Kit: tests.
param([string]$Dir = $PSScriptRoot, [string]$Kit = 'C:\PCSetupKit', [switch]$Now, [switch]$Regular)   # -Regular: the 4-hourly check's guard pass (update-check.ps1) - the same, for PCs left on for days   # -Now: the owner just changed a choice in the app (runs even while paused)
$ErrorActionPreference = 'SilentlyContinue'
if (-not $Now -and (Test-Path "$Dir\paused.ps1") -and (& "$Dir\paused.ps1")) { return }   # paused by the owner
$mx = New-Object Threading.Mutex($false, "Global\PCSetupKitAfterUpdate$(if ($env:PCKIT_IN_TESTS) { "-$PID" })")   # (tests: their own - never the real guard's, which may be running)
if (-not $mx.WaitOne(0)) { return }   # a burst of update events: one run is enough
$bm = $null; if (-not $Now -and -not $env:PCKIT_IN_TESTS -and [Threading.Mutex]::TryOpenExisting('Global\ClaudeBgMaint', [ref]$bm)) { $bm.Dispose(); return }   # the maintenance running now runs the guard itself
$t0 = Get-Date
$fixed = @(if (Test-Path "$Kit\tweaks.ps1") { & "$Kit\tweaks.ps1" }) + @(if (Test-Path "$Dir\tweaks-local.ps1") { & "$Dir\tweaks-local.ps1" })
$lines = @(if ($fixed) { "Tweaks: $(if ($Regular) { 'Windows had changed back' } else { 'an update had reverted' }) $($fixed.Count) - re-applied: $(($fixed | Select-Object -Unique) -join ', ')" })
foreach ($s in 'display-refresh.ps1', 'nvidia-settings.ps1') { if (Test-Path "$Dir\$s") { $lines += @(& "$Dir\$s") } }
# the gaming fixes an update can undo too (the fast graphics chip per game, Game Bar and AMD's V-Cache service on X3D CPUs) -
# only what it fixed: its reminders are the login check's (10/2)
if (Test-Path "$Dir\gaming-check.ps1") { $lines += @(& "$Dir\gaming-check.ps1" | Where-Object { "$_" -match '^Gaming: ' }) }
$lines = @($lines | Where-Object { $_ })
try { @{ at = (Get-Date).ToString('o'); fixed = @($fixed).Count } | ConvertTo-Json | Set-Content "$Dir\guard-state.json" -Encoding UTF8 } catch { }   # (the app's Guarded tile)
if ($lines) {
    $h = New-Item "$Dir\maint-history" -ItemType Directory -Force
    @("Checked $($t0.ToString('g')) in $([int]((Get-Date) - $t0).TotalSeconds) s ($(if ($Regular) { 'regular check' } else { 'right after an update' }))") + $lines | Set-Content "$h\report-$($t0.ToString('yyyyMMdd-HHmmss'))-$(if ($Regular) { 'guard' } else { 'update' }).txt" -Encoding UTF8
}
$lines
