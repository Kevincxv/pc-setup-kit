# Messiah fixing its own published release - only on the PC the kit is made on (publish-kit.ps1 is there), with the AI
# assistant on. Run by claude-bg-maint.ps1 before its hidden /maintain run: when GitHub's daily fresh-install check of
# the published release failed (an open "Daily install check failed" issue - fresh-install.yml opens it, and closes it
# again after a passing day), the job goes to the next hidden /maintain run (maint-requests.txt): read the failed run,
# fix the kit, test it all, publish only if everything passes. Once a day per issue. State: release-issues.txt.
# -Test (hashtable: DevPc, Ai, Issues = @(@{ number; url; title })) with -Requests, -State: tests.
param([hashtable]$Test, [string]$Requests = "$PSScriptRoot\maint-requests.txt", [string]$State = "$PSScriptRoot\release-issues.txt", [datetime]$Now = (Get-Date))
$ErrorActionPreference = 'SilentlyContinue'
$T = $Test
if ($env:PCKIT_IN_TESTS -and -not $T) { return }
$dev = if ($T) { $T.DevPc } else { Test-Path "$PSScriptRoot\publish-kit.ps1" }
$ai = if ($T) { $T.Ai } else { [bool](& "$PSScriptRoot\ai-enabled.ps1") }
if (-not $dev -or -not $ai) { return }
$repo = 'Kevincxv/pc-setup-kit'
$issues = @(if ($T) { $T.Issues | ForEach-Object { [pscustomobject]$_ } } else {
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return }
        (gh issue list -R $repo --state open --search 'Daily install check failed in:title' --json number,url,title 2>$null | Out-String | ConvertFrom-Json) | ForEach-Object { $_ }
    })
$seen = @(Get-Content $State -ErrorAction SilentlyContinue)   # "<issue number>|<yyyy-MM-dd>" lines
foreach ($i in $issues | Where-Object { $_.title -like 'Daily install check failed*' }) {
    $key = "$($i.number)|$($Now.ToString('yyyy-MM-dd'))"
    if ($seen -contains $key) { continue }
    Add-Content $Requests -Encoding UTF8 ("GitHub's daily fresh-install check of the published release failed - issue #$($i.number) ($($i.url)). " +
        "Read the failed run (the issue and its comments link it; gh run view <id> --log-failed -R $repo), find the cause and fix it in the kit (Documents\PC Setup Kit). " +
        "Install the fix on this PC (the live scripts too), run the full unit suite, then publish with publish-kit.ps1 and watch the release with watch-release.ps1 - publish only if every test passes. " +
        "If the cause is outside the kit and can't be fixed from here (a GitHub outage, a download that is back by itself), say so in a comment on the issue instead (gh issue comment). " +
        "The next passing daily check closes the issue by itself. Tell the owner what you found and did (maint-todo.txt only if something needs them).")
    Add-Content $State $key
    "Release check: the daily fresh-install check failed (issue #$($i.number)) - the hidden Claude maintenance looks into it now"
}
