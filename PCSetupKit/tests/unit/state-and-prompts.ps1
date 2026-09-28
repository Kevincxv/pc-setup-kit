# maint-state.json handling (periodic-maint merge, corrupt files) and the headless run's prompt (claude-unattended.ps1).
. "$PSScriptRoot\..\lib.ps1"
Section 'periodic-maint: long runs never lose keys written meanwhile'
$d = "$Work\pm"; New-Item $d -ItemType Directory -Force | Out-Null
(Get-Content "$Src\periodic-maint.ps1" -Raw).Replace('$cur = Read-State', 'Start-Sleep 3; $cur = Read-State') | Set-Content "$d\periodic-maint.ps1"
'' | Set-Content "$d\game-check.ps1"
$now = (Get-Date).ToString('o'); @{ 'weekly-apps' = $now; 'monthly-cleanup' = $now; 'trim' = $now; 'claude-quarterly' = $now; 'claude-winver-due' = 'yes' } | ConvertTo-Json | Set-Content "$d\maint-state.json"
$p = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$d\periodic-maint.ps1`"", '-TestDisplayVersion', '25H2', '-TestEdition', 'Professional', '-TestToday', '2026-09-27' -PassThru -WindowStyle Hidden -RedirectStandardOutput "$d\out.txt"
Start-Sleep 1.5
$s = Get-Content "$d\maint-state.json" -Raw | ConvertFrom-Json; $s | Add-Member 'expo-off-test' '2026-09-26T22:18:34' -Force; $s | Add-Member 'claude-handled-report' 'Checked X' -Force; $s | ConvertTo-Json | Set-Content "$d\maint-state.json"
$p.WaitForExit()
$r = Get-Content "$d\maint-state.json" -Raw | ConvertFrom-Json
Check 'keys written during the run survive (expo-off-test, handled report)' ($r.'expo-off-test' -and $r.'claude-handled-report') ''
Check 'keys it does not own are untouched (claude-quarterly)' ($r.'claude-quarterly' -eq $now) ''
Check 'its own keys are updated (winver-due cleared on a supported Windows)' (-not $r.'claude-winver-due') ''
$head = ((Get-Content "$Src\periodic-maint.ps1" -Raw) -split "`n" | Select-String -Pattern '^\$stateFile|^function Read-State|^    if \(\$j\)|^\$state = Read-State|^function Due' | ForEach-Object Line) -join "`n"
$head = $head -replace '\$PSScriptRoot', $d
foreach ($c in '{"broken', '', 'null', '{"weekly-apps":"garbage"}') {
    $c | Set-Content "$d\maint-state.json"; $err = @(. ([scriptblock]::Create($head)) 2>&1)
    Check "state file [$c]: no error, weekly treated as due" ($err.Count -eq 0 -and (Due 'weekly-apps' 7)) "$err"
}

Section 'Windows end of support depends on the edition'
$d2 = "$Work\eos"; New-Item $d2 -ItemType Directory -Force | Out-Null; Copy-Item "$Src\periodic-maint.ps1" $d2; '' | Set-Content "$d2\game-check.ps1"
function Eos($ver, $ed, $type = 'Client', $day = '2026-09-27') {
    @{ 'weekly-apps' = $now; 'monthly-cleanup' = $now; 'trim' = $now } | ConvertTo-Json | Set-Content "$d2\maint-state.json"
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File "$d2\periodic-maint.ps1" -TestDisplayVersion $ver -TestEdition $ed -TestInstallType $type -TestToday $day -TestRebootPending no
    [pscustomobject]@{ Warn = [bool]($o -match 'WARNING: Windows'); Due = [bool](Get-Content "$d2\maint-state.json" -Raw | ConvertFrom-Json).'claude-winver-due'; Out = $o -join ' / ' }
}
foreach ($c in @(
        @('24H2', 'Professional', 'Client', $true, 'Pro 24H2 (ends Oct 2026)'), @('24H2', 'Core', 'Client', $true, 'Home 24H2'),
        @('25H2', 'Professional', 'Client', $false, 'Pro 25H2 (ends Oct 2027)'), @('24H2', 'ProfessionalEducation', 'Client', $true, 'Pro Education 24H2 (24 months)'),
        @('24H2', 'Education', 'Client', $false, 'Education 24H2 (36 months: Oct 2027)'), @('24H2', 'Enterprise', 'Client', $false, 'Enterprise 24H2 (36 months)'),
        @('23H2', 'Enterprise', 'Client', $true, 'Enterprise 23H2 (ends Oct 2026)'), @('24H2', 'EnterpriseS', 'Client', $false, 'LTSC (own long lifecycle)'),
        @('24H2', 'ServerDatacenter', 'Server', $false, 'Windows Server (own lifecycle)'))) {
    $r = Eos $c[0] $c[1] $c[2]
    Check "$($c[4]): upgrade warning = $($c[3])" ($r.Warn -eq $c[3] -and $r.Due -eq $c[3]) $r.Out
}

Section 'claude-unattended: the headless prompt'
$H = "$Work\home"; $C = "$H\.claude"; New-Item "$H\.local\bin", $C -ItemType Directory -Force | Out-Null
Copy-Item (Get-FakeClaude) "$H\.local\bin\claude.exe"; Copy-Item "$Src\claude-unattended.ps1" $C
[IO.File]::WriteAllText("$C\maint-requests.txt", "Check José's café ✓ upgrade", (New-Object Text.UTF8Encoding $false))   # like Claude writes it (no BOM)
[void](Invoke-As $H "$C\claude-unattended.ps1" @('-Mode', 'maintain', '-Due', 'quarterly check') @{ FAKE_LOG = "$Work\un.log" })
$l = Get-Content "$Work\un.log" -Encoding UTF8
Check 'accented text reaches Claude intact (UTF-8, not ?)' ([bool]($l -match "José's café ✓")) (($l | Select-String STDIN).Line)
Check 'the due items are in the prompt' ([bool]($l -match 'Due now: quarterly check')) ''
Check 'it runs headless with its own session id and name' (($l -contains 'ARG=-p') -and ($l -contains 'ARG=--session-id') -and ($l -contains 'ARG=Hidden maintenance (maintain)')) ''
Check 'the one-off request file is consumed' (-not (Test-Path "$C\maint-requests.txt")) ''
Check 'the session file names the run (for Watch live)' ((Get-Content "$C\maint-claude-session")[1] -eq 'maintain') ''
[void](Invoke-As $H "$C\claude-unattended.ps1" @('-Mode', 'improve') @{ FAKE_LOG = "$Work\im.log" })
Check 'improve mode sends /self-improve' ([bool]((Get-Content "$Work\im.log" -Encoding UTF8) -match 'STDIN=/self-improve')) ''
Check 'the prompt tells Claude to check for games before heavy steps' ([bool]((Get-Content "$Work\im.log" -Encoding UTF8) -match 'game-check')) ''
Finish
