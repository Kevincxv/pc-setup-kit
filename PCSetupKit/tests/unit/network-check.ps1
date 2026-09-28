# network-check.ps1: ping / loss / jitter / DNS over time, said only when it repeats, and a slow router DNS switched
# where that's safe. Made-up measurements; the DNS change is a recorder, never the real adapter.
. "$PSScriptRoot\..\lib.ps1"
$nc = "$Src\network-check.ps1"
if (-not (Test-Path $nc)) { Skip 'network-check' 'not installed here'; Finish }
$now = Get-Date
$hf = "$Work\net-history.json"
$global:dnsCalls = @()
$rec = { param($to) $global:dnsCalls += $to }
function Good { @{ gwPing = 1; gwJitter = 1; gwLoss = 0; ping = 9; jitter = 2; loss = 0; wifi = $false; dnsServer = '192.168.1.1'; dnsIsRouter = $true; dns = 14; dnsBest = 12; ifIndex = 7 } }
function NC([hashtable]$m, [datetime]$at = $now) { @(& $nc -History $hf -Now $at -Measured $m -SetDns $rec) }
function Fresh { Clear-Path $hf; $global:dnsCalls = @() }

Section 'quiet when fine, and one bad check is not news'
Fresh; $o = NC (Good)
Check 'a good network: nothing said' (-not $o) ($o -join ' / ')
$b = Good; $b.gwLoss = 8; $o = NC $b
Check 'one check losing packets: not said yet' (-not $o) ($o -join ' / ')
$o = NC $b
Check '2 of the last 3: said, pointing at the cable/router port (wired)' ("$o" -match '^Reminder: the home network loses packets to the router \(8% now\) - check the network cable or router port') ($o -join ' / ')
Fresh; $b = Good; $b.loss = 5; $b.wifi = $true; [void](NC $b); $o = NC $b
Check 'loss only past the router: the provider/modem' ("$o" -match 'internet connection loses packets \(5% to 1\.1\.1\.1, the home network is fine\)') ($o -join ' / ')
Fresh; $b = Good; $b.jitter = 25; $b.gwJitter = 14; $b.wifi = $true; [void](NC $b); $o = NC $b
Check 'unsteady pings, already to the router on Wi-Fi: says so' ("$o" -match 'unsteady - pings vary by 25 ms.+already to the router: Wi-Fi signal') ($o -join ' / ')

Section 'slow DNS'
Fresh; $s = Good; $s.dns = 120; $s.dnsBest = 15; [void](NC $s); $o = NC $s
Check "wired, the router's DNS: switched to 1.1.1.1 (not just reported)" ((($global:dnsCalls -join ',') -eq 'public') -and "$o" -match "^Network: the router's DNS answered slowly \(120 ms vs 15 ms\) - switched") ($o -join ' / ')
$p = Good; $p.dnsServer = '1.1.1.1'; $p.dnsIsRouter = $false; $p.dns = 10; $o = NC $p
Check '... working afterwards: nothing more' (-not $o -and ($global:dnsCalls -join ',') -eq 'public') ($o -join ' / ')
$p.dns = $null; $o = NC $p
Check '... 1.1.1.1 stops answering on this network: back to automatic' (($global:dnsCalls -join ',') -eq 'public,reset' -and "$o" -match 'set back to automatic') ($o -join ' / ')
$o = NC $s; $o = NC $s
Check '... and never switched again (no flip-flopping): a reminder instead' (($global:dnsCalls -join ',') -eq 'public,reset' -and "$o" -match '^Reminder: the DNS server \(192\.168\.1\.1\) answers slowly') ($o -join ' / ')
Fresh; $w = $s.Clone(); $w.wifi = $true; [void](NC $w); $o = NC $w
Check 'on Wi-Fi (a hotel sign-in page needs its DNS): only a reminder' (-not $global:dnsCalls -and "$o" -match '^Reminder: the DNS server') ($o -join ' / ')
Fresh; $ph = $s.Clone(); $ph.dnsServer = '192.168.1.5'; $ph.dnsIsRouter = $false; [void](NC $ph); $o = NC $ph
Check 'a DNS that is not the router (a Pi-hole, a company DNS): left alone' (-not $global:dnsCalls -and "$o" -match '^Reminder: the DNS server \(192\.168\.1\.5\)') ($o -join ' / ')

Section 'ping over the weeks'
Fresh
for ($i = 40; $i -ge 8; $i--) { [void](NC (Good) $now.AddDays(-$i)) }
$hi = Good; $hi.ping = 45
for ($i = 3; $i -ge 1; $i--) { $o = NC $hi $now.AddDays(-$i).AddHours(1) }
Check 'a week of much higher ping than usual: said' ("$o" -match 'internet ping is higher this week - 45 ms, usually 9 ms') ($o -join ' / ')
$j = Get-Content $hf -Raw | ConvertFrom-Json
Check 'the history is kept (one entry per check)' (@($j | ForEach-Object { $_ }).Count -eq 36) "$(@($j | ForEach-Object { $_ }).Count)"
Finish
