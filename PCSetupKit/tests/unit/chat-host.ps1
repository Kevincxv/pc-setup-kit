# chat-host.ps1: the app's chat with Claude - messages from the app's inbox go to Claude, its answer, steps and the end of
# each turn come back as events, state.json says what it's doing. A stand-in Claude (PowerShell answering in Claude
# Code's stream-json) - no tokens, no other session touched (-ExeArgs).
. "$PSScriptRoot\..\lib.ps1"
$ch = "$Src\chat-host.ps1"
if (-not (Test-Path $ch)) { Skip 'chat-host' 'not installed here'; Finish }
$D = "$Work\chat"; New-Item "$D\inbox" -ItemType Directory -Force | Out-Null
# the stand-in: a tiny console program (like claude.exe) - reads stream-json user messages, replays each (like
# --replay-user-messages), answers it with a tool step and its result, streamed text, the whole message and a result;
# "crash" ends it mid-answer; "phone" also brings a message typed elsewhere (Remote Control)
$exe = "$Work\fake-claude.exe"
Add-Type -OutputType ConsoleApplication -OutputAssembly $exe -TypeDefinition @"
using System; using System.IO; using System.Text; using System.Text.RegularExpressions;
public static class P { public static int Main() {
  var o = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false)); o.AutoFlush = true;
  var i = new StreamReader(Console.OpenStandardInput(), new UTF8Encoding(false));
  o.WriteLine("{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"" + Guid.NewGuid() + "\"}");
  string l;
  while ((l = i.ReadLine()) != null) {
    if (l.Length > 0 && l[0] == '\uFEFF') return 9;   // a byte-order mark: the real Claude would choke too
    var m = Regex.Match(l, "\"content\":\"([^\"]*)\"");
    if (!l.Contains("\"type\":\"user\"") || !m.Success) continue;
    var q = m.Groups[1].Value;
    if (q == "crash") return 3;
    if (q.StartsWith("limit")) {   // the usage limit: the turn ends with Claude Code's message (a time, a date and time, or none)
      var said = q == "limit" ? "You've hit your session limit \u00b7 resets 3am (America/Los_Angeles)" : q == "limitdate" ? "You've hit your weekly limit \u00b7 resets Nov 2, 9:30am" : "Claude usage limit reached.";
      o.WriteLine("{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"" + q + "\"}}");
      o.WriteLine("{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":true,\"result\":\"" + said + "\"}");
      continue;
    }
    o.WriteLine("{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"" + q + "\"}}");   // --replay-user-messages
    if (q == "phone") o.WriteLine("{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"typed on the phone\"}]}}");
    o.WriteLine("{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"content\":\"ok\"}]}}");
    o.WriteLine("{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"PowerShell\",\"input\":{\"command\":\"Get-Date\",\"description\":\"Check the time\"}}]}}");
    o.WriteLine("{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"You \"}}}");
    o.WriteLine("{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"said it\"}}}");
    o.WriteLine("{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"You said: " + q + "\"}]}}");
    o.WriteLine("{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false}");
  }
  return 0; } }
"@
$fa = 'stand-in'
function Drop($obj, $n) { [IO.File]::WriteAllText("$D\inbox\$n.json", ($obj | ConvertTo-Json -Compress)) }
function Events { @(Get-Content "$D\events.jsonl" -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { $_ | ConvertFrom-Json }) }
function Run { & $ch -Dir $D -Exe $exe -ExeArgs $fa -Once }

