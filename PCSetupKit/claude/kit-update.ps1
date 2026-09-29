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
foreach ($p in 'skip', 'failingSince', 'failing') { if (-not ($st.PSObject.Properties.Name -contains $p)) { $st | Add-Member $p $null } }
function Save-State { try { $st | ConvertTo-Json | Set-Content $stFile -Encoding UTF8 } catch { } }
function Restart-Tray {   # reload the tray (it won't open a second session)
    if ($Force -or -not (Get-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue)) { return }
    Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe' OR Name='Messiah.exe' OR Name='PC Setup Kit.exe'" | Where-Object CommandLine -match 'Messiah Tray\.ahk' | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Start-ScheduledTask 'Messiah Tray'
}
if ($Rollback) {
    $prev = if (Test-Path "$Saved\version.txt") { (Get-Content "$Saved\version.txt" -Raw).Trim() }
    if (-not $prev) { 'Kit update: nothing saved to go back to'; return }
    foreach ($d in 'tests', 'claude') { if ((Test-Path "$Saved\kit\$d") -and (Test-Path "$KitDir\$d")) { [IO.Directory]::Delete("$KitDir\$d", $true) } }   # replaced whole, as an update does
    Copy-Item "$Saved\kit\*" $KitDir -Recurse -Force
    Copy-Item "$Saved\claude\*" $ClaudeDir -Recurse -Force
    if ((Test-Path "$Saved\tray\Messiah Tray.ahk") -and (Test-Path $TrayDir)) { Copy-Item "$Saved\tray\Messiah Tray.ahk" $TrayDir -Force }
    $st.skip = $cur; Save-State   # this release is not installed again; the next one is
    $prev | Set-Content $verFile
    if (Test-Path "$KitDir\tests") { $prev | Set-Content "$KitDir\tests\tests-version.txt" }
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
    }
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
    if ($st.failing -ne $tag -or -not $st.failingSince) { $st.failing = $tag; $st.failingSince = (Get-Date).ToString('o') }; Save-State
    $days = ((Get-Date) - [datetime]$st.failingSince).TotalDays
    "$(if ($days -ge 3) { "WARNING: kit updates have failed for $([int]$days) days" } else { 'Kit update' }): couldn't install $tag ($($_.Exception.Message)) - will retry next time"
}
finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
