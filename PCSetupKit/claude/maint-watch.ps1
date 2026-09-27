# Live view of the hidden maintenance run (opened from the Messiah tray menu: "Watch maintenance live").
# Follows the headless Claude session named in maint-claude-session and prints each step as it happens.
# When nothing is running it shows the output of the last run.
$cl = "$env:USERPROFILE\.claude"
$Host.UI.RawUI.WindowTitle = 'Claude hidden maintenance - live'
$busy = "$cl\maint-claude-running"
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime   # a marker left from before a shutdown is stale
function Running { (Test-Path $busy) -and ((Get-Date) - (Get-Item $busy).LastWriteTime).TotalMinutes -lt 60 -and (Get-Item $busy).LastWriteTime -gt $boot }
function Show-LastLog {
    $last = Get-ChildItem "$cl\maint-claude-log\*.md" -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($last) { Write-Host "Last run: $($last.BaseName)" -ForegroundColor Cyan; Get-Content $last.FullName | Write-Host }
    else { Write-Host 'No hidden maintenance run yet.' }
}

if (-not (Running)) { Write-Host "Hidden maintenance isn't running right now.`n" -ForegroundColor DarkGray; Show-LastLog; return }

$shownId = $null
while ($true) {
    $s = @(Get-Content "$cl\maint-claude-session" -ErrorAction SilentlyContinue)
    if ($s -and $s[0] -ne $shownId) {
        $shownId = $s[0]; $pos = 0
        Write-Host "`n=== Hidden maintenance: $($s[1]) (started $(([datetime]$s[2]).ToString('t'))) ===" -ForegroundColor Cyan
    }
    $t = if ($shownId) { Get-ChildItem "$cl\projects\*\$shownId.jsonl" -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if ($t) {
        $fs = [IO.File]::Open($t.FullName, 'Open', 'Read', 'ReadWrite')
        if ($fs.Length -gt $pos) {
            [void]$fs.Seek($pos, 'Begin'); $sr = New-Object IO.StreamReader($fs)
            $text = $sr.ReadToEnd(); $cut = $text.LastIndexOf("`n") + 1   # only whole lines; the rest next time
            $pos += [Text.Encoding]::UTF8.GetByteCount($text.Substring(0, $cut))
            foreach ($line in $text.Substring(0, $cut) -split "`n") {
                try { $j = $line | ConvertFrom-Json } catch { continue }
                if ($j.type -ne 'assistant') { continue }
                $time = ([datetime]$j.timestamp).ToLocalTime().ToString('T')
                foreach ($c in $j.message.content) {
                    if ($c.type -eq 'tool_use') { Write-Host "$time  > $(if ($c.input.description) { $c.input.description } else { $c.name })" -ForegroundColor DarkGray }
                    elseif ($c.type -eq 'text' -and $c.text.Trim()) { Write-Host "$time  $($c.text.Trim())" }
                }
            }
        }
        $fs.Close()
    }
    if (-not (Running)) { Write-Host "`n=== Finished. You can close this window. ===" -ForegroundColor Green; break }
    Start-Sleep -Seconds 2
}
