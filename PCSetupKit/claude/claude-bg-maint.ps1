# Background maintenance for the "Messiah" launcher. Runs elevated and hidden, so Claude never waits on it.
# Started by the launcher (fire-and-forget) and by the "Claude Background Maintenance" task at logon.
# Runs the driver check, Claude Code maintenance and PC health check in parallel and writes a report
# that the launcher shows at the next start.
param([switch]$Force, [switch]$Unattended, [switch]$Now)   # -Now: the owner started it (tray / app "Run maintenance now", optimize): runs even while paused   # -Unattended: run at login by the scheduled task; also lets Claude do /maintain headless
$ErrorActionPreference = 'Continue'
$dir = "$env:USERPROFILE\.claude"
$report = "$dir\maint-report.txt"
# Claude is optional (setup.ps1 -WithClaude): without it, nothing here needs AI - Claude Code upkeep and hidden Claude runs are skipped
$ai = if (Test-Path "$dir\ai-enabled.ps1") { & "$dir\ai-enabled.ps1" } else { $true }   # (an older copy without the switch: it was installed with Claude)

# One run at a time; skip if the last run was recent (launching Claude twice in a row shouldn't redo everything)
$mutex = New-Object Threading.Mutex($false, 'Global\ClaudeBgMaint')
if (-not $mutex.WaitOne(0)) { exit }
# paused by the owner (tray > Pause maintenance): nothing runs until then - "Run maintenance now" (-Now) still does
if (-not $Now -and (Test-Path "$dir\paused.ps1") -and (& "$dir\paused.ps1")) { exit }
if (-not $Force -and (Test-Path $report) -and ((Get-Date) - (Get-Item $report).LastWriteTime).TotalMinutes -lt 30) { exit }

# Game-aware: never start maintenance under a running game (driver installs black the screen, updates stutter it).
# Wait up to 45 min for it to close; after that the heavy steps each hold themselves (they check game-check too).
$gameNote = $null; $w0 = Get-Date
while (($g = & "$dir\game-check.ps1") -and ((Get-Date) - $w0).TotalMinutes -lt 45) { Start-Sleep 60 }
$waited = [int]((Get-Date) - $w0).TotalMinutes
if ($g) { $gameNote = "Game: $g still running after $waited min - heavy steps held until the next run" }
elseif ($waited -ge 1) { $gameNote = "Game: waited $waited min for it to close before starting" }
# PCs installed before the rename to Messiah: move the shortcuts and tray task once (migrate-names.ps1)
$renamed = if (Test-Path "$dir\migrate-names.ps1") { & "$dir\migrate-names.ps1" }
# the app (icon, Start menu entry, tray program and task) as the installed version wants it - after kit updates and
# AutoHotkey updates too. Never from the test suite: it would change the owner's real Start menu and tray.
$trayApp = if (-not $env:PCKIT_IN_TESTS -and (Test-Path "$dir\tray-app.ps1")) { & "$dir\tray-app.ps1" }
$start = Get-Date
$jobs = foreach ($j in @(
        @{ Name = 'Drivers'; Script = 'driver-check.ps1'; Timeout = 1200 },
        @{ Name = 'Claude Code'; Script = 'claude-maint.ps1'; Timeout = 300 },    # its own steps can take 120+45+45 s (+45 per plugin)
        @{ Name = 'PC health'; Script = 'health-check.ps1'; Timeout = 900 },     # long limit: first crash-dump analysis downloads symbols
        @{ Name = 'Periodic'; Script = 'periodic-maint.ps1'; Timeout = 3600 },   # weekly app updates, monthly cleanup (only when due)
        @{ Name = 'Kit'; Script = 'kit-update.ps1'; Timeout = 900 })) {          # PCs installed from the kit: newest published version
    if (-not (Test-Path "$dir\$($j.Script)")) { continue }
    if ($j.Script -eq 'claude-maint.ps1' -and -not $ai) { continue }
    # this run's own file names: another run at the same time (a test copy, a manual run) must never mix into this report
    $out = Join-Path $env:TEMP "claude-bg-$PID-$($j.Script).log"
    $p = Start-Process powershell -WindowStyle Hidden -PassThru -RedirectStandardOutput $out `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$dir\$($j.Script)`""
    [pscustomobject]@{ Name = $j.Name; Proc = $p; Out = $out; Deadline = $start.AddSeconds($j.Timeout) }
}
foreach ($j in $jobs) {
    $left = [int]($j.Deadline - (Get-Date)).TotalMilliseconds
    if ($left -le 0 -or -not $j.Proc.WaitForExit($left)) { Stop-Process -Id $j.Proc.Id -Force -ErrorAction SilentlyContinue; $j | Add-Member TimedOut $true }
}

