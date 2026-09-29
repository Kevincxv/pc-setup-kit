# Scripted maintenance decisions (no AI): turns what the background maintenance found into safe fixes, or into plain
# step-by-step items on the owner's to-do list (todo.ps1; the tray alerts on it). Items go away by themselves once the
# thing is fixed. Run by claude-bg-maint.ps1 after its jobs when the optional Claude part is off (with it on, the hidden
# /maintain run does this with judgment). Prints one line per action for the report.
# Never restarts the PC, never touches BIOS settings, never deletes anything (leftovers are only disabled).
# Test overrides: -Lines (the report instead of maint-report.txt), -Board 'Maker|Model', -Now, -JedecDefault.
param([string[]]$Lines, [string]$Board, [datetime]$Now = (Get-Date), [string]$Dir = $PSScriptRoot)
$ErrorActionPreference = 'Continue'
if (-not $Lines) { $Lines = @(Get-Content "$Dir\maint-report.txt" -Encoding UTF8 -ErrorAction SilentlyContinue) }
$stFile = "$Dir\actions-state.json"
$st = @{ crashes = @(); expires = @{}; appFails = @{}; memtest = $null; disabled = @() }
try { $j = Get-Content $stFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    foreach ($k in 'crashes', 'disabled') { if ($j.$k) { $st[$k] = @($j.$k) } }
    foreach ($k in 'expires', 'appFails') { if ($j.$k) { $j.$k.PSObject.Properties | ForEach-Object { $st[$k][$_.Name] = $_.Value } } }
    if ($j.memtest) { $st.memtest = @{}; $j.memtest.PSObject.Properties | ForEach-Object { $st.memtest[$_.Name] = $_.Value } } } catch {}   # (a hashtable: .Result gets added later)
function Todo([string]$Id, [string]$Text, [int]$Days) { & "$Dir\todo.ps1" -Dir $Dir -Id $Id -Text $Text; if ($Days) { $st.expires[$Id] = $Now.AddDays($Days).ToString('o') } }
function Done([string]$Id) { & "$Dir\todo.ps1" -Dir $Dir -Id $Id -Done; $st.expires.Remove($Id) }
function Line([string]$Pattern) { $Lines | Where-Object { $_ -match $Pattern } | Select-Object -First 1 }
$healthRan = [bool]($Lines -match '^\[PC health\]')   # reminders only clear when the check that reports them really ran

