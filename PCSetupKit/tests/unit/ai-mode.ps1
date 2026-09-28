# ai-enabled.ps1: the optional Claude part is on only by choice (setup.ps1 -WithClaude) or for PCs installed before the
# option existed (they all had Messiah). A Claude Code installed on its own never turns hidden Claude runs on.
. "$PSScriptRoot\..\lib.ps1"
$H = "$Work\home"; $C = "$H\.claude"; $P = "$H\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"
function Fresh { Clear-Path $H; New-Item $C, $P, "$H\.local\bin" -ItemType Directory -Force | Out-Null; Copy-Item "$Src\ai-enabled.ps1" $C }
function AI { & "$C\ai-enabled.ps1" }
function Opt { Get-Content "$C\kit-options.txt" -ErrorAction SilentlyContinue }

Section 'recorded choice'
Fresh; 'claude=on' | Set-Content "$C\kit-options.txt"; Check 'claude=on: on' ((AI) -eq $true) ''
'claude=off' | Set-Content "$C\kit-options.txt"; Check 'claude=off: off' ((AI) -eq $false) ''
'  claude = on  ' | Set-Content "$C\kit-options.txt"; Check 'spaces around it are fine' ((AI) -eq $true) ''
'claude=onx' | Set-Content "$C\kit-options.txt"; Check 'anything else counts as off' ((AI) -eq $false) ''

Section 'nothing recorded yet (installed before the option existed, or a brand-new folder)'
Fresh; Check 'no sign of Messiah: off, and recorded' ((AI) -eq $false -and (Opt) -eq 'claude=off') "$(Opt)"
Fresh; 'x' | Set-Content "$H\.local\bin\claude.exe"; Check 'a Claude Code the owner installed on their own does NOT turn it on' ((AI) -eq $false) ''
Fresh; 'x' | Set-Content "$P\Messiah.lnk"; Check 'Messiah shortcut (installed with Claude before): on, and recorded' ((AI) -eq $true -and (Opt) -eq 'claude=on') "$(Opt)"
Fresh; 'x' | Set-Content -LiteralPath "$P\Claude (Admin).lnk"; Check 'the pre-rename shortcut counts too' ((AI) -eq $true) ''
Fresh; 'id' | Set-Content "$C\admin-sessions.txt"; Check 'Messiah sessions were used here: on' ((AI) -eq $true) ''
Fresh; 'x' | Set-Content "$P\Messiah.lnk"; [void](AI); [IO.File]::Delete("$P\Messiah.lnk")
Check 'once recorded, the record decides (removing the shortcut later changes nothing)' ((AI) -eq $true) ''
Finish
