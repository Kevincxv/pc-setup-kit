# Builds a made-up home folder for screenshots and the layout audit: what a PC that has used Messiah for a few weeks
# looks like - a maintenance report and its schedule, a few weeks of history, power-offs and a blue screen, games on two
# drives, Call of Duty with a setting being tried both ways. Nothing is read from this PC; every date is relative to now, so This week and Next stay right whenever it's run.
#   & tools\app\demo-profile.ps1 [-Path <folder>] [-Full]   (default %TEMP%\messiah-demo-1026, emptied first)
#   -Full: C: nearly full (120 GB free), so Storage shows the Drives warning and Call of Duty's 'Moving it ... frees' note
#   $env:USERPROFILE = <folder>; MessiahApp.exe --audit <dir>
param([string]$Path = "$env:TEMP\messiah-demo-1026", [switch]$Full)
$ErrorActionPreference = 'Stop'
$us = [Globalization.CultureInfo]'en-US'
$now = Get-Date
$C = Join-Path $Path '.claude'
foreach ($d in '.claude', '.claude\maint-history', 'Documents') {
    $p = Join-Path $Path $d
    if (Test-Path $p) { Get-ChildItem $p -File -Force | Remove-Item -Force } else { New-Item $p -ItemType Directory -Force | Out-Null }
}
function Put([string]$Name, $Text) { [IO.File]::WriteAllText((Join-Path $C $Name), (($Text | Out-String).TrimEnd() + "`r`n"), (New-Object Text.UTF8Encoding $false)) }
function Json($o) { $o | ConvertTo-Json -Depth 6 }
function Iso([datetime]$t) { $t.ToString('s') }
function Checked([datetime]$t, [int]$s = 20) { "Checked $($t.ToString('M/d/yyyy h:mm tt', $us)) in ${s}s" }

Put 'kit-options.txt' 'claude=off'
Put 'gsync.txt' '1'   # (G-SYNC on, as nvidia-settings.ps1 writes it: a capped game's card names Messiah's cap)
# The last driver / BIOS read (the app reads it first, so Tools' Graphics driver card is drawn - not this PC's own board)
$bUrl = 'https://www.asus.com/supportonly/ROG%20STRIX%20B650E-I%20GAMING%20WIFI/helpdesk_bios/'
Put 'hardware.json' (Json ([ordered]@{ gpu = [ordered]@{ name = 'NVIDIA GeForce RTX 4080 SUPER'; version = '32.0.15.6094'; date = $now.AddDays(-12).ToString('yyyy-MM-dd') }
    bios = [ordered]@{ maker = 'ASUSTeK COMPUTER INC.'; model = 'ROG STRIX B650E-I GAMING WIFI'; version = '3201'; date = $now.AddDays(-200).ToString('yyyy-MM-dd'); url = $bUrl
        steps = "1. Open $bUrl and download the newest BIOS (newer than 3201). 2. Unzip it onto a USB stick (FAT32). 3. Restart, press Del (or F2) while the logo shows, press F7 for Advanced Mode, then Tool > ASUS EZ Flash 3 Utility, and pick the file. 4. Never turn the PC off while it updates (a few minutes; it restarts by itself). 5. Afterwards the BIOS settings are back to defaults: turn EXPO/XMP (the RAM speed) back on." } }))

# A few weeks of maintenance (one report over 7 days old, so This week is a full week, not the first one)
$hist = @(
    @(20, 'Created a monthly restore point', 'Removed temporary files (800 MB)'),
    @(5, 'PC Setup Kit updated v2.13 -> v2.14'),
    @(3, 'Tweaks: Start menu recommendations re-applied (Windows Update had changed it)', 'Removed 3 old crash dumps (1.2 GB)'),
    @(1, 'NVIDIA: updating 560.94 -> 566.03...', 'NVIDIA: installed 566.03', 'NVIDIA: 566.03 installed; no NVIDIA app recommendation file to compare against', 'Updated app: Microsoft.WindowsAppRuntime.1.8'))
foreach ($h in $hist) {
    $t = $now.Date.AddDays(-$h[0]).AddHours(8)
    [IO.File]::WriteAllLines("$C\maint-history\report-$($t.ToString('yyyyMMdd-HHmmss')).txt", [string[]](@(Checked $t) + $h[1..($h.Count - 1)]))
}
$last = $now.AddMinutes(-40)
$apps = 'Updated app: Valve.Steam', 'Updated app: Discord.Discord', 'Updated app: Microsoft.WindowsTerminal', 'Updated app: OpenJS.NodeJS.LTS'
[IO.File]::WriteAllLines("$C\maint-history\report-$($last.ToString('yyyyMMdd-HHmmss')).txt", [string[]](@(Checked $last) + $apps))

