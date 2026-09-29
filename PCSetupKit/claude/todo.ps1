# Script-written items on the owner's to-do list (maint-todo.txt: the tray alerts on it, Status lists it). Each item
# has an id, so it is added once, updated in place, and removed with -Done once the thing is fixed. Lines written by
# anyone else (Claude, when the optional Claude part is on) are left exactly as they are.
#   & todo.ps1 -Id ram-expo -Text "..."     add or update     & todo.ps1 -Id ram-expo -Done     remove
#   & todo.ps1 -List                        the ids currently on the list
# The owner dismisses an item by deleting its line (tray > Maintenance to-do list opens the file): it then stays away for
# 90 days even if the reason is still there. The file is only rewritten when its content changes, so the tray alerts once
# per real change.
#   & todo.ps1 -Snooze '<the line>' [-Days 7]   off the list until then (the app's "Remind me in a week"), then back
param([string]$Id, [string]$Text, [switch]$Done, [switch]$List, [string]$Snooze, [int]$Days = 7, [string]$Dir = $PSScriptRoot)
$file = "$Dir\maint-todo.txt"; $store = "$Dir\todo-scripted.json"
$items = [ordered]@{}; $dismissed = @{}; $snoozed = @{}   # snoozed: the line -> @{ until; id (the kit's own items) }
if (Test-Path $store) { try { $j = Get-Content $store -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop; if ($j.items) { $j.items.PSObject.Properties | ForEach-Object { $items[$_.Name] = "$($_.Value)" } }; if ($j.dismissed) { $j.dismissed.PSObject.Properties | ForEach-Object { $dismissed[$_.Name] = "$($_.Value)" } }; if ($j.snoozed) { $j.snoozed.PSObject.Properties | ForEach-Object { $snoozed[$_.Name] = @{ until = "$($_.Value.until)"; id = "$($_.Value.id)" } } } } catch {} }
if ($List) { return @($items.Keys) }
$ours = @($items.Values)
$lines = @(Get-Content $file -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
$orig = $lines
# snooze a line: off the list (not dismissed) until then - a kit item can't come back meanwhile
if ($Snooze) {
    $sid = @($items.Keys | Where-Object { $items[$_] -eq $Snooze }) | Select-Object -First 1
    $snoozed[$Snooze] = @{ until = (Get-Date).AddDays($Days).ToString('o'); id = "$sid" }
    if ($sid) { $items.Remove($sid) }
    $lines = @($lines | Where-Object { $_ -ne $Snooze })
}
# snoozes that are over: back on the list (a kit item that got fixed meanwhile is removed again by its own check)
foreach ($k in @($snoozed.Keys)) {
    $u = [datetime]::MinValue
    if ([datetime]::TryParse($snoozed[$k].until, [ref]$u) -and $u -gt (Get-Date)) { continue }
    if ($snoozed[$k].id) { $items[$snoozed[$k].id] = $k }; if ($k -notin $lines) { $lines += $k }   # (in the lines too: not taken for deleted)
    $snoozed.Remove($k)
}
$ours = @($items.Values)
$others = @($lines | Where-Object { $_ -notin $ours })
# ours that are no longer in the file were deleted by the owner: dismissed
foreach ($k in @($items.Keys)) { if ($items[$k] -notin $lines -and (Test-Path $file)) { $dismissed[$k] = (Get-Date).ToString('o'); $items.Remove($k) } }
foreach ($k in @($dismissed.Keys)) { $d = [datetime]::MinValue; if (-not [datetime]::TryParse($dismissed[$k], [ref]$d) -or $d -lt (Get-Date).AddDays(-90)) { $dismissed.Remove($k) } }
if ($Done) { if ($Id) { $items.Remove($Id) } }
elseif ($Id -and $Text -and -not $dismissed.ContainsKey($Id) -and -not ($snoozed.Values | Where-Object { $_.id -eq $Id })) { $items[$Id] = ($Text -replace '\s*[\r\n]+\s*', ' ').Trim() }
$new = @($others) + @($items.Values)
$tmp = "$store.tmp"
[IO.File]::WriteAllText($tmp, ([pscustomobject]@{ items = [pscustomobject]$items; dismissed = [pscustomobject]$dismissed; snoozed = [pscustomobject]$snoozed } | ConvertTo-Json), (New-Object Text.UTF8Encoding $false)); Move-Item $tmp $store -Force
if (($new -join "`n") -ne ($orig -join "`n")) {
    [IO.File]::WriteAllLines("$file.tmp", [string[]]$new, (New-Object Text.UTF8Encoding $false)); Move-Item "$file.tmp" $file -Force
}