$lines = @("Checked $((Get-Date).ToString('g')) in $([int]((Get-Date) - $start).TotalSeconds)s") + @($gameNote, $renamed, $trayApp | Where-Object { $_ })
foreach ($j in $jobs) {
    $out = @(if (Test-Path $j.Out) { Get-Content $j.Out | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }; Remove-Item $j.Out -Force })
    if ($j.TimedOut) { $out = @('WARNING: timed out') + $out }
    if ($out) { $lines += "[$($j.Name)]"; $lines += $out }   # a job with nothing to say (e.g. no kit update) leaves no empty section
}
# Self-test (weekly, and after a kit update - so after the jobs): the kit's test suite against the installed scripts.
# A failure is a WARNING, so /maintain looks at it at this same login.
$st = @(if (Test-Path "$dir\self-test.ps1") { & "$dir\self-test.ps1" | Where-Object { $_ } })
if ($st) { $lines += '[Self-test]'; $lines += $st }
# Without Claude: scripted decisions - safe fixes and plain to-do items - from what the jobs found (maint-actions.ps1)
$act = @(if (-not $ai -and (Test-Path "$dir\maint-actions.ps1")) { & "$dir\maint-actions.ps1" -Lines $lines | Where-Object { $_ } })
if ($act) { $lines += '[Actions]'; $lines += $act }
# Write to a temp file then swap, so the launcher never reads a half-written report
$lines | Set-Content "$report.tmp" -Encoding utf8
Move-Item "$report.tmp" $report -Force
# Keep the last 30 reports so Claude can look back at when something started
$hist = New-Item "$dir\maint-history" -ItemType Directory -Force
Copy-Item $report (Join-Path $hist ("report-{0:yyyyMMdd-HHmmss}.txt" -f (Get-Date)))
Get-ChildItem $hist -Filter 'report-*.txt' | Sort-Object Name -Descending | Select-Object -Skip 30 | ForEach-Object { [IO.File]::Delete($_.FullName) }

