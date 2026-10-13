# The app's chat with Claude (the owner's rule 10/10: everything in the app, no terminal). Runs hidden and elevated -
# the tray starts it when the app asks (app command 13) - and keeps one Claude Code conversation open in stream-json
# mode. The app and this host talk through files in .claude\chat (the main chat) or .claude\chats\<id> (more chats
# running side by side, 10/11 - the app's chat menu):
#   inbox\*.json   the app drops {"text": ...} (or {"cmd": "stop" | "new" | "start" | "quit" | "open", "session", "fork"},
#                  or {"cmd": "edit", "text": ...} - the last message, changed; or {"cmd": "mode"} - mode.txt changed);
#                  taken oldest first and deleted
#   events.jsonl   what happened, one JSON object per line: {t: user|delta|text|tool|status|error|session, text, at}
#   state.json     {pid, session, busy, step, since, remote, at} - rewritten as it changes; the app's "working on ..."
#                  line; remote = the Remote Control link (claude.ai/code and the phone app), like the terminal's
# The main chat's conversation: the one a hidden Messiah session (the tray's session from login) has open - taken over
# when it's idle, so a conversation a restart cut off continues right here - else the chat's last one (session.txt),
# else a new one. Started without -Dir (the tray), it also starts the hosts of other chats that have messages waiting.
# One host per chat (mutex). It leaves when its Claude has been idle for a day, or when told to.
# Claude starts right away (not at the first message) so Remote Control is on as soon as the chat is: what's typed
# on the phone shows here too (--replay-user-messages: every message comes back, the app's own are told apart).
# -Dir / -Exe / -Test: test overrides (-Test: a stand-in Claude, no tokens).
param([string]$Dir, [string]$Exe = "$env:USERPROFILE\.local\bin\claude.exe", [string]$ExeArgs, [int]$IdleHours = 24, [switch]$Once)
$ErrorActionPreference = 'SilentlyContinue'
$cl = "$env:USERPROFILE\.claude"; $proj = "$cl\projects\C--WINDOWS-system32"
$main = -not $Dir; if ($main) { $Dir = "$cl\chat" }
# the tray's start: chats waiting for their host get one (each runs elevated like this one)
if ($main -and -not $ExeArgs) {
    foreach ($d in @(Get-ChildItem "$cl\chats" -Directory -ErrorAction SilentlyContinue)) {
        if (-not (Get-ChildItem "$($d.FullName)\inbox\*.json" -ErrorAction SilentlyContinue)) { continue }
        $s = try { Get-Content "$($d.FullName)\state.json" -Raw | ConvertFrom-Json } catch { $null }
        if ($s -and $s.pid -and (Get-Process -Id $s.pid -ErrorAction SilentlyContinue)) { continue }
        Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Dir', "`"$($d.FullName)`""
    }
}
New-Item "$Dir\inbox" -ItemType Directory -Force | Out-Null
$mutex = New-Object Threading.Mutex($false, "Local\MessiahChatHost-$([Math]::Abs($Dir.ToLower().GetHashCode()))")
if (-not $mutex.WaitOne(0)) { return }
try { . "$cl\session-lib.ps1" } catch {}
$events = "$Dir\events.jsonl"; $stateFile = "$Dir\state.json"; $sessFile = "$Dir\session.txt"

function Add-Event([string]$t, [string]$text) {
    $line = [pscustomobject]@{ t = $t; text = $text; at = (Get-Date).ToString('o') } | ConvertTo-Json -Compress
    for ($i = 0; $i -lt 20; $i++) { try { [IO.File]::AppendAllText($events, "$line`n", (New-Object Text.UTF8Encoding $false)); break } catch { Start-Sleep -Milliseconds 50 } }
}
$script:st = @{ pid = $PID; session = $null; busy = $false; step = ''; since = $null; remote = $null }
function Save-State { $script:st.at = (Get-Date).ToString('o'); try { [IO.File]::WriteAllText("$stateFile.tmp", ([pscustomobject]$script:st | ConvertTo-Json -Compress)); Move-Item "$stateFile.tmp" $stateFile -Force } catch {} }
function Set-Busy([string]$step) { $script:st.busy = $true; $script:st.step = $step; if (-not $script:st.since) { $script:st.since = (Get-Date).ToString('o') }; Save-State }
# the events file stays short: the last 600 lines once it passes 1 MB
if ((Get-Item $events -ErrorAction SilentlyContinue).Length -gt 1MB) { $keep = @(Get-Content $events -Encoding UTF8 -Tail 600); [IO.File]::WriteAllLines($events, [string[]]$keep, (New-Object Text.UTF8Encoding $false)) }

