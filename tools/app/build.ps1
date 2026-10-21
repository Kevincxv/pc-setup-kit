# Builds the Messiah app (app\Messiah.App, C# / WPF on .NET Framework 4.8 - part of every Windows 10/11) into
# PCSetupKit\claude\app\MessiahApp.exe, where installs and updates take it from. Needs the .NET SDK (here: winget
# Microsoft.DotNet.SDK.9; GitHub's windows-latest has it). Run by publish-kit.ps1 before each release and by tests.yml.
# -Version: the release (v2026.10.20.1) - stamped into the file. -Out: another folder (the CI build check).
param([string]$Version = '0.0.0', [string]$Out = "$PSScriptRoot\..\..\PCSetupKit\claude\app")
$ErrorActionPreference = 'Stop'
$proj = Join-Path $PSScriptRoot '..\..\app\Messiah.App\Messiah.App.csproj'
$v = (($Version -replace '^v', '') -split '\.' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }) + @(0, 0, 0, 0) | Select-Object -First 4
$tmp = Join-Path $env:TEMP "messiah-app-build-$PID"
try {
    $log = & dotnet build $proj -c Release -nologo -v q "-p:Version=$($v -join '.')" "-p:InformationalVersion=$Version" "-p:OutDir=$tmp\" 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$tmp\MessiahApp.exe")) { $log | Select-Object -Last 30; throw "The app did not build ($LASTEXITCODE)" }
    New-Item $Out -ItemType Directory -Force | Out-Null
    Copy-Item "$tmp\MessiahApp.exe" $Out -Force
    if (Test-Path "$tmp\MessiahApp.exe.config") { Copy-Item "$tmp\MessiahApp.exe.config" $Out -Force }
    $f = Get-Item "$Out\MessiahApp.exe"
    "built $($f.FullName) ($($f.Length) bytes) - $($f.VersionInfo.FileVersion)"
}
finally { if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue } }
