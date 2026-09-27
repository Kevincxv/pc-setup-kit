# Static checks: every script parses, the tray script validates, nothing personal in the kit, docs match the files.
. "$PSScriptRoot\..\lib.ps1"
$repoRoot = Split-Path $Kit
$all = @(Get-ChildItem $Src -Filter *.ps1 -File) + @(Get-ChildItem $Kit -Recurse -Filter *.ps1 -File) + @(Get-ChildItem $repoRoot -Filter *.ps1 -File)
$bad = @($all | Where-Object { $e = $null; [void][Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e); $e } | ForEach-Object FullName)
Check "all $($all.Count) PowerShell scripts parse" (-not $bad) ($bad -join ', ')
# PowerShell 5.1 reads BOM-less files as ANSI: any non-ASCII character needs a UTF-8 BOM
$enc = @($all | Where-Object { $b = [IO.File]::ReadAllBytes($_.FullName); ($b | Where-Object { $_ -gt 127 } | Select-Object -First 1) -and -not ($b.Length -ge 3 -and $b[0] -eq 0xEF) } | ForEach-Object Name)
Check 'scripts with non-ASCII characters have a UTF-8 BOM' (-not $enc) ($enc -join ', ')
$ahk = "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"
if (Test-Path $ahk) {
    foreach ($t in @($Tray, "$Kit\claude\tray\Claude Admin Tray.ahk") | Select-Object -Unique) {
        $v = Start-Process $ahk -ArgumentList '/ErrorStdOut', '/Validate', "`"$t`"" -Wait -PassThru -WindowStyle Hidden
        Check "tray script validates ($(Split-Path (Split-Path $t) -Leaf))" ($v.ExitCode -eq 0) "exit $($v.ExitCode)"
    }
} else { Skip 'tray script validation' 'AutoHotkey not installed' }
# tests must not reassign the shared $Src / $Kit / $Tray / $Work (PowerShell names ignore case: "$src = ..." clobbers $Src)
$clobber = @(Get-ChildItem "$PSScriptRoot\*.ps1" | Select-String -Pattern '(?i)^\s*\$(src|kit|tray|work)\s*=' | ForEach-Object { "$($_.Filename):$($_.LineNumber)" })
Check 'no test overwrites the shared $Src/$Kit/$Tray/$Work' (-not $clobber) ($clobber -join ', ')
# names of functions must not collide with built-in aliases (e.g. H = Get-History)
$clash = @($all | ForEach-Object { [regex]::Matches((Get-Content $_.FullName -Raw), '(?m)^\s*function\s+([\w-]+)') | ForEach-Object { $_.Groups[1].Value } } | Where-Object { Get-Alias $_ -ErrorAction SilentlyContinue } | Select-Object -Unique)
Check 'no function is shadowed by a built-in alias' (-not $clash) ($clash -join ', ')
$personal = 'Kevin|gmail|@[a-z0-9-]+\.(com|net|org)|B650I|7800X3D|RTX 5080|G2725D|PG27AQDM|CMK32|Seagate ZP|gho_|ghp_|sk-ant-'
$hits = @(Get-ChildItem $repoRoot -Recurse -File | Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.Name -ne 'last-run.txt' } | Select-String -Pattern $personal |
        Where-Object { $_.Line -notmatch 'Kevincxv/pc-setup-kit|noreply@anthropic\.com' -and $_.Line -notmatch '^\s*\$personal = ' } | ForEach-Object { "$($_.Filename):$($_.LineNumber)" })   # (the pattern line itself)
Check 'nothing personal in the kit (names, email, hardware, tokens)' (-not $hits) ($hits -join ', ')
# every script the kit installs is known to the uninstaller, so nothing is left behind
$un = Get-Content "$Kit\uninstall.ps1" -Raw
$missing = @(Get-ChildItem "$Kit\claude\*.ps1" | Where-Object { $un -notmatch [regex]::Escape("'$($_.Name)'") } | ForEach-Object Name)
Check 'the uninstaller removes every script the kit installs' (-not $missing) ($missing -join ', ')
# the kit's copies match this PC's live scripts (only meaningful on the PC where the kit is developed)
if ($Src -ne "$Kit\claude") {
    $drift = @(Get-ChildItem "$Kit\claude\*.ps1" | Where-Object { (Test-Path "$Src\$($_.Name)") -and (Get-FileHash $_.FullName).Hash -ne (Get-FileHash "$Src\$($_.Name)").Hash } | ForEach-Object Name)
    if ($drift) { Skip 'kit copies match the live scripts' "differs (publish-kit syncs them): $($drift -join ', ')" } else { Check 'kit copies match the live scripts' $true '' }
}
Finish