# what a tool call is doing, in a few words (the same words the terminal shows)
function Get-Step($c) {
    $i = $c.input
    $what = if ($i.description) { $i.description } elseif ($i.file_path) { "$(Split-Path $i.file_path -Leaf)" } elseif ($i.pattern) { "searching for $($i.pattern)" } elseif ($i.url) { $i.url } elseif ($i.query) { $i.query } elseif ($i.prompt) { "$($i.prompt)".Substring(0, [Math]::Min(60, "$($i.prompt)".Length)) } else { '' }
    $verb = switch -Regex ($c.name) { '^(Bash|PowerShell)$' { 'Running' } '^Read$' { 'Reading' } '^(Edit|Write|MultiEdit)$' { 'Editing' } '^(Grep|Glob)$' { 'Searching' } '^Web' { 'Looking up' } '^(Agent|Task)$' { 'Helper' } default { $c.name } }
    "$verb$(if ($what) { ": $what" })"
}

# which conversation: a hidden Messiah session's (stopped first - two processes writing one conversation fork it - but
# only when it isn't in the middle of something, and only once it has a transcript to continue), else the chat's own,
# else a new one. (10/11: a login session that hadn't saved anything yet was "resumed" and every message failed.)
function Select-Session {
    if ($main) {
        foreach ($s in @(Get-AdminSessions | Where-Object { $_.SessionId -and -not $_.Shown })) {
            if (-not ($s.Transcript -and (Test-Path $s.Transcript))) { continue }   # nothing said yet: nothing to continue
            if (Test-MidTask $s.Transcript) { continue }   # working: leave it, take it over next time
            Get-CimInstance Win32_Process -Filter "ParentProcessId=$($s.LauncherPid)" | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
            Stop-Process -Id $s.LauncherPid -Force
            Add-Event 'status' 'Took over the conversation Messiah had open in the background.'
            return $s.SessionId
        }
    }
    $id = "$(Get-Content $sessFile -ErrorAction SilentlyContinue)".Trim()
    if ($id -and (Test-Path "$proj\$id.jsonl")) { return $id }
    $null
}

# Remote Control, as the terminal has it (settings.json "remoteControlAtStartup", on unless it says false)
function Test-RemoteWanted { if ($ExeArgs) { return $false }; $j = try { Get-Content "$cl\settings.json" -Raw | ConvertFrom-Json } catch { $null }; -not ($j -and $j.remoteControlAtStartup -eq $false) }
function Get-ChatName { $n = "$(Get-Content "$Dir\name.txt" -ErrorAction SilentlyContinue)".Trim(); if ($n) { $n } else { 'Messiah' } }

