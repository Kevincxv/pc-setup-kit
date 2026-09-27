# Launcher for the "Messiah" shortcut. Opens Claude immediately with full permissions.
# Maintenance (drivers, Claude Code, PC health, weekly/monthly tasks) runs hidden in the background via
# claude-bg-maint.ps1; this launcher only shows anything notable from the last finished run, which takes no time.
# When maintenance needs judgment (a WARNING in the report, or a quarterly/half-year/yearly check is due), Claude opens
# straight into the /maintain skill so the owner never has to do maintenance themselves.
$claude = "$env:USERPROFILE\.local\bin\claude.exe"
$cl = "$env:USERPROFILE\.claude"
$report = "$cl\maint-report.txt"
$proj = "$cl\projects\C--WINDOWS-system32"
$sessList = "$cl\admin-sessions.txt"                 # ids of sessions this launcher opened (newest last)
$resumeFile = "$cl\resume-after-login.txt"           # "<session id><TAB><prompt>" left by resume-after-restart.ps1
Set-Location C:\WINDOWS\system32
$Host.UI.RawUI.WindowTitle = 'Messiah'
$cargs = @($args)

# Autostart: the tray script opens a hidden session at every login (CLAUDE_ADMIN_AUTOSTART=1). It continues the
# conversation a restart cut off (armed by resume-after-restart.ps1, or any session active <30 min before boot);
# otherwise it opens a fresh idle session. It never auto-starts maintenance - the headless run at login does that.
# Test-MidTask (was the conversation cut off mid-turn?) lives in session-lib.ps1; without it, sessions count as idle
try { . "$cl\session-lib.ps1" } catch {}
if (-not (Get-Command Test-MidTask -ErrorAction SilentlyContinue)) { function Test-MidTask { $false } }

# Login rehearsal (rehearse-login.ps1): "boot=" / "shutdown=" lines pretend the PC just started - only honored for
# 10 minutes after the file was written, so a leftover can never affect a real startup
$reh = @{}; $rf = "$cl\rehearsal.txt"
if ((Test-Path $rf) -and ((Get-Date) - (Get-Item $rf).LastWriteTime).TotalMinutes -lt 10) {
    Get-Content $rf | ForEach-Object { $k, $v = $_ -split '=', 2; if ($v) { $reh[$k.Trim()] = $v.Trim() } }
}

$auto = $env:CLAUDE_ADMIN_AUTOSTART -eq '1'
Remove-Item Env:CLAUDE_ADMIN_AUTOSTART -ErrorAction SilentlyContinue
if ($auto -and -not $cargs) {
    if (Test-Path $resumeFile) {
        $fresh = ((Get-Date) - (Get-Item $resumeFile).LastWriteTime).TotalHours -lt 24   # don't replay an old request days later
        $id, $prompt = "$(Get-Content $resumeFile -Raw)".Trim() -split "`t", 2
        Remove-Item $resumeFile -Force
        if ($fresh -and $id -and (Test-Path "$proj\$id.jsonl")) { $cargs = @('--resume', $id) + @($prompt | Where-Object { $_ }) }
    }
    else {
        # "Recent" is measured from when the PC went down, so turning it off at night and on in the morning still counts.
        # When it went down = the last thing Windows logged before this boot (a clean shutdown, or a crash/power cut).
        $boot = if ($reh.boot) { [datetime]$reh.boot } else { (Get-CimInstance Win32_OperatingSystem).LastBootUpTime }
        $down = if ($reh.shutdown) { [datetime]$reh.shutdown } else { Get-WinEvent -FilterHashtable @{ LogName = 'System'; EndTime = $boot } -MaxEvents 1 -ErrorAction SilentlyContinue |
            ForEach-Object TimeCreated }
        # never a conversation another running Claude already has open (two processes writing one conversation fork it)
        $open = "$(Get-CimInstance Win32_Process -Filter "Name='claude.exe'" | ForEach-Object CommandLine)"
        $last = Get-Content $sessList -ErrorAction SilentlyContinue | Where-Object { $_ -and -not $open.Contains($_) } |
            ForEach-Object { Get-Item "$proj\$_.jsonl" -ErrorAction SilentlyContinue } |
            Where-Object LastWriteTime -lt $boot | Sort-Object LastWriteTime | Select-Object -Last 1
        # a conversation written after the "went down" time means that time is wrong (e.g. an old log) - use the boot
        if (-not $down -or ($last -and $last.LastWriteTime -gt $down.AddMinutes(2))) { $down = $boot }
        if ($last -and ($down - $last.LastWriteTime).TotalMinutes -lt 30) {
            $cargs = @('--resume', $last.BaseName)
            if (Test-MidTask $last.FullName) {   # the owner turned the PC off while Claude was working: finish the job
                $cargs += 'The PC was turned off while you were in the middle of this. Continue where you left off and finish the task. Anything that needed a restart has completed now - verify it.'
            }
        }
    }
}

