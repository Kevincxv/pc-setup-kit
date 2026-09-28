# optimize.ps1 (the no-AI /pc-optimize) with WinSAT, hardware queries, installed programs and Notepad mocked; the
# monitor fix and the maintenance run are stand-ins. Report written into a sandbox profile.
. "$PSScriptRoot\..\lib.ps1"
$H = "$Work\home"; $D = "$H\.claude"; New-Item $D, "$H\Documents" -ItemType Directory -Force | Out-Null
Copy-Item "$Src\optimize.ps1", "$Src\todo.ps1" $D
'"Monitor: Fast Monitor set to 165Hz (was 60Hz)"' | Set-Content "$D\display-refresh.ps1"
'param([switch]$Force, [switch]$Unattended) "bg-maint Force=$Force Unattended=$Unattended" | Add-Content "$PSScriptRoot\calls.txt"; "yearly-at-run=$((Get-Content "$PSScriptRoot\maint-state.json" -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json).''claude-yearly'')" | Add-Content "$PSScriptRoot\calls.txt"; "Checked now in 9s", "[Drivers]", "NVIDIA: 617.14 is up to date" | Set-Content "$PSScriptRoot\maint-report.txt"' | Set-Content "$D\claude-bg-maint.ps1"
$mocked = 'Start-Process', 'Get-CimInstance', 'Get-PhysicalDisk', 'Get-ItemProperty'
if (-not (Test-Tripwire "$D\optimize.ps1" $mocked)) { Finish }
Import-MockTargets $mocked   # load their Windows modules BEFORE defining the mocks (see lib.ps1)
function Start-Process { param($FilePath, $ArgumentList, $WindowStyle, [switch]$PassThru, [switch]$Wait) Add-Content "$D\calls.txt" "run $FilePath $ArgumentList"; [pscustomobject]@{ ExitCode = 0 } }
function Get-CimInstance { param($ClassName) switch ($ClassName) {
        'Win32_WinSAT' { if ($global:Sat) { [pscustomobject]$global:Sat } }
        'Win32_Processor' { [pscustomobject]@{ Name = 'Test CPU 8-Core' } }
        'Win32_BaseBoard' { [pscustomobject]@{ Manufacturer = 'TestBoard Inc.'; Product = 'X650' } }
        'Win32_BIOS' { [pscustomobject]@{ SMBIOSBIOSVersion = '3.20'; ReleaseDate = [datetime]'2026-01-15' } }
        'Win32_PhysicalMemory' { 1..2 | ForEach-Object { [pscustomobject]@{ Capacity = 16GB; ConfiguredClockSpeed = 6000; PartNumber = 'KIT-6000 ' } } }
        'Win32_VideoController' { [pscustomobject]@{ Name = 'Test GPU 9000'; DriverVersion = '32.0.1' }, [pscustomobject]@{ Name = 'Microsoft Basic Display Adapter'; DriverVersion = '1' } } } }
function Get-PhysicalDisk { [pscustomobject]@{ FriendlyName = 'Test NVMe'; Size = 2000GB; HealthStatus = 'Healthy' } }
function Get-ItemProperty { param($Path) if ("$Path" -match 'Uninstall') { $global:Apps | ForEach-Object { [pscustomobject]@{ DisplayName = $_ } } } else { [pscustomobject]@{ ProductName = 'Windows 11 Pro'; DisplayVersion = '25H2'; CurrentBuild = '26200' } } }
if (-not (Assert-Mocks $mocked)) { Finish }
# switches passed by name: a list would pass "-Benchmark" as plain text
function Opt([hashtable]$A = @{}) { $u = $env:USERPROFILE; $env:USERPROFILE = $H; try { @(& "$D\optimize.ps1" @A) } finally { $env:USERPROFILE = $u } }
function Calls { @(Get-Content "$D\calls.txt" -ErrorAction SilentlyContinue) }
function Reset-O { foreach ($f in 'calls.txt', 'benchmarks.json', 'maint-todo.txt', 'todo-scripted.json', 'maint-state.json') { Clear-Path "$D\$f" }; Clear-Path "$H\Documents\PC Setup Kit report.txt"
    $global:Sat = @{ CPUScore = 9.3; MemoryScore = 9.3; D3DScore = 9.9; GraphicsScore = 9.9; DiskScore = 8.4 }; $global:Apps = @('Steam', 'ASUS Armoury Crate Service', 'McAfee LiveSafe'); '' | Set-Content "$D\game-check.ps1" }