# --- Hardware reminders: an item while the reminder is there, gone once fixed ---
if ($healthRan) {
    if (($l = Line '^Reminder: (.+) runs at PCIe x(\d+) \(card supports x(\d+)\)') -and $l -match '^Reminder: (.+) runs at PCIe x(\d+) \(card supports x(\d+)\)') {
        Todo 'gpu-link' "Your graphics card ($($Matches[1])) runs at PCIe x$($Matches[2]) but supports x$($Matches[3]), so it can be slower than it should. Usually it isn't pushed in all the way or it sits in the wrong slot: turn the PC off and unplug it, then push the card firmly into the top long slot until it clicks. If you use a riser cable or chose this on purpose, delete this line."
    } else { Done 'gpu-link' }
    if (($l = Line '^Reminder: RAM runs at its default') -and $l -match 'default (\d+) MT/s \(([^)]*)\)') {
        Todo 'ram-expo' "Your RAM runs at its default speed ($($Matches[1]) MT/s). If you bought faster RAM ($($Matches[2])), switch its speed profile on in the BIOS: restart, press Del (or F2) while the logo shows, find EXPO (AMD) or XMP (Intel) - usually under Overclocking, Ai Tweaker or OC Tweaker - set it to Profile 1 and press F10 to save. If the PC crashes afterwards, set it back to Auto. To keep it as it is, delete this line."
    } else { Done 'ram-expo' }
    if (($l = Line '^Reminder: BIOS (.+) is from (.+) \(over a year old\)') -and $l -match '^Reminder: BIOS (.+) is from (.+) \(over a year old\)') {
        $ver = $Matches[1]; $date = $Matches[2]
        if (-not $Board) { $b = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue; $Board = "$($b.Manufacturer)|$($b.Product)" }
        $maker, $model = $Board -split '\|', 2
        $url = switch -Regex ($maker) {
            'ASUS' { 'https://www.asus.com/support/download-center/' } 'ASRock' { 'https://www.asrock.com/support/index.asp' }
            'Micro-Star|MSI' { 'https://www.msi.com/support/download' } 'Gigabyte' { 'https://www.gigabyte.com/Support' }
            default { "your motherboard maker's website (search for `"$model BIOS`")" } }
        Todo 'bios' "Your motherboard's BIOS ($ver, from $date) is over a year old; newer versions fix stability and security problems. Get the newest BIOS for your $($maker.Trim()) $($model.Trim()) from $url and follow the maker's steps (usually: copy it to a USB stick, then use the update tool inside the BIOS). Never turn the PC off while it updates."
    } else { Done 'bios' }
    if ($l = Line '^Reminder: .+ runs at \d+Hz but supports \d+Hz') {
        # the fix is safe and instant: set the monitor to its best refresh rate
        $fix = @(& "$Dir\display-refresh.ps1")
        $fix
        $bad = $fix | Where-Object { $_ -match '^Monitor: (.+) could not be set to (\d+)Hz' } | Select-Object -First 1
        if ($bad -and $bad -match '^Monitor: (.+) could not be set to (\d+)Hz') {
            Todo 'monitor-hz' "$($Matches[1]) could run at $($Matches[2])Hz but Windows can't switch it with this connection. Use a DisplayPort cable (or an HDMI 2.1 cable) and plug it into the graphics card, not the motherboard."
        } else { Done 'monitor-hz' }
    } else { Done 'monitor-hz' }
    # gaming-check.ps1's reminders: things only the owner can do (BIOS, a driver, moving games) - the reminder's own words
    foreach ($r in @(@('rebar', '^Reminder: Resizable BAR is off'), @('x3d-chipset', "^Reminder: the .+ needs AMD's chipset driver"),
            @('x3d-gamebar', '^Reminder: the .+ needs the Xbox Game Bar'), @('games-hdd', '^Reminder: \d+ Steam game\(s\) are on a hard drive'),
            @('hypervisor', '^Reminder: the Windows hypervisor is running'))) {
        if ($l = Line $r[1]) { Todo $r[0] ($l -replace '^Reminder: ', '') } else { Done $r[0] }
    }
    if (($l = Line '^Reminder: (.+) network link is only (.+?) \(') -and $l -match '^Reminder: (.+) network link is only (.+?) \(') {
        Todo 'network-link' "Your wired network ($($Matches[1])) connects at only $($Matches[2]). Try another network cable (Cat5e or better) or another port on the router."
    } else { Done 'network-link' }
    if (($l = Line '^Reminder: (.+) \((\d+) GB\) is connected and nothing is backed up') -and $l -match '^Reminder: (.+) \((\d+) GB\) is connected') {
        Todo 'backup' "The drive $($Matches[1]) is connected but nothing is backed up. To back up your files to it automatically: open Control Panel > File History, choose that drive and click Turn on."
    } else { Done 'backup' }
    if (Line '^WARNING: Defender real-time protection is OFF') {
        Todo 'defender' "Windows Security's real-time protection is off. Open Windows Security > Virus & threat protection > Manage settings and turn Real-time protection on (unless you use another antivirus)."
    } else { Done 'defender' }
    if (($l = Line '^WARNING: C: is low on space') -and $l -match '\((\d+) GB free\)') {
        Todo 'disk-space' "Drive C: is almost full ($($Matches[1]) GB free). Open Settings > System > Storage > Cleanup recommendations, or uninstall games you no longer play."
    } else { Done 'disk-space' }
    if (($l = Line '^WARNING: drive (.+) reports (\w+) health') -and $l -match '^WARNING: drive (.+) reports (\w+) health') {
        Todo 'drive-health' "Back up your files now: the drive $($Matches[1]) reports it may fail soon ($($Matches[2])). Then replace it."
    } else { Done 'drive-health' }
    if (($l = Line '^WARNING: (.+) wear at (\d+)%') -and $l -match '^WARNING: (.+) wear at (\d+)%') {
        Todo 'drive-wear' "$($Matches[1]) is $($Matches[2])% worn out. Keep backups and plan to replace it."
    } else { Done 'drive-wear' }
}

# --- Crashes: the crash ladder, as fixed rules ---
foreach ($l in $Lines) {
    if ($l -match '^WARNING: blue screen (\S+) at (.+?)\s*$') { $st.crashes += [pscustomobject]@{ Time = $Matches[2]; Code = $Matches[1]; Blamed = '' } }
}
foreach ($l in $Lines) {   # the dump analysis names the driver/module (crash-analyze.ps1)
    if ($l -match 'blamed: (\S+) \(([^)]*)\)' -and $st.crashes) { $st.crashes[-1].Blamed = "$($Matches[1])" }
}
$seen = @{}; $st.crashes = @($st.crashes | Where-Object { $t = [datetime]::MinValue; [datetime]::TryParse("$($_.Time)", [ref]$t) -and $t -gt $Now.AddDays(-30) -and -not $seen.ContainsKey("$($_.Time)") -and ($seen["$($_.Time)"] = 1) })
$recent = @($st.crashes | Where-Object { $t = [datetime]::MinValue; [void][datetime]::TryParse("$($_.Time)", [ref]$t); $t -gt $Now.AddDays(-14) })
$core = '^(ntoskrnl|hal|win32k\w*|memory_corruption|nt|unknown|)(\.\w+)?$'   # Windows itself: not a driver to update
if ($recent) {
    $last = $recent[-1]
    $who = if ($last.Blamed -and $last.Blamed -notmatch $core) { " It points at $($last.Blamed): update or reinstall the program or driver it belongs to." } else { '' }
    if ($recent.Count -eq 1) {
        Todo 'crash' "A blue screen happened on $($last.Time) (code $($last.Code)).$who Drivers are kept up to date automatically; if it happens again, the next step shows up here." 14
    } else {
        $ram = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue | Select-Object -First 1
        $jedec = 2133, 2400, 2666, 2933, 3200, 4800, 5200, 5600
        $fastProfile = $ram -and $ram.ConfiguredClockSpeed -and $jedec -notcontains [int]$ram.ConfiguredClockSpeed
        $step = if ($fastProfile) { " The most common cause is RAM running at its fast profile (EXPO/XMP): for a week, test without it - restart, press Del (or F2) at the logo, set EXPO/XMP to Auto or Disabled, press F10. If the blue screens stop, the RAM settings were the cause." } else { '' }
        Todo 'crash' "Blue screens keep happening ($($recent.Count) in the last 2 weeks, last on $($last.Time), code $($last.Code)).$who$step" 14
        # a memory test at the owner's next restart (never restarts the PC itself); once
        if (-not $st.memtest -and ((bcdedit /enum '{memdiag}' 2>&1 | Out-String) -match 'memdiag|Windows Memory Tester')) {
            $o = bcdedit /bootsequence '{memdiag}' 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0 -or $o -match 'successfully') {
                $st.memtest = @{ Scheduled = $Now.ToString('o') }
                'Crashes: a memory test runs at the next restart'
                Todo 'memtest' 'A memory test runs automatically the next time you restart the PC (about 20 minutes - do not turn it off meanwhile). The result shows up here afterwards.' 30
            }
        }
    }
} else { Done 'crash' }
if ($st.memtest -and -not $st.memtest.Result) {   # its result, once it ran
    $t0 = [datetime]::MinValue; [void][datetime]::TryParse("$($st.memtest.Scheduled)", [ref]$t0)
    $ev = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results'; StartTime = $t0 } -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($ev) {
        Done 'memtest'
        if ($ev.Id -eq 1101) { $st.memtest.Result = 'ok'; 'Crashes: the memory test found no errors' }
        else { $st.memtest.Result = 'errors'; 'WARNING: the memory test found RAM errors'
            Todo 'ram-faulty' 'The memory test found errors: a RAM stick is likely faulty. If EXPO/XMP is on, set it to Auto in the BIOS first; if blue screens continue, test with one stick at a time or contact the seller (warranty).' 60 }
    }
}
if (($l = Line '^WARNING: unexpected shutdown/freeze at (.+?) \(') -and $l -match 'at (.+?) \(') {
    Todo 'freeze' "The PC went off without shutting down on $($Matches[1]). If you turned it off yourself, delete this line. If it froze or switched off by itself and it happens again, check that the power cable sits firmly." 7
}
if (($l = Line '^WARNING: (\d+) hardware error\(s\) logged \(WHEA\)') -and $l -match '^WARNING: (\d+)') {
    Todo 'whea' "Windows logged $($Matches[1]) hardware error(s). If you overclocked the CPU or RAM (including EXPO/XMP), set it back to default in the BIOS. If they continue, the RAM, CPU or power supply may be failing." 14
}

# --- App updates that keep failing (the weekly update retries; after 3 weeks in a row: an item) ---
foreach ($l in $Lines) {
    if ($l -match '^App update FAILED: (\S+)') { $st.appFails[$Matches[1]] = 1 + [int]$st.appFails[$Matches[1]] }
    elseif ($l -match '^Updated app: (\S+)') { $st.appFails.Remove($Matches[1]); Done "app-$($Matches[1])" }
}
foreach ($id in @($st.appFails.Keys)) {
    if ([int]$st.appFails[$id] -ge 3) { Todo "app-$id" "$id has failed to update by itself for 3 weeks. Open it and update it from its own menu, or uninstall it and install it again." }
}

# --- Leftovers of deleted programs: disabled (not deleted), so they can be switched back on ---
if (($l = Line '^WARNING: leftovers pointing at deleted programs: (.+)$') -and $l -match 'programs: (.+)$') {
    foreach ($item in $Matches[1] -split ', ') {
        if ($item -match '^task (.*\\)([^\\]+)$') {
            try { Disable-ScheduledTask -TaskPath $Matches[1] -TaskName $Matches[2] -ErrorAction Stop | Out-Null; "Leftovers: disabled task $($Matches[1])$($Matches[2]) (its program was deleted)"; $st.disabled += $item } catch {}
        } elseif ($item -match '^service (\S+)$') {
            $svc = Get-CimInstance Win32_Service -Filter "Name='$($Matches[1])'" -ErrorAction SilentlyContinue
            if ($svc -and $svc.State -eq 'Stopped' -and $svc.StartMode -ne 'Disabled' -and $svc.PathName -notmatch '(?i)\\Windows\\') {
                try { Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction Stop; "Leftovers: disabled service $($svc.Name) (its program was deleted)"; $st.disabled += $item } catch {}
            }
        }
    }
}

# --- Restore points failing because System Protection is off for C: - Windows' own undo points, switched on ---
if (Line '^Restore point FAILED') {
    try { Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop; 'Restore points: turned System Protection on for C: (the monthly restore point works from next month)' }
    catch { "Restore points: couldn't turn System Protection on ($($_.Exception.Message))" }
}

# --- Windows near its end of support: ask Windows Update for the newest version (installs like any update) ---
$msFile = "$Dir\maint-state.json"
function Read-MaintState { $s = @{}; try { (Get-Content $msFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).PSObject.Properties | ForEach-Object { $s[$_.Name] = $_.Value } } catch {}; $s }
function Save-MaintKey([string]$Key, $Value) {   # merge one key into the file as it is now (other writers keep theirs)
    $s = Read-MaintState; if ($null -eq $Value) { $s.Remove($Key) } else { $s[$Key] = $Value }
    $s | ConvertTo-Json | Set-Content "$msFile.tmp" -Encoding UTF8; Move-Item "$msFile.tmp" $msFile -Force
}
$ms = Read-MaintState
if ($ms['claude-winver-due']) {
    try {
        $page = (Invoke-WebRequest 'https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information' -UseBasicParsing -TimeoutSec 30).Content
        $latest = [regex]::Matches($page, 'Version (\d{2}H[12])') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique | Select-Object -Last 1
        $cur = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).DisplayVersion
        if ($latest -and $latest -gt "$cur") {
            $wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
            if (-not (Test-Path $wu)) { New-Item $wu -Force | Out-Null }
            Set-ItemProperty $wu ProductVersion 'Windows 11'; Set-ItemProperty $wu TargetReleaseVersion 1 -Type DWord; Set-ItemProperty $wu TargetReleaseVersionInfo $latest
            "Windows: asked Windows Update for version $latest (it installs by itself and finishes at a restart)"
            Save-MaintKey 'claude-winver-due' $null
        }
    } catch { "Windows: couldn't look up the newest version ($($_.Exception.Message)) - next run" }
}

# --- Scheduled checks (the same clocks the Status window shows) ---
function Due([string]$Key, [int]$Days) { $d = [datetime]::MinValue; -not [datetime]::TryParse("$($ms[$Key])", [ref]$d) -or $d -lt $Now.AddDays(-$Days) }
if (Due 'claude-yearly' 365) {   # a full optimize run (it includes the benchmark)
    if (Test-Path "$Dir\optimize.ps1") { & "$Dir\optimize.ps1" -FromMaintenance }
    Save-MaintKey 'claude-yearly' $Now.ToString('o'); Save-MaintKey 'claude-quarterly' $Now.ToString('o')
} elseif (Due 'claude-quarterly' 90) {   # re-benchmark against the baseline
    if (Test-Path "$Dir\optimize.ps1") { & "$Dir\optimize.ps1" -Benchmark -FromMaintenance }
    Save-MaintKey 'claude-quarterly' $Now.ToString('o')
}
if (Due 'claude-halfyear' 180) {
    Todo 'dust' 'Time for a clean: turn the PC off and unplug it, then blow the dust out of the fans, filters and graphics card with compressed air (hold each fan still while you blow). Delete this line when done.' 14
    Save-MaintKey 'claude-halfyear' $Now.ToString('o')
}

# --- items with an end date go away by themselves ---
foreach ($id in @($st.expires.Keys)) { $d = [datetime]::MinValue; if ([datetime]::TryParse("$($st.expires[$id])", [ref]$d) -and $d -lt $Now) { Done $id } }
$st | ConvertTo-Json -Depth 5 | Set-Content "$stFile.tmp" -Encoding UTF8; Move-Item "$stFile.tmp" $stFile -Force
