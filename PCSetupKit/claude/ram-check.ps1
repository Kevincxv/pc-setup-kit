# The memory test (10/22, the owner's request - the 0x109 blue screens with one flipped bit). Two tests, each logged in
# ram-test.log next to the starts and crashes (the app's RAM stick test reads them per stick setup):
# - -Stress (the tray, while the PC is idle): most of the free memory filled with patterns and read back, again and
#   again, on all cores - a flipped bit is an error. Only after 30+ minutes without keyboard or mouse, no game, and it
#   stops within a second of the owner coming back; up to 45 minutes. Every night while blue screens happened in the
#   last 30 days (or the stick test runs), else once a month. The PC is kept from sleeping while it runs.
# - -ArmBoot (the app's button): Windows' own memory test, the extended one, at the next start-up - it tests all of the
#   memory before Windows loads (a few hours; best started at night). Messiah never restarts the PC: the owner does.
#   -CancelBoot takes it back.
# - -Check (health-check.ps1): the boot test's result once it ran, and stress errors not said yet - a WARNING (so it
#   gets looked at) when errors were found.
# kit-options.txt ramcheck=off (the app's Settings) stops the nightly test.
# Tests: -Force, -Seconds, -MB, -Inject (a bit flipped on purpose), -Idle, -Game, -Bsods, -Log, -State, -Setup,
# -Now, -BootAt, -Events, -Do (gets bcdedit's arguments), -Options, -MaintState.
param([switch]$Stress, [switch]$ArmBoot, [switch]$CancelBoot, [switch]$Check, [switch]$Force, [int]$Seconds = 2700, [int]$MB,
    [switch]$Inject, [long]$Idle = -1, [string]$Game, [object[]]$Bsods, [string]$Log = "$PSScriptRoot\ram-test.log",
    [string]$State = "$PSScriptRoot\ram-check.json", [string]$Setup, [datetime]$Now = (Get-Date), [object]$BootAt, [object[]]$Events,
    [scriptblock]$Do, [string]$Options = "$PSScriptRoot\kit-options.txt", [string]$MaintState = "$PSScriptRoot\maint-state.json")