# At login: let Claude work headless (no window). First /maintain if anything needs it, then the /self-improve pass
# (at most once a day). Output in .claude\maint-claude-log; the tray's "Watch maintenance live" follows the running session.
if ($Unattended -and $ai) {
    $runs = @()
    $logDir = New-Item "$dir\maint-claude-log" -ItemType Directory -Force
    $busy = "$dir\maint-claude-running"                           # tells the launcher not to start a second /maintain
    # The owner may turn the PC off in the middle of a hidden run - that's fine: this login picks the work up again
    if ((Test-Path $busy) -and (Get-Item $busy).LastWriteTime -lt (Get-CimInstance Win32_OperatingSystem).LastBootUpTime) {
        $prev = @(Get-Content "$dir\maint-claude-session" -ErrorAction SilentlyContinue)
        $plog = Get-ChildItem $logDir -Filter '*.md' | Sort-Object Name -Descending | Select-Object -First 1
        Add-Content "$dir\maint-requests.txt" -Encoding UTF8 ("The previous hidden run ($($prev[1]), started $($prev[2])) was cut off (the PC was turned off, or it hit its time limit). " +
            "Its transcript is session $($prev[0])$(if ($plog) { " (log: $($plog.FullName))" }). Check what it had started, verify anything that needed the restart, and finish it.")
    }
    # Warnings count as handled only once /maintain has finished (a shutdown in the middle leaves them due for next login)
    $due = @(& "$dir\maint-due.ps1")
    if ($due -or (Test-Path "$dir\maint-requests.txt")) { $runs += @{ Mode = 'maintain'; Minutes = 45 } }
    # Self-improvement: at most once a day (a full Opus pass at every login ate into the plan's usage on restart-heavy days)
    $si = "$dir\selfimprove-last"
    if (-not (Test-Path $si) -or ((Get-Date) - (Get-Item $si).LastWriteTime).TotalHours -ge 20) { $runs += @{ Mode = 'improve'; Minutes = 30 } }
    $tray = "$env:USERPROFILE\Documents\Messiah Tray\Messiah Tray.ahk"
    $ahk = "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"
    # reload the tray after a rollback - never from inside the test suite: the task is the owner's real tray
    function Restart-Tray { if (-not $env:PCKIT_IN_TESTS) { Stop-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue; Start-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue } }
    foreach ($r in $runs) {
        # Hidden Claude runs wait for a game to close too (up to 30 min); self-improvement then waits for another day.
        # Worst case 45 + ~5 + 30 + 45 + 30 + 30 min fits the login task's 4 h limit.
        $w0 = Get-Date; while (($g = & "$dir\game-check.ps1") -and ((Get-Date) - $w0).TotalMinutes -lt 30) { Start-Sleep 60 }
        if ($g -and $r.Mode -eq 'improve') { continue }
        $log = Join-Path $logDir ('{0:yyyyMMdd-HHmmss}-{1}.md' -f (Get-Date), $r.Mode)
        (Get-Date).ToString('o') | Set-Content $busy
        if ($r.Mode -eq 'improve') {
            (Get-Date).ToString('o') | Set-Content $si
            # Safety net: snapshot the code first; afterwards roll back any file that no longer parses
            $snap = New-Item ("$dir\selfimprove-backup\{0:yyyyMMdd-HHmmss}" -f (Get-Date)) -ItemType Directory -Force
            Copy-Item "$dir\*.ps1" $snap
            Copy-Item "$dir\skills\maintain", "$dir\skills\pc-optimize", "$dir\skills\self-improve" $snap -Recurse -ErrorAction SilentlyContinue
            if (Test-Path $tray) { Copy-Item $tray $snap }
            # the kit's test suite (developer PC: the kit repo; installed PCs: C:\PCSetupKit) - snapshotted too
            # (inside a test run the gate is off unless a test points it at a stand-in suite - no suite-in-suite loops)
            $tests = if ($env:PCKIT_TESTS_DIR) { $env:PCKIT_TESTS_DIR } elseif (-not $env:PCKIT_IN_TESTS) {
                @("$env:USERPROFILE\Documents\PC Setup Kit\PCSetupKit\tests", 'C:\PCSetupKit\tests') | Where-Object { Test-Path "$_\run-tests.ps1" } | Select-Object -First 1 }
            if ($tests) { Copy-Item $tests "$snap\tests" -Recurse }
        }
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$dir\claude-unattended.ps1`"", '-Mode', $r.Mode)
        if ($r.Mode -eq 'maintain') { $argList += '-Due', "`"$($due -join ', ')`"" }
        $p = Start-Process powershell -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -ArgumentList $argList
        if (-not $p.WaitForExit($r.Minutes * 60000)) { Stop-Process -Id $p.Id -Force; Add-Content $log "`n(stopped after $($r.Minutes) minutes)" }
        if ($r.Mode -eq 'maintain') { [void](& "$dir\maint-due.ps1" -MarkHandled) }
        if ($r.Mode -eq 'improve') {
            foreach ($f in Get-ChildItem "$dir\*.ps1") {
                $e = $null; [void][Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$e)
                if ($e -and (Test-Path "$snap\$($f.Name)")) { Copy-Item "$snap\$($f.Name)" $f.FullName -Force; Add-Content $log "`nROLLED BACK $($f.Name) (syntax error after self-improve)" }
            }
            if ((Test-Path $ahk) -and (Test-Path "$snap\Messiah Tray.ahk")) {
                $v = Start-Process $ahk -ArgumentList '/ErrorStdOut', '/Validate', "`"$tray`"" -Wait -PassThru -WindowStyle Hidden
                if ($v.ExitCode -ne 0) {
                    Copy-Item "$snap\Messiah Tray.ahk" $tray -Force; Add-Content $log "`nROLLED BACK Messiah Tray.ahk (failed to validate)"
                    Restart-Tray
                }
            }
            # Test gate: everything must still pass after self-improvement - otherwise ALL of its changes are undone
            # (scripts, skills, tray and tests; files it added are moved into the snapshot's "added" folder)
            if ($tests) {
                $tlog = Join-Path $logDir ('{0:yyyyMMdd-HHmmss}-tests.txt' -f (Get-Date))
                & powershell -NoProfile -ExecutionPolicy Bypass -File "$tests\run-tests.ps1" -Suite unit -Src $dir -TrayFile $tray *> $tlog
                $ok = $LASTEXITCODE -eq 0; $sum = Get-Content "$tests\last-run.txt" -TotalCount 1 -ErrorAction SilentlyContinue
                if ($ok) { Add-Content $log "`nTests after self-improvement: $sum" }
                else {
                    foreach ($f in Get-ChildItem "$dir\*.ps1") {
                        if (Test-Path "$snap\$($f.Name)") { Copy-Item "$snap\$($f.Name)" $f.FullName -Force }
                        else { New-Item "$snap\added" -ItemType Directory -Force | Out-Null; Move-Item $f.FullName "$snap\added\" -Force }
                    }
                    foreach ($s in 'maintain', 'pc-optimize', 'self-improve') { if (Test-Path "$snap\$s") { Copy-Item "$snap\$s\*" "$dir\skills\$s\" -Recurse -Force } }
                    if (Test-Path "$snap\Messiah Tray.ahk") { Copy-Item "$snap\Messiah Tray.ahk" $tray -Force }
                    if (Test-Path "$snap\tests") { Copy-Item "$snap\tests\*" $tests -Recurse -Force }
                    Add-Content $log "`nROLLED BACK all self-improvement changes - the test suite failed afterwards: $sum (details: $tlog)"
                    & powershell -NoProfile -ExecutionPolicy Bypass -File "$tests\run-tests.ps1" -Suite unit -Src $dir -TrayFile $tray *> "$tlog.after-rollback.txt"
                    Add-Content $log "Tests after the rollback: $(Get-Content "$tests\last-run.txt" -TotalCount 1 -ErrorAction SilentlyContinue)"
                    Restart-Tray
                }
            }
            Get-ChildItem "$dir\selfimprove-backup" -Directory | Where-Object Name -match '^\d{8}-\d{6}$' | Sort-Object Name -Descending | Select-Object -Skip 10 | Remove-Item -Recurse -Force
        }
    }
    [IO.File]::Delete($busy)
    Get-ChildItem $logDir -Filter '*.md' | Sort-Object Name -Descending | Select-Object -Skip 30 | ForEach-Object { [IO.File]::Delete($_.FullName) }
}
# once a week: what the maintenance did, as one short note in the corner (weekly-summary.ps1; not from the test suite)
if (-not $env:PCKIT_IN_TESTS -and (Test-Path "$dir\weekly-summary.ps1")) { [void](& "$dir\weekly-summary.ps1") }
# last (it changes the task this run belongs to): the daily run for PCs that stay on for days (ensure-schedule.ps1)
if (Test-Path "$dir\ensure-schedule.ps1") { $es = @(& "$dir\ensure-schedule.ps1"); if ($es) { Add-Content $report $es -Encoding UTF8 } }
$mutex.ReleaseMutex()
