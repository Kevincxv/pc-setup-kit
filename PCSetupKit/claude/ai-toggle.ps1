# The AI assistant switch (the app's Settings "AI assistant (Claude)", run by the tray with admin rights; setup.ps1
# -WithClaude uses -Setup). Messiah does everything without it; switched on, the owner signs in with their own Claude
# account and gets the Messiah sessions (Claude Code with admin rights), /maintain and /self-improve.
# -On:  Claude Code (from claude.ai, only when it's missing), the kit's skills and the no-power-off hook, "claude=on" in
#       kit-options.txt, the session shortcut (tray-app.ps1), then a Messiah session opens for the sign-in (-NoOpen: not)
#       and the tray restarts with the sessions.
# -Off: "claude=off"; the open Messiah sessions close and the tray restarts without them (background maintenance stops
#       its hidden Claude runs on its next run). Claude Code, the sign-in and the conversations stay: on again needs
#       nothing new.
# -Setup: only the install part of -On (setup.ps1 does the shortcut, the tray and the first session itself).
# -Install (scriptblock instead of claude.ai's installer), -Claude, -Tray, -Test (no processes stopped/started): tests.
param([switch]$On, [switch]$Off, [switch]$Setup, [switch]$NoOpen, [switch]$Test,
    [string]$ClaudeDir = $PSScriptRoot, [string]$KitDir = 'C:\PCSetupKit', [scriptblock]$Install,
    [string]$Claude = "$env:USERPROFILE\.local\bin\claude.exe", [string]$Tray = "$env:USERPROFILE\Documents\Messiah Tray")
$ErrorActionPreference = 'Continue'
if ($Setup) { $On = $true }
if ($On -eq $Off) { 'Use -On or -Off'; return }
$cl = $ClaudeDir
$log = "$cl\ai-toggle.log"
function Say($m) { $m; try { Add-Content $log "$((Get-Date).ToString('s'))  $m" } catch {} }
function Set-Claude($v) {
    $f = "$cl\kit-options.txt"
    $lines = @(Get-Content $f -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch '^\s*claude\s*=' }) + "claude=$v"
    [IO.File]::WriteAllLines($f, [string[]]$lines)
}
function Restart-Tray {
    if ($Test) { Say 'Tray: restarted'; return }
    Stop-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe' OR Name='Messiah.exe' OR Name='PC Setup Kit.exe'" -ErrorAction SilentlyContinue |
        Where-Object CommandLine -match 'Messiah Tray\.ahk' | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue
}

if ($Off) {
    Set-Claude 'off'
    Say 'AI assistant: off (Claude Code and your conversations stay; switch it on again any time)'
    # the Messiah sessions: their launcher windows and the Claude Code inside them
    if (-not $Test) {
        foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object CommandLine -match 'claude-admin-launch\.ps1')) {
            Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.ProcessId)" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    Restart-Tray
    return
}

$Host.UI.RawUI.WindowTitle = 'Messiah - switching on the AI assistant'
if (-not (Test-Path $Claude)) {
    Say 'Installing Claude Code (from claude.ai)...'
    try {
        if ($Install) { & $Install } else { & ([scriptblock]::Create((Invoke-RestMethod 'https://claude.ai/install.ps1'))) }
    } catch { Say "Claude Code install failed: $($_.Exception.Message)" }
    if (-not (Test-Path $Claude)) {
        Say "AI assistant: Claude Code didn't install (no internet?) - it stays off; try the switch again later"
        Set-Claude 'off'
        return
    }
}
New-Item "$cl\skills", "$cl\hooks" -ItemType Directory -Force | Out-Null
if (Test-Path "$KitDir\claude\skills") { Copy-Item "$KitDir\claude\skills\*" "$cl\skills" -Recurse -Force }
# Claude never shuts down or restarts the PC (hook); restart-only work finishes whenever the owner turns it off
if (Test-Path "$KitDir\claude\hooks") { Copy-Item "$KitDir\claude\hooks\*" "$cl\hooks" -Force }
$sf = "$cl\settings.json"
$s = $null; if (Test-Path $sf) { try { $s = Get-Content $sf -Raw | ConvertFrom-Json -ErrorAction Stop } catch {} }
if (-not $s) { $s = [pscustomobject]@{} }
$s | Add-Member hooks ([pscustomobject]@{ PreToolUse = @([pscustomobject]@{ matcher = 'Bash|PowerShell'; hooks = @([pscustomobject]@{
                    type = 'command'; command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$cl\hooks\no-power-off.ps1`""; timeout = 15 }) }) }) -Force
[IO.File]::WriteAllText($sf, ($s | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding $false))   # no BOM
Set-Claude 'on'
Say 'AI assistant: on'
if ($Setup) { return }

if (Test-Path "$cl\tray-app.ps1") { & "$cl\tray-app.ps1" -TrayDir $Tray -ClaudeDir $cl -NoRestart | ForEach-Object { Say "  $_" } }
# the session first (its window is there when the tray starts, so the tray doesn't open a hidden one as well)
if (-not $NoOpen -and (Test-Path "$cl\Messiah Session.lnk")) {
    Say 'Opening Messiah: sign in with your own Claude account in the browser page it opens'
    if (-not $Test) {
        Start-Process "$cl\Messiah Session.lnk"
        for ($i = 0; $i -lt 20 -and -not (Get-Process powershell -ErrorAction SilentlyContinue | Where-Object MainWindowTitle -eq 'Messiah'); $i++) { Start-Sleep 1 }
    }
}
Restart-Tray
