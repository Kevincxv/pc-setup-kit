# power-log.ps1: the stability record - every blue screen and power-off (with when it really went off), the owner's
# "did you turn it off?" answers, and what changed between checks. Made-up events and snapshots - no real log is read.
. "$PSScriptRoot\..\lib.ps1"
$pl = "$Src\power-log.ps1"
if (-not (Test-Path $pl)) { Skip 'power-log' 'not installed here'; Finish }
$f = "$Work\power-log.json"; $now = [datetime]'2026-10-12 20:00'
$snap = @{ gpu = 'Graphics X 617.42'; bios = '4.43'; ram = '2 x 16 GB at 4800 MT/s in slot A + slot B'; verifier = 'off' }
$evs = @(@{ At = [datetime]'2026-10-12 13:08:40'; Bugcheck = 265; OffAt = [datetime]'2026-10-12 13:07:14' }, @{ At = [datetime]'2026-10-12 19:34:25'; Bugcheck = 0; OffAt = [datetime]'2026-10-12 14:42:51' })
function PL([hashtable]$p) { $p.File = $f; $p.Now = $now; @(& $pl @p) }
function J { Get-Content $f -Raw | ConvertFrom-Json }

Section 'crashes and power-offs'
[void](PL @{ Update = $true; Events = $evs; Snapshot = $snap })
$e = @((J).events)
Check 'a blue screen: its stop code, when it happened' ($e[0].kind -eq 'bsod' -and $e[0].code -eq '0x109' -and $e[0].at -eq '2026-10-12T13:07:14') ($e | ConvertTo-Json -Compress)
Check 'a power-off without one: when it went off (not when it started again), no answer yet' ($e[1].kind -eq 'off' -and $e[1].at -eq '2026-10-12T14:42:51' -and -not $e[1].answer) ''
[void](PL @{ Update = $true; Events = $evs; Snapshot = $snap })
Check 'the next check: nothing twice' (@((J).events).Count -eq 2) ''

Section 'the owner''s answer'
[void](PL @{ Answer = 'froze'; Key = '2026-10-12T19:34:25' })
Check 'kept with the power-off' (@((J).events)[1].answer -eq 'froze') ''
[void](PL @{ Update = $true; Events = $evs; Snapshot = $snap })
Check '... and kept through the next check' (@((J).events)[1].answer -eq 'froze') ''
[void](PL @{ Answer = 'nonsense'; Key = '2026-10-12T19:34:25' })
Check 'an answer that isn''t one is ignored' (@((J).events)[1].answer -eq 'froze') ''
$old = @(@{ At = [datetime]'2025-06-01 10:00'; Bugcheck = 0 }, @{ At = [datetime]'2025-07-01 10:00'; Bugcheck = 0 }, @{ At = [datetime]'2025-07-02 10:00'; Bugcheck = 0x109 }, @{ At = [datetime]'2026-10-01 10:00'; Bugcheck = 0 })
[void](PL @{ Update = $true; Events = $old; Snapshot = $snap })
[void](PL @{ Answer = 'me'; Old = $true })
$a = @{}; foreach ($x in (J).events) { $a[$x.key] = "$($x.answer)" }
Check 'one click for the old ones: every power-off over 30 days old not answered is "me" - not a blue screen, not a recent one, not one already answered' ($a['2025-06-01T10:00:00'] -eq 'me' -and $a['2025-07-01T10:00:00'] -eq 'me' -and $a['2025-07-02T10:00:00'] -eq '' -and $a['2026-10-01T10:00:00'] -eq '' -and $a['2026-10-12T19:34:25'] -eq 'froze') ($a | ConvertTo-Json -Compress)

Section 'what changed'
$s2 = $snap.Clone(); $s2.ram = '1 x 16 GB at 4800 MT/s in slot A'; $s2.gpu = 'Graphics X 618.10'
[void](PL @{ Update = $true; Events = $evs; Snapshot = $s2 })
$c = @((J).changes)
Check 'the RAM and the graphics driver: from what to what, when seen' ($c.Count -eq 2 -and ($c | Where-Object what -eq 'RAM').to -eq '1 x 16 GB at 4800 MT/s in slot A' -and ($c | Where-Object what -eq 'Graphics driver').from -eq 'Graphics X 617.42' -and $c[0].at -eq '2026-10-12T20:00:00') ($c | ConvertTo-Json -Compress)
[void](PL @{ Update = $true; Events = $evs; Snapshot = $s2 })
Check 'nothing different: nothing added' (@((J).changes).Count -eq 2) ''
Finish
