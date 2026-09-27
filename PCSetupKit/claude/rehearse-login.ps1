# Login rehearsal: tests what happens after a restart WITHOUT restarting. Runs the real chain exactly as Windows does at
# sign-in (the "Messiah Tray" scheduled task -> tray script -> hidden launcher -> real claude.exe) with a
# rehearsal.txt that makes the launcher and tray believe the PC just started. Sessions already open (like the one
# running this test) are ignored for the duration. Each scenario uses its own small throwaway session.
#   midtask : a session was cut off mid-task by a shutdown -> reopened hidden and told to finish (checks it does)
#   armed   : an agent armed resume-after-restart.ps1 -> reopened hidden with that prompt (checks it answers)
#   fresh   : nothing to resume -> a fresh idle hidden session (no prompt, no tokens)
# Usage (elevated): & "$env:USERPROFILE\.claude\rehearse-login.ps1" [-Scenario midtask,armed,fresh]
param([ValidateSet('midtask', 'armed', 'fresh')][string[]]$Scenario = @('midtask', 'armed', 'fresh'))
$cl = "$env:USERPROFILE\.claude"; $proj = "$cl\projects\C--WINDOWS-system32"; $claude = "$env:USERPROFILE\.local\bin\claude.exe"
$sessList = "$cl\admin-sessions.txt"; $rf = "$cl\rehearsal.txt"
$script:pass = 0; $script:fail = 0
function Check($name, $cond, $detail) { if ($cond) { $script:pass++; Write-Host "  PASS  $name" -ForegroundColor Green } else { $script:fail++; Write-Host "  FAIL  $name  $detail" -ForegroundColor Red } }
Add-Type -Namespace RH -Name W -MemberDefinition @'
public delegate bool EnumProc(System.IntPtr h, System.IntPtr l);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, System.IntPtr l);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)] public static extern int GetClassName(System.IntPtr h, System.Text.StringBuilder s, int n);
'@
function Get-Launchers { @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object CommandLine -match 'claude-admin-launch\.ps1') }
function Test-WindowVisible([int]$ProcId) {   # the launcher's console window (hidden = in the tray)
    $script:vis = $null
    [void][RH.W]::EnumWindows({ param($h, $l) $p = 0; [void][RH.W]::GetWindowThreadProcessId($h, [ref]$p)
            $sb = New-Object Text.StringBuilder 64; [void][RH.W]::GetClassName($h, $sb, 64)
            if ($p -eq $ProcId -and $sb.ToString() -eq 'ConsoleWindowClass') { $script:vis = [RH.W]::IsWindowVisible($h) }; $true }, [IntPtr]::Zero)
    $script:vis
}
function Stop-Tree([int]$ProcId) {
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcId" | ForEach-Object { Stop-Tree $_.ProcessId }
    Stop-Process -Id $ProcId -Force -ErrorAction SilentlyContinue
}
function Restart-Tray { Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" | Where-Object CommandLine -match 'Messiah Tray\.ahk' | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Start-ScheduledTask 'Messiah Tray' }
# A small real session made headless with a cheap model; -KillAfter cuts it off mid-task like a shutdown would
function New-TestSession([string]$Prompt, [int]$KillAfter) {
    $id = [guid]::NewGuid().ToString()
    $p = Start-Process $claude -ArgumentList '-p', "`"$Prompt`"", '--session-id', $id, '--model', 'haiku', '--dangerously-skip-permissions' -WorkingDirectory "$env:WINDIR\System32" -WindowStyle Hidden -PassThru
    if ($KillAfter) { Start-Sleep $KillAfter; Stop-Tree $p.Id } else { [void]$p.WaitForExit(120000) }
    $id
}
function Wait-Transcript([string]$Id, [string]$Text, [int]$Seconds) {
    $t = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $t) {   # only Claude's own replies count (the prompt contains the marker too)
        foreach ($l in @(Get-Content "$proj\$Id.jsonl" -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            if ($l -notmatch '"type":"assistant"') { continue }
            try { $j = $l | ConvertFrom-Json } catch { continue }
            if ($j.message.content | Where-Object { $_.type -eq 'text' -and $_.text -match [regex]::Escape($Text) }) { return $true }
        }
        Start-Sleep 3
    }
    $false
}

$keep = Get-Launchers | ForEach-Object ProcessId          # sessions open now (this one) stay open and are ignored
$listBackup = @(Get-Content $sessList -ErrorAction SilentlyContinue)
Write-Host "Login rehearsal - no restart. Open sessions left alone: $($keep -join ', ')" -ForegroundColor Cyan
try {
    foreach ($s in $Scenario) {
        Write-Host "`n[$s]" -ForegroundColor Cyan
        $test = $null; $expect = $null
        if ($s -eq 'midtask') {
            Write-Host '  preparing: a session that gets cut off while running a command...'
            $test = New-TestSession 'Use the PowerShell tool to run exactly: ping -n 25 127.0.0.1. (Claude Code refuses long foreground sleeps.) After it finishes, reply with exactly: REHEARSAL-MIDTASK-FINISHED' 14
            $expect = 'REHEARSAL-MIDTASK-FINISHED'
        }
        elseif ($s -eq 'armed') {
            Write-Host '  preparing: a finished session whose agent armed resume-after-restart...'
            $test = New-TestSession 'Reply with exactly: READY' 0
            $env:CLAUDE_CODE_SESSION_ID = $test
            & "$cl\resume-after-restart.ps1" -Prompt 'Login rehearsal: reply with exactly REHEARSAL-ARMED-OK and nothing else.' | Out-Null
            Remove-Item Env:CLAUDE_CODE_SESSION_ID
            $expect = 'REHEARSAL-ARMED-OK'
        }
        $shutdown = (Get-Date).AddSeconds(-90); $boot = (Get-Date).AddSeconds(-60)
        if ($test) {
            if (-not (Test-Path "$proj\$test.jsonl")) { Check 'test session was created' $false "no transcript for $test"; continue }
            (Get-Item "$proj\$test.jsonl").LastWriteTime = $shutdown.AddMinutes(-3)   # it was last active before the "shutdown"
            $test | Set-Content $sessList   # only the test session is offered: real ones (like the one running this) stay out
        } else { '' | Set-Content $sessList }
        "boot=$($boot.ToString('o'))", "shutdown=$($shutdown.ToString('o'))", "ignorepids=$($keep -join ',')" | Set-Content $rf

        Restart-Tray   # exactly what Windows runs at sign-in
        $new = $null; $t = (Get-Date).AddSeconds(25)
        while (-not $new -and (Get-Date) -lt $t) { Start-Sleep 1; $new = Get-Launchers | Where-Object { $_.ProcessId -notin $keep } | Select-Object -First 1 }
        Check 'tray started a session by itself (like at login)' $new
        if (-not $new) { continue }
        Start-Sleep 4
        $c = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($new.ProcessId) AND Name='claude.exe'" | Select-Object -First 1
        Check 'session window is hidden (in the tray)' ((Test-WindowVisible $new.ProcessId) -eq $false) "visible: $(Test-WindowVisible $new.ProcessId)"
        Check 'real claude.exe is running in it' $c
        $cmd = "$($c.CommandLine)"
        if ($s -eq 'fresh') {
            Check 'fresh session: new --session-id, nothing resumed, no prompt' (($cmd -match '--session-id') -and $cmd -notmatch '--resume' -and $cmd -notmatch '"[^"]*\s[^"]*"\s*$') $cmd
        } else {
            Check "resumed the right conversation ($($test.Substring(0,8)))" ($cmd -match "--resume $test") $cmd
            if ($s -eq 'midtask') { Check 'told to continue and finish' ($cmd -match 'turned off while you were in the middle') $cmd }
            if ($s -eq 'armed') { Check "the armed prompt was passed" ($cmd -match 'Login rehearsal: reply') $cmd; Check 'resume request consumed' (-not (Test-Path "$cl\resume-after-login.txt")) }
            Write-Host "  waiting for Claude to answer in the hidden session (up to 3 min)..."
            Check "Claude actually did it: '$expect' in the conversation" (Wait-Transcript $test $expect 180)
        }
        Stop-Tree $new.ProcessId   # close this scenario's hidden session (and any command Claude was running)
        if ($test) { [IO.File]::Delete("$proj\$test.jsonl") }
    }
}
finally {
    [IO.File]::Delete($rf); if (Test-Path "$cl\resume-after-login.txt") { [IO.File]::Delete("$cl\resume-after-login.txt") }
    $listBackup | Set-Content $sessList
    Restart-Tray   # back to normal (it sees the open session and starts nothing)
    Start-Sleep 5
    $extra = @(Get-Launchers | Where-Object { $_.ProcessId -notin $keep })
    Check 'cleanup: tray back to normal, no extra sessions left' ($extra.Count -eq 0) "extra: $($extra.ProcessId -join ',')"
    Write-Host "`nRehearsal: $script:pass passed, $script:fail failed" -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
}
