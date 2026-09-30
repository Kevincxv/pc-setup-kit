# settings-backup.ps1: the look, game settings and the kit's memory saved weekly, and restored on a reinstall of the
# SAME PC only. A made-up user (folders under $Work, registry under a throwaway HKCU key); -NoApply: nothing on the
# real desktop changes.
. "$PSScriptRoot\..\lib.ps1"
$sb = "$Src\settings-backup.ps1"
if (-not (Test-Path $sb)) { Skip 'settings-backup' 'not installed here'; Finish }
$rk = "PCSetupKitTest-$(Get-Random)"; $old = "HKCU:\Software\$rk\old"; $new = "HKCU:\Software\$rk\new"
$oh = "$Work\oldpc"; $nh = "$Work\newpc"; $bk = "$Work\backups"
try {
    # the old install: dark mode, an accent colour, a wallpaper, a game's settings, a big file, the kit's memory
    New-Item "$old\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "$old\Software\Microsoft\Windows\DWM", "$old\Control Panel\Desktop", "$old\Control Panel\Mouse" -Force | Out-Null
    Set-ItemProperty "$old\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" AppsUseLightTheme 0 -Type DWord
    Set-ItemProperty "$old\Software\Microsoft\Windows\DWM" AccentColor -8388608 -Type DWord
    New-Item "$old\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent" -Force | Out-Null
    Set-ItemProperty "$old\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent" AccentPalette ([byte[]](1, 2, 3, 250)) -Type Binary
    Set-ItemProperty "$old\Control Panel\Mouse" MouseSensitivity '14' -Type String
    New-Item "$oh\Pictures", "$oh\Documents\My Games\TestGame", "$oh\.claude", "$oh\AppData\Local\UeGame\Saved\Config\Windows" -ItemType Directory -Force | Out-Null
    [IO.File]::WriteAllBytes("$oh\Pictures\beach.png", [byte[]](137, 80, 78, 71))
    Set-ItemProperty "$old\Control Panel\Desktop" WallPaper "$oh\Pictures\beach.png" -Type String
    'fov=100' | Set-Content "$oh\Documents\My Games\TestGame\settings.ini"
    'r.Shadow=1' | Set-Content "$oh\AppData\Local\UeGame\Saved\Config\Windows\GameUserSettings.ini"
    $big = [IO.File]::Create("$oh\Documents\My Games\TestGame\replay.bin"); $big.SetLength(11MB); $big.Close()
    'TestGame' | Set-Content "$oh\.claude\games.txt"
    New-Item "$old\Software\Valve\Steam", "$new\Software\Valve\Steam" -Force | Out-Null   # Steam installed, never started: the key without SteamPath (the Sandbox test, 9/28)
    function Backup([switch]$Force) { @(& $sb -RegRoot $old -HomeDir $oh -Dest $bk -MachineId 'PC-1' -ClaudeDir "$oh\.claude" -Force:$Force) }
    function Restore([string]$id = 'PC-1') { @(& $sb -Restore -RegRoot $new -HomeDir $nh -Dest $bk -MachineId $id -ClaudeDir "$nh\.claude" -NoApply) }

    Section 'backup'
    $o = Backup
    $zip = @(Get-ChildItem "$bk\*.zip")
    Check 'a backup zip, saying where it went' ($zip.Count -eq 1 -and "$o" -match '^Backup: settings saved .+ to ') ($o -join ' / ')
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead($zip[0].FullName); $names = @($z.Entries | ForEach-Object { $_.FullName -replace '/', '\' }); $z.Dispose()
    Check '... with the look, the wallpaper image, game settings and the kit memory' (($names -contains 'backup.json') -and ($names -contains 'wallpaper.png') -and ($names -contains 'games\MyGames\TestGame\settings.ini') -and ($names -contains 'games\Unreal\UeGame\Windows\GameUserSettings.ini') -and ($names -contains 'kit\games.txt')) ($names -join ', ')
    Check '... but not files over 10 MB' (-not ($names -match 'replay\.bin')) ''
    $o = Backup
    Check 'a second run within 6 days: skipped' (-not $o -and @(Get-ChildItem "$bk\*.zip").Count -eq 1) ($o -join ' / ')
    foreach ($d in 1..5) { [IO.File]::WriteAllBytes("$bk\$env:COMPUTERNAME-2020-01-0$d.zip", [byte[]](0)) }
    [void](Backup -Force)
    Check 'the newest 4 are kept' (@(Get-ChildItem "$bk\$env:COMPUTERNAME-*.zip").Count -eq 4 -and (Test-Path $zip[0].FullName)) (@(Get-ChildItem "$bk\*.zip").Name -join ', ')
    foreach ($f in Get-ChildItem "$bk\$env:COMPUTERNAME-2020-*.zip") { [IO.File]::Delete($f.FullName) }
    # a profile path in its short 8.3 form (GitHub's machines: C:\Users\RUNNER~1) - file paths inside the zip stay right
    $shortHome = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($oh).ShortPath
    $bk2 = "$Work\backups-short"
    [void](& $sb -RegRoot $old -HomeDir $shortHome -Dest $bk2 -MachineId 'PC-1' -ClaudeDir "$oh\.claude" -Force)
    $z = [IO.Compression.ZipFile]::OpenRead(@(Get-ChildItem "$bk2\*.zip")[0].FullName); $n2 = @($z.Entries | ForEach-Object { $_.FullName -replace '/', '\' }); $z.Dispose()
    Check "a short (8.3) profile path: the game files' paths inside the backup still right ($shortHome)" ($n2 -contains 'games\MyGames\TestGame\settings.ini') ($n2 -match '^games' -join ', ')

    # -ToUsb (the tray, when a drive is plugged in): a kit USB gets today's backup once
    $usbb = "$Work\usb\PC Setup Kit Backup"
    $o1 = @(& $sb -ToUsb -RegRoot $old -HomeDir $oh -Dest $usbb -MachineId 'PC-1' -ClaudeDir "$oh\.claude")
    $o2 = @(& $sb -ToUsb -RegRoot $old -HomeDir $oh -Dest $usbb -MachineId 'PC-1' -ClaudeDir "$oh\.claude")
    Check 'a kit USB plugged in: a fresh backup on it; plugged in again the same day: nothing' ("$o1" -match '^Backup: settings saved' -and -not $o2 -and @(Get-ChildItem "$usbb\*.zip").Count -eq 1) (($o1 + $o2) -join ' / ')

    Section 'restore'
    New-Item "$nh\Documents\My Games\TestGame", "$nh\.claude" -ItemType Directory -Force | Out-Null
    $o = Restore 'PC-2'
    Check "another PC's backup is never used (a kit USB shared between friends)" ("$o" -match 'made on other PCs - not used' -and -not (Test-Path "$new\Control Panel\Desktop")) ($o -join ' / ')
    $o2 = @(& $sb -Restore -From $zip[0].FullName -RegRoot "HKCU:\Software\$rk\anypc" -HomeDir "$Work\anypc" -MachineId 'PC-2' -ClaudeDir "$Work\anypc\.claude" -NoApply -AnyPc)
    Check '... unless the owner picks it in the app and says yes (-AnyPc)' ("$o2" -match '^Restore: brought back') ($o2 -join ' / ')
    'fov=90 (changed on the new install)' | Set-Content "$nh\Documents\My Games\TestGame\settings.ini"
    $o = Restore
    Check "this PC's backup: restored, saying what came back" ("$o" -match '^Restore: brought back from the backup of .+colours and dark mode.+wallpaper.+game settings') ($o -join ' / ')
    Check '... dark mode and the accent colour' ((Get-ItemProperty "$new\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize").AppsUseLightTheme -eq 0 -and [uint32](Get-ItemProperty "$new\Software\Microsoft\Windows\DWM").AccentColor -eq 4286578688) "light=$((Get-ItemProperty "$new\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize").AppsUseLightTheme) accent=$((Get-ItemProperty "$new\Software\Microsoft\Windows\DWM").AccentColor)"   # (accent: the same 32 bits, read back unsigned)
    Check '... binary values intact (the accent palette)' (((Get-ItemProperty "$new\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent").AccentPalette -join ',') -eq '1,2,3,250') ''
    $wp = (Get-ItemProperty "$new\Control Panel\Desktop").WallPaper
    Check '... the wallpaper image copied into the new profile and set' ($wp -like "$nh\*" -and (Test-Path $wp)) "$wp"
    Check '... game settings (the Unreal one back in its own folder)' ((Test-Path "$nh\AppData\Local\UeGame\Saved\Config\Windows\GameUserSettings.ini")) ''
    Check "... a file that's already there is never overwritten" ((Get-Content "$nh\Documents\My Games\TestGame\settings.ini") -match 'changed on the new install') ''
    Check "... the kit's memory" ((Get-Content "$nh\.claude\games.txt") -eq 'TestGame') ''
    $err = & { $ErrorActionPreference = 'Stop'; try { [void](& $sb -Restore -From $zip[0].FullName -RegRoot $new -HomeDir $nh -MachineId 'PC-1' -ClaudeDir "$nh\.claude" -NoApply); '' } catch { "$_" } }
    $wp0 = (Get-ItemProperty 'HKCU:\Control Panel\Desktop').WallPaper
    $o = @(& $sb -Restore -From $zip[0].FullName -MachineId 'PC-1' -NoApply)
    Check 'under tests, never the real registry (the default HKCU) - even with this PC''s own backup' (-not $o -and (Get-ItemProperty 'HKCU:\Control Panel\Desktop').WallPaper -eq $wp0) ($o -join ' / ')
    Check 'Steam installed but never started (its key without SteamPath): no error, even under -ErrorAction Stop' (-not $err) $err

    Section 'the kit''s look for every fresh install (-ExportLook, restored with -AnyPc)'
    $lzip = "$Work\kitlook\look.zip"
    # a real picture this time (the one above is 4 bytes - it only has to be copied): re-saved on export
    Add-Type -AssemblyName System.Drawing; $pic = New-Object Drawing.Bitmap 64, 40; $pic.Save("$oh\Pictures\real.png", [Drawing.Imaging.ImageFormat]::Png); $pic.Dispose()
    Set-ItemProperty "$old\Control Panel\Desktop" WallPaper "$oh\Pictures\real.png" -Type String
    $o = @(& $sb -ExportLook $lzip -RegRoot $old -HomeDir $oh -ClaudeDir "$oh\.claude")
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $lz = [IO.Compression.ZipFile]::OpenRead($lzip); $names = @($lz.Entries | ForEach-Object FullName); $lj = (New-Object IO.StreamReader ($lz.GetEntry('backup.json').Open())).ReadToEnd() | ConvertFrom-Json; $lz.Dispose()
    Check 'exported: the look and the wallpaper only - no kit memory, game settings, Steam or Start pins' ((($names | Sort-Object) -join ',') -eq 'backup.json,wallpaper.jpg' -and "$o" -match '^Look exported') ($names -join ', ')
    Check '... for no PC in particular: no PC name or id in it' ($lj.machine -eq 'any' -and $lj.computer -eq 'Messiah look') "$($lj.machine) / $($lj.computer)"
    $lh = "$Work\friendpc"; New-Item "$lh\.claude" -ItemType Directory -Force | Out-Null
    $o = @(& $sb -Restore -From $lzip -RegRoot "HKCU:\Software\$rk\friend" -HomeDir $lh -MachineId 'FRIEND-PC' -ClaudeDir "$lh\.claude" -NoApply -AnyPc)
    Check 'a friend''s new PC: gets the look - dark mode, the accent colour, the wallpaper - said as the kit''s look' ((Get-ItemProperty "HKCU:\Software\$rk\friend\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize").AppsUseLightTheme -eq 0 -and [uint32](Get-ItemProperty "HKCU:\Software\$rk\friend\Software\Microsoft\Windows\DWM").AccentColor -eq [uint32]4286578688 -and (Test-Path (Get-ItemProperty "HKCU:\Software\$rk\friend\Control Panel\Desktop").WallPaper) -and "$o" -match "^Look: Messiah's look put on this new Windows") ($o -join ' / ')
    Check '... and nothing else of the owner''s (games list, history)' (-not (Test-Path "$lh\.claude\games.txt")) ''

    Section 'a tampered backup (another PC''s, or changed by hand) only ever restores the look'
    $tw = "$Work\tampered"; [IO.Compression.ZipFile]::ExtractToDirectory($zip[0].FullName, $tw)
    $j = Get-Content "$tw\backup.json" -Raw | ConvertFrom-Json
    $j.look | Add-Member 'Software\Microsoft\Windows\CurrentVersion\Run' ([pscustomobject]@{ Evil = [pscustomobject]@{ kind = 'String'; value = 'C:\evil.exe' } })
    $j.look.'Control Panel\Mouse' | Add-Member 'NotALookValue' ([pscustomobject]@{ kind = 'String'; value = 'x' })
    $j | ConvertTo-Json -Depth 6 | Set-Content "$tw\backup.json" -Encoding UTF8
    'evil' | Set-Content "$tw\kit\evil.ps1"
    $tz = "$Work\tampered.zip"; [IO.Compression.ZipFile]::CreateFromDirectory($tw, $tz)
    $th = "$Work\tamperedpc"; New-Item "$th\.claude" -ItemType Directory -Force | Out-Null
    $o = @(& $sb -Restore -From $tz -RegRoot "HKCU:\Software\$rk\tampered" -HomeDir $th -MachineId 'PC-1' -ClaudeDir "$th\.claude" -NoApply)
    Check 'a Run key in the backup: never written (nothing starts at login from a backup)' (-not (Test-Path "HKCU:\Software\$rk\tampered\Software\Microsoft\Windows\CurrentVersion\Run")) ($o -join ' / ')
    Check '... a value that is not part of the look: ignored, said; the look itself restored' ($null -eq (Get-ItemProperty "HKCU:\Software\$rk\tampered\Control Panel\Mouse").NotALookValue -and (Get-ItemProperty "HKCU:\Software\$rk\tampered\Control Panel\Mouse").MouseSensitivity -eq '14' -and "$o" -match "setting\(s\) in the backup that aren't part of the look were ignored") ($o -join ' / ')
    Check '... an extra script in it: not copied (only the kit''s own memory files)' (-not (Test-Path "$th\.claude\evil.ps1") -and (Test-Path "$th\.claude\games.txt")) ''
}
finally { Remove-Item "HKCU:\Software\$rk" -Recurse -Force -ErrorAction SilentlyContinue }
Finish
