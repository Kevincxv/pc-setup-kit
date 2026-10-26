# What's on the drives (10/25, the owner: "move games between drives and clean leftover shader caches and duplicate
# installs"). The app's Games > Storage page shows storage.json:
#   drives     each fixed drive: size, free, SSD or not, the Windows drive
#   games      Steam (its libraries' manifests), Epic (its manifests), and other installed games (uninstall entries of
#              game publishers, folders under <drive>:\Games) - name, where, size, the store; Steam games can be moved
#   leftovers  what uninstalled games left behind: Steam shader caches and Workshop downloads of games no longer installed
#              (safe - Steam fetches them again if the game comes back), abandoned downloads, game folders no installed
#              game uses (those can hold saves - shown, removed only when the owner says so, to the Recycle Bin)
#   duplicates the same game installed twice (two Steam libraries, or Steam and another copy) - shown, never removed
# -Scan (default): the above, at most once a day from health-check (sizes of non-Steam folders take a while).
# -Clean: the safe leftovers, now (periodic-maint.ps1's monthly cleanup; the app's button) - a line for the report.
# -Move <appid> -To <drive letter>: a Steam game to another drive - Steam closed first (asked to exit; started again after),
#   the files copied (robocopy), checked (count and bytes), then the manifest moved and the old copy deleted; a library
#   is made on that drive if it has none. Nothing is deleted unless the copy checks out.
# -Request: what the app asked for (storage-request.json {cmd: move|clean|recycle, appid, to, path}), its progress in
#   storage-status.json {state: working|done|failed, text, pct}.
# -Root / -SteamPath / -EpicDir / -NoProcess: tests (a made-up drive, Steam and Epic; Steam never asked to exit).
param([switch]$Scan, [switch]$Clean, [string]$Move, [string]$To, [switch]$Request, [switch]$Force,
    [string]$Dir = $PSScriptRoot, [string]$SteamPath, [string]$EpicDir = "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests", [string[]]$Roots, [switch]$NoProcess)