# the chat's speed (the app's picker; mode.txt "model/effort"): Opus at medium effort unless the owner chose otherwise
function Get-Mode {
    $m = "$(Get-Content "$Dir\mode.txt" -ErrorAction SilentlyContinue)".Trim() -split '/'
    if ($m.Count -eq 2 -and $m[0] -in 'opus', 'sonnet', 'haiku', 'fable' -and $m[1] -in 'low', 'medium', 'high', 'xhigh', 'max') { $m } else { 'opus', 'medium' }
}
$script:proc = $null; $script:fork = $false; $script:resumeAt = $null; $script:modeWait = $false; $script:sent = New-Object Collections.Generic.List[string]
function Start-Claude {
    $script:mode = Get-Mode; $script:st.mode = $script:mode -join '/'
    $id = if ($script:st.session) { $script:st.session } elseif (-not $ExeArgs) { Select-Session }   # (tests: never another session)
    $new = -not $id -or -not (Test-Path "$proj\$id.jsonl")   # an id with no transcript can't be resumed: start it fresh
    if (-not $id) { $id = [guid]::NewGuid().ToString() }
    $psi = New-Object Diagnostics.ProcessStartInfo $Exe
    $psi.Arguments = if ($ExeArgs) { $ExeArgs } else { "-p --input-format stream-json --output-format stream-json --verbose --include-partial-messages --replay-user-messages --dangerously-skip-permissions --model $($script:mode[0]) --effort $($script:mode[1]) --fallback-model sonnet $(if ($new) { "--session-id $id" } else { "--resume $id$(if ($script:resumeAt) { " --resume-session-at $script:resumeAt" })$(if ($script:fork) { ' --fork-session' })" })" }
    $script:fork = $false; $script:resumeAt = $null
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true   # (stderr not read: a full pipe would stall Claude)
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = "$env:SystemRoot\System32"
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $script:proc = [Diagnostics.Process]::Start($psi)
    # messages as UTF-8 without a byte-order mark (the console's own encoding would garble other languages and emoji)
    $script:in = New-Object IO.StreamWriter($script:proc.StandardInput.BaseStream, (New-Object Text.UTF8Encoding $false)); $script:in.AutoFlush = $true
    $script:exeTime = (Get-Item $Exe).LastWriteTime; $script:sent.Clear()
    $script:st.session = $id; $script:st.remote = $null; Set-Content $sessFile $id
    # the launcher's list too: resume-after-restart.ps1 and the login session find the chat's conversation
    $sl = "$cl\admin-sessions.txt"; @(@(Get-Content $sl -ErrorAction SilentlyContinue | Where-Object { $_ -and $_ -ne $id } | Select-Object -Last 19) + $id) | Set-Content $sl
    Add-Event 'session' $id; Save-State
    $script:reader = $script:proc.StandardOutput.ReadLineAsync()
    if (Test-RemoteWanted) { Send-Remote $true }
}
# Remote Control on: the same remote session as last time when it's the same conversation (remote.txt: "bridge id|
# conversation id"), else a new one
function Send-Remote([bool]$reattach) {
    $r = @{ subtype = 'remote_control'; enabled = $true; name = (Get-ChatName) }
    $old = "$(Get-Content "$Dir\remote.txt" -ErrorAction SilentlyContinue)".Trim() -split '\|'
    if ($reattach -and $old[0] -and $old[1] -eq $script:st.session) { $r.reattach_session_id = $old[0] }
    $script:rcId = "rc-$([guid]::NewGuid())"; $script:rcReattach = [bool]$r.reattach_session_id
    $script:in.Write((@{ type = 'control_request'; request_id = $script:rcId; request = $r } | ConvertTo-Json -Compress -Depth 4) + "`n")
}
function Stop-Claude { if ($script:proc -and -not $script:proc.HasExited) { try { $script:in.Close() } catch {}; if (-not $script:proc.WaitForExit(3000)) { $script:proc.Kill() } }; $script:proc = $null; $script:st.remote = $null }
function Send-Line([string]$json) {
    if (-not $script:proc -or $script:proc.HasExited) { Start-Claude }
    $script:in.Write("$json`n")
}

# a user message's words (string or text blocks); $null for tool results, reminders and other plumbing
function Get-UserText($j) {
    if ($j.parent_tool_use_id -or $j.isMeta -or $j.isSynthetic) { return $null }
    $c = $j.message.content
    $t = if ($c -is [string]) { $c } else { $parts = @($c | Where-Object { $_.type -eq 'text' } | ForEach-Object text); if (@($c | Where-Object { $_.type -eq 'tool_result' }).Count) { return $null }; $parts -join "`n" }
    if (-not "$t".Trim() -or "$t".TrimStart().StartsWith('<')) { return $null }
    $t
}

# where an edit of the last message goes back to: the entry before that message (its parentUuid); '' = it was the first
# message; $null = no transcript (or no message in it)
function Get-EditPoint {
    $sid = if ($script:st.session) { $script:st.session } else { "$(Get-Content $sessFile -ErrorAction SilentlyContinue)".Trim() }
    $f = "$proj\$sid.jsonl"
    if (-not $sid -or -not (Test-Path $f)) { return $null }
    $script:st.session = $sid
    $last = $null
    foreach ($l in [IO.File]::ReadAllLines($f)) {
        if ($l -notmatch '"type":"user"') { continue }
        $j = try { $l | ConvertFrom-Json } catch { continue }
        if ($j.type -eq 'user' -and $j.uuid -and $null -ne (Get-UserText $j)) { $last = $j }
    }
    if (-not $last) { return $null }
    "$($last.parentUuid)"
}

