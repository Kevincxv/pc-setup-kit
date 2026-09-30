# Nothing the kit deletes can ever be someone's own folder: install.ps1 -DownloadOnly never empties a folder with other
# files in it; kit-update.ps1 refuses a kit folder that is empty, relative or a drive root. Nothing is downloaded -
# GitHub is mocked to answer, then the download refuses.
. "$PSScriptRoot\..\lib.ps1"
$root = Split-Path $Kit
Section 'install.ps1 -DownloadOnly'
if (-not (Test-Path "$root\install.ps1")) { Skip 'install.ps1' 'not next to this kit' } else {
    $mine = "$Work\My Documents"; New-Item $mine -ItemType Directory -Force | Out-Null
    'my thesis' | Set-Content "$mine\thesis.docx"
    function Invoke-RestMethod { [pscustomobject]@{ tag_name = 'v2099.01.01' } }
    function Invoke-WebRequest { throw 'no downloads in this test' }
    $o = try { & "$root\install.ps1" -DownloadOnly $mine 2>&1 | Out-String } catch { "$_" }
    Check 'a folder with someone''s files: refused, the files still there' ((Test-Path "$mine\thesis.docx") -and "$o" -match 'already holds other files') $o
    $own = "$Work\dl"; New-Item "$own\x" -ItemType Directory -Force | Out-Null; 'zip' | Set-Content "$own\kit.zip"
    $o = try { & "$root\install.ps1" -DownloadOnly $own 2>&1 | Out-String } catch { "$_" }
    Check '... its own earlier download: cleared and downloaded again (here: the mocked download refuses)' (-not (Test-Path "$own\kit.zip") -and "$o" -match 'no downloads in this test') $o
    Remove-Item Function:\Invoke-RestMethod, Function:\Invoke-WebRequest
}
Section 'kit-update.ps1 with a bad kit folder'
foreach ($bad in 'C:\', 'C:', 'relative\kit') {
    $o = @(& "$Src\kit-update.ps1" -KitDir $bad -ClaudeDir "$Work\cl" -Force 2>&1 | ForEach-Object { "$_" })
    Check "kit folder '$bad': refused before anything else" ("$o" -match '^Kit update: refused') ($o -join ' / ')
}
Finish
