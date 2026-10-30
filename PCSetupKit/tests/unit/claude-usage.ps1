# claude-usage.ps1: where the Claude usage goes - made-up conversation files (Claude Code's format); /usage is not asked.
. "$PSScriptRoot\..\lib.ps1"
$cu = "$Src\claude-usage.ps1"
if (-not (Test-Path $cu)) { Skip 'claude-usage' 'not installed here'; Finish }
$D = "$Work\cl"; $P = "$D\projects\C--WINDOWS-system32"; New-Item $P, "$D\chat" -ItemType Directory -Force | Out-Null
$now = Get-Date; $ts = $now.AddHours(-2).ToUniversalTime().ToString('o')
$chat = [guid]::NewGuid().ToString(); $round = [guid]::NewGuid().ToString()
function Reply([string]$id, [int]$in, [int]$cw, [int]$cr, [int]$out, [string]$content = '{"type":"text","text":"ok"}') {
    "{`"type`":`"assistant`",`"timestamp`":`"$ts`",`"message`":{`"id`":`"$id`",`"role`":`"assistant`",`"content`":[$content],`"usage`":{`"input_tokens`":$in,`"cache_creation_input_tokens`":$cw,`"cache_read_input_tokens`":$cr,`"output_tokens`":$out}}}"
}
# the chat: 4 replies (one written in two parts - counted once), a big file read early and a screenshot
$lines = @('{"type":"user","message":{"role":"user","content":"first question"},"timestamp":"' + $ts + '"}')
$lines += Reply 'msg_a' 10 1000 0 100 '{"type":"tool_use","id":"toolu_big","name":"Read","input":{"file_path":"C:\\\\code\\\\Big.cs"}}'
$lines += Reply 'msg_a' 10 1000 0 100 '{"type":"tool_use","id":"toolu_big","name":"Read","input":{"file_path":"C:\\\\code\\\\Big.cs"}}'
$lines += '{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_big","type":"tool_result","content":"' + ('x' * 80000) + '"}]}}'
$lines += Reply 'msg_b' 10 20000 1000 100 '{"type":"tool_use","id":"toolu_img","name":"Read","input":{"file_path":"C:\\\\shot.png"}}'
$lines += '{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_img","type":"tool_result","content":[{"type":"image","source":{"data":"' + ('A' * 900000) + '"}}]}]}}'
$lines += Reply 'msg_c' 10 2000 21000 100; $lines += Reply 'msg_d' 10 500 23000 100
$lines += '{"type":"ai-title","aiTitle":"Early title"}'; $lines += '{"type":"ai-title","aiTitle":"Fix the\r\nbig file"}'
$lines | Set-Content "$P\$chat.jsonl" -Encoding UTF8
"{`"t`":`"session`",`"text`":`"$chat`"}" | Set-Content "$D\chat\events.jsonl"
# an improvement round: small
@((Reply 'msg_r1' 5 3000 0 200), (Reply 'msg_r2' 5 500 3000 200), '{"type":"custom-title","customTitle":"Improving Messiah"}') | Set-Content "$P\$round.jsonl" -Encoding UTF8
# an old conversation (3 weeks): not counted
(Reply 'msg_old' 10 99999 0 999) | Set-Content "$P\old.jsonl" -Encoding UTF8; (Get-Item "$P\old.jsonl").LastWriteTime = $now.AddDays(-21)
function Run { & $cu -Projects "$D\projects" -Dir $D -Out "$D\claude-usage.json" -Now $now -NoUsage; Get-Content "$D\claude-usage.json" -Raw | ConvertFrom-Json }

Section 'this week by kind, the heaviest conversations and steps'
$j = Run
$k = @{}; foreach ($x in $j.kinds) { $k[$x.kind] = $x }
# chat units: msg_a 10+1250+0+500 = 1760 (once), msg_b 10+25000+100+500 = 25610, msg_c 10+2500+2100+500 = 5110, msg_d 10+625+2300+500 = 3435 -> 35915; round: 5+3750+0+1000 + 5+625+300+1000 = 6685
Check 'a reply written in two parts counts once (the weights: input 1, cache write 1.25, cache read 0.1, output 5)' ($k['Your chats (the app)'].units -eq 35915 -and $k['Improvement rounds'].units -eq 6685) "$($k['Your chats (the app)'].units) / $($k['Improvement rounds'].units)"
Check '... the app''s chat and the improvement round told apart, shares of the week' ($k['Your chats (the app)'].share -eq 84 -and $k['Improvement rounds'].share -eq 16 -and @($j.kinds).Count -eq 2) (($j.kinds | ForEach-Object { "$($_.kind) $($_.share)" }) -join ', ')
Check 'a conversation 3 weeks old: not counted' ($j.weekUnits -eq (35915 + 6685)) "$($j.weekUnits)"
$top = @($j.sessions)[0]
Check 'the heaviest conversation first, by its latest title (line breaks gone), with its replies' ($top.title -eq 'Fix the big file' -and $top.replies -eq 4 -and $top.share -eq 84) "$($top.title) / $($top.replies) / $($top.share)"
$s = @($j.steps)
Check 'the heaviest step: the big file read early (its size x the replies after it), named' ($s[0].what -eq 'Big.cs' -and $s[0].tool -eq 'Read' -and $s[0].tokens -ge 20000) (($s | ForEach-Object { "$($_.what) $($_.tokens)" }) -join ', ')
Check '... a screenshot counts as the ~1,600 tokens it costs, not its file size' (-not ($s | Where-Object { $_.what -eq 'shot.png' })) ''
Check 'a long chat that took most of the week: a tip to start a new chat' (@($j.tips) -match 'New chat' -and @($j.tips) -match 'Fix the big file') (@($j.tips) -join ' | ')
Section 'read again: from the cache (the same file is never parsed twice)'
$c = Get-Content "$D\claude-usage-cache.json" -Raw; $j2 = Run
Check 'the same numbers from the cache' ($j2.weekUnits -eq $j.weekUnits -and $c.Length -gt 100) ''
Finish
