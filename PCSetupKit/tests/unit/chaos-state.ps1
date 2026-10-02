# Break-it test: every state file the app and its read-only helpers read is filled with garbage (broken JSON, empty,
# binary noise, a huge file, the wrong type), in a profile whose path has spaces and non-English letters - and nothing
# may crash or throw: the app window builds every page, the text status, the to-do list, the schedule, the pause and
# AI switches, the weekly summary. (Scripts that change the PC have their own tests with mocks.)
. "$PSScriptRoot\..\lib.ps1"
$H = "$Work\Jörg Müller ÄÖÜ ñ"; $C = "$H\.claude"
New-Item $C, "$H\Documents", "$C\maint-history" -ItemType Directory -Force | Out-Null
foreach ($f in 'dashboard.ps1', 'status.ps1', 'status-lib.ps1', 'session-lib.ps1', 'ai-enabled.ps1', 'todo.ps1', 'maint-due.ps1', 'paused.ps1', 'weekly-summary.ps1', 'bios-info.ps1') {
    if (Test-Path "$Src\$f") { Copy-Item "$Src\$f" $C }
}
$states = 'actions-state.json', 'guard-state.json', 'benchmarks.json', 'display-state.json', 'files-backup-state.json', 'gaming-state.json', 'gpu-state.json',
    'health-history.json', 'junk-state.json', 'maint-state.json', 'net-history.json', 'perf-history.json', 'restart-ledger.json', 'self-test.json',
    'todo-scripted.json', 'update-state.json', 'vendor-state.json', 'kit-options.txt', 'maint-report.txt', 'maint-todo.txt', 'notifications.log',
    'tray-news.txt', 'tray-notified.ini', 'gpu-hold.txt', 'admin-sessions.txt', 'app-window.txt', 'tray-hwnd.txt', 'restart-night.log'
$big = 'x' * 3MB
$kinds = [ordered]@{
    'broken JSON'  = '{"date": "2026-01-01", "freeGB": '
    'empty'        = ''
    'wrong type'   = '[1, "two", {"three": [null]}, true]'
    'binary noise' = (-join ((1..600) | ForEach-Object { [char](Get-Random -Minimum 0 -Maximum 0xD7FF) }))   # (below the surrogate range: writable)
    'huge'         = $big
    'bad dates'    = '[{"date":"not a date","bootAt":"99/99/9999","boot":"slow","freeGB":"lots","fps":-1,"game":null}]'
}
foreach ($k in $kinds.Keys) {
    Section "state files: $k"
    foreach ($f in $states) { [IO.File]::WriteAllText("$C\$f", $kinds[$k]) }
    [IO.File]::WriteAllText("$C\maint-history\report-20260101-000000.txt", $kinds[$k])
    $r = Invoke-As $H "$C\dashboard.ps1" @('-Test')
    $pages = @([regex]::Matches("$($r.Out)", '(?m)^PAGE: ') ).Count
    $pe = @([regex]::Matches("$($r.Out)", '(?m)^PAGE ERROR: .*$') | ForEach-Object Value) -join ' / '
    Check "the app window builds every page, no error ($k)" (-not "$($r.Err)".Trim() -and $pages -ge 6 -and "$($r.Out)" -match 'NAV: ' -and -not $pe) ("$pe $($r.Err)".Substring(0, [Math]::Min(600, "$pe $($r.Err)".Length)))
    $r = Invoke-As $H "$C\dashboard.ps1" @('-Test', '-Page', 'Welcome')   # (no setup report here: see below for one)
    Check "... the welcome page too ($k)" (-not "$($r.Err)".Trim() -and "$($r.Out)" -match 'PAGE: Welcome' -and "$($r.Out)" -notmatch 'PAGE ERROR') ("$($r.Err)".Substring(0, [Math]::Min(600, "$($r.Err)".Length)))
    # the history keeps working: after one check on the damaged file it is valid again, with today's entry
    if (Test-Path "$Src\trends.ps1") {
        $r = Invoke-As $H "$Src\trends.ps1" @('-History', "$C\health-history.json", '-PerfHistory', "$C\perf-history.json")
        $hj = try { @(Get-Content "$C\health-history.json" -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop | ForEach-Object { $_ }) } catch { $null }
        Check "trends.ps1: the damaged history is valid again after one check, with today's entry ($k)" ($hj -and @($hj | Where-Object { "$($_.date)" -like "$((Get-Date).ToString('yyyy-MM-dd'))*" }).Count -ge 1) ("$($r.Err)".Substring(0, [Math]::Min(300, "$($r.Err)".Length)))
    }
    foreach ($s in @(@('todo.ps1', '-List'), @('maint-due.ps1'), @('paused.ps1'), @('ai-enabled.ps1'), @('weekly-summary.ps1'))) {
        if (-not (Test-Path "$C\$($s[0])")) { continue }
        $r = Invoke-As $H "$C\$($s[0])" @($s | Select-Object -Skip 1)
        Check "$($s[0]) runs without an error ($k)" (-not "$($r.Err)".Trim()) ("$($r.Err)".Substring(0, [Math]::Min(400, "$($r.Err)".Length)))
    }
}
Section 'the Welcome page with the setup report a new PC has (9/30: its filter regex broke the whole page)'
foreach ($f in $states) { [IO.File]::Delete("$C\$f") }
New-Item "$H\Documents" -ItemType Directory -Force | Out-Null
# (the shape of a real report: the boot-from-USB VM test's, shortened)
@('PC Setup Kit - optimization report', '', 'THIS PC', '  Windows: Windows 11 Pro 25H2', '', 'WHAT WAS DONE', '  Benchmark: could not run (WinSAT gave no scores)',
  '  Maintenance (in the background, right after setup):', '    [Drivers]', '    Other drivers: all up to date (Windows Update)', '    [PC health]', '    Crashes: none since last check',
  '    Tweaks: Windows had reverted 2 - re-applied: task X off', '    Security: started a quick virus scan (last one never)', '    SSD TRIM run (Windows had not done it in 2+ weeks)',
  '    Restore point FAILED (is System Protection on for C:?)', '    Next: App updates Oct 7, cleanup Oct 30', '    [Actions]', '    Night restart: pending updates now finish with a restart at night', '',
  'WHAT NEEDS YOU', '  - Windows isn''t activated', '') | Set-Content "$H\Documents\PC Setup Kit report.txt" -Encoding UTF8
$r = Invoke-As $H "$C\dashboard.ps1" @('-Test', '-Page', 'Welcome')
$pe = (@([regex]::Matches("$($r.Out)", '(?m)^PAGE ERROR: .*$') | ForEach-Object Value) -join ' / ') + " $($r.Err)"
Check 'the Welcome page builds from a real setup report' (-not "$($r.Err)".Trim() -and "$($r.Out)" -match 'PAGE: Welcome' -and "$($r.Out)" -notmatch 'PAGE ERROR') $pe.Substring(0, [Math]::Min(600, $pe.Length))
[IO.File]::Delete("$H\Documents\PC Setup Kit report.txt")
Finish
