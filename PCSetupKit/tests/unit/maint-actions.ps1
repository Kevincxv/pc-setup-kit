# maint-actions.ps1 (the no-AI maintenance decisions) with every system change mocked: report lines in -> fixes and
# plain to-do items out, items gone once fixed, the crash ladder, leftovers, Windows end of support, scheduled checks.
. "$PSScriptRoot\..\lib.ps1"
$D = "$Work\cl"; New-Item $D -ItemType Directory -Force | Out-Null
Copy-Item "$Src\maint-actions.ps1", "$Src\todo.ps1" $D
$mocked = 'bcdedit', 'Enable-ComputerRestore', 'Disable-ScheduledTask', 'Set-Service', 'Set-ItemProperty', 'New-Item', 'Invoke-WebRequest', 'Get-WinEvent', 'Get-CimInstance', 'Get-ItemProperty'
if (-not (Test-Tripwire "$D\maint-actions.ps1" $mocked)) { Finish }
Import-MockTargets $mocked   # load their Windows modules BEFORE defining the mocks (see lib.ps1)
$global:MA = @{}
function Reset-MA { $global:MA = @{ Calls = New-Object System.Collections.Generic.List[string]; Ram = 6000; Events = @(); Services = @{}; Page = 'Version 24H2 ... Version 25H2 ...'; CurVer = '24H2'; Memdiag = $true } }
function bcdedit { $global:MA.Calls.Add("bcdedit $args"); if ("$args" -match 'enum') { if ($global:MA.Memdiag) { 'Windows Memory Tester  identifier {memdiag}' } else { 'The boot configuration data store could not be opened.' } } else { 'The operation completed successfully.' } }
function Enable-ComputerRestore { param($Drive) if ($global:MA.NoRestore) { throw 'not supported on this Windows' }; $global:MA.Calls.Add("restore on $Drive") }
function Disable-ScheduledTask { param($TaskPath, $TaskName) $global:MA.Calls.Add("disable task $TaskPath$TaskName") }
function Set-Service { param($Name, $StartupType) $global:MA.Calls.Add("service $Name $StartupType") }
function Set-ItemProperty { param($Path, $Name, $Value, $Type) $global:MA.Calls.Add("reg $Name=$Value") }
function New-Item { param($Path, [switch]$Force, $ItemType) if ("$Path" -match '^HK') { $global:MA.Calls.Add("new key") } else { Microsoft.PowerShell.Management\New-Item @PSBoundParameters } }
function Invoke-WebRequest { $global:MA.Calls.Add('web'); [pscustomobject]@{ Content = $global:MA.Page } }
function Get-WinEvent { $global:MA.Events }
function Get-CimInstance { param($ClassName, $Filter) switch ($ClassName) {
        'Win32_PhysicalMemory' { [pscustomobject]@{ ConfiguredClockSpeed = $global:MA.Ram } }
        'Win32_BaseBoard' { [pscustomobject]@{ Manufacturer = 'ASUSTeK COMPUTER INC.'; Product = 'TEST X650-A' } }
        'Win32_Service' { if ($Filter -match "Name='([^']+)'") { $global:MA.Services[$Matches[1]] } } } }
function Get-ItemProperty { param($Path) [pscustomobject]@{ DisplayVersion = $global:MA.CurVer } }
if (-not (Assert-Mocks $mocked)) { Finish }
'"Monitor: Fast Monitor set to 165Hz (was 60Hz)"' | Set-Content "$D\display-refresh.ps1"
'param([switch]$Benchmark, [switch]$FromMaintenance) "optimize benchmark=$Benchmark" | Add-Content "$PSScriptRoot\optimize-calls.txt"' | Set-Content "$D\optimize.ps1"
$now = Get-Date
function Fresh { Reset-MA; foreach ($f in 'maint-todo.txt', 'todo-scripted.json', 'actions-state.json', 'optimize-calls.txt') { Clear-Path "$D\$f" }
    @{ 'claude-quarterly' = $now.ToString('o'); 'claude-halfyear' = $now.ToString('o'); 'claude-yearly' = $now.ToString('o') } | ConvertTo-Json | Set-Content "$D\maint-state.json" }
