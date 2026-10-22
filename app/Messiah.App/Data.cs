using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Management;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

namespace Messiah
{
    class Section { public string Title; public List<Line> Lines = new List<Line>(); }

    // What the pages show, read in the background (never on the window's thread): status-lib.ps1's Get-KitStatus and the
    // small readers dashboard.ps1 called while building a page
    static class Data
    {
        [DllImport("kernel32.dll")] static extern ulong GetTickCount64();
        public static DateTime BootTime => DateTime.Now - TimeSpan.FromMilliseconds(GetTickCount64());

        // --- Claude Code's version: asked once (a process), then kept
        static string claudeVer;
        public static string ClaudeVersion()
        {
            if (claudeVer != null) return claudeVer;
            try
            {
                var exe = Path.Combine(Kit.Home, @".local\bin\claude.exe");
                if (!File.Exists(exe)) return claudeVer = "";
                var p = Process.Start(new ProcessStartInfo(exe, "--version") { UseShellExecute = false, RedirectStandardOutput = true, CreateNoWindow = true });
                var o = p.StandardOutput.ReadToEnd(); p.WaitForExit(5000);
                return claudeVer = (o.Trim().Split(' ').FirstOrDefault() ?? "");
            }
            catch { return claudeVer = ""; }
        }

        // --- the status sections (status-lib.ps1, the same titles and words)
        public static List<Section> KitStatus(bool ai)
        {
            var secs = new List<Section>(); Section cur = null;
            void Sec(string t) { cur = new Section { Title = t }; secs.Add(cur); }
            void Ln(string t, string lv = "info") => cur.Lines.Add(new Line(t, lv));
            var state = Kit.ReadJson(Kit.P("maint-state.json")) ?? new Dictionary<string, object>();
            string Next(string key, int days) { var d = Kit.Date(Json.Get(state, key)); if (d == null) return "due now"; var n = d.Value.AddDays(days); return n < DateTime.Now ? "due now" : n.ToString("MMM d, yyyy"); }

            if (ai) { Sec("Messiah"); Ln("Claude Code " + ClaudeVersion()); }

            Sec("Needs you");
            var todo = Kit.Lines(Kit.P("maint-todo.txt")).Where(x => x.Trim() != "").ToList();
            if (todo.Count > 0) foreach (var t in todo) Ln("- " + t, "warn"); else Ln("Nothing", "ok");

            Sec("Waiting for your next shutdown or restart");
            var led = Kit.ReadJson(Kit.P("restart-ledger.json"));
            var items = Json.L(led, "items").ToList();
            if (items.Count > 0) { foreach (var i in items) Ln("- " + Json.S(i, "Name")); Ln("These finish by themselves the next time you turn the PC off; the check after that confirms it.", "dim"); }
            else Ln("Nothing", "ok");

            Sec("Last background check");
            if (!Kit.InTests && Mutex.TryOpenExisting(@"Global\ClaudeBgMaint", out var m)) { m.Dispose(); Ln("Background maintenance is running right now - the result shows here when it finishes", "ok"); }
            var r = Kit.Lines(Kit.P("maint-report.txt"));
            if (r.Length > 0)
            {
                Ln(r[0]);
                var notable = r.Where(x => Regex.IsMatch(x, "WARNING|FAILED|REBOOT|Reminder|Restart check|installed|Updated|re-applied|rolled back|Driver guard")).ToList();
                if (notable.Count > 0) foreach (var x in notable) Ln(x, Regex.IsMatch(x, "WARNING|FAILED") ? "warn" : "info"); else Ln("All fine", "ok");
            }
            else Ln("No report yet");

            if (ai)
            {
                Sec("Hidden Claude maintenance (about 2 minutes after each login)");
                var busy = Kit.P("maint-claude-running");
                if (File.Exists(busy) && File.GetLastWriteTime(busy) > BootTime) Ln("Running now (tray menu > Watch maintenance live)", "warn");
                try
                {
                    var last = Directory.Exists(Kit.P("maint-claude-log")) ? new DirectoryInfo(Kit.P("maint-claude-log")).GetFiles("*.md").OrderByDescending(f => f.Name).FirstOrDefault() : null;
                    if (last != null) Ln($"Last run: {last.LastWriteTime:g} ({Regex.Replace(Path.GetFileNameWithoutExtension(last.Name), @"^\d+-\d+-?", "")})");
                }
                catch { }
                if (File.Exists(Kit.P("selfimprove-last"))) { var si = File.GetLastWriteTime(Kit.P("selfimprove-last")); Ln($"Self-improvement: last {si:g}; next at the first login after {si.AddHours(20):g}"); }
            }

            Sec("Scheduled checks");
            Ln($"App updates:       {Next("weekly-apps", 7)}");
            Ln($"Monthly cleanup:   {Next("monthly-cleanup", 30)}");
            Ln($"Quarterly check:   {Next("claude-quarterly", 90)}  (benchmark vs setup; hardware)");
            Ln($"Half-year check:   {Next("claude-halfyear", 180)}  (dusting reminder)");
            Ln($"Yearly re-optimize: {Next("claude-yearly", 365)}");
            var st = Kit.ReadJson(Kit.P("self-test.json")); var std = Kit.Date(Json.Get(st, "date"));
            if (st != null && std != null)
            {
                var ok = Json.B(st, "ok"); var failed = Json.L(st, "failed").Select(x => x.ToString()).ToList();
                var next = std.Value.AddDays(7) < DateTime.Now ? "at the next login" : std.Value.AddDays(7).ToString("d");
                Ln($"Self-test:         {(ok ? $"passed {std.Value:d} ({Json.S(st, "result")})" : $"FAILED {std.Value:d} ({Json.S(st, "result")}{(failed.Count > 0 ? " in " + string.Join(", ", failed) : "")})")}; next {next} or after a kit update", ok ? "info" : "warn");
            }
            else Ln("Self-test:         at the next login (tests the maintenance scripts, weekly)");
            var kv = Kit.FirstLine(Path.Combine(Kit.KitDir, "kit-version.txt"));
            if (kv != "") Ln($"Kit version:       {kv} (updates itself)", "dim");
            return secs;
        }

