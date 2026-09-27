# crash-analyze.ps1 (fake WinDbg debuggers print canned !analyze output) and claude-maint.ps1 (scripted fake claude.exe).
. "$PSScriptRoot\..\lib.ps1"
Section 'crash-analyze: debugger choice and verdict parsing'
$ca = "$Work\ca"; New-Item "$ca\windbg\amd64" -ItemType Directory -Force | Out-Null; Copy-Item "$Src\crash-analyze.ps1" $ca
if (-not (Test-Tripwire "$ca\crash-analyze.ps1" @('Get-AppxPackage'))) { Finish }
$dbgSrc = 'using System; using System.IO; public static class D { public static void Main(string[] a) { File.AppendAllText(Environment.GetEnvironmentVariable("DBG_LOG"), "{EXE} " + string.Join(" ", a) + Environment.NewLine); Console.Write(File.ReadAllText(Environment.GetEnvironmentVariable("DBG_OUT"))); } }'
foreach ($x in 'kd', 'cdb') {
    $exe = Join-Path $env:TEMP "pckit-tests\dbg\$x.exe"
    if (-not (Test-Path $exe)) { New-Item (Split-Path $exe) -ItemType Directory -Force | Out-Null; Add-Type -OutputType ConsoleApplication -OutputAssembly $exe -TypeDefinition ($dbgSrc.Replace('{EXE}', $x).Replace('public static class D', "public static class D$x")) }
    Copy-Item $exe "$ca\windbg\amd64\$x.exe" -Force
}
Import-MockTargets 'Get-AppxPackage'   # load its module BEFORE defining the mock (see lib.ps1)
$global:WinDbgInstalled = $true
function Get-AppxPackage { if ($global:WinDbgInstalled) { [pscustomobject]@{ Name = 'Microsoft.WinDbg'; Version = [version]'1.2.0'; InstallLocation = "$ca\windbg" } } }
if (-not (Assert-Mocks 'Get-AppxPackage')) { Finish }
$env:DBG_LOG = "$Work\dbg.log"; $env:DBG_OUT = "$Work\dbg.out"
@'
*******************************************************************************
*                        Bugcheck Analysis                                    *
BUGCHECK_CODE:  109
PROCESS_NAME:  System
MODULE_NAME: nt
IMAGE_NAME:  ntkrnlmp.exe
FAILURE_BUCKET_ID:  0x109_MEMORY_CORRUPTION_ONE_BIT
'@ | Set-Content $env:DBG_OUT
$o = & "$ca\crash-analyze.ps1" -Dump 'C:\Windows\Minidump\092726-10453-01.dmp'
Check 'blue-screen minidump: kernel debugger (kd) used' ((Get-Content $env:DBG_LOG -Tail 1) -match '^kd -z C:\\Windows\\Minidump\\092726') (Get-Content $env:DBG_LOG -Tail 1)
Check 'one-line verdict: code, blamed module, process, bucket' ("$o" -eq 'code 109 | blamed: ntkrnlmp.exe (nt) | process: System | bucket: 0x109_MEMORY_CORRUPTION_ONE_BIT') "$o"
Check 'symbols cached locally and fetched from Microsoft' ((Get-Content $env:DBG_LOG -Tail 1) -match 'CrashSymbols\*https://msdl.microsoft.com/download/symbols') ''
[void](& "$ca\crash-analyze.ps1" -Dump 'C:\Windows\MEMORY.DMP')
Check 'full memory dump: kd' ((Get-Content $env:DBG_LOG -Tail 1) -match '^kd ') ''
"EXCEPTION_CODE_STR:  c0000005`nPROCESS_NAME:  game.exe`nMODULE_NAME: gamedll`nIMAGE_NAME:  gamedll.dll`nFAILURE_BUCKET_ID:  NULL_POINTER_READ_c0000005_gamedll.dll" | Set-Content $env:DBG_OUT
$o = & "$ca\crash-analyze.ps1" -Dump 'C:\Users\x\AppData\Local\CrashDumps\game.exe.4242.dmp'
Check 'app crash dump: user-mode debugger (cdb), exception code read' (((Get-Content $env:DBG_LOG -Tail 1) -match '^cdb ') -and "$o" -match '^code c0000005 \| blamed: gamedll.dll \(gamedll\) \| process: game.exe') "$o"
'Loading symbols... nothing useful here' | Set-Content $env:DBG_OUT
$o = & "$ca\crash-analyze.ps1" -Dump 'C:\Windows\Minidump\x.dmp'
Check 'nothing recognisable: "inconclusive", no half-empty verdict' ("$o" -match '^Analysis inconclusive for x.dmp') "$o"
$o = & "$ca\crash-analyze.ps1" -Dump 'C:\Windows\Minidump\x.dmp' -Full
Check '-Full returns the raw debugger output' ("$o" -match 'nothing useful here') "$o"
$global:WinDbgInstalled = $false; $o = & "$ca\crash-analyze.ps1" -Dump 'C:\Windows\Minidump\x.dmp'
Check 'WinDbg not installed: says how to get it' ("$o" -match 'WinDbg not installed \(winget install Microsoft.WinDbg\)') "$o"

