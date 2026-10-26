# nvidia-app-check.ps1: the NVIDIA app's downloads kept unstuck - a status file a crash left as zero bytes, and finished
# driver downloads already installed. A made-up UpdateFramework folder; nothing is stopped or started.
. "$PSScriptRoot\..\lib.ps1"
$nc = "$Src\nvidia-app-check.ps1"
if (-not (Test-Path $nc)) { Skip 'nvidia-app-check' 'not installed here'; Finish }
$R = "$Work\UpdateFramework"
function New-Fake([string]$newest = '621.01', [int]$age = 5, [switch]$Damaged) {
    if (Test-Path $R) { Remove-Item $R -Recurse -Force }
    New-Item "$R\status\grd", "$R\status\nvapp" -ItemType Directory -Force | Out-Null
    $dl = foreach ($v in '617.42', $newest) {
        $f = "$R\ota-artifacts\grd\t$($v -replace '\.', '')\$v-desktop.exe"; New-Item (Split-Path $f) -ItemType Directory -Force | Out-Null
        $s = [IO.File]::Create($f); $s.SetLength(5MB); $s.Close(); (Get-Item $f).LastWriteTime = (Get-Date).AddDays(-$age)
        @{ state = 8; percentComplete = 100.0; version = $v; fileLocation = $f }
    }
    ConvertTo-Json -InputObject @($dl) | Set-Content "$R\status\grd\download.json"
    if ($Damaged) { [IO.File]::WriteAllBytes("$R\status\grd\postprocessing.json", (New-Object byte[] 1747)) } else { '[]' | Set-Content "$R\status\grd\postprocessing.json" }
    '[{"componentName":"nvapp","updateState":1}]' | Set-Content "$R\status\nvapp\autoupdate.json"
}
function Run([string]$game = '') { @(& $nc -Root $R -Installed '621.01' -TestGame $game -NoProcess) }

Section 'a status file a crash left as zero bytes (10/21: stuck at 100%)'
New-Fake -Damaged -age 0
$o = Run 'cod'
Check 'while a game runs: left for the next check' ((Test-Path "$R\status\grd\postprocessing.json") -and -not $o) "$o"
$o = Run
Check 'reset: the driver component''s status and downloads gone, said why' (-not (Test-Path "$R\status\grd\postprocessing.json") -and -not (Test-Path "$R\status\grd\download.json") -and -not (Test-Path "$R\ota-artifacts\grd") -and "$o" -match '^NVIDIA app: its driver download was stuck \(a status file damaged') "$o"
Check '... the app''s other parts untouched' (Test-Path "$R\status\nvapp\autoupdate.json") ''
Check 'nothing wrong: says nothing' (-not (Run)) ''

Section 'finished driver downloads already installed'
New-Fake -age 5
$o = Run
Check 'installed already and 3+ days old: removed, with the size' (-not (Test-Path "$R\ota-artifacts\grd") -and "$o" -match '^NVIDIA app: removed its finished driver downloads already installed \(0 GB\)') "$o"
New-Fake -age 1
Check 'only a day old: kept for now' (-not (Run) -and (Test-Path "$R\ota-artifacts\grd")) ''
New-Fake -newest '622.10' -age 5
Check 'a newer driver waiting to be installed: nothing touched' (-not (Run) -and (Test-Path "$R\status\grd\download.json") -and (Test-Path "$R\ota-artifacts\grd\t62210")) ''
Finish
