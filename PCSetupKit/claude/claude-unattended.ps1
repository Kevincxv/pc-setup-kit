# Runs Claude headless (no window, nothing pops up) for maintenance right after login.
# Called by claude-bg-maint.ps1 -Unattended:
#   -Mode maintain : when maint-due.ps1 lists something or maint-requests.txt exists (the /maintain skill)
#   -Mode improve  : once a day (first login 20+ h after the last one), the /self-improve pass (fix bugs, improve, check something new)
# maint-requests.txt: optional one-off requests for the next maintain run (e.g. "verify the Windows upgrade finished"); deleted after.
# The session id goes to maint-claude-session so the tray's "Watch maintenance live" can follow the run.
param([string]$Due, [ValidateSet('maintain', 'improve')][string]$Mode = 'maintain')
$cl = $PSScriptRoot
$claude = "$env:USERPROFILE\.local\bin\claude.exe"
$req = "$cl\maint-requests.txt"
Set-Location C:\WINDOWS\system32          # same project folder as Messiah, so memory is shared

$rules = @"
You are running UNATTENDED in the background right after the owner logged in. Nobody is watching and nothing may pop up
or open a window. Do everything that needs no confirmation. Do NOT restart, start BIOS steps, uninstall the owner's apps,
or run heavy benchmarks/stress tests (they may be starting a game) - put those on the to-do list instead.
Before any heavy step (driver/app installs, virus scans, DISM/cleanup, anything that loads the PC) run
& "$cl\game-check.ps1" - if it prints a game name, the owner is playing: skip that step and leave it for the next run.
To-do list: write each thing that needs the owner as one short plain-English line to $cl\maint-todo.txt (rewrite the file
with the complete current list; delete the file when nothing is open). The launcher shows it next time they open Messiah.
"@
if ($Mode -eq 'improve') {
    $extra = $null
    $prompt = "/self-improve`n`n$rules`nEnd with a short summary of what you did."
} else {
    $extra = if (Test-Path $req) { (Get-Content $req -Raw -Encoding UTF8).Trim() }
    $prompt = @"
/maintain $(if ($Due) { "Due now: $Due." })
$(if ($extra) { "One-off requests for this run:`n$extra" })

$rules
Update maint-state.json for the checks you completed. End with a short summary of what you did.
"@
}
$OutputEncoding = New-Object Text.UTF8Encoding $false   # PS 5.1 pipes to programs as ASCII by default: accented letters, symbols or an accented user name became '?'
$id = [guid]::NewGuid().ToString()
@($id, $Mode, (Get-Date).ToString('o')) | Set-Content "$cl\maint-claude-session"
$prompt | & $claude -p --session-id $id -n "Hidden maintenance ($Mode)" --dangerously-skip-permissions --model opus --effort medium --fallback-model sonnet
if ($extra -and (Test-Path $req)) { [IO.File]::Delete($req) }
