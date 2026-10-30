# What the status views show: status.ps1 (text window; the app, MessiahApp.exe, has its own copy in C#). Dot-source, then
# Get-KitStatus returns the sections in order: @{ Title; Lines = @(@{ Text; Level }) } with Level ok / info / warn / dim.
# -ClaudeVersion: pass a version already known (the window refreshes every few seconds; claude --version costs a process).

# What a background check looked at, from its report's 'Label: ...' lines - under 'All fine', which alone said nothing
# (10/28; the app's Data.Looked, the same words). 'Looked at drivers, Claude Code, crashes, your tweaks and app updates.'; '' without any.
function Get-KitLooked([string[]]$Report) {
    $said = New-Object Collections.Generic.List[string]
    foreach ($x in $Report) {
        if ("$x" -cnotmatch '^([A-Za-z][A-Za-z .]{1,28}):\s') { continue }
        $k = $Matches[1].Trim()
        $w = if ($k -match 'driver|^NVIDIA$|^AMD$|^Intel$') { 'drivers' } elseif ($k -ceq 'Claude Code') { 'Claude Code' } elseif ($k -ceq 'Tweaks') { 'your tweaks' }
            elseif ($k -ceq 'Apps') { 'app updates' } elseif ($k -ceq 'Security') { 'virus protection' } elseif ($k -ceq 'Backup') { 'your settings backup' }
            elseif ($k -cmatch 'tuning$|^Next$|^Updated app$|^Restart check$|^Reminder$') { $null } else { $k.ToLowerInvariant() }
        if ($w -and -not $said.Contains($w)) { $said.Add($w) }
    }
    if ($said.Count -eq 0) { return '' }
    'Looked at ' + $(if ($said.Count -eq 1) { $said[0] } else { ($said[0..($said.Count - 2)] -join ', ') + ' and ' + $said[$said.Count - 1] }) + '.'
}

