# Script-written items on the owner's to-do list (maint-todo.txt: the tray alerts on it, Status lists it). Each item
# has an id, so it is added once, updated in place, and removed with -Done once the thing is fixed. Lines written by
# anyone else (Claude, when the optional Claude part is on) are left exactly as they are.
#   & todo.ps1 -Id ram-expo -Text "..."     add or update     & todo.ps1 -Id ram-expo -Done     remove
#   & todo.ps1 -List                        the ids currently on the list
# The owner dismisses an item by deleting its line (tray > Maintenance to-do list opens the file): it then stays away for
# 90 days even if the reason is still there. The file is only rewritten when its content changes, so the tray alerts once
# per real change.
param([string]$Id, [string]$Text, [switch]$Done, [switch]$List, [string]$Dir = $PSScriptRoot)
$file = "$Dir\maint-todo.txt"; $store = "$Dir\todo-scripted.json"
$items = [ordered]@{}; $dismissed = @{}
if (Test-Path $store) { try { $j = Get-Content $store -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop; if ($j.items) { $j.items.PSObject.Properties | ForEach-Object { $items[$_.Name] = "$($_.Value)" } }; if ($j.dismissed) { $j.dismissed.PSObject.Properties | ForEach-Object { $dismissed[$_.Name] = "$($_.Value)" } } } catch {} }
if ($List) { return @($items.Keys) }
$ours = @($items.Values)
$lines = @(Get-Content $file -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
$others = @($lines | Where-Object { $_ -notin $ours })
# ours that are no longer in the file were deleted by the owner: dismissed
foreach ($k in @($items.Keys)) { if ($items[$k] -notin $lines -and (Test-Path $file)) { $dismissed[$k] = (Get-Date).ToString('o'); $items.Remove($k) } }
foreach ($k in @($dismissed.Keys)) { $d = [datetime]::MinValue; if (-not [datetime]::TryParse($dismissed[$k], [ref]$d) -or $d -lt (Get-Date).AddDays(-90)) { $dismissed.Remove($k) } }
if ($Done) { if ($Id) { $items.Remove($Id) } }
elseif ($Id -and $Text -and -not $dismissed.ContainsKey($Id)) { $items[$Id] = ($Text -replace '\s*[\r\n]+\s*', ' ').Trim() }
$new = @($others) + @($items.Values)
$tmp = "$store.tmp"
[IO.File]::WriteAllText($tmp, ([pscustomobject]@{ items = [pscustomobject]$items; dismissed = [pscustomobject]$dismissed } | ConvertTo-Json), (New-Object Text.UTF8Encoding $false)); Move-Item $tmp $store -Force
if (($new -join "`n") -ne ($lines -join "`n")) {
    [IO.File]::WriteAllLines("$file.tmp", [string[]]$new, (New-Object Text.UTF8Encoding $false)); Move-Item "$file.tmp" $file -Force
}
