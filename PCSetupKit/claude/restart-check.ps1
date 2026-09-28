# Restart check for the "Messiah" launcher (PC Setup Kit), run by health-check.ps1.
# Claude never restarts the PC: work that needs a restart (Windows updates, driver installs, files in use) waits for the
# owner's own shutdown/restart. This script makes sure that work really finishes:
# - Before: records what Windows has queued for the next restart (restart-ledger.json) and checks the queue is healthy.
# - After the next restart: checks each recorded item finished; anything that didn't is a WARNING (Claude then fixes it).
# -Canary: also queues a harmless test file for deletion at the next restart, proving the whole chain end to end.
# -BootTime / -Pending: test overrides (simulate a restart without doing one).
# Items accepted as stuck (e.g. a Microsoft component that re-queues its own leftover every boot) can be listed in
# health-ignore.txt: a line matching an item's name or path leaves it out of the check.
param([switch]$Canary, [datetime]$BootTime, [object[]]$Pending, [string]$Ledger = "$PSScriptRoot\restart-ledger.json",
    [string]$IgnoreFile = "$env:USERPROFILE\.claude\health-ignore.txt")
$ErrorActionPreference = 'SilentlyContinue'
$canaryFile = "$PSScriptRoot\restart-canary.txt"

function Get-PendingWork {
    $items = @()
    # Windows Update: updates installed but waiting for a restart to finish
    try {
        $s = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        foreach ($u in @($s.Search('RebootRequired=1').Updates)) { $items += [pscustomobject]@{ Kind = 'update'; Id = $u.Identity.UpdateID; Name = $u.Title } }
    } catch {}
    # Devices whose driver install needs a restart (problem code 14)
    foreach ($d in Get-PnpDevice -PresentOnly | Where-Object { $_.Problem -eq 'CM_PROB_NEED_RESTART' -or $_.ConfigManagerErrorCode -eq 14 }) {
        $items += [pscustomobject]@{ Kind = 'device'; Id = $d.InstanceId; Name = $d.FriendlyName }
    }
    # Windows component packages staged for the restart (servicing stack / cumulative update parts)
    foreach ($p in Get-WindowsPackage -Online | Where-Object PackageState -eq 'InstallPending') {
        $items += [pscustomobject]@{ Kind = 'package'; Id = $p.PackageName; Name = $p.PackageName }
    }
    # Files in use that Windows deletes/replaces at the restart (update leftovers, the canary): pairs of source, target
    $pf = @((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager').PendingFileRenameOperations)
    for ($i = 0; $i + 1 -lt $pf.Count; $i += 2) {
        $src = $pf[$i] -replace '^\*\d+', '' -replace '^\\\?\?\\', ''; if (-not $src) { continue }
        $name = if ($src -eq $canaryFile) { 'restart test file (canary)' } elseif ($pf[$i + 1]) { "replace $(Split-Path $src -Leaf)" } else { "delete $(Split-Path $src -Leaf)" }
        $items += [pscustomobject]@{ Kind = 'file'; Id = $src; Name = $name }
    }
    $items
}

# Things that would stop a restart from finishing the queued work
function Get-QueueProblems {
    $cbs = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    foreach ($svc in 'wuauserv', 'TrustedInstaller', 'msiserver') {
        if ((Get-Service $svc).StartType -eq 'Disabled') { "the $svc service is disabled (the restart can't install updates)" }
    }
    if ($cbs -and -not (Test-Path "$env:WINDIR\WinSxS\pending.xml")) { "Windows says a restart is pending but has nothing staged (WinSxS\pending.xml missing)" }
    $c = Get-PSDrive C; if ($c.Free -lt 10GB) { "only $([int]($c.Free / 1GB)) GB free on C: (updates need room to finish)" }
}

if ($Canary) {
    Add-Type -Namespace RC -Name K -MemberDefinition '[DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool MoveFileEx(string a, string b, int f);'
    "Created $(Get-Date -Format o) to prove that work queued for the next restart gets done. Windows deletes it at the restart." | Set-Content $canaryFile
    # 4 = delete at restart; a plain $null would reach Windows as "" (an invalid rename)
    if ([RC.K]::MoveFileEx($canaryFile, [NullString]::Value, 4)) { 'Restart test: canary queued - Windows deletes it at the next restart' } else { 'Restart test: could not queue the canary' }
}

$boot = if ($BootTime) { $BootTime } else { (Get-CimInstance Win32_OperatingSystem).LastBootUpTime }
$bootKey = $boot.ToString('s')
$ignore = @(Get-Content $IgnoreFile | ForEach-Object { $_.Trim() } | Where-Object { $_ })
function Test-Ignored($it) { foreach ($x in $ignore) { if ("$($it.Name)" -like "*$x*" -or "$($it.Id)" -like "*$x*") { return $true } }; $false }
$now = if ($PSBoundParameters.ContainsKey('Pending')) { @($Pending) } else { @(Get-PendingWork) }
$now = @($now | Where-Object { $_ -and -not (Test-Ignored $_) })
$old = $null; if (Test-Path $Ledger) { try { $old = Get-Content $Ledger -Raw | ConvertFrom-Json -ErrorAction Stop } catch {} }

# A restart happened since the ledger was written: did everything on it finish?
if ($old -and $old.boot -ne $bootKey) {
    # A queued file is done only if it's really gone (Windows drops the queue entry even when the delete fails);
    # everything else is done when it's no longer pending
    $recorded = @($old.items | Where-Object { $_ -and -not (Test-Ignored $_) })
    $left = @($recorded | Where-Object { $o = $_
            if ($o.Kind -eq 'file') { Test-Path -LiteralPath $o.Id } else { $now | Where-Object { $_.Kind -eq $o.Kind -and $_.Id -eq $o.Id } } })
    $done = @($recorded | Where-Object { $_ -notin $left })
    if ($done) { "Restart check: $($done.Count) item(s) Windows had queued finished at the restart ($((@($done | ForEach-Object Name) | Select-Object -First 4) -join '; '))" }
    if ($left) { "WARNING: after the restart these still hadn't finished: $((@($left | ForEach-Object Name)) -join '; ') (Windows retries them at the next restart)" }
    $old = $null
}
# Record what's queued for the next restart (keeps anything recorded earlier during this boot)
if ($now) {
    $items = @($now) + @($old.items | Where-Object { $o = $_; $o -and -not (Test-Ignored $o) -and -not ($now | Where-Object { $_.Kind -eq $o.Kind -and $_.Id -eq $o.Id }) })
    [pscustomobject]@{ boot = $bootKey; recorded = (Get-Date).ToString('o'); items = @($items | Select-Object Kind, Id, Name) } | ConvertTo-Json -Depth 4 | Set-Content "$Ledger.tmp" -Encoding utf8
    Move-Item "$Ledger.tmp" $Ledger -Force
    "Restart check: $($items.Count) item(s) will finish the next time you turn the PC off or restart ($((@($items | ForEach-Object Name) | Select-Object -First 3) -join '; '))"
    $bad = @(Get-QueueProblems); if ($bad) { "WARNING: restart queue problem: $($bad -join '; ')" }
}
elseif (Test-Path $Ledger) { [IO.File]::Delete($Ledger) }
