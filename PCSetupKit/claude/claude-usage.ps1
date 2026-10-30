# Where the Claude usage goes (10/26, the owner: "a token usage awareness feature which monitors the tasks or things that
# take up the most tokens"). Claude Code writes every conversation to .claude\projects\<project>\<session>.jsonl, each
# reply with its token counts; this reads the last 14 days (each file once - cached by its size and time) and writes
# claude-usage.json for the app (Health > Checks, "Claude usage") and the improvement loop:
#   kinds     this week's usage by what it was for: your chats in the app, improvement rounds, background maintenance,
#             self-improvement, tests, your other sessions (a terminal)
#   sessions  the heaviest conversations of the week; steps: the heaviest single steps (a file read, a command's output) -
#             what something adds stays in the conversation and is read again with every reply after it, so a step costs
#             its size x the replies that followed (a big file read early in a long chat costs the most)
#   current   the session's and the week's % used and when they reset (Claude Code's /usage - no tokens)
# Weights (to compare like the plan does, roughly Anthropic's price ratios): input 1, cache write 1.25, cache read 0.1,
# output 5 - "units". Shares are of this PC's usage; the % of the plan comes from /usage.
# -Projects / -Out / -Now / -NoUsage: tests.
param([string]$Projects = "$PSScriptRoot\projects", [string]$Out = "$PSScriptRoot\claude-usage.json", [datetime]$Now = (Get-Date), [switch]$NoUsage, [string]$Dir = $PSScriptRoot)
$ErrorActionPreference = 'SilentlyContinue'
$cacheFile = "$Dir\claude-usage-cache.json"
$cache = @{}; try { (Get-Content $cacheFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $cache[$_.Name] = $_.Value } } catch { }
$since = $Now.AddDays(-14)
$rxId = [regex]'"id":"(msg_[^"]+)"'; $rxUse = [regex]'"usage":\{"input_tokens":(\d+),"cache_creation_input_tokens":(\d+),"cache_read_input_tokens":(\d+),"output_tokens":(\d+)'
$rxTs = [regex]'"timestamp":"([^"]+)"'; $rxTool = [regex]'"type":"tool_use","id":"(toolu_[^"]+)","name":"([^"]+)","input":\{'
$rxRes = [regex]'"tool_use_id":"(toolu_[^"]+)","type":"tool_result"'
function Field([string]$l, [string]$k) { $m = [regex]::Match($l, "`"$k`":`"((?:[^`"\\]|\\.){0,160})"); if ($m.Success) { ($m.Groups[1].Value -replace '\\[nrt]', ' ' -replace '\\\\', '\' -replace '\\"', '"' -replace '\s+', ' ').Trim() } }

# --- each conversation file: its replies (counted once per message), its title, its steps ---
function Read-Session([IO.FileInfo]$f) {
    $msgs = @{}; $order = New-Object Collections.Generic.List[string]; $tools = @{}; $results = New-Object Collections.Generic.List[object]
    $title = $null; $custom = $null; $ai = $null; $lastPrompt = $null; $first = $null; $last = $null; $daily = @{}
    $sr = New-Object IO.StreamReader($f.FullName, [Text.Encoding]::UTF8)
    try {
        while ($null -ne ($l = $sr.ReadLine())) {
            # (the title Claude Code keeps rewriting near the end: the last one - the given name, else its own, else the last prompt)
            if ($l.Contains('"customTitle"')) { $t = Field $l 'customTitle'; if ($t) { $custom = $t } }
            if ($l.Contains('"aiTitle"')) { $t = Field $l 'aiTitle'; if ($t) { $ai = $t } }
            if ($l.Contains('"lastPrompt"')) { $t = Field $l 'lastPrompt'; if ($t) { $lastPrompt = $t } }
            if ($l.Contains('"type":"assistant"')) {
                $mi = $rxId.Match($l); $mu = $rxUse.Match($l); $ts = $rxTs.Match($l)
                if ($mi.Success -and $mu.Success) {
                    $id = $mi.Groups[1].Value
                    if (-not $msgs.ContainsKey($id)) { $order.Add($id) }
                    $u = [double]$mu.Groups[1].Value + 1.25 * [double]$mu.Groups[2].Value + 0.1 * [double]$mu.Groups[3].Value + 5 * [double]$mu.Groups[4].Value
                    $day = if ($ts.Success) { ([datetime]$ts.Groups[1].Value).ToLocalTime().ToString('yyyy-MM-dd') } else { $f.LastWriteTime.ToString('yyyy-MM-dd') }
                    $msgs[$id] = @{ u = $u; day = $day }   # (a reply written in parts repeats its usage: the last one counts)
                    if ($ts.Success) { $tt = ([datetime]$ts.Groups[1].Value).ToLocalTime(); if (-not $first) { $first = $tt }; $last = $tt }
                }
                foreach ($m in $rxTool.Matches($l)) {
                    $what = Field $l 'description'; if (-not $what) { $what = Field $l 'file_path'; if ($what) { $what = Split-Path $what -Leaf } }; if (-not $what) { $what = Field $l 'pattern' }; if (-not $what) { $what = Field $l 'command' }
                    $tools[$m.Groups[1].Value] = @{ name = $m.Groups[2].Value; what = "$what" }
                }
            }
            elseif ($l.Contains('"tool_result"')) {
                # (a picture - a screenshot read - is sent scaled down, ~1,600 tokens whatever its file size; text ~4 characters a token)
                $mr = $rxRes.Match($l); if ($mr.Success) { $results.Add(@{ id = $mr.Groups[1].Value; chars = $(if ($l.Contains('"type":"image"')) { 6400 } else { $l.Length }); at = $order.Count }) }
            }
        }
    }
    finally { $sr.Close() }
    $title = if ($custom) { $custom } elseif ($ai) { $ai } elseif ($lastPrompt) { if ($lastPrompt.Length -gt 70) { $lastPrompt.Substring(0, 67) + '...' } else { $lastPrompt } }
    foreach ($id in $order) { $d = $msgs[$id].day; $daily[$d] = [double]$daily[$d] + $msgs[$id].u }
    # a step: its result's size (~4 characters a token) written once, then read again with every reply after it
    $steps = @(foreach ($r in $results) {
            $tk = [Math]::Round($r.chars / 4); $after = [Math]::Max(0, $order.Count - $r.at)
            $t = $tools[$r.id]; if ($tk -lt 2000) { continue }
            [pscustomobject]@{ tool = "$($t.name)"; what = "$($t.what)"; tokens = $tk; units = [Math]::Round($tk * (1.25 + 0.1 * $after)) }
        }) | Sort-Object units -Descending | Select-Object -First 5
    [pscustomobject]@{ title = $title; first = $(if ($first) { $first.ToString('o') }); last = $(if ($last) { $last.ToString('o') }); replies = $order.Count
        units = [Math]::Round(($msgs.Values | ForEach-Object { $_.u } | Measure-Object -Sum).Sum); daily = $daily; steps = @($steps) }
}

