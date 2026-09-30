# Once a week (claude-bg-maint.ps1, at the end of a run): what the maintenance did in the last 7 days, as one short note
# in the corner (tray-news.txt, shown once) - "3 app updates, 1 driver, no crashes, your games ran as usual". Nothing
# when nothing happened. From the saved reports (maint-history) and the game samples (perf-history.json).
# -Dir / -Now: tests.
param([string]$Dir = $PSScriptRoot, [datetime]$Now = (Get-Date))
$ErrorActionPreference = 'SilentlyContinue'
$stamp = "$Dir\weekly-summary.last"
$last = [datetime]::MinValue; [void][datetime]::TryParse("$(Get-Content $stamp -TotalCount 1)", [ref]$last)
if ($last -gt $Now.AddDays(-7)) { return }
$Now.ToString('o') | Set-Content $stamp
$lines = @(Get-ChildItem "$Dir\maint-history\report-*.txt" | Where-Object { $_.LastWriteTime -gt $Now.AddDays(-7) } | ForEach-Object { Get-Content $_.FullName -Encoding UTF8 } | Select-Object -Unique)
$n = { param($rx) @($lines -match $rx).Count }
$kit = & $n '^PC Setup Kit updated'; $apps = & $n '^Updated app'; $drv = & $n '^(Driver|NVIDIA|AMD chipset): .*installed'
$fixed = & $n 'reverted \d+ - re-applied'; $crash = & $n '^WARNING: (blue screen|unexpected shutdown)'
$slow = & $n 'runs slower since'
$parts = @(
    if ($kit) { 'the kit updated itself' }
    if ($apps) { "$apps app update$(if ($apps -gt 1) { 's' })" }
    if ($drv) { "$drv driver$(if ($drv -gt 1) { 's' }) installed" }
    if ($fixed) { "settings an update undid put back $fixed time$(if ($fixed -gt 1) { 's' })" }
)
$pj = try { Get-Content "$Dir\perf-history.json" -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null }
$games = @($pj | ForEach-Object { $_ } | Where-Object { $_ -is [Management.Automation.PSCustomObject] -and $(try { [void][datetime]"$($_.date)"; $true } catch { $false }) } | Where-Object { [datetime]$_.date -gt $Now.AddDays(-7) } | ForEach-Object game | Select-Object -Unique)
if (-not $parts -and -not $crash -and -not $games) { return }   # a quiet week: nothing to say
$msg = "This week: $(if ($parts) { $parts -join ', ' } else { 'nothing needed doing' }). $(if ($crash) { "$crash crash$(if ($crash -gt 1) { 'es' }) - see the app." } else { 'No crashes.' })"
if ($games) { $msg += " $($games.Count) game$(if ($games.Count -gt 1) { 's' }) played$(if ($slow) { ' - one runs slower since an update (see the app)' } else { ', running as usual' })." }
$msg | Set-Content "$Dir\tray-news.txt" -Encoding UTF8
$msg
