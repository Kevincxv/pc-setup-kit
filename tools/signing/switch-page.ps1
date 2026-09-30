# The install page switched to the signed installer - run by sign.yml once a release carries a signed
# Install-Messiah.exe. The button then downloads it from the latest release (Windows opens it without a
# "Windows protected your PC" warning), and the "applied for" wording goes. Safe to run again: prints "changed" or
# "unchanged". The .cmd stays in docs\ for old links. -Docs: tests.
param([string]$Docs = (Join-Path $PSScriptRoot '..\..\docs'))
$exe = 'https://github.com/Kevincxv/pc-setup-kit/releases/latest/download/Install-Messiah.exe'
$changed = $false
function Edit-File($name, [hashtable]$pairs) {
    $p = Join-Path $Docs $name; $s = [IO.File]::ReadAllText($p); $o = $s
    foreach ($k in $pairs.Keys) { $s = $s.Replace($k, $pairs[$k]) }
    if ($s -ne $o) { [IO.File]::WriteAllText($p, $s, (New-Object Text.UTF8Encoding $false)); $script:changed = $true }
}
Edit-File 'index.html' @{
    'href="Install%20PC%20Setup%20Kit.cmd" download' = "href=`"$exe`""
    'This shows up because the file isn''t code-signed yet: the project has applied for free code signing by the <a href="https://signpath.org">SignPath Foundation</a> (<a href="code-signing.html">code signing policy</a>).' = 'It shouldn''t: the installer is code-signed (free code signing provided by SignPath.io, certificate by the <a href="https://signpath.org">SignPath Foundation</a> - <a href="code-signing.html">code signing policy</a>).'
}
Edit-File 'code-signing.html' @{ ' (applied for; until it is granted the installer is not signed)' = '' }
if ($changed) { 'changed' } else { 'unchanged' }