# --- what each conversation was for ---
$improveIds = @{}; try { foreach ($r in (Get-Content "$Dir\improve-state.json" -Raw | ConvertFrom-Json).rounds) { if ($r.session) { $improveIds["$($r.session)"] = 1 } } } catch { }
$chatIds = @{}; foreach ($ev in Get-ChildItem "$Dir\chat\events.jsonl", "$Dir\chats\*\events.jsonl") { foreach ($m in [regex]::Matches([IO.File]::ReadAllText($ev.FullName), '"t":"session","text":"([0-9a-f-]{36})"')) { $chatIds[$m.Groups[1].Value] = 1 } }
function Kind([string]$id, [string]$title) {
    if ($improveIds[$id] -or $title -eq 'Improving Messiah') { return 'Improvement rounds' }
    if ($title -match '^Hidden maintenance \(improve\)') { return 'Self-improvement' }
    if ($title -match '^Hidden maintenance') { return 'Background maintenance' }
    if ($title -match '^(Login rehearsal|Smoke test)') { return 'Tests' }
    if ($chatIds[$id]) { return 'Your chats (the app)' }
    'Your other sessions'
}

$sessions = @(); $newCache = @{}
foreach ($f in Get-ChildItem $Projects -Recurse -Filter *.jsonl | Where-Object { $_.LastWriteTime -ge $since }) {
    $id = if ($f.BaseName -match '^[0-9a-f-]{36}$') { $f.BaseName } else { Split-Path (Split-Path $f.FullName) -Leaf }   # (a helper's own file: its parent conversation)
    $key = "$($f.FullName)|$($f.Length)|$($f.LastWriteTime.Ticks)"
    $s = if ($cache.ContainsKey($key)) { $cache[$key] } else { Read-Session $f }
    $newCache[$key] = $s
    $sessions += [pscustomobject]@{ id = $id; s = $s }
}
$newCache | ConvertTo-Json -Depth 6 -Compress | Set-Content $cacheFile -Encoding UTF8

