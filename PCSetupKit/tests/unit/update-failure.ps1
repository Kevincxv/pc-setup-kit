# kit-update.ps1 failing half-way (a full disk, an antivirus holding a file): the previous version is put back right
# away - never a mix of old and new scripts. Offline: GitHub is mocked, the "release" is a zip of this kit.
. "$PSScriptRoot\..\lib.ps1"
$ku = "$Src\kit-update.ps1"
if (-not (Test-Path $ku)) { Skip 'update-failure' 'not installed here'; Finish }
$kd = "$Work\kit"; $cd = "$Work\cl"; $td = "$Work\tray"; $sv = "$Work\saved"
New-Item "$kd\tests", "$kd\claude", $cd, $td -ItemType Directory -Force | Out-Null
'repo=owner/repo' | Set-Content "$kd\kit-source.txt"; 'v2026.01.01' | Set-Content "$kd\kit-version.txt"
"'old setup'" | Set-Content "$kd\setup.ps1"; "'old test'" | Set-Content "$kd\tests\x.ps1"
foreach ($f in 'health-check.ps1', 'status.ps1', 'claude-bg-maint.ps1') { "'old $f'" | Set-Content "$cd\$f" }
'$false' | Set-Content "$cd\ai-enabled.ps1"; 'old tray' | Set-Content "$td\Messiah Tray.ahk"
# the new "release": this kit, zipped the way GitHub does (one top folder)
$rel = "$Work\rel\owner-repo-2026.02.01"; New-Item $rel -ItemType Directory -Force | Out-Null
Copy-Item $Kit "$rel\PCSetupKit" -Recurse; Copy-Item "$Src\*.ps1" "$rel\PCSetupKit\claude" -Force
Compress-Archive "$Work\rel\*" "$Work\rel.zip"
$mocked = 'Get-ScheduledTask', 'Invoke-RestMethod', 'Invoke-WebRequest'
Import-MockTargets $mocked   # load their modules BEFORE defining the mocks (see lib.ps1)
function Invoke-RestMethod { [pscustomobject]@{ tag_name = 'v2026.02.01'; body = '' } }
function Invoke-WebRequest { param($Uri, $OutFile, [switch]$UseBasicParsing, $TimeoutSec, $Method, $Headers) if ($OutFile) { Copy-Item "$Work\rel.zip" $OutFile } }
function Get-ScheduledTask { }   # (the real tray is never restarted)
if (-not (Assert-Mocks $mocked)) { Finish }

Section 'a maintenance script held open (an antivirus scan) while the update copies'
$lock = [IO.File]::Open("$cd\status.ps1", 'Open', 'Read', 'Read')   # (readable - the old version gets saved - but not writable)
try { $o = @(& $ku -KitDir $kd -ClaudeDir $cd -TrayDir $td -Saved $sv -Force 2>&1 | ForEach-Object { "$_" }) } finally { $lock.Dispose() }
Check 'the update fails and says so, with the previous version put back' ("$o" -match "couldn't install v2026\.02\.01" -and "$o" -match 'put v2026\.01\.01 back as it was') ($o -join ' / ')
Check '... the version is still the old one' ((Get-Content "$kd\kit-version.txt").Trim() -eq 'v2026.01.01') ''
Check '... the maintenance scripts are all old again (no mix)' ((Get-Content "$cd\health-check.ps1") -eq "'old health-check.ps1'" -and (Get-Content "$cd\claude-bg-maint.ps1") -eq "'old claude-bg-maint.ps1'") ''
Check '... the kit folder too (its tests and setup)' ((Get-Content "$kd\setup.ps1") -eq "'old setup'" -and (Test-Path "$kd\tests\x.ps1")) ''
Check '... and it is tried again next time (not skipped)' (-not "$((Get-Content "$cd\update-state.json" -Raw | ConvertFrom-Json).skip)") ''

Section 'the same release once nothing is in the way'
$o = @(& $ku -KitDir $kd -ClaudeDir $cd -TrayDir $td -Saved $sv -Force 2>&1 | ForEach-Object { "$_" })
Check 'installed' ("$o" -match 'updated v2026\.01\.01 -> v2026\.02\.01' -and (Get-Content "$kd\kit-version.txt").Trim() -eq 'v2026.02.01') ($o -join ' / ')
'{"skip": null, "failing": "v2026.03.01", "failingSince": "not a date"}' | Set-Content "$cd\update-state.json"
function Invoke-RestMethod { [pscustomobject]@{ tag_name = 'v2026.03.01'; body = '' } }
function Invoke-WebRequest { param($Uri, $OutFile, [switch]$UseBasicParsing, $TimeoutSec, $Method, $Headers) throw 'network down' }
$o = @(& $ku -KitDir $kd -ClaudeDir $cd -TrayDir $td -Saved $sv -Force 2>&1 | ForEach-Object { "$_" })
Check 'a damaged date in its state + the download failing: a plain retry message, no error of its own' ("$o" -match "^Kit update: couldn't install v2026\.03\.01 \(network down\) - will retry next time$") ($o -join ' / ')
Finish
