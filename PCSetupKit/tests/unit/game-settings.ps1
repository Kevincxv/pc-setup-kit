# game-settings.ps1: the owner's tuned game settings (Call of Duty's s.1.0.cod*.txt) kept - a reset by a game patch or
# a new driver is undone, the owner's own changes are kept; the shader reminder after a new graphics driver. A made-up
# settings file in the game's format; nothing real is read or changed.
. "$PSScriptRoot\..\lib.ps1"
$gs = "$Src\game-settings.ps1"
if (-not (Test-Path $gs)) { Skip 'game-settings' 'not installed here'; Finish }
$f = "$Work\s.1.0.cod26.txt"; $st = "$Work\gs.json"; $opt = "$Work\opts.txt"; 'claude=on' | Set-Content $opt
$set = [ordered]@{ ShadowQuality = 'Low'; ParticleQuality = 'low'; SSRQuality = 'Off'; VolumetricQuality = 'QUALITY_LOW'; MotionBlur = 'Off'; VideoMemoryScaleMP = '0.850000'; DLSSModelUI = 'TRANSFORMER'; Volume = '0.800000'; DisplayDriverVersion = '621.01' }
function Write-Cod([hashtable]$over = @{}) {
    $lines = @('// Call of Duty settings', '')
    foreach ($k in $set.Keys) { $v = if ($over.ContainsKey($k)) { $over[$k] } else { $set[$k] }; $lines += "$k@0;$($k.Length * 7);$($k.Length * 13) = $v // one of a, b, c" }
    [IO.File]::WriteAllLines($f, [string[]]$lines)
}
function Val([string]$k) { $l = (Select-String -Path $f -Pattern "^$k@0;").Line; if ($l -match ' = ([^/]*?)\s*(//|$)') { $Matches[1] } }
function Invoke-Gs([string]$Driver = 'd1', [string]$Running = 'no') { @(& $gs -Files $f -State $st -Running $Running -Driver $Driver -Options $opt) }

Section 'keeping the settings'
Write-Cod; $o = Invoke-Gs
Check 'first time: the settings as they are are the ones kept, nothing said' (-not $o -and (Test-Path $st)) "$o"
Write-Cod @{ ShadowQuality = 'Medium' }; $o = Invoke-Gs
Check 'one setting changed (the owner, in the game): kept as it is, nothing said' (-not $o -and (Val ShadowQuality) -eq 'Medium') "$o"
Write-Cod @{ ShadowQuality = 'Very_High'; ParticleQuality = 'high'; SSRQuality = 'High'; VolumetricQuality = 'QUALITY_VERYHIGH'; MotionBlur = 'On'; VideoMemoryScaleMP = '0.700000'; Volume = '1.000000' }
$o = Invoke-Gs
Check 'many changed at once (a reset by a patch or a driver): the tuned ones are back, said' ("$o" -match 'Call of Duty: 6 of your settings had been reset' -and (Val ShadowQuality) -eq 'Medium' -and (Val ParticleQuality) -eq 'low' -and (Val VideoMemoryScaleMP) -eq '0.850000') "$o / shadows $(Val ShadowQuality)"
Check '... sound and the PC''s own details are left as the game wrote them' ((Val Volume) -eq '1.000000') "$(Val Volume)"
Check '... the comments stay, the file before is saved next to it' ((Get-Content $f -Raw) -match 'ShadowQuality@0;\d+;\d+ = Medium // one of a, b, c' -and (Test-Path "$f.before-reset")) ''
Check '... and nothing again at the next check' (-not (Invoke-Gs)) ''
Write-Cod @{ ShadowQuality = 'Very_High'; ParticleQuality = 'high'; SSRQuality = 'High'; VolumetricQuality = 'QUALITY_VERYHIGH'; MotionBlur = 'On' }
$o = Invoke-Gs -Running yes
Check 'the game running: the file is left alone (it writes it when it closes)' (-not $o -and (Val ShadowQuality) -eq 'Very_High') "$o"
'gamesettings=off' | Set-Content $opt; $o = Invoke-Gs
Check 'turned off in Settings: nothing done' (-not $o -and (Val ShadowQuality) -eq 'Very_High') "$o"
'claude=on' | Set-Content $opt; [void](Invoke-Gs)   # (back on: the reset above is undone first)

Section 'a new graphics driver'
$o = Invoke-Gs -Driver 'd2'
Check 'said once: let the game compile its shaders at the main menu' ("$o" -match '^Reminder: new graphics driver \(d2\) - start Call of Duty and let it finish compiling shaders') "$o"
Check '... not again for the same driver' (-not (@(Invoke-Gs -Driver 'd2') -match 'shaders')) ''
Finish