# The last check's report and the schedule it keeps (claude-bg-maint.ps1 writes both with the history)
Put 'maint-report.txt' @"
$(Checked $last 64)
[Drivers]
NVIDIA: 560.94 is up to date
Other drivers: all up to date (Windows Update)
[PC health]
Crashes: none since last check
Tweaks: all still applied
Apps: 2 update(s) available (7-Zip, Google Chrome) - the weekly app update installs them
Game saves: 1 of 4 games had new saves - backed up to Documents\Game Saves (Messiah) (3 MB in all)
[Periodic]
Backup: settings saved (look, game settings, the kit's memory) to Documents\PC Setup Kit Backup
Next: App updates $($now.AddDays(1).ToString('MMM d', $us)), cleanup $($now.AddDays(12).ToString('MMM d', $us))
"@
$set = (Get-Date).AddDays(-36).ToString('o')
# (10/27: Checks' Self-test row with a result - the next date first, like the other scheduled rows)
Put 'self-test.json' (Json ([ordered]@{ ok = $true; result = '1652 passed, 0 failed'; failed = @(); date = $now.AddDays(-3).ToString('o'); reason = 'weekly'; seconds = 80 }))
Put 'maint-state.json' (Json ([ordered]@{
    'weekly-apps' = $now.AddDays(-6).ToString('o'); 'monthly-cleanup' = $now.AddDays(-18).ToString('o'); 'trim' = $now.AddDays(-4).ToString('o')
    'claude-quarterly' = $set; 'claude-halfyear' = $set; 'claude-yearly' = $set; 'claude-warnings' = $now.AddDays(-3).ToString('o')
    'claude-handled-report' = (Checked $last 64)
}))

# The tweak guard's last look: every optimization still applied (Optimizations' rows say "On", not "Not checked")
$keys = [ordered]@{}
foreach ($k in 'network-defaults=1;windowed-games=1;notifications-off=1;game-recording=3;memory-integrity=2;feature-delay=3;transparency=1;restart-block=4;end-task=1;#Registry backup=1;#Scheduled tasks=0;sticky-keys=3;onedrive=1;folder-types=1;#Gaming / performance=11;mouse-acceleration=3;edge=16;start-menu=5;telemetry=57' -split ';') {
    $id, $n = $k -split '=(?=\d+$)'; $keys[$id] = [ordered]@{ blocked = 0; fixed = @(); same = [int]$n }
}
Put 'tweak-status.json' (Json ([ordered]@{ at = $last.ToString('o'); preview = $false; dualX3D = $true; optIn = @('edge-remove', 'notifications-off', 'sysmain-off'); on = @('notifications-off'); keys = $keys }))

# Power-offs nobody answered (one over 30 days), one blue screen, one the owner answered; a driver change before them
$ev = foreach ($e in @(@(250, 'off', ''), @(100, 'off', ''), @(80, 'off', ''), @(20, 'bsod', '0x109'), @(5, 'off', '', 'me'))) {
    $at = Iso $now.Date.AddDays(-$e[0]).AddHours(3)
    [ordered]@{ answer = $(if ($e.Count -gt 3) { $e[3] } else { '' }); key = $at; kind = $e[1]; code = $e[2]; at = $at }
}
Put 'power-log.json' (Json ([ordered]@{ events = @($ev); changes = @([ordered]@{ from = '617.42'; to = '618.10'; what = 'Graphics driver'; at = (Iso $now.Date.AddDays(-30).AddHours(3)) }) }))

# Games on two drives, a leftover folder, one game installed twice
function Game($id, $name, $store, $drive, $gb, $path, $mov) { [ordered]@{ id = $id; name = $name; store = $store; drive = $drive; sizeGB = $gb; path = $path; movable = $mov } }
Put 'storage.json' (Json ([ordered]@{
    date = $now.AddHours(-2).ToString('o')
    games = @(
        (Game '1938090' 'Call of Duty' 'Steam' 'C' 245 'C:\Steam\steamapps\common\Call of Duty HQ' $true),
        (Game 'path:C:\Games\NBA 2K\NBA 2K23' 'NBA 2K23' 'Folder' 'C' 132.3 'C:\Games\NBA 2K\NBA 2K23' $false),
        (Game '1919590' 'NBA 2K23' 'Steam' 'C' 118 'C:\Program Files (x86)\Steam\steamapps\common\NBA 2K23' $true),   # (both copies are games, like storage.ps1's)
        (Game 'epic:r6' "Tom Clancy's Rainbow Six Siege - Operation Deadly Omen Edition" 'Epic' 'D' 88 'D:\Epic\R6' $false),
        (Game '1172470' 'Apex Legends' 'Steam' 'D' 0.8 'D:\SteamLibrary\steamapps\common\Apex Legends' $true))
    leftovers = [ordered]@{ kind = 'folder'; name = 'Halo Infinite - no installed game uses this folder'; path = 'D:\SteamLibrary\steamapps\common\Halo Infinite'; sizeGB = 4.2; safe = $false }
    drives = @([ordered]@{ label = ''; ssd = $true; sizeGB = 1862; freeGB = $(if ($Full) { 120 } else { 997 }); system = $true; letter = 'C' }, [ordered]@{ label = 'Games'; ssd = $true; sizeGB = 2000; freeGB = 1500; system = $false; letter = 'D' })
    duplicates = @([ordered]@{ name = 'NBA 2K23'; places = @('Steam: C:\Program Files (x86)\Steam\steamapps\common\NBA 2K23 (118 GB)', 'Folder: C:\Games\NBA 2K\NBA 2K23 (132 GB)'); sizeGB = 118 })
}))

# Call of Duty's last two days, a minute per row: the video memory budget tried both ways since yesterday (game-tune.ps1's
# A/B - Performance's "Trying now" card, 6 of 8 minutes measured), Reflex Boost already decided
$perf = @(foreach ($i in 0..13) {
    $r = [ordered]@{ date = $now.AddMinutes(-30).AddHours(-(13 - $i) * 4).ToString('o'); game = 'cod'; fps = 196 + ($i % 5); low1 = 148 + ($i % 4); frames = 11800; stutters = $i % 3; driver = '560.94'; gpuTemp = 68 + ($i % 6); gpuFan = 55; gpuPower = 290; cpuLimit = 100; cpuPerf = 112 }
    if ($i -ge 8) { $r.tune = 'vram:' + $(if ($i -lt 11) { 'a' } else { 'b' }) }; $r })
$perf[-1].gpuBusy = 72; $perf[-1].latency = 11.4; $perf[-1].presentMode = 'Hardware: Independent Flip'
# and Apex a few days ago (recorded under its program's name, like game-perf.ps1 does), so Performance has two game cards
$perf = @(foreach ($i in 0..3) { [ordered]@{ date = $now.AddDays(-3).AddMinutes(-25 * (3 - $i)).ToString('o'); game = 'r5apex_dx12'; fps = 231 + $i; low1 = 162 + ($i % 2); frames = 13900; stutters = 1; driver = '560.94'; gpuTemp = 64 + $i; gpuUse = 81; gpuFan = 50; gpuPower = 250; cpuLimit = 100; cpuPerf = 110 } }) + $perf
# and one game for each kind of Game check-up verdict (10/28), all before this week: NBA 2K20 capped at 60, Cyberpunk held
# back by the graphics card, Rocket League by the processor, Fortnite with more hitches than usual (Call of Duty and Apex: smooth)
function PerfRow($days, $game, $title, $fps, $low, $st, $busy) { [ordered]@{ date = $now.AddDays(-$days).ToString('o'); game = $game; title = $title; fps = $fps; low1 = $low; frames = [int]($fps * 60); stutters = $st; driver = '560.94'; gpuTemp = 66; gpuBusy = $busy; cpuLimit = 100; cpuPerf = 110 } }
$cap = PerfRow 9 'nba2k20' 'NBA 2K20' 59.9 52 1 24; $cap.perSec = @(1..20 | ForEach-Object { 60 - ($_ % 2) })
$perf = @((PerfRow 20 'FortniteClient-Win64-Shipping' 'Fortnite' 205 150 1 80), (PerfRow 18 'FortniteClient-Win64-Shipping' 'Fortnite' 210 152 0 80),
    (PerfRow 16 'FortniteClient-Win64-Shipping' 'Fortnite' 186 96 17 82),
    (PerfRow 14 'RocketLeague' 'Rocket League' 172 121 0 41), (PerfRow 13 'RocketLeague' 'Rocket League' 168 119 1 44),
    (PerfRow 12 'Cyberpunk2077' 'Cyberpunk 2077' 88 64 1 98), (PerfRow 11 'Cyberpunk2077' 'Cyberpunk 2077' 91 66 2 98),
    (PerfRow 10 'nba2k20' 'NBA 2K20' 59.8 51 2 25), $cap) + $perf
# and Hunt 40 days ago (Earlier games): a game no list knows, named by the title game-perf.ps1 found (its folder's game)
$perf = @(foreach ($i in 0..1) { [ordered]@{ date = $now.AddDays(-40).AddMinutes(-25 * (1 - $i)).ToString('o'); game = 'HuntGame'; title = 'Hunt: Showdown 1896'; fps = 142 + $i; low1 = 97; frames = 8600; stutters = 3; driver = '560.94'; gpuTemp = 70; gpuUse = 93; cpuLimit = 100; cpuPerf = 108 } }) + $perf
Put 'perf-history.json' (ConvertTo-Json -InputObject $perf -Depth 4)
Put 'game-tune.json' (Json ([ordered]@{
    active = [ordered]@{ id = 'vram'; game = 'cod'; label = 'the video memory budget'; a = '0.850000'; b = '0.750000'; arm = 'b'; started = $now.AddDays(-1).ToString('o') }
    done = @([ordered]@{ id = 'reflex'; label = 'Reflex Boost'; a = 'Enabled + boost'; b = 'Enabled'; kept = 'Enabled'; why = 'faster'; at = $now.AddDays(-4).ToString('o'); aFps = 197; bFps = 201; aLow = 146; bLow = 158; aLatency = 12.5; bLatency = 10.9 })
}))
# Five weeks of the background check's health rows (Health > Trends' charts, Performance's idle temperatures): a check
# most days (the last one is the last check's), a restart every few days, C: filling up slowly to storage.json's free space (and 60 GB at once 12 days ago - a game installed: the chart's mark); and its idle ping each time
$freeC = $(if ($Full) { 120 } else { 997 })
$days = @(35, 34, 32, 31, 29, 28, 26, 24, 23, 21, 20, 18, 17, 15, 14, 12, 10, 9, 7, 6, 4, 3, 2, 1, 0)
$health = @(foreach ($n in 0..($days.Count - 1)) {
    $d = $days[$n]; $bd = $d - ($d % 4) + 4; $boot = $now.Date.AddDays(-$bd).AddHours(9)
    [ordered]@{ date = $(if ($d) { $now.Date.AddDays(-$d).AddHours(12) } else { $last }).ToString('o'); bootAt = $boot.ToString('o'); boot = 18.5 + (($bd / 4) % 3) * 1.4
        freeGB = $freeC + [math]::Round($d * 1.3 + ($n % 3) * 2.1, 1) + $(if ($d -gt 12) { 60 } else { 0 }); sizeGB = 1862; ssdWear = 1; ssdTemp = 46 + ($n % 5); ssdTempMax = 71
        gpuIdle = 41 + ($n % 4); gpuIdleFan = 0; cpuIdle = 43 + (($n + 2) % 5) } })
$health[-1].freeGB = $freeC
Put 'health-history.json' (ConvertTo-Json -InputObject $health -Depth 3)
$net = @(foreach ($n in 0..($days.Count - 1)) { [ordered]@{ date = $(if ($days[$n]) { $now.Date.AddDays(-$days[$n]).AddHours(12) } else { $last }).AddMinutes(1).ToString('o'); gwPing = 1 + ($n % 2); gwJitter = 0.6; gwLoss = 0; ping = 8 + ($n % 4); jitter = 1.5; loss = 0; wifi = $false; dnsServer = '1.1.1.1'; dnsIsRouter = $false; dns = 13 + ($n % 3) } })
Put 'net-history.json' (ConvertTo-Json -InputObject $net -Depth 3)
# the weekly settings backup the report mentions (Settings > General's backup card: 'Last backup ..., in Documents\...')
$bk = Join-Path $Path 'Documents\PC Setup Kit Backup'
if (Test-Path $bk) { Get-ChildItem $bk -File -Force | Remove-Item -Force } else { New-Item $bk -ItemType Directory -Force | Out-Null }
$zip = Join-Path $bk "DEMO-PC-$($now.AddDays(-2).ToString('yyyy-MM-dd')).zip"
[IO.File]::WriteAllBytes($zip, [byte[]](@(80, 75, 5, 6) + @(0) * 18))   # an empty zip
(Get-Item $zip).LastWriteTime = $now.Date.AddDays(-2).AddHours(12)
"Demo profile: $Path"
