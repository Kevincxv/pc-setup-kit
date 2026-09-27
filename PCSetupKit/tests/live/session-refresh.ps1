# LIVE: refresh-session.ps1 with real hidden Messiah sessions on this PC (uses a little Claude usage via haiku).
# Pretends a Claude Code update landed (a scratch file dated "now") and checks which sessions get restarted.
. "$PSScriptRoot\..\lib.ps1"
if (-not (Get-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue)) { Skip 'session refresh' 'Messiah is not installed on this PC'; Finish }
$cl = "$env:USERPROFILE\.claude"; $proj = "$cl\projects\C--WINDOWS-system32"; $claude = "$env:USERPROFILE\.local\bin\claude.exe"
$rs = "$Src\refresh-session.ps1"; . "$Src\session-lib.ps1"

function Start-Hidden([string[]]$ExtraArgs) {   # a hidden session exactly like the tray starts one
    $env:CLAUDE_ADMIN_AUTOSTART = '1'
    $p = Start-Process powershell.exe -ArgumentList @(@('-NoLogo', '-ExecutionPolicy', 'Bypass', '-File', "`"$cl\claude-admin-launch.ps1`"") + $ExtraArgs | Where-Object { $_ }) -WorkingDirectory "$env:WINDIR\System32" -WindowStyle Hidden -PassThru
    Remove-Item Env:CLAUDE_ADMIN_AUTOSTART; Start-Sleep 6; $p.Id
}
function Session($launcherPid) { Get-AdminSessions | Where-Object LauncherPid -eq $launcherPid }
function NewLaunchers($before) { , @(Get-AdminSessions | Where-Object { $_.LauncherPid -notin $before }) }
function New-Conversation([string]$Prompt, [int]$KillAfter) {
    $id = [guid]::NewGuid().ToString()
    $p = Start-Process $claude -ArgumentList '-p', "`"$Prompt`"", '--session-id', $id, '--model', 'haiku', '--dangerously-skip-permissions' -WorkingDirectory "$env:WINDIR\System32" -WindowStyle Hidden -PassThru
    if ($KillAfter) { Start-Sleep $KillAfter; Stop-Tree $p.Id } else { [void]$p.WaitForExit(120000) }
    $id
}
$listBackup = @(Get-Content "$cl\admin-sessions.txt")
$newExe = "$Work\claude-new.exe"; 'x' | Set-Content $newExe; (Get-Item $newExe).LastWriteTime = (Get-Date).AddSeconds(30)   # "an update just landed"
$oldExe = "$Work\claude-old.exe"; 'x' | Set-Content $oldExe; (Get-Item $oldExe).LastWriteTime = (Get-Date).AddDays(-5)
function Touch-New { (Get-Item $newExe).LastWriteTime = Get-Date; $newExe }   # "an update just landed" (always before any restart it causes)
$mine = @(Get-AdminSessions | ForEach-Object LauncherPid)
$cleanup = @(); $ids = @()
try {
    Write-Host "`n== never-used hidden session ==" -ForegroundColor Cyan
    $s1 = Start-Hidden; $cleanup += $s1
    $o = & $rs -Exe $oldExe -OnlyPid $s1 -WhatIf; Check 'no update on disk: nothing happens' (-not $o) ($o -join ' / ')
    $o = & $rs -Exe (Touch-New) -OnlyPid $s1 -WhatIf; Check 'update landed: would restart it as a fresh session' ($o -match 'would restart .* fresh') ($o -join ' / ')
    $before = @(Get-AdminSessions | ForEach-Object LauncherPid)
    $o = & $rs -Exe (Touch-New) -OnlyPid $s1; Start-Sleep 7
    $n = NewLaunchers $before
    Check 'old session closed' (-not (Get-Process -Id $s1 -ErrorAction SilentlyContinue))
    Check 'new session running, hidden, fresh' ($n.Count -eq 1 -and $n[0].Shown -eq $false -and $n[0].SessionId) (($n | Out-String))
    $cleanup += $n.LauncherPid
    Check 'logged' ((Get-Content "$cl\session-refresh.log" -Tail 1) -match 'Restarted the hidden session') ''

    Write-Host "`n== idle conversation ==" -ForegroundColor Cyan
    $id = New-Conversation 'Reply with exactly: OK' 0; $ids += $id
    $s2 = Start-Hidden @('--resume', $id); $cleanup += $s2
    (Get-Item "$proj\$id.jsonl").LastWriteTime = (Get-Date).AddMinutes(-20)   # resuming writes to it; backdate afterwards
    Check 'resumed session is running' ((Session $s2).SessionId -eq $id) ((Session $s2) | Out-String)
    $wt = (Get-Item "$proj\$id.jsonl").LastWriteTime; Write-Host "  (transcript last written $wt after the idle resume)"
    $o = & $rs -Exe (Touch-New) -OnlyPid $s2 -IdleMinutes 10 -WhatIf
    Check 'idle 20 min, finished turn, hidden: would restart and resume the same conversation' ($o -match "would restart .* resuming $id") ($o -join ' / ')
    $before = @(Get-AdminSessions | ForEach-Object LauncherPid)
    [void](& $rs -Exe (Touch-New) -OnlyPid $s2 -IdleMinutes 10); Start-Sleep 7
    $n = NewLaunchers $before; $cleanup += $n.LauncherPid
    Check 'restarted with --resume <same conversation>, hidden' ($n.Count -eq 1 -and $n[0].SessionId -eq $id -and $n[0].Shown -eq $false) (($n | Out-String))
    $c = Get-CimInstance Win32_Process -Filter "ProcessId=$($n[0].ClaudePid)"
    Check 'no prompt sent (idle resume uses no tokens)' ($c.CommandLine -match "--resume $id`$" -or $c.CommandLine -match "--resume $id\s*$") $c.CommandLine
    $o = & $rs -Exe $newExe -OnlyPid $n[0].LauncherPid -IdleMinutes 0 -WhatIf
    Check 'after the restart it counts as up to date (no restart loop)' (-not $o) ($o -join ' / ')

    Write-Host "`n== must NOT be restarted ==" -ForegroundColor Cyan
    (Get-Item "$proj\$id.jsonl").LastWriteTime = Get-Date
    $o = & $rs -Exe (Touch-New) -OnlyPid $n[0].LauncherPid -IdleMinutes 10 -WhatIf   # it is up to date anyway; use an older session for this:
    $id3 = New-Conversation 'Use the PowerShell tool to run exactly: ping -n 30 127.0.0.1. Then reply DONE.' 13; $ids += $id3
    $s3 = Start-Hidden @('--resume', $id3); $cleanup += $s3
    (Get-Item "$proj\$id3.jsonl").LastWriteTime = (Get-Date).AddMinutes(-30)
    $o = & $rs -Exe (Touch-New) -OnlyPid $s3 -IdleMinutes 10 -WhatIf
    Check 'conversation cut off mid-task: skipped' ($o -match 'skip .*middle of a task') ($o -join ' / ')
    $id4 = New-Conversation 'Reply with exactly: OK' 0; $ids += $id4
    $s4 = Start-Hidden @('--resume', $id4); $cleanup += $s4
    (Get-Item "$proj\$id4.jsonl").LastWriteTime = (Get-Date).AddMinutes(-3)
    $o = & $rs -Exe (Touch-New) -OnlyPid $s4 -IdleMinutes 10 -WhatIf
    Check 'used 3 minutes ago: skipped' ($o -match 'skip .*active') ($o -join ' / ')
    $o = & $rs -Exe (Touch-New) -OnlyPid $mine -WhatIf
    Check 'this session (on screen, or hidden but in use): skipped' ($o -match 'skip .*(window is open|conversation id unknown|active)') ($o -join ' / ')
    Check 'this session is still alive' ([bool](Get-Process -Id $mine[0] -ErrorAction SilentlyContinue))
}
finally {
    foreach ($p in $cleanup) { if ($p) { Stop-Tree $p } }
    foreach ($i in $ids) { if (Test-Path "$proj\$i.jsonl") { [IO.File]::Delete("$proj\$i.jsonl") } }
    $listBackup | Set-Content "$cl\admin-sessions.txt"
    $left = @(Get-AdminSessions | Where-Object { $_.LauncherPid -notin $mine })
    Check 'cleanup: only the original session remains' ($left.Count -eq 0) ($left.LauncherPid -join ',')

}
Finish
