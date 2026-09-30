# Keeps a PC installed from the PC Setup Kit up to date with the published kit (GitHub releases). Run by the background
# maintenance. Does nothing on the PC where the kit is developed (its folder is a git repo) or without kit-source.txt.
# A new release is downloaded, checked (all files present, every script parses) and only then installed.
# Before installing, the current version is saved (ProgramData\PCSetupKit\previous); -Rollback puts it back and skips
# the release it replaces from then on (self-test.ps1 does that when a new release fails its self-test on this PC).
# A release that keeps failing to install for 3 days is a WARNING (update-state.json).
# Test overrides: -KitDir -ClaudeDir -TrayDir -Force (skip the developer-PC check) -Saved.
param([string]$KitDir = 'C:\PCSetupKit', [string]$ClaudeDir = $PSScriptRoot, [string]$TrayDir = "$env:USERPROFILE\Documents\Messiah Tray", [switch]$Force, [switch]$Reinstall, [switch]$Rollback, [string]$Saved = "$env:ProgramData\PCSetupKit\previous")   # -Reinstall: install the current release again (self-test.ps1: its test suite is missing or stale)
$ErrorActionPreference = 'Stop'
if ($env:PCKIT_IN_TESTS -and -not $PSBoundParameters.ContainsKey('Saved')) { $Saved = Join-Path $env:TEMP "pckit-saved-$PID" }   # never the real saved version
# one update at a time (the maintenance, the 4-hourly check, the app's Repair / Undo): a second one just stops
# (it replaces $KitDir\tests and $KitDir\claude whole: never with an empty, relative or drive-root folder)
if ("$KitDir" -notmatch '^[A-Za-z]:\\[^\\]' -or "$ClaudeDir" -notmatch '^[A-Za-z]:\\[^\\]') { "Kit update: refused - kit folder '$KitDir' / scripts folder '$ClaudeDir' is not a full folder path"; return }
$umx = New-Object Threading.Mutex($false, "Global\PCSetupKitUpdate$(if ($env:PCKIT_IN_TESTS) { "-$PID" })")
$got = try { $umx.WaitOne(0) } catch [Threading.AbandonedMutexException] { $true }
if (-not $got) { return }
$srcFile = "$KitDir\kit-source.txt"
if (-not (Test-Path $srcFile)) { return }
if (-not $Force -and (Test-Path "$env:USERPROFILE\Documents\PC Setup Kit\.git")) { return }   # the owner's PC publishes, it doesn't update
$cfg = @{}; Get-Content $srcFile | ForEach-Object { $k, $v = $_ -split '=', 2; if ($v) { $cfg[$k.Trim()] = $v.Trim() } }
if ($cfg.repo -notmatch '^[\w.-]+/[\w.-]+$') { return }
$verFile = "$KitDir\kit-version.txt"; $cur = if (Test-Path $verFile) { (Get-Content $verFile -Raw).Trim() } else { '' }
$stFile = "$ClaudeDir\update-state.json"
$st = try { Get-Content $stFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { [pscustomobject]@{} }
if ($st -isnot [Management.Automation.PSCustomObject]) { $st = [pscustomobject]@{} }   # (valid JSON of the wrong shape - a number, a list - counts as no state, never as an error)
foreach ($p in 'skip', 'failingSince', 'failing') { if (-not ($st.PSObject.Properties.Name -contains $p)) { $st | Add-Member $p $null } }
function Save-State { try { $st | ConvertTo-Json | Set-Content $stFile -Encoding UTF8 } catch { } }
function Restart-Tray {   # reload the tray (it won't open a second session)
    if ($Force -or -not (Get-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue)) { return }
    Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe' OR Name='Messiah.exe' OR Name='PC Setup Kit.exe'" | Where-Object CommandLine -match 'Messiah Tray\.ahk' | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Start-ScheduledTask 'Messiah Tray'
}
# the saved version back in place (-Rollback, and an install that failed half-way)
function Restore-Saved {
    $prev = if (Test-Path "$Saved\version.txt") { (Get-Content "$Saved\version.txt" -Raw).Trim() }
    if (-not $prev) { return $null }
    # (a file that can't be written - still held open - is skipped, not the end of it: the update never got to write it either)
    foreach ($d in 'tests', 'claude') { if ((Test-Path "$Saved\kit\$d") -and (Test-Path "$KitDir\$d")) { try { [IO.Directory]::Delete("$KitDir\$d", $true) } catch { } } }   # replaced whole, as an update does
    # file by file: Copy-Item stops a whole folder at the first file it can't write
    $script:held = @()
    function Copy-Back($from, $to) {
        if (-not (Test-Path $from)) { return }
        $from = (Get-Item -LiteralPath $from -Force).FullName   # the long form: a short 8.3 path (RUNNER~1 on GitHub) would shift every relative path
        foreach ($f in Get-ChildItem -LiteralPath $from -Recurse -File -Force) {
            $dest = Join-Path $to $f.FullName.Substring($from.Length).TrimStart('\')
            try { New-Item (Split-Path $dest) -ItemType Directory -Force -ErrorAction Stop | Out-Null; Copy-Item -LiteralPath $f.FullName $dest -Force -ErrorAction Stop } catch { $script:held += (Split-Path $dest -Leaf) }
        }
    }
    Copy-Back "$Saved\kit" $KitDir
    Copy-Back "$Saved\claude" $ClaudeDir
    if ((Test-Path "$Saved\tray\Messiah Tray.ahk") -and (Test-Path $TrayDir)) { Copy-Back "$Saved\tray" $TrayDir }
    $prev | Set-Content $verFile
    if (Test-Path "$KitDir\tests") { $prev | Set-Content "$KitDir\tests\tests-version.txt" }
    $prev
}
if ($Rollback) {
    $prev = Restore-Saved
    if (-not $prev) { 'Kit update: nothing saved to go back to'; return }
    $st.skip = $cur; Save-State   # this release is not installed again; the next one is
    Restart-Tray
    "PC Setup Kit: went back to $prev - $cur failed its self-test on this PC (the next release installs normally)"; return
}
# the newest release that passed its test installs: GitHub's API, else the release page's redirect (the API allows only
# 60 requests an hour per network - shared networks can run out); offline: quietly try again next time
$tag = try { (Invoke-RestMethod "https://api.github.com/repos/$($cfg.repo)/releases/latest" -Headers @{ 'User-Agent' = 'pc-setup-kit' } -TimeoutSec 20).tag_name } catch { $null }
if (-not $tag) {
    try { $r = Invoke-WebRequest "https://github.com/$($cfg.repo)/releases/latest" -Method Head -UseBasicParsing -TimeoutSec 20; if ("$($r.BaseResponse.ResponseUri)" -match '/releases/tag/([^/?#]+)$') { $tag = $Matches[1] } } catch {}
}
if (-not $tag -or ($tag -eq $cur -and -not $Reinstall)) { return }
if ($tag -eq $st.skip -and -not $Reinstall) { return }   # went back from it: wait for the next release
# never back to an older release (e.g. while a newer one waits as a pre-release)
function Ver([string]$t) { $v = $null; if ([version]::TryParse(($t -replace '^v', ''), [ref]$v)) { $v } }
if ((Ver $tag) -and (Ver $cur) -and (Ver $tag) -lt (Ver $cur)) { return }

$tmp = Join-Path $env:TEMP "pc-setup-kit-update"; if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item $tmp -ItemType Directory -Force | Out-Null
$installing = $false; $savedNow = $false
try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest "https://github.com/$($cfg.repo)/archive/refs/tags/$tag.zip" -OutFile "$tmp\kit.zip" -UseBasicParsing -TimeoutSec 120
    Expand-Archive "$tmp\kit.zip" "$tmp\x" -Force
    $k = Get-ChildItem "$tmp\x" -Directory | Select-Object -First 1 | ForEach-Object { "$($_.FullName)\PCSetupKit" }
    $need = 'setup.ps1', 'tweaks.ps1', 'uninstall.ps1', 'claude\claude-admin-launch.ps1', 'claude\claude-bg-maint.ps1', 'claude\health-check.ps1',
        'claude\session-lib.ps1', 'claude\hooks\no-power-off.ps1', 'claude\skills\maintain\SKILL.md'
    $trayFile = @('Messiah Tray.ahk', 'Claude Admin Tray.ahk') | Where-Object { Test-Path "$k\claude\tray\$_" } | Select-Object -First 1   # releases before the rename to Messiah: old name
    $missing = @($need | Where-Object { -not (Test-Path "$k\$_") }) + @(if (-not $trayFile) { 'claude\tray\Messiah Tray.ahk' })
    if ($missing) { "Kit update: $tag is incomplete ($($missing -join ', ')) - kept the current version"; return }
    $bad = @(Get-ChildItem $k -Recurse -Filter *.ps1 | Where-Object { $e = $null; [void][Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e); $e })
    if ($bad) { "Kit update: $tag has scripts that don't parse ($($bad.Name -join ', ')) - kept the current version"; return }

    # save what is installed now (for -Rollback): the kit folder's scripts and tests, the maintenance scripts, hooks,
    # skills and the tray script - not data (reports, history, state)
    if ($cur -and -not $Reinstall) {
        if (Test-Path $Saved) { [IO.Directory]::Delete($Saved, $true) }
        New-Item "$Saved\kit", "$Saved\claude", "$Saved\tray" -ItemType Directory -Force | Out-Null
        Copy-Item "$KitDir\*.ps1" "$Saved\kit\"; foreach ($d in 'tests', 'claude') { if (Test-Path "$KitDir\$d") { Copy-Item "$KitDir\$d" "$Saved\kit\" -Recurse } }
        Copy-Item "$ClaudeDir\*.ps1" "$Saved\claude\"; foreach ($d in 'hooks', 'skills') { if (Test-Path "$ClaudeDir\$d") { Copy-Item "$ClaudeDir\$d" "$Saved\claude\" -Recurse } }
        if (Test-Path "$TrayDir\Messiah Tray.ahk") { Copy-Item "$TrayDir\Messiah Tray.ahk" "$Saved\tray\" }
        $cur | Set-Content "$Saved\version.txt"
        $savedNow = $true
    }
    $installing = $true   # from here on a failure leaves a mix of versions: the catch puts the saved one back
    Copy-Item "$k\*.ps1" $KitDir -Force                                   # setup / tweaks / uninstall
    # the kit copy's tests and scripts (self-test.ps1 runs these tests weekly): replaced whole, so removed files don't linger
    foreach ($d in 'tests', 'claude') { if (Test-Path "$k\$d") { Remove-Item "$KitDir\$d" -Recurse -Force -ErrorAction SilentlyContinue; Copy-Item "$k\$d" $KitDir -Recurse -Force } }
    if (Test-Path "$KitDir\tests") { $tag | Set-Content "$KitDir\tests\tests-version.txt" }   # which release these tests belong to (self-test.ps1)
    Copy-Item "$k\claude\*.ps1" $ClaudeDir -Force                         # maintenance scripts
    # Claude's skills and its no-shutdown hook only where the optional Claude part is on
    $ai = if (Test-Path "$ClaudeDir\ai-enabled.ps1") { & "$ClaudeDir\ai-enabled.ps1" } else { $true }
    if ($ai) {
        New-Item "$ClaudeDir\hooks", "$ClaudeDir\skills" -ItemType Directory -Force | Out-Null
        Copy-Item "$k\claude\hooks\*" "$ClaudeDir\hooks" -Force
        Copy-Item "$k\claude\skills\*" "$ClaudeDir\skills" -Recurse -Force
    }
    if (Test-Path $TrayDir) {
        Copy-Item "$k\claude\tray\$trayFile" "$TrayDir\Messiah Tray.ahk" -Force
        Restart-Tray
    }
    $tag | Set-Content $verFile
    $installing = $false
    $st.failingSince = $null; $st.failing = $null; Save-State
    # what's new, as a short note in the corner (the tray shows tray-news.txt once): the release's first points
    try {
            $notes = "$((Invoke-RestMethod "https://api.github.com/repos/$($cfg.repo)/releases/tags/$tag" -Headers @{ 'User-Agent' = 'pc-setup-kit' } -TimeoutSec 20).body)"
            $pts = @($notes -split "`r?`n" | Where-Object { $_ -match '^\s*-\s+\S' } | ForEach-Object { ($_ -replace '^\s*-\s+', '' -replace '\s*\(.*$', '' -replace ':.*$', '').Trim() } | Where-Object { $_ } | Select-Object -First 3)
            "Updated to $tag$(if ($pts) { " - new: $($pts -join '; ')" }). Details: the app > Maintenance." | Set-Content "$ClaudeDir\tray-news.txt" -Encoding UTF8
        } catch { "Updated to $tag." | Set-Content "$ClaudeDir\tray-news.txt" -Encoding UTF8 }
    "PC Setup Kit updated $(if ($cur) { "$cur -> " })$tag"
}
catch {
    # retried at every check; still failing after 3 days (disk full, antivirus, a network blocking GitHub) = WARNING
    # half-installed (a full disk, a locked file): the previous version back right away - never a mix of old and new
    $back = if ($installing -and $savedNow) {   # (only what this run saved: a Reinstall saves nothing, and an older saved version must never come back)
        try { Restore-Saved } catch { $null } }
    $since = [datetime]::MinValue
    if ($st.failing -ne $tag -or -not [datetime]::TryParse("$($st.failingSince)", [ref]$since)) { $st.failing = $tag; $since = Get-Date; $st.failingSince = $since.ToString('o') }; Save-State
    $days = ((Get-Date) - $since).TotalDays
    "$(if ($days -ge 3) { "WARNING: kit updates have failed for $([int]$days) days" } else { 'Kit update' }): couldn't install $tag ($($_.Exception.Message))$(if ($back) { " - put $back back as it was$(if ($script:held) { " ($($script:held -join ', ') was held open and never changed)" })" } elseif ($installing) { ' - AND COULD NOT PUT THE PREVIOUS VERSION BACK' }) - will retry next time"
}
finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