Section 'a message and its answer'
Drop @{ text = 'hello' } '001'
Run
$e = Events
Check 'the message is shown as the owner''s' (@($e | Where-Object t -eq 'user')[0].text -eq 'hello') (($e | ForEach-Object { "$($_.t):$($_.text)" }) -join ' | ')
Check '... the step Claude takes, in words' (@($e | Where-Object t -eq 'tool').text -contains 'Running: Check the time') ''
Check '... the answer streams in, then comes whole' ((@($e | Where-Object t -eq 'delta').text -join '') -eq 'You said it' -and @($e | Where-Object t -eq 'text').text -contains 'You said: hello') ''
Check '... and the turn ends (idle)' (@($e)[-1].t -eq 'status' -and @($e)[-1].text -eq 'idle') ''
Check 'the inbox is emptied' (-not (Get-ChildItem "$D\inbox\*.json")) ''
$s = Get-Content "$D\state.json" -Raw | ConvertFrom-Json
Check 'state: not busy, the conversation recorded' (-not $s.busy -and $s.session -and (Get-Content "$D\session.txt") -eq $s.session) (Get-Content "$D\state.json" -Raw)

Section 'two messages, in order; a new conversation; Claude dying mid-answer'
Clear-Path "$D\events.jsonl"
Drop @{ text = 'one' } '002'; Drop @{ text = 'two' } '003'
Run
$t = @(Events | Where-Object t -eq 'text').text
Check 'both answered, in the order sent' (($t -join ',') -eq 'You said: one,You said: two') ($t -join ',')
Drop @{ cmd = 'new' } '004'
Run
Check 'new conversation: said, and the old one forgotten' ((@(Events)[-1].text -eq 'New conversation.') -and -not (Test-Path "$D\session.txt")) ''
Clear-Path "$D\events.jsonl"
Drop @{ text = 'crash' } '005'
Run
$x = @(Events | Where-Object t -eq 'error')
Check 'Claude stopping mid-answer: an error says so, and the chat is ready again' ($x.Count -eq 1 -and $x[0].text -match 'stopped unexpectedly' -and -not (Get-Content "$D\state.json" -Raw | ConvertFrom-Json).busy) (($x | ForEach-Object text) -join ' | ')
Drop @{ text = 'again' } '006'
Run
Check '... the next message starts Claude again and is answered' (@(Events | Where-Object t -eq 'text').text -contains 'You said: again') ''

Section 'messages typed on the phone (Remote Control); an earlier conversation'
Clear-Path "$D\events.jsonl"
Drop @{ text = 'phone' } '007'
Run
$u = @(Events | Where-Object t -eq 'user').text
Check 'the app''s own message shows once (its replay isn''t shown again), tool results never' (($u -join ',') -eq 'phone,typed on the phone') ($u -join ',')
Check '... one typed on the phone shows as the owner''s too' ($u -contains 'typed on the phone') ''
$g = [guid]::NewGuid().ToString()
Drop @{ cmd = 'open'; session = $g } '008'
Run
Check 'an earlier conversation: opened, said, and continued from now on' ((Get-Content "$D\session.txt") -eq $g -and @(Events | Where-Object t -eq 'status').text -contains 'Opened an earlier conversation.') ''
Drop @{ cmd = 'open'; session = 'not-an-id' } '009'
Run
Check '... a bad id is ignored' ((Get-Content "$D\session.txt") -eq $g) ''

