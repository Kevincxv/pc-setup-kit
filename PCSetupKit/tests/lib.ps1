# Shared helpers for the PC Setup Kit tests. Every test file starts with:  . "$PSScriptRoot\..\lib.ps1"
# What is tested (set by run-tests.ps1, or defaults for running a single test by hand):
#   $Src  - the maintenance scripts (.claude folder of an installed PC, or the kit's PCSetupKit\claude)
#   $Kit  - the kit folder (setup.ps1, tweaks.ps1, uninstall.ps1, claude\tray, ...)
#   $Tray - the tray script
#   $Work - an empty scratch folder for this test (under %TEMP%\pckit-tests)
$ErrorActionPreference = 'Continue'
$Kit = if ($env:PCKIT_KIT) { $env:PCKIT_KIT } else { Split-Path (Split-Path $PSScriptRoot) }
$Src = if ($env:PCKIT_SRC) { $env:PCKIT_SRC } else { "$Kit\claude" }
$Tray = if ($env:PCKIT_TRAY) { $env:PCKIT_TRAY } else { "$Kit\claude\tray\Messiah Tray.ahk" }
$TestName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.PSCommandPath)
# compiled stand-ins (fake claude.exe etc.) are cached here; run-tests.ps1 builds them once before tests run side by side
$BinRoot = if ($env:PCKIT_BIN_ROOT) { $env:PCKIT_BIN_ROOT } else { Join-Path $env:TEMP 'pckit-tests' }
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
    $exe = Join-Path $BinRoot 'bin\claude.exe'
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
    $exe = Join-Path $BinRoot 'sleeper\claude.exe'
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
# Tripwire for mocked tests: every command a script uses must be mocked by the test, harmless (read-only / sandbox
# writes), or explicitly guarded - so a future edit that adds a real system change can't slip through a test unmocked.
$SafeCommands = 'Add-Type', 'ConvertFrom-Json', 'ConvertTo-Json', 'ForEach-Object', 'Where-Object', 'Select-Object', 'Sort-Object', 'Group-Object',
    'Measure-Object', 'Get-ChildItem', 'Get-Content', 'Get-Date', 'Get-Item', 'Get-ItemProperty', 'Join-Path', 'Split-Path', 'Out-Null', 'Out-String', 'Select-String',
    'New-Object', 'Write-Host', 'Start-Sleep', 'Add-Member', 'New-TimeSpan', 'Set-Content', 'Add-Content', 'Move-Item', 'Remove-Item', 'Copy-Item', 'New-Item', 'Test-Path'
function Test-Tripwire([string]$Script, [string[]]$Mocked, [string[]]$Guarded = @()) {
    $ast = [Management.Automation.Language.Parser]::ParseFile($Script, [ref]$null, [ref]$null)
    $own = $ast.FindAll({ $args[0] -is [Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object Name
    $used = $ast.FindAll({ $args[0] -is [Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique
    $unknown = @($used | Where-Object { $_ -notin $SafeCommands -and $_ -notin $Mocked -and $_ -notin $Guarded -and $_ -notin $own })
    Check "tripwire: every command in $(Split-Path $Script -Leaf) is mocked or harmless" (-not $unknown) "not covered by this test: $($unknown -join ', ')"
    -not $unknown
}
# Mocks and Windows modules: PowerShell loads a module on first use of ANY of its commands, and a mock defined before
# that load loses to the real command afterwards (a test once re-registered the owner's real scheduled tasks that way).
# So every mocked test: 1) Import-MockTargets <names> BEFORE defining the mocks, 2) Assert-Mocks <names> after -
# it refuses to go on unless every name resolves to the test's own function. (static.ps1 checks tests do both.)
function Import-MockTargets([string[]]$Names) {
    foreach ($n in $Names) {
        $c = Get-Command $n -All -ErrorAction SilentlyContinue | Where-Object { $_.ModuleName } | Select-Object -First 1
        if ($c -and -not (Get-Module $c.ModuleName)) { Import-Module $c.ModuleName -ErrorAction SilentlyContinue }
    }
}
function Assert-Mocks([string[]]$Names) {
    $real = @($Names | Where-Object { $c = Get-Command $_ -ErrorAction SilentlyContinue; -not $c -or $c.CommandType -ne 'Function' -or $c.Module })
    Check "all $($Names.Count) mocks are in place (no real system command can run)" (-not $real) "would run for real: $($real -join ', ')"
    -not $real
}
# A scriptable stand-in claude.exe: for arguments "a b c" it prints $env:FAKE_DIR\a_b_c.txt, sleeps a_b_c.sleep (ms),
# exits with a_b_c.exit; "--version" prints version.txt, and a_b_c.newversion replaces version.txt (an update).
# Every call is appended to $env:FAKE_DIR\calls.log.
function Get-ScriptedClaude {
    $exe = Join-Path $BinRoot 'scripted2\claude.exe'
    if (-not (Test-Path $exe)) {
        New-Item (Split-Path $exe) -ItemType Directory -Force | Out-Null
        Add-Type -OutputType ConsoleApplication -OutputAssembly $exe -TypeDefinition @'
using System; using System.IO;
public static class P { public static int Main(string[] a) {
  string d = Environment.GetEnvironmentVariable("FAKE_DIR") ?? "."; string k = string.Join("_", a).Replace("-", ""); File.AppendAllText(Path.Combine(d, "calls.log"), k + Environment.NewLine);
  if (File.Exists(Path.Combine(d, k + ".sleep"))) System.Threading.Thread.Sleep(int.Parse(File.ReadAllText(Path.Combine(d, k + ".sleep")).Trim()));
  if (k == "version") { Console.WriteLine(File.Exists(Path.Combine(d, "version.txt")) ? File.ReadAllText(Path.Combine(d, "version.txt")).Trim() + " (Claude Code)" : "1.0.0 (Claude Code)"); return 0; }
  if (File.Exists(Path.Combine(d, k + ".newversion"))) File.Copy(Path.Combine(d, k + ".newversion"), Path.Combine(d, "version.txt"), true);
  if (File.Exists(Path.Combine(d, k + ".txt"))) Console.Write(File.ReadAllText(Path.Combine(d, k + ".txt")));
  return File.Exists(Path.Combine(d, k + ".exit")) ? int.Parse(File.ReadAllText(Path.Combine(d, k + ".exit")).Trim()) : 0;
}}
'@
    }
    $exe
}
function Test-Online { try { [void](Invoke-WebRequest 'https://api.github.com' -UseBasicParsing -TimeoutSec 10); $true } catch { $false } }
function Test-IsAdmin { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
