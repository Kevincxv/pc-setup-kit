# Messiah's own files, checked (run by the maintenance and the 4-hourly check - each repairs the other): a script that is
# missing, empty or damaged (doesn't parse - an antivirus that quarantined it, a disk error, a half-written file) is put
# back. From the kit's own copy in C:\PCSetupKit when that one is fine (instant, offline), else the release is installed
# again (kit-update.ps1 -Reinstall). A script that is only DIFFERENT is left alone: the AI assistant may have improved
# it on purpose. Not on the PC the kit is developed on (there the live scripts are the source of truth).
# -Dir / -KitDir / -Tray: tests (-Reinstall: a stand-in for kit-update.ps1 -Reinstall).
param([string]$Dir = $PSScriptRoot, [string]$KitDir = 'C:\PCSetupKit', [string]$Tray = "$env:USERPROFILE\Documents\Messiah Tray", [scriptblock]$Reinstall)
$ErrorActionPreference = 'SilentlyContinue'
if (Test-Path "$Dir\publish-kit.ps1") { return }   # the kit's own PC
if (-not (Test-Path "$KitDir\claude")) { return }   # not installed from the kit (nothing to compare with)
function Test-Good([string]$f) {
    $i = Get-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
    if (-not $i -or $i.Length -eq 0) { return $false }
    if ($i.Extension -ne '.ps1') { return $true }
    $e = $null; [void][Management.Automation.Language.Parser]::ParseFile($i.FullName, [ref]$null, [ref]$e); -not $e
}
# what should be there: every maintenance script of the kit (in .claude), the kit's own scripts, and the tray
$pairs = @(Get-ChildItem "$KitDir\claude\*.ps1" -File | ForEach-Object { , @($_.FullName, "$Dir\$($_.Name)") }) +
    @('setup.ps1', 'tweaks.ps1', 'uninstall.ps1' | ForEach-Object { , @($null, "$KitDir\$_") }) +
    @(if (Test-Path "$KitDir\claude\tray\Messiah Tray.ahk") { , @("$KitDir\claude\tray\Messiah Tray.ahk", "$Tray\Messiah Tray.ahk") })
$fixed = @(); $download = @()
foreach ($p in $pairs) {
    if (Test-Good $p[1]) { continue }
    if ($p[0] -and (Test-Good $p[0])) {
        try { New-Item (Split-Path $p[1]) -ItemType Directory -Force | Out-Null; Copy-Item -LiteralPath $p[0] $p[1] -Force -ErrorAction Stop; $fixed += Split-Path $p[1] -Leaf } catch { $download += Split-Path $p[1] -Leaf }
    } else { $download += Split-Path $p[1] -Leaf }
}
if ($fixed) { "Repair: $($fixed.Count) of Messiah's files were missing or damaged ($($fixed -join ', ')) - put back from the kit" }
if ($download) {
    $r = @(if ($Reinstall) { & $Reinstall } else { & "$Dir\kit-update.ps1" -KitDir $KitDir -ClaudeDir $Dir -Reinstall -Force })
    if ($r -match '^PC Setup Kit updated|installed') { "Repair: $($download -join ', ') damaged in the kit itself too - the release was installed again" }
    else { "WARNING: Messiah's files $($download -join ', ') are damaged and couldn't be put back yet ($(@($r)[-1])) - tried again at the next check" }
}
