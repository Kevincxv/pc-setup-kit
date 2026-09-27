# Keeps a PC installed from the PC Setup Kit up to date with the published kit (GitHub releases). Run by the background
# maintenance. Does nothing on the PC where the kit is developed (its folder is a git repo) or without kit-source.txt.
# A new release is downloaded, checked (all files present, every script parses) and only then installed.
# Test overrides: -KitDir -ClaudeDir -TrayDir -Force (skip the developer-PC check).
param([string]$KitDir = 'C:\PCSetupKit', [string]$ClaudeDir = $PSScriptRoot, [string]$TrayDir = "$env:USERPROFILE\Documents\Claude Admin Tray", [switch]$Force)
$ErrorActionPreference = 'Stop'
$srcFile = "$KitDir\kit-source.txt"
if (-not (Test-Path $srcFile)) { return }
if (-not $Force -and (Test-Path "$env:USERPROFILE\Documents\PC Setup Kit\.git")) { return }   # the owner's PC publishes, it doesn't update
$cfg = @{}; Get-Content $srcFile | ForEach-Object { $k, $v = $_ -split '=', 2; if ($v) { $cfg[$k.Trim()] = $v.Trim() } }
if ($cfg.repo -notmatch '^[\w.-]+/[\w.-]+$') { return }
$verFile = "$KitDir\kit-version.txt"; $cur = if (Test-Path $verFile) { (Get-Content $verFile -Raw).Trim() } else { '' }
try { $rel = Invoke-RestMethod "https://api.github.com/repos/$($cfg.repo)/releases/latest" -Headers @{ 'User-Agent' = 'pc-setup-kit' } -TimeoutSec 20 }
catch { return }   # offline or rate-limited: quietly try again next time
$tag = $rel.tag_name
if (-not $tag -or $tag -eq $cur) { return }

$tmp = Join-Path $env:TEMP "pc-setup-kit-update"; if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item $tmp -ItemType Directory -Force | Out-Null
try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest "https://github.com/$($cfg.repo)/archive/refs/tags/$tag.zip" -OutFile "$tmp\kit.zip" -UseBasicParsing -TimeoutSec 120
    Expand-Archive "$tmp\kit.zip" "$tmp\x" -Force
    $k = Get-ChildItem "$tmp\x" -Directory | Select-Object -First 1 | ForEach-Object { "$($_.FullName)\PCSetupKit" }
    $need = 'setup.ps1', 'tweaks.ps1', 'uninstall.ps1', 'claude\claude-admin-launch.ps1', 'claude\claude-bg-maint.ps1', 'claude\health-check.ps1',
        'claude\session-lib.ps1', 'claude\hooks\no-power-off.ps1', 'claude\skills\maintain\SKILL.md', 'claude\tray\Claude Admin Tray.ahk'
    $missing = @($need | Where-Object { -not (Test-Path "$k\$_") })
    if ($missing) { "Kit update: $tag is incomplete ($($missing -join ', ')) - kept the current version"; return }
    $bad = @(Get-ChildItem $k -Recurse -Filter *.ps1 | Where-Object { $e = $null; [void][Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e); $e })
    if ($bad) { "Kit update: $tag has scripts that don't parse ($($bad.Name -join ', ')) - kept the current version"; return }

    Copy-Item "$k\*.ps1" $KitDir -Force                                   # setup / tweaks / uninstall
    Copy-Item "$k\claude\*.ps1" $ClaudeDir -Force                         # maintenance scripts
    New-Item "$ClaudeDir\hooks", "$ClaudeDir\skills" -ItemType Directory -Force | Out-Null
    Copy-Item "$k\claude\hooks\*" "$ClaudeDir\hooks" -Force
    Copy-Item "$k\claude\skills\*" "$ClaudeDir\skills" -Recurse -Force
    if (Test-Path $TrayDir) {
        Copy-Item "$k\claude\tray\Claude Admin Tray.ahk" $TrayDir -Force
        if (-not $Force -and (Get-ScheduledTask 'Claude Admin Tray' -ErrorAction SilentlyContinue)) {   # reload the tray (it won't open a second session)
            Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" | Where-Object CommandLine -match 'Claude Admin Tray\.ahk' | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
            Start-ScheduledTask 'Claude Admin Tray'
        }
    }
    $tag | Set-Content $verFile
    "PC Setup Kit updated $(if ($cur) { "$cur -> " })$tag"
}
catch { "Kit update: couldn't install $tag ($($_.Exception.Message)) - will retry next time" }
finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