function Act([string[]]$L, [datetime]$At = $now) { @(& "$D\maint-actions.ps1" -Lines $L -Now $At -Dir $D) }
function Todos { @(Get-Content "$D\maint-todo.txt" -Encoding UTF8 -ErrorAction SilentlyContinue) }
function Ids { @(& "$D\todo.ps1" -Dir $D -List) }

Section 'hardware reminders: an item while the reminder is there, gone once fixed'
Fresh
$rep = 'Checked X', '[PC health]', 'Reminder: NVIDIA GeForce RTX 9090 runs at PCIe x8 (card supports x16) - check BIOS slot setting / reseat card',
'Reminder: RAM runs at its default 4800 MT/s (KIT-6000-TEST) - if it''s a faster kit, turn EXPO/XMP on in BIOS', 'Reminder: BIOS 1.10 is from 1/2/2024 (over a year old)',
'Reminder: Ethernet network link is only 100 Mbps (adapter supports 1 Gbps or more) - check the cable', 'Reminder: Backup Drive (2000 GB) is connected and nothing is backed up',
'WARNING: Defender real-time protection is OFF', 'WARNING: C: is low on space (12 GB free)', 'WARNING: drive Samsung SSD reports Warning health (Degraded) - back up your files now'
$o = Act $rep
Check 'one item each: GPU slot, RAM profile, BIOS, network, backup, Defender, disk space, failing drive' ((((Ids) | Sort-Object) -join ',') -eq 'backup,bios,defender,disk-space,drive-health,gpu-link,network-link,ram-expo') ((Ids) -join ',')
$t = (Todos) -join "`n"
Check 'plain steps, with the facts in them (x8/x16, 4800 MT/s + kit, board maker''s download page)' ($t -match 'PCIe x8 but supports x16' -and $t -match '4800 MT/s' -and $t -match 'KIT-6000-TEST' -and $t -match 'EXPO \(AMD\) or XMP \(Intel\)' -and $t -match 'asus\.com/support' -and $t -match 'TEST X650-A') $t
Check '... and how to keep things as they are (delete the line)' ($t -match 'delete this line') ''
$o = Act 'Checked Y', '[PC health]', 'Reminder: BIOS 1.10 is from 1/2/2024 (over a year old)'
Check 'fixed ones are removed by the next check, the rest stays' (((Ids) -join ',') -eq 'bios') ((Ids) -join ',')
$o = Act 'Checked Z', '[Drivers]', 'NVIDIA: up to date'
Check 'the health check did not run (e.g. timed out): nothing is cleared' (((Ids) -join ',') -eq 'bios') ((Ids) -join ',')
$o = Act 'Checked W', '[PC health]', 'Reminder: Dell runs at 60Hz but supports 165Hz'
Check 'a monitor below its best refresh rate: fixed right away, no item' (($o -match 'Fast Monitor set to 165Hz') -and -not ((Ids) -contains 'monitor-hz')) ($o -join ' / ')
'"Monitor: Old Monitor could not be set to 144Hz (Windows answered -2; it stays at 60Hz)"' | Set-Content "$D\display-refresh.ps1"
$o = Act 'Checked V', '[PC health]', 'Reminder: Old Monitor runs at 60Hz but supports 144Hz'
Check '... if Windows can''t switch it: an item about the cable' ((Ids) -contains 'monitor-hz' -and ((Todos) -join ' ') -match 'DisplayPort cable') ((Todos) -join ' | ')
'"Monitor: Fast Monitor set to 165Hz (was 60Hz)"' | Set-Content "$D\display-refresh.ps1"

