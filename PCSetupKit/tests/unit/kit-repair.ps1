# kit-repair.ps1: Messiah's own files missing, empty or damaged are put back - from the kit's copy, else the release again.
# Made-up folders under $Work; the reinstall is a stand-in.
. "$PSScriptRoot\..\lib.ps1"
$kr = "$Src\kit-repair.ps1"
if (-not (Test-Path $kr)) { Skip 'kit-repair' 'not installed here'; Finish }
$D = "$Work\cl"; $K = "$Work\kit"; $T = "$Work\tray"
function Fresh {
    foreach ($x in $D, $K, $T) { Clear-Path $x; New-Item $x -ItemType Directory -Force | Out-Null }
    New-Item "$K\claude\tray" -ItemType Directory -Force | Out-Null
    foreach ($n in 'health-check.ps1', 'driver-check.ps1') { '"ok"' | Set-Content "$K\claude\$n"; '"ok"' | Set-Content "$D\$n" }
    foreach ($n in 'setup.ps1', 'tweaks.ps1', 'uninstall.ps1') { '"ok"' | Set-Content "$K\$n" }
    'x := 1' | Set-Content "$K\claude\tray\Messiah Tray.ahk"; 'x := 1' | Set-Content "$T\Messiah Tray.ahk"
    $global:reinst = 0
}
function KR([string]$res = 'PC Setup Kit updated v1 -> v1') { @(& $kr -Dir $D -KitDir $K -Tray $T -Reinstall ([scriptblock]::Create("`$global:reinst++; '$res'"))) }
Fresh; $o = KR
Check 'all there and fine: nothing done, nothing said' (-not $o -and $global:reinst -eq 0) ($o -join ' / ')
[IO.File]::Delete("$D\driver-check.ps1"); [IO.File]::WriteAllText("$D\health-check.ps1", ''); $o = KR
Check 'a missing and an empty script: put back from the kit''s copy, said, no download' ("$o" -match 'Repair: 2 of Messiah''s files .+ put back from the kit' -and (Get-Content "$D\driver-check.ps1") -eq '"ok"' -and $global:reinst -eq 0) ($o -join ' / ')
Fresh; 'if ($x { broken' | Set-Content "$D\health-check.ps1"; $o = KR
Check 'a damaged script (doesn''t parse): put back' ((Get-Content "$D\health-check.ps1") -eq '"ok"') ($o -join ' / ')
Fresh; '"improved by the AI assistant"' | Set-Content "$D\health-check.ps1"; $o = KR
Check 'a script that is only different (improved on purpose): left alone' (-not $o -and (Get-Content "$D\health-check.ps1") -eq '"improved by the AI assistant"') ($o -join ' / ')
Fresh; [IO.File]::Delete("$T\Messiah Tray.ahk"); $o = KR
Check 'the tray''s script missing: put back too' (Test-Path "$T\Messiah Tray.ahk") ($o -join ' / ')
Fresh; [IO.File]::Delete("$K\tweaks.ps1"); $o = KR
Check 'the kit''s own copy damaged: the release is installed again' ($global:reinst -eq 1 -and "$o" -match 'release was installed again') ($o -join ' / ')
Fresh; [IO.File]::Delete("$K\tweaks.ps1"); $o = KR -res 'Kit update: no internet'
Check '... offline: a WARNING, tried again at the next check' ("$o" -match '^WARNING: Messiah''s files tweaks\.ps1 are damaged') ($o -join ' / ')
Fresh; '' | Set-Content "$D\publish-kit.ps1"; [IO.File]::Delete("$D\driver-check.ps1"); $o = KR
Check 'never on the PC the kit is developed on' (-not $o -and -not (Test-Path "$D\driver-check.ps1")) ($o -join ' / ')
Finish
