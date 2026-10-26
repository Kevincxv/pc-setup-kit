# PreToolUse hook (Bash/PowerShell): Claude never shuts down, restarts or logs off this PC on its own - the owner's rule.
# Maintenance finishes everything it can and leaves restart-only work pending; it completes whenever the owner
# turns the PC off or restarts it themselves, and the tray reopens the conversation afterwards.
# Owner's permission (10/23, the owner's request "restart me to my BIOS"): a plain shutdown.exe or Restart-/Stop-Computer
# is still blocked, but the owner is asked in a popup on the screen (Yes / No, No by itself after 60 s). Only a click on
# Yes does it - 10 s later, by the popup itself, with a fixed command (restart, restart into the BIOS, shut down,
# hibernate, sign out), never the command text. So Claude can't give itself permission, a hidden run with nobody at
# the PC does nothing, and the hook never waits (a hook that runs past its time limit would let the command through).
# The other ways (WMI/API calls, logoff, killing system processes) stay blocked outright - only used to dodge this rule.
# Exit 2 = block the command and show the reason to Claude.
# -Answer yes / no / none: tests only - nothing is shown or run, the popup's outcome is printed (none = nobody answered).
param([ValidateSet('', 'yes', 'no', 'none')][string]$Answer = '')
$in = [Console]::In.ReadToEnd()
try { $cmd = ($in | ConvertFrom-Json).tool_input.command } catch { exit 0 }
if (-not $cmd) { exit 0 }
$c = $cmd -replace '[`^]', ''   # ignore PowerShell/cmd escape characters used to dodge a match
$ask = @(
    '(^|[\s;&|("''{\\/])(shutdown|shutdown\.exe)["'']?\s+[^\r\n;&|]*[/-](r|s|g|sg|p|h|l|e|hybrid|fw)\b'   # shutdown /r /s /g /p /h /l ... (not /a = abort)
    '\b(Restart|Stop)-Computer\b'
)
$never = @(
    '\bWin32Shutdown(Tracker)?\b|\bInitiateSystemShutdown(Ex)?\b|\bInitiateShutdown\b|\bExitWindowsEx\b|\bNtShutdownSystem\b|\bNtRaiseHardError\b'
    '\.(Reboot|Shutdown)\(\s*\)|-MethodName\s+["'']?(Reboot|Shutdown|Win32Shutdown(Tracker)?)\b'   # WMI/CIM Win32_OperatingSystem calls
    '\bwpeutil\s+(reboot|shutdown)\b'
    '\blogoff(\.exe)?\b|\btsdiscon\b'
    '(taskkill|Stop-Process|kill)\b[^\r\n]*\b(wininit|csrss|smss|winlogon)\b'   # killing these crashes/reboots Windows
)
$isAsk = [bool]($ask | Where-Object { $c -match $_ }); $isNever = [bool]($never | Where-Object { $c -match $_ })
if (-not $isAsk -and -not $isNever) { exit 0 }
$why = "BLOCKED by the owner's rule: Claude never shuts down, restarts or logs off this PC on its own. " +
    "Finish everything that can be done now. For work that needs a restart, leave it pending (Windows completes it at the owner's next " +
    "shutdown or restart; fast startup is off), and if you need to continue afterwards run " +
    "& `"`$env:USERPROFILE\.claude\resume-after-restart.ps1`" -Prompt `"<what to verify>`" - the tray reopens this conversation hidden after the next login. " +
    "Tell the owner in one line that it finishes the next time they turn the PC off or restart it, whenever suits them. For a BIOS visit, tell them to press F2 or Del at the logo when they next start the PC."
if ($isNever) {
    [Console]::Error.WriteLine("$why Only a plain shutdown.exe command (e.g. shutdown /r /fw) can be allowed, and only by the owner clicking Yes on a popup - use that when the owner asks for it.")
    exit 2
}
# what the owner is asked about, and the fixed command a Yes runs
$what, $run = if ($c -match '[/-]fw\b') { 'restart this PC into the BIOS', '/r /fw /t 10' }
    elseif ($c -match '[/-](r|g)\b|Restart-Computer') { 'restart this PC', '/r /t 10' }
    elseif ($c -match '[/-]h\b') { 'hibernate this PC', '/h' }
    elseif ($c -match '[/-]l\b') { 'sign you out of Windows', '/l' }
    else { 'shut down this PC', '/s /t 10' }
if ($Answer) {   # tests: say what the popup would lead to, change nothing
    $out = switch ($Answer) { 'yes' { "would run: shutdown.exe $run" } 'no' { 'owner said no' } default { 'nobody answered' } }
    [Console]::Error.WriteLine("ASKED: $what | $out")
    exit 2
}
$msg = "Claude wants to $what.`n`nSave anything open first. Allow it?`n`n(This closes as No in 60 seconds.)"
$pop = @"
`$r = (New-Object -ComObject WScript.Shell).Popup('$($msg -replace "'", "''")', 60, 'Messiah - allow a restart?', 4 + 32 + 256 + 4096)
if (`$r -eq 6) { & "`$env:SystemRoot\System32\shutdown.exe" $run /c 'Restart allowed by the owner (Messiah popup)' }
"@
# 4 Yes/No + 32 question + 256 No is the default + 4096 on top of everything; 6 = Yes, 7 = No, -1 = nobody answered
try {
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand',
        ([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($pop))) -ErrorAction Stop
    [Console]::Error.WriteLine("ASKED THE OWNER: this command did not run, but a popup on the screen now asks the owner whether to $what. " +
        "If they click Yes within 60 s, it happens by itself 10 s later (the conversation ends then; the tray reopens it after the next login if you armed resume-after-restart.ps1). " +
        "If they click No or nobody is at the PC, nothing happens. Don't retry - tell the owner to look for the popup and click Yes, and that you can't do it without that click. " +
        "Hidden or unattended runs: never use this; leave restart-only work pending instead.")
} catch { [Console]::Error.WriteLine("The permission popup could not be shown ($($_.Exception.Message)). $why") }
exit 2