        // --- a game running right now (game-check.ps1 -NoLearn: read-only; this window in front never counts as one)
        static readonly string[] NotGames = { "explorer", "ApplicationFrameHost", "ShellExperienceHost", "StartMenuExperienceHost", "SearchHost", "LockApp", "chrome", "msedge", "firefox",
            "opera", "brave", "vivaldi", "vlc", "mpc-hc64", "mpc-be64", "PotPlayerMini64", "mpv", "Video.UI", "Microsoft.Media.Player", "POWERPNT", "Teams",
            "Discord", "steamwebhelper", "powershell", "WindowsTerminal", "conhost", "AutoHotkey64", "Messiah", "MessiahApp", "MessiahApp", "PC Setup Kit", "obs64",
            "steam", "EpicGamesLauncher", "Battle.net", "EADesktop", "GalaxyClient", "upc", "RiotClientServices", "Better2k", "SaveTheGame", "revival-client", "Slums 2K Launcher" };
        static readonly Regex Libs = new Regex(@"\\steamapps\\common\\|\\Epic Games\\(?!Launcher\\)|\\XboxGames\\(?!GameSave\\)|\\EA Games\\|\\GOG Galaxy\\Games\\|\\GOG Games\\|\\Ubisoft Game Launcher\\games\\", RegexOptions.IgnoreCase);
        static readonly string[] Overlays = { "TextInputHost", "ShellExperienceHost", "StartMenuExperienceHost", "SearchHost", "LockApp", "NVIDIA Overlay", "GameBar", "XboxGameBar", "codex-computer-use" };
        static readonly string[] Tools = { "wallpaper32", "wallpaper64", "webwallpaper32", "ui32", "LosslessScaling", "UnityCrashHandler64", "UnityCrashHandler32", "CrashReportClient" };
        public static string Playing()
        {
            var t = Environment.GetEnvironmentVariable("PCKIT_GAME_TEST"); if (!string.IsNullOrEmpty(t)) return t;
            if (Kit.InTests) return "";
            try
            {
                string fgName = null; bool covers = false; int state = 0;
                var fg = Native.GetForegroundWindow();
                if (fg != IntPtr.Zero)
                {
                    Native.GetWindowThreadProcessId(fg, out var pid);
                    try { using (var p = Process.GetProcessById((int)pid)) fgName = p.ProcessName; } catch { }
                    var cls = new StringBuilder(64); Native.GetClassName(fg, cls, 64);
                    covers = Native.Covers(fg);
                    Native.SHQueryUserNotificationState(out state);
                    if (Regex.IsMatch(cls.ToString(), "^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$")) { covers = false; state = 0; }
                }
                // (state 2/4 with the window in front not covering its monitor: the window really covering one behind it, else
                // nothing - an always-on overlay says "fullscreen" too; game-check.ps1, 10/21)
                var behind = !covers && (state == 2 || state == 4) ? Native.Behind(fg, Overlays) : "";
                bool why = covers || state == 3 || behind != "", own = why;
                if (!covers && state != 3 && behind != "") fgName = behind;
                if (why && own && fgName != null && !NotGames.Contains(fgName, StringComparer.OrdinalIgnoreCase)) return fgName;
                if (why) return fgName ?? "";
                // (the process list once - not a full scan per known game - and each program's path the quick way, not
                // through its loaded modules: 820 ms -> a few ms; the answer kept 30 s, as game-check.ps1's callers do)
                if (DateTime.Now < bgUntil) return bgGame;
                var procs = Process.GetProcesses(); bgUntil = DateTime.Now.AddSeconds(30); bgGame = "";
                try
                {
                    var running = new HashSet<string>(procs.Select(p => p.ProcessName), StringComparer.OrdinalIgnoreCase);
                    var known = Kit.Lines(Kit.P("games.txt")).Select(x => x.Split('#')[0].Trim()).Where(x => x != "" && !NotGames.Contains(x, StringComparer.OrdinalIgnoreCase));
                    bgGame = known.FirstOrDefault(running.Contains) ?? "";
                    if (bgGame != "") return bgGame;
                    foreach (var p in procs)
                    {
                        if (Tools.Contains(p.ProcessName, StringComparer.OrdinalIgnoreCase) || NotGames.Contains(p.ProcessName, StringComparer.OrdinalIgnoreCase)) continue;
                        var path = Native.ImagePath(p.Id);
                        if (path != null && Libs.IsMatch(path)) return bgGame = p.ProcessName;
                    }
                }
                finally { foreach (var p in procs) p.Dispose(); }
            }
            catch { }
            return "";
        }
        static DateTime bgUntil = DateTime.MinValue; static string bgGame = "";