Section 'a full run (end of setup, tray "Optimize this PC now", yearly)'
Reset-O; $o = Opt
$rep = Get-Content "$H\Documents\PC Setup Kit report.txt" -Raw -ErrorAction SilentlyContinue
Check 'monitors set to their best refresh rate' ($o -match 'Fast Monitor set to 165Hz') ($o -join ' / ')
Check 'vendor background apps pointed out as an item (never removed); other programs not mentioned' (((Get-Content "$D\maint-todo.txt") -join ' ') -match 'Armoury Crate.*McAfee' -and ((Get-Content "$D\maint-todo.txt") -join ' ') -notmatch 'Steam') ((Get-Content "$D\maint-todo.txt") -join ' ')
Check 'benchmark run (WinSAT formal) and saved as the baseline' ((Calls) -match 'run winsat formal' -and $o -match 'saved as the baseline' -and @(Get-Content "$D\benchmarks.json" -Raw | ConvertFrom-Json | ForEach-Object { $_ }).Count -eq 1) ((Calls) -join ' / ')
Check 'then the full maintenance, once' (@(Calls | Where-Object { $_ -match '^bg-maint' }).Count -eq 1 -and (Calls) -contains 'bg-maint Force=True Unattended=True') ((Calls) -join ' / ')
$ms = Get-Content "$D\maint-state.json" -Raw | ConvertFrom-Json
$y = ((Calls) | Where-Object { $_ -like 'yearly-at-run=*' }) -replace '^yearly-at-run='
Check '... already set when its maintenance run starts (else that run would start the yearly optimize again)' ($y -and ([datetime]$y) -gt (Get-Date).AddMinutes(-1)) ((Calls) -join ' / ')
Check 'scheduled checks count from today' ((([datetime]$ms.'claude-quarterly') -gt (Get-Date).AddMinutes(-1)) -and (([datetime]$ms.'claude-yearly') -gt (Get-Date).AddMinutes(-1)) -and (([datetime]$ms.'claude-halfyear') -gt (Get-Date).AddMinutes(-1))) ''
Check 'a readable report in Documents: this PC, what was done (incl. the maintenance), what needs you' ($rep -match 'THIS PC' -and $rep -match 'CPU: Test CPU 8-Core' -and $rep -match 'TestBoard Inc\. X650, BIOS 3\.20' -and $rep -match 'RAM: 32 GB, 2 stick\(s\) at 6000 MT/s \(KIT-6000\)' -and $rep -match 'Graphics: Test GPU 9000' -and $rep -notmatch 'Basic Display' -and $rep -match 'Drive: Test NVMe, 2000 GB, Healthy' -and $rep -match 'NVIDIA: 617\.14 is up to date' -and $rep -match 'WHAT NEEDS YOU\s+- These came with the PC') $rep
Check '... and opened for the owner' ((Calls) -match 'run notepad\.exe') ((Calls) -join ' / ')

Section 'the quarterly benchmark against the baseline'
$global:Sat.CPUScore = 7.5; Clear-Path "$D\calls.txt"; $o = Opt @{ Benchmark = $true }
Check 'more than 15% slower: WARNING and an item with the likely causes' ($o -match 'WARNING: benchmark is more than 15% lower than at setup: CPU 7\.5 \(was 9\.3\)' -and ((Get-Content "$D\maint-todo.txt") -join ' ') -match 'dust') ($o -join ' / ')
Check '... only the benchmark (no maintenance run, no report window)' (-not ((Calls) -match 'bg-maint|notepad')) ((Calls) -join ' / ')
$global:Sat.CPUScore = 9.2; $o = Opt @{ Benchmark = $true }
Check 'back to normal: "as fast as at setup", the item goes' ($o -match 'as fast as at setup' -and -not (((Get-Content "$D\maint-todo.txt") -join ' ') -match 'scores lower')) ($o -join ' / ')
Check '... the baseline stays the first result' ((@(Get-Content "$D\benchmarks.json" -Raw | ConvertFrom-Json | ForEach-Object { $_ })[0].cpu) -eq 9.3) ''
$global:Sat = $null; $o = Opt @{ Benchmark = $true }
Check 'WinSAT gives no scores (e.g. a virtual machine): says so, no error' ($o -match 'could not run') ($o -join ' / ')

Section 'never in the way'
Reset-O; '"TestGame"' | Set-Content "$D\game-check.ps1"; $o = Opt
Check 'a game is running: held, nothing runs' ($o -match 'held: TestGame' -and -not (Calls)) (($o + (Calls)) -join ' / ')
Reset-O; $o = Opt @{ FromMaintenance = $true }
Check 'called by the maintenance itself: no second maintenance run, no report window' (-not ((Calls) -match 'bg-maint|notepad') -and (Calls) -match 'winsat') ((Calls) -join ' / ')
Finish
