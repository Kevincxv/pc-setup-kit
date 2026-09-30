# release-issues.ps1: a failed daily fresh-install check (an open GitHub issue) becomes a job for the hidden /maintain run,
# once a day per issue, only on the PC the kit is made on with the AI assistant on. Made-up issues (-Test).
. "$PSScriptRoot\..\lib.ps1"
$ri = "$Src\release-issues.ps1"
if (-not (Test-Path $ri)) { Skip 'release-issues' 'not installed here'; Finish }
$req = "$Work\maint-requests.txt"; $st = "$Work\release-issues.txt"
$iss = @(@{ number = 7; url = 'https://github.com/x/y/issues/7'; title = 'Daily install check failed (v2026.09.30)' })
function Invoke-RI([hashtable]$t, [datetime]$now = (Get-Date), [switch]$Keep) { if (-not $Keep) { foreach ($f in $req, $st) { [IO.File]::Delete($f) } }; @(& $ri -Test $t -Requests $req -State $st -Now $now) }
$o = Invoke-RI @{ DevPc = $true; Ai = $true; Issues = $iss }
$r = Get-Content $req -Raw -ErrorAction SilentlyContinue
Check 'an open daily-check issue: a job for the hidden /maintain run (read the run, fix, test, publish only if all passes), said' ("$o" -match 'issue #7' -and $r -match 'issue #7 \(https://github\.com/x/y/issues/7\)' -and $r -match 'publish only if every test passes' -and $r -match 'comment on the issue') ($o -join ' / ')
$o = Invoke-RI @{ DevPc = $true; Ai = $true; Issues = $iss } -Keep
Check '... once a day, not at every login' (-not $o -and @(Get-Content $req).Count -eq 1) ''
$o = Invoke-RI @{ DevPc = $true; Ai = $true; Issues = $iss } (Get-Date).AddDays(1) -Keep
Check '... still open the next day: asked again' ("$o" -match 'issue #7' -and @(Get-Content $req).Count -eq 2) ''
$o = Invoke-RI @{ DevPc = $true; Ai = $true; Issues = @() }
Check 'no open issue: nothing' (-not $o -and -not (Test-Path $req)) ''
$o = Invoke-RI @{ DevPc = $false; Ai = $true; Issues = $iss }
Check 'any other PC (a friend''s): never' (-not $o -and -not (Test-Path $req)) ''
$o = Invoke-RI @{ DevPc = $true; Ai = $false; Issues = $iss }
Check 'the AI assistant off: never' (-not $o -and -not (Test-Path $req)) ''
$o = Invoke-RI @{ DevPc = $true; Ai = $true; Issues = @(@{ number = 9; url = 'u'; title = 'Something else' }) }
Check 'other issues: ignored' (-not $o) ''
Finish