        // --- paused (paused.ps1): kit-options "pause-until=<local time>", while it's still ahead
        public static DateTime? PausedUntil() { var d = Kit.Date(Kit.Opt("pause-until", "")); return d != null && d > DateTime.Now ? d : null; }

        // --- what's new after an update (whats-new.json from kit-update.ps1): until "Got it", three weeks at most
        public static Dictionary<string, object> WhatsNew()
        {
            var w = Kit.ReadJson(Kit.P("whats-new.json")); if (w == null || Json.S(w, "version") == "") return null;
            var d = Kit.Date(Json.Get(w, "date")); if (d != null && d < DateTime.Now.AddDays(-21)) return null;
            if (Kit.Opt("newsseen", "") == Json.S(w, "version")) return null;
            return w;
        }

        // --- crash-hunting modes left on (diag-modes.ps1, read-only here - the script keeps diag-state.json)
        public class Diag { public string Id, Name; public DateTime Since; public int Days; }
        public static List<Diag> DiagModes()
        {
            var on = new List<(string, string)>();
            try
            {
                // (tests: PCKIT_DIAG_TEST="<VerifyDrivers>|<SystemStartOptions>" stands in for the registry)
                var t = Kit.InTests ? Environment.GetEnvironmentVariable("PCKIT_DIAG_TEST") : null; var tp = t != null && t.Contains("|") ? t.Split('|') : null;
                var vd = tp != null ? tp[0].Trim() : (Microsoft.Win32.Registry.GetValue(@"HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management", "VerifyDrivers", "") ?? "").ToString().Trim();
                var opts = tp != null ? tp[1] : (Microsoft.Win32.Registry.GetValue(@"HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control", "SystemStartOptions", "") ?? "").ToString();
                if (vd != "") { var n = vd.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries).Length; on.Add(("verifier", vd == "*" ? "Driver Verifier (every driver)" : $"Driver Verifier ({n} driver{Kit.S(n)})")); }
                if (Regex.IsMatch(opts, @"(^|\s)DEBUG(\s|=|$)")) on.Add(("debug", "Kernel debugging"));
                if (Regex.IsMatch(opts, @"(^|\s)TESTSIGNING(\s|$)")) on.Add(("testsigning", "Test signing (unsigned drivers allowed)"));
            }
            catch { }
            var st = Kit.ReadJson(Kit.P("diag-state.json"));
            return on.Select(x => { var s = Kit.Date(Json.Get(st, x.Item1)) ?? DateTime.Today; return new Diag { Id = x.Item1, Name = x.Item2, Since = s.Date, Days = (int)(DateTime.Today - s.Date).TotalDays }; }).ToList();
        }
        public static List<string> DiagOffPending()
        {
            var st = Kit.ReadJson(Kit.P("diag-state.json")); var boot = BootTime; var l = new List<string>();
            if (st != null) foreach (var kv in st) if (kv.Key.EndsWith("-off") && Kit.Date(kv.Value) is DateTime t && t > boot) l.Add(kv.Key.Substring(0, kv.Key.Length - 4));
            return l;
        }

        // --- the health over time (health-history.json, perf-history.json, net-history.json): rows with a readable date
        public static List<Dictionary<string, object>> History(string name = "health-history.json")
        {
            var o = Kit.ParseJson(Kit.Text(Kit.P(name)));
            return Json.L(o).OfType<Dictionary<string, object>>().Where(x => Kit.Date(Json.Get(x, "date")) != null).ToList();
        }

