# Your own files on a second drive, by itself: Documents, Desktop, Pictures, Videos and Music copied to
# <drive>:\Messiah Backup\<PC name>\ whenever that drive is connected (at most every 20 hours; new and changed files
# only, and nothing is ever deleted from the backup - a file deleted or overwritten by mistake is still there).
# The drive is chosen once, in the app: when a second drive with room (64 GB+; not the kit or install USB) is there
# and nothing backs the files up yet, a to-do item offers it ("Back up to this drive" = -Enable). Remembered by the
# drive's volume id (kit-options.txt filebackup=), so its letter may change.
# -Check: health-check.ps1 (the offer, or the backup when due, or a reminder when the drive hasn't been connected for
# 2 weeks). -Arrived: the tray, when a drive is plugged in. -Enable: the app's button (the first candidate drive).
# -Test (hashtable: Candidates = @(@{ Id; Label; Letter; SizeGB }), Configured (id), Other (another backup exists),
# Exit (robocopy), LastRun, LastSeen, Game) with -Do, -Options, -State, -Now: tests.
param([switch]$Check, [switch]$Arrived, [switch]$Enable, [hashtable]$Test, [scriptblock]$Do,
    [string]$Options = "$PSScriptRoot\kit-options.txt", [string]$State = "$PSScriptRoot\files-backup-state.json", [datetime]$Now = (Get-Date))
$ErrorActionPreference = 'SilentlyContinue'
$T = $Test
if ($env:PCKIT_IN_TESTS -and -not $T) { return }   # never from the test suite (the real drives and files)
function Act([string]$What, [scriptblock]$Real) { if ($Do) { & $Do $What } else { & $Real } }
$st = @{}; try { (Get-Content $State -Raw -ErrorAction Stop | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $st[$_.Name] = $_.Value } } catch {}
if ($T) { if ($T.LastRun) { $st.lastRun = $T.LastRun }; if ($T.LastSeen) { $st.lastSeen = $T.LastSeen } }
function Save { try { [pscustomobject]$st | ConvertTo-Json | Set-Content $State -Encoding UTF8 } catch {} }
function Get-Opt { $l = @(Get-Content $Options) -match '^\s*filebackup\s*=' | Select-Object -First 1; if ($l) { ($l -split '=', 2)[1].Trim() } }
function Set-Opt($v) { $lines = @(Get-Content $Options | Where-Object { $_ -notmatch '^\s*filebackup\s*=' }) + "filebackup=$v"; [IO.File]::WriteAllLines($Options, [string[]]$lines) }

# second drives with room: not the Windows disk, not virtual, 64 GB+, a letter, not a kit / install USB
function Get-Candidates {
    if ($T) { return @($T.Candidates | ForEach-Object { [pscustomobject]$_ }) }
    $sys = (Get-Partition -DriveLetter C).DiskNumber
    @(foreach ($d in Get-Disk | Where-Object { $_.Number -ne $sys -and $_.BusType -notin 'File Backed Virtual', 'Virtual' -and -not $_.IsBoot }) {
            foreach ($v in $d | Get-Partition | Get-Volume | Where-Object { $_.DriveLetter -and $_.Size -ge 64GB -and $_.FileSystem -in 'NTFS', 'exFAT', 'ReFS' }) {
                $r = "$($v.DriveLetter):\"
                if ((Test-Path "$r\PCSetupKit") -or (Test-Path "$r\sources\install.wim") -or (Test-Path "$r\sources\install.swm") -or (Test-Path "$r\sources\install.esd")) { continue }
                [pscustomobject]@{ Id = "$($v.UniqueId)"; Label = $(if ($v.FileSystemLabel) { $v.FileSystemLabel } else { $d.FriendlyName }); Letter = "$($v.DriveLetter)"; SizeGB = [int]($v.Size / 1GB) }
            }
        })
}
$folders = if ($T) { 'Documents', 'Desktop', 'Pictures', 'Videos', 'Music' } else {
    [ordered]@{ Documents = [Environment]::GetFolderPath('MyDocuments'); Desktop = [Environment]::GetFolderPath('Desktop'); Pictures = [Environment]::GetFolderPath('MyPictures'); Videos = [Environment]::GetFolderPath('MyVideos'); Music = [Environment]::GetFolderPath('MyMusic') }
}
function Invoke-Backup($c) {
    $dest = "$($c.Letter):\Messiah Backup\$env:COMPUTERNAME"
    $worst = 0; $copied = $false
    foreach ($f in @($(if ($T) { $folders } else { $folders.Keys }))) {
        $code = 0
        if ($Do) { & $Do "copy $f"; $code = $T.Exit }
        elseif (Test-Path $folders[$f]) { $null = robocopy $folders[$f] "$dest\$f" /E /XO /XJ /R:1 /W:1 /MT:8 /NP /NFL /NDL /NJH /NJS /XF desktop.ini thumbs.db; $code = $LASTEXITCODE }
        if ($code -band 1) { $copied = $true }; if ($code -ge 8) { $worst = $code }
    }
    $st.lastRun = $Now.ToString('o'); $st.lastSeen = $Now.ToString('o'); Save
    if ($worst) { "Files backup to $($c.Label) ($($c.Letter):) FAILED for some files (robocopy $worst - the drive full, or files in use); tried again next time" }
    elseif ($copied) { "Files backup: new and changed files copied to $($c.Label) ($($c.Letter):\Messiah Backup)" }
    else { "Files backup: $($c.Label) is up to date" }
}

$want = if ($T) { $T.Configured } else { Get-Opt }
$cands = Get-Candidates
if ($Enable) {
    $c = $cands | Select-Object -First 1
    if (-not $c) { return 'No second drive with room is connected - plug one in (64 GB or more) and try again' }
    if (-not $T) { Set-Opt $c.Id }
    Invoke-Backup $c
    return
}
if ($want) {
    $c = $cands | Where-Object Id -eq $want | Select-Object -First 1
    if ($c) {
        $last = [datetime]::MinValue; [void][datetime]::TryParse("$($st.lastRun)", [ref]$last)
        if ($last -gt $Now.AddHours(-20)) { $st.lastSeen = $Now.ToString('o'); Save; return }
        if ($g = $(if ($T) { $T.Game } else { & "$PSScriptRoot\game-check.ps1" })) { return }   # never under a game (the disk is busy)
        return Invoke-Backup $c
    }
    if ($Check) {
        $seen = [datetime]::MinValue; [void][datetime]::TryParse("$($st.lastSeen)", [ref]$seen)
        if ($seen -gt [datetime]::MinValue -and $seen -lt $Now.AddDays(-14)) { "Reminder: your files backup drive hasn't been connected for $([int]($Now - $seen).TotalDays) days - plug it in and the backup catches up by itself" }
    }
    return
}
if (-not $Check) { return }
# nothing chosen yet: offer the first candidate (unless something else already backs the files up)
$other = if ($T) { $T.Other } else {
    (Test-Path "$env:LOCALAPPDATA\Microsoft\Windows\FileHistory\Configuration\Config1.xml") -or
    [bool](Get-ScheduledTask | Where-Object { $_.TaskName -match 'backup' -and $_.TaskPath -notlike '\Microsoft\*' -and $_.State -ne 'Disabled' })
}
if ($other) { return }
$c = $cands | Select-Object -First 1
if ($c) { "Reminder: $($c.Label) ($($c.SizeGB) GB, $($c.Letter):) is connected and nothing is backed up" }