Section 'editing the last message'
# (a made-up home, so its transcripts are the ones the host reads)
$home_ = "$Work\home"; $pj = "$home_\.claude\projects\C--WINDOWS-system32"; New-Item $pj -ItemType Directory -Force | Out-Null
$uh = $env:USERPROFILE
function RunAs { $env:USERPROFILE = $home_; try { Run } finally { $env:USERPROFILE = $uh } }
function Transcript($id, [string[]]$parents) {
    $ls = for ($i = 0; $i -lt $parents.Count; $i++) {
        @{ type = 'user'; uuid = "u$i"; parentUuid = $(if ($parents[$i]) { $parents[$i] } else { $null }); message = @{ role = 'user'; content = "question $i" } } | ConvertTo-Json -Compress -Depth 4
        @{ type = 'user'; uuid = "r$i"; parentUuid = "u$i"; message = @{ role = 'user'; content = @(@{ type = 'tool_result'; content = 'ok' }) } } | ConvertTo-Json -Compress -Depth 4
    }
    [IO.File]::WriteAllLines("$pj\$id.jsonl", [string[]]$ls)
}
$g1 = [guid]::NewGuid().ToString(); Transcript $g1 @('', 'a0'); Set-Content "$D\session.txt" $g1; Clear-Path "$D\events.jsonl"
Drop @{ cmd = 'edit'; text = 'question 1, better' } '010'
RunAs
$e = Events
Check 'a later message: the conversation goes back to just before it (said), the new words answered' (@($e | Where-Object t -eq 'status').text -contains 'Edited your last message.' -and @($e | Where-Object t -eq 'text').text -contains 'You said: question 1, better') (($e | ForEach-Object { "$($_.t):$($_.text)" }) -join ' | ')
$g2 = [guid]::NewGuid().ToString(); Transcript $g2 @(''); Set-Content "$D\session.txt" $g2; Clear-Path "$D\events.jsonl"
Drop @{ cmd = 'edit'; text = 'first, better' } '011'
RunAs
Check 'the first message: a fresh start (said), answered' (@(Events | Where-Object t -eq 'status').text -contains 'Edited your first message - a fresh start.' -and @(Events | Where-Object t -eq 'text').text -contains 'You said: first, better') ''
Set-Content "$D\session.txt" ([guid]::NewGuid().ToString()); Clear-Path "$D\events.jsonl"
Drop @{ cmd = 'edit'; text = 'no transcript' } '012'
RunAs
Check 'no transcript to go back in: sent as a new message (said)' (@(Events | Where-Object t -eq 'status').text -contains 'Edited your last message (sent as a new one).' -and @(Events | Where-Object t -eq 'text').text -contains 'You said: no transcript') ''

Section 'the chat''s speed (the app''s picker)'
Remove-Item "$D\mode.txt" -ErrorAction SilentlyContinue; Clear-Path "$D\events.jsonl"
Drop @{ text = 'hi' } '020'; Run
Check 'nothing chosen: Opus at medium effort' ((Get-Content "$D\state.json" -Raw | ConvertFrom-Json).mode -eq 'opus/medium') (Get-Content "$D\state.json" -Raw)
Set-Content "$D\mode.txt" 'sonnet/low'; Drop @{ cmd = 'mode' } '021'; Run
Check 'a new speed: Claude starts again on it, said' ((Get-Content "$D\state.json" -Raw | ConvertFrom-Json).mode -eq 'sonnet/low' -and @(Events | Where-Object t -eq 'status').text -contains 'Now using Sonnet at low effort.') (Get-Content "$D\state.json" -Raw)
Set-Content "$D\mode.txt" 'gpt/ultra'; Drop @{ text = 'again' } '022'; Run
Check 'a speed that isn''t one: the default' ((Get-Content "$D\state.json" -Raw | ConvertFrom-Json).mode -eq 'opus/medium') ''
Remove-Item "$D\mode.txt"

