# PC Setup Kit - uninstaller. Removes Messiah and its zero-maintenance system: tray icon, hidden session,
# background maintenance, shortcuts, the no-shutdown block and the maintenance scripts/skills. Your conversations,
# Claude account/settings and installed apps stay. Nothing is deleted outright: the removed files are moved to
# %USERPROFILE%\.claude\pc-setup-kit-removed-<date> so it can be put back by hand.
#   -RevertTweaks     also put back every Windows setting the kit changed (from C:\PCSetupKit\tweaks-backup.json),
#                     the Balanced power plan and hibernation. Removed Windows apps are listed (reinstall from the Store).
#   -RemoveClaudeCode also remove Claude Code itself.
#   -Yes              don't ask for confirmation.   -WhatIf  only list what would be done.
# Run as administrator: right-click > Run with PowerShell (it asks for admin), or from an admin PowerShell.
param([switch]$RevertTweaks, [switch]$RemoveClaudeCode, [switch]$Yes, [switch]$WhatIf,
    [string]$BackupFile = 'C:\PCSetupKit\tweaks-backup.json', [switch]$RevertOnly)   # -RevertOnly: tests / revert without removing
$ErrorActionPreference = 'Continue'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") + $(foreach ($k in $PSBoundParameters.Keys) { "-$k" })
    Start-Process powershell -Verb RunAs -ArgumentList $a; exit
}
# Running from C:\PCSetupKit (which gets moved at the end): continue from a temporary copy instead
if (-not $WhatIf -and -not $RevertOnly -and $PSCommandPath -like 'C:\PCSetupKit\*') {
    $tmp = Join-Path $env:TEMP 'pc-setup-kit-uninstall.ps1'; Copy-Item $PSCommandPath $tmp -Force
    & $tmp @PSBoundParameters; return
}
$cl = "$env:USERPROFILE\.claude"
$stash = "$cl\pc-setup-kit-removed-$(Get-Date -Format yyyyMMdd-HHmmss)"
$done = New-Object System.Collections.Generic.List[string]
function Do-It([string]$What, [scriptblock]$Action) { if ($WhatIf) { "  would: $What" } else { try { & $Action; $done.Add($What) } catch { "  FAILED: $What - $($_.Exception.Message)" } } }
function Stash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Do-It "move $Path to the removed-files folder" { New-Item $stash -ItemType Directory -Force | Out-Null
        $dest = Join-Path $stash ((Split-Path $Path -Leaf)); if (Test-Path $dest) { $dest += "-$(Get-Random)" }; Move-Item -LiteralPath $Path $dest -Force }
}

if (-not $Yes -and -not $WhatIf) {
    Write-Host "This removes Messiah, its tray icon and the hidden maintenance from this PC." -ForegroundColor Yellow
    if ($RevertTweaks) { Write-Host 'It also puts back the Windows settings the kit changed.' -ForegroundColor Yellow }
    if ($RemoveClaudeCode) { Write-Host 'It also removes Claude Code itself.' -ForegroundColor Yellow }
    if ((Read-Host 'Type YES to continue') -ne 'YES') { 'Cancelled - nothing was changed.'; return }
}

