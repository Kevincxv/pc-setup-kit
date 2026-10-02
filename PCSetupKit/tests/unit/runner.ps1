# The test runner itself: a passing test's scratch folder is deleted right away, a failing one is kept to look at
. "$PSScriptRoot\..\lib.ps1"

Section 'scratch folders'
$k = "$Work\kit"; New-Item "$k\tests\unit" -ItemType Directory -Force | Out-Null
Copy-Item "$PSScriptRoot\..\run-tests.ps1" "$k\tests"
foreach ($n in 'ok', 'bad') {
    "'x' | Set-Content `"`$env:TEMP\left-behind.txt`"; 'RESULT $n pass=1 fail=$([int]($n -eq 'bad')) skip=0'" | Set-Content "$k\tests\unit\$n.ps1"
}
$runTemp = "$Work\temp"; New-Item $runTemp -ItemType Directory -Force | Out-Null
$psi = New-Object Diagnostics.ProcessStartInfo 'powershell.exe'
$psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$k\tests\run-tests.ps1`" -Suite unit -Kit `"$k`" -Src `"$k`" -Jobs 2"
$psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$psi.EnvironmentVariables['TEMP'] = $runTemp; $psi.EnvironmentVariables['TMP'] = $runTemp
$p = [Diagnostics.Process]::Start($psi); $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
if (-not $p.WaitForExit(120000)) { Stop-Tree $p.Id }
$left = @(Get-ChildItem "$runTemp\pckit-tests" -Directory -Filter 'tmp-*' -ErrorAction SilentlyContinue | ForEach-Object Name)
Check 'the runner ran both tests (1 failed)' ((Get-Content "$k\tests\last-run.txt" -Raw) -match ' 3 passed, 1 failed') ($o.Result + $e.Result)
Check 'a passing test''s scratch folder is deleted when it ends' (-not ($left -match '^tmp-ok-')) ($left -join ', ')
Check 'a failing test''s scratch folder stays (to look at)' ([bool]($left -match '^tmp-bad-')) ($left -join ', ')

Clear-Path $Work
Finish
