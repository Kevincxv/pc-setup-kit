# Weekly / monthly maintenance for the "Messiah" launcher. Run by claude-bg-maint.ps1 (elevated, hidden).
# Tracks what ran when in .claude\maint-state.json and only does tasks that are due. Prints one line per action.
# Tasks that need judgment (BIOS, firmware, Windows version upgrades, re-benchmarks) are marked due here and done
# by Claude itself: the launcher opens Claude with /maintain when anything in "claude" is due.
param([string]$TestDisplayVersion, [string]$TestEdition, [string]$TestInstallType, [string]$TestToday, [ValidateSet('', 'yes', 'no')][string]$TestRebootPending)   # -Test*: tests (-TestRebootPending: this PC may really have a restart pending)
$ErrorActionPreference = 'SilentlyContinue'
$stateFile = "$PSScriptRoot\maint-state.json"
function Read-State { $h = @{}; try { $j = Get-Content $stateFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { $j = $null }
    if ($j) { $j.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value } }; $h }
$state = Read-State
function Due($key, $days) { $d = [datetime]::MinValue; -not [datetime]::TryParse("$($state[$key])", [ref]$d) -or $d -lt (Get-Date).AddDays(-$days) }
function Done($key) { $state[$key] = (Get-Date).ToString('o') }
$rebootPending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
if ($TestRebootPending) { $rebootPending = $TestRebootPending -eq 'yes' }

# --- Weekly: app updates (apps that don't update themselves; Steam/Discord/Chrome/NVIDIA update on their own) ---
$game = & "$PSScriptRoot\game-check.ps1"   # heavy work waits for the game to close (not marked done, so it runs next time)
if ($game -and ((Due 'weekly-apps' 7) -or (Due 'monthly-cleanup' 30))) { "App updates / cleanup held while $game is running (next run)" }
if (-not $game -and (Due 'weekly-apps' 7)) {
    $skip = 'Valve.Steam', 'Discord.Discord', 'Google.Chrome', 'Nvidia.', 'Microsoft.Edge'   # (Edge and WebView2 update themselves)
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}   # winget writes UTF-8 (a shortened name ends in "...")
    # A table of updates, or "No installed package found" = winget answered. Anything else (no answer, "No packages
    # were found", a source error) = its package list is missing or broken: fetched again, then asked once more.
    # Still no answer: not marked done, so the next run tries again - never a silently skipped week.
    $answered = { param($r) [array]::FindIndex($r, [Predicate[object]] { param($l) "$l" -match 'Name\s+Id\s+Version' }) -ge 0 -or ($r -match 'No installed package found') }
    $raw = @(winget upgrade --accept-source-agreements --disable-interactivity 2>$null)
    if (-not (& $answered $raw)) {
        winget source reset --force 2>&1 | Out-Null; winget source update --accept-source-agreements 2>&1 | Out-Null
        $raw = @(winget upgrade --accept-source-agreements --disable-interactivity 2>$null)
        if (& $answered $raw) { 'App updates: winget''s package list was broken - fetched it again' }
    }
    $h = [array]::FindIndex($raw, [Predicate[object]] { param($l) "$l" -match 'Name\s+Id\s+Version' })
    # one miss (offline, winget busy) is "held"; three weeks without app updates is a FAILED line (it gets looked at).
    # winget's own message stays out of the line: its "Failed when searching..." would read as FAILED.
    if (-not (& $answered $raw)) { "App updates $(if (Due 'weekly-apps' 21) { 'FAILED' } else { 'held' }): winget couldn't load its package list - trying again next run" }
    elseif ($h -ge 0) {
        # each row read from the right (Id, Version, Available, Source never contain spaces): a shortened or oddly
        # encoded name can't shift the columns
        for ($i = $h + 2; $i -lt $raw.Count -and $raw[$i] -match '\S' -and $raw[$i] -notmatch 'upgrades? available|explicit targeting'; $i++) {
            $id = $src = $null; if ("$($raw[$i])" -match '^(?<name>.+?)\s+(?<id>\S+)\s+(?<ver>(<\s)?\S+)\s+(?<avail>\S+)\s+(?<src>\S+)\s*$') { $id = $Matches['id']; $src = $Matches['src'] }
            if (-not $id -or ($skip | Where-Object { $id -like "$_*" })) { continue }
            $o = winget upgrade --id $id -e --source $src --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | Out-String
            if ($o -match 'Successfully installed') { "Updated app: $id" } else { "App update FAILED: $id" }
        }
    }
    if (& $answered $raw) { Done 'weekly-apps' }
}

# --- Weekly: settings backup (the look, game settings, the kit's memory - setup brings them back after a reinstall) ---
if (-not $game -and (Test-Path "$PSScriptRoot\settings-backup.ps1")) { & "$PSScriptRoot\settings-backup.ps1" }   # (it skips itself when the last is under 6 days old)

