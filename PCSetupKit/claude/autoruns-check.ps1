# Weekly startup audit with Sysinternals Autoruns (Microsoft's own tool): everything that starts by itself beyond what
# health-check.ps1 watches at every login (Run keys, Startup folders, tasks) - services, drivers, Explorer and browser
# add-ons, Winlogon, LSA, Winsock and print providers, codecs, image hijacks. Run by periodic-maint.ps1 (never under a game).
# - The first run only records what's there (a PC's own drivers and tools are not news); after that only what's NEW or
#   CHANGED is said: a new entry not signed by its maker, running from a folder any program can write to (AppData, Temp,
#   Users\Public) = WARNING (that's how malware starts itself); another unsigned one = Reminder; signed ones = a plain line.
#   An entry that was signed and is now a changed, unsigned file = WARNING (tampering).
# - Autoruns is fetched from download.sysinternals.com into .claude\tools\autoruns, and only used when its signature is
#   Microsoft's. Entries Microsoft signs are left out (-m), so are disabled ones and leftovers whose file is gone.
# Test overrides: -Csv (the scan's output instead of running Autoruns), -Dir (where state and the tool live), -Force.
param([string]$Csv, [string]$Dir = $PSScriptRoot, [switch]$Force)
$ErrorActionPreference = 'SilentlyContinue'
$stFile = "$Dir\autoruns-state.json"; $baseFile = "$Dir\autoruns-baseline.json"
$st = try { Get-Content $stFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { $null }
if (-not $Force -and $st.last -and ([datetime]$st.last) -gt (Get-Date).AddDays(-6)) { return }   # weekly

if (-not $Csv) {
    $toolDir = "$Dir\tools\autoruns"
    $exe = "$toolDir\$(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'autorunsc64a.exe' } else { 'autorunsc64.exe' })"
    $isMs = { param($f) $s = Get-AuthenticodeSignature -FilePath $f; $s.Status -eq 'Valid' -and "$($s.SignerCertificate.Subject)" -match '^CN=Microsoft Corporation,' }
    if (-not (Test-Path $exe) -or -not (& $isMs $exe)) {
        $tmp = Join-Path $env:TEMP "pckit-autoruns-$(Get-Random)"; New-Item $tmp -ItemType Directory -Force | Out-Null
        try {
            Invoke-WebRequest 'https://download.sysinternals.com/files/Autoruns.zip' -OutFile "$tmp\a.zip" -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
            Expand-Archive "$tmp\a.zip" "$tmp\x" -Force -ErrorAction Stop
            $got = "$tmp\x\$(Split-Path $exe -Leaf)"
            if (-not (& $isMs $got)) { "Startup audit: the downloaded Autoruns isn't signed by Microsoft - not used (tried again next week)"; return }
            New-Item $toolDir -ItemType Directory -Force | Out-Null; Copy-Item $got $exe -Force
        }
        catch { "Startup audit: couldn't download Autoruns ($($_.Exception.Message)) - tried again next week"; return }
        finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $Csv = Join-Path $env:TEMP "pckit-autoruns-$(Get-Random).csv"
    # every kind of entry, as CSV, with hashes and signature checks, Microsoft's own left out (5 minutes at most)
    $p = Start-Process $exe -ArgumentList '-accepteula', '-nobanner', '-a', '*', '-c', '-h', '-s', '-m', '-o', "`"$Csv`"" -WindowStyle Hidden -PassThru
    if (-not $p.WaitForExit(300000)) { Stop-Process -Id $p.Id -Force; "Startup audit: Autoruns took over 5 minutes - stopped, tried again next week"; return }
    $temp = $Csv
}
$rows = @(Import-Csv $Csv -ErrorAction SilentlyContinue)
if ($temp) { Remove-Item $temp -Force -ErrorAction SilentlyContinue }
if (-not $rows) { "Startup audit: Autoruns gave no results - tried again next week"; return }

# what health-check.ps1 already watches at every login (Run keys, Startup folders, tasks) is left to it
$cur = @{}
foreach ($r in $rows) {
    if (-not $r.Entry -or $r.Enabled -ne 'enabled' -or "$($r.'Image Path')" -match '^File not found' -or $r.Category -eq 'Scheduled Tasks') { continue }
    if ($r.Category -eq 'Logon' -and $r.'Entry Location' -match '\\CurrentVersion\\Run$|\\Start Menu\\Programs\\Startup$') { continue }
    $key = "$($r.Category)|$($r.'Entry Location')|$($r.Entry)|$($r.'Image Path')"
    $cur[$key] = [ordered]@{ Category = $r.Category; Entry = $r.Entry; Path = "$($r.'Image Path')"; Signed = "$($r.Signer)" -match '^\(Verified\)'
        Company = "$($r.Company)"; Sha1 = "$($r.'SHA-1')" }
}
$base = @{}; $hadBase = Test-Path $baseFile
if ($hadBase) { try { (Get-Content $baseFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).PSObject.Properties | ForEach-Object { $base[$_.Name] = $_.Value } } catch { $hadBase = $false } }

if (-not $hadBase) { "Startup audit: $($cur.Count) auto-start entries recorded (services, drivers, add-ons beyond the Run keys and tasks) - only new or changed ones are mentioned from now on" }
else {
    $warn = @(); $remind = @(); $signed = @()
    foreach ($k in $cur.Keys) {
        $e = $cur[$k]; $name = "$($e.Entry) ($($e.Category), $($e.Path))"
        if (-not $base.ContainsKey($k)) {
            if ($e.Signed) { $signed += "$($e.Entry)$(if ($e.Company) { " ($($e.Company))" })" }
            elseif ($e.Path -match '\\AppData\\|\\Temp\\|\\Users\\Public\\') { $warn += $name }
            else { $remind += $name }
        }
        elseif ($base[$k].Signed -and -not $e.Signed -and $e.Sha1 -and $e.Sha1 -ne $base[$k].Sha1) { $warn += "$name - it was signed by its maker before and has been changed" }
    }
    if ($warn) { "WARNING: startup audit - auto-start entries not signed by their maker: $($warn -join '; ') - if you didn't install this, it may be malware" }
    if ($remind) { "Reminder: startup audit - new auto-start entries not signed by their maker: $($remind -join '; ') (fine if you just installed it)" }
    if ($signed) { "Startup audit: new auto-start entries (signed): $($signed -join ', ')" }
    if (-not ($warn -or $remind -or $signed)) { "Startup audit: nothing new ($($cur.Count) entries checked)" }
}
$cur | ConvertTo-Json -Depth 3 | Set-Content $baseFile -Encoding UTF8
@{ last = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content $stFile -Encoding UTF8
