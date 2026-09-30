# Builds Install-Messiah.exe from Installer.cs with the C# compiler that comes with Windows (.NET Framework 4) - no SDK,
# nothing downloaded. The app's icon is drawn by the kit's own app-icon.ps1. Used by .github\workflows\sign.yml.
# -Version: the release (v2026.09.29.2 or 2026.9.29.2) - stamped into the file with the product name (SignPath needs both).
param([string]$Out = "$PSScriptRoot\out\Install-Messiah.exe", [string]$Version = '0.0.0.0')
$ErrorActionPreference = 'Stop'
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { throw "C# compiler not found: $csc" }
$v = (($Version -replace '^v', '') -split '\.' | ForEach-Object { [int]$_ }) + @(0, 0, 0, 0) | Select-Object -First 4
$v = $v -join '.'
$dir = Split-Path $Out; New-Item $dir -ItemType Directory -Force | Out-Null
$ico = Join-Path $dir 'app.ico'
& (Join-Path $PSScriptRoot '..\..\PCSetupKit\claude\app-icon.ps1') -Path $ico | Out-Null
$info = Join-Path $dir 'Version.g.cs'
"[assembly: System.Reflection.AssemblyVersion(`"$v`")]`n[assembly: System.Reflection.AssemblyFileVersion(`"$v`")]`n[assembly: System.Reflection.AssemblyInformationalVersion(`"$Version`")]" | Set-Content $info -Encoding ASCII
& $csc /nologo /target:exe /optimize+ /platform:anycpu "/win32icon:$ico" "/out:$Out" (Join-Path $PSScriptRoot 'Installer.cs') $info
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Out)) { throw "build failed ($LASTEXITCODE)" }
$fi = (Get-Item $Out).VersionInfo
"built $Out ($((Get-Item $Out).Length) bytes) - $($fi.ProductName) $($fi.FileVersion)"
