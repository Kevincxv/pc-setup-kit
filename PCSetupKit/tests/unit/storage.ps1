# storage.ps1: the drives, the games on them, leftovers of uninstalled games, the same game twice, and a Steam game moved
# to another drive. Two made-up drives (folders standing in for C: and D:), a made-up Steam and Epic; Steam is never
# asked to exit and nothing outside the test folder is touched.
. "$PSScriptRoot\..\lib.ps1"
$st = "$Src\storage.ps1"
if (-not (Test-Path $st)) { Skip 'storage' 'not installed here'; Finish }
$C = "$Work\C"; $D = "$Work\D"; $steam = "$C\Steam"; $epic = "$Work\Epic"
function File([string]$p, [long]$size) { New-Item (Split-Path $p) -ItemType Directory -Force | Out-Null; $f = [IO.File]::Create($p); $f.SetLength($size); $f.Close() }
function Acf([string]$lib, [string]$id, [string]$name, [string]$dir, [long]$size) {
    New-Item "$lib\steamapps" -ItemType Directory -Force | Out-Null
    "`"AppState`"`n{`n`t`"appid`"`t`t`"$id`"`n`t`"name`"`t`t`"$name`"`n`t`"installdir`"`t`t`"$dir`"`n`t`"SizeOnDisk`"`t`t`"$size`"`n}" | Set-Content "$lib\steamapps\appmanifest_$id.acf" -Encoding UTF8   # (UTF-8, like Steam's own)
}
New-Item "$steam\steamapps", $D, $epic -ItemType Directory -Force | Out-Null
"`"libraryfolders`"`n{`n`t`"0`"`n`t{`n`t`t`"path`"`t`t`"$($steam -replace '\\', '\\')`"`n`t`t`"apps`"`n`t`t{`n`t`t`t`"100`"`t`t`"3000000`"`n`t`t}`n`t}`n}" | Set-Content "$steam\steamapps\libraryfolders.vdf"
Acf $steam 100 "Game One$([char]0xAE)" 'GameOne' 3000000
File "$steam\steamapps\common\GameOne\game.exe" 1MB; File "$steam\steamapps\common\GameOne\data\pak1.bin" 2MB; File "$steam\steamapps\common\GameOne\data\pak2.bin" 5KB
File "$steam\steamapps\shadercache\100\cache.bin" 12MB   # (the installed game's own: stays)
Acf $steam 228980 'Steamworks Common Redistributables' '_CommonRedist' 1000; File "$steam\steamapps\shadercache\228980\x.bin" 12MB   # (Steam's runtime: not a game, not a leftover)
File "$steam\steamapps\shadercache\999\cache.bin" 12MB; File "$steam\steamapps\workshop\content\998\mod.bin" 15MB   # (uninstalled games')
File "$steam\steamapps\common\OldGame\saves\slot1.sav" 120MB   # (no game uses it: maybe saves - never removed by itself)
File "$C\Games\NBA 2K\NBA 2K20\nba2k20.exe" 600MB; File "$C\Games\NBA 2K\NBA 2K21\nba2k21.exe" 700MB
File "$C\Games\Game One\GameOne.exe" 600MB   # (the same game as Steam's, again)
File "$C\Games\Tiny Tool\tool.exe" 1MB   # (too small to be a game)
File "$D\Epic Games\EpicGame\epic.exe" 1MB
@{ DisplayName = 'Epic Game'; AppName = 'eg'; InstallLocation = "$D\Epic Games\EpicGame"; InstallSize = 5GB } | ConvertTo-Json | Set-Content "$epic\eg.item"
$common = @{ Dir = $Work; SteamPath = $steam; EpicDir = $epic; Roots = @("C=$C", "D=$D"); NoProcess = $true }
function Scan { & $st -Scan -Force @common | Out-Null; Get-Content "$Work\storage.json" -Raw | ConvertFrom-Json }

Section 'the scan: games on each drive, leftovers, the same game twice'
$j = Scan
$names = @($j.games | ForEach-Object name)
Check 'Steam games from its manifests (sizes from Steam; the (R) sign left out), Steam''s runtimes left out' ('Game One' -in $names -and 'Steamworks Common Redistributables' -notin $names -and ($j.games | Where-Object { $_.name -eq 'Game One' -and $_.store -eq 'Steam' }).sizeGB -eq 0) ($names -join ', ')
Check 'a folder of several games: each one, named once (NBA 2K21, not "NBA 2K NBA 2K21")' ('NBA 2K20' -in $names -and 'NBA 2K21' -in $names -and 'Tiny Tool' -notin $names) ($names -join ', ')
Check 'Epic games from its manifests, on their drive' (@($j.games | Where-Object { $_.store -eq 'Epic' -and $_.drive -eq 'D' -and $_.sizeGB -eq 5 }).Count -eq 1) ''
Check 'only Steam games can be moved' (@($j.games | Where-Object movable | ForEach-Object name) -join ',' -eq 'Game One') ''
$lk = @($j.leftovers | ForEach-Object { "$($_.kind):$(Split-Path $_.path -Leaf):$($_.safe)" })
Check 'leftovers: shader caches and Workshop mods of uninstalled games (safe), a folder no game uses (not safe)' ('shadercache:999:True' -in $lk -and 'workshop:998:True' -in $lk -and 'folder:OldGame:False' -in $lk) ($lk -join ' | ')
Check '... but never the installed game''s own shader cache, or Steam''s runtime''s' ('shadercache:100:True' -notin $lk -and 'shadercache:228980:True' -notin $lk) ($lk -join ' | ')
Check 'the same game twice (Steam and a folder copy): shown' (@($j.duplicates | Where-Object { $_.name -match 'Game One' -and @($_.places).Count -eq 2 }).Count -eq 1) (($j.duplicates | ConvertTo-Json -Compress))

Section 'clean: only the safe leftovers'
$o = @(& $st -Clean @common)
Check 'shader caches and mods of uninstalled games removed, said with the size' (-not (Test-Path "$steam\steamapps\shadercache\999") -and -not (Test-Path "$steam\steamapps\workshop\content\998") -and "$o" -match '^Storage: removed 2 leftovers .* - 27 MB$') "$o"
Check '... the installed game''s cache, the runtime''s and the folder that may hold saves stay' ((Test-Path "$steam\steamapps\shadercache\100") -and (Test-Path "$steam\steamapps\shadercache\228980") -and (Test-Path "$steam\steamapps\common\OldGame\saves\slot1.sav")) ''
Check 'nothing left to clean: says nothing' (-not (@(& $st -Clean @common) | Where-Object { $_ })) ''

Section 'the app''s requests: a leftover folder to the Recycle Bin - only one the scan listed'
'{"cmd":"recycle","path":"' + ("$Work\Epic" -replace '\\', '\\') + '"}' | Set-Content "$Work\storage-request.json"
$env:PCKIT_IN_TESTS = '1'; & $st -Request @common | Out-Null
$s = Get-Content "$Work\storage-status.json" -Raw | ConvertFrom-Json
Check 'a folder the scan didn''t list: refused, untouched' ($s.state -eq 'failed' -and (Test-Path "$Work\Epic\eg.item")) "$($s.state): $($s.text)"
'{"cmd":"recycle","path":"' + ("$steam\steamapps\common\OldGame" -replace '\\', '\\') + '"}' | Set-Content "$Work\storage-request.json"
& $st -Request @common | Out-Null
$s = Get-Content "$Work\storage-status.json" -Raw | ConvertFrom-Json
Check 'a listed leftover folder: to the Recycle Bin, said' ($s.state -eq 'done' -and -not (Test-Path "$steam\steamapps\common\OldGame") -and $s.text -match 'Recycle Bin') "$($s.state): $($s.text)"

Section 'a Steam game moved to another drive'
$o = @(& $st -Move 100 -To C @common)
Check 'to the drive it''s already on: said, nothing done' ("$o" -match 'already on C:' -and (Test-Path "$steam\steamapps\common\GameOne\game.exe")) "$o"
$o = @(& $st -Move 100 -To Q @common)
Check 'to a drive that isn''t there: said, nothing done' ("$o" -match "no drive Q:" -and (Test-Path "$steam\steamapps\common\GameOne\game.exe")) "$o"
New-Item "$D\SteamLibrary\steamapps\common\GameOne" -ItemType Directory -Force | Out-Null; Acf "$D\SteamLibrary" 1 'x' 'x' 0; Remove-Item "$D\SteamLibrary\steamapps\appmanifest_1.acf"
$vdf0 = Get-Content "$steam\steamapps\libraryfolders.vdf" -Raw
$o = @(& $st -Move 100 -To D @common)
Check 'a folder of that name already on the other drive: refused, the game stays' ("$o" -match 'already exists' -and (Test-Path "$steam\steamapps\common\GameOne\game.exe") -and (Test-Path "$steam\steamapps\appmanifest_100.acf")) "$o"
Remove-Item "$D\SteamLibrary" -Recurse -Force
$o = @(& $st -Move 100 -To D @common)
$nd = "$D\SteamLibrary\steamapps"
Check 'moved: every file there (the same count and bytes), said' ((Test-Path "$nd\common\GameOne\data\pak2.bin") -and (Get-Item "$nd\common\GameOne\data\pak1.bin").Length -eq 2MB -and "$o" -match '^Storage: moved Game One .* from C: to D:') "$o"
Check '... Steam''s record of it and its shader cache went along; the old copy is gone' ((Test-Path "$nd\appmanifest_100.acf") -and (Test-Path "$nd\shadercache\100\cache.bin") -and -not (Test-Path "$steam\steamapps\appmanifest_100.acf") -and -not (Test-Path "$steam\steamapps\common\GameOne")) ''
$vdf = Get-Content "$steam\steamapps\libraryfolders.vdf" -Raw
Check '... a new Steam library made on that drive and added to Steam''s list (the old entries kept)' ($vdf -match '"path"\s+"[^"]*\\\\D\\\\SteamLibrary"' -and $vdf -match '"1"' -and $vdf.StartsWith($vdf0.Substring(0, 40))) $vdf
$j = Scan
Check '... and the scan finds it on D:' (@($j.games | Where-Object { $_.name -eq 'Game One' -and $_.drive -eq 'D' -and $_.store -eq 'Steam' }).Count -eq 1) ''
'{"cmd":"move","appid":"100","to":"C"}' | Set-Content "$Work\storage-request.json"
& $st -Request @common | Out-Null
$s = Get-Content "$Work\storage-status.json" -Raw | ConvertFrom-Json
Check 'the app''s request: moved back (to the first library), said in its status' ($s.state -eq 'done' -and (Test-Path "$steam\steamapps\common\GameOne\game.exe") -and (Test-Path "$steam\steamapps\appmanifest_100.acf") -and -not (Test-Path "$nd\common\GameOne")) "$($s.state): $($s.text)"
Remove-Item Env:\PCKIT_IN_TESTS
Finish
