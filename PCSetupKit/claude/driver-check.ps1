# Driver check for the "Messiah" launcher. Runs elevated.
# - NVIDIA GPU: compares the installed driver with the NVIDIA app's latest Game Ready recommendation;
#   downloads and silently installs it if newer.
# - Everything else (AMD chipset, Realtek audio, MediaTek Wi-Fi/BT, SteelSeries, Logitech...):
#   installs any pending driver updates from Windows Update.
# Prints one line per finding; "REBOOT" in the output means a restart is needed to finish.
$ErrorActionPreference = 'Continue'

# --- NVIDIA ---
# (PCs without an NVIDIA card - AMD/Intel graphics - skip this silently; a missing nvidia-smi used to throw an error
#  whose "failed" woke /maintain at every login)
if (Get-CimInstance Win32_VideoController | Where-Object Name -match 'NVIDIA') { try {
    $installed = & nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>$null | Select-Object -First 1
    $installed = if ($installed) { "$installed".Trim() }
    $recFile = "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA app\NvBackend\DriverRecommendations.dat"
    if (-not $installed) {
        'NVIDIA: could not read installed driver version (nvidia-smi failed)'
    } elseif (-not (Test-Path $recFile)) {
        "NVIDIA: $installed installed; no NVIDIA app recommendation file to compare against"
    } else {
        $rec = (Get-Content $recFile -Raw | ConvertFrom-Json)
        $latest = $rec.updates | Where-Object { -not $_.isBeta -and $_.driverType -eq 0 } | Select-Object -First 1
        $age = [int]((Get-Date).ToUniversalTime() - [datetime]$rec.checkTime).TotalDays
        if (-not $latest) {
            "NVIDIA: $installed (no Game Ready recommendation found)"
        } elseif ([version]$latest.version -le [version]$installed) {
            "NVIDIA: $installed is up to date" + $(if ($age -gt 3) { " (NVIDIA app last checked $age days ago)" })
        } else {
            if ($g = & "$PSScriptRoot\game-check.ps1") { "NVIDIA: $($latest.version) is available - install held while $g is running (next check)"; throw 'held' }
            "NVIDIA: updating $installed -> $($latest.version)..."
            $exe = Join-Path $env:TEMP ([IO.Path]::GetFileName($latest.downloadURL))
            if (-not (Test-Path $exe)) {
                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest $latest.downloadURL -OutFile $exe -UseBasicParsing
            }
            $sig = Get-AuthenticodeSignature $exe
            if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'NVIDIA') {
                "NVIDIA: download failed signature check - not installing"
            } else {
                $p = Start-Process $exe -ArgumentList '-s -noreboot -noeula' -Wait -PassThru
                if ($p.ExitCode -eq 0) { "NVIDIA: installed $($latest.version)" } else { "NVIDIA: installer exit code $($p.ExitCode)" }
                Remove-Item $exe -Force -ErrorAction SilentlyContinue
            }
        }
    }
} catch { if ("$_" -ne 'held') { "NVIDIA: check failed - $($_.Exception.Message)" } } }

# --- Windows Update drivers ---
try {
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $result = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Driver'")
    # A driver that already failed to install (e.g. for a disabled device) would retry forever: hide it instead
    $failed = @($searcher.QueryHistory(0, [Math]::Min(200, $searcher.GetTotalHistoryCount())) | Where-Object { $_.ResultCode -in 4, 5 } | ForEach-Object Title)
    # A driver version driver-guard.ps1 rolled back after a blue screen ("provider|yyyy-MM-dd|version|inf" lines) is
    # hidden too, instead of coming back (Windows Update shows a driver's provider and date, not its version)
    $blocked = @(Get-Content "$PSScriptRoot\driver-blocklist.txt" -ErrorAction SilentlyContinue | Where-Object { $_ -match '\|' } | ForEach-Object { $p = $_ -split '\|'; "$($p[0])|$($p[1])" })
    foreach ($u in @($result.Updates)) {
        if ($failed -contains $u.Title) { $u.IsHidden = $true; "Driver: '$($u.Title)' failed before - hidden so it stops retrying" }
        elseif ($blocked -contains "$($u.DriverProvider)|$(try { ([datetime]$u.DriverVerDate).ToString('yyyy-MM-dd') } catch {})") {
            $u.IsHidden = $true; "Driver: '$($u.Title)' was rolled back after a blue screen - hidden so it isn't installed again"
        }
    }
    $result = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Driver'")
    if ($result.Updates.Count -eq 0) {
        'Other drivers: all up to date (Windows Update)'
    } elseif ($g = & "$PSScriptRoot\game-check.ps1") {
        "Other drivers: $($result.Updates.Count) update(s) available - held while $g is running (next check)"
    } else {
        $coll = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $result.Updates) { if (-not $u.EulaAccepted) { $u.AcceptEula() }; [void]$coll.Add($u) }
        $dl = $session.CreateUpdateDownloader(); $dl.Updates = $coll; [void]$dl.Download()
        $inst = $session.CreateUpdateInstaller(); $inst.Updates = $coll; $res = $inst.Install()
        for ($i = 0; $i -lt $coll.Count; $i++) {
            $ok = $res.GetUpdateResult($i).ResultCode -eq 2
            "Driver: $($coll.Item($i).Title) - $(if ($ok) { 'installed' } else { 'FAILED' })"
        }
        if ($res.RebootRequired) { 'REBOOT required to finish driver installs' }
    }
} catch { "Other drivers: Windows Update check failed - $($_.Exception.Message)" }
