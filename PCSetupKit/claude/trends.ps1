# Health over time: every check adds one line to health-history.json (start-up time, free space on C:, SSD wear and
# temperature, graphics card temperature at idle), then compares with this PC's own normal. Run by health-check.ps1.
# - Start-up much slower than usual (1.5x and 10+ s): what slowed it (Windows' own start-up diagnostics); three slow
#   start-ups in a row = WARNING (gets looked at)
# - C: filling up: when it will be full at the current pace
# - Graphics card 10+ C warmer at idle than a month ago (dust), SSD wear rising fast
# Prints only what's worth saying. -History / -Now: test overrides.
param([string]$History = "$PSScriptRoot\health-history.json", [datetime]$Now = (Get-Date))
$ErrorActionPreference = 'SilentlyContinue'
$j = try { Get-Content $History -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { }
$h = @($j | ForEach-Object { $_ })   # PowerShell 5.1 hands a JSON array over as ONE item: unrolled here
function Median($v) { $s = @($v | Sort-Object); if (-not $s) { return $null }; $m = [int][Math]::Floor($s.Count / 2); if ($s.Count % 2) { $s[$m] } else { ($s[$m - 1] + $s[$m]) / 2 } }

# --- this check's numbers ---
$e = [ordered]@{ date = $Now.ToString('o') }
$dp = 'Microsoft-Windows-Diagnostics-Performance/Operational'
$b = Get-WinEvent -FilterHashtable @{ LogName = $dp; Id = 100 } -MaxEvents 1
$bd = @{}; if ($b) { ([xml]$b.ToXml()).Event.EventData.Data | ForEach-Object { $bd[$_.Name] = $_.'#text' } }
if ($bd.BootTime) { $e.bootAt = $b.TimeCreated.ToString('o'); $e.boot = [Math]::Round([int]$bd.BootTime / 1000, 1) }
$free = (Get-PSDrive C).Free; if ($free) { $e.freeGB = [Math]::Round($free / 1GB, 1) }
$rc = Get-Partition -DriveLetter C | Get-Disk | Get-StorageReliabilityCounter
if ($null -ne $rc.Wear) { $e.ssdWear = [int]$rc.Wear }; if ($rc.Temperature) { $e.ssdTemp = [int]$rc.Temperature }
$g = "$(& nvidia-smi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1)" -split ',\s*'
if ($g.Count -eq 2 -and [int]$g[1] -lt 10) { $e.gpuIdle = [int]$g[0] }   # only when the card is idle (a game would skew it)
$h = @($h | Where-Object { $_.date }) + [pscustomobject]$e | Select-Object -Last 300
try { ConvertTo-Json -InputObject @($h) -Depth 3 | Set-Content "$History.tmp" -Encoding UTF8; Move-Item "$History.tmp" $History -Force } catch {}   # always an array, even with one entry

# --- start-up time: this boot vs the usual (the median of the 10 boots before it) ---
$boots = @($h | Where-Object { $_.bootAt -and $_.boot } | Group-Object bootAt | ForEach-Object { $_.Group[-1] } | Sort-Object { [datetime]$_.bootAt })
if ($e.boot -and $boots.Count -ge 6) {
    $usual = Median ($boots | Select-Object -SkipLast 1 | Select-Object -Last 10 | ForEach-Object { [double]$_.boot })
    $slow = { param($x) $x -ge $usual * 1.5 -and $x -ge $usual + 10 }
    if (& $slow $e.boot) {
        # what slowed it: Windows logs each app / driver / service that made this start-up slower (events 101-110)
        $bt = [datetime]$e.bootAt
        $why = @(Get-WinEvent -FilterHashtable @{ LogName = $dp; StartTime = $bt.AddMinutes(-10); EndTime = $bt.AddMinutes(10) } | Where-Object { $_.Id -ge 101 -and $_.Id -le 110 } | ForEach-Object {
                $d = @{}; ([xml]$_.ToXml()).Event.EventData.Data | ForEach-Object { $d[$_.Name] = $_.'#text' }
                [pscustomobject]@{ Name = $(if ($d.FriendlyName) { $d.FriendlyName } else { $d.Name }); Ms = [int]$d.DegradationTime } } |
            Sort-Object Ms -Descending | Select-Object -First 3 | ForEach-Object { "$($_.Name) (+$([Math]::Round($_.Ms / 1000, 1)) s)" })
        $streak = @($boots | Select-Object -Last 3 | Where-Object { & $slow ([double]$_.boot) }).Count
        "$(if ($streak -ge 3) { 'WARNING: start-up has been slow 3 times in a row' } else { 'Reminder: this start-up was slow' }) - $($e.boot) s (usually $usual s)$(if ($why) { "; slowed by: $($why -join ', ')" })"
    }
}

# --- C: filling up: the pace over the last 1-4 weeks ---
$past = $h | Where-Object { $_.freeGB -and [datetime]$_.date -lt $Now.AddDays(-7) -and [datetime]$_.date -gt $Now.AddDays(-28) } | Select-Object -First 1
if ($e.freeGB -and $past) {
    $perDay = ([double]$past.freeGB - $e.freeGB) / ($Now - [datetime]$past.date).TotalDays
    if ($perDay -gt 0.5) {
        $days = [int](($e.freeGB - 10) / $perDay)   # "full" = under 10 GB (Windows updates and games need room)
        if ($days -lt 30) { "$(if ($days -lt 14) { 'WARNING' } else { 'Reminder' }): C: is filling up - $($e.freeGB) GB free, about $([Math]::Round($perDay * 7)) GB less each week; nearly full in about $([Math]::Max(0, $days)) days" }
    }
}

# --- graphics card at idle: this week vs a month ago ---
$idle = { param($from, $to) Median ($h | Where-Object { $_.gpuIdle -and [datetime]$_.date -ge $from -and [datetime]$_.date -lt $to } | ForEach-Object { [int]$_.gpuIdle }) }
$then = & $idle $Now.AddDays(-45) $Now.AddDays(-25); $recent = & $idle $Now.AddDays(-7) $Now.AddMinutes(1)
if ($then -and $recent -and $recent -ge $then + 10) { "Reminder: the graphics card runs $($recent - $then) C warmer at idle than a month ago ($recent C, was $then C) - dust in the fans or filters? A clean usually fixes it" }

# --- SSD wear: fast rise ---
$w0 = $h | Where-Object { $null -ne $_.ssdWear -and [datetime]$_.date -gt $Now.AddDays(-31) } | Select-Object -First 1
if ($null -ne $e.ssdWear -and $w0 -and $e.ssdWear - [int]$w0.ssdWear -ge 5) { "Reminder: the SSD wore $($e.ssdWear - [int]$w0.ssdWear)% in a month (now $($e.ssdWear)% used) - something is writing a lot" }