Section 'the usage limit: Claude carries on by itself once it resets (10/25)'
function Wait { try { [datetime](Get-Content "$D\resume.json" -Raw | ConvertFrom-Json).until } catch { $null } }
Clear-Path "$D\events.jsonl"; Drop @{ text = 'limit' } '030'; Run
$at = (Get-Date).Date.AddHours(3).AddMinutes(1); if ($at -le (Get-Date).AddMinutes(1)) { $at = $at.AddDays(1) }
Check '"resets 3am": waits for the next 3 AM (a minute after), kept in resume.json, said in the chat and in state.json' ((Wait) -eq $at -and @(Events | Where-Object t -eq 'status').text -match '^Usage limit reached - Claude continues here by itself at 3:01 AM' -and (Get-Content "$D\state.json" -Raw | ConvertFrom-Json).waitUntil) "$(Wait) / $(@(Events | Where-Object t -eq 'status').text -join ' | ')"
Drop @{ text = 'limitdate' } '031'; Run
$nov = [datetime]"Nov 2 $((Get-Date).Year) 9:31am"; if ($nov -lt (Get-Date).AddDays(-1)) { $nov = $nov.AddYears(1) }
Check '"resets Nov 2, 9:30am" (the weekly limit): that day and time' ((Wait) -eq $nov) "$(Wait)"
Drop @{ text = 'limitnotime' } '032'; Run
$w = Wait
Check 'no time said: tried again in half an hour' ($w -and $w -gt (Get-Date).AddMinutes(28) -and $w -lt (Get-Date).AddMinutes(32)) "$w"
Drop @{ text = 'my own message' } '033'; Run
Check 'the owner writes meanwhile: their message goes, the automatic continue is dropped' (-not (Test-Path "$D\resume.json") -and @(Events | Where-Object t -eq 'text').text -contains 'You said: my own message') ''
Clear-Path "$D\events.jsonl"
[IO.File]::WriteAllText("$D\resume.json", (@{ until = (Get-Date).AddMinutes(-1).ToString('o') } | ConvertTo-Json -Compress)); Run
$e = Events
Check 'the reset has passed (even after a restart - read from resume.json): said, and the conversation continues where it left off' (@($e | Where-Object t -eq 'status').text -contains 'The usage limit has reset - continuing where it left off.' -and (@($e | Where-Object t -eq 'text').text -match '^You said: Continue where you left off') -and -not (Test-Path "$D\resume.json")) (($e | ForEach-Object { "$($_.t):$($_.text)" }) -join ' | ')
Check '... the continue isn''t shown as the owner''s own message' (-not (@($e | Where-Object t -eq 'user').text -match '^Continue where')) ''
Check 'other errors don''t wait for anything' (-not (Test-Path "$D\resume.json")) ''
Section 'a new version of the chat host takes over by itself (when Claude isn''t working)'
# (a copy of the host, running for real in the background - not -Once)
$D2 = "$Work\chat2"; New-Item "$D2\inbox" -ItemType Directory -Force | Out-Null; $ch2 = "$Work\host-copy.ps1"; Copy-Item $ch $ch2
function State2 { try { Get-Content "$D2\state.json" -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null } }
function WaitFor([scriptblock]$c, [int]$s = 20) { for ($i = 0; $i -lt $s * 4; $i++) { if (& $c) { return $true }; Start-Sleep -Milliseconds 250 }; $false }
Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$ch2`"", '-Dir', "`"$D2`"", '-Exe', "`"$exe`"", '-ExeArgs', $fa
$up = WaitFor { $s_ = State2; $s_ -and $s_.pid -and (Get-Process -Id $s_.pid -ErrorAction SilentlyContinue) }
$pid1 = (State2).pid
Add-Content $ch2 '# a newer version'; (Get-Item $ch2).LastWriteTime = (Get-Date).AddSeconds(-10)
$moved = WaitFor { $s_ = State2; $s_ -and $s_.pid -and $s_.pid -ne $pid1 -and (Get-Process -Id $s_.pid -ErrorAction SilentlyContinue) }
Check 'the file changed: a new host runs it, the old one has gone' ($up -and $moved -and -not (Get-Process -Id $pid1 -ErrorAction SilentlyContinue)) "up=$up moved=$moved"
[IO.File]::WriteAllText("$D2\inbox\1.json", (@{ text = 'still here' } | ConvertTo-Json -Compress))
$ans = WaitFor { @(Get-Content "$D2\events.jsonl" -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object t -eq 'text').text -contains 'You said: still here' }
Check '... and answers the next message' $ans ''
Add-Content $ch2 '}{ broken'; (Get-Item $ch2).LastWriteTime = (Get-Date).AddSeconds(-10); $pid2 = (State2).pid; Start-Sleep 3
Check 'a version that doesn''t parse is not taken: the running host stays' ((State2).pid -eq $pid2 -and (Get-Process -Id $pid2 -ErrorAction SilentlyContinue)) ''
[IO.File]::WriteAllText("$D2\inbox\2.json", (@{ cmd = 'quit' } | ConvertTo-Json -Compress)); [void](WaitFor { -not (Get-Process -Id $pid2 -ErrorAction SilentlyContinue) } 10)
Get-Process -Id $pid2 -ErrorAction SilentlyContinue | Stop-Process -Force
Finish
