# The NVIDIA app's driver downloads, kept unstuck (10/25, the owner: "in my NVIDIA app the driver seems to be stuck at
# 100% - how can we prevent that from happening again"). The app keeps each download's progress in
# UpdateFramework\status\<component>\*.json. A blue screen or a power cut while it writes one leaves it as zero bytes
# (9/26 and 10/21 - both times at a 0x109 crash), and from then on the app shows that download stuck at 100% forever.
# At every check (health-check.ps1):
# - a damaged status file (nothing but zero bytes, or not JSON): that component starts over - the NVIDIA app closed, its
#   service restarted, the component's status files and downloads removed; the app downloads again by itself
# - finished driver downloads for versions already installed (or older, ~800 MB each), 3+ days old: removed the same way
#   (only when nothing newer is waiting to be installed)
# Never while a game runs or the NVIDIA app's window is open (then at the next check).
# -Root / -Installed / -TestGame / -NoProcess / -Now: tests (a made-up folder; nothing is stopped or started).
param([string]$Root = "$env:ProgramData\NVIDIA Corporation\NVIDIA app\UpdateFramework", [string]$Installed, [string]$TestGame, [switch]$NoProcess, [datetime]$Now = (Get-Date))
$ErrorActionPreference = 'SilentlyContinue'
if (-not (Test-Path "$Root\status")) { return }
function Broken([IO.FileInfo]$f) {
    if ($f.Length -eq 0) { return $false }
    $b = [IO.File]::ReadAllBytes($f.FullName)
    if (-not ($b | Where-Object { $_ -ne 0 } | Select-Object -First 1)) { return $true }   # (all zero bytes)
    try { $null = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json -ErrorAction Stop; $false } catch { $true }
}
function Ver([string]$v) { $x = $null; if ([version]::TryParse(($v -replace '[^\d.]', ''), [ref]$x)) { $x } }

# what to reset: components with a damaged status file, and a driver component whose downloads are all installed already
$reset = @{}
foreach ($f in Get-ChildItem "$Root\status" -Recurse -File -Filter *.json) { if (Broken $f) { $reset[$f.Directory.Name] = 'damaged' } }
$inst = Ver $(if ($Installed) { $Installed } else { "$(& nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>$null | Select-Object -First 1)".Trim() })
foreach ($comp in Get-ChildItem "$Root\status" -Directory | Where-Object { $_.Name -notin $reset.Keys }) {
    $dl = try { @(Get-Content "$($comp.FullName)\download.json" -Raw | ConvertFrom-Json -ErrorAction Stop | ForEach-Object { $_ }) } catch { @() }
    $done = @($dl | Where-Object { $_.version -and $_.fileLocation })
    if (-not $done -or -not $inst) { continue }
    $pending = @($done | Where-Object { (Ver $_.version) -gt $inst })
    $old = @($done | Where-Object { (Test-Path -LiteralPath $_.fileLocation) -and (Get-Item -LiteralPath $_.fileLocation).LastWriteTime -lt $Now.AddDays(-3) })
    if (-not $pending -and $old) { $reset[$comp.Name] = "$([Math]::Round((($old | ForEach-Object { (Get-Item -LiteralPath $_.fileLocation).Length } | Measure-Object -Sum).Sum) / 1GB, 1)) GB" }
}
if (-not $reset.Count) { return }

# never under a game, never under the owner's open NVIDIA app
$game = if ($PSBoundParameters.ContainsKey('TestGame')) { $TestGame } else { & "$PSScriptRoot\game-check.ps1" }
if ($game) { return }
if (-not $NoProcess -and (Get-Process 'NVIDIA App' | Where-Object { $_.MainWindowHandle -ne 0 })) { return }

if (-not $NoProcess) { Get-Process 'NVIDIA App' | Stop-Process -Force; Stop-Service NvContainerLocalSystem -Force; Start-Sleep 2 }
try {
    foreach ($c in $reset.Keys) {
        foreach ($f in Get-ChildItem "$Root\status\$c" -File) { try { [IO.File]::Delete($f.FullName) } catch { } }   # ([IO] - paths with spaces)
        if (Test-Path "$Root\ota-artifacts\$c") { try { [IO.Directory]::Delete("$Root\ota-artifacts\$c", $true) } catch { } }
    }
}
finally { if (-not $NoProcess) { Start-Service NvContainerLocalSystem } }
foreach ($c in $reset.Keys) {
    $what = if ($c -eq 'grd') { 'driver download' } elseif ($c -eq 'nvapp') { 'own update' } else { "$c download" }
    if ($reset[$c] -eq 'damaged') { "NVIDIA app: its $what was stuck (a status file damaged - by a crash or a power cut while it was writing) - reset; it downloads again by itself" }
    else { "NVIDIA app: removed its finished driver downloads already installed ($($reset[$c]))" }
}
