# LIVE, the kit's own PC only: a real fresh install on a clean Windows 11 CLIENT in Windows Sandbox - for each mode (no
# AI, with Claude) a new sandbox runs setup.ps1 for real, the install checks and the install's own self-test (inside.ps1).
# GitHub's machines are Windows Server; this is the only test on the Windows friends actually have.
# Windows Sandbox needs the hypervisor, which the kit keeps OFF for gaming. So it's switched on only for the test:
# -Cleanup (after the test, or on its own) turns off every Windows feature enabled since sandbox-features-before.json
# was saved and sets the hypervisor to not start - fully off at the next restart (Windows can't unload it before;
# Claude never restarts the PC). Needs admin rights and the owner's desktop (the sandbox is a window).
# Results: %USERPROFILE%\.claude\sandbox-test\<mode>\ (summary.txt, check.txt, setup.txt, logs) and result.txt.
param([ValidateSet('noai', 'ai', 'both')][string]$Mode = 'both', [int]$Minutes = 100, [switch]$Cleanup, [switch]$CleanupOnly,
    [string]$Out = "$env:USERPROFILE\.claude\sandbox-test")
$repo = Split-Path (Split-Path (Split-Path $PSScriptRoot))   # the repo root (holds PCSetupKit\)
$cl = "$env:USERPROFILE\.claude"
New-Item $Out -ItemType Directory -Force | Out-Null
function Say($m) { $l = "$((Get-Date).ToString('g'))  $m"; Add-Content "$Out\run.log" $l; $l }

function Stop-Sandbox {
    foreach ($n in 'WindowsSandboxRemoteSession', 'WindowsSandboxClient', 'WindowsSandbox', 'WindowsSandboxServer') { Get-Process $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
    $w = [Diagnostics.Stopwatch]::StartNew()
    while ((Get-Process 'vmmemWindowsSandbox', 'WindowsSandbox*' -ErrorAction SilentlyContinue) -and $w.Elapsed.TotalSeconds -lt 60) { Start-Sleep 2 }
}

function Invoke-Cleanup {
    $b = try { Get-Content "$cl\sandbox-features-before.json" -Raw | ConvertFrom-Json } catch { $null }
    if (-not $b) { Say 'Cleanup: no saved feature list - turning off Windows Sandbox only' }
    $keep = @($b.enabled)
    $added = @(Get-WindowsOptionalFeature -Online | Where-Object { $_.State -match '^Enable' -and ($(if ($b) { $_.FeatureName -notin $keep } else { $_.FeatureName -eq 'Containers-DisposableClientVM' })) } | ForEach-Object FeatureName)
    foreach ($f in $added) {
        $r = Disable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        Say "Cleanup: turned off the Windows feature $f$(if ($r.RestartNeeded) { ' (finishes at the next restart)' })"
    }
    $o = bcdedit /set '{current}' hypervisorlaunchtype off 2>&1 | Out-String
    Say "Cleanup: hypervisor set not to start ($("$o".Trim())) - it is fully off after the next restart"
    Unregister-ScheduledTask -TaskName 'PCSetupKit Sandbox Test' -Confirm:$false -ErrorAction SilentlyContinue
    [IO.File]::Delete("$cl\sandbox-features-before.json")
}

if ($CleanupOnly) { Invoke-Cleanup; return }

$feat = (Get-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM).State
if ($feat -ne 'Enabled' -or -not (Get-CimInstance Win32_ComputerSystem).HypervisorPresent) {
    Say "Sandbox not ready yet (feature: $feat, hypervisor running: $((Get-CimInstance Win32_ComputerSystem).HypervisorPresent)) - it needs the restart after turning it on; trying again at the next login"
    return
}
# never under a game: the sandbox takes 8 GB of RAM and a lot of CPU for an hour
$w0 = Get-Date
while (($g = & "$cl\game-check.ps1") -and ((Get-Date) - $w0).TotalMinutes -lt 120) { Start-Sleep 60 }
if ($g) { Say "Held: $g still running after 2 h - trying again at the next login"; return }

$results = @()
foreach ($m in $(if ($Mode -eq 'both') { 'noai', 'ai' } else { $Mode })) {
    $res = "$Out\$m"; if (Test-Path $res) { Remove-Item $res -Recurse -Force }; New-Item $res -ItemType Directory -Force | Out-Null
    $wsb = "$Out\$m.wsb"
    @"
<Configuration>
  <MemoryInMB>8192</MemoryInMB>
  <vGPU>Disable</vGPU>
  <Networking>Enable</Networking>
  <MappedFolders>
    <MappedFolder><HostFolder>$repo</HostFolder><SandboxFolder>C:\KitRO</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder>$res</HostFolder><SandboxFolder>C:\Results</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder>
  </MappedFolders>
  <LogonCommand><Command>powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File C:\KitRO\PCSetupKit\tests\sandbox\inside.ps1 -Mode $m</Command></LogonCommand>
</Configuration>
"@ | Set-Content $wsb -Encoding UTF8
    Stop-Sandbox   # only one sandbox can run at a time
    Say "Sandbox ($m): starting a clean Windows 11 and installing the kit in it (up to $Minutes min)"
    Start-Process $wsb
    $w = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path "$res\done.txt") -and $w.Elapsed.TotalMinutes -lt $Minutes) { Start-Sleep 20 }
    $done = Test-Path "$res\done.txt"
    Start-Sleep 5; Stop-Sandbox
    $sum = @(Get-Content "$res\summary.txt" -ErrorAction SilentlyContinue)
    $ok = $done -and ($sum -match 'install checks: exit 0') -and ($sum -match 'self-test: Self-test \(requested\): \d+ passed, 0 failed')
    $results += "$m`: $(if ($ok) { 'PASSED' } elseif (-not $done) { "DID NOT FINISH in $Minutes min" } else { 'FAILED' }) in $([int]$w.Elapsed.TotalMinutes) min - $($sum -join ' | ')"
    Say $results[-1]
}
$results | Set-Content "$Out\result.txt" -Encoding UTF8
if ($Cleanup) { Invoke-Cleanup }
