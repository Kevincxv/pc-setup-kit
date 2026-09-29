# One-page status of the zero-maintenance system as text (the tray's Status opens dashboard.ps1, which falls back to this).
param([switch]$NoWait)
$cl = "$env:USERPROFILE\.claude"
$ai = if (Test-Path "$cl\ai-enabled.ps1") { & "$cl\ai-enabled.ps1" } else { $true }
$Host.UI.RawUI.WindowTitle = 'Messiah - status'
. "$cl\status-lib.ps1"
$colors = @{ ok = 'Green'; info = 'Gray'; warn = 'Yellow'; dim = 'DarkGray' }
foreach ($s in Get-KitStatus) {
    Write-Host "`n$($s.Title)" -ForegroundColor Cyan
    foreach ($l in $s.Lines) { Write-Host "  $($l.Text)" -ForegroundColor $colors[$l.Level] }
}
if (-not $NoWait) { Write-Host "`nPress any key to close." -ForegroundColor DarkGray; [void][Console]::ReadKey($true) }
