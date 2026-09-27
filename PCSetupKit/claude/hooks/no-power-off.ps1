# PreToolUse hook (Bash/PowerShell): Claude never shuts down, restarts or logs off this PC - the owner's rule.
# Maintenance finishes everything it can and leaves restart-only work pending; it completes whenever the owner
# turns the PC off or restarts it themselves, and the tray reopens the conversation afterwards.
# Exit 2 = block the command and show the reason to Claude.
$in = [Console]::In.ReadToEnd()
try { $cmd = ($in | ConvertFrom-Json).tool_input.command } catch { exit 0 }
if (-not $cmd) { exit 0 }
$c = $cmd -replace '[`^]', ''   # ignore PowerShell/cmd escape characters used to dodge a match
$bad = @(
    '(^|[\s;&|("''{\\/])(shutdown|shutdown\.exe)["'']?\s+[^\r\n;&|]*[/-](r|s|g|sg|p|h|l|e|hybrid|fw)\b'   # shutdown /r /s /g /p /h /l ... (not /a = abort)
    '\b(Restart|Stop)-Computer\b'
    '\bWin32Shutdown(Tracker)?\b|\bInitiateSystemShutdown(Ex)?\b|\bInitiateShutdown\b|\bExitWindowsEx\b|\bNtShutdownSystem\b|\bNtRaiseHardError\b'
    '\.(Reboot|Shutdown)\(\s*\)|-MethodName\s+["'']?(Reboot|Shutdown|Win32Shutdown(Tracker)?)\b'   # WMI/CIM Win32_OperatingSystem calls
    '\bwpeutil\s+(reboot|shutdown)\b'
    '\blogoff(\.exe)?\b|\btsdiscon\b'
    '(taskkill|Stop-Process|kill)\b[^\r\n]*\b(wininit|csrss|smss|winlogon)\b'   # killing these crashes/reboots Windows
)
if ($bad | Where-Object { $c -match $_ }) {
    [Console]::Error.WriteLine("BLOCKED by the owner's rule: Claude never shuts down, restarts or logs off this PC. " +
        "Finish everything that can be done now. For work that needs a restart, leave it pending (Windows completes it at the owner's next " +
        "shutdown or restart; fast startup is off), and if you need to continue afterwards run " +
        "& `"`$env:USERPROFILE\.claude\resume-after-restart.ps1`" -Prompt `"<what to verify>`" - the tray reopens this conversation hidden after the next login. " +
        "Tell the owner in one line that it finishes the next time they turn the PC off or restart it, whenever suits them. For a BIOS visit, tell them to press F2 or Del at the logo when they next start the PC.")
    exit 2
}
exit 0