# --- one entry per conversation (a helper's file joins its parent), its kind; the week's totals ---
$byId = @{}
foreach ($x in $sessions) {
    if (-not $byId[$x.id]) { $byId[$x.id] = [pscustomobject]@{ id = $x.id; title = $null; units = 0.0; week = 0.0; replies = 0; last = $null; steps = @(); daily = @{} } }
    $e = $byId[$x.id]; if ($x.s.title -and -not $e.title) { $e.title = $x.s.title }
    $e.units += [double]$x.s.units; $e.replies += [int]$x.s.replies; $e.steps += @($x.s.steps)
    if ($x.s.last -and (-not $e.last -or [datetime]$x.s.last -gt [datetime]$e.last)) { $e.last = $x.s.last }
    $pairs = if ($x.s.daily -is [hashtable]) { @($x.s.daily.GetEnumerator() | ForEach-Object { @($_.Key, $_.Value) }) } else { @($x.s.daily.PSObject.Properties | ForEach-Object { @($_.Name, $_.Value) }) }   # (just read: a table; from the cache: an object)
    for ($i = 0; $i + 1 -lt $pairs.Count; $i += 2) { $e.daily["$($pairs[$i])"] = [double]$e.daily["$($pairs[$i])"] + [double]$pairs[$i + 1] }
}
$weekFrom = $Now.Date.AddDays(-6).ToString('yyyy-MM-dd')
foreach ($e in $byId.Values) { $e.week = ($e.daily.GetEnumerator() | Where-Object { $_.Key -ge $weekFrom } | ForEach-Object { $_.Value } | Measure-Object -Sum).Sum; $e | Add-Member kind (Kind $e.id $e.title) -Force }
$total = ($byId.Values | Measure-Object week -Sum).Sum
$kinds = @($byId.Values | Group-Object kind | ForEach-Object { [pscustomobject]@{ kind = $_.Name; units = [Math]::Round(($_.Group | Measure-Object week -Sum).Sum); share = $(if ($total) { [Math]::Round(100 * ($_.Group | Measure-Object week -Sum).Sum / $total) } else { 0 }) } } | Where-Object units -gt 0 | Sort-Object units -Descending)
$top = @($byId.Values | Where-Object week -gt 0 | Sort-Object week -Descending | Select-Object -First 6 | ForEach-Object { [pscustomobject]@{ title = $(if ($_.title) { $_.title } else { 'Untitled' }); kind = $_.kind; share = [Math]::Round(100 * $_.week / [Math]::Max(1, $total)); replies = $_.replies; last = $_.last } })
$steps = @($byId.Values | Where-Object week -gt 0 | ForEach-Object { $t = $_.title; $_.steps | ForEach-Object { $_ | Add-Member session $(if ($t) { $t } else { 'Untitled' }) -Force -PassThru } } | Sort-Object units -Descending | Select-Object -First 8)
$days = @(foreach ($i in 13..0) { $d = $Now.Date.AddDays(-$i).ToString('yyyy-MM-dd'); [pscustomobject]@{ date = $d; units = [Math]::Round(($byId.Values | ForEach-Object { [double]$_.daily[$d] } | Measure-Object -Sum).Sum) } })
# the improvement rounds: what one costs on average (the loop uses it to start a round only when one fits)
$rounds = @($byId.Values | Where-Object { $_.kind -eq 'Improvement rounds' -and $_.units -gt 0 })
$current = $null
if (-not $NoUsage) {
    $claude = "$env:USERPROFILE\.local\bin\claude.exe"
    if (Test-Path $claude) { Push-Location $env:TEMP; try { $t = "$((& $claude -p '/usage' --output-format json 2>$null | Out-String | ConvertFrom-Json).result)" } catch { $t = '' } finally { Pop-Location }
        $sm = [regex]::Match($t, 'Current session:\s*(\d+)% used[^\r\n]*?resets\s+([^(\r\n]+)'); $wm = [regex]::Match($t, 'Current week \(all models\):\s*(\d+)% used[^\r\n]*?resets\s+([^(\r\n]+)')
        if ($sm.Success) { $current = [pscustomobject]@{ session = [int]$sm.Groups[1].Value; sessionResets = $sm.Groups[2].Value.Trim(); week = $(if ($wm.Success) { [int]$wm.Groups[1].Value }); weekResets = $(if ($wm.Success) { $wm.Groups[2].Value.Trim() }) } } }
}
# tips - only what the numbers point at
$tips = @()
$long = $top | Where-Object { $_.kind -eq 'Your chats (the app)' -and $_.share -ge 30 } | Select-Object -First 1
if ($long) { $tips += "One chat used $($long.share)% of the week ('$($long.title)') - every reply re-reads the whole conversation, so a New chat for a new topic costs much less." }
$bigRead = $steps | Where-Object { $_.tool -eq 'Read' -and $_.tokens -ge 15000 } | Select-Object -First 1
if ($bigRead) { $tips += "Reading whole large files is the heaviest kind of step ($($bigRead.what), ~$([Math]::Round($bigRead.tokens / 1000))k tokens) - Claude reads only the part it needs when it can." }
$imp = $kinds | Where-Object kind -eq 'Improvement rounds'
if ($imp -and $imp.share -ge 50) { $tips += "Improvement rounds were $($imp.share)% of the week - lower kit-options improveweek (now the cap they stop at) to keep more for yourself." }
[pscustomobject]@{ at = $Now.ToString('o'); current = $current; kinds = $kinds; sessions = $top; steps = @($steps | Select-Object tool, what, tokens, units, session); days = $days
    roundAvg = $(if ($rounds) { [Math]::Round(($rounds | Measure-Object units -Average).Average) }); tips = $tips; weekUnits = [Math]::Round($total) } | ConvertTo-Json -Depth 5 | Set-Content "$Out.tmp" -Encoding UTF8
Move-Item "$Out.tmp" $Out -Force
