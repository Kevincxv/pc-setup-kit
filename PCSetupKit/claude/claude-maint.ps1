# Claude Code maintenance for the "Messiah" launcher (runs in the background via claude-bg-maint.ps1).
# update -> marketplaces -> plugins -> doctor, in order since they touch the same install. Prints one clean status line.
param([int]$StepSeconds = 45)   # time limit per step (tests use a short one)
$ErrorActionPreference = 'Continue'
$c = "$env:USERPROFILE\.local\bin\claude.exe"
# Runs one claude subcommand with its own time limit (right after login the network can hang a step for minutes)
function Invoke-Claude([string[]]$ArgList, [int]$Seconds = $StepSeconds) {
    $o = Join-Path $env:TEMP "claude-maint-$PID.txt"; $e = "$o.err"
    $p = Start-Process $c -ArgumentList $ArgList -WindowStyle Hidden -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
    if (-not $p.WaitForExit($Seconds * 1000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; "Claude Code: '$($ArgList -join ' ')' got no response in $Seconds s, skipped" }
    else { (Get-Content $o, $e -Raw -ErrorAction SilentlyContinue) -join "`n" }
    Remove-Item $o, $e -Force -ErrorAction SilentlyContinue
}
$before = ((& $c --version 2>$null) -split ' ')[0]
$upd = Invoke-Claude 'update' 120
$after = ((& $c --version 2>$null) -split ' ')[0]
if ($after -and $before -ne $after) { "Claude Code: Updated $before -> $after" }
elseif ($upd -match 'no response in') { $upd }
elseif ($upd -match '(?i)fail|error') { "Claude Code: update FAILED - $(($upd -split "`n" | Where-Object { $_ -match '(?i)fail|error' } | Select-Object -First 1).Trim())" }
else { "Claude Code: $after (up to date)" }
Invoke-Claude 'plugin', 'marketplace', 'update' | Where-Object { $_ -match 'no response in' }
$s = Get-Content "$env:USERPROFILE\.claude\settings.json" -Raw | ConvertFrom-Json
if ($s.enabledPlugins) {
    $s.enabledPlugins.PSObject.Properties | Where-Object Value | ForEach-Object { Invoke-Claude 'plugin', 'update', $_.Name | Where-Object { $_ -match 'no response in' } }
}
$doc = Invoke-Claude 'doctor'
if ($doc -match 'no response in') { $doc }
elseif ($doc -notmatch 'No installation issues found') { "DOCTOR ISSUES:"; $doc }