# the DNS network-check.ps1 switched to, if it did (read now: its history is moved away with the scripts below)
# the game folders gaming-check.ps1 asked Defender to skip (read now, before its state moves away)
$gameEx = try { @((Get-Content "$env:USERPROFILE\.claude\gaming-state.json" -Raw -ErrorAction Stop | ConvertFrom-Json).excluded) } catch { @() }
$gpuPref = try { @((Get-Content "$env:USERPROFILE\.claude\gaming-state.json" -Raw -ErrorAction Stop | ConvertFrom-Json).gpuPref) } catch { @() }   # the games gaming-check.ps1 set to the fast graphics chip
$dnsSet = try { @(Get-Content "$env:USERPROFILE\.claude\net-history.json" -Raw -ErrorAction Stop | ConvertFrom-Json | ForEach-Object { $_ } | Where-Object { $_.dnsSet }) | Select-Object -Last 1 } catch { $null }
if (-not $RevertOnly) {
    Write-Host "`n=== Stopping Messiah" -ForegroundColor Cyan
    # ourselves and our parents stay alive (the uninstaller may be run from inside a Messiah session)
    $keep = @(); $p = $PID; while ($p) { $keep += $p; $p = (Get-CimInstance Win32_Process -Filter "ProcessId=$p").ParentProcessId; if ($p -in $keep) { break } }
    foreach ($pr in Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -notin $keep -and ($_.CommandLine -match 'Messiah Tray\.ahk|Claude Admin Tray\.ahk|claude-admin-launch\.ps1|claude-bg-maint\.ps1|claude-unattended\.ps1') }) {
        Do-It "stop $($pr.Name) $($pr.ProcessId)" { Stop-Process -Id $pr.ProcessId -Force }
    }
    Write-Host "`n=== Scheduled tasks" -ForegroundColor Cyan
    foreach ($t in 'Messiah Tray', 'Claude Admin Tray', 'Claude Background Maintenance', 'Claude Resume After Restart', 'PC Setup Kit Update Guard', 'PC Setup Kit Update Check', 'Messiah Night Restart') {
        if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) { Do-It "remove task '$t'" { Unregister-ScheduledTask -TaskName $t -Confirm:$false } }
    }
    Write-Host "`n=== Shortcuts and tray icon" -ForegroundColor Cyan
    foreach ($l in "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Messiah.lnk", "$env:USERPROFILE\Desktop\Messiah.lnk",
        "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Messiah.lnk", "$env:USERPROFILE\Documents\Messiah Tray",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\PC Setup Kit.lnk", "$env:USERPROFILE\Desktop\PC Setup Kit.lnk",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Messiah Status.lnk", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\PC Setup Kit Status.lnk",
        # from before the rename to Messiah
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Claude (Admin).lnk", "$env:USERPROFILE\Desktop\Claude (Admin).lnk",
        "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Claude (Admin).lnk", "$env:USERPROFILE\Documents\Claude Admin Tray") { Stash $l }

    Write-Host "`n=== No-shutdown block (Claude settings)" -ForegroundColor Cyan
    $sf = "$cl\settings.json"
    if (Test-Path $sf) {
        $s = Get-Content $sf -Raw | ConvertFrom-Json
        $pre = @($s.hooks.PreToolUse | Where-Object { -not ($_.hooks | Where-Object { $_.command -match 'no-power-off\.ps1' }) })
        if (@($s.hooks.PreToolUse).Count -ne $pre.Count) {
            Do-It 'remove the no-shutdown hook from Claude settings (other settings kept)' {
                Copy-Item $sf "$sf.before-uninstall" -Force
                if ($pre) { $s.hooks.PreToolUse = $pre } else { $s.hooks.PSObject.Properties.Remove('PreToolUse') }
                if (-not @($s.hooks.PSObject.Properties).Count) { $s.PSObject.Properties.Remove('hooks') }
                [IO.File]::WriteAllText($sf, ($s | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding $false)) }
        }
    }
    Write-Host "`n=== Maintenance scripts, skills and their data" -ForegroundColor Cyan
    # (settings backups in "PC Setup Kit Backup" folders are the owner's: kept)
    $files = 'claude-admin-launch.ps1', 'claude-bg-maint.ps1', 'claude-maint.ps1', 'claude-unattended.ps1', 'crash-analyze.ps1', 'driver-check.ps1',
        'health-check.ps1', 'maint-due.ps1', 'maint-watch.ps1', 'periodic-maint.ps1', 'resume-after-restart.ps1', 'restart-check.ps1', 'session-lib.ps1',
        'refresh-session.ps1', 'status.ps1', 'status-lib.ps1', 'dashboard.ps1', 'tray-app.ps1', 'app-icon.ps1', 'driver-guard.ps1', 'driver-blocklist.txt', 'trends.ps1', 'health-history.json', 'Messiah Session.lnk', 'app-window.txt', 'tray-hwnd.txt', 'rehearse-login.ps1', 'game-check.ps1', 'kit-update.ps1', 'migrate-names.ps1', 'self-test.ps1', 'self-test.json', 'self-test.log', 'ai-enabled.ps1', 'kit-options.txt', 'optimize.ps1', 'maint-actions.ps1', 'ensure-schedule.ps1', 'todo.ps1', 'display-refresh.ps1', 'todo-scripted.json', 'actions-state.json', 'tweaks-local.ps1',
        'game-perf.ps1', 'perf-history.json', 'tools', 'gpu-watch.ps1', 'gpu-state.json', 'network-check.ps1', 'net-history.json', 'settings-backup.ps1',
        'settings-restored.txt', 'display-state.json', 'notifications.log', 'gaming-check.ps1', 'gaming-state.json', 'make-usb.ps1', 'after-update.ps1', 'update-check.ps1', 'update-state.json', 'paused.ps1', 'weekly-summary.ps1', 'bios-info.ps1', 'activation-check.ps1', 'activation-state.txt', 'ai-toggle.ps1', 'ai-toggle.log', 'gpu-rollback.ps1', 'gpu-hold.txt', 'vendor-updates.ps1', 'vendor-state.json', 'restart-night.ps1', 'restart-night.log', 'junk-apps.ps1', 'junk-state.json', 'files-backup.ps1', 'files-backup-state.json', 'defender-check.ps1', 'release-issues.ps1', 'release-issues.txt', 'weekly-summary.last', 'tray-news.txt', 'self-test-retry.log', 'nvidia-settings.ps1', 'nvidia-settings.txt',
        'maint-report.txt', 'maint-state.json', 'maint-todo.txt', 'maint-todo.shown', 'maint-requests.txt', 'maint-claude-running', 'maint-claude-session',
        'maint-history', 'maint-claude-log', 'restart-ledger.json', 'restart-canary.txt', 'admin-sessions.txt', 'resume-after-login.txt', 'rehearsal.txt',
        'games.txt', 'tray-notified.ini', 'tray-errors.log', 'selfimprove-last', 'selfimprove-journal.md', 'selfimprove-backup', 'session-refresh.log', 'benchmarks.json',
        'health-check.last', 'health-ignore.txt', 'startup-baseline.txt', 'kit-version.txt', 'hooks\no-power-off.ps1', 'skills\maintain', 'skills\pc-optimize', 'skills\self-improve'
    foreach ($f in $files) { Stash "$cl\$f" }
    Stash "$env:USERPROFILE\Documents\PC Setup Kit report.txt"
}

