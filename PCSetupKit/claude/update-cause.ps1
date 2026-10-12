# What most likely changed settings back: the Windows updates and driver installs since a time (the tweak guard's last
# pass), as one short line - "after <update>" in the Status tab's history - or nothing when there were none (another
# program, or the owner). Defender's definition updates (several a day) and Store app updates change no settings: left out.
# Driver installs: UserPnp 20003 (25H2) / 20001, named by their .inf. -Events: tests (objects with Id, TimeCreated, Properties).
param([datetime]$Since = (Get-Date).AddHours(-6), [object[]]$Events)
$ErrorActionPreference = 'SilentlyContinue'
$ev = if ($PSBoundParameters.ContainsKey('Events')) { @($Events) } else {
    @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'; Id = 19; StartTime = $Since } -MaxEvents 30) +
    @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-UserPnp'; Id = 20001, 20003; StartTime = $Since } -MaxEvents 60)
}
$ev = @($ev | Where-Object { $_ -and $_.TimeCreated -ge $Since })
$wu = @($ev | Where-Object Id -eq 19 | ForEach-Object { "$($_.Properties[0].Value)".Trim() } | Where-Object { $_ -and $_ -notmatch '^Security Intelligence Update|^[0-9A-Z]{12}-' } | Select-Object -Unique)   # (Store apps: "9WZDNCRFJBH4-Microsoft.Windows.Photos")
# a driver: its .inf from the driver store path ("nvmdi.inf_amd64_..." -> nvmdi.inf), else the service it added
$drv = @($ev | Where-Object { $_.Id -in 20001, 20003 } | ForEach-Object {
        $all = (@($_.Properties) | ForEach-Object { "$($_.Value)" }) -join ' '
        if ($all -match '\\([\w.-]+\.inf)_') { $Matches[1] } elseif ("$($_.Properties[0].Value)") { "$($_.Properties[0].Value)" } } | Where-Object { $_ } | Select-Object -Unique)
$parts = @()
if ($wu) { $parts += "Windows Update ($(($wu | Select-Object -First 2) -join '; ')$(if ($wu.Count -gt 2) { "; +$($wu.Count - 2) more" }))" }
if ($drv) { $parts += "driver install ($(($drv | Select-Object -First 3) -join ', ')$(if ($drv.Count -gt 3) { ", +$($drv.Count - 3) more" }))" }
$parts -join ' and '
