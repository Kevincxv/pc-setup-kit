# What the status views show: status.ps1 (text window) and dashboard.ps1 (the Status window). Dot-source, then
# Get-KitStatus returns the sections in order: @{ Title; Lines = @(@{ Text; Level }) } with Level ok / info / warn / dim.
# -ClaudeVersion: pass a version already known (the window refreshes every few seconds; claude --version costs a process).
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
    if ($led.items) { $led.items | ForEach-Object { Ln "- $($_.Name)" }; Ln 'These finish by themselves the next time you turn the PC off; the check after that confirms it.' 'dim' }
    else { Ln 'Nothing' 'ok' }

    Sec 'Last background check'
    $m = $null   # claude-bg-maint.ps1 holds this while it runs
    if ([Threading.Mutex]::TryOpenExisting('Global\ClaudeBgMaint', [ref]$m)) { $m.Dispose(); Ln 'Background maintenance is running right now - the result shows here when it finishes' 'ok' }
    $r = @(Get-Content "$cl\maint-report.txt" -Encoding UTF8 -ErrorAction SilentlyContinue)
    if ($r) {
        Ln $r[0]
        $notable = @($r | Where-Object { $_ -match 'WARNING|FAILED|REBOOT|Reminder|Restart check|installed|Updated|re-applied' })
        if ($notable) { $notable | ForEach-Object { Ln $_ $(if ($_ -match 'WARNING|FAILED') { 'warn' } else { 'info' }) } } else { Ln 'All fine' 'ok' }
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
    Ln "App updates:       $(Next 'weekly-apps' 7)"
    Ln "Monthly cleanup:   $(Next 'monthly-cleanup' 30)"
    Ln "Quarterly check:   $(Next 'claude-quarterly' 90)  (benchmark vs setup; hardware)"
    Ln "Half-year check:   $(Next 'claude-halfyear' 180)  (dusting reminder)"
    Ln "Yearly re-optimize: $(Next 'claude-yearly' 365)"
    $st = $null; try { $st = Get-Content "$cl\self-test.json" -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch {}
    $std = [datetime]::MinValue
    if ($st -and [datetime]::TryParse("$($st.date)", [ref]$std)) {
        Ln "Self-test:         $(if ($st.ok) { "passed $($std.ToString('d')) ($($st.result))" } else { "FAILED $($std.ToString('d')) ($($st.result)$(if ($st.failed) { " in $($st.failed -join ', ')" }))" }); next $($std.AddDays(7).ToString('d')) or after a kit update" $(if ($st.ok) { 'info' } else { 'warn' })
    } else { Ln 'Self-test:         at the next login (tests the maintenance scripts, weekly)' }
    $kv = Get-Content 'C:\PCSetupKit\kit-version.txt' -TotalCount 1 -ErrorAction SilentlyContinue
    if ($kv) { Ln "Kit version:       $kv (updates itself)" 'dim' }
    $sections.ToArray()
}