if ($RevertTweaks) {
    Write-Host "`n=== Putting Windows settings back" -ForegroundColor Cyan
    $bk = $null; try { $bk = Get-Content $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch {}
    if (-not $bk) { '  No backup of the original settings was found (the kit was set up before backups existed) - nothing to put back.' }
    $apps = @()
    foreach ($e in @($bk.PSObject.Properties)) {
        $k = $e.Name -split '\|'; $v = $e.Value
        switch ($k[0]) {
            'reg' {
                if ($v.Existed) { Do-It "setting $($k[2]) back to '$($v.Value)'" { Set-ItemProperty -Path $k[1] -Name $k[2] -Value $v.Value -Type $(if ($v.Kind) { $v.Kind } else { 'DWord' }) } }
                elseif ($null -ne (Get-ItemProperty -Path $k[1] -Name $k[2] -ErrorAction SilentlyContinue)) { Do-It "setting $($k[2]) removed (wasn't set before)" { Remove-ItemProperty -Path $k[1] -Name $k[2] } }
            }
            'service' { Do-It "service $($k[1]) back to $($v.StartType)" { Set-Service $k[1] -StartupType $v.StartType } }
            'task' { $tp = $k[1].Substring(0, $k[1].LastIndexOf('\') + 1); $tn = $k[1].Substring($k[1].LastIndexOf('\') + 1)
                Do-It "task $tn back on" { Enable-ScheduledTask -TaskPath $tp -TaskName $tn | Out-Null } }
            'nic' { Do-It "network adapter $($k[1]) '$($k[2])' back to $($v.DisplayValue)" { Set-NetAdapterAdvancedProperty -Name $k[1] -DisplayName $k[2] -DisplayValue $v.DisplayValue -NoRestart } }
            'power' { $d = Get-CimInstance -Namespace root\wmi MSPower_DeviceEnable | Where-Object InstanceName -eq $k[1]
                if ($d) { Do-It "USB/network power-saving back on ($($k[1].Split('\')[1]))" { Set-CimInstance -InputObject $d -Property @{ Enable = $true } } } }
            'app' { $apps += $k[1] }
            'startup' { Do-It "start-up item $($k[2]) back on" { if ($v.Existed) { Set-ItemProperty -Path $k[1] -Name $k[2] -Value ([Convert]::FromBase64String($v.Value)) -Type Binary } else { Remove-ItemProperty -Path $k[1] -Name $k[2] } } }
            'plan' { $plan = $v.Guid }   # put back below
            'edge' { if ($k[1] -eq 'desktop' -and (Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe")) { Do-It 'Edge desktop icon back' { $s = (New-Object -ComObject WScript.Shell).CreateShortcut("$env:PUBLIC\Desktop\Microsoft Edge.lnk"); $s.TargetPath = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"; $s.Save() } } }   # (the pin and the default browser: the owner's to choose again)
            'cap' { Do-It "Windows part $(($k[1] -split '~')[0]) back" { Add-WindowsCapability -Online -Name $k[1] | Out-Null } }
            'feature' { Do-It "Windows feature $($k[1]) back on" { Enable-WindowsOptionalFeature -Online -FeatureName $k[1] -NoRestart -WarningAction SilentlyContinue | Out-Null } }
            'reserved' { Do-It 'reserved storage back on' { Set-WindowsReservedStorageState -State Enabled | Out-Null } }
            'pagefile' { }   # kept: no page file at all makes games crash when memory runs short
        }
    }
    if (-not $RevertOnly) {
        $to = if ($plan) { $plan } else { '381b4222-f694-41f0-9685-ff5bb260df2e' }   # the plan it had (else Balanced)
        Do-It "power plan back to $(if ($plan) { 'the one it had' } else { 'Balanced' })" { powercfg /setactive $to }
        Do-It 'hibernation (and fast startup) back on' { powercfg /hibernate on }
    }
    if ($dnsSet.dnsSet -eq 'public' -and $dnsSet.ifIndex) { Do-It 'DNS back to automatic (the router''s)' { Set-DnsClientServerAddress -InterfaceIndex $dnsSet.ifIndex -ResetServerAddresses } }
    if ($apps) { "  Windows apps the kit removed (reinstall any you want from the Microsoft Store): $($apps -join ', ')" }
}

# Defender scans the game folders again (always: a leftover exclusion would be a security gap nobody knows about)
foreach ($p in $gameEx | Where-Object { $_ }) { Do-It "Defender scans $p again" { Remove-MpPreference -ExclusionPath $p } }
foreach ($e in $gpuPref | Where-Object { $_ }) { Do-It "graphics chip choice for $e back to Windows' own" { Remove-ItemProperty 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -Name $e -ErrorAction Stop } }

if ($RemoveClaudeCode -and -not $RevertOnly) {
    Write-Host "`n=== Claude Code" -ForegroundColor Cyan
    foreach ($p in "$env:USERPROFILE\.local\bin\claude.exe", "$env:USERPROFILE\.local\share\claude") { Stash $p }
}
if (-not $RevertOnly -and (Test-Path 'C:\PCSetupKit')) {
    Stash 'C:\PCSetupKit'   # its setup.log and tweaks-backup.json end up in the removed-files folder too
}

Write-Host ''
if ($WhatIf) { 'Nothing was changed (-WhatIf).' }
else {
    "Done: $($done.Count) step(s)."
    if (Test-Path $stash) { "Removed files were moved to $stash (delete that folder when you're sure)." }
    if (-not $RevertOnly) { 'Apps the kit installed (Git, Steam, Discord, Chrome, WinDbg, AutoHotkey, NVIDIA App) are still there - uninstall any you don''t want in Settings > Apps.' }
    if ($RevertTweaks -and -not $RevertOnly) { 'Restart the PC when convenient so every setting takes effect.' }
}
