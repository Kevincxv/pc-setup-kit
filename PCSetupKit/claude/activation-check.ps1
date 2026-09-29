# Windows activation - only with this PC's own license, never an activator or a borrowed key (run by health-check.ps1):
# - activated: nothing to do
# - the PC's firmware holds a Windows key (most prebuilt PCs and laptops) for the edition that's installed: it's put in
#   and activated online
# - otherwise online activation is tried (once a day): a digital license - this hardware activated before, or a
#   license on the owner's Microsoft account - activates that way
# - still not activated: a Reminder with what to do (Settings > System > Activation: Troubleshoot, or enter / buy a key);
#   a firmware license for another edition (Home key, Pro installed) is said as such
# The key is never printed. State: activation-state.txt (the last try). -Test (hashtable: Status, Edition, FwKey,
# FwDesc, AfterIpk, AfterAto) with -Do (gets the actions), -State: tests.
param([hashtable]$Test, [scriptblock]$Do, [string]$State = "$PSScriptRoot\activation-state.txt", [datetime]$Now = (Get-Date))
$ErrorActionPreference = 'SilentlyContinue'
$T = $Test
function Get-Lic { if ($T) { return $T.Status }; [int](Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" | Select-Object -First 1).LicenseStatus }
if ((Get-Lic) -eq 1) { return }   # 1 = licensed
$last = [datetime]::MinValue; [void][datetime]::TryParse("$(Get-Content $State -TotalCount 1)", [ref]$last)
$tryNow = $last -lt $Now.AddHours(-20)
$edition = if ($T) { $T.Edition } else { "$((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID)" }
$svc = if (-not $T) { Get-CimInstance SoftwareLicensingService }
$fwKey = if ($T) { $T.FwKey } else { "$($svc.OA3xOriginalProductKey)" }
$fwDesc = if ($T) { $T.FwDesc } else { "$($svc.OA3xOriginalProductKeyDescription)" }
# the firmware key's edition, from its description ("[4.0] Core OEM:DM", "[4.0] Professional OEM:DM", ...)
$fwEdition = if ($fwDesc -match '\]\s*([A-Za-z]+)\s') { $Matches[1] }
$names = @{ Core = 'Home'; CoreSingleLanguage = 'Home Single Language'; Professional = 'Pro'; Education = 'Education'; Enterprise = 'Enterprise' }
function Name($e) { if ($names.ContainsKey("$e")) { $names["$e"] } else { "$e" } }
function Act([string]$What, [scriptblock]$Real) { if ($Do) { & $Do $What } else { & $Real } }
if ($tryNow) {
    $Now.ToString('o') | Set-Content $State
    if ($fwKey -and $fwEdition -eq $edition) {
        Act 'install firmware key' { [void](Invoke-CimMethod -InputObject $svc -MethodName InstallProductKey -Arguments @{ ProductKey = $fwKey }) }
        Act 'activate' { Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" | ForEach-Object { [void](Invoke-CimMethod -InputObject $_ -MethodName Activate) } }
        if ($T) { $T.Status = $T.AfterIpk }
        if ((Get-Lic) -eq 1) { return "Windows activated with the license built into this PC ($(Name $edition))" }
    }
    else {
        Act 'activate' { Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" | ForEach-Object { [void](Invoke-CimMethod -InputObject $_ -MethodName Activate) } }
        if ($T) { $T.Status = $T.AfterAto }
        if ((Get-Lic) -eq 1) { return "Windows activated (this PC's digital license)" }
    }
}
if ($fwKey -and $fwEdition -and $fwEdition -ne $edition) {
    "Reminder: Windows isn't activated - this PC's built-in license is for Windows $(Name $fwEdition), but Windows $(Name $edition) is installed. Reinstall choosing $(Name $fwEdition) in Windows Setup (the install USB works), or buy an upgrade to $(Name $edition): Settings > System > Activation"
} else {
    "Reminder: Windows isn't activated - open Settings > System > Activation. If this PC came with Windows or was activated before, choose Troubleshoot (sign in with your Microsoft account if you linked the license to it); otherwise enter your product key there, or buy one from Microsoft on that page"
}
