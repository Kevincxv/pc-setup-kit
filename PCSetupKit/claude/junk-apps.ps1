# What came with the PC and only gets in the way (run weekly by periodic-maint.ps1 and by optimize.ps1):
# - plain junk (game offers, browser add-ons, promo shortcuts) is uninstalled by itself, silently, once: an app the
#   owner installs again afterwards is theirs and stays
# - trial antivirus and VPNs (someone may have paid for them) are a to-do item with a one-click Uninstall in the app
#   (-Remove '<name>': runs that app's own uninstaller, visibly). A trial antivirus that expires leaves the PC
#   unprotected while Microsoft Defender, free and built in, stays switched off
# - hardware tools (RGB, fans, the maker's control centre) are never touched
# State: junk-state.json (what it removed). -Test (hashtable: Apps = @(@{ DisplayName; QuietUninstallString;
# UninstallString }), Gone = names gone after an uninstall) with -Do, -State: tests.
param([hashtable]$Test, [scriptblock]$Do, [string]$State = "$PSScriptRoot\junk-state.json", [string]$Remove)
$ErrorActionPreference = 'SilentlyContinue'
$T = $Test
if ($env:PCKIT_IN_TESTS -and -not $T) { return }   # never from the test suite
function Act([string]$What, [scriptblock]$Real) { if ($Do) { & $Do $What } else { & $Real } }
$junk = 'WildTangent|McAfee WebAdvisor|Dropbox Promotion|Dropbox 25 ?GB|Booking\.com|Acer Jumpstart|Acer Collection|Norton Safe Web|Avast Secure Browser Setup'
$ask = '\b(McAfee|Norton (360|Security|AntiVirus|Internet Security|Utilities)|Avast (Free|Premium|One|Antivirus)|AVG (AntiVirus|Internet Security|TuneUp)|ExpressVPN|Keeper Password Manager)'   # (after $junk: WebAdvisor etc. are plain junk)
$uninst = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
$script:ran = @()   # (tests: the apps whose uninstaller ran - those in Gone are gone afterwards)
function Get-Apps { if ($T) { @($T.Apps | Where-Object { -not ($_.DisplayName -in @($T.Gone) -and $_.DisplayName -in $script:ran) } | ForEach-Object { [pscustomobject]$_ }) } else { @(Get-ItemProperty $uninst | Where-Object { $_.DisplayName -and -not $_.SystemComponent -and -not $_.ParentKeyName }) } }
$st = try { Get-Content $State -Raw -ErrorAction Stop | ConvertFrom-Json } catch { [pscustomobject]@{} }
if (-not ($st.PSObject.Properties.Name -contains 'removed')) { $st | Add-Member removed @() }

# one app's uninstaller: silent for junk (its quiet command, msiexec /x, or winget), visible for -Remove
function Uninstall($a, [switch]$Visible) {
    $n = $a.DisplayName; $script:ran += $n
    if ($Visible) { Act "uninstall (visible) $n" { $c = "$($a.UninstallString)"; if ($c -match '(?i)msiexec.*?(\{[0-9A-F-]+\})') { Start-Process msiexec.exe "/x $($Matches[1])" -Wait } elseif ($c -match '^"([^"]+)"\s*(.*)$') { Start-Process $Matches[1] $Matches[2] -Wait } elseif ($c) { Start-Process cmd.exe "/c `"$c`"" -Wait } }; return }
    Act "uninstall $n" {
        $q = "$($a.QuietUninstallString)"; $c = "$($a.UninstallString)"
        if ($q) { Start-Process cmd.exe "/c `"$q`"" -WindowStyle Hidden -Wait }
        elseif ($c -match '(?i)msiexec.*?(\{[0-9A-F-]+\})') { Start-Process msiexec.exe "/x $($Matches[1]) /qn /norestart" -WindowStyle Hidden -Wait }
        else { $null = winget uninstall --name $n --exact --silent --accept-source-agreements --disable-interactivity 2>&1 }
    }
}

if ($Remove) {   # the app's Uninstall button: that app's own uninstaller, visibly
    $a = Get-Apps | Where-Object DisplayName -eq $Remove | Select-Object -First 1
    if (-not $a) { return "$Remove isn't installed any more" }
    Uninstall $a -Visible
    if (-not (Get-Apps | Where-Object DisplayName -eq $Remove)) { & "$PSScriptRoot\todo.ps1" -Id "junk-$(($Remove -replace '\W', '').ToLower())" -Done; "Removed $Remove" } else { "$Remove is still installed (its uninstaller was closed?)" }
    return
}

$apps = Get-Apps
$removed = @()
foreach ($a in $apps | Where-Object { $_.DisplayName -match $junk }) {
    if ($a.DisplayName -in @($st.removed)) { continue }   # removed before and back: the owner installed it
    Uninstall $a
    if (-not (Get-Apps | Where-Object DisplayName -eq $a.DisplayName)) { $removed += $a.DisplayName }
}
if ($removed) {
    $st.removed = @(@($st.removed) + $removed | Select-Object -Unique); try { $st | ConvertTo-Json -Depth 3 | Set-Content $State -Encoding UTF8 } catch {}
    "Removed what came with the PC and gets in the way: $($removed -join ', ')"
}
$trials = @($apps | Where-Object { $_.DisplayName -match $ask -and $_.DisplayName -notmatch $junk } | ForEach-Object DisplayName | Sort-Object -Unique)
$ids = @()
foreach ($n in $trials) {
    $id = "junk-$(($n -replace '\W', '').ToLower())"; $ids += $id
    $av = $n -match 'McAfee|Norton|Avast|AVG'
    $why = if ($av) { "an antivirus that usually comes as a trial - once it runs out the PC is unprotected, while Microsoft Defender (free, built in) stays switched off as long as it's installed" } else { 'usually a trial that came with the PC' }
    if (-not $T) { & "$PSScriptRoot\todo.ps1" -Id $id -Text "$n is installed - $why. If you didn't buy it, uninstall it (the Uninstall button here)." }
    "Found: $n (a to-do item with an Uninstall button)"
}
if (-not $T) {   # items for apps that are gone: off the list
    foreach ($old in @(& "$PSScriptRoot\todo.ps1" -List) | Where-Object { $_ -like 'junk-*' -and $_ -notin $ids }) { & "$PSScriptRoot\todo.ps1" -Id $old -Done }
    & "$PSScriptRoot\todo.ps1" -Id 'vendor-apps' -Done   # the older "these came with the PC" item
}