Section 'crashes: the crash ladder as fixed rules'
Fresh; $t1 = $now.AddDays(-3).ToString('g'); $t2 = $now.AddDays(-1).ToString('g')
$o = Act 'Checked A', '[PC health]', "WARNING: blue screen 0x109 at $t1", 'WARNING: crash dump 092726.dmp - code 0x109 | blamed: nvlddmkm.sys (nvlddmkm) | process: System | bucket: x'
$c = (Todos) -join ' '
Check 'first blue screen: an item with the code and the driver it points at, nothing scheduled' ((Ids) -contains 'crash' -and $c -match '0x109' -and $c -match 'points at nvlddmkm\.sys' -and -not ($MA.Calls -match 'bootsequence')) $c
$o = Act 'Checked B', '[PC health]', "WARNING: blue screen 0x109 at $t2", 'WARNING: crash dump 092826.dmp - code 0x109 | blamed: ntoskrnl.exe (nt) | process: System | bucket: y'
$c = (Todos) -join ' '
Check 'second within 2 weeks, RAM on its fast profile: the EXPO/XMP test is suggested' ($c -match '2 in the last 2 weeks' -and $c -match 'EXPO/XMP to Auto or Disabled') $c
Check '... Windows itself (ntoskrnl) is not blamed as a driver to update' ($c -notmatch 'points at ntoskrnl') $c
Check '... a memory test is scheduled for the owner''s next restart (the PC is not restarted)' (($MA.Calls -match "bcdedit /bootsequence \{memdiag\}") -and ($o -match 'memory test runs at the next restart') -and (Ids) -contains 'memtest') (($MA.Calls + $o) -join ' / ')
$MA.Calls.Clear(); $o = Act 'Checked C', '[PC health]', "WARNING: blue screen 0x1A at $($now.ToString('g'))"
Check '... only once' (-not ($MA.Calls -match 'bootsequence')) ($MA.Calls -join ' / ')
$MA.Events = @([pscustomobject]@{ Id = 1102; TimeCreated = $now }); $o = Act 'Checked D', '[PC health]'
Check 'the test found errors: a WARNING and an item about the faulty stick; the "test pending" item goes' (($o -match 'WARNING: the memory test found RAM errors') -and (Ids) -contains 'ram-faulty' -and -not ((Ids) -contains 'memtest')) (($o + (Ids)) -join ' / ')
Fresh; $MA.Ram = 4800
[void](Act 'x', '[PC health]', "WARNING: blue screen 0x109 at $t1"); $o = Act 'x', '[PC health]', "WARNING: blue screen 0x109 at $t2"
Check 'RAM already at its default speed: no EXPO advice (the memory test still runs)' ((((Todos) -join ' ') -notmatch 'EXPO/XMP to Auto') -and ($MA.Calls -match 'bootsequence')) ((Todos) -join ' ')
$MA.Events = @([pscustomobject]@{ Id = 1101; TimeCreated = $now }); $o = Act 'x', '[PC health]'
Check 'a clean memory test: said in the report, no item' (($o -match 'found no errors') -and -not ((Ids) -contains 'ram-faulty')) ($o -join ' / ')
$o = Act 'x', '[PC health]' $now.AddDays(15)
Check 'two weeks without blue screens: the crash item goes by itself' (-not ((Ids) -contains 'crash')) ((Ids) -join ',')
Fresh; $o = Act 'x', '[PC health]', "WARNING: unexpected shutdown/freeze at $t2 (no blue screen recorded)"
Check 'a power-off without a blue screen: "if it was you, delete this line"' ((Ids) -contains 'freeze' -and ((Todos) -join ' ') -match 'If you turned it off yourself, delete this line') ((Todos) -join ' ')
$o = Act 'x', '[PC health]' $now.AddDays(8)
Check '... gone after a week by itself' (-not ((Ids) -contains 'freeze')) ((Ids) -join ',')

Section 'apps that keep failing to update'
Fresh
foreach ($w in 1..2) { [void](Act 'App update FAILED: Some.App') }
Check 'two weeks failing: no item yet (it retries every week)' (-not ((Ids) -contains 'app-Some.App')) ''
[void](Act 'App update FAILED: Some.App')
Check 'three weeks in a row: an item to update it by hand' ((Ids) -contains 'app-Some.App') ((Ids) -join ',')
[void](Act 'Updated app: Some.App')
Check 'it updated again: item gone, count reset' (-not ((Ids) -contains 'app-Some.App')) ((Ids) -join ',')

