# Static checks: every script parses, the tray script validates, nothing personal in the kit, docs match the files.
. "$PSScriptRoot\..\lib.ps1"
$repoRoot = Split-Path $Kit
# only the kit's own repo (here, or GitHub's checkout) - on an installed PC the kit sits in C:\PCSetupKit and its parent is C:\
$inRepo = Test-Path "$repoRoot\.git"
$all = @(Get-ChildItem $Src -Filter *.ps1 -File) + @(Get-ChildItem $Kit -Recurse -Filter *.ps1 -File) + @(if ($inRepo) { Get-ChildItem $repoRoot -Filter *.ps1 -File })
$bad = @($all | Where-Object { $e = $null; [void][Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e); $e } | ForEach-Object FullName)
Check "all $($all.Count) PowerShell scripts parse" (-not $bad) ($bad -join ', ')
# PowerShell 5.1 reads BOM-less files as ANSI: any non-ASCII character needs a UTF-8 BOM
$enc = @($all | Where-Object { $b = [IO.File]::ReadAllBytes($_.FullName); ($b | Where-Object { $_ -gt 127 } | Select-Object -First 1) -and -not ($b.Length -ge 3 -and $b[0] -eq 0xEF) } | ForEach-Object Name)
Check 'scripts with non-ASCII characters have a UTF-8 BOM' (-not $enc) ($enc -join ', ')
$ahk = "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"
if (Test-Path $ahk) {
    foreach ($t in @($Tray, "$Kit\claude\tray\Messiah Tray.ahk") | Select-Object -Unique) {
        $v = Start-Process $ahk -ArgumentList '/ErrorStdOut', '/Validate', "`"$t`"" -Wait -PassThru -WindowStyle Hidden
        Check "tray script validates ($(Split-Path (Split-Path $t) -Leaf))" ($v.ExitCode -eq 0) "exit $($v.ExitCode)"
    }
} else { Skip 'tray script validation' 'AutoHotkey not installed' }
# PCs updating from before the rename to Messiah get the tray through the old updater, under the old name (migrate-names.ps1)
$compat = "$Kit\claude\tray\Claude Admin Tray.ahk"
Check 'the old-name tray copy is identical to Messiah Tray.ahk' ((Test-Path $compat) -and (Get-FileHash $compat).Hash -eq (Get-FileHash "$Kit\claude\tray\Messiah Tray.ahk").Hash) ''
# tests must not reassign the shared $Src / $Kit / $Tray / $Work (PowerShell names ignore case: "$src = ..." clobbers $Src)
$clobber = @(Get-ChildItem "$PSScriptRoot\*.ps1" | Select-String -Pattern '(?i)^\s*\$(src|kit|tray|work|hook)\s*=' | ForEach-Object { "$($_.Filename):$($_.LineNumber)" })
Check 'no test overwrites the shared $Src/$Kit/$Tray/$Work' (-not $clobber) ($clobber -join ', ')
# tests that mock a command from a Windows module must load the module first and verify the mock (see lib.ps1)
$unsafe = @(foreach ($tf in Get-ChildItem "$PSScriptRoot\*.ps1") {
        $txt = Get-Content $tf.FullName -Raw
        foreach ($m in [regex]::Matches($txt, '(?m)^\s*function\s+(?:global:)?([\w-]+)')) {
            $n = $m.Groups[1].Value
            if (-not (Get-Command $n -All -ErrorAction SilentlyContinue | Where-Object { $_.ModuleName -and $_.ModuleName -notmatch '^Microsoft\.PowerShell\.(Management|Utility)$' })) { continue }
            $imp = $txt.IndexOf('Import-MockTargets'); $as = $txt.LastIndexOf('Assert-Mocks')
            if ($imp -lt 0 -or $imp -gt $m.Index -or $as -lt $m.Index) { "$($tf.Name): $n" }
        } })
Check 'every module-command mock is loaded first and verified (Import-MockTargets / Assert-Mocks)' (-not $unsafe) ($unsafe -join ', ')
# names of functions must not collide with built-in aliases (e.g. H = Get-History)
$clash = @($all | ForEach-Object { [regex]::Matches((Get-Content $_.FullName -Raw), '(?m)^\s*function\s+([\w-]+)') | ForEach-Object { $_.Groups[1].Value } } | Where-Object { Get-Alias $_ -ErrorAction SilentlyContinue } | Select-Object -Unique)
Check 'no function is shadowed by a built-in alias' (-not $clash) ($clash -join ', ')
# only where the kit is published from (the repo) or in CI - an installed PC's kit folder holds its own setup log etc.
if ($inRepo) {
    $personal = 'Kevin|gmail|@[a-z0-9-]+\.(com|net|org)|B650I|7800X3D|RTX 5080|G2725D|PG27AQDM|CMK32|Seagate ZP|gho_|ghp_|sk-ant-'
    $hits = @(Get-ChildItem $repoRoot -Recurse -File | Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.Name -ne 'last-run.txt' } | Select-String -Pattern $personal |
            Where-Object { $_.Line -notmatch 'Kevincxv/pc-setup-kit|kevincxv\.github\.io/pc-setup-kit|noreply@anthropic\.com' -and $_.Line -notmatch '^\s*\$personal = ' } | ForEach-Object { "$($_.Filename):$($_.LineNumber)" })   # (the pattern line itself)
    Check 'nothing personal in the kit (names, email, hardware, tokens)' (-not $hits) ($hits -join ', ')
    # the install page (GitHub Pages, docs\): its download buttons point at files that run the real one-line installer
    $page = Get-Content "$repoRoot\docs\index.html" -Raw -ErrorAction SilentlyContinue
    $links = @([regex]::Matches("$page", 'href="([^"]+\.cmd)" download') | ForEach-Object { [uri]::UnescapeDataString($_.Groups[1].Value) })
    $bad = @($links | Where-Object { $f = "$repoRoot\docs\$_"; -not (Test-Path $f) -or (Get-Content $f -Raw) -notmatch 'raw\.githubusercontent\.com/Kevincxv/pc-setup-kit/main/install\.ps1' -or [IO.File]::ReadAllText($f) -match '[^\r]\n' })
    Check 'install page: both download buttons (without / with Messiah) lead to CRLF batch files running install.ps1' ($links.Count -eq 2 -and -not $bad -and ($links -match 'Messiah').Count -eq 1 -and (Get-Content "$repoRoot\docs\$($links -match 'Messiah')" -Raw) -match '-WithClaude') "links: $($links -join ', '); bad: $($bad -join ', ')"
} else { Skip 'nothing personal in the kit' 'checked where the kit is published from' }
# scratch files belong in $Work: anything else in the tests folder's root gets published with the kit (9/27: '-report.txt' was)
$stray = @(Get-ChildItem -LiteralPath (Split-Path $PSScriptRoot) -File | Where-Object { $_.Name -notin 'lib.ps1', 'run-tests.ps1', 'last-run.txt' } | ForEach-Object Name)
Check 'no stray files in the tests folder' (-not $stray) ($stray -join ', ')
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
