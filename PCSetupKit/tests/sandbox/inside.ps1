# Runs INSIDE Windows Sandbox (run-sandbox.ps1 starts it at the sandbox's logon): a real, clean Windows 11 client -
# the one test GitHub's Windows Server machines can't give. The same steps as the fresh-install workflow: setup.ps1 for
# real, the install checks, then the new install's own self-test. Everything goes to C:\Results (a folder on the host);
# done.txt last, so the host knows it finished.
param([ValidateSet('noai', 'ai')][string]$Mode = 'noai')
$r = 'C:\Results'
# no transcript here: setup.ps1 keeps its own (C:\PCSetupKit\setup.log), which an outer transcript leaves empty
"started $((Get-Date).ToString('o'))" | Set-Content "$r\inside.log"
try {
    # a writable copy of the kit (the host folder is read-only) without kit-source.txt: this version is tested, the
    # updater stays off (as on GitHub)
    New-Item C:\KitSrc -ItemType Directory -Force | Out-Null
    Copy-Item C:\KitRO\* C:\KitSrc -Recurse -Force
    Remove-Item C:\KitSrc\PCSetupKit\kit-source.txt -ErrorAction SilentlyContinue
    $env:FRESH_WITH_CLAUDE = if ($Mode -eq 'ai') { '1' } else { '0' }
    $t0 = Get-Date
    # its own process, as at a real first login (inside this try, any error in setup would stop it here)
    $sa = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\KitSrc\PCSetupKit\setup.ps1', '-NoLaunch') + @(if ($Mode -eq 'ai') { '-WithClaude' })
    & powershell @sa *> "$r\setup.txt"
    $errs = @(Get-Content "$r\setup.txt" | Select-String '^\s*\+ (CategoryInfo|FullyQualifiedErrorId)\s*:' | Where-Object { $_ -match 'FullyQualifiedErrorId' })
    "setup took $([int]((Get-Date) - $t0).TotalMinutes) min, $($errs.Count) PowerShell error(s) in its output" | Add-Content "$r\summary.txt"
    & powershell -NoProfile -ExecutionPolicy Bypass -File C:\KitSrc\PCSetupKit\tests\fresh\check-install.ps1 *> "$r\check.txt"
    "install checks: exit $LASTEXITCODE - $((Get-Content "$r\check.txt" | Select-String 'RESULT |passed' | Select-Object -Last 1).Line)" | Add-Content "$r\summary.txt"
    $st = & "$env:USERPROFILE\.claude\self-test.ps1" -Force 2>&1
    "self-test: $st" | Add-Content "$r\summary.txt"
    Copy-Item C:\PCSetupKit\setup.log, "$env:USERPROFILE\.claude\self-test.log", "$env:USERPROFILE\.claude\maint-report.txt" $r -ErrorAction SilentlyContinue
    # a settings backup mapped in (run-sandbox.ps1 -Backup): restored as on a reinstall of the PC it came from - the
    # sandbox is other hardware, so the backup's own machine id is passed - then checked value by value
    $zip = Get-ChildItem C:\Backup\*.zip -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
    if ($zip) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $z = [IO.Compression.ZipFile]::OpenRead($zip.FullName); $meta = (New-Object IO.StreamReader($z.GetEntry('backup.json').Open())).ReadToEnd() | ConvertFrom-Json; $z.Dispose()
        $rs = @(& "$env:USERPROFILE\.claude\settings-backup.ps1" -Restore -From $zip.FullName -MachineId $meta.machine)
        "settings restore: $($rs -join ' / ')" | Add-Content "$r\summary.txt"
        $same = 0; $diff = @()
        foreach ($k in $meta.look.PSObject.Properties) { foreach ($v in $k.Value.PSObject.Properties) {
                $want = if ($v.Value.kind -eq 'Binary') { $v.Value.value } else { "$($v.Value.value)" }
                $got = (Get-Item "HKCU:\$($k.Name)" -ErrorAction SilentlyContinue).GetValue($v.Name, $null, 'DoNotExpandEnvironmentNames')
                $got = if ($got -is [byte[]]) { [Convert]::ToBase64String($got) } else { "$got" }   # (GetValue gives DWORDs signed, as the backup stored them)
                if ($got -eq $want) { $same++ } else { $diff += "$($k.Name)\$($v.Name): want $want, got $got" } } }
        $wp = (Get-ItemProperty 'HKCU:\Control Panel\Desktop').WallPaper
        @("settings: $same match the backup, $($diff.Count) differ") + $diff + "wallpaper: $wp (exists: $(Test-Path $wp))" | Set-Content "$r\restore-check.txt"
        "settings check: $same match, $($diff.Count) differ, wallpaper $(if (Test-Path $wp) { 'set' } else { 'MISSING' })" | Add-Content "$r\summary.txt"
        Start-Sleep 20   # Explorer restarts with the restored taskbar and colours
    }
    # screenshots of the finished PC: the desktop, then the app's pages
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    function Save-Screen([string]$Name) {
        $b = [Windows.Forms.SystemInformation]::VirtualScreen; $bmp = New-Object Drawing.Bitmap $b.Width, $b.Height
        $g = [Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location, [Drawing.Point]::Empty, $b.Size); $bmp.Save("$r\screen-$Name.png"); $g.Dispose(); $bmp.Dispose()
    }
    Save-Screen '1-desktop'
    $n = 2
    foreach ($pg in 'Home', 'History', 'Maintenance') {
        $p = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "$env:USERPROFILE\.claude\dashboard.ps1", '-Page', $pg -PassThru
        Start-Sleep 15; Save-Screen "$n-app-$($pg.ToLower())"; $n++
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; Start-Sleep 2
    }
}
catch { "inside.ps1 failed: $($_.Exception.Message)" | Add-Content "$r\summary.txt"; "$_`n$($_.ScriptStackTrace)" | Add-Content "$r\inside.log" }
finally {
    (Get-Date).ToString('o') | Set-Content "$r\done.txt"
}