# --- Monthly: cleanup, restore point, orphans, driver store ---
if (-not $game -and (Due 'monthly-cleanup' 30)) {
    $rps = @(Get-ComputerRestorePoint)
    if (-not ($rps | Where-Object { $_.ConvertToDateTime($_.CreationTime) -gt (Get-Date).AddDays(-1) })) {   # Windows allows one per 24 h
        Checkpoint-Computer -Description 'Monthly maintenance (Messiah)' -RestorePointType MODIFY_SETTINGS -WarningAction SilentlyContinue
        if (@(Get-ComputerRestorePoint).Count -gt $rps.Count) { 'Created a monthly restore point' } else { 'Restore point FAILED (is System Protection on for C:?)' }
    }
    $free0 = (Get-PSDrive C).Free
    if (-not $rebootPending) { DISM /Online /Cleanup-Image /StartComponentCleanup /Quiet | Out-Null }   # hangs if a restart is pending
    # Disk Cleanup: ONLY these safe categories (allow-list). Never: Downloads, Recycle Bin, shader caches (only gpu-watch.ps1, once after a driver update; games stutter
    # while rebuilding), crash dumps, previous Windows (needed to roll back an upgrade), driver packages / language packs /
    # update cleanup (DISM-based: they hang while a restart is pending, and DISM above already cleans updates).
    $safe = 'Temporary Files', 'Temporary Setup Files', 'Thumbnail Cache', 'Delivery Optimization Files', 'Setup Log Files',
        'Windows Upgrade Log Files', 'Old ChkDsk Files', 'Internet Cache Files', 'Downloaded Program Files', 'Active Setup Temp Folders',
        'BranchCache', 'Content Indexer Cleaner', 'Feedback Hub Archive log files', 'Diagnostic Data Viewer database files',
        'RetailDemo Offline Content', 'Windows Reset Log Files', 'Windows Defender'
    $vc = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    foreach ($k in Get-ChildItem $vc) {
        if ($k.PSChildName -in $safe) { Set-ItemProperty $k.PSPath StateFlags0078 2 -Type DWord } else { Remove-ItemProperty $k.PSPath StateFlags0078 }
    }
    $cm = Start-Process cleanmgr.exe -ArgumentList '/sagerun:78' -WindowStyle Hidden -PassThru
    if (-not $cm.WaitForExit(900000)) { Stop-Process -Id $cm.Id -Force; 'Disk Cleanup: stopped after 15 min' }
    # Old driver versions (in-use packages are refused by pnputil without /force, so this only removes stale ones)
    $pk = [regex]::Matches((pnputil /enum-drivers | Out-String), 'Published Name:\s+(\S+)\s+Original Name:\s+(\S+)[\s\S]*?Driver Version:\s+\S+\s+(\S+)') |
        ForEach-Object { [pscustomobject]@{ Pub = $_.Groups[1].Value; Orig = $_.Groups[2].Value; Ver = [version]($_.Groups[3].Value -replace '[^\d.]', '') } }
    # A driver updated in the last 30 days keeps its previous version: driver-guard.ps1 goes back to it if the new
    # one causes blue screens (arrival time = its driver store folder's creation time)
    $recent = @(Get-WindowsDriver -Online | Where-Object { (Get-Item -LiteralPath (Split-Path $_.OriginalFileName)).CreationTime -gt (Get-Date).AddDays(-30) } | ForEach-Object { Split-Path $_.OriginalFileName -Leaf })
    foreach ($g in $pk | Group-Object Orig | Where-Object { $_.Count -gt 1 -and $_.Name -notin $recent }) {
        foreach ($old in $g.Group | Sort-Object Ver -Descending | Select-Object -Skip 1) {
            if ((pnputil /delete-driver $old.Pub 2>&1 | Out-String) -match 'deleted successfully') { "Removed old driver $($old.Orig) $($old.Ver)" }
        }
    }
    # Orphans that are always safe to remove: firewall rules and uninstall entries for programs that no longer exist
    $fw = @(Get-NetFirewallApplicationFilter | Where-Object { $_.Program -and $_.Program -ne 'Any' -and $_.Program -notmatch '^%|System$' -and
            -not (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables($_.Program))) })
    if ($fw) { $fw | ForEach-Object { $_ | Get-NetFirewallRule | Remove-NetFirewallRule }; "Removed $($fw.Count) firewall rules for deleted programs" }
    # Orphans that need a human look (services/tasks pointing at deleted files) are reported for Claude
    function Exe($s) { if (-not $s) { return }; $s = [Environment]::ExpandEnvironmentVariables($s.Trim()) -replace '^\\\?\?\\', '' -replace '^\\SystemRoot', $env:SystemRoot
        if ($s -match '^"([^"]+)"') { $Matches[1] } elseif ($s -match '^(.+?\.(exe|sys|dll|cmd|bat|ps1))(\s|$)') { $Matches[1] } }
    $orph = @()
    $orph += Get-CimInstance Win32_Service | Where-Object { ($e = Exe $_.PathName) -and $e -match '^[A-Za-z]:\\' -and -not (Test-Path -LiteralPath $e) } | ForEach-Object { "service $($_.Name)" }
    $orph += Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notmatch '^\\Microsoft\\' } |
        Where-Object { $_.Actions | Where-Object { ($e = Exe $_.Execute) -and $e -match '^[A-Za-z]:\\' -and -not (Test-Path -LiteralPath $e) } } | ForEach-Object { "task $($_.TaskPath)$($_.TaskName)" }
    if ($orph) { "WARNING: leftovers pointing at deleted programs: $($orph -join ', ')" }
    $freed = ((Get-PSDrive C).Free - $free0) / 1GB
    "Monthly cleanup done$(if ($freed -gt 0.1) { ', freed {0:N1} GB' -f $freed })"
    Done 'monthly-cleanup'
}

