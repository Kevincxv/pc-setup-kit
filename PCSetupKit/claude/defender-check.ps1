# Microsoft Defender's real-time protection, kept on by itself (run by health-check.ps1 at every check):
# - off, and no other antivirus protects the PC: switched back on (Set-MpPreference), said
# - another antivirus is active (it turns Defender's real-time part off, as it should): only said
# - a policy (an organisation's or a tweak tool's) or Tamper Protection keeps it off: a WARNING with where to switch it
# The WARNING text is the one maint-actions.ps1 turns into the to-do item. -Test (hashtable: Rtp, OtherAv, Policy,
# After) with -Do (gets the action): tests.
param([hashtable]$Test, [scriptblock]$Do)
$ErrorActionPreference = 'SilentlyContinue'
$T = $Test
if ($env:PCKIT_IN_TESTS -and -not $T) { return }   # never from the test suite
$rtp = if ($T) { $T.Rtp } else { $mp = Get-MpComputerStatus; if ($mp) { [bool]$mp.RealTimeProtectionEnabled } }
if ($null -eq $rtp -or $rtp) { return }   # on, or Defender isn't there at all (Windows Server, Sandbox)
# another antivirus registered with Windows Security and switched on (productState bits 12-15 = 1: on)
$other = if ($T) { $T.OtherAv } else {
    @(Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct | Where-Object { $_.displayName -notmatch 'Windows Defender|Microsoft Defender' -and (([int]$_.productState -shr 12) -band 0xF) -eq 1 } | ForEach-Object displayName) -join ', '
}
if ($other) { return "Security: $other protects this PC (Microsoft Defender's real-time part is off because of it, as it should be)" }
$policy = if ($T) { $T.Policy } else { (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection').DisableRealtimeMonitoring -eq 1 -or (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender').DisableAntiSpyware -eq 1 }
if (-not $policy) {
    if ($Do) { & $Do 'defender on' } else { Set-MpPreference -DisableRealtimeMonitoring $false }
    $after = if ($T) { $T.After } else { Start-Sleep 3; [bool](Get-MpComputerStatus).RealTimeProtectionEnabled }
    if ($after) { return "Security: Microsoft Defender's real-time protection was off, with no other antivirus - turned it back on" }
}
$why = if ($policy) { 'a policy keeps it off' } else { 'it did not stay on' }
"WARNING: Defender real-time protection is OFF ($why - Windows Security > Virus & threat protection > Manage settings)"
