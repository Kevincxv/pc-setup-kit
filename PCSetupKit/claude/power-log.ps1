# The PC's stability record (power-log.json), for the app's Home question and Activity > Stability, the RAM stick test
# and /maintain:
#   events   every blue screen and every time the PC went off without one (Windows' log: Kernel-Power 41 at the start
#            after it - bugcheck 0 = no blue screen; the time it went off from event 6008), each with the owner's answer
#            for the ones without a blue screen: me (turned it off themselves) / froze (it froze or went off by itself) /
#            unsure. 10/12: three times "did you turn it off?" was asked in the chat - now the app asks, once.
#   changes  what changed that matters for crashes: the graphics driver, the BIOS, the RAM (sticks, speed - EXPO), Driver
#            Verifier, the hardware-monitor driver (PawnIO) - seen at each update, so the timeline shows what was different before and after a crash
# -Update: health-check.ps1 (at each login - right after a crash). -Answer <key> <me|froze|unsure>: the app's buttons.
# Test overrides: -File, -Events (@{ At; Bugcheck; OffAt }), -Snapshot (@{ gpu; bios; ram; verifier }), -Now.
param([switch]$Update, [string]$Answer, [string]$Key, [string]$File = "$env:USERPROFILE\.claude\power-log.json", [object[]]$Events, [hashtable]$Snapshot, [datetime]$Now = (Get-Date))
$ErrorActionPreference = 'SilentlyContinue'
$log = try { Get-Content $File -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json } catch { $null }
$ev = @(if ($log) { $log.events }); $ch = @(if ($log) { $log.changes }); $last = if ($log) { $log.last }
function Save { $o = [ordered]@{ events = @($ev | Sort-Object at); changes = @($ch | Sort-Object at); last = $last }; [IO.File]::WriteAllText("$File.tmp", ($o | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false)); Move-Item "$File.tmp" $File -Force }

if ($Answer) {
    if ($Answer -notin 'me', 'froze', 'unsure' -or -not $Key) { return }
    foreach ($e in $ev) { if ($e.key -eq $Key) { $e.answer = $Answer; $e | Add-Member answeredAt $Now.ToString('o') -Force } }
    Save; return
}
if (-not $Update) { return }

# --- the crashes and power-offs Windows logged (all of its System log, so the timeline starts with the PC's history)
$found = if ($Events) { $Events } else {
    $offs = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 6008 } | ForEach-Object {
            $m = ($_.Message -replace "[$([char]0x200E)$([char]0x200F)]", ''); $d = [datetime]::MinValue   # (Windows puts invisible left-to-right marks in the date)
            if ($m -match 'at (.+?) on (.+?) was' -and [datetime]::TryParse("$($Matches[2]) $($Matches[1])", [ref]$d)) { [pscustomobject]@{ Logged = $_.TimeCreated; At = $d } } })
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41 } | ForEach-Object {
        $t = $_.TimeCreated; $o = $offs | Where-Object { [Math]::Abs(($_.Logged - $t).TotalMinutes) -lt 3 } | Select-Object -First 1
        @{ At = $t; Bugcheck = [long]$_.Properties[0].Value; OffAt = $(if ($o) { $o.At }) } }
}
$known = @{}; foreach ($e in $ev) { $known[$e.key] = $true }
foreach ($f in $found) {
    $k = ([datetime]$f.At).ToString('yyyy-MM-ddTHH:mm:ss')
    if ($known[$k]) { continue }
    $bsod = [long]$f.Bugcheck -ne 0
    $ev += [pscustomobject]@{ key = $k; at = $(if ($f.OffAt) { ([datetime]$f.OffAt).ToString('yyyy-MM-ddTHH:mm:ss') } else { $k }); kind = $(if ($bsod) { 'bsod' } else { 'off' })
        code = $(if ($bsod) { '0x{0:X}' -f [long]$f.Bugcheck } else { '' }); answer = '' }
}

# --- what's different now (a change is recorded with the time it was first seen)
$s = if ($Snapshot) { $Snapshot } else {
    $sticks = @(Get-CimInstance Win32_PhysicalMemory)
    @{ gpu = "$((Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA|Radeon|Arc' } | Select-Object -First 1).Name) $(try { (& nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>$null | Select-Object -First 1).Trim() } catch { '' })".Trim()
        bios = "$((Get-CimInstance Win32_BIOS).SMBIOSBIOSVersion)"
        ram = "$($sticks.Count) x $([math]::Round(($sticks | Select-Object -First 1).Capacity / 1GB)) GB at $(($sticks | Select-Object -First 1).ConfiguredClockSpeed) MT/s in $(@($sticks | ForEach-Object { "$($_.BankLabel)".Trim() -replace '^P0 CHANNEL ', 'slot ' }) -join ' + ')"
        verifier = $(if ("$((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management').VerifyDrivers)".Trim()) { 'on' } else { 'off' })
        # the hardware-monitor kernel driver (cpu-temp.ps1 - 10/22): a kernel driver is what matters around a crash
        monitor = $($v = "$((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO' -ErrorAction SilentlyContinue).DisplayVersion)"; if ($v) { "PawnIO $v" } else { 'none' }) }
}
$names = @{ gpu = 'Graphics driver'; bios = 'BIOS'; ram = 'RAM'; verifier = 'Driver Verifier'; monitor = 'Hardware monitor driver' }
if ($last) {
    foreach ($k in 'gpu', 'bios', 'ram', 'verifier', 'monitor') {
        if ("$($s[$k])" -and "$($last.$k)" -and "$($s[$k])" -ne "$($last.$k)") { $ch += [pscustomobject]@{ at = $Now.ToString('yyyy-MM-ddTHH:mm:ss'); what = $names[$k]; from = "$($last.$k)"; to = "$($s[$k])" } }
    }
}
$last = [pscustomobject]$s
Save
# the question, said once in the report too (the app asks it on Home)
$open = @($ev | Where-Object { $_.kind -eq 'off' -and -not $_.answer -and [datetime]$_.key -gt $Now.AddDays(-30) })
if ($open -and -not $Events) { "Reminder: the PC went off without a blue screen $(@($open | ForEach-Object { ([datetime]$_.at).ToString('ddd MMM d h:mm tt') }) -join ', ') - did you turn it off? (the app's Home asks)" }
