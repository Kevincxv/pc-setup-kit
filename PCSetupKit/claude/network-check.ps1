# Network quality at every check (run by health-check.ps1), kept in net-history.json (last 300) and charted by the app:
# - ping, jitter and packet loss to the router (the home network: Wi-Fi, cables) and to the internet (1.1.1.1)
# - how fast the DNS server answers, next to public ones (1.1.1.1, 8.8.8.8)
# Uses no data worth counting (pings and a few DNS lookups - no speed tests; the owner's rule).
# Says something only when it repeats (2 of the last 3 checks), since one bad minute on a network is normal.
# A slow DNS is fixed, not just reported - only where that's safe: a wired connection (a laptop on hotel Wi-Fi needs
# the network's own DNS for its sign-in page) whose DNS is the router itself (a Pi-hole or a company DNS is someone's
# choice). The adapter then uses 1.1.1.1 / 1.0.0.1; if those ever stop answering, it goes back to automatic.
# -Measured: tests (a hashtable of this check's numbers - nothing is measured); -SetDns: tests (a scriptblock that
# receives 'public' or 'reset' instead of the real change).
param([string]$History = "$PSScriptRoot\net-history.json", [datetime]$Now = (Get-Date), [hashtable]$Measured, [scriptblock]$SetDns)
$ErrorActionPreference = 'SilentlyContinue'
$j = try { Get-Content $History -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { }
$h = @($j | ForEach-Object { $_ })   # PowerShell 5.1 hands a JSON array over as ONE item: unrolled here
function Median($v) { $s = @($v | Sort-Object); if (-not $s) { return $null }; $m = [int][Math]::Floor($s.Count / 2); if ($s.Count % 2) { $s[$m] } else { ($s[$m - 1] + $s[$m]) / 2 } }
# pings: median, jitter (the average change between two pings) and loss %, 150 ms apart
function Measure-Ping([string]$Target, [int]$Count = 30) {
    $p = New-Object Net.NetworkInformation.Ping; $ms = @(); $lost = 0
    for ($i = 0; $i -lt $Count; $i++) {
        try { $r = $p.Send($Target, 1000); if ($r.Status -eq 'Success') { $ms += [double]$r.RoundtripTime } else { $lost++ } } catch { $lost++ }
        Start-Sleep -Milliseconds 150
    }
    $jit = if ($ms.Count -ge 2) { (@(for ($i = 1; $i -lt $ms.Count; $i++) { [Math]::Abs($ms[$i] - $ms[$i - 1]) }) | Measure-Object -Average).Average }
    @{ ms = Median $ms; jitter = $(if ($null -ne $jit) { [Math]::Round($jit, 1) }); loss = [Math]::Round(100 * $lost / $Count, 1) }
}
function Measure-Dns([string]$Server) {
    $t = foreach ($n in 'www.microsoft.com', 'store.steampowered.com', 'discord.com', 'www.google.com', 'www.nvidia.com') {
        $w = [Diagnostics.Stopwatch]::StartNew()
        if (Resolve-DnsName $n -Server $Server -DnsOnly -QuickTimeout -Type A -ErrorAction Stop) { $w.Elapsed.TotalMilliseconds }
    }
    if (@($t).Count -ge 3) { [Math]::Round((Median $t), 0) }
}

# --- this check's numbers ---
$e = [ordered]@{ date = $Now.ToString('o') }
if ($Measured) { foreach ($k in $Measured.Keys) { $e[$k] = $Measured[$k] } }
else {
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
    if (-not $route) { return }   # offline: nothing to measure
    $gw = Measure-Ping $route.NextHop; $net = Measure-Ping '1.1.1.1'
    $e.gwPing = $gw.ms; $e.gwJitter = $gw.jitter; $e.gwLoss = $gw.loss; $e.ping = $net.ms; $e.jitter = $net.jitter; $e.loss = $net.loss
    $e.wifi = [bool]((Get-NetAdapter -InterfaceIndex $route.InterfaceIndex).NdisPhysicalMedium -eq 9)   # 9 = native 802.11
    $dns = @((Get-DnsClientServerAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4).ServerAddresses) | Select-Object -First 1
    if ($dns) { $e.dnsServer = $dns; $e.dnsIsRouter = $dns -eq $route.NextHop; $e.dns = Measure-Dns $dns }
    $e.ifIndex = $route.InterfaceIndex
    $pub = @(foreach ($s in '1.1.1.1', '8.8.8.8') { if ($s -ne $dns) { Measure-Dns $s } }) | Where-Object { $_ }
    if ($pub) { $e.dnsBest = ($pub | Measure-Object -Minimum).Minimum }
}
$h = @($h | Where-Object { $_.date }) + [pscustomobject]$e | Select-Object -Last 300
try { ConvertTo-Json -InputObject @($h) -Depth 3 | Set-Content "$History.tmp" -Encoding UTF8; Move-Item "$History.tmp" $History -Force } catch {}

# --- what repeats: 2 of the last 3 checks ---
$l3 = @($h | Select-Object -Last 3)
$twice = { param($cond) @($l3 | Where-Object $cond).Count -ge 2 }
$via = if ($e.wifi) { 'Wi-Fi signal (a cable is steadier for games)' } else { 'network cable or router port' }
if (& $twice { $_.gwLoss -ge 3 }) { "Reminder: the home network loses packets to the router ($($e.gwLoss)% now) - check the $via" }
elseif (& $twice { $_.loss -ge 3 }) { "Reminder: the internet connection loses packets ($($e.loss)% to 1.1.1.1, the home network is fine) - in games that's rubber-banding; the modem or the provider" }
if (& $twice { $_.jitter -ge 15 }) { "Reminder: the connection is unsteady - pings vary by $($e.jitter) ms on average$(if ($e.gwJitter -ge 10) { " (already to the router: $via)" })" }
$change = if ($SetDns) { $SetDns } else { { param($to) if ($to -eq 'public') { Set-DnsClientServerAddress -InterfaceIndex $e.ifIndex -ServerAddresses '1.1.1.1', '1.0.0.1' } else { Set-DnsClientServerAddress -InterfaceIndex $e.ifIndex -ResetServerAddresses } } }
$slowDns = { $_.dns -and $_.dnsBest -and $_.dns -ge 2 * $_.dnsBest -and $_.dns -ge $_.dnsBest + 30 }
$mine = @($h | Where-Object { $_.dnsSet } | Select-Object -Last 1).dnsSet   # the last change this script made (not the owner)
if ($mine -eq 'public' -and $e.dnsServer -eq '1.1.1.1' -and $null -eq $e.dns -and $e.ping) {
    & $change 'reset'; $e.dnsSet = 'reset'
    'Network: 1.1.1.1 stopped answering on this network - DNS set back to automatic (the router''s)'
}
elseif ((@([pscustomobject]$e) | Where-Object $slowDns) -and (& $twice $slowDns)) {   # slow now too (not just in older checks - e.g. before a switch)
    if (-not $e.wifi -and $e.dnsIsRouter -and $e.ifIndex -and $mine -ne 'reset') {   # (after a way back: never again - no flip-flopping)
        & $change 'public'; $e.dnsSet = 'public'
        "Network: the router's DNS answered slowly ($($e.dns) ms vs $($e.dnsBest) ms) - switched this connection to 1.1.1.1 / 1.0.0.1 (websites and game logins start faster)"
    }
    else { "Reminder: the DNS server ($($e.dnsServer)) answers slowly - $($e.dns) ms vs $($e.dnsBest) ms for a public one; websites and game logins start slower. To switch: Settings > Network & internet > (your connection) > DNS server assignment > Edit > 1.1.1.1 and 1.0.0.1" }
}
if ($e.dnsSet) { $h[-1] | Add-Member dnsSet $e.dnsSet -Force; try { ConvertTo-Json -InputObject @($h) -Depth 3 | Set-Content "$History.tmp" -Encoding UTF8; Move-Item "$History.tmp" $History -Force } catch {} }
# the internet ping this week vs the month before
$usual = Median ($h | Where-Object { $_.ping -and [datetime]$_.date -lt $Now.AddDays(-7) -and [datetime]$_.date -gt $Now.AddDays(-45) } | ForEach-Object { [double]$_.ping })
$week = Median ($h | Where-Object { $_.ping -and [datetime]$_.date -ge $Now.AddDays(-7) } | ForEach-Object { [double]$_.ping })
if ($usual -and $week -and @($h | Where-Object { $_.ping -and [datetime]$_.date -ge $Now.AddDays(-7) }).Count -ge 3 -and $week -ge $usual * 1.5 -and $week -ge $usual + 20) {
    "Reminder: the internet ping is higher this week - $week ms, usually $usual ms (the provider, or something on the network using it)"
}