# Kick off background maintenance (skips itself if it ran in the last 30 min). Not at autostart: the
# "Claude Background Maintenance" task runs it 2 min after login.
if (-not $auto) {
    Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$cl\claude-bg-maint.ps1`""
}

# Show only what needs attention from the last run: installs, failures, crashes, reverted tweaks, reminders
$warn = $false
if (Test-Path $report) {
    $r = Get-Content $report -Encoding UTF8
    $notable = $r | Where-Object { $_ -match 'WARNING|FAILED|failed|REBOOT|exit code|DOCTOR ISSUES|re-applied|Reminder|installed|updating|Updated|timed out|hidden|Apps:|Security:|Removed|restore point|freed|TRIM' -and $_ -notmatch 'up to date' }
    if ($notable) {
        Write-Host "Maintenance ($($r[0])):" -ForegroundColor Cyan
        foreach ($l in $notable) { Write-Host "  $l" -ForegroundColor $(if ($l -match 'WARNING|FAILED|failed|timed out|DOCTOR') { 'Yellow' } else { 'DarkGray' }) }
        Write-Host ''
    }
    $warn = [bool]($r | Where-Object { $_ -match 'WARNING|FAILED|timed out|DOCTOR ISSUES' })
}

# Things only the owner can do (left by the headless maintenance run at login)
$todo = @(Get-Content "$cl\maint-todo.txt" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
if ($todo) {
    Write-Host "Needs you ($($todo.Count)):" -ForegroundColor Cyan
    foreach ($l in $todo) { Write-Host "  - $l" -ForegroundColor Yellow }
    Write-Host ''
}

# Anything for Claude to handle? (only when opened normally - not when resuming a conversation or passing a prompt,
# and not while the headless run from login is still working on it)
$autoArgs = @()
$busy = (Test-Path "$cl\maint-claude-running") -and ((Get-Date) - (Get-Item "$cl\maint-claude-running").LastWriteTime).TotalMinutes -lt 45 -and
    (Get-Item "$cl\maint-claude-running").LastWriteTime -gt (Get-CimInstance Win32_OperatingSystem).LastBootUpTime   # a marker from before a shutdown is stale
if (-not $cargs -and -not $auto -and -not $busy) {
    $due = @(& "$cl\maint-due.ps1" -MarkHandled)
    if ($due) {
        Write-Host "Maintenance due: $($due -join ', ') - Claude is taking care of it now." -ForegroundColor Cyan
        $autoArgs = @("/maintain Due now: $($due -join ', ').")
    }
    elseif ($todo) {
        $stamp = (Get-Item "$cl\maint-todo.txt").LastWriteTime.ToString('o')        # walk through each new list once
        if ((Get-Content "$cl\maint-todo.shown" -ErrorAction SilentlyContinue) -ne $stamp) {
            $stamp | Set-Content "$cl\maint-todo.shown"
            $autoArgs = @('/maintain The owner just opened Messiah. Briefly go through the open items in maint-todo.txt with them.')
        }
    }
}

# Remember which session this is, so it can be continued after a restart
$sid = $null; $idArgs = @()
if (-not ($cargs -match '^(-c|--continue|-r|--resume|--session-id)$')) { $sid = [guid]::NewGuid().ToString(); $idArgs = @('--session-id', $sid) }
elseif (($i = [array]::IndexOf($cargs, '--resume')) -ge 0 -and $i + 1 -lt $cargs.Count) { $sid = $cargs[$i + 1] }
if ($sid) { @(Get-Content $sessList -ErrorAction SilentlyContinue | Where-Object { $_ -and $_ -ne $sid } | Select-Object -Last 19) + $sid | Set-Content $sessList }

# opus = always the newest Opus; medium effort keeps usage down; falls back to Sonnet if Opus is unavailable
& $claude --dangerously-skip-permissions --model opus --effort medium --fallback-model sonnet @idArgs @cargs @autoArgs
