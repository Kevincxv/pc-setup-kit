# One-time move from the old name "Claude (Admin)" to "Messiah" on PCs installed before the rename: shortcuts, the tray
# task and its folder. Run by the background maintenance at every login; does nothing once everything is moved.
# Taskbar pins are left alone (renaming a pinned shortcut unpins it). The old updater still needs the kit to contain
# tray\Claude Admin Tray.ahk - delete that copy and this script once every installed PC is past 2026-12.
# -Force: tests (sandbox paths, mocked scheduled-task commands); otherwise it never runs inside the test suite.
param([string]$UserHome = $env:USERPROFILE, [string]$AppData = $env:APPDATA, [switch]$Force)
if ($env:PCKIT_IN_TESTS -and -not $Force) { return }
$ErrorActionPreference = 'Continue'
$done = @()

foreach ($d in "$AppData\Microsoft\Windows\Start Menu\Programs", "$UserHome\Desktop") {
    $old = "$d\Claude (Admin).lnk"
    if (-not (Test-Path -LiteralPath $old)) { continue }
    if (Test-Path -LiteralPath "$d\Messiah.lnk") { Remove-Item -LiteralPath $old -Force } else { Move-Item -LiteralPath $old "$d\Messiah.lnk" -Force }
    $done += "shortcut ($(Split-Path $d -Leaf))"
}

$oldDir = "$UserHome\Documents\Claude Admin Tray"; $newDir = "$UserHome\Documents\Messiah Tray"
function OldTrayRunning { @(Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" | Where-Object CommandLine -match 'Claude Admin Tray\.ahk') }
$oldTask = Get-ScheduledTask -TaskName 'Claude Admin Tray' -ErrorAction SilentlyContinue
if ($oldTask) {
    try {
        New-Item $newDir -ItemType Directory -Force | Out-Null
        if (-not (Test-Path "$newDir\Messiah Tray.ahk")) { Copy-Item "$oldDir\Claude Admin Tray.ahk" "$newDir\Messiah Tray.ahk" -ErrorAction Stop }
        # the exact task definition with only the name and path changed (handing back the principal object fails when
        # the user name equals the computer name)
        $xml = (Export-ScheduledTask -TaskName 'Claude Admin Tray') -replace 'Claude Admin Tray', 'Messiah Tray'
        Register-ScheduledTask -TaskName 'Messiah Tray' -Xml $xml -Force -ErrorAction Stop | Out-Null
        OldTrayRunning | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
        Unregister-ScheduledTask -TaskName 'Claude Admin Tray' -Confirm:$false -ErrorAction Stop
        Start-ScheduledTask 'Messiah Tray'
        $done += 'tray task'; $oldTask = $null
    }
    catch { "Rename to Messiah: tray task not moved yet ($($_.Exception.Message)) - will retry next login" }
}
# the old folder goes once nothing uses it (only the tray script was ever in it; anything else stays)
if (-not $oldTask -and (Test-Path "$oldDir\Claude Admin Tray.ahk") -and -not (OldTrayRunning)) {
    Remove-Item "$oldDir\Claude Admin Tray.ahk" -Force
    if (-not (Get-ChildItem $oldDir -Force)) { Remove-Item $oldDir -Force }
    $done += 'tray folder'
}
if ($done) { "Renamed Claude (Admin) to Messiah: $($done -join ', ')" }
