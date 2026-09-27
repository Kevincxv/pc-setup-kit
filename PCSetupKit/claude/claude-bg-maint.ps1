# Background maintenance for the "Claude (Admin)" launcher. Runs elevated and hidden, so Claude never waits on it.
# Started by the launcher (fire-and-forget) and by the "Claude Background Maintenance" task at logon.
# Runs the driver check, Claude Code maintenance and PC health check in parallel and writes a report
# that the launcher shows at the next start.
param([switch]$Force, [switch]$Unattended)   # -Unattended: run at login by the scheduled task; also lets Claude do /maintain headless
$ErrorActionPreference = 'Continue'
$dir = "$env:USERPROFILE\.claude"
$report = "$dir\maint-report.txt"

# One run at a time; skip if the last run was recent (launching Claude twice in a row shouldn't redo everything)
$mutex = New-Object Threading.Mutex($false, 'Global\ClaudeBgMaint')
if (-not $mutex.WaitOne(0)) { exit }
if (-not $Force -and (Test-Path $report) -and ((Get-Date) - (Get-Item $report).LastWriteTime).TotalMinutes -lt 30) { exit }

# Game-aware: never start maintenance under a running game (driver installs black the screen, updates stutter it).
# Wait up to 45 min for it to close; after that the heavy steps each hold themselves (they check game-check too).
$gameNote = $null; $w0 = Get-Date
while (($g = & "$dir\game-check.ps1") -and ((Get-Date) - $w0).TotalMinutes -lt 45) { Start-Sleep 60 }
$waited = [int]((Get-Date) - $w0).TotalMinutes
if ($g) { $gameNote = "Game: $g still running after $waited min - heavy steps held until the next run" }
elseif ($waited -ge 1) { $gameNote = "Game: waited $waited min for it to close before starting" }
$start = Get-Date
$jobs = foreach ($j in @(
        @{ Name = 'Drivers'; Script = 'driver-check.ps1'; Timeout = 1200 },
        @{ Name = 'Claude Code'; Script = 'claude-maint.ps1'; Timeout = 300 },    # its own steps can take 120+45+45 s (+45 per plugin)
        @{ Name = 'PC health'; Script = 'health-check.ps1'; Timeout = 900 },     # long limit: first crash-dump analysis downloads symbols
        @{ Name = 'Periodic'; Script = 'periodic-maint.ps1'; Timeout = 3600 },   # weekly app updates, monthly cleanup (only when due)
        @{ Name = 'Kit'; Script = 'kit-update.ps1'; Timeout = 300 })) {          # PCs installed from the kit: newest published version
    if (-not (Test-Path "$dir\$($j.Script)")) { continue }
    $out = Join-Path $env:TEMP "claude-bg-$($j.Script).log"
    $p = Start-Process powershell -WindowStyle Hidden -PassThru -RedirectStandardOutput $out `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$dir\$($j.Script)`""
    [pscustomobject]@{ Name = $j.Name; Proc = $p; Out = $out; Deadline = $start.AddSeconds($j.Timeout) }
}
foreach ($j in $jobs) {
    $left = [int]($j.Deadline - (Get-Date)).TotalMilliseconds
    if ($left -le 0 -or -not $j.Proc.WaitForExit($left)) { Stop-Process -Id $j.Proc.Id -Force -ErrorAction SilentlyContinue; $j | Add-Member TimedOut $true }
}

$lines = @("Checked $((Get-Date).ToString('g')) in $([int]((Get-Date) - $start).TotalSeconds)s") + @($gameNote | Where-Object { $_ })
foreach ($j in $jobs) {
    $out = @(if (Test-Path $j.Out) { Get-Content $j.Out | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }; Remove-Item $j.Out -Force })
    if ($j.TimedOut) { $out = @('WARNING: timed out') + $out }
    if ($out) { $lines += "[$($j.Name)]"; $lines += $out }   # a job with nothing to say (e.g. no kit update) leaves no empty section
}
# Write to a temp file then swap, so the launcher never reads a half-written report
$lines | Set-Content "$report.tmp" -Encoding utf8
Move-Item "$report.tmp" $report -Force
# Keep the last 30 reports so Claude can look back at when something started
$hist = New-Item "$dir\maint-history" -ItemType Directory -Force
Copy-Item $report (Join-Path $hist ("report-{0:yyyyMMdd-HHmmss}.txt" -f (Get-Date)))
Get-ChildItem $hist -Filter 'report-*.txt' | Sort-Object Name -Descending | Select-Object -Skip 30 | ForEach-Object { [IO.File]::Delete($_.FullName) }

# At login: let Claude work headless (no window). First /maintain if anything needs it, then the /self-improve pass
# (at most once a day). Output in .claude\maint-claude-log; the tray's "Watch maintenance live" follows the running session.
if ($Unattended) {
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
    $tray = "$env:USERPROFILE\Documents\Claude Admin Tray\Claude Admin Tray.ahk"
    $ahk = "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"
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
            if ((Test-Path $ahk) -and (Test-Path "$snap\Claude Admin Tray.ahk")) {
                $v = Start-Process $ahk -ArgumentList '/ErrorStdOut', '/Validate', "`"$tray`"" -Wait -PassThru -WindowStyle Hidden
                if ($v.ExitCode -ne 0) {
                    Copy-Item "$snap\Claude Admin Tray.ahk" $tray -Force; Add-Content $log "`nROLLED BACK Claude Admin Tray.ahk (failed to validate)"
                    Stop-ScheduledTask 'Claude Admin Tray' -ErrorAction SilentlyContinue; Start-ScheduledTask 'Claude Admin Tray' -ErrorAction SilentlyContinue
                }
            }
            Get-ChildItem "$dir\selfimprove-backup" -Directory | Where-Object Name -match '^\d{8}-\d{6}$' | Sort-Object Name -Descending | Select-Object -Skip 10 | Remove-Item -Recurse -Force
        }
    }
    [IO.File]::Delete($busy)
    Get-ChildItem $logDir -Filter '*.md' | Sort-Object Name -Descending | Select-Object -Skip 30 | ForEach-Object { [IO.File]::Delete($_.FullName) }
}
$mutex.ReleaseMutex()
