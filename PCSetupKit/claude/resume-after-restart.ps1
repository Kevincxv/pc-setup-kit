# Continues the current conversation after the next login, with the given prompt.
# Usage (from inside a Messiah session):  & "$env:USERPROFILE\.claude\resume-after-restart.ps1" -Prompt "Verify X after reboot"
# With the tray script installed, its hidden autostart session picks this up (claude-admin-launch.ps1 reads
# resume-after-login.txt); without it, a one-time logon task opens a visible session instead.
param([Parameter(Mandatory)][string]$Prompt)
$cl = "$env:USERPROFILE\.claude"
$launcher = "$cl\claude-admin-launch.ps1"
$p = $Prompt -replace "'", '' -replace '"', '' -replace "[`t`r`n]", ' '
$id = $env:CLAUDE_CODE_SESSION_ID
if (-not $id) {   # not run from a Claude session: take the newest session the launcher opened
    $id = Get-Content "$cl\admin-sessions.txt" -ErrorAction SilentlyContinue |
        ForEach-Object { Get-Item "$cl\projects\C--WINDOWS-system32\$_.jsonl" -ErrorAction SilentlyContinue } |
        Sort-Object LastWriteTime | Select-Object -Last 1 -ExpandProperty BaseName
}
"$id`t$p" | Set-Content "$cl\resume-after-login.txt" -Encoding utf8
Unregister-ScheduledTask -TaskName 'Claude Resume After Restart' -Confirm:$false -ErrorAction SilentlyContinue

if (Get-ScheduledTask -TaskName 'Messiah Tray' -ErrorAction SilentlyContinue) { "Resume: the tray opens it hidden after login (session $id)"; return }

$cmd = "Unregister-ScheduledTask -TaskName 'Claude Resume After Restart' -Confirm:`$false; `$env:CLAUDE_ADMIN_AUTOSTART='1'; & '$launcher'"
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`"" -WorkingDirectory "$env:SystemRoot\System32"
$trg = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"; $trg.Delay = 'PT20S'
$prn = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName 'Claude Resume After Restart' -Action $act -Trigger $trg -Principal $prn -Force `
    -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)) | ForEach-Object { "Resume task: $($_.State)" }