        // --- what maintenance changed, newest first (the last 30 saved reports; routine "all fine" lines left out)
        static readonly Regex TimelineRx = new Regex(@"PC Setup Kit updated|went back to|re-applied|Updated app|installed|Driver:|Driver rolled back|Removed|Created a monthly|Restore point created|fetched it again|Restart check: .*finished at");
        public static List<(string When, string Text)> MaintTimeline()
        {
            var o = new List<(string, string)>();
            try
            {
                if (!Directory.Exists(Kit.P("maint-history"))) return o;
                foreach (var f in new DirectoryInfo(Kit.P("maint-history")).GetFiles("report-*.txt").OrderByDescending(x => x.Name))
                {
                    var l = Kit.Lines(f.FullName);
                    var m = l.Length > 0 ? Regex.Match(l[0], "^Checked (.+?) in ") : Match.Empty;
                    // (in the app's own words for dates, like every other page - 10/22 audit: "10/21/2026 7:17 PM" here only)
                    var when = Kit.FormatWhen(m.Success && DateTime.TryParse(m.Groups[1].Value, out var wd) ? wd : f.LastWriteTime);
                    // (a line listing dozens of update packages: its start - the full report has the rest)
                    foreach (var x in l) if (TimelineRx.IsMatch(x) && !Regex.IsMatch(x, "up to date|all still applied")) { var t = x.Trim(); o.Add((when, t.Length > 180 ? t.Substring(0, Math.Max(100, t.LastIndexOf(' ', 175))) + " ... (Full report)" : t)); }
                    if (o.Count >= 40) break;
                }
            }
            catch { }
            return o.Take(40).ToList();
        }
        // --- the alerts kept for the app (notifications.log, "yyyy-MM-dd HH:mm|text", newest last)
        // --- Home's "Since you last looked": what happened while the window was closed - the checks and what they changed,
        // alerts, a blue screen or power-off, a driver / BIOS / RAM change, games measured. Empty: nothing worth a line.
        public static List<Line> SinceLast(DateTime? since)
        {
            var o = new List<Line>(); if (since == null) return o; var t = since.Value;
            try
            {
                var reports = Directory.Exists(P("maint-history")) ? new DirectoryInfo(P("maint-history")).GetFiles("report-*.txt").Where(x => x.LastWriteTime > t).OrderBy(x => x.Name).ToList() : new List<FileInfo>();
                if (reports.Count > 0)
                {
                    var did = reports.SelectMany(r => Kit.Lines(r.FullName)).Select(x => x.Trim()).Where(x => TimelineRx.IsMatch(x) && !Regex.IsMatch(x, "up to date|all still applied")).Distinct().ToList();
                    o.Add(new Line($"{reports.Count} check{Kit.S(reports.Count)} ran" + (did.Count > 0 ? ": " + string.Join("; ", did.Take(3).Select(x => Regex.Replace(x, @"^(WARNING|Reminder):\s*", ""))) + (did.Count > 3 ? $" (+{did.Count - 3} more)" : "") : " - nothing needed changing"),
                        did.Any(x => x.StartsWith("WARNING")) ? "warn" : "info"));
                }
                var crashes = PowerEvents().Where(e => e.At > t).ToList();
                foreach (var e in crashes.Take(2)) o.Add(new Line(e.Kind == "bsod" ? $"A blue screen {Kit.FormatWhen(e.At)}{(e.Code != "" ? $" ({e.Code})" : "")} - Activity > Stability has what was found" : $"The PC went off without shutting down {Kit.FormatWhen(e.At)}", "warn"));
                foreach (var ch in PowerChanges().Where(x => x.At > t).Take(3)) o.Add(new Line($"{ch.What}: {ch.From} -> {ch.To}"));
                var notes = Notes().Where(n => n.When > t).ToList();
                if (notes.Count > 0) o.Add(new Line($"{notes.Count} alert{Kit.S(notes.Count)} - the newest: {notes.Last().Text}", "dim"));
                var games = History("perf-history.json").Where(r => (Kit.Date(Json.Get(r, "date")) ?? DateTime.MinValue) > t).GroupBy(r => Json.S(r, "game")).ToList();
                // a change's verdict that came in meanwhile (its 2nd session after it): better, worse, about the same
                foreach (var g in History("perf-history.json").GroupBy(r => Json.S(r, "game")))
                    foreach (var v in Pages.Performance.Verdicts(g.Key, g.ToList()).Where(x => x.Decided != null && x.Decided > t))
                        o.Add(new Line(v.Text + " - Activity > Performance", v.Level));
                if (games.Count > 0) o.Add(new Line("Games measured: " + string.Join(", ", games.Select(g => $"{g.Key} {Math.Round(Json.N(g.Last(), "fps") ?? 0)} fps")) + " - Activity > Performance", "dim"));
            }
            catch (Exception e) { App.Log("since: " + e.Message); }
            return o;
        }
        static string P(string f) => Kit.P(f);
        public static List<(DateTime When, string Text)> Notes() =>
            Kit.Lines(Kit.P("notifications.log")).Select(l => Regex.Match(l, @"^(\d{4}-\d\d-\d\d \d\d:\d\d)\|(.*)$")).Where(m => m.Success)
                .Select(m => (DateTime.ParseExact(m.Groups[1].Value, "yyyy-MM-dd HH:mm", null), m.Groups[2].Value)).ToList();