# one line from Claude: text as it streams, whole messages, tool steps, the end of a turn
function Read-Out([string]$l) {
    $j = try { $l | ConvertFrom-Json } catch { return }
    switch ($j.type) {
        'stream_event' { if ($j.event.type -eq 'content_block_delta' -and $j.event.delta.type -eq 'text_delta' -and -not $j.parent_tool_use_id) { if (-not $script:st.busy) { Set-Busy 'Thinking' }; Add-Event 'delta' $j.event.delta.text } }
        'assistant' {
            if ($j.parent_tool_use_id) { return }   # a helper's own steps: only its summary counts
            foreach ($c in @($j.message.content)) {
                if ($c.type -eq 'text' -and "$($c.text)".Trim()) { Add-Event 'text' $c.text }
                elseif ($c.type -eq 'tool_use') { $s = Get-Step $c; Add-Event 'tool' $s; Set-Busy $s }
            }
        }
        'user' {   # the replay: the app's own messages are already shown; others came from the phone or claude.ai
            $t = Get-UserText $j
            if ($null -eq $t) { return }
            $k = $script:sent.IndexOf($t)
            if ($k -ge 0) { $script:sent.RemoveAt($k) } else { Add-Event 'user' $t; Set-Busy 'Thinking' }
        }
        'result' {
            $script:st.busy = $false; $script:st.step = ''; $script:st.since = $null; Save-State
            if ($j.is_error -or $j.subtype -ne 'success') { Add-Event 'error' "$(if ($j.result) { $j.result } else { $j.subtype })" }
            Add-Event 'status' 'idle'
        }
        'control_response' {
            if ($j.response.request_id -ne $script:rcId) { return }
            if ($j.response.subtype -eq 'success' -and $j.response.response.session_url) {
                $script:st.remote = $j.response.response.session_url; Save-State
                if ($j.response.response.bridge_session_id) { Set-Content "$Dir\remote.txt" "$($j.response.response.bridge_session_id)|$($script:st.session)" }
            } elseif ($script:rcReattach) { Send-Remote $false }   # the old remote session is gone: a new one
        }
        'system' { if ($j.subtype -eq 'init' -and $j.session_id -and $j.session_id -ne $script:st.session) { $script:st.session = $j.session_id; Set-Content $sessFile $j.session_id; Save-State } }   # (the id Claude really uses: resumed next time)
    }
}

