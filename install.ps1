# PC Setup Kit - one-command install on an existing Windows 11 PC. In PowerShell (it asks for admin by itself):
#   irm https://raw.githubusercontent.com/Kevincxv/pc-setup-kit/main/install.ps1 | iex
# With the optional Claude part (Messiah):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Kevincxv/pc-setup-kit/main/install.ps1))) -WithClaude
# Downloads the newest release, then runs PCSetupKit\setup.ps1 (tweaks, apps, zero maintenance - no AI needed).
# -DownloadOnly <folder>: only download and unpack (used for testing).
param([string]$DownloadOnly, [switch]$WithClaude)
$ErrorActionPreference = 'Stop'
$repo = 'Kevincxv/pc-setup-kit'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $DownloadOnly -and -not $isAdmin) {
    Write-Host 'Asking for administrator rights...' -ForegroundColor Cyan
    $cmd = "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/$repo/main/install.ps1)))$(if ($WithClaude) { ' -WithClaude' })"
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd
    return
}
if (-not $DownloadOnly) {
    Write-Host @'

  PC SETUP KIT
  This sets up this PC like a tuned gaming PC that then keeps itself maintained (no AI or account needed):
   - removes Windows bloat and ads, turns off telemetry and AI features, applies gaming tweaks
     (also turns memory integrity / VBS off for performance)
   - installs Git, Steam, Discord, Chrome, WinDbg, AutoHotkey, NVIDIA App (NVIDIA cards only)
   - at every login, in the background: driver and app updates, cleanup, crash checks, a self-test
'@ -ForegroundColor Yellow
    if ($WithClaude) {
        Write-Host @'
   - WITH CLAUDE: also installs Claude Code and Messiah, which runs WITHOUT permission prompts and needs
     your own Claude account (Pro or higher)
'@ -ForegroundColor Yellow
    }
    Write-Host @'
  Everything can be removed later with C:\PCSetupKit\uninstall.ps1 (-RevertTweaks puts Windows settings back).

'@ -ForegroundColor Yellow
    if ((Read-Host 'Type YES to set up this PC') -ne 'YES') { 'Cancelled - nothing was changed.'; return }
}

$ProgressPreference = 'SilentlyContinue'
# The newest release that passed its test installs ("latest"): GitHub's API, else the web page's redirect (the API
# allows only 60 requests an hour per network). Never the unreleased main branch - it may hold a release still being tested.
$tag = try { (Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'pc-setup-kit' } -TimeoutSec 30).tag_name } catch { $null }
if (-not $tag) {
    try { $r = Invoke-WebRequest "https://github.com/$repo/releases/latest" -Method Head -UseBasicParsing -TimeoutSec 30; if ("$($r.BaseResponse.ResponseUri)" -match '/releases/tag/([^/?#]+)$') { $tag = $Matches[1] } } catch {}
}
if (-not $tag) { throw "Couldn't reach GitHub to find the newest release - check the internet connection and try again in a few minutes. Nothing was changed." }
$url = "https://github.com/$repo/archive/refs/tags/$tag.zip"
$dest = if ($DownloadOnly) { $DownloadOnly } else { Join-Path $env:TEMP 'pc-setup-kit' }
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
New-Item $dest -ItemType Directory -Force | Out-Null
Write-Host "Downloading the PC Setup Kit $(if ($tag) { $tag } else { '(latest)' })..." -ForegroundColor Cyan
Invoke-WebRequest $url -OutFile "$dest\kit.zip" -UseBasicParsing
Expand-Archive "$dest\kit.zip" "$dest\x" -Force
$kit = Get-ChildItem "$dest\x" -Directory | Select-Object -First 1 | ForEach-Object { "$($_.FullName)\PCSetupKit" }
if (-not (Test-Path "$kit\setup.ps1")) { throw "The download doesn't contain PCSetupKit\setup.ps1 - try again later." }
if ($tag) { $tag | Set-Content "$kit\kit-version.txt" }   # setup copies it to C:\PCSetupKit; kit-update.ps1 continues from there
if ($DownloadOnly) { "Downloaded $(if ($tag) { $tag } else { 'main' }) to $kit"; return }
& "$kit\setup.ps1" -WithClaude:$WithClaude
