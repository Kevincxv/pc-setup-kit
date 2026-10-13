# game-saves.ps1: every game's saves backed up by Ludusavi when the owner turned it on - once a day, never under a game,
# huge cache files left out (said once), a failure said as a WARNING. A stand-in Ludusavi (it logs what it was asked and
# answers in its --api JSON) - nothing real is backed up or installed.
. "$PSScriptRoot\..\lib.ps1"
$gs = "$Src\game-saves.ps1"
if (-not (Test-Path $gs)) { Skip 'game-saves' 'not installed here'; Finish }
$fake = "$Work\ludusavi.ps1"; $log = "$Work\lud.log"; $env:LUD_LOG = $log
Set-Content $fake @'
$a = "$args"; Add-Content $env:LUD_LOG $a
if ($env:LUD_FAIL -and $a -match 'backup --force') { '{"errors":{"someGamesFailed":true}}'; exit 1 }
$big = if ($env:LUD_BIG) { ',"C:/G/cache.bin":{"bytes":3000000000}' } else { '' }
$ch = if ($env:LUD_SAME) { '"new":0,"different":0,"same":2' } else { '"new":1,"different":1,"same":0' }
'{"overall":{"totalGames":2,"processedBytes":2097152,"changedGames":{' + $ch + '}},"games":{"Game A":{"files":{"C:/G/save1.dat":{"bytes":1024}' + $big + '}},"Game B":{"files":{"C:/G/b.sav":{"bytes":2048}}}}}'
exit 0
'@
$opt = "$Work\kit-options.txt"; $state = "$Work\gs.json"; $cfg = "$Work\lud-config"; $dest = "$Work\saves"
New-Item $cfg -ItemType Directory -Force | Out-Null
Set-Content "$cfg\config.yaml" "backup:`n  path: `"x`"`n  filter:`n    ignoredPaths: []`n    ignoredRegistry: []`nrestore:`n  path: `"x`"`n"
function GS([hashtable]$p) { $p.Exe = $fake; $p.Options = $opt; $p.State = $state; $p.ConfigDir = $cfg; $p.Dest = $dest; if (-not $p.GameCheck) { $p.GameCheck = { $null } }; @(& $gs @p) }
function Asked { @(Get-Content $log -ErrorAction SilentlyContinue) }

Section 'off unless the owner turns it on'
Set-Content $opt 'claude=on'; Clear-Path $log
$o = GS @{ Check = $true }
Check 'off: the check does nothing, says nothing' (-not $o -and -not (Asked)) ($o -join ' / ')

Section 'turned on (Back up now)'
$o = GS @{ Run = $true }
Check 'turned on, recorded' ((Get-Content $opt) -contains 'gamesaves=on') ((Get-Content $opt) -join ',')
Check 'backed up: zipped, the last 3 copies per game, into the backup folder, without asking' (@(Asked) -match "backup --force --path $([regex]::Escape($dest)) --format zip --compression zstd --full-limit 3 --api") ((Asked) -join ' / ')
Check '... and said, with how many games had new saves' (($o -join ' ') -match 'Game saves: 2 of 2 games had new saves') ($o -join ' / ')
Check '... its own settings point Ludusavi''s restore at the backups' ((Get-Content "$cfg\config.yaml" -Raw) -match ('restore:\r?\n  path: "' + [regex]::Escape(($dest -replace '\\', '/')) + '"')) (Get-Content "$cfg\config.yaml" -Raw)

Section 'once a day, never under a game'
Clear-Path $log
$o = GS @{ Check = $true }
Check 'backed up less than a day ago: nothing' (-not $o -and -not (Asked)) ''
$o = GS @{ Check = $true; Now = (Get-Date).AddHours(21); GameCheck = { 'NBA 2K17' } }
Check 'due, but a game is running: waits (nothing asked)' (-not $o -and -not (Asked)) ''
$env:LUD_SAME = '1'; $o = GS @{ Check = $true; Now = (Get-Date).AddHours(21) }; $env:LUD_SAME = $null
Check 'due, no game: backed up; nothing new is said as such' (($o -join ' ') -match 'all 2 games already backed up') ($o -join ' / ')

Section 'a huge cache in a save folder'
$env:LUD_BIG = '1'; $o = GS @{ Run = $true }; $env:LUD_BIG = $null
Check 'left out - in its settings and remembered - and said once' ((Get-Content "$cfg\config.yaml" -Raw) -match '- "C:/G/cache.bin"' -and ((Get-Content $state -Raw | ConvertFrom-Json).ignored -contains 'C:/G/cache.bin') -and ($o -join ' ') -match 'left out 1 huge cache file') ($o -join ' / ')
$env:LUD_BIG = '1'; $o = GS @{ Run = $true }; $env:LUD_BIG = $null
Check '... not said again' (($o -join ' ') -notmatch 'left out') ($o -join ' / ')

Section 'Ludusavi failing'
$env:LUD_FAIL = '1'; $o = GS @{ Run = $true }; $env:LUD_FAIL = $null
Check 'a WARNING with the reason (the maintenance looks at it)' (($o -join ' ') -match '^WARNING: game save backup failed \(Ludusavi exit 1\).*someGamesFailed') ($o -join ' / ')
Finish