# --- Checks every run (cheap) ---
$trim = Get-ScheduledTask -TaskPath '\Microsoft\Windows\Defrag\' -TaskName ScheduledDefrag | Get-ScheduledTaskInfo
if ($trim.LastRunTime -lt (Get-Date).AddDays(-14) -and (Due 'trim' 7)) { Optimize-Volume -DriveLetter C -ReTrim; 'SSD TRIM run (Windows had not done it in 2+ weeks)'; Done 'trim' }
# Windows version end of support, by edition (Windows 11 lifecycle): Home/Pro/Pro Education/Pro for Workstations/SE get
# 24 months per yearly release, Enterprise/Education/IoT Enterprise 36 months; LTSC and Server have their own long
# lifecycles and are not checked. (Test overrides: -TestDisplayVersion -TestEdition -TestInstallType -TestToday.)
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$dv = if ($TestDisplayVersion) { $TestDisplayVersion } else { $cv.DisplayVersion }
$ed = if ($TestEdition) { $TestEdition } else { $cv.EditionID }
$it = if ($TestInstallType) { $TestInstallType } else { $cv.InstallationType }
$today = if ($TestToday) { [datetime]$TestToday } else { Get-Date }
$months = if ($it -eq 'Server' -or $ed -match 'Server|EnterpriseS|IoTEnterpriseS') { 0 } elseif ($ed -match '^(Enterprise|Education|IoTEnterprise)N?$|^EnterpriseG') { 36 } else { 24 }
if (-not $months) { $state.Remove('claude-winver-due') }
elseif ($dv -match '^(\d\d)H(\d)$') {
    $eos = (Get-Date -Year (2000 + [int]$Matches[1]) -Month $(if ($Matches[2] -eq '2') { 10 } else { 4 }) -Day 10).AddMonths($months)
    $target = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate').TargetReleaseVersionInfo
    if ($today -gt $eos.AddDays(-75)) {
        if ($rebootPending -and $target -and $target -gt $dv) { "REBOOT required to finish the Windows $target upgrade (Windows $dv support ends $($eos.ToString('MMM yyyy')))"; $state.Remove('claude-winver-due') }
        else { "WARNING: Windows $dv stops getting security updates around $($eos.ToString('MMM yyyy')) - upgrading it"; $state['claude-winver-due'] = 'yes' }
    }
    else { $state.Remove('claude-winver-due') }
}

# Always say when the next runs are, so a quiet day doesn't leave an empty report section
$next = foreach ($t in @(@('App updates', 'weekly-apps', 7), @('cleanup', 'monthly-cleanup', 30))) { $d = [datetime]::MinValue; if ([datetime]::TryParse("$($state[$t[1]])", [ref]$d)) { "$($t[0]) $($d.AddDays($t[2]).ToString('MMM d'))" } }
if ($next) { "Next: $($next -join ', ')" }

# This run can take an hour (app updates, cleanup): merge only our own keys into the file as it is NOW, so keys the
# launcher or Claude wrote meanwhile (claude-handled-report, claude-quarterly, expo-off-test...) aren't lost
$cur = Read-State
foreach ($k in 'weekly-apps', 'monthly-cleanup', 'trim', 'claude-winver-due') { if ($state.ContainsKey($k)) { $cur[$k] = $state[$k] } else { $cur.Remove($k) } }
$cur | ConvertTo-Json | Set-Content "$stateFile.tmp" -Encoding utf8
Move-Item "$stateFile.tmp" $stateFile -Force