$ErrorActionPreference = 'SilentlyContinue'
$out = "$Dir\storage.json"; $statusFile = "$Dir\storage-status.json"
if (-not $SteamPath) { $SteamPath = "$((Get-ItemProperty 'HKCU:\Software\Valve\Steam').SteamPath)" -replace '/', '\' }
function GB($b) { [Math]::Round([double]$b / 1GB, 1) }
# the drive a path is on (tests: -Roots "D=<folder>" stand in for drives)
$rootMap = [ordered]@{}; foreach ($r in $Roots) { if ($r -match '^([A-Za-z])=(.+)$') { $rootMap[$Matches[1].ToUpper()] = $Matches[2].TrimEnd('\') } }
function DriveOf([string]$p) { foreach ($k in $rootMap.Keys) { if ($p.StartsWith($rootMap[$k], [StringComparison]::OrdinalIgnoreCase)) { return $k } }; if ($p) { $p.Substring(0, 1).ToUpper() } }
function Size([string]$p) {   # a folder's size, not following junctions (C:\Games\NBA 2K\16 points into another folder - counted there)
    $t = 0L; $st = New-Object Collections.Stack; $st.Push((Get-Item -LiteralPath $p -Force))
    while ($st.Count) {
        $d = $st.Pop()
        try { foreach ($i in $d.EnumerateFileSystemInfos()) { if ($i -is [IO.FileInfo]) { $t += $i.Length } elseif (-not ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $st.Push($i) } } } catch { }   # (a folder Windows keeps closed: skipped)
    }
    $t
}
function Status([string]$state, [string]$text, $pct) { [pscustomobject]@{ state = $state; text = $text; pct = $pct; at = (Get-Date).ToString('o') } | ConvertTo-Json -Compress | Set-Content $statusFile -Encoding UTF8 }

# --- Steam: its libraries (libraryfolders.vdf) and each one's games (appmanifest_<id>.acf) ---
function Get-SteamLibs {
    $vdf = @("$SteamPath\steamapps\libraryfolders.vdf", "$SteamPath\config\libraryfolders.vdf") | Where-Object { Test-Path $_ } | Select-Object -First 1
    @(@(if ($vdf) { Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' } }) + $(if ($SteamPath) { $SteamPath }) |
        Where-Object { $_ -and (Test-Path "$_\steamapps") } | ForEach-Object { (Get-Item -LiteralPath $_).FullName.TrimEnd('\') } | Sort-Object -Unique)
}
function Read-Acf([string]$f) {
    $t = [IO.File]::ReadAllText($f); $o = @{}
    foreach ($k in 'appid', 'name', 'installdir', 'SizeOnDisk', 'LastUpdated', 'StateFlags') { if ($t -match "`"$k`"\s+`"([^`"]*)`"") { $o[$k] = $Matches[1] } }
    if ($o.name) { $o.name = ($o.name -replace '[\u00AE\u2122]', '').Trim() }   # ("Call of Duty(R)")
    $o
}
function Get-SteamGames {
    foreach ($l in Get-SteamLibs) {
        foreach ($f in Get-ChildItem "$l\steamapps\appmanifest_*.acf") {
            $a = Read-Acf $f.FullName; if (-not $a.appid -or -not $a.installdir) { continue }
            if ($a.name -match '^(Steamworks Common Redistributables|Proton|Steam Linux Runtime)') { continue }
            $path = "$l\steamapps\common\$($a.installdir)"
            [pscustomobject]@{ name = $a.name; id = $a.appid; store = 'Steam'; path = $path; library = $l; drive = (DriveOf $l); sizeGB = GB $a.SizeOnDisk; movable = $true; exists = (Test-Path -LiteralPath $path) }
        }
    }
}
function Get-OtherGames([string[]]$skip) {
    # Epic: its manifests (.item, JSON)
    foreach ($f in Get-ChildItem "$EpicDir\*.item") {
        $j = try { Get-Content $f.FullName -Raw | ConvertFrom-Json } catch { $null }; if (-not $j.InstallLocation -or -not (Test-Path -LiteralPath $j.InstallLocation)) { continue }
        [pscustomobject]@{ name = $j.DisplayName; id = "epic:$($j.AppName)"; store = 'Epic'; path = $j.InstallLocation; drive = (DriveOf $j.InstallLocation); sizeGB = GB $j.InstallSize; movable = $false }
    }
    # uninstall entries of game publishers and launchers (Battle.net, EA, Ubisoft, Riot, Rockstar, ...), and <drive>:\Games\*
    $pub = 'Activision|Blizzard|Electronic Arts|EA Games|Ubisoft|Riot Games|Rockstar|2K|Bethesda|Mojang|Epic Games|CD PROJEKT|Bandai|Capcom|SEGA|Square Enix|Krafton|miHoYo|HoYoverse'
    $seen = @{}; foreach ($s in $skip) { $seen[$s.TrimEnd('\').ToLower()] = 1 }
    $cands = @()
    if (-not $Roots) {
        foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*') {
            foreach ($e in Get-ItemProperty $k) {
                if (-not $e.InstallLocation -or -not $e.DisplayName -or $e.SystemComponent -eq 1) { continue }
                if ("$($e.Publisher)" -notmatch $pub -or "$($e.DisplayName)" -match 'Launcher|Battle\.net|Origin|EA app|Ubisoft Connect|Redistributable|Helper|Anti-?Cheat|Rockstar Games Launcher') { continue }
                $cands += [pscustomobject]@{ name = $e.DisplayName; path = "$($e.InstallLocation)".Trim('"').TrimEnd('\'); store = 'Other' }
            }
        }
    }
    $driveRoots = if ($Roots) { @($rootMap.Values) } else { @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object { "$($_.DriveLetter):\" }) }
    foreach ($r in $driveRoots) {
        foreach ($g in Get-ChildItem (Join-Path $r 'Games') -Directory -Force) {
            # a folder of several games (C:\Games\NBA 2K\16, 17, ...): each one; else the folder itself
            $subs = @(Get-ChildItem $g.FullName -Directory -Force | Where-Object { Get-ChildItem $_.FullName -Filter *.exe -File -Force | Select-Object -First 1 })
            if ($subs.Count -ge 2 -and -not (Get-ChildItem $g.FullName -Filter *.exe -File | Select-Object -First 1)) { foreach ($s in $subs) { $cands += [pscustomobject]@{ name = $(if ($s.Name -like "$($g.Name)*") { $s.Name } else { "$($g.Name) $($s.Name)" }); path = $s.FullName; store = 'Folder'; link = [bool]($s.Attributes -band [IO.FileAttributes]::ReparsePoint) } } }
            else { $cands += [pscustomobject]@{ name = $g.Name; path = $g.FullName; store = 'Folder' } }
        }
    }
    foreach ($c in $cands) {
        $key = $c.path.ToLower(); if (-not $c.path -or $seen[$key] -or -not (Test-Path -LiteralPath $c.path)) { continue }
        if ($seen.Keys | Where-Object { $key.StartsWith("$_\") }) { continue }   # (inside a Steam library or a game already listed)
        $seen[$key] = 1
        $target = if ($c.link) { "$((Get-Item -LiteralPath $c.path -Force).Target)" }
        $size = if ($c.link -and $target -and (Test-Path -LiteralPath $target)) { Size $target } else { Size $c.path }
        if ($size -lt 500MB) { continue }   # (a launcher's stub, a tool - not a game's install)
        [pscustomobject]@{ name = $c.name; id = "path:$($c.path)"; store = $c.store; path = $c.path; drive = (DriveOf $c.path); sizeGB = GB $size; movable = $false; linkTo = $target }
    }
}
function Get-Leftovers([object[]]$steamGames) {
    $have = @{}; foreach ($g in $steamGames) { $have[$g.id] = 1 }
    foreach ($l in Get-SteamLibs) { foreach ($f in Get-ChildItem "$l\steamapps\appmanifest_*.acf") { $have[(Read-Acf $f.FullName).appid] = 1 } }   # (Steam's own runtimes too - not games, not leftovers)
    foreach ($l in Get-SteamLibs) {
        $used = @(Get-ChildItem "$l\steamapps\appmanifest_*.acf" | ForEach-Object { (Read-Acf $_.FullName).installdir })
        foreach ($d in Get-ChildItem "$l\steamapps\shadercache" -Directory -Force | Where-Object { $_.Name -match '^\d+$' -and -not $have[$_.Name] }) {
            $s = Size $d.FullName; if ($s -ge 10MB) { [pscustomobject]@{ kind = 'shadercache'; name = "Shader cache of an uninstalled game ($($d.Name))"; path = $d.FullName; sizeGB = GB $s; bytes = $s; safe = $true } } }
        foreach ($d in Get-ChildItem "$l\steamapps\workshop\content" -Directory -Force | Where-Object { $_.Name -match '^\d+$' -and -not $have[$_.Name] }) {
            $s = Size $d.FullName; if ($s -ge 10MB) { [pscustomobject]@{ kind = 'workshop'; name = "Workshop mods of an uninstalled game ($($d.Name))"; path = $d.FullName; sizeGB = GB $s; bytes = $s; safe = $true } } }
        foreach ($d in Get-ChildItem "$l\steamapps\downloading", "$l\steamapps\temp" -Directory -Force | Where-Object { $_.Name -match '^\d+$' -and -not $have[$_.Name] }) {
            $s = Size $d.FullName; if ($s -ge 10MB) { [pscustomobject]@{ kind = 'download'; name = "An unfinished download ($($d.Name))"; path = $d.FullName; sizeGB = GB $s; bytes = $s; safe = $true } } }
        foreach ($d in Get-ChildItem "$l\steamapps\common" -Directory -Force | Where-Object { $_.Name -notin $used }) {
            $s = Size $d.FullName; if ($s -ge 100MB) { [pscustomobject]@{ kind = 'folder'; name = "$($d.Name) - no installed game uses this folder"; path = $d.FullName; sizeGB = GB $s; bytes = $s; safe = $false } } }
    }
}
function Get-Duplicates([object[]]$games) {
    $norm = { param($n) ($n -replace '(?i)\b(game of the year|goty|definitive|complete|edition|remastered)\b', '' -replace '[^A-Za-z0-9]', '').ToLower() }
    foreach ($g in $games | Where-Object { $_.name } | Group-Object { & $norm $_.name } | Where-Object { $_.Name -and $_.Count -ge 2 }) {
        [pscustomobject]@{ name = $g.Group[0].name; places = @($g.Group | ForEach-Object { "$($_.store): $($_.path) ($($_.sizeGB) GB)" }); sizeGB = ($g.Group | Measure-Object sizeGB -Minimum).Minimum }
    }
}

function Invoke-Scan {
    $drives = if ($Roots) { @() } else {
        $sys = $env:SystemDrive.Substring(0, 1)
        $media = @{}; foreach ($pd in Get-PhysicalDisk) { $media["$($pd.DeviceId)"] = "$($pd.MediaType)" }
        @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.Size -gt 20GB } | Sort-Object DriveLetter | ForEach-Object {
                $dn = (Get-Partition -DriveLetter $_.DriveLetter | Get-Disk).Number
                [pscustomobject]@{ letter = "$($_.DriveLetter)"; label = $_.FileSystemLabel; sizeGB = GB $_.Size; freeGB = GB $_.SizeRemaining; ssd = $media["$dn"] -eq 'SSD'; system = "$($_.DriveLetter)" -eq $sys; fs = $_.FileSystem }
            })
    }
    $steam = @(Get-SteamGames | Where-Object exists)
    $other = @(Get-OtherGames (Get-SteamLibs))
    $games = @($steam | Select-Object name, id, store, path, drive, sizeGB, movable) + $other | Sort-Object sizeGB -Descending
    $left = @(Get-Leftovers $steam)
    [pscustomobject]@{ date = (Get-Date).ToString('o'); drives = @($drives); games = @($games); leftovers = @($left); duplicates = @(Get-Duplicates $games) } | ConvertTo-Json -Depth 5 | Set-Content "$out.tmp" -Encoding UTF8
    Move-Item "$out.tmp" $out -Force
}

# --- the safe leftovers, removed ---
function Invoke-Clean {
    $steam = @(Get-SteamGames | Where-Object exists); $gone = 0L; $n = 0
    foreach ($x in Get-Leftovers $steam | Where-Object safe) { try { [IO.Directory]::Delete($x.path, $true); $gone += $x.bytes; $n++ } catch { } }
    $amt = if ($gone -ge 1GB) { "$(GB $gone) GB" } else { "$([Math]::Round($gone / 1MB)) MB" }
    if ($n) { "Storage: removed $n leftover$(if ($n -gt 1) { 's' }) of uninstalled games (shader caches, mods, unfinished downloads) - $amt" }
}

# --- a Steam game to another drive ---
function Stop-Steam {
    if ($NoProcess) { return $false }
    $p = Get-Process steam; if (-not $p) { return $false }
    Start-Process "$SteamPath\steam.exe" -ArgumentList '-shutdown'
    for ($i = 0; $i -lt 60 -and (Get-Process steam); $i++) { Start-Sleep 1 }
    if (Get-Process steam) { throw 'Steam did not close - close it yourself (Steam > Exit) and try again.' }
    $true
}
function Add-Library([string]$lib) {   # libraryfolders.vdf: a new entry for the library (Steam fills in the rest when it starts)
    $vdf = "$SteamPath\steamapps\libraryfolders.vdf"; if (-not (Test-Path $vdf)) { return }
    $t = [IO.File]::ReadAllText($vdf)
    if ($t -match [regex]::Escape(($lib -replace '\\', '\\'))) { return }
    $n = @([regex]::Matches($t, '(?m)^\t"(\d+)"\s*$') | ForEach-Object { [int]$_.Groups[1].Value } | Measure-Object -Maximum).Maximum + 1
    $entry = "`t`"$n`"`n`t{`n`t`t`"path`"`t`t`"$($lib -replace '\\', '\\')`"`n`t`t`"label`"`t`t`"`"`n`t`t`"contentid`"`t`t`"0`"`n`t`t`"totalsize`"`t`t`"0`"`n`t`t`"apps`"`n`t`t{`n`t`t}`n`t}`n"
    $i = $t.LastIndexOf('}'); [IO.File]::WriteAllText($vdf, $t.Substring(0, $i) + $entry + $t.Substring($i))
}
function Move-SteamGame([string]$appid, [string]$letter) {
    $g = @(Get-SteamGames | Where-Object { $_.id -eq $appid -and $_.exists }) | Select-Object -First 1
    if (-not $g) { throw "That game isn't installed through Steam here." }
    $letter = $letter.Substring(0, 1).ToUpper(); if ($g.drive -eq $letter) { throw "$($g.name) is already on $($letter):." }
    $target = @(Get-SteamLibs | Where-Object { (DriveOf $_) -eq $letter }) | Select-Object -First 1
    $root = if ($Roots) { $rootMap[$letter] } else { "$($letter):\" }
    if (-not $root -or -not (Test-Path $root)) { throw "There's no drive $($letter): here." }
    $free = if ($Roots) { [double]::MaxValue } else { (Get-Volume -DriveLetter $letter).SizeRemaining }
    $need = (Size $g.path) + 2GB
    if ($free -lt $need) { throw "$($letter): has $(GB $free) GB free - $($g.name) needs $(GB $need) GB." }
    $wasOpen = Stop-Steam
    try {
        if (-not $target) { $target = Join-Path $root 'SteamLibrary'; New-Item "$target\steamapps\common" -ItemType Directory -Force | Out-Null; Add-Library $target }
        $dst = "$target\steamapps\common\$(Split-Path $g.path -Leaf)"
        if (Test-Path -LiteralPath $dst) { throw "$dst already exists - move or delete it first." }
        Status 'working' "Moving $($g.name) to $($letter): (copying)" 0
        $srcFiles = @(Get-ChildItem -LiteralPath $g.path -Recurse -File -Force); $srcBytes = ($srcFiles | Measure-Object Length -Sum).Sum
        $rc = Start-Process robocopy.exe -ArgumentList "`"$($g.path)`"", "`"$dst`"", '/E', '/COPY:DAT', '/DCOPY:DAT', '/R:1', '/W:1', '/MT:8', '/NFL', '/NDL', '/NP', '/NJH', '/NJS' -WindowStyle Hidden -PassThru
        while (-not $rc.HasExited) { Start-Sleep 2; $done = (Get-ChildItem -LiteralPath $dst -Recurse -File -Force | Measure-Object Length -Sum).Sum; Status 'working' "Moving $($g.name) to $($letter): (copying)" ([int](100 * $done / [Math]::Max(1, $srcBytes))) }
        $dstFiles = @(Get-ChildItem -LiteralPath $dst -Recurse -File -Force); $dstBytes = ($dstFiles | Measure-Object Length -Sum).Sum
        if ($rc.ExitCode -ge 8 -or $dstFiles.Count -ne $srcFiles.Count -or $dstBytes -ne $srcBytes) {
            [IO.Directory]::Delete($dst, $true)   # (the copy, not the game: the game stays where it was)
            throw "The copy didn't check out ($($dstFiles.Count) of $($srcFiles.Count) files) - $($g.name) stays on $($g.drive):."
        }
        # Steam's record of it, its shader cache and its Workshop mods go along; then the old copy goes
        Move-Item -LiteralPath "$($g.library)\steamapps\appmanifest_$appid.acf" "$target\steamapps\" -Force
        foreach ($sub in "shadercache\$appid", "workshop\content\$appid") { if (Test-Path "$($g.library)\steamapps\$sub") { New-Item (Split-Path "$target\steamapps\$sub") -ItemType Directory -Force | Out-Null; robocopy "$($g.library)\steamapps\$sub" "$target\steamapps\$sub" /E /MOVE /R:1 /W:1 /NFL /NDL /NP /NJH /NJS | Out-Null } }
        if (Test-Path "$($g.library)\steamapps\workshop\appworkshop_$appid.acf") { New-Item "$target\steamapps\workshop" -ItemType Directory -Force | Out-Null; Move-Item "$($g.library)\steamapps\workshop\appworkshop_$appid.acf" "$target\steamapps\workshop\" -Force }
        [IO.Directory]::Delete($g.path, $true)
        $msg = "Storage: moved $($g.name) ($($g.sizeGB) GB) from $($g.drive): to $($letter): - Steam finds it there"
        Status 'done' $msg 100; $msg
    }
    finally { if ($wasOpen) { Start-Process "$SteamPath\steam.exe" -ArgumentList '-silent' } }
}

# --- what to do ---
if ($Request) {
    $r = try { Get-Content "$Dir\storage-request.json" -Raw | ConvertFrom-Json } catch { $null }; Remove-Item "$Dir\storage-request.json" -Force
    try {
        switch ($r.cmd) {
            'move' { Move-SteamGame "$($r.appid)" "$($r.to)" | Out-Null }
            'clean' { Status 'working' 'Removing leftovers' $null; $m = Invoke-Clean; Status 'done' $(if ($m) { $m } else { 'Nothing to remove.' }) 100 }
            'scan' { Remove-Item $statusFile -Force }   # (the app's "Look now": just the scan below)
            'recycle' {   # a leftover game folder the owner looked at: to the Recycle Bin (only one the scan listed)
                $known = try { @((Get-Content $out -Raw | ConvertFrom-Json).leftovers | Where-Object { -not $_.safe } | ForEach-Object path) } catch { @() }
                if ("$($r.path)" -notin $known) { throw 'That folder is not a listed leftover.' }
                if ($env:PCKIT_IN_TESTS) { $rb = Join-Path $env:TEMP 'pckit-test-recycle'; New-Item $rb -ItemType Directory -Force | Out-Null; Move-Item -LiteralPath "$($r.path)" $rb -Force }   # (tests: never the real Recycle Bin)
                else { Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory("$($r.path)", 'OnlyErrorDialogs', 'SendToRecycleBin') }
                Status 'done' "Moved $(Split-Path $r.path -Leaf) to the Recycle Bin." 100
            }
            default { throw 'Nothing asked.' }
        }
    }
    catch { Status 'failed' "$($_.Exception.Message)" $null }
    Invoke-Scan; return
}
if ($Move) { try { Move-SteamGame $Move $To } catch { "Storage: $($_.Exception.Message)" }; Invoke-Scan; return }
if ($Clean) { Invoke-Clean; Invoke-Scan; return }
# -Scan (and no switch): at most once a day unless -Force
$last = (Get-Item $out).LastWriteTime
if (-not $Force -and $last -and $last -gt (Get-Date).AddHours(-20)) { return }
Invoke-Scan
