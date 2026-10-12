# Diagnostic modes left on: Driver Verifier (checks every call of the drivers it watches - games lose frame rate and
# stutter), kernel debugging and test signing. Right while a crash is hunted, a cost after. One object per mode that is on
# (Id, Name, Since, Days); the day each was first seen is kept in diag-state.json. One that goes off is kept as "<id>-off"
# (when - it still runs until the next restart: the Status tab says so), for 30 days.
# Read-only otherwise. Used by health-check.ps1 (a Reminder after 14 days) and the app's Status tab.
# -Test (hashtable: VerifyDrivers, StartOptions, Today) / -State: tests.
param([string]$State = "$PSScriptRoot\diag-state.json", [hashtable]$Test)
$ErrorActionPreference = 'SilentlyContinue'
$vd = if ($Test) { "$($Test.VerifyDrivers)" } else { "$((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name VerifyDrivers).VerifyDrivers)".Trim() }
# (the options this start of Windows was made with: what bcdedit set - readable without admin rights)
$opts = if ($Test) { "$($Test.StartOptions)" } else { "$((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions).SystemStartOptions)" }
$on = [ordered]@{}
if ($vd) { $n = @($vd -split '\s+' | Where-Object { $_ }).Count; $on['verifier'] = if ($vd -eq '*') { 'Driver Verifier (every driver)' } else { "Driver Verifier ($n driver$(if ($n -ne 1) { 's' }))" } }
if ($opts -match '(^|\s)DEBUG(\s|=|$)') { $on['debug'] = 'Kernel debugging' }
if ($opts -match '(^|\s)TESTSIGNING(\s|$)') { $on['testsigning'] = 'Test signing (unsigned drivers allowed)' }
$st = @{}; try { (Get-Content $State -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).PSObject.Properties | ForEach-Object { if ("$($_.Value)" -match '^\d{4}-\d\d-\d\d(T|$)') { $st[$_.Name] = "$($_.Value)" } } } catch { }
$today = if ($Test -and $Test.Today) { [datetime]$Test.Today } else { Get-Date }
$changed = $false
foreach ($k in @($st.Keys | Where-Object { $_ -notlike '*-off' })) { if (-not $on.Contains($k)) { $st.Remove($k); $st["$k-off"] = $today.ToString('s'); $changed = $true } }
foreach ($k in @($st.Keys | Where-Object { $_ -like '*-off' })) {
    $t = [datetime]::MinValue; if ($on.Contains(($k -replace '-off$', '')) -or -not [datetime]::TryParse($st[$k], [ref]$t) -or $t -lt $today.AddDays(-30)) { $st.Remove($k); $changed = $true }
}
foreach ($k in $on.Keys) { if (-not $st.ContainsKey($k)) { $st[$k] = $today.ToString('yyyy-MM-dd'); $changed = $true } }
if ($changed) { try { [IO.File]::WriteAllText($State, (ConvertTo-Json -InputObject $st), (New-Object Text.UTF8Encoding $false)) } catch { } }
foreach ($k in $on.Keys) {
    $since = [datetime]::ParseExact($st[$k], 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    [pscustomobject]@{ Id = $k; Name = $on[$k]; Since = $since; Days = [int]($today.Date - $since).TotalDays }
}