Section 'leftovers of deleted programs are disabled, never deleted'
Fresh
$MA.Services['OldSvc'] = [pscustomobject]@{ Name = 'OldSvc'; State = 'Stopped'; StartMode = 'Auto'; PathName = 'C:\Program Files\Gone\svc.exe' }
$MA.Services['WinSvc'] = [pscustomobject]@{ Name = 'WinSvc'; State = 'Stopped'; StartMode = 'Manual'; PathName = 'C:\Windows\System32\gone.exe' }
$MA.Services['RunSvc'] = [pscustomobject]@{ Name = 'RunSvc'; State = 'Running'; StartMode = 'Auto'; PathName = 'C:\Program Files\X\x.exe' }
$o = Act 'WARNING: leftovers pointing at deleted programs: task \Vendor\Updater, service OldSvc, service WinSvc, service RunSvc'
Check 'the task and the stopped third-party service are disabled (and said so)' (($MA.Calls -contains 'disable task \Vendor\Updater') -and ($MA.Calls -contains 'service OldSvc Disabled') -and ($o -match 'disabled task') -and ($o -match 'disabled service OldSvc')) (($MA.Calls + $o) -join ' / ')
Check '... anything in the Windows folder or still running is left alone' (-not ($MA.Calls -match 'WinSvc|RunSvc')) ($MA.Calls -join ' / ')

Section 'restore points failing (System Protection off)'
Fresh; $o = Act 'Restore point FAILED (is System Protection on for C:?)'
Check 'System Protection switched on for C: (Windows'' own undo points), said so' (($MA.Calls -match '^restore on C:') -and ($o -match 'turned System Protection on')) (($MA.Calls + $o) -join ' / ')
Fresh; $MA.NoRestore = $true; $o = Act 'Restore point FAILED (is System Protection on for C:?)'
Check '... where Windows can''t (e.g. a server): says so, no error' ([bool]($o -match "couldn't turn System Protection on")) ($o -join ' / ')

Section 'Windows near its end of support'
Fresh; $s = Get-Content "$D\maint-state.json" -Raw | ConvertFrom-Json; $s | Add-Member 'claude-winver-due' 'yes'; $s | ConvertTo-Json | Set-Content "$D\maint-state.json"
$o = Act 'x'
Check 'asks Windows Update for the newest version (25H2), says so, clears the flag' (($MA.Calls -contains 'reg TargetReleaseVersionInfo=25H2') -and ($MA.Calls -contains 'reg TargetReleaseVersion=1') -and ($o -match 'version 25H2') -and -not ((Get-Content "$D\maint-state.json" -Raw) -match 'winver-due')) (($MA.Calls + $o) -join ' / ')
Fresh; $s = Get-Content "$D\maint-state.json" -Raw | ConvertFrom-Json; $s | Add-Member 'claude-winver-due' 'yes'; $s | ConvertTo-Json | Set-Content "$D\maint-state.json"
$MA.Page = $null; function Invoke-WebRequest { throw 'offline' }; $o = Act 'x'
Check 'offline: says so, keeps the flag for the next run' (($o -match 'next run') -and ((Get-Content "$D\maint-state.json" -Raw) -match 'winver-due') -and -not ($MA.Calls -match 'reg ')) ($o -join ' / ')
function Invoke-WebRequest { $global:MA.Calls.Add('web'); [pscustomobject]@{ Content = $global:MA.Page } }

Section 'scheduled checks'
Fresh; $old = $now.AddDays(-200).ToString('o'); @{ 'claude-quarterly' = $old; 'claude-halfyear' = $old; 'claude-yearly' = $now.ToString('o') } | ConvertTo-Json | Set-Content "$D\maint-state.json"
$o = Act 'x'
$ms = Get-Content "$D\maint-state.json" -Raw | ConvertFrom-Json
Check 'quarterly due: re-benchmark; half-year due: dust reminder; both clocks restarted' (((Get-Content "$D\optimize-calls.txt") -join ',') -eq 'optimize benchmark=True' -and (Ids) -contains 'dust' -and ([datetime]$ms.'claude-quarterly') -gt $now.AddMinutes(-1) -and ([datetime]$ms.'claude-halfyear') -gt $now.AddMinutes(-1)) ((Get-Content "$D\optimize-calls.txt") -join ',')
Fresh; @{ 'claude-quarterly' = $now.ToString('o'); 'claude-halfyear' = $now.ToString('o'); 'claude-yearly' = $now.AddDays(-400).ToString('o') } | ConvertTo-Json | Set-Content "$D\maint-state.json"
[void](Act 'x')
Check 'yearly due: a full optimize run' (((Get-Content "$D\optimize-calls.txt") -join ',') -eq 'optimize benchmark=False') ((Get-Content "$D\optimize-calls.txt") -join ',')
Fresh; [void](Act 'x')
Check 'nothing due: nothing runs' (-not (Test-Path "$D\optimize-calls.txt") -and -not (Ids)) ''
Finish