$ErrorActionPreference = 'SilentlyContinue'
$st = try { Get-Content $State -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { $null }
if ($st -isnot [Management.Automation.PSCustomObject]) { $st = [pscustomobject]@{} }
foreach ($k in 'lastStress', 'bootArmed', 'unsaid') { if (-not ($st.PSObject.Properties.Name -contains $k)) { $st | Add-Member $k $null } }
function Save { try { $st | ConvertTo-Json -Depth 3 | Set-Content "$State.tmp" -Encoding UTF8; Move-Item "$State.tmp" $State -Force } catch { } }
# the sticks as health-check.ps1 words them (the stick test groups by this), and their speed
if (-not $Setup) {
    $sticks = @(Get-CimInstance Win32_PhysicalMemory)
    $Setup = "$($sticks.Count) stick(s), $([math]::Round(($sticks | Measure-Object Capacity -Sum).Sum / 1GB)) GB in $(@($sticks | ForEach-Object { "$($_.BankLabel)".Trim() }) -join ' + ')"
    $speed = "$(($sticks | Select-Object -First 1).ConfiguredClockSpeed) MT/s"
}
function Bcd([string]$a) { if ($Do) { & $Do $a } else { $null = & bcdedit.exe ($a -split ' ') 2>&1; $LASTEXITCODE -eq 0 } }

if ($ArmBoot) {
    $ok = (Bcd '/set {memdiag} testmix extended') -and (Bcd '/set {memdiag} passcount 1') -and (Bcd '/bootsequence {memdiag}')
    if (-not $ok) { 'The deep memory test could not be set up (bcdedit refused) - nothing was changed for the next start-up'; return }
    $st.bootArmed = $Now.ToString('o'); Save
    'The deep memory test runs at the next start-up: it tests all of the memory before Windows loads - it can take a few hours, so start it at night: restart the PC yourself (Start > Power > Restart) and leave it. Windows loads by itself after it, and Messiah shows the result (Health > Stability)'
    return
}
if ($CancelBoot) {
    [void](Bcd '/deletevalue {bootmgr} bootsequence'); [void](Bcd '/deletevalue {memdiag} testmix'); [void](Bcd '/deletevalue {memdiag} passcount')
    $st.bootArmed = $null; Save
    'The deep memory test is off - the next start-up is a normal one'
    return
}

if ($Check) {
    # the boot test: once the PC started after it was set up, Windows' own result (MemoryDiagnostics-Results 1201 no
    # errors / 1202 errors; 1101/1102 the same from the start-up itself)
    if ($st.bootArmed) {
        $armed = [datetime]$st.bootArmed
        $boot = if ($BootAt) { [datetime]$BootAt } else { (Get-CimInstance Win32_OperatingSystem).LastBootUpTime }
        if ($boot -gt $armed) {
            $ev = if ($null -ne $Events) { $Events } else { @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results'; StartTime = $armed }) }
            $r = $ev | Where-Object { $_.Id -in 1102, 1202 } | Select-Object -First 1; if (-not $r) { $r = $ev | Where-Object { $_.Id -in 1101, 1201 } | Select-Object -First 1 }
            $line = if (-not $r) { $null } elseif ($r.Id -in 1102, 1202) { 'errors found' } else { 'no errors' }
            [void](Bcd '/deletevalue {memdiag} testmix'); [void](Bcd '/deletevalue {memdiag} passcount')   # (Windows' memory test back to its own default)
            $st.bootArmed = $null; Save
            if ($line) {
                "$($Now.ToString('yyyy-MM-dd HH:mm')) | boottest | $Setup | Windows' extended memory test at start-up: $line" | Add-Content $Log -Encoding UTF8
                if ($line -eq 'errors found') { "WARNING: Windows' deep memory test found errors with $Setup - the memory is faulty: test one stick at a time to find which (Health > Stability shows the steps)" }
                else { "Deep memory test at start-up: no errors with $Setup" }
            }
            elseif ($ev | Where-Object { $_.Id -eq 1103 }) { 'Deep memory test: it was cancelled at start-up - start it again from Health > Stability when it suits you' }
            else { "Deep memory test: it didn't finish (the PC was turned off during it, or it didn't start) - start it again from Health > Stability when it suits you" }
        }
    }
    if ($st.unsaid) {
        "WARNING: the memory test found $($st.unsaid) - the memory is faulty: test one stick at a time to find which (Health > Stability shows the steps)"
        $st.unsaid = $null; Save
    }
    return
}
if (-not $Stress) { return }

# --- the nightly test: when it may run ---
if (-not $Force) {
    if (Select-String -Path $Options -Pattern '^\s*ramcheck\s*=\s*off\s*$' -Quiet) { return }
    $bs = if ($null -ne $Bsods) { $Bsods } else { $pl = try { Get-Content "$PSScriptRoot\power-log.json" -Raw | ConvertFrom-Json } catch { $null }; @($pl.events | Where-Object { $_.kind -eq 'bsod' } | ForEach-Object { [datetime]$_.key }) }
    $ladder = try { [datetime](Get-Content $MaintState -Raw | ConvertFrom-Json).'ram-stick-test' -gt $Now.AddDays(-60) } catch { $false }
    $every = if ($ladder -or @($bs | Where-Object { $_ -gt $Now.AddDays(-30) }).Count) { 20 } else { 24 * 30 }   # hours
    if ($st.lastStress -and [datetime]$st.lastStress -gt $Now.AddHours(-$every)) { return }
}
if (-not ('KitRamTest' -as [type])) {
    $cp = New-Object CodeDom.Compiler.CompilerParameters; $cp.CompilerOptions = '/unsafe /optimize'; [void]$cp.ReferencedAssemblies.Add('System.dll'); [void]$cp.ReferencedAssemblies.Add('System.Core.dll')
    Add-Type -CompilerParameters $cp -TypeDefinition @"
using System; using System.Collections.Generic; using System.Diagnostics; using System.Runtime.InteropServices; using System.Threading; using System.Threading.Tasks;
public static unsafe class KitRamTest {
  [DllImport("kernel32.dll")] static extern IntPtr VirtualAlloc(IntPtr a, UIntPtr size, uint type, uint prot);
  [DllImport("kernel32.dll")] static extern bool VirtualFree(IntPtr a, UIntPtr size, uint type);
  [DllImport("kernel32.dll")] static extern uint SetThreadExecutionState(uint f);
  [StructLayout(LayoutKind.Sequential)] struct LII { public uint cbSize; public uint dwTime; }
  [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LII l);
  [StructLayout(LayoutKind.Sequential)] class MSX { public uint dwLength = 64; public uint load; public ulong totalPhys, availPhys, totalPage, availPage, totalVirt, availVirt, availExt; }
  [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx([In, Out] MSX m);
  public static ulong Total() { var m = new MSX(); GlobalMemoryStatusEx(m); return m.totalPhys; }
  public static ulong Free() { var m = new MSX(); GlobalMemoryStatusEx(m); return m.availPhys; }
  public static uint IdleMs() { var l = new LII(); l.cbSize = 8; GetLastInputInfo(ref l); return unchecked((uint)Environment.TickCount - l.dwTime); }
  const long Block = 64L << 20;
  static long errors; static string first;
  // the value at word i of a block, for a pattern kind and seed: an address mix, its inverse, a random stream, walking bits
  static ulong Next(int kind, ulong i, ulong s, ref ulong x) {
    switch (kind) {
      case 0: return (i * 0x9E3779B97F4A7C15UL) ^ s;
      case 1: return ~((i * 0x9E3779B97F4A7C15UL) ^ s);
      case 2: x ^= x << 13; x ^= x >> 7; x ^= x << 17; return x;
      default: ulong w = 1UL << (int)(i & 63); return (s & 1) == 1 ? ~w : w;
    }
  }
  static void Fill(ulong* p, long n, int kind, ulong s) { ulong x = s | 1; for (long i = 0; i < n; i++) p[i] = Next(kind, (ulong)i, s, ref x); }
  static void Verify(ulong* p, long n, int kind, ulong s, int b) {
    ulong x = s | 1;
    for (long i = 0; i < n; i++) {
      ulong want = Next(kind, (ulong)i, s, ref x), got = p[i];
      if (got != want && Interlocked.Increment(ref errors) == 1) first = "block " + b + " word " + i + ": bits 0x" + (got ^ want).ToString("X16") + " flipped";
    }
  }
  // "passes|GB|errors|stop reason|first error"
  public static string Run(long bytes, int seconds, uint stopIdleMs, bool inject) {
    errors = 0; first = "";
    var blocks = new List<IntPtr>();
    for (long done = 0; done + Block <= bytes; done += Block) { var p = VirtualAlloc(IntPtr.Zero, (UIntPtr)Block, 0x3000, 4); if (p == IntPtr.Zero) break; blocks.Add(p); }
    if (blocks.Count == 0) return "0|0|0|no memory free|";
    SetThreadExecutionState(0x80000001);   // ES_CONTINUOUS | ES_SYSTEM_REQUIRED: no sleep while it runs
    var sw = Stopwatch.StartNew(); int pass = 0; double gb = 0; string stop = "time";
    var po = new ParallelOptions { MaxDegreeOfParallelism = Math.Max(1, Environment.ProcessorCount / 2) };
    try {
      while (true) {
        int kind = pass % 4; ulong seed = (ulong)(pass + 1) * 0xBF58476D1CE4E5B9UL;
        Parallel.For(0, blocks.Count, po, b => Fill((ulong*)blocks[b], Block / 8, kind, seed ^ (ulong)b));
        if (inject && pass == 1) ((ulong*)blocks[0])[4321] ^= 1UL << 9;   // (tests: one bit flipped, as faulty memory would)
        Parallel.For(0, blocks.Count, po, b => Verify((ulong*)blocks[b], Block / 8, kind, seed ^ (ulong)b, b));
        pass++; gb += blocks.Count * (double)Block / (1L << 30);
        if (sw.Elapsed.TotalSeconds >= seconds) { stop = "time"; break; }
        if (stopIdleMs > 0 && IdleMs() < stopIdleMs) { stop = "you came back"; break; }
      }
    } finally { foreach (var p in blocks) VirtualFree(p, UIntPtr.Zero, 0x8000); SetThreadExecutionState(0x80000000); }
    return pass + "|" + Math.Round(gb) + "|" + errors + "|" + stop + "|" + first;
  }
}
"@
}
if (-not $Force) {
    $idleMs = if ($Idle -ge 0) { $Idle } else { [KitRamTest]::IdleMs() }
    if ($idleMs -lt 1800000) { return }
    $g = if ($PSBoundParameters.ContainsKey('Game')) { $Game } else { & "$PSScriptRoot\game-check.ps1" }
    if ($g) { return }
}
$mx = New-Object Threading.Mutex($false, "Global\PCSetupKitRamCheck$(if ($MB) { "-test-$PID" })")
if (-not $mx.WaitOne(0)) { return }
# most of the free memory, leaving 3 GB for Windows and what's open (at most 75% of all of it)
$bytes = if ($MB) { [long]$MB * 1MB } else { [long][Math]::Min([double][KitRamTest]::Free() - 3GB, [double][KitRamTest]::Total() * 0.75) }
if ($bytes -lt 1GB -and -not $MB) { return }
$t0 = Get-Date
$r = ([KitRamTest]::Run($bytes, $Seconds, $(if ($Force) { 0 } else { 60000 }), [bool]$Inject)) -split '\|', 5
$secs = ((Get-Date) - $t0).TotalSeconds; $took = if ($secs -lt 90) { "$([int]$secs) s" } else { "$([int]($secs / 60)) min" }
$st.lastStress = $Now.ToString('o')
$res = "$($r[0]) passes over $($r[1]) GB in $took$(if ($speed) { " at $speed" }): $($r[2]) errors$(if ($r[3] -eq 'you came back') { ' (stopped: you came back)' })"
"$($Now.ToString('yyyy-MM-dd HH:mm')) | stress | $Setup | $res" | Add-Content $Log -Encoding UTF8
if ([long]$r[2] -gt 0) { $st.unsaid = "$($r[2]) error(s) with $Setup ($($r[4]))" }
Save
"Memory test: $res"
