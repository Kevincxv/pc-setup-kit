# Game saves, backed up by themselves (opt-in: kit-options.txt "gamesaves=on" - the app's Settings > Game saves).
# Ludusavi (open source; its list knows the save places of 10,000+ games, Steam or not) copies every game's saves to
# Documents\Game Saves (Messiah): once a day at most, never while a game runs, zipped, the last 3 copies per game kept.
# Documents goes to the files-backup drive as well when there is one, so the saves do too.
# Huge files that are a game's caches, not its saves (10/12: NBA 2K21's 6 GB of online data in its save folder) are
# left out by themselves - said once.
# -Check: health-check.ps1 (when due).  -Run: now (the app's "Back up now"; turns it on).  -Restore: Ludusavi's own
# window, to put saves back.  Ludusavi itself is installed (winget) the first time it's needed.
# Test overrides: -Exe (a stand-in), -Dest, -Options, -State, -ConfigDir, -Now, -GameCheck.
param([switch]$Check, [switch]$Run, [switch]$Restore, [string]$Exe, [string]$Dest, [string]$Options = "$env:USERPROFILE\.claude\kit-options.txt",
    [string]$State = "$env:USERPROFILE\.claude\game-saves.json", [string]$ConfigDir = "$env:USERPROFILE\.claude\ludusavi", [datetime]$Now = (Get-Date),
    [scriptblock]$GameCheck = { if (Test-Path "$PSScriptRoot\game-check.ps1") { & "$PSScriptRoot\game-check.ps1" } })
$ErrorActionPreference = 'SilentlyContinue'
if ($env:PCKIT_IN_TESTS -and -not $Exe) { return }   # never the real Ludusavi from the test suite
if (-not $Dest) { $Dest = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Game Saves (Messiah)' }
$bigFile = 512MB   # a single "save" file this big is a cache

function Test-On { [bool](@(Get-Content $Options) -match '^\s*gamesaves\s*=\s*on\s*$') }
function Set-On { $l = @(Get-Content $Options | Where-Object { $_ -notmatch '^\s*gamesaves\s*=' }) + 'gamesaves=on'; [IO.File]::WriteAllLines($Options, [string[]]$l) }
$st = @{}; try { (Get-Content $State -Raw -ErrorAction Stop | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $st[$_.Name] = $_.Value } } catch {}
function Save { try { [pscustomobject]$st | ConvertTo-Json -Depth 4 | Set-Content $State -Encoding UTF8 } catch {} }

function Find-Exe {
    if ($Exe) { return $Exe }
    foreach ($p in @((Get-Command ludusavi -ErrorAction SilentlyContinue).Source, "$env:LOCALAPPDATA\Microsoft\WinGet\Links\ludusavi.exe")) { if ($p -and (Test-Path $p)) { return $p } }
    $null = winget install --id mtkennerly.ludusavi -e --silent --accept-package-agreements --accept-source-agreements 2>&1
    $p = "$env:LOCALAPPDATA\Microsoft\WinGet\Links\ludusavi.exe"; if (Test-Path $p) { $p }
}
# its own settings folder (not the owner's own Ludusavi, if they use it): where the backups are, what's left out
function Set-Config($exe, [string[]]$ignored) {
    $f = "$ConfigDir\config.yaml"
    if (-not (Test-Path $f)) { New-Item $ConfigDir -ItemType Directory -Force | Out-Null; $null = & $exe --config $ConfigDir --no-manifest-update backup --preview --api 2>&1 }   # (its defaults, with this PC's game stores found)
    $y = Get-Content $f -Raw; if (-not $y) { return }
    $d = $Dest -replace '\\', '/'
    $n = [regex]::Replace($y, '(?m)^((?:backup|restore):\r?\n  path: ).*$', { param($m) "$($m.Groups[1].Value)`"$d`"" })
    $list = if ($ignored) { "`n" + (($ignored | ForEach-Object { "      - `"$($_ -replace '\\', '/')`"" }) -join "`n") } else { ' []' }
    $n = [regex]::Replace($n, '(?ms)^    ignoredPaths:.*?(?=^    ignoredRegistry:)', { param($m) "    ignoredPaths:$list`n" })
    if ($n -ne $y) { [IO.File]::WriteAllText($f, $n, (New-Object Text.UTF8Encoding $false)) }
}
function Invoke-Lud($exe, [string[]]$a) {
    $out = @(& $exe --config $ConfigDir --try-manifest-update @a 2>&1 | ForEach-Object { "$_" })
    [pscustomobject]@{ Code = $LASTEXITCODE; Json = $(try { ($out -join "`n") | ConvertFrom-Json } catch { $null }); Text = ($out -join ' ') }
}

if ($Restore) {
    $exe = Find-Exe; if (-not $exe) { return "Couldn't install Ludusavi (winget) - try again later" }
    Set-Config $exe @($st.ignored); Start-Process $exe -ArgumentList '--config', "`"$ConfigDir`"", 'gui'; return
}
if ($Run) { if (-not (Test-On)) { Set-On } }
elseif (-not (Test-On)) { return }
else {
    $last = [datetime]::MinValue; [void][datetime]::TryParse("$($st.lastRun)", [ref]$last)
    if ($last -gt $Now.AddHours(-20)) { return }
    if (& $GameCheck) { return }   # (a game running: its saves may be half written - next time)
}

$exe = Find-Exe
if (-not $exe) { return 'WARNING: game save backup - couldn''t install Ludusavi (winget); tried again next time' }
$ignored = @($st.ignored | Where-Object { $_ })
Set-Config $exe $ignored
# caches in save folders: left out (from the preview - nothing written yet)
$pv = Invoke-Lud $exe @('backup', '--preview', '--api')
$said = @()
if ($pv.Json) {
    foreach ($g in $pv.Json.games.PSObject.Properties) {
        foreach ($fp in $g.Value.files.PSObject.Properties) {
            if ([double]$fp.Value.bytes -ge $bigFile -and $fp.Name -notin $ignored) { $ignored += $fp.Name; $said += "$($g.Name): $(Split-Path $fp.Name -Leaf) ($([math]::Round([double]$fp.Value.bytes / 1GB, 1)) GB)" }
        }
    }
    if ($said) { $st.ignored = $ignored; Save; Set-Config $exe $ignored }
}
$r = Invoke-Lud $exe @('backup', '--force', '--path', $Dest, '--format', 'zip', '--compression', 'zstd', '--full-limit', '3', '--api')
if ($r.Code -ne 0 -or -not $r.Json) {
    $why = if ($r.Json -and $r.Json.errors) { ($r.Json.errors | ConvertTo-Json -Compress -Depth 3) } else { $r.Text }
    return "WARNING: game save backup failed (Ludusavi exit $($r.Code)): $("$why".Substring(0, [Math]::Min(200, "$why".Length)))"
}
$o = $r.Json.overall
$st.lastRun = $Now.ToString('o'); $st.games = [int]$o.totalGames; Save
$changed = [int]$o.changedGames.new + [int]$o.changedGames.different
if ($said) { "Game saves: left out $($said.Count) huge cache file(s), not saves - $($said -join '; ')" }
if ($changed) { "Game saves: $changed of $($o.totalGames) games had new saves - backed up to Documents\Game Saves (Messiah) ($([math]::Round([double]$o.processedBytes / 1MB)) MB in all)" }
else { "Game saves: all $($o.totalGames) games already backed up" }
