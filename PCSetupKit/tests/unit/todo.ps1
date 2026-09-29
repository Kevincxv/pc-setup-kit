# todo.ps1: script-written to-do items (added once, updated in place, removed when fixed; other lines untouched).
. "$PSScriptRoot\..\lib.ps1"
$D = "$Work\cl"; New-Item $D -ItemType Directory -Force | Out-Null
function T { & "$Src\todo.ps1" -Dir $D @args }
function Lines { @(Get-Content "$D\maint-todo.txt" -Encoding UTF8 -ErrorAction SilentlyContinue) }

Section 'adding, updating, removing'
T -Id bios -Text 'Update the BIOS.'
Check 'added' ((Lines) -join '|' -eq 'Update the BIOS.') ((Lines) -join ' | ')
$t0 = (Get-Item "$D\maint-todo.txt").LastWriteTime; Start-Sleep -Milliseconds 30
T -Id bios -Text 'Update the BIOS.'
Check 'the same item again: the file is not touched (no second alert)' ((Get-Item "$D\maint-todo.txt").LastWriteTime -eq $t0 -and @(Lines).Count -eq 1) ''
T -Id bios -Text 'Update the BIOS (newer text).'
Check 'new text for the same id: replaced in place, not added twice' ((Lines) -join '|' -eq 'Update the BIOS (newer text).') ((Lines) -join ' | ')
T -Id dust -Text "Dust the PC:`n  fans and filters."
Check 'a second item; line breaks in the text become one line' ((Lines) -join '|' -eq 'Update the BIOS (newer text).|Dust the PC: fans and filters.') ((Lines) -join ' | ')
Check '-List gives the ids' (((T -List) -join ',') -eq 'bios,dust') ((T -List) -join ',')
T -Id bios -Done
Check 'done: removed' ((Lines) -join '|' -eq 'Dust the PC: fans and filters.') ((Lines) -join ' | ')
T -Id never-added -Done
Check 'done for an id that is not there: nothing happens' ((Lines) -join '|' -eq 'Dust the PC: fans and filters.') ''

Section 'the owner dismisses an item by deleting its line'
T -Id expo -Text 'Turn EXPO on.'
$keep = @(Lines | Where-Object { $_ -ne 'Turn EXPO on.' }); [IO.File]::WriteAllLines("$D\maint-todo.txt", [string[]]$keep, (New-Object Text.UTF8Encoding $false))
T -Id expo -Text 'Turn EXPO on.'
Check 'deleted line: not added back while the reason is still there' (-not ((Lines) -contains 'Turn EXPO on.')) ((Lines) -join ' | ')
$j = Get-Content "$D\todo-scripted.json" -Raw | ConvertFrom-Json; $j.dismissed.expo = (Get-Date).AddDays(-91).ToString('o'); $j | ConvertTo-Json | Set-Content "$D\todo-scripted.json"
T -Id expo -Text 'Turn EXPO on.'
Check '... but back after 90 days' ((Lines) -contains 'Turn EXPO on.') ((Lines) -join ' | ')
T -Id expo -Done

Section 'lines written by others (Claude) are left alone'
[IO.File]::WriteAllLines("$D\maint-todo.txt", [string[]]@('Blue screen test: EXPO is off - use the PC normally.', 'Dust the PC: fans and filters.'), (New-Object Text.UTF8Encoding $false))
T -Id ram -Text 'Turn EXPO on.'
Check 'another line stays, in its place; ours follow' ((Lines) -join '|' -eq 'Blue screen test: EXPO is off - use the PC normally.|Dust the PC: fans and filters.|Turn EXPO on.') ((Lines) -join ' | ')
T -Id dust -Done; T -Id ram -Done
Check 'removing ours never removes theirs' ((Lines) -join '|' -eq 'Blue screen test: EXPO is off - use the PC normally.') ((Lines) -join ' | ')
Check 'unicode survives (UTF-8, no BOM)' ($(T -Id u -Text 'Café ✓ done'; (Get-Content "$D\maint-todo.txt" -Encoding UTF8) -contains 'Café ✓ done') -and [IO.File]::ReadAllBytes("$D\maint-todo.txt")[0] -ne 0xEF) ''
'{ broken' | Set-Content "$D\todo-scripted.json"; T -Id x -Text 'X.'
Check 'a damaged store: starts over without errors, other lines kept' ((Lines) -contains 'X.' -and (Lines) -contains 'Blue screen test: EXPO is off - use the PC normally.') ((Lines) -join ' | ')
Section 'snooze (the app: Remind me in a week)'
Clear-Path "$D\maint-todo.txt"; Clear-Path "$D\todo-scripted.json"
T -Id rebar -Text 'Resizable BAR is off'; 'A line Claude wrote' | Add-Content "$D\maint-todo.txt"
T -Snooze 'Resizable BAR is off'; T -Snooze 'A line Claude wrote'
T -Id rebar -Text 'Resizable BAR is off'
Check 'snoozed: off the list - the kit''s item doesn''t put itself back meanwhile' (-not @(Get-Content "$D\maint-todo.txt" -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })) ((Get-Content "$D\maint-todo.txt") -join ' | ')
$j = Get-Content "$D\todo-scripted.json" -Raw | ConvertFrom-Json; foreach ($p in $j.snoozed.PSObject.Properties) { $p.Value.until = (Get-Date).AddDays(-1).ToString('o') }; $j | ConvertTo-Json -Depth 4 | Set-Content "$D\todo-scripted.json"
T -Id rebar -Text 'Resizable BAR is off'
$l = @(Get-Content "$D\maint-todo.txt")
Check '... a week later: both back (not counted as dismissed)' (($l -contains 'Resizable BAR is off') -and ($l -contains 'A line Claude wrote') -and -not ((Get-Content "$D\todo-scripted.json" -Raw | ConvertFrom-Json).dismissed.PSObject.Properties.Name -contains 'rebar')) ($l -join ' | ')
Finish
