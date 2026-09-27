# PC Setup Kit - one-command install on an existing Windows 11 PC. In PowerShell (it asks for admin by itself):
#   irm https://raw.githubusercontent.com/Kevincxv/pc-setup-kit/main/install.ps1 | iex
# Downloads the newest release, then runs PCSetupKit\setup.ps1 (tweaks, apps, Messiah + zero maintenance).
# -DownloadOnly <folder>: only download and unpack (used for testing).
param([string]$DownloadOnly)
$ErrorActionPreference = 'Stop'
$repo = 'Kevincxv/pc-setup-kit'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $DownloadOnly -and -not $isAdmin) {
    Write-Host 'Asking for administrator rights...' -ForegroundColor Cyan
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', "irm https://raw.githubusercontent.com/$repo/main/install.ps1 | iex"
    return
}
if (-not $DownloadOnly) {
    Write-Host @'

  PC SETUP KIT
  This sets up this PC like a tuned gaming PC and installs Messiah, which then keeps it maintained by itself:
   - removes Windows bloat and ads, turns off telemetry and AI features, applies gaming tweaks
     (also turns memory integrity / VBS off for performance)
   - installs Git, Steam, Discord, Chrome, WinDbg, AutoHotkey, NVIDIA App (NVIDIA cards only) and Claude Code
   - Messiah runs WITHOUT permission prompts and needs your own Claude account (Pro or higher)
  Everything can be removed later with C:\PCSetupKit\uninstall.ps1 (-RevertTweaks puts Windows settings back).

'@ -ForegroundColor Yellow
    if ((Read-Host 'Type YES to set up this PC') -ne 'YES') { 'Cancelled - nothing was changed.'; return }
}

$ProgressPreference = 'SilentlyContinue'
$tag = try { (Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'pc-setup-kit' }).tag_name } catch { $null }
$url = if ($tag) { "https://github.com/$repo/archive/refs/tags/$tag.zip" } else { "https://github.com/$repo/archive/refs/heads/main.zip" }
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
& "$kit\setup.ps1"