Section 'claude-maint: update, plugins, doctor'
$H = "$Work\home"; $cm = "$H\.claude"; $fd = "$Work\fake"; New-Item "$H\.local\bin", $cm, $fd -ItemType Directory -Force | Out-Null
Copy-Item (Get-ScriptedClaude) "$H\.local\bin\claude.exe"; Copy-Item "$Src\claude-maint.ps1" $cm
if (-not (Test-Tripwire "$cm\claude-maint.ps1" @('Start-Process', 'Stop-Process'))) { Finish }   # (they only start/stop the fake claude.exe in the sandbox)
function Fake([hashtable]$files) { Get-ChildItem $fd -File | ForEach-Object { Clear-Path $_.FullName }; '2.1.283' | Set-Content "$fd\version.txt"; foreach ($k in $files.Keys) { $files[$k] | Set-Content "$fd\$k" } }
function CM { (Invoke-As $H "$cm\claude-maint.ps1" @() @{ FAKE_DIR = $fd }).Out.Trim() -split "`r?`n" }
'{ "enabledPlugins": { "helper@market": true, "off@market": false } }' | Set-Content "$cm\settings.json"
Fake @{ 'update.txt' = 'Claude Code is up to date (2.1.283)'; 'doctor.txt' = "Diagnostics`nNo installation issues found" }
$o = CM
Check 'up to date: one clean line' (($o -join '|') -eq 'Claude Code: 2.1.283 (up to date)') ($o -join ' / ')
$calls = Get-Content "$fd\calls.log"
Check 'plugin marketplaces and enabled plugins are updated (disabled ones not)' (($calls -contains 'plugin_marketplace_update') -and ($calls -contains 'plugin_update_helper@market') -and -not ($calls -match 'off@market')) ($calls -join ', ')
Fake @{ 'update.txt' = 'Updating...'; 'update.newversion' = '2.1.284'; 'doctor.txt' = 'No installation issues found' }
$o = CM
Check 'an update: "Updated 2.1.283 -> 2.1.284"' (($o -join '|') -eq 'Claude Code: Updated 2.1.283 -> 2.1.284') ($o -join ' / ')
Fake @{ 'update.txt' = "Checking...`nError: failed to download the update (network)"; 'doctor.txt' = 'No installation issues found' }
$o = CM
Check 'update error: "update FAILED" with the reason (Claude looks at it)' (($o -join '|') -match '^Claude Code: update FAILED - Error: failed to download') ($o -join ' / ')
Fake @{ 'update.txt' = 'Claude Code is up to date'; 'doctor.txt' = "Warning: multiple installations found`n- npm-global at C:\x" }
$o = CM
Check 'doctor finds a problem: DOCTOR ISSUES with the details' (($o -contains 'DOCTOR ISSUES:') -and ($o -match 'multiple installations')) ($o -join ' / ')
Fake @{ 'update.txt' = 'Claude Code is up to date'; 'doctor.sleep' = '60000' }
$t0 = Get-Date; $o = CM
Check 'doctor hangs: skipped after 45 s, worded so it does not wake /maintain' ((($o -join '|') -match "got no response in 45 s, skipped") -and -not (($o -join '|') -match 'WARNING|FAILED|timed out|DOCTOR ISSUES') -and ((Get-Date) - $t0).TotalSeconds -lt 70) ($o -join ' / ')
Get-CimInstance Win32_Process -Filter "Name='claude.exe'" | Where-Object ExecutablePath -like "$H*" | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Finish