        // --- Settings > Tools: the graphics driver, the BIOS (bios-info.ps1's words and pages), the settings backups. The
        // driver and the board don't change while the app runs: read once (Win32_PnPSignedDriver takes about a second).
        public class Gpu { public string Name, Version; public DateTime? Date; }
        public class Bios { public string Maker, Model, Version, Date, Url, Steps; }
        static Gpu gpu; static bool gpuRead; static DateTime gpuUntil; static Bios bios; static bool biosRead;
        public static Gpu GraphicsDriver()
        {
            if ((gpuRead && DateTime.Now < gpuUntil) || Kit.InTests) return gpu; gpuRead = true; gpuUntil = DateTime.Now.AddMinutes(10);   // (a driver update or rollback shows within 10 min)
            try
            {
                using (var s = new ManagementObjectSearcher("SELECT DeviceName, DriverVersion, DriverDate, InfName FROM Win32_PnPSignedDriver WHERE DeviceClass='DISPLAY'"))
                    gpu = s.Get().Cast<ManagementObject>().Where(o => Regex.IsMatch((o["InfName"] ?? "").ToString(), @"^oem\d+\.inf$", RegexOptions.IgnoreCase))
                        .OrderBy(o => Regex.IsMatch((o["DeviceName"] ?? "").ToString(), "NVIDIA") ? 0 : Regex.IsMatch((o["DeviceName"] ?? "").ToString(), "Radeon|AMD") ? 1 : 2)
                        .Select(o => new Gpu { Name = (o["DeviceName"] ?? "").ToString(), Version = (o["DriverVersion"] ?? "").ToString(), Date = o["DriverDate"] != null ? ManagementDateTimeConverter.ToDateTime(o["DriverDate"].ToString()) : (DateTime?)null }).FirstOrDefault();
            }
            catch { }
            return gpu;
        }
        public static Bios BiosInfo()
        {
            if (biosRead) return bios; biosRead = true;
            try
            {
                string One(string q, string p) { using (var s = new ManagementObjectSearcher(q)) return s.Get().Cast<ManagementObject>().Select(o => (o[p] ?? "").ToString().Trim()).FirstOrDefault() ?? ""; }
                var maker = One("SELECT Manufacturer FROM Win32_BaseBoard", "Manufacturer"); var model = One("SELECT Product FROM Win32_BaseBoard", "Product");
                var ver = One("SELECT SMBIOSBIOSVersion FROM Win32_BIOS", "SMBIOSBIOSVersion"); var rd = One("SELECT ReleaseDate FROM Win32_BIOS", "ReleaseDate");
                var date = rd != "" ? ManagementDateTimeConverter.ToDateTime(rd).ToString("yyyy-MM-dd") : "";
                var serial = One("SELECT SerialNumber FROM Win32_BIOS", "SerialNumber"); var cpu = One("SELECT Name FROM Win32_Processor", "Name");
                if (maker == "") return null;
                var m = Uri.EscapeDataString(model); var dash = Regex.Replace(Regex.Replace(model, "[()]", ""), @"\s+", "-");
                var platform = Regex.IsMatch(cpu, "AMD|Ryzen") ? "AMD" : "Intel";
                var hasSerial = serial != "" && !Regex.IsMatch(serial, "^(Default|To be filled|System Serial|0+|None)");
                (string Url, string How) r =
                    Regex.IsMatch(maker, "ASUS") ? ($"https://www.asus.com/supportonly/{m}/helpdesk_bios/", "press Del (or F2) while the logo shows, press F7 for Advanced Mode, then Tool > ASUS EZ Flash 3 Utility") :
                    Regex.IsMatch(maker, "ASRock") ? ($"https://www.asrock.com/mb/{platform}/{m}/index.asp#BIOS", "press F2 (or Del) while the logo shows, then Tool > Instant Flash") :
                    Regex.IsMatch(maker, "Micro-Star|MSI") ? ($"https://www.msi.com/Motherboard/{dash}/support#bios", "press Del while the logo shows, then M-Flash (bottom left); the PC restarts into the flash tool") :
                    Regex.IsMatch(maker, "Gigabyte") ? ($"https://www.gigabyte.com/Motherboard/{dash}/support#support-dl-bios", "press End (or Del) while the logo shows, then Q-Flash") :
                    Regex.IsMatch(maker, "Dell") ? (hasSerial ? $"https://www.dell.com/support/home/product-support/servicetag/{serial}/drivers" : "https://www.dell.com/support/home/", "run the downloaded BIOS file in Windows - it restarts and updates by itself (keep a laptop plugged in)") :
                    Regex.IsMatch(maker, "HP|Hewlett") ? ("https://support.hp.com/drivers", $"enter the serial number {(hasSerial ? $"({serial}) " : "")}on the page, then run the downloaded BIOS file in Windows - it restarts and updates by itself") :
                    Regex.IsMatch(maker, "Lenovo") ? (hasSerial ? $"https://pcsupport.lenovo.com/products/{serial}/downloads" : "https://pcsupport.lenovo.com/", "run the downloaded BIOS file in Windows - it restarts and updates by itself (keep a laptop plugged in)") :
                    ($"https://www.google.com/search?q={Uri.EscapeDataString($"{maker} {model} BIOS download")}", "follow the maker's steps on the page");
                var steps = Regex.IsMatch(maker, "Dell|HP|Hewlett|Lenovo")
                    ? $"1. Open {r.Url} and download the newest BIOS (newer than {ver} from {date}). 2. Close your games and apps, {r.How}. 3. Never turn the PC off while it updates (a few minutes)."
                    : $"1. Open {r.Url} and download the newest BIOS (newer than {ver} from {date}). 2. Unzip it onto a USB stick (FAT32). 3. Restart, {r.How}, and pick the file. 4. Never turn the PC off while it updates (a few minutes; it restarts by itself). 5. Afterwards the BIOS settings are back to defaults: turn EXPO/XMP (the RAM speed) back on.";
                bios = new Bios { Maker = maker, Model = model, Version = ver, Date = date, Url = r.Url, Steps = steps };
            }
            catch { }
            return bios;
        }
        // the newest settings backup (settings-backup.ps1: Documents\PC Setup Kit Backup, or a drive's root folder)
        public static FileInfo LastSettingsBackup()
        {
            var dirs = new List<string> { Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "PC Setup Kit Backup") };
            try { foreach (var d in DriveInfo.GetDrives()) if (d.DriveType == DriveType.Fixed || d.DriveType == DriveType.Removable) dirs.Add(Path.Combine(d.RootDirectory.FullName, "PC Setup Kit Backup")); } catch { }
            return dirs.Where(Directory.Exists).SelectMany(d => { try { return new DirectoryInfo(d).GetFiles("*.zip"); } catch { return new FileInfo[0]; } }).OrderByDescending(f => f.LastWriteTime).FirstOrDefault();
        }

        // --- the chat's state (chat\state.json while its host runs)
        public static Dictionary<string, object> ChatState(string dir = null)
        {
            var j = Kit.ReadJson(Path.Combine(dir ?? Kit.P("chat"), "state.json"));
            var pid = (int)(Json.N(j, "pid") ?? 0);
            if (pid == 0) return null;
            try { using (Process.GetProcessById(pid)) return j; } catch { return null; }
        }

        // --- the RAM stick test (Get-RamTest / Get-RamTestNow: the same steps and words)
        public const int RamNeed = 10;   // starts without a crash before a stick counts as fine
        public static List<Line> RamTest(string[] log, string now, ICollection<string> mine)
        {
            var g = new Dictionary<string, (int Starts, int Crashes, string Since)>(); var order = new List<string>();
            foreach (var l in log)
            {
                // (a memory test that found errors - ram-check.ps1 - counts as a crash for that stick setup: it is proof)
                var mt = Regex.Match(l, @"^(\S+ \S+) \| (stress|boottest) \| (.+?) \| (.+)$");
                if (mt.Success) { if (mt.Groups[4].Value.EndsWith("errors found") || Regex.IsMatch(mt.Groups[4].Value, @": [1-9]\d* errors")) { var ks = mt.Groups[3].Value.Trim(); if (!g.ContainsKey(ks)) { g[ks] = (0, 0, mt.Groups[1].Value); order.Add(ks); } var kv = g[ks]; g[ks] = (kv.Starts, kv.Crashes + 1, kv.Since); } continue; }
                var m = Regex.Match(l, @"^(\S+ \S+) \| (start|crash) \| (.+)$"); if (!m.Success) continue;
                if (m.Groups[2].Value == "crash" && mine != null && mine.Contains(m.Groups[1].Value)) continue;
                var s = m.Groups[3].Value.Trim(); if (!g.ContainsKey(s)) { g[s] = (0, 0, m.Groups[1].Value); order.Add(s); }
                var v = g[s]; g[s] = m.Groups[2].Value == "start" ? (v.Starts + 1, v.Crashes, v.Since) : (v.Starts, v.Crashes + 1, v.Since);
            }
            string Slot(string s) { var m = Regex.Match(s, @"CHANNEL ([A-Z])\s*$"); if (m.Success) return m.Groups[1].Value; m = Regex.Match(s, " in (.+)$"); return m.Success ? m.Groups[1].Value : "?"; }
            var one = new Dictionary<string, (int Starts, int Crashes, string Since)>();
            foreach (var k in order) if (k.StartsWith("1 stick(s)")) one[Slot(k)] = g[k];
            var both = order.FirstOrDefault(k => k.StartsWith("2 stick(s)"));
            var L = new List<Line>();
            if (both != null) { var b = g[both]; L.Add(new Line($"With both sticks in: {b.Starts} start{Kit.S(b.Starts)}, {b.Crashes} blue screen{Kit.S(b.Crashes)} or sudden restart{Kit.S(b.Crashes)} (counted since {Kit.FormatWhen(DateTime.Parse(b.Since), dateOnly: true)}).", "dim")); }
            foreach (var k in new[] { "A", "B" }) if (one.TryGetValue(k, out var o)) L.Add(new Line($"Only the stick in slot {k}: {o.Starts} start{Kit.S(o.Starts)}, {o.Crashes} crash{(o.Crashes == 1 ? "" : "es")}.", o.Crashes > 0 ? "warn" : "dim"));
            bool Done(string k) => one.TryGetValue(k, out var r) && (r.Crashes > 0 || r.Starts >= RamNeed);
            bool Bad(string k) => one.TryGetValue(k, out var r) && r.Crashes > 0;
            const string shut = "shut the PC down (Start > Power > Shut down) and unplug it, then";
            const string warranty = "Keep using the good stick (16 GB is plenty for games) and get the faulty one replaced under Corsair's lifetime warranty (corsair.com > Support > RMA; they usually replace the pair).";
            if (Done("A") && Done("B"))
            {
                if (Bad("A") && !Bad("B")) L.Add(new Line($"Result: the stick from slot A is faulty - the other one ran clean on its own. {warranty} To be extra sure it's the stick and not the slot: put the faulty stick in slot B - if it crashes there too, it's the stick.", "warn"));
                else if (Bad("B") && !Bad("A")) L.Add(new Line($"Result: the stick tested in slot B is faulty - the other one ran clean on its own. {warranty} To be extra sure it's the stick and not the slot: put the faulty stick in slot A - if it crashes there too, it's the stick.", "warn"));
                else if (Bad("A") && Bad("B")) L.Add(new Line("Result: both sticks crashed on their own, so the sticks are most likely fine - the processor's memory controller or the motherboard is the likely cause. That's a warranty case for AMD or ASRock; Claude can help you with it.", "warn"));
                else L.Add(new Line($"Result: neither stick crashed on its own ({RamNeed}+ starts each). The fault may only show with both sticks in, or be rarer than the test caught. Put both sticks back in; Claude can help with the next step."));
            }
            else if (now.StartsWith("1 stick(s)"))
            {
                var k = Slot(now); var other = k == "A" ? "B" : "A";
                if (Done(k)) { var r = one[k]; L.Add(new Line($"Next: {shut} take this stick out and put the OTHER stick in slot {other} on its own. {(Bad(k) ? "This stick crashed on its own - the other one will show whether it's the stick." : $"This stick ran {r.Starts} starts without a crash, so it looks fine.")}", "warn")); }
                else { var n = one.TryGetValue(k, out var r) ? r.Starts : 0; L.Add(new Line($"Now: just use the PC as usual with this stick - {RamNeed - n} more start{Kit.S(RamNeed - n)} to go. Messiah counts them by itself.", "ok")); }
            }
            else if (one.Count == 0) L.Add(new Line($"Step 1 of 2: {shut} take out the stick in slot B (the slot marked B on the motherboard, e.g. DDR5_B1) and leave the other one where it is. Then use the PC as usual for about {RamNeed} starts; Messiah counts them and the crashes by itself. Leave EXPO off during the test.", "warn"));
            else L.Add(new Line($"Both sticks are back in, but the test isn't finished: {shut} put only the stick you haven't tested yet in slot {(one.ContainsKey("A") ? "B" : "A")}.", "warn"));
            return L;
        }
        static string sticks;
        public static List<Line> RamTestNow()
        {
            var st = Kit.ReadJson(Kit.P("maint-state.json"));
            var since = Kit.Date(Json.Get(st, "ram-stick-test")); if (since == null || since < DateTime.Now.AddDays(-60)) return null;
            if (sticks == null)   // (read once: sticks only change with the PC off)
            {
                var labels = new List<string>(); long total = 0;
                try { using (var s = new ManagementObjectSearcher("SELECT BankLabel, Capacity FROM Win32_PhysicalMemory")) foreach (ManagementObject o in s.Get()) { labels.Add((o["BankLabel"] ?? "").ToString().Trim()); total += Convert.ToInt64(o["Capacity"] ?? 0); } } catch { }
                sticks = $"{labels.Count} stick(s), {Math.Round(total / 1073741824.0)} GB in {string.Join(" + ", labels)}";   // (health-check.ps1's words)
            }
            var now = sticks;
            var mine = new HashSet<string>(PowerEvents().Where(e => e.Answer == "me").Select(e => e.Key.ToString("yyyy-MM-dd HH:mm")));
            return RamTest(Kit.Lines(Kit.P("ram-test.log")), now, mine);
        }

        // --- the last game session (game-sessions.log from the tray, the minutes game-perf.ps1 measured in it): how it ran
        // against that game's usual - Home's and Performance's "Last session" (10/22)
        public class Session { public string Game; public DateTime Start, End; public int Minutes, Samples; public double? Fps, Low, UsualFps, UsualLow, GpuTemp, CpuTemp; public int Hitches; }
        public static Session LastSession(List<Dictionary<string, object>> perf, string[] log = null)
        {
            log = log ?? Kit.Lines(Kit.P("game-sessions.log"));
            var m = log.Reverse().Select(l => Regex.Match(l, @"^(\S+) \| (\S+) \| (.+)$")).FirstOrDefault(x => x.Success);
            if (m == null || !DateTime.TryParse(m.Groups[1].Value, out var a) || !DateTime.TryParse(m.Groups[2].Value, out var b)) return null;
            var s = new Session { Game = m.Groups[3].Value.Trim(), Start = a, End = b, Minutes = (int)Math.Round((b - a).TotalMinutes) };
            var mine = perf.Where(r => Json.S(r, "game").Equals(s.Game, StringComparison.OrdinalIgnoreCase)).ToList();
            var inS = mine.Where(r => Kit.Date(Json.Get(r, "date")) is DateTime d && d >= a.AddMinutes(-2) && d <= b.AddMinutes(2)).ToList();
            var before = mine.Where(r => Kit.Date(Json.Get(r, "date")) is DateTime d && d < a).Reverse().Take(10).ToList();
            double? Avg(List<Dictionary<string, object>> rr, string f) { var v = rr.Select(r => Json.N(r, f)).Where(x => x != null).Select(x => x.Value).ToList(); return v.Count > 0 ? v.Average() : (double?)null; }
            double? Max(string f) { var v = inS.Select(r => Json.N(r, f)).Where(x => x != null).Select(x => x.Value).ToList(); return v.Count > 0 ? v.Max() : (double?)null; }
            s.Samples = inS.Count; s.Fps = Avg(inS, "fps"); s.Low = Avg(inS, "low1"); s.UsualFps = Avg(before, "fps"); s.UsualLow = Avg(before, "low1");
            s.GpuTemp = Max("gpuTemp"); s.CpuTemp = Max("cpuTemp"); s.Hitches = (int)inS.Sum(r => Json.N(r, "stutters") ?? 0);
            return s;
        }
        public static List<Line> SessionLines(Session s)
        {
            var o = new List<Line>();
            var len = s.Minutes >= 60 ? $"{s.Minutes / 60} h {s.Minutes % 60} min" : $"{s.Minutes} min";
            if (s.Fps == null) { o.Add(new Line($"{GameName(s.Game)} - {len}, ended {Kit.FormatWhen(s.End)}. Too short to measure (a minute is measured every 25 minutes of play).", "dim")); return o; }
            string Cmp(double v, double? u) => u == null || u <= 0 ? "" : Math.Abs(v - u.Value) / u.Value < 0.05 ? " (as usual)" : v > u ? $" (usual {Math.Round(u.Value)} - better)" : $" (usual {Math.Round(u.Value)} - lower)";
            var worse = s.UsualLow > 0 && s.Low < s.UsualLow * 0.9;
            o.Add(new Line($"{GameName(s.Game)} - {len}, ended {Kit.FormatWhen(s.End)}: {Math.Round(s.Fps.Value)} fps average{Cmp(s.Fps.Value, s.UsualFps)}, 1% low {Math.Round(s.Low ?? 0)} fps{Cmp(s.Low ?? 0, s.UsualLow)}, {s.Hitches} hitch{(s.Hitches == 1 ? "" : "es")}.", worse ? "warn" : "ok"));
            var heat = new List<string>(); if (s.GpuTemp != null) heat.Add($"graphics card up to {s.GpuTemp} °C"); if (s.CpuTemp != null) heat.Add($"processor up to {s.CpuTemp} °C");
            if (heat.Count > 0) o.Add(new Line(char.ToUpper(heat[0][0]) + string.Join(", ", heat).Substring(1) + $" - from {s.Samples} measured minute{Kit.S(s.Samples)}.", (s.GpuTemp ?? 0) >= 85 || (s.CpuTemp ?? 0) >= 88 ? "warn" : "dim"));
            return o;
        }

        // --- a game by its name, not its program's (10/22 audit: "cod", "NBA2K20" on the cards)
        public static string GameName(string proc)
        {
            if (string.IsNullOrEmpty(proc)) return proc ?? "";
            if (proc.Equals("cod", StringComparison.OrdinalIgnoreCase)) return "Call of Duty";
            var m = Regex.Match(proc, @"^NBA ?2K(\d+)$", RegexOptions.IgnoreCase); if (m.Success) return "NBA 2K" + m.Groups[1].Value;
            return proc;
        }

        // --- the memory tests (ram-check.ps1): the nightly one in Windows and Windows' deep one at start-up, newest first
        public class RamCheck { public DateTime At; public string Kind, Setup, Result; public bool Bad; }
        public static List<RamCheck> RamChecks()
        {
            var o = new List<RamCheck>();
            foreach (var l in Kit.Lines(Kit.P("ram-test.log")))
            {
                var m = Regex.Match(l, @"^(\S+ \S+) \| (stress|boottest) \| (.+?) \| (.+)$"); if (!m.Success || !DateTime.TryParse(m.Groups[1].Value, out var at)) continue;
                var r = m.Groups[4].Value; var bad = r.EndsWith("errors found") || Regex.IsMatch(r, @": [1-9]\d* errors");
                o.Add(new RamCheck { At = at, Kind = m.Groups[2].Value, Setup = m.Groups[3].Value, Result = r, Bad = bad });
            }
            o.Reverse(); return o;
        }

        // --- the stability record (power-log.json, power-log.ps1)
        public class PowerEvent { public DateTime Key, At; public string Kind, Code, Answer, KeyText; }
        public class Change { public DateTime At; public string What, From, To; public bool Approx; }
        public static List<PowerEvent> PowerEvents()
        {
            var j = Kit.ReadJson(Kit.P("power-log.json"));
            return Json.L(j, "events").Select(e => new PowerEvent { KeyText = Json.S(e, "key"), Key = Kit.Date(Json.Get(e, "key")) ?? DateTime.MinValue, At = Kit.Date(Json.Get(e, "at")) ?? DateTime.MinValue, Kind = Json.S(e, "kind"), Code = Json.S(e, "code"), Answer = Json.S(e, "answer") })
                .Where(e => e.Key > DateTime.MinValue).ToList();
        }
        public static List<Change> PowerChanges()
        {
            var j = Kit.ReadJson(Kit.P("power-log.json"));
            return Json.L(j, "changes").Select(c => new Change { At = Kit.Date(Json.Get(c, "at")) ?? DateTime.MinValue, What = Json.S(c, "what"), From = Json.S(c, "from"), To = Json.S(c, "to"), Approx = Json.B(c, "approx") }).Where(c => c.At > DateTime.MinValue).ToList();
        }

        // --- a script of the kit, hidden (the actions: todo.ps1, power-log.ps1 ...), optionally waiting for its output
        public static string RunPs(string file, string args, bool wait = true)
        {
            var psi = new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -File \"{Kit.P(file)}\" {args}") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = wait };
            var p = Process.Start(psi); if (!wait) return "";
            var o = p.StandardOutput.ReadToEnd(); p.WaitForExit(60000); return o.Trim();
        }
        public static string Q(string s) => "\"" + (s ?? "").Replace("\"", "\\\"") + "\"";
    }
}
