# The no-shutdown hook: every way to shut down/restart/log off is blocked, normal commands are not; a plain shutdown or
# restart asks the owner in a popup instead, and only their Yes runs a fixed command.
. "$PSScriptRoot\..\lib.ps1"
$h = $Hook
if (-not (Test-Path $h)) { Check 'hook script exists' $false $h; Finish }
$block = @(
    'shutdown /r /t 15', 'shutdown.exe /s /t 0', 'shutdown /r /fw /t 15', 'C:\Windows\System32\shutdown.exe -r -t 5', '"C:\WINDOWS\system32\shutdown.exe" /s',
    'C:/Windows/System32/shutdown /r', 'cmd /c "shutdown /r"', 'Restart-Computer -Force', 'Stop-Computer', '(Get-WmiObject Win32_OperatingSystem).Reboot()',
    '(Get-WmiObject Win32_OperatingSystem).Win32Shutdown(6)', 'Get-CimInstance Win32_OperatingSystem | Invoke-CimMethod -MethodName Shutdown',
    'Invoke-CimMethod -ClassName Win32_OperatingSystem -MethodName Reboot', 'shutdown /g /t 0', 'shutdown /p', 'shutdown /h',
    'Start-Process shutdown -ArgumentList "/r /t 0"', 'logoff', 'shutdown /l', 'taskkill /f /im wininit.exe', 'Stop-Process -Name csrss -Force',
    'Res`tart-Computer', 'echo x; shutdown /r /t 1', 'shutdown -s -f -t 0', "Get-Date`nRestart-Computer", 'wpeutil reboot')
$allow = @(
    'shutdown /a', 'Get-WinEvent -FilterHashtable @{LogName=''System'';Id=1074}', '& "C:\Program Files (x86)\Steam\steam.exe" -shutdown',
    'Select-String -Pattern ''restart|shutdown|reboot'' SKILL.md', 'Get-Content shutdown-notes.txt', 'Get-Content C:\notes\shutdown-log.txt',
    'git log --oneline', 'powercfg /hibernate off', '"REBOOT required to finish" | Add-Content x', 'Stop-Process -Name notepad',
    "`$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime`n# previous run was cut off by a shutdown (older than boot)`n'simulate power-off'",
    "Get-CimInstance Win32_OperatingSystem | Select LastBootUpTime; 'the owner shuts down at night'",
    'Get-WinEvent -FilterHashtable @{LogName=''System''; ProviderName=''Microsoft-Windows-Kernel-General''; Id=13}  # OS shutdown events',
    'bcdedit /bootsequence {memdiag}', 'Write-Host "finishes the next time you shut down or restart"', 'Get-ScheduledTask | ? TaskName -match Restart',
    'Start-Sleep 25', 'ping -n 30 127.0.0.1')
# -Answer: the popup's outcome without showing it (tests must never show it or restart anything)
function Run($c, $a = 'no') { @{ tool_name = 'PowerShell'; tool_input = @{ command = $c } } | ConvertTo-Json -Compress | powershell -NoProfile -ExecutionPolicy Bypass -File $h -Answer $a 2>$null; $LASTEXITCODE }
function Said($c, $a) { "$(@{ tool_input = @{ command = $c } } | ConvertTo-Json -Compress | powershell -NoProfile -ExecutionPolicy Bypass -File $h -Answer $a 2>&1)" }
$nb = @($block | Where-Object { (Run $_) -ne 2 })
Check "all $($block.Count) shutdown/restart/logoff commands are blocked" (-not $nb) "not blocked: $($nb -join ' | ')"
$wb = @($allow | Where-Object { (Run $_) -ne 0 })
Check "all $($allow.Count) normal commands are allowed" (-not $wb) "wrongly blocked: $(($wb -join ' | ') -replace "`n", ' \n ')"
'garbage' | powershell -NoProfile -ExecutionPolicy Bypass -File $h -Answer no 2>$null
Check 'non-JSON input never blocks' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
$msg = Said 'logoff' 'none'
Check 'block message tells Claude what to do instead' ("$msg" -match 'resume-after-restart' -and "$msg" -match 'next time') "$msg"

Section "owner's permission (popup)"
$yb = @($block | Where-Object { (Run $_ 'yes') -ne 2 })
Check 'even with Yes the command itself never runs (the popup runs a fixed one)' (-not $yb) "$($yb -join ' | ')"
$m = Said 'shutdown /r /fw /t 15' 'yes'
Check 'restart into the BIOS: the owner is asked, Yes runs shutdown /r /fw' ($m -match 'ASKED: restart this PC into the BIOS' -and $m -match 'shutdown\.exe /r /fw /t 10') $m
$m = Said 'Restart-Computer -Force' 'yes'
Check 'Restart-Computer: asked as a plain restart' ($m -match 'ASKED: restart this PC \|' -and $m -match '/r /t 10') $m
$m = Said 'shutdown -s -f -t 0' 'yes'
Check 'shutdown: asked as a shut down, the extra switches dropped' ($m -match 'ASKED: shut down this PC' -and $m -match 'would run: shutdown\.exe /s /t 10\s*$') $m
$m = Said 'shutdown /r /t 0' 'no'; $m2 = Said 'shutdown /r /t 0' 'none'
Check 'No or no answer: nothing runs' ($m -match 'owner said no' -and $m -notmatch 'would run' -and $m2 -match 'nobody answered' -and $m2 -notmatch 'would run') "$m / $m2"
$never = @('(Get-WmiObject Win32_OperatingSystem).Reboot()', 'logoff', 'Stop-Process -Name csrss -Force', 'wpeutil reboot', 'Invoke-CimMethod -ClassName Win32_OperatingSystem -MethodName Reboot')
$asked = @($never | Where-Object { (Said $_ 'yes') -match 'ASKED' })
Check 'WMI/API calls, logoff and killing system processes are never offered to the owner' (-not $asked) "$($asked -join ' | ')"
Finish