# (a new version of this file: settled for 5 s and parsing - one being written isn't run - else waited for)
$script:selfTime = (Get-Item $PSCommandPath).LastWriteTime
$script:selfArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") + @(foreach ($k in 'Dir', 'Exe', 'ExeArgs', 'IdleHours') { if ($PSBoundParameters.ContainsKey($k)) { "-$k"; "`"$($PSBoundParameters[$k])`"" } })
function Test-SelfUpdated {
    $t = (Get-Item $PSCommandPath -ErrorAction SilentlyContinue).LastWriteTime
    if (-not $t -or $t -eq $script:selfTime -or ((Get-Date) - $t).TotalSeconds -lt 5) { return $false }
    $err = $null; [void][Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$null, [ref]$err)
    if ($err) { $script:selfTime = $t; return $false }   # (broken: keep running this one until the file changes again)
    $true
}
function Switch-Mode {
    $n = Get-Mode; if (($n -join '/') -eq $script:st.mode -and $script:proc) { return }
    $had = [bool]$script:proc; Stop-Claude
    if ($had -or $Once) { Start-Claude } else { $script:st.mode = $n -join '/' }
    Add-Event 'status' "Now using $((Get-Culture).TextInfo.ToTitleCase($n[0])) at $($n[1]) effort."; Save-State
}
function Restart-Self { Stop-Claude; Save-State; $mutex.ReleaseMutex(); Start-Process powershell -WindowStyle Hidden -ArgumentList $script:selfArgs }
Save-State
if (-not $Once) { Start-Claude }   # (Remote Control from the start)
$lastUse = Get-Date; $started = Get-Date
while ($true) {
    # the app's requests, oldest first
    foreach ($f in @(Get-ChildItem "$Dir\inbox\*.json" -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $m = try { Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
        Remove-Item $f.FullName -Force
        if (-not $m) { continue }
        $lastUse = Get-Date
        if ($m.cmd -eq 'stop') {   # stop the answer: Claude Code's interrupt, else start over on the same conversation
            if ($script:st.busy) {
                try { Send-Line (@{ type = 'control_request'; request_id = [guid]::NewGuid().ToString(); request = @{ subtype = 'interrupt' } } | ConvertTo-Json -Compress -Depth 4) } catch { Stop-Claude }
                $script:st.busy = $false; $script:st.step = ''; $script:st.since = $null; Save-State; Add-Event 'status' 'Stopped.'
            }
            continue
        }
        if ($m.cmd -eq 'new') { Stop-Claude; $script:st.session = $null; Remove-Item $sessFile -Force; $script:st.busy = $false; Add-Event 'status' 'New conversation.'; Save-State; if (-not $Once) { Start-Claude }; continue }
        if ($m.cmd -eq 'open' -and "$($m.session)" -match '^[0-9a-fA-F-]{36}$') {   # an earlier conversation (the app's chat menu); fork: it's open somewhere else too
            Stop-Claude; $script:st.session = "$($m.session)"; $script:fork = [bool]$m.fork; $script:st.busy = $false; Set-Content $sessFile $script:st.session
            Add-Event 'status' "$(if ($m.fork) { 'Continuing a copy of an earlier conversation (it''s open somewhere else too).' } else { 'Opened an earlier conversation.' })"; Save-State
            if (-not $Once) { Start-Claude }; continue
        }
        # the last message, changed (the app's edit button): the conversation goes back to just before that message - a
        # copy of it (--resume-session-at + --fork-session; the original keeps the old answer) - and the new words go in
        # its place. It was the first message: a new conversation. No transcript to go back in: sent as it is.
        if ($m.cmd -eq 'edit' -and "$($m.text)".Trim()) {
            $at = Get-EditPoint
            Stop-Claude; $script:st.busy = $false; $script:st.step = ''; $script:st.since = $null
            if ($at -eq '') { $script:st.session = $null; Remove-Item $sessFile -Force; Add-Event 'status' 'Edited your first message - a fresh start.' }
            elseif ($at) { $script:resumeAt = $at; $script:fork = $true; Add-Event 'status' 'Edited your last message.' }
            else { Add-Event 'status' 'Edited your last message (sent as a new one).' }
            Save-State
            $m = [pscustomobject]@{ text = "$($m.text)" }
        }
        # a new speed (mode.txt, written by the app): Claude starts again on it, same conversation - after its answer when busy
        if ($m.cmd -eq 'mode') { if ($script:st.busy) { $script:modeWait = $true } else { Switch-Mode }; continue }
        if ($m.cmd -eq 'start') { if (-not $script:proc -and -not $Once) { Start-Claude }; continue }
        if ($m.cmd -eq 'quit') { Stop-Claude; Remove-Item $stateFile -Force; if (-not $main) { $mutex.ReleaseMutex(); Set-Location $env:TEMP; Remove-Item $Dir -Recurse -Force }; return }
        if ("$($m.text)".Trim()) {
            if (-not $script:proc -or $script:proc.HasExited) { Start-Claude }   # (its "session" event first: the app shows a conversation from there)
            Add-Event 'user' $m.text
            Set-Busy 'Thinking'
            Send-Line (@{ type = 'user'; message = @{ role = 'user'; content = "$($m.text)" } } | ConvertTo-Json -Compress -Depth 4)
            $script:sent.Add("$($m.text)")
        }
    }
    # Claude's output, as it comes
    if ($script:proc) {
        while ($script:reader -and $script:reader.IsCompleted) {
            $l = $script:reader.Result
            if ($null -eq $l) { $script:reader = $null; break }
            Read-Out $l; $lastUse = Get-Date
            $script:reader = $script:proc.StandardOutput.ReadLineAsync()
        }
        if ($script:proc.HasExited -and -not $script:reader) {
            if ($script:st.busy) { Add-Event 'error' "Claude stopped unexpectedly (exit code $($script:proc.ExitCode)) - send the message again." }
            $script:proc = $null; $script:st.busy = $false; $script:st.step = ''; $script:st.since = $null; $script:st.remote = $null; Save-State
        }
        # Claude Code updated itself: the new version takes over (same conversation)
        elseif (-not $script:st.busy -and (Get-Item $Exe).LastWriteTime -ne $script:exeTime) { Stop-Claude; if (-not $Once) { Start-Claude } }
    }
    # this script was updated (a Messiah update, a fix): the new version takes over once Claude isn't working - the same
    # conversation (session.txt), Remote Control on the same link (remote.txt). 10/12: a chat kept old code for a day.
    if (-not $Once -and -not $script:st.busy -and -not (Get-ChildItem "$Dir\inbox\*.json") -and (Test-SelfUpdated)) { Restart-Self; return }
    if ($script:modeWait -and -not $script:st.busy) { $script:modeWait = $false; Switch-Mode }
    if ($Once -and -not $script:st.busy -and -not (Get-ChildItem "$Dir\inbox\*.json")) { Stop-Claude; return }
    if ($Once -and ((Get-Date) - $started).TotalSeconds -gt 60) { Add-Event 'error' 'Test run stopped after 60 s'; Stop-Claude; return }   # (tests: never hang)
    if (-not $script:st.busy -and ((Get-Date) - $lastUse).TotalHours -ge $IdleHours) { Stop-Claude; Remove-Item $stateFile -Force; return }
    Start-Sleep -Milliseconds 150
}
