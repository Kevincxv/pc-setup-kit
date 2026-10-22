# ram-check.ps1: the memory test - the nightly one in Windows (a small real run here: 256 MB for 2 seconds, one with a bit
# flipped on purpose) and Windows' deep test at the next start-up (bcdedit stood in for, made-up result events).
. "$PSScriptRoot\..\lib.ps1"
$rc = "$Src\ram-check.ps1"
if (-not (Test-Path $rc)) { Skip 'ram-check' 'not installed here'; Finish }
$now = Get-Date; $log = "$Work\ram-test.log"; $sf = "$Work\ram-check.json"; $opt = "$Work\opts.txt"; '' | Set-Content $opt
$setup = '2 stick(s), 32 GB in P0 CHANNEL A + P0 CHANNEL B'
function RC([hashtable]$a) { $p = @{ Log = $log; State = $sf; Setup = $setup; Options = $opt; MB = 256; Seconds = 2; MaintState = "$Work\none.json" }; foreach ($k in $a.Keys) { $p[$k] = $a[$k] }; @(& $rc @p) }
function St { Get-Content $sf -Raw | ConvertFrom-Json }
function Ev($id) { [pscustomobject]@{ Id = $id } }

Section 'the test in Windows'
$o = RC @{ Stress = $true; Force = $true }
Check 'it runs: passes over the memory, no errors, logged with the stick setup (the stick test reads it)' ("$o" -match '^Memory test: \d+ passes over \d+ GB in \d+ s: 0 errors' -and @(Get-Content $log)[-1] -match "^\d{4}-\d\d-\d\d \d\d:\d\d \| stress \| $([regex]::Escape($setup)) \| \d+ passes .+: 0 errors$") "$o"
$o = RC @{ Stress = $true; Force = $true; Inject = $true }
Check 'a flipped bit (as faulty memory does): found and counted, with which bit' ("$o" -match ': 1 errors' -and (St).unsaid -match '1 error\(s\) with .+bits 0x0000000000000200 flipped') "$o / $((St).unsaid)"
$o = RC @{ Check = $true }
Check '... said once as a WARNING at the next check (it gets looked at), with what to do' ("$o" -match '^WARNING: the memory test found 1 error\(s\) with .+ test one stick at a time') "$o"
Check '... and only once' (-not (RC @{ Check = $true })) ''

Section 'when it runs by itself'
Clear-Path $sf; $n0 = @(Get-Content $log).Count
function Auto([hashtable]$a) { $p = @{ Stress = $true; Idle = 3600000; Game = ''; Bsods = @($now.AddDays(-3)); Now = $now }; foreach ($k in $a.Keys) { $p[$k] = $a[$k] }; RC $p }
[void](Auto @{ Idle = 600000 })
Check 'not while the PC is in use (under 30 minutes idle)' (@(Get-Content $log).Count -eq $n0) ''
[void](Auto @{ Game = 'TestGame' })
Check 'not under a game' (@(Get-Content $log).Count -eq $n0) ''
'ramcheck=off' | Set-Content $opt; [void](Auto @{}); '' | Set-Content $opt
Check 'not when switched off in Settings' (@(Get-Content $log).Count -eq $n0) ''
$o = Auto @{}
Check 'idle 30+ minutes, no game, a blue screen this month: it runs' ("$o" -match '^Memory test:' -and @(Get-Content $log).Count -eq $n0 + 1) "$o"
[void](Auto @{ Now = $now.AddHours(8) })
Check '... not again the same night' (@(Get-Content $log).Count -eq $n0 + 1) ''
[void](Auto @{ Now = $now.AddHours(21) })
Check '... the next night again while blue screens keep coming' (@(Get-Content $log).Count -eq $n0 + 2) ''
[void](Auto @{ Now = $now.AddDays(3); Bsods = @($now.AddDays(-60)) })
Check 'no blue screen for a month: once a month only' (@(Get-Content $log).Count -eq $n0 + 2) ''

Section 'the deep test at the next start-up'
Clear-Path $sf
$global:bcd = @(); $do = { $global:bcd += $args[0]; $true }
$o = RC @{ ArmBoot = $true; Do = $do; Now = $now }
Check 'set up: the extended test, one pass, for the next start-up only - and how to start it (Messiah never restarts)' (($bcd -join ',') -eq '/set {memdiag} testmix extended,/set {memdiag} passcount 1,/bootsequence {memdiag}' -and "$o" -match 'restart the PC yourself' -and (St).bootArmed) "$($bcd -join ',') / $o"
$o = RC @{ Check = $true; Do = $do; BootAt = $now.AddMinutes(-5); Events = @() }
Check 'not started yet (no start-up since): nothing said' (-not $o -and (St).bootArmed) "$o"
$global:bcd = @(); $n0 = @(Get-Content $log).Count
$o = RC @{ Check = $true; Do = $do; BootAt = $now.AddHours(3); Events = @((Ev 1201), (Ev 1101)); Now = $now.AddHours(3) }
Check 'ran with no errors: said, logged for the stick setup, Windows'' test back to its default' ("$o" -match '^Deep memory test at start-up: no errors' -and @(Get-Content $log)[-1] -match '\| boottest \| .+: no errors$' -and ($bcd -join ',') -match 'deletevalue \{memdiag\} testmix' -and -not (St).bootArmed) "$o / $($bcd -join ',')"
[void](RC @{ ArmBoot = $true; Do = $do; Now = $now })
$o = RC @{ Check = $true; Do = $do; BootAt = $now.AddHours(3); Events = @((Ev 1202)); Now = $now.AddHours(3) }
Check 'errors found: a WARNING with the next step' ("$o" -match '^WARNING: Windows'' deep memory test found errors' -and @(Get-Content $log)[-1] -match 'errors found$') "$o"
[void](RC @{ ArmBoot = $true; Do = $do; Now = $now })
$o = RC @{ Check = $true; Do = $do; BootAt = $now.AddHours(3); Events = @((Ev 1103)); Now = $now.AddHours(3) }
Check 'cancelled at start-up: said, how to start it again' ("$o" -match 'cancelled at start-up') "$o"
[void](RC @{ ArmBoot = $true; Do = $do; Now = $now })
$o = RC @{ Check = $true; Do = $do; BootAt = $now.AddHours(3); Events = @(); Now = $now.AddHours(3) }
Check 'no result (turned off during it): said, not left waiting' ("$o" -match "didn't finish" -and -not (St).bootArmed) "$o"
[void](RC @{ ArmBoot = $true; Do = $do; Now = $now }); $global:bcd = @()
$o = RC @{ CancelBoot = $true; Do = $do }
Check 'cancelled in the app: the next start-up is normal again' (($bcd -join ',') -match '^/deletevalue \{bootmgr\} bootsequence' -and -not (St).bootArmed -and "$o" -match 'next start-up is a normal one') "$($bcd -join ',')"
$o = RC @{ ArmBoot = $true; Do = { $false } }
Check 'bcdedit refusing: said, nothing armed' ("$o" -match 'could not be set up' -and -not (St).bootArmed) "$o"
Finish
