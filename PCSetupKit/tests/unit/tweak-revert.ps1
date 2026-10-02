# tweaks.ps1 records original values the first time it changes them; uninstall.ps1 -RevertTweaks puts them back.
. "$PSScriptRoot\..\lib.ps1"
if (-not (Test-IsAdmin)) { Skip 'tweak revert' 'needs administrator'; Finish }
$key = 'HKCU:\Software\PCSetupKitTest'; $bkf = "$Work\tweaks-backup.json"; $tp = '\PCSetupKitTest\'; $tn = 'PCSetupKitRevertTest'
try {
    if (Test-Path $key) { Remove-Item $key -Recurse -Force }
    New-Item $key -Force | Out-Null
    New-ItemProperty $key -Name ValueA -Value 5 -PropertyType DWord | Out-Null
    New-ItemProperty $key -Name ValueS -Value 'hello' -PropertyType String | Out-Null
    # the real recording code of tweaks.ps1 (its header + footer), applied to test values
    $tw = Get-Content "$Kit\tweaks.ps1" -Raw
    $head = $tw.Substring(0, $tw.IndexOf('# --- Telemetry')).Replace("'C:\PCSetupKit\tweaks-backup.json'", "'$bkf'")
    $foot = $tw.Substring($tw.LastIndexOf("Trace 'done'"))   # (the end: the last save of the originals and the lock)
    Set-Content "$Work\tweaks-test.ps1" ($head + "Set-Reg '$key' ValueA 0`nSet-Reg '$key' ValueS 'changed' 'String'`nSet-Reg '$key' ValueNew 1`n" + $foot)
    $o = & "$Work\tweaks-test.ps1"
    Check 'tweaks applied to the test values' ((Get-ItemProperty $key).ValueA -eq 0 -and (Get-ItemProperty $key).ValueS -eq 'changed' -and (Get-ItemProperty $key).ValueNew -eq 1) ($o -join ',')
    Check 'originals recorded (3 entries)' (@((Get-Content $bkf -Raw | ConvertFrom-Json).PSObject.Properties).Count -eq 3) (Get-Content $bkf -Raw)
    Set-ItemProperty $key ValueA 7; [void](& "$Work\tweaks-test.ps1")
    Check 'the tweak guard running again keeps the FIRST original (5), not 7' ((Get-Content $bkf -Raw | ConvertFrom-Json)."reg|$key|ValueA".Value -eq 5) (Get-Content $bkf -Raw)
    Register-ScheduledTask -TaskName $tn -TaskPath $tp -Action (New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c exit') -Force | Out-Null
    Disable-ScheduledTask -TaskPath $tp -TaskName $tn | Out-Null
    $j = Get-Content $bkf -Raw | ConvertFrom-Json
    $j | Add-Member "task|$tp$tn" ([pscustomobject]@{ Enabled = $true }); $j | Add-Member 'app|Microsoft.BingWeather' ([pscustomobject]@{ Name = 'Microsoft.BingWeather'; Removed = 'x' })
    $j | ConvertTo-Json -Depth 4 | Set-Content $bkf
    $o = & "$Kit\uninstall.ps1" -RevertTweaks -RevertOnly -Yes -BackupFile $bkf 2>&1 | Out-String
    $p = Get-ItemProperty $key
    Check 'ValueA back to 5, still a DWORD' ($p.ValueA -eq 5 -and (Get-Item $key).GetValueKind('ValueA') -eq 'DWord') "$($p.ValueA)"
    Check 'ValueS back to hello, still a String' ($p.ValueS -eq 'hello' -and (Get-Item $key).GetValueKind('ValueS') -eq 'String') "$($p.ValueS)"
    Check "ValueNew removed (it didn't exist before)" ($null -eq $p.ValueNew) "$($p.ValueNew)"
    Check 'scheduled task enabled again' ((Get-ScheduledTask -TaskPath $tp -TaskName $tn).State -ne 'Disabled') ''
    Check 'removed app listed for the Store' ($o -match 'Microsoft.BingWeather') ''
    Check 'revert-only touched no power plan or files' (-not ($o -match 'power plan|removed-files')) ''
    $o = & "$Kit\uninstall.ps1" -RevertTweaks -RevertOnly -Yes -BackupFile "$Work\does-not-exist.json" 2>&1 | Out-String
    Check 'no backup file: explains, no error' (($o -match 'No backup of the original settings') -and -not ($o -match 'Exception|Cannot find')) $o
}
finally {
    Unregister-ScheduledTask -TaskPath $tp -TaskName $tn -Confirm:$false -ErrorAction SilentlyContinue
    try { $svc = New-Object -ComObject Schedule.Service; $svc.Connect(); $svc.GetFolder('\').DeleteFolder('PCSetupKitTest', 0) } catch {}
    if (Test-Path $key) { Remove-Item $key -Recurse -Force }
}
Finish
