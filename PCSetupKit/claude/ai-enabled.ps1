# Is the optional Claude part (Messiah) turned on for this PC? Prints True or False.
# The kit needs no AI: every tweak, update and maintenance step is a script. Claude is an opt-in extra
# (setup.ps1 -WithClaude), recorded as "claude=on" in kit-options.txt next to this script. It never turns itself on:
# a Claude Code the owner installs on their own does not start hidden Claude runs.
# PCs installed before this option existed all had Messiah: they count as "on" (recorded on the first check).
$f = "$PSScriptRoot\kit-options.txt"
if (-not (Test-Path $f)) {
    $home_ = Split-Path $PSScriptRoot   # the profile this .claude folder belongs to
    $legacy = (Test-Path "$PSScriptRoot\admin-sessions.txt") -or (Test-Path "$PSScriptRoot\Messiah Session.lnk") -or (Test-Path "$home_\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Messiah.lnk") -or
        (Test-Path -LiteralPath "$home_\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Claude (Admin).lnk")
    try { "claude=$(if ($legacy) { 'on' } else { 'off' })" | Set-Content $f -Encoding ASCII } catch {}
    return [bool]$legacy
}
[bool]((Get-Content $f -ErrorAction SilentlyContinue) -match '^\s*claude\s*=\s*on\s*$')
