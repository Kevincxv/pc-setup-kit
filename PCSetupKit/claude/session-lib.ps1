# Shared helpers for Claude (Admin) sessions (dot-sourced by claude-admin-launch.ps1, refresh-session.ps1,
# status.ps1 and rehearse-login.ps1).

# True when a conversation stopped mid-turn: a finished turn ends with a turn_duration record or a final (end_turn)
# answer; a cut-off one ends on a tool call/result or an unanswered prompt. Slash-command records (/exit...) count as idle.
function Test-MidTask([string]$File) {
    $tail = @(Get-Content $File -Tail 40 -Encoding UTF8 -ErrorAction SilentlyContinue); [array]::Reverse($tail)
    foreach ($l in $tail) {
        try { $j = $l | ConvertFrom-Json } catch { continue }
        if ($j.type -eq 'system' -and $j.subtype -eq 'turn_duration') { return $false }
        if ($j.type -eq 'assistant') { return $j.message.stop_reason -ne 'end_turn' }
        if ($j.type -eq 'user' -and -not $j.isMeta) {
            $c = $j.message.content
            if ($c -is [string] -and $c -match '^\s*<(command-name|local-command)') { return $false }
            return $true
        }
    }
    $false
}

function Initialize-Win { if ('ClaudeAdmin.Win' -as [type]) { return }   # compiled on first use (keeps the launcher fast)
    Add-Type -Namespace ClaudeAdmin -Name Win -MemberDefinition @'
public delegate bool EnumProc(System.IntPtr h, System.IntPtr l);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, System.IntPtr l);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsIconic(System.IntPtr h);
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)] public static extern int GetClassName(System.IntPtr h, System.Text.StringBuilder s, int n);
'@
}
# $true / $false for the launcher's console window (visible and not minimized = the owner may be using it); $null if none
function Test-SessionWindowShown([int]$ProcId) {
    Initialize-Win; $script:__shown = $null
    [void][ClaudeAdmin.Win]::EnumWindows({ param($h, $l) $p = 0; [void][ClaudeAdmin.Win]::GetWindowThreadProcessId($h, [ref]$p)
            if ($p -eq $ProcId) { $sb = New-Object Text.StringBuilder 64; [void][ClaudeAdmin.Win]::GetClassName($h, $sb, 64)
                if ($sb.ToString() -eq 'ConsoleWindowClass') { $script:__shown = [ClaudeAdmin.Win]::IsWindowVisible($h) -and -not [ClaudeAdmin.Win]::IsIconic($h) } }
            $true }, [IntPtr]::Zero)
    $script:__shown
}

# Open Claude (Admin) sessions: launcher process, its claude.exe, the conversation id and transcript
function Get-AdminSessions {
    $proj = "$env:USERPROFILE\.claude\projects\C--WINDOWS-system32"
    foreach ($l in Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object CommandLine -match 'claude-admin-launch\.ps1') {
        $c = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($l.ProcessId) AND Name='claude.exe'" | Select-Object -First 1
        $id = if ($c.CommandLine -match '--(session-id|resume)\s+"?([0-9a-fA-F-]{36})') { $Matches[2] }
        [pscustomobject]@{ LauncherPid = $l.ProcessId; ClaudePid = $c.ProcessId; ClaudeStarted = $c.CreationDate; SessionId = $id
            Transcript = if ($id) { "$proj\$id.jsonl" }; Shown = Test-SessionWindowShown $l.ProcessId }
    }
}
