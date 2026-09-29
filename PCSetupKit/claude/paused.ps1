# Is the maintenance paused? (tray > Pause maintenance, or the app: kit-options.txt "pause-until=<local time>")
# Prints the time it's paused until, nothing when it isn't (or the pause is over). Used by claude-bg-maint.ps1,
# update-check.ps1 and after-update.ps1. -Options: tests.
param([string]$Options = "$PSScriptRoot\kit-options.txt")
$l = @(Get-Content $Options -ErrorAction SilentlyContinue) -match '^\s*pause-until\s*=' | Select-Object -First 1
$until = [datetime]::MinValue
if ($l -and [datetime]::TryParse((($l -split '=', 2)[1]).Trim(), [ref]$until) -and $until -gt (Get-Date)) { $until }
