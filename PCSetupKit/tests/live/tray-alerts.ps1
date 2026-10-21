# LIVE + VISIBLE: the tray's corner alert. It shows a real alert on screen, so it only runs when asked
# ($env:PCKIT_VISUAL=1) and never while a game is running. The fullscreen hold is covered by game-check (game-aware).
. "$PSScriptRoot\..\lib.ps1"
if ($env:PCKIT_VISUAL -ne '1') { Skip 'tray alert on screen' 'visible test - run with $env:PCKIT_VISUAL=1'; Finish }
if (& "$Src\game-check.ps1") { Skip 'tray alert on screen' 'a game is running'; Finish }
$tp = { (Get-CimInstance Win32_Process -Filter "Name='MessiahApp.exe'" | Where-Object CommandLine -match '--tray').ProcessId }   # (the tray is the app since 10/21)
if (-not (& $tp)) { Skip 'tray alert on screen' 'the tray is not running'; Finish }
Add-Type -Namespace TA -Name W -MemberDefinition @'
public delegate bool EnumProc(System.IntPtr h, System.IntPtr l);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, System.IntPtr l);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)] public static extern int GetClassName(System.IntPtr h, System.Text.StringBuilder s, int n);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern int GetWindowLong(System.IntPtr h, int i);
'@
function NoteShown { $p = & $tp; $script:f = $false
    [void][TA.W]::EnumWindows({ param($h, $l) $q = 0; [void][TA.W]::GetWindowThreadProcessId($h, [ref]$q)
            if ($q -eq $p -and [TA.W]::IsWindowVisible($h) -and ([TA.W]::GetWindowLong($h, -20) -band 0x08000000)) { $script:f = $true }; $true }, [IntPtr]::Zero)   # (the note: a window of the tray that never takes focus)
    $script:f }
$ini = "$env:USERPROFILE\.claude\tray-notified.ini"; $todo = "$env:USERPROFILE\.claude\maint-todo.txt"
$iniBak = if (Test-Path $ini) { Get-Content $ini -Raw }; $todoBak = if (Test-Path $todo) { Get-Content $todo -Raw -Encoding UTF8 }
try {
    'Test alert from the PC Setup Kit tests - nothing to do.' | Set-Content $todo -Encoding UTF8
    $fg = [TA.W]::GetForegroundWindow()
    $t0 = Get-Date; while (-not (NoteShown) -and ((Get-Date) - $t0).TotalSeconds -lt 40) { Start-Sleep 2 }
    Check 'an alert appears for a new to-do item' (NoteShown) ''
    Check 'it did not take focus' ([TA.W]::GetForegroundWindow() -eq $fg) ''
    $t0 = Get-Date; while ((NoteShown) -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Start-Sleep 2 }
    Check 'it closes by itself' (-not (NoteShown)) ''
    Start-Sleep 35
    Check 'the same item is not alerted twice' (-not (NoteShown)) ''
}
finally {
    if ($null -ne $todoBak) { [IO.File]::WriteAllText($todo, $todoBak, (New-Object Text.UTF8Encoding $false)) } else { Clear-Path $todo }
    # the restored to-do file has a new date: mark it as already shown so the owner doesn't get a repeat alert
    $st = (Get-Item $todo -ErrorAction SilentlyContinue).LastWriteTime
    $lines = @(if ($null -ne $iniBak) { $iniBak -split "`r?`n" | Where-Object { $_ -and $_ -notmatch '^todo=' } } else { '[shown]' })
    if ($st) { $lines += "todo=$($st.ToString('yyyyMMddHHmmss'))" }
    $lines | Set-Content $ini
}
Finish
