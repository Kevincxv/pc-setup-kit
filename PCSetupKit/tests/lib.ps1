# Shared helpers for the PC Setup Kit tests. Every test file starts with:  . "$PSScriptRoot\..\lib.ps1"
# What is tested (set by run-tests.ps1, or defaults for running a single test by hand):
#   $Src  - the maintenance scripts (.claude folder of an installed PC, or the kit's PCSetupKit\claude)
#   $Kit  - the kit folder (setup.ps1, tweaks.ps1, uninstall.ps1, claude\tray, ...)
#   $Tray - the tray script
#   $Work - an empty scratch folder for this test (under %TEMP%\pckit-tests)
$ErrorActionPreference = 'Continue'
$Kit = if ($env:PCKIT_KIT) { $env:PCKIT_KIT } else { Split-Path (Split-Path $PSScriptRoot) }
$Src = if ($env:PCKIT_SRC) { $env:PCKIT_SRC } else { "$Kit\claude" }
$Tray = if ($env:PCKIT_TRAY) { $env:PCKIT_TRAY } else { "$Kit\claude\tray\Claude Admin Tray.ahk" }
$TestName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.PSCommandPath)
$Work = Join-Path $env:TEMP "pckit-tests\$TestName-$(Get-Date -Format HHmmss)-$(Get-Random -Maximum 999)"
New-Item $Work -ItemType Directory -Force | Out-Null
$script:pass = 0; $script:fail = 0; $script:skip = 0

function Check([string]$Name, $Cond, $Detail) {
    if ($Cond) { $script:pass++; Write-Host "  PASS  $Name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}
function Skip([string]$Name, [string]$Why) { $script:skip++; Write-Host "  SKIP  $Name ($Why)" -ForegroundColor DarkGray }
function Section([string]$Title) { Write-Host "`n  == $Title" -ForegroundColor Cyan }
# End of every test: one machine-readable line for the runner, exit code 1 on any failure
function Finish { "RESULT $TestName pass=$script:pass fail=$script:fail skip=$script:skip"; exit [int]($script:fail -gt 0) }

function Stop-Tree([int]$ProcId) {
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcId" | ForEach-Object { Stop-Tree $_.ProcessId }
    Stop-Process -Id $ProcId -Force -ErrorAction SilentlyContinue
}
# Deletes a scratch path without Remove-Item (some safety tools block Remove-Item on paths named like the kit)
function Clear-Path([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::Delete($Path) }
    elseif (Test-Path -LiteralPath $Path) { [IO.Directory]::Delete($Path, $true) }
}
# A stand-in claude.exe that records how it was called (args, stdin, env) to $env:FAKE_LOG and exits
function Get-FakeClaude {
    $exe = Join-Path $env:TEMP 'pckit-tests\bin\claude.exe'
    if (-not (Test-Path $exe)) {
        New-Item (Split-Path $exe) -ItemType Directory -Force | Out-Null
        Add-Type -OutputType ConsoleApplication -OutputAssembly $exe -TypeDefinition @'
using System; using System.IO; using System.Text;
public static class P { public static void Main(string[] a) {
  var sb = new StringBuilder();
  sb.AppendLine("CWD=" + Environment.CurrentDirectory);
  sb.AppendLine("AUTOSTART_ENV=" + Environment.GetEnvironmentVariable("CLAUDE_ADMIN_AUTOSTART"));
  foreach (var x in a) sb.AppendLine("ARG=" + x);
  if (Console.IsInputRedirected) { var s = new StreamReader(Console.OpenStandardInput(), Encoding.UTF8).ReadToEnd(); sb.AppendLine("STDIN=" + s.Replace("\r","").Replace("\n","\\n")); }
  var log = Environment.GetEnvironmentVariable("FAKE_LOG"); if (!string.IsNullOrEmpty(log)) File.WriteAllText(log, sb.ToString(), Encoding.UTF8);
}}
'@
    }
    $exe
}
# A stand-in claude.exe that just stays alive for 30 s (holds a conversation "open")
function Get-SleeperClaude {
    $exe = Join-Path $env:TEMP 'pckit-tests\sleeper\claude.exe'
    if (-not (Test-Path $exe)) {
        New-Item (Split-Path $exe) -ItemType Directory -Force | Out-Null
        Add-Type -OutputType ConsoleApplication -OutputAssembly $exe -TypeDefinition 'public static class S { public static void Main(string[] a) { System.Threading.Thread.Sleep(30000); } }'
    }
    $exe
}
# Runs a script in a separate PowerShell with a different USERPROFILE (a sandbox home); returns its output
function Invoke-As([string]$Home_, [string]$Script, [string[]]$ArgList = @(), [hashtable]$Env = @{}) {
    $psi = New-Object Diagnostics.ProcessStartInfo 'powershell.exe'
    $psi.Arguments = "-NoProfile -NoLogo -ExecutionPolicy Bypass -File `"$Script`" " + (($ArgList | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['USERPROFILE'] = $Home_
    foreach ($k in $Env.Keys) { if ($null -eq $Env[$k]) { $psi.EnvironmentVariables.Remove($k) } else { $psi.EnvironmentVariables[$k] = $Env[$k] } }
    $p = [Diagnostics.Process]::Start($psi); $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    [void]$p.WaitForExit(600000)
    [pscustomobject]@{ Out = $o.Result; Err = $e.Result; Code = $p.ExitCode }
}
function Test-Online { try { [void](Invoke-WebRequest 'https://api.github.com' -UseBasicParsing -TimeoutSec 10); $true } catch { $false } }
function Test-IsAdmin { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
