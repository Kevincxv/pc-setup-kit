# Keeps the always-on Claude (Admin) session on the newest Claude Code. Claude Code updates itself, but a session that
# is already running keeps the old version until it restarts - and the tray's session runs all the time. Run every
# 15 min by the tray (elevated, hidden). A session is only restarted when that's invisible to the owner:
# window hidden in the tray (or minimized), no activity for 10+ minutes, and not in the middle of a task.
# It comes back hidden with the same conversation (--resume), no prompt, so no tokens are used.
# -Exe / -OnlyPid / -IdleMinutes: test overrides. -WhatIf: only say what would happen.
param([string]$Exe = "$env:USERPROFILE\.local\bin\claude.exe", [int[]]$OnlyPid, [int]$IdleMinutes = 10, [switch]$WhatIf)
$cl = "$env:USERPROFILE\.claude"
. "$cl\session-lib.ps1"
$log = "$cl\session-refresh.log"
function Log($m) { $l = "$((Get-Date).ToString('g'))  $m"; @(@(Get-Content $log -ErrorAction SilentlyContinue) + $l | Select-Object -Last 100) | Set-Content $log -Encoding UTF8; $l }
function Stop-Tree([int]$ProcId) {
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcId" | ForEach-Object { Stop-Tree $_.ProcessId }
    Stop-Process -Id $ProcId -Force -ErrorAction SilentlyContinue
}

# When did the newest Claude Code land on disk? (the bin copy, or a newer version folder not swapped in yet)
$newest = @(Get-Item $Exe -ErrorAction SilentlyContinue) + @(Get-ChildItem "$env:USERPROFILE\.local\share\claude\versions" -File -ErrorAction SilentlyContinue) |
    Sort-Object LastWriteTime | Select-Object -Last 1 -ExpandProperty LastWriteTime
if (-not $newest) { return }

foreach ($s in Get-AdminSessions) {
    if ($OnlyPid -and $s.LauncherPid -notin $OnlyPid) { continue }
    if (-not $s.ClaudePid -or $s.ClaudeStarted -ge $newest) { continue }                  # already on the newest version
    $why = if ($s.Shown) { 'window is open' }
    elseif (-not $s.SessionId) { 'conversation id unknown (started with --continue)' }
    elseif ((Test-Path $s.Transcript) -and ((Get-Date) - (Get-Item $s.Transcript).LastWriteTime).TotalMinutes -lt $IdleMinutes) { 'active in the last few minutes' }
    elseif ((Test-Path $s.Transcript) -and (Test-MidTask $s.Transcript)) { 'in the middle of a task' }
    if ($why) { if ($WhatIf) { "skip $($s.LauncherPid): $why" }; continue }

    $resume = if (Test-Path $s.Transcript) { @('--resume', $s.SessionId) } else { @() }      # never used = nothing to resume
    if ($WhatIf) { "would restart $($s.LauncherPid) on the new version $(if ($resume) { "resuming $($s.SessionId)" } else { 'as a fresh session' })"; continue }
    Stop-Tree $s.LauncherPid
    $env:CLAUDE_ADMIN_AUTOSTART = '1'   # hidden autostart mode: no maintenance prompts, no second background run
    $argList = @(@('-NoLogo', '-ExecutionPolicy', 'Bypass', '-File', "`"$cl\claude-admin-launch.ps1`"") + $resume | Where-Object { $_ })   # $resume may be $null
    $p = Start-Process powershell.exe -ArgumentList $argList -WorkingDirectory "$env:WINDIR\System32" -WindowStyle Hidden -PassThru
    Remove-Item Env:CLAUDE_ADMIN_AUTOSTART
    Log "Restarted the hidden session on the new Claude Code ($(if ($resume) { "same conversation $($s.SessionId)" } else { 'fresh' })): pid $($s.LauncherPid) -> $($p.Id)"
}
