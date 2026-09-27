# Analyzes a crash dump with Microsoft's debugger (WinDbg package, winget Microsoft.WinDbg) and prints a one-line
# verdict: bugcheck, the module/driver blamed, and the failure bucket. Symbols are cached in %LOCALAPPDATA%\CrashSymbols
# (first run downloads them, which can take a few minutes). Needs admin for kernel dumps.
# Usage: & "$env:USERPROFILE\.claude\crash-analyze.ps1" -Dump C:\Windows\Minidump\xxxx.dmp [-Full]
param([Parameter(Mandatory)][string]$Dump, [switch]$Full)
$pkg = Get-AppxPackage -AllUsers Microsoft.WinDbg | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pkg) { 'Crash analysis unavailable: WinDbg not installed (winget install Microsoft.WinDbg)'; return }
$kernel = (Split-Path $Dump -Leaf) -match '^(MEMORY|Mini|\d{6}-\d+-\d+)' -or $Dump -match '\\Minidump\\|MEMORY\.DMP$'
$dbg = Join-Path $pkg.InstallLocation ("amd64\" + $(if ($kernel) { 'kd.exe' } else { 'cdb.exe' }))
$sym = "srv*$env:LOCALAPPDATA\CrashSymbols*https://msdl.microsoft.com/download/symbols"
$out = & $dbg -z $Dump -y $sym -c '!analyze -v; q' 2>&1 | Out-String
if ($Full) { return $out }
function F($k) { if ($out -match "(?m)^\s*$k\s*[:=]\s*(.+)$") { $Matches[1].Trim() } }
$code = F 'BUGCHECK_CODE'; if (-not $code) { $code = F 'EXCEPTION_CODE_STR' }
$mod = F 'MODULE_NAME'; $img = F 'IMAGE_NAME'; $bucket = F 'FAILURE_BUCKET_ID'; $proc = F 'PROCESS_NAME'
if (-not ($mod -or $img -or $bucket)) { "Analysis inconclusive for $(Split-Path $Dump -Leaf) (run with -Full for the debugger output)"; return }
"code $code | blamed: $img ($mod) | process: $proc | bucket: $bucket"
