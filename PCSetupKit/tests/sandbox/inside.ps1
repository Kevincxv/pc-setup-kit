# Runs INSIDE Windows Sandbox (run-sandbox.ps1 starts it at the sandbox's logon): a real, clean Windows 11 client -
# the one test GitHub's Windows Server machines can't give. The same steps as the fresh-install workflow: setup.ps1 for
# real, the install checks, then the new install's own self-test. Everything goes to C:\Results (a folder on the host);
# done.txt last, so the host knows it finished.
param([ValidateSet('noai', 'ai')][string]$Mode = 'noai')
$r = 'C:\Results'
Start-Transcript "$r\inside.log" -Force | Out-Null
try {
    # a writable copy of the kit (the host folder is read-only) without kit-source.txt: this version is tested, the
    # updater stays off (as on GitHub)
    New-Item C:\KitSrc -ItemType Directory -Force | Out-Null
    Copy-Item C:\KitRO\* C:\KitSrc -Recurse -Force
    Remove-Item C:\KitSrc\PCSetupKit\kit-source.txt -ErrorAction SilentlyContinue
    $env:FRESH_WITH_CLAUDE = if ($Mode -eq 'ai') { '1' } else { '0' }
    $t0 = Get-Date
    if ($Mode -eq 'ai') { & C:\KitSrc\PCSetupKit\setup.ps1 -NoLaunch -WithClaude *> "$r\setup.txt" } else { & C:\KitSrc\PCSetupKit\setup.ps1 -NoLaunch *> "$r\setup.txt" }
    "setup took $([int]((Get-Date) - $t0).TotalMinutes) min" | Add-Content "$r\summary.txt"
    & powershell -NoProfile -ExecutionPolicy Bypass -File C:\KitSrc\PCSetupKit\tests\fresh\check-install.ps1 *> "$r\check.txt"
    "install checks: exit $LASTEXITCODE - $((Get-Content "$r\check.txt" | Select-String 'RESULT |passed' | Select-Object -Last 1).Line)" | Add-Content "$r\summary.txt"
    $st = & "$env:USERPROFILE\.claude\self-test.ps1" -Force 2>&1
    "self-test: $st" | Add-Content "$r\summary.txt"
    Copy-Item C:\PCSetupKit\setup.log, "$env:USERPROFILE\.claude\self-test.log", "$env:USERPROFILE\.claude\maint-report.txt" $r -ErrorAction SilentlyContinue
}
catch { "inside.ps1 failed: $($_.Exception.Message)" | Add-Content "$r\summary.txt" }
finally {
    Stop-Transcript | Out-Null
    (Get-Date).ToString('o') | Set-Content "$r\done.txt"
}
