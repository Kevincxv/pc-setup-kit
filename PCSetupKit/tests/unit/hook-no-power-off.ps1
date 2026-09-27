# The no-shutdown hook: every way to shut down/restart/log off is blocked, normal commands are not.
. "$PSScriptRoot\..\lib.ps1"
$h = "$Src\hooks\no-power-off.ps1"
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
function Run($c) { @{ tool_name = 'PowerShell'; tool_input = @{ command = $c } } | ConvertTo-Json -Compress | powershell -NoProfile -ExecutionPolicy Bypass -File $h 2>$null; $LASTEXITCODE }
$nb = @($block | Where-Object { (Run $_) -ne 2 })
Check "all $($block.Count) shutdown/restart/logoff commands are blocked" (-not $nb) "not blocked: $($nb -join ' | ')"
$wb = @($allow | Where-Object { (Run $_) -ne 0 })
Check "all $($allow.Count) normal commands are allowed" (-not $wb) "wrongly blocked: $(($wb -join ' | ') -replace "`n", ' \n ')"
'garbage' | powershell -NoProfile -ExecutionPolicy Bypass -File $h 2>$null
Check 'non-JSON input never blocks' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
$msg = @{ tool_input = @{ command = 'shutdown /r' } } | ConvertTo-Json -Compress | powershell -NoProfile -ExecutionPolicy Bypass -File $h 2>&1
Check 'block message tells Claude what to do instead' ("$msg" -match 'resume-after-restart' -and "$msg" -match 'next time') "$msg"
Finish