function Get-KitStatus([string]$ClaudeVersion) {
    $cl = "$env:USERPROFILE\.claude"
    $ai = if (Test-Path "$cl\ai-enabled.ps1") { & "$cl\ai-enabled.ps1" } else { $true }
    if ($ai) { . "$cl\session-lib.ps1" }
    $sections = New-Object Collections.ArrayList
    function Sec($t) { [void]$sections.Add(@{ Title = $t; Lines = New-Object Collections.ArrayList }) }
    function Ln($t, $lv = 'info') { [void]$sections[$sections.Count - 1].Lines.Add(@{ Text = "$t"; Level = $lv }) }
    $state = @{}; try { (Get-Content "$cl\maint-state.json" -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).PSObject.Properties | ForEach-Object { $state[$_.Name] = $_.Value } } catch {}
    function Next($key, $days) { $d = [datetime]::MinValue; if ([datetime]::TryParse("$($state[$key])", [ref]$d)) { $n = $d.AddDays($days); if ($n -lt (Get-Date)) { 'due now' } else { $n.ToString('MMM d, yyyy') } } else { 'due now' } }

    if ($ai) {
        Sec 'Messiah'
        $ver = if ($ClaudeVersion) { $ClaudeVersion } else { ((& "$env:USERPROFILE\.local\bin\claude.exe" --version 2>$null) -split ' ')[0] }
        Ln "Claude Code $ver"
        $sess = @(Get-AdminSessions)
        if (-not $sess) { Ln 'No session open (the tray opens one at every login; click the tray icon to open one now)' 'warn' }
        foreach ($s in $sess) { Ln "Session $(if ($s.SessionId) { $s.SessionId.Substring(0, 8) } else { '(continued)' }): $(if ($s.Shown) { 'open on screen' } else { 'hidden in the tray' }), $(if ($s.ClaudeStarted) { "running since $($s.ClaudeStarted.ToString('g'))" } else { 'starting' })" }
    }

    Sec 'Needs you'
    $todo = @(Get-Content "$cl\maint-todo.txt" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
    if ($todo) { $todo | ForEach-Object { Ln "- $_" 'warn' } } else { Ln 'Nothing' 'ok' }

    Sec 'Waiting for your next shutdown or restart'
    $led = $null; try { $led = Get-Content "$cl\restart-ledger.json" -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch {}
    # (when, by Restart at night - kit-options nightrestart, default on except where publish-kit.ps1 is; the app's Data.RestartFinish)
    $night = @(Get-Content "$cl\kit-options.txt" -ErrorAction SilentlyContinue) -match '^\s*nightrestart\s*=' | Select-Object -First 1
    $night = if ($night) { ($night -split '=', 2)[1].Trim() -eq 'on' } else { -not (Test-Path "$cl\publish-kit.ps1") }
    $fin = if ($night) { 'These finish by themselves at the next restart: one at night while the PC is unused (Settings > Restart at night), or when you turn it off. The check after that confirms it.' }
        else { 'These finish by themselves the next time you turn the PC off or restart. The check after that confirms it.' }
    if ($led.items) { $led.items | ForEach-Object { Ln "- $($_.Name)" }; Ln $fin 'dim' }
    else { Ln 'Nothing' 'ok' }

    Sec 'Last background check'
    $m = $null   # claude-bg-maint.ps1 holds this while it runs
    # (not under tests: the self-test runs inside the maintenance, which would change what the pages show)
    if (-not $env:PCKIT_IN_TESTS -and [Threading.Mutex]::TryOpenExisting('Global\ClaudeBgMaint', [ref]$m)) { $m.Dispose(); Ln 'Background maintenance is running right now - the result shows here when it finishes' 'ok' }
    $r = @(Get-Content "$cl\maint-report.txt" -Encoding UTF8 -ErrorAction SilentlyContinue)
    if ($r) {
        Ln $r[0]
        $notable = @($r | Where-Object { $_ -match 'WARNING|FAILED|REBOOT|Reminder|Restart check|installed|Updated|re-applied|rolled back|Driver guard' })
        if ($notable) { $notable | ForEach-Object { Ln $_ $(if ($_ -match 'WARNING|FAILED') { 'warn' } else { 'info' }) } }
        else { Ln 'All fine' 'ok'; $looked = Get-KitLooked $r; if ($looked) { Ln $looked 'dim' } }
    } else { Ln 'No report yet' }

    if ($ai) {
        Sec 'Hidden Claude maintenance (about 2 minutes after each login)'
        $busy = "$cl\maint-claude-running"
        $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        if ((Test-Path $busy) -and (Get-Item $busy).LastWriteTime -gt $boot) { Ln 'Running now (tray menu > Watch maintenance live)' 'warn' }
        $last = Get-ChildItem "$cl\maint-claude-log\*.md" -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
        if ($last) { Ln "Last run: $($last.LastWriteTime.ToString('g')) ($($last.BaseName -replace '^\d+-\d+-?', ''))" }
        $si = Get-Item "$cl\selfimprove-last" -ErrorAction SilentlyContinue
        if ($si) { Ln "Self-improvement: last $($si.LastWriteTime.ToString('g')); next at the first login after $($si.LastWriteTime.AddHours(20).ToString('g'))" }
    }

    Sec 'Scheduled checks'
    Ln "App updates:       $(Next 'weekly-apps' 7)  (every week)"
    Ln "Cleanup:           $(Next 'monthly-cleanup' 30)  (every month: temporary files, old drivers, a restore point)"
    # (10/27: the app's plain names - were Quarterly check / Half-year check / Yearly re-optimize)
    Ln "Benchmark:         $(Next 'claude-quarterly' 90)  (every 3 months, compared with day one)"
    Ln "Dust reminder:     $(Next 'claude-halfyear' 180)  (every 6 months)"
    Ln "Full tune-up:      $(Next 'claude-yearly' 365)  (every year: the whole setup again)"
    $st = $null; try { $st = Get-Content "$cl\self-test.json" -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch {}
    $std = [datetime]::MinValue
    if ($st -and [datetime]::TryParse("$($st.date)", [ref]$std)) {
        # (10/27: when first, like the other rows - was 'passed 10/26 (...); next ... or after a kit update')
        # (later 10/27: a gamer's words, as the app - was 'after a kit update - last passed Oct 24: 1652 passed, 0 failed')
        # (10/28: 'Self-check', and what it is; no count when it passed - was 'all 1652 checks passed')
        $said = "$($st.result)"
        if ($said -match '^(\d+) passed, (\d+) failed$') { $said = if ($st.ok) { 'all fine' } else { "$($Matches[2]) checks failed" } }
        # (later 10/28: the last run is its own sentence, as the app - was '(... after updates - last run Oct 25: all fine)')
        $last = "Last run $($std.ToString('MMM d', [Globalization.CultureInfo]::InvariantCulture)): $said$(if (-not $st.ok -and $st.failed) { " in $($st.failed -join ', ')" })."
        Ln "Self-check:        $(if ($std.AddDays(7) -lt (Get-Date)) { 'at the next login' } else { $std.AddDays(7).ToString('MMM d, yyyy', [Globalization.CultureInfo]::InvariantCulture) })  (the app tests itself every week and after updates). $last" $(if ($st.ok) { 'info' } else { 'warn' })
    } else { Ln 'Self-check:        at the next login  (the app tests itself every week)' }
    $kv = Get-Content 'C:\PCSetupKit\kit-version.txt' -TotalCount 1 -ErrorAction SilentlyContinue
    if ($kv) { Ln "Kit version:       $kv (updates itself)" 'dim' }
    $sections.ToArray()
}
