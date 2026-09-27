# Lists the maintenance items that need Claude itself (the /maintain skill), one per line; prints nothing if none.
# Shared by claude-admin-launch.ps1 (interactive) and claude-bg-maint.ps1 -Unattended (headless run at login).
# -MarkHandled records that the current report's warnings have been passed to Claude, so they trigger only once.
param([switch]$MarkHandled)
$cl = $PSScriptRoot
$stateFile = "$cl\maint-state.json"
$state = @{}
# An empty/corrupt state file (e.g. power loss mid-write) counts as "everything due"; keep a copy for Claude to look at
if (Test-Path $stateFile) {
    try { $j = Get-Content $stateFile -Raw | ConvertFrom-Json -ErrorAction Stop } catch { $j = $null; Copy-Item $stateFile "$stateFile.bad" -Force }
    if ($j) { $j.PSObject.Properties | ForEach-Object { $state[$_.Name] = $_.Value } }
}
$due = @()
foreach ($t in @(@('claude-quarterly', 90, 'quarterly check'), @('claude-halfyear', 180, 'half-year check'), @('claude-yearly', 365, 'yearly re-audit'))) {
    $d = [datetime]::MinValue
    if (-not [datetime]::TryParse("$($state[$t[0]])", [ref]$d) -or $d -lt (Get-Date).AddDays(-$t[1])) { $due += $t[2] }
}
if ($state['claude-winver-due']) { $due += 'Windows version upgrade' }
# Crash-ladder EXPO-off test: ask for a verdict once it has run long enough (4 days, or the review date Claude set)
$t0 = [datetime]::MinValue
if ([datetime]::TryParse("$($state['expo-off-test'])", [ref]$t0)) {
    $rv = [datetime]::MinValue; $review = if ([datetime]::TryParse("$($state['expo-off-test-review'])", [ref]$rv)) { $rv } else { $t0.AddDays(4) }
    if ((Get-Date) -ge $review) { $due += "EXPO-off test verdict (test running since $($t0.ToString('MMM d')))" }
}
$r = @(Get-Content "$cl\maint-report.txt" -ErrorAction SilentlyContinue)
# A Get-Content string saved straight to JSON becomes {value, PSPath, ...}; read .value so it still matches
$handled = $state['claude-handled-report']; if ($handled.value) { $handled = $handled.value }
if ($r -and ($r | Where-Object { $_ -match 'WARNING|FAILED|timed out|DOCTOR ISSUES' }) -and "$handled" -ne "$($r[0])") {
    $due += 'warnings in the maintenance report'
}
if ($MarkHandled -and $due) {
    $state['claude-handled-report'] = "$($r[0])"
    $state | ConvertTo-Json | Set-Content "$stateFile.tmp" -Encoding utf8
    Move-Item "$stateFile.tmp" $stateFile -Force   # swap in whole, so a crash never leaves a half-written file
}
$due
