using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Management;
using System.Text.RegularExpressions;
using System.Threading;

namespace Messiah
{
    // The Status tab's model, shared with Home's Guarded tile (dashboard.ps1's Get-StatusModel): every optimization Messiah
    // keeps, one row each, with what the last guard pass found - ok (in place, or put back by that pass), warn (needs a
    // look), dim (off by the owner's choice, or not checked yet). From tweak-status.json (tweaks.ps1 -StatusFile),
    // guard-state.json, diag-state.json and a few live reads. Built in the background: the details are data (More), the
    // page makes them into lines and buttons.
    class StatusRow
    {
        public string Card, Title, Level, State, Detail, Group;
        public string[] Keys; public string About, HistRx;
        public (string Glyph, string Label, string Action)? Fix;   // Action: an id Actions.Run knows
        public List<More> More;                                    // the details behind a click (null: none)
        public string Words => $"{Title} {State} {Detail} {string.Join(" ", (More ?? new List<More>()).Where(m => m.Label != null).Select(m => m.Label + " " + m.Text))}";
    }
    // one line of a row's details: "Label  text", or a small button (Glyph, Text = its words, Action = what it does)
    class More
    {
        public string Label, Text, Glyph, Action;
        public static More L(string label, string text) => new More { Label = label, Text = text };
        public static More Btn(string glyph, string text, string action) => new More { Glyph = glyph, Text = text, Action = action };
    }
    class StatusModel
    {
        public DateTime? At; public bool Preview; public string Cause; public bool Stale; public bool Checking; public string Times;   // (Times: each part's ms - Snapshot's "checks")
        public List<StatusRow> Rows = new List<StatusRow>();
        public Dictionary<string, string> Keeps = new Dictionary<string, string>();
        public int Warn => Rows.Count(r => r.Level == "warn");
        public int Ok => Rows.Count(r => r.Level == "ok");
        public int Kept => Rows.Count(r => r.Level == "ok" && r.State?.StartsWith("Kept - ") == true);   // (KeptOnPurpose's rows)
        // In place's headline when nothing needs a look (10/27: a kept-on-purpose row counted as one of "All 31 in place")
        public string AllInPlace => Kept > 0 ? $"All {Ok - Kept} in place, {Kept} kept for this PC" : $"All {Ok} in place";
        // the same for Home's tile, where there is less room (10/27: it read "28 of 28 in place" with a kept row among them)
        public string TileInPlace => Kept > 0 ? $"{Ok - Kept} in place, {Kept} kept" : $"{Ok} of {Ok + Warn} in place";

        // title, the status keys (a switch, or "#<section>" of tweaks.ps1), the switch, what it does when it has no switch of
        // its own (or shares one), and what its history lines look like besides its settings
        public static readonly (string Card, string Title, string[] Keys, string Group, string About, string HistRx)[] Catalog = {
            ("Speed and games", "Game Mode, hardware GPU scheduling, crash diagnostics", new[] { "#Gaming / performance" }, null, "Game Mode on and hardware-accelerated GPU scheduling; crash dumps kept and blue screens that name their cause; long file paths; bigger event logs; no motherboard \"auto driver installer\" (WPBT) and no device companion-app downloads; the page file managed by Windows.", "page file"),
            ("Speed and games", "Memory integrity off", new[] { "memory-integrity" }, "memory-integrity", null, null),
            ("Speed and games", "Background game recording off", new[] { "game-recording" }, "game-recording", null, null),
            ("Speed and games", "Xbox Game Bar removed", new[] { "game-bar" }, "game-bar", null, "XboxGamingOverlay|Xbox Game Bar"),
            ("Speed and games", "Optimizations for windowed games and VRR", new[] { "windowed-games" }, "windowed-games", null, null),
            ("Speed and games", "Mouse acceleration off", new[] { "mouse-acceleration" }, "mouse-acceleration", null, null),
            ("Speed and games", "Sticky Keys pop-up off", new[] { "sticky-keys" }, "sticky-keys", null, null),
            ("Speed and games", "\"End task\" in the taskbar menu", new[] { "end-task" }, "end-task", null, null),
            ("Speed and games", "Best power plan, USB sleep and hibernation off", new[] { "power-plan", "hibernation", "#Power" }, "power-plan", null, "power plan|USB sleep|hibernation|processor at full"),
            ("Speed and games", "SysMain (app prefetch) off", new[] { "sysmain-off" }, "sysmain-off", null, "service SysMain"),
            ("Speed and games", "No power-saving on controllers and network adapters", new[] { "#Devices" }, null, "Power-saving off on game controllers (Xbox, PlayStation, Nintendo, 8BitDo and more), the wired network adapter (Energy-Efficient / Green Ethernet) and, on a desktop, Wi-Fi - no input drops or lag spikes when they \"wake up\".", "power-saving|ethernet"),
            ("Speed and games", "Network at Windows' defaults (no lag-adding tweaks)", new[] { "network-defaults", "#Network" }, "network-defaults", null, "Nagle setting"),
            ("Privacy and clutter", "Telemetry, ads, suggestions and Windows AI off", new[] { "telemetry" }, "telemetry", null, null),
            ("Privacy and clutter", "Unneeded services off", new[] { "#Services" }, null, "Diagnostic tracking, WAP push, the Windows AI fabric, Maps, location, link tracking, the compatibility assistant and the retail demo off; the scanner, phone and diagnostics services (and printing, without a real printer) start only when needed.", "^service "),
            ("Privacy and clutter", "Telemetry and feedback tasks off", new[] { "#Scheduled tasks" }, "telemetry", "Windows' telemetry, feedback, compatibility-appraiser, usage-data and \"sustainability\" tasks off, plus Chrome's \"tips\" task and motherboard installer tasks. A few are protected by Windows itself and stay as they are.", "^task |installer task"),
            ("Privacy and clutter", "All app notifications off", new[] { "notifications-off" }, "notifications-off", null, null),
            ("Privacy and clutter", "Start menu recommendations and Task View off", new[] { "start-menu" }, "start-menu", null, null),
            ("Privacy and clutter", "Preinstalled apps removed", new[] { "#Preinstalled apps" }, "bloat-apps", null, "^app "),
            ("Privacy and clutter", "OneDrive removed", new[] { "onedrive", "#OneDrive" }, "onedrive", null, "OneDrive"),
            ("Privacy and clutter", "Edge kept out of the way", new[] { "edge", "#Edge" }, "edge", null, "^Edge (desktop|unpinned)"),
            ("Privacy and clutter", "Edge removed completely", new[] { "edge-remove" }, "edge-remove", null, "^Edge (removed|installed)"),
            ("Privacy and clutter", "Old Windows parts removed", new[] { "#Old Windows parts" }, "legacy", null, "old Windows part|Windows feature|reserved storage"),
            ("Privacy and clutter", "Start-up clutter off", new[] { "#Start-up clutter" }, "startup-clutter", "Vendor updaters, promo tools and \"assistants\" don't start with Windows, nor the helpers of hardware that is switched off (an unused integrated GPU's, onboard audio's). Turned off the Task Manager way - still installed. Off: they start again.", "start-up item"),
            ("Privacy and clutter", "Razer and Logitech apps don't install by themselves", new[] { "#Vendor auto-installers" }, "vendor-installers", null, "auto-installer"),
            ("Privacy and clutter", "File Explorer doesn't guess folder types", new[] { "folder-types" }, "folder-types", null, null),
            ("Privacy and clutter", "Transparency effects off", new[] { "transparency" }, "transparency", null, null),
            ("Privacy and clutter", "Windows keeps registry backups", new[] { "#Registry backup" }, null, "Windows saves copies of the registry again (it stopped in 2018) - a way back if a bad driver or update stops the PC from starting.", null),
            ("Windows Update", "No update restarts while you're signed in", new[] { "restart-block" }, "restart-block", null, null),
            ("Windows Update", "Big Windows upgrades wait 45 days", new[] { "feature-delay" }, "feature-delay", null, null),
        };

        // the history file (C:\PCSetupKit\change-history.log), read again only when it changes
        // - each line split into its time and its text once here (10/26: every row used to match all 3000 lines' times itself)
        static string histStamp; static (DateTime At, string Text)[] hist = new (DateTime, string)[0];
        static (DateTime At, string Text)[] History()
        {
            var f = Path.Combine(Kit.KitDir, "change-history.log"); var st = Kit.Stamp(f)?.Ticks.ToString() ?? "";
            if (st != histStamp)
            {
                var all = Kit.Lines(f); var o = new List<(DateTime, string)>();
                foreach (var line in all.Skip(Math.Max(0, all.Length - 3000)))
                {
                    var lm = Regex.Match(line, @"^(\d{4}-\d\d-\d\d \d\d:\d\d)\s+(.+)$");
                    if (lm.Success && DateTime.TryParseExact(lm.Groups[1].Value, "yyyy-MM-dd HH:mm", null, System.Globalization.DateTimeStyles.None, out var at)) o.Add((at, lm.Groups[2].Value));
                }
                hist = o.ToArray(); histStamp = st;
            }
            return hist;
        }
        public static Dictionary<string, string> ReadKeeps()
        {
            var k = new Dictionary<string, string>();
            foreach (var l in Kit.Lines(Kit.P("kit-options.txt"))) { var m = Regex.Match(l, @"^\s*keep\.(.+?)=(.*)$"); if (m.Success) k[m.Groups[1].Value.Trim()] = m.Groups[2].Value; }
            return k;
        }

        // the rows' details timed in three parts (setting names, history match, the rest) - the DATA line's 'rows N (...)'
        [ThreadStatic] static long[] MoreLaps;

        // each row's history pattern, built once and kept (the setting names rarely change; a new name makes a new key) -
        // was 27 new Regexes per read, ~5 ms (10/27). HistBuilt: how many were built (--test's HISTRX line)
        static readonly System.Collections.Concurrent.ConcurrentDictionary<string, Regex> HistRxs = new System.Collections.Concurrent.ConcurrentDictionary<string, Regex>();
        internal static int HistBuilt;
        static readonly Regex HistSet = new Regex(@"^(.+?) '(.*)' -> '(.*?)'(.*)$"), HistUnset = new Regex(@"^(.+?) '(.*)' -> \(not set\)(.*)$"), HistAfter = new Regex(@" \[after (.+)\]$");
        static Regex HistRx(string pat) => HistRxs.GetOrAdd(pat, p => { System.Threading.Interlocked.Increment(ref HistBuilt); return new Regex(p); });

        public static StatusModel Load(DateTime? checkingSince = null, bool details = true)
        {
            var m = new StatusModel();
            var sw = System.Diagnostics.Stopwatch.StartNew(); var times = new List<string>(); void Lap(string part) { times.Add(part + " " + sw.ElapsedMilliseconds); sw.Restart(); }
            var ts = Kit.ReadJson(Kit.P("tweak-status.json")); var gs = Kit.ReadJson(Kit.P("guard-state.json")); Lap("files");
            m.At = Kit.Date(Json.Get(ts, "at")); m.Preview = Json.B(ts, "preview"); m.Cause = Json.S(ts, "cause"); if (m.Cause == "") m.Cause = null;
            var optIn = Json.L(ts, "optIn").Select(x => x.ToString()).ToList(); if (optIn.Count == 0) optIn = new List<string> { "edge-remove", "notifications-off", "sysmain-off" };
            var keys = Json.Get(ts, "keys");
            var h = details ? History() : new (DateTime, string)[0];
            if (details) m.Keeps = ReadKeeps(); Lap("history");
            var rw = new System.Diagnostics.Stopwatch(); long tState = 0; MoreLaps = new long[3];
            foreach (var c in Catalog)
            {
                var row = new StatusRow { Card = c.Card, Title = c.Title, Keys = c.Keys, Group = c.Group, About = c.About, HistRx = c.HistRx };
                rw.Restart(); RowState(m, row, ts, keys, optIn); tState += rw.ElapsedTicks;
                if (row.Level == "warn") row.Fix = ("E72C", "Put it back now", "CheckNow");
                if (details) row.More = MoreOf(m, row, ts, keys, h);
                m.Rows.Add(row);
            }
            long Ms(long ticks) => ticks * 1000 / System.Diagnostics.Stopwatch.Frequency;
            times.Add($"rows {sw.ElapsedMilliseconds} (state {Ms(tState)}, names {Ms(MoreLaps[0])}, match {Ms(MoreLaps[1])}, rest {Ms(MoreLaps[2])})"); sw.Restart();
            ThisPc(m, gs, details, Lap); m.Times = string.Join(", ", times);
            m.Stale = m.At == null || m.At < DateTime.Now.AddDays(-2);
            // a check the owner started (Check now): running until the guard's next status, 3 minutes at most
            m.Checking = checkingSince != null && (m.At == null || m.At < checkingSince) && checkingSince > DateTime.Now.AddMinutes(-3);
            return m;
        }

        // a switch that is on but tweaks.ps1 leaves alone on purpose on this PC (10/27: "Xbox Game Bar removed" read In place
        // on a dual-CCD X3D, where the Game Bar is kept): what the row says instead, or null
        internal static (string State, string Detail)? KeptOnPurpose(string group, object ts)
        {
            if (group == "game-bar" && Json.B(ts, "dualX3D")) return ("Kept - your processor needs it", "AMD's dual-CCD X3D processors use the Game Bar to keep games on the fast cache cores");
            if (group == "sysmain-off" && Json.B(ts, "sysHdd")) return ("Kept - Windows is on a hard drive", "On a hard drive, SysMain is what makes apps start quicker");
            return null;
        }

        static void RowState(StatusModel m, StatusRow r, object ts, object keys, List<string> optIn)
        {
            if (r.Group != null && Kit.Opt("tweak." + r.Group, optIn.Contains(r.Group) ? "off" : "on") == "off") { r.Level = "dim"; r.State = optIn.Contains(r.Group) ? "Not turned on" : "Off - your choice"; return; }
            if (m.At == null) { r.Level = "dim"; r.State = "Not checked yet"; return; }
            var onPurpose = KeptOnPurpose(r.Group, ts); if (onPurpose != null) { r.Level = "ok"; r.State = onPurpose.Value.State; r.Detail = onPurpose.Value.Detail; return; }
            int same = 0, blk = 0, kept = 0; var fx = new List<string>();
            foreach (var k in r.Keys) { var e = Json.Get(keys, k); if (e == null) continue; same += (int)(Json.N(e, "same") ?? 0); blk += (int)(Json.N(e, "blocked") ?? 0); kept += (int)(Json.N(e, "kept") ?? 0); fx.AddRange(Json.L(e, "fixed").Select(x => x?.ToString()).Where(x => !string.IsNullOrEmpty(x))); }
            var notes = new List<string>(); if (blk > 0) notes.Add($"{blk} protected by Windows itself (left as they are)"); if (kept > 0) notes.Add($"{kept} kept the way you chose");
            if (fx.Count > 0)
            {
                var what = string.Join(", ", fx.Distinct().Take(4).Select(PlainNames.Of));
                if (m.Preview) { r.Level = "warn"; r.State = "Changed - put back at the next check"; r.Detail = what; return; }
                r.Level = "ok"; r.State = "Put back " + Kit.FormatWhen(m.At.Value, shortForm: true); r.Detail = "Something had changed it: " + what + (m.Cause != null ? " - after " + m.Cause : ""); return;
            }
            r.Level = "ok"; r.State = "In place"; r.Detail = notes.Count > 0 ? string.Join("; ", notes) : null;   // (10/25: was "In place (11)" - the count of settings is in the row's details)
        }

        // a row's details: what it does, what it checks, the last check, its history (the last 3 changes, each with "keep
        // that value" once per setting), the values the owner keeps, a way to its switch
        static List<More> MoreOf(StatusModel m, StatusRow r, object ts, object keys, (DateTime At, string Text)[] hist)
        {
            var o = new List<More>(); var lw = System.Diagnostics.Stopwatch.StartNew();
            var about = r.About ?? (r.Group != null && TweakCatalog.Describe.TryGetValue(r.Group, out var d) ? d : null);
            if (about != null) o.Add(More.L("What it does", about));
            var names = r.Keys.SelectMany(k => Json.L(Json.Get(keys, k), "names").Select(x => x?.ToString())).Where(x => !string.IsNullOrEmpty(x)).Distinct().ToList();
            var leaf = names.Select(PlainNames.Of).Distinct().ToList();
            if (names.Count > 0) o.Add(More.L($"Checks {names.Count} setting{Kit.S(names.Count)}", string.Join(", ", leaf.Take(14)) + (leaf.Count > 14 ? $" and {leaf.Count - 14} more" : "")));
            MoreLaps[0] += lw.ElapsedTicks; lw.Restart();
            if (m.At != null) o.Add(More.L("Last check", $"{Kit.FormatWhen(m.At.Value)} - {(m.Preview ? "a preview" : "at login, every 4 hours and after each update")}"));
            // its history (tweaks.ps1's before -> after, with what changed it back), matched by the settings' full names
            var pats = names.Select(n => n.Contains("\\") ? "^" + Regex.Escape(n) + " '" : "\\\\" + Regex.Escape(n) + " '").ToList();
            if (!string.IsNullOrEmpty(r.HistRx)) pats.Add(r.HistRx);
            var hl = new List<(string Text, string Full, string Old)>();
            if (pats.Count > 0)
            {
                var pat = HistRx(string.Join("|", pats));
                foreach (var (at, text) in hist)
                {
                    if (!pat.IsMatch(text)) continue;
                    string w = text, full = null, old = null;
                    var a = HistSet.Match(w); var b = HistUnset.Match(w);
                    if (a.Success) { full = a.Groups[1].Value; old = a.Groups[2].Value == "" || a.Groups[2].Value == "(not set)" ? "(not set)" : a.Groups[2].Value; w = $"{PlainNames.Of(full)}: {old} -> {a.Groups[3].Value}{a.Groups[4].Value}"; }
                    else if (b.Success) { full = b.Groups[1].Value; old = b.Groups[2].Value; w = $"{PlainNames.Of(full)}: {old} -> (not set){b.Groups[3].Value}"; }
                    if (w.Contains("(your choice)")) full = null;   // (the owner's own change: nothing to keep)
                    hl.Add(($"{Kit.FormatWhen(at)} - {HistAfter.Replace(w, " (after $1)")}", full, old));
                }
                hl = hl.Skip(Math.Max(0, hl.Count - 3)).ToList();
            }
            MoreLaps[1] += lw.ElapsedTicks; lw.Restart();
            if (hl.Count == 0) o.Add(More.L("History", "Never had to be put back"));
            bool first = true; var offered = new HashSet<string>();
            foreach (var x in Enumerable.Reverse(hl))
            {
                o.Add(More.L(first ? "History" : "", x.Text)); first = false;
                // the newest change of a setting: its earlier value can be kept instead (once per setting, not one already kept)
                if (x.Full != null && offered.Add(x.Full) && !m.Keeps.ContainsKey(x.Full))
                    o.Add(More.Btn("E7A7", $"Keep {(x.Old == "(not set)" ? "Windows' default" : $"'{x.Old}'")} for {PlainNames.Of(x.Full)}", "Keep:" + x.Full + "\t" + x.Old));
            }
            // settings the owner keeps their own way: said, with the way back
            foreach (var kf in names.Where(m.Keeps.ContainsKey))
            {
                o.Add(More.L("Kept by you", $"{PlainNames.Of(kf)} stays at {(m.Keeps[kf] == "(not set)" ? "Windows' default" : $"'{m.Keeps[kf]}'")}"));
                o.Add(More.Btn("E72C", $"Let Messiah manage {PlainNames.Of(kf)} again", "Manage:" + kf));
            }
            if (r.Group != null) o.Add(More.Btn("E713", "Change in Settings", "Page:Settings/Windows"));
            MoreLaps[2] += lw.ElapsedTicks;
            return o;
        }

        // the two live reads (the monitors' modes, Messiah's scheduled tasks): what was read before, never waited for - 10/26:
        // the Task Scheduler took 140 of the 210 ms the checks took at start-up. Read on a thread of its own once a minute; the
        // page drawn again only when something changed (the first read: the two rows' details fill in a moment later)
        static List<string> modesCache; static List<Tasks.Info> tasksCache; static DateTime liveAt; static int liveReading;
        static readonly string[] OwnTasks = { "Claude Background Maintenance", "PC Setup Kit Update Guard", "PC Setup Kit Update Check", "Messiah Tray" };
        static void LiveReads()
        {
            if (liveAt > DateTime.Now.AddMinutes(-1) || Interlocked.CompareExchange(ref liveReading, 1, 0) != 0) return;
            new Thread(() =>
            {
                bool changed;
                try
                {
                    var l = new List<string>();
                    try { using (var s = new ManagementObjectSearcher("SELECT Name, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate, Status FROM Win32_VideoController")) foreach (ManagementObject o in s.Get()) if (Convert.ToInt32(o["CurrentRefreshRate"] ?? 0) > 1 && (o["Status"]?.ToString() ?? "") == "OK") l.Add($"{o["Name"]}: {o["CurrentHorizontalResolution"]} x {o["CurrentVerticalResolution"]} at {o["CurrentRefreshRate"]} Hz"); } catch { }
                    var tk = Tasks.Read(OwnTasks);
                    string Sig(List<string> ml, List<Tasks.Info> tl) => ml == null ? null : string.Join("|", ml) + "#" + string.Join("|", tl.Select(x => $"{x.Name} {x.Enabled} {x.State} {x.LastRun}"));
                    changed = Sig(modesCache, tasksCache) != Sig(l, tk);
                    modesCache = l; tasksCache = tk; liveAt = DateTime.Now;
                }
                finally { liveReading = 0; }
                if (changed) System.Windows.Application.Current?.Dispatcher.BeginInvoke(new Action(() => Shell.Refresh(false)));
            }) { IsBackground = true }.Start();
        }

        // this PC: its own extras, crash-hunting modes, the NVIDIA settings, the monitors, the drivers, Messiah's own tasks
        static void ThisPc(StatusModel m, Dictionary<string, object> gs, bool details, Action<string> lap)
        {
            const string pc = "This PC";
            void Add(string title, string lv, string state, string detail, (string, string, string)? fix = null, List<More> more = null) => m.Rows.Add(new StatusRow { Card = pc, Title = title, Level = lv, State = state, Detail = detail, Fix = fix, More = details ? more : null });
            if (!Kit.InTests) LiveReads();   // (the monitors and the tasks: what was read before)
            lap("live");
            if (gs != null && Json.B(gs, "hasLocal"))
            {
                var at = Kit.Date(Json.Get(gs, "at")); var ll = Json.L(gs, "local").Select(x => x?.ToString()).Where(x => !string.IsNullOrEmpty(x)).ToList(); var cause = Json.S(gs, "cause");
                Add("This PC's own extras (unused devices off, power)", "ok", ll.Count > 0 && at != null ? "Put back " + Kit.FormatWhen(at.Value, shortForm: true) : "In place", ll.Count > 0 ? string.Join(", ", ll.Take(3)) : null, null, new List<More> {
                    More.L("What it does", "Extras only this PC has (tweaks-local.ps1 next to Messiah's scripts), checked and put back with everything else."),
                    More.L("Last check", at != null ? $"{Kit.FormatWhen(at.Value)} - {(ll.Count > 0 ? $"put back: {string.Join(", ", ll)}{(cause != "" ? $" (after {cause})" : "")}" : "all in place")}" : "Not yet") });
            }
            // crash-hunting modes: a real cost in games while on - amber from the start; turned off, they keep running until
            // the next restart
            if (!Kit.InTests || Environment.GetEnvironmentVariable("PCKIT_DIAG_TEST") != null)
            {
                var dms = Data.DiagModes(); var offPending = Data.DiagOffPending();
                var about = More.L("What it does", "Modes for hunting crashes: Driver Verifier checks every call of the drivers it watches, kernel debugging and test signing change how Windows starts. Right while a crash is being tracked down - after that they cost frame rate and smoothness in every game. Messiah never turns one on or off by itself.");
                if (dms.Count > 0)
                {
                    var dm = dms[0];
                    var fix = dm.Id == "verifier" ? ("E7E8", "Turn off Driver Verifier", "DiagOff:verifier") : dm.Id == "debug" ? ("E7E8", "Turn off kernel debugging", "DiagOff:debug") : ("E7E8", "Turn off test signing", "DiagOff:testsigning");
                    Add("Crash-hunting modes off", "warn", dm.Name + " on", $"On for {dm.Days} day{Kit.S(dm.Days)} (since {dm.Since:MMM d}) - it slows games; turn it off once the crash hunt is over{(dms.Count > 1 ? "; also: " + string.Join(", ", dms.Skip(1).Select(x => x.Name)) : "")}", fix, new List<More> {
                        about, More.L("On now", string.Join("   |   ", dms.Select(x => $"{x.Name} - since {x.Since:MMM d}"))),
                        More.L("Turning it off", "Takes effect at the next restart (Messiah never restarts the PC). If blue screens come back afterwards, the crash notes in Messiah still have what was found.") });
                }
                else if (offPending.Count > 0) Add("Crash-hunting modes off", "ok", "Off from the next restart", string.Join(", ", offPending.Select(x => x == "verifier" ? "Driver Verifier" : x == "debug" ? "Kernel debugging" : "Test signing")) + " switched off - still running until Windows restarts", null, new List<More> { about });
                else Add("Crash-hunting modes off", "ok", "Off", null, null, new List<More> { about });
            }
            lap("extras");
            if (File.Exists(Kit.P("nvidia-settings.txt")))
            {
                var nvFor = Kit.FirstLine(Kit.P("nvidia-settings.txt")); var gpuNow = Json.S(Kit.ReadJson(Kit.P("gpu-state.json")), "driver").Trim();
                const string nvT = "NVIDIA low latency and unlimited shader cache";
                var nvMore = new List<More> {
                    More.L("What it does", "Low latency mode \"On\" (one pre-rendered frame: less input lag - games with NVIDIA Reflex use their own) and an unlimited shader cache (games don't recompile shaders and stutter because an old 4 GB cache filled up), on the driver's global profile. Every other NVIDIA setting stays yours."),
                    More.L("Driver", $"Set for {(nvFor != "" ? nvFor : "-")}{(gpuNow != "" ? "; installed now: " + gpuNow : "")} - read back from the driver at every pass and set again after driver updates"),
                    More.Btn("E713", "Change in Settings", "Page:Settings/General") };
                if (Kit.Opt("nvidiasettings", "on") == "off") Add(nvT, "dim", "Off - your choice", null, null, nvMore);
                else if (gpuNow != "" && nvFor != gpuNow) Add(nvT, "warn", "New driver - set at the next check", "Last set for driver " + nvFor, ("E72C", "Set it now", "CheckNow"), nvMore);
                else Add(nvT, "ok", "In place", $"Driver {nvFor} - checked at every pass", null, nvMore);
            }
            var rep = Kit.Lines(Kit.P("maint-report.txt"));
            if (rep.Length > 0)
            {
                var mon = rep.Where(x => Regex.IsMatch(x, @"^(Reminder|WARNING):.*(Hz|refresh rate|resolution)")).ToList();
                // (the modes right now: each graphics card with a screen on it - LiveReads)
                var monMore = new List<More> { More.L("What it does", "Each monitor at its native resolution and the highest refresh rate it supports - set by itself once per monitor, also for one plugged in later; a cable or port that can't carry the full rate is said.") };
                if (details && !Kit.InTests && modesCache != null && modesCache.Count > 0) monMore.Add(More.L("Right now", string.Join("   |   ", modesCache)));
                if (mon.Count > 0) monMore.Add(More.L("Found", string.Join("   |   ", mon)));
                Add("Monitors at their best resolution and refresh rate", mon.Count > 0 ? "warn" : "ok", mon.Count > 0 ? "Needs a look" : "In place", mon.Count > 0 ? Regex.Replace(mon[0], @"^(Reminder|WARNING):\s*", "") : null, mon.Count > 0 ? ("E7F4", "Display settings", "Open:ms-settings:display") : ((string, string, string)?)null, monMore);
                var i = Array.IndexOf(rep, "[Drivers]");
                var dl = new List<string>(); if (i >= 0) for (int j = i + 1; j < rep.Length && !rep[j].StartsWith("["); j++) if (rep[j].Trim() != "") dl.Add(rep[j].Trim());
                if (dl.Count > 0)
                {
                    var bad = dl.Where(x => Regex.IsMatch(x, "FAILED|WARNING|could not")).ToList();
                    Add("Drivers up to date", bad.Count > 0 ? "warn" : "ok", bad.Count > 0 ? "Needs a look" : "Up to date", bad.Count > 0 ? bad[0] : dl[0], bad.Count > 0 ? ("E768", "Run maintenance now", "RunMaint") : ((string, string, string)?)null, new List<More> {
                        More.L("What it does", "The graphics driver from its maker (checked against the NVIDIA app; AMD Radeon too), everything else from Windows Update - installed by itself, never while you play, with a restore point first. A driver that keeps failing is hidden; one that crashes the PC is rolled back."),
                        More.L("Last check", string.Join("   |   ", dl)) });
                }
            }
            lap("drivers");
            if (!Kit.InTests)
            {
                var kt = OwnTasks; var tk = tasksCache ?? new List<Tasks.Info>();   // (LiveReads: none yet - the row comes with the first read)
                if (tk.Count > 0)
                {
                    var badT = kt.Where(n => !tk.Any(t => t.Name == n && t.Enabled)).ToList();
                    var tkMore = new List<More> { More.L("What it does", "The scheduled tasks that keep all of this going: the maintenance at login, the check every 4 hours, the guard 2 minutes after each Windows or driver update, and the tray. Each one switches the others back on if something turns it off.") };
                    tkMore.AddRange(tk.Select(t => More.L(t.Name, (t.Enabled ? t.State.ToLower() : "switched off") + (t.LastRun != null ? " - last ran " + Kit.FormatWhen(t.LastRun.Value) : ""))));
                    Add("Messiah's own checks scheduled (login, every 4 hours, after updates)", badT.Count > 0 ? "warn" : "ok", badT.Count > 0 ? "Switched off" : "On", badT.Count > 0 ? string.Join(", ", badT) + " - turned back on at the next maintenance" : null, badT.Count > 0 ? ("E768", "Switch them back on", "RunMaint") : ((string, string, string)?)null, tkMore);
                }
            }
            lap("tasks");
        }
    }

    // Messiah's scheduled tasks, read through Windows' Task Scheduler (no PowerShell)
    static class Tasks
    {
        public class Info { public string Name; public bool Enabled; public string State; public DateTime? LastRun; }
        public static List<Info> Read(string[] names)
        {
            var l = new List<Info>();
            try
            {
                dynamic svc = Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service")); svc.Connect();
                dynamic root = svc.GetFolder("\\");
                foreach (var n in names)
                {
                    try
                    {
                        dynamic t = root.GetTask(n);
                        DateTime lr = t.LastRunTime;
                        int st = t.State;   // 1 disabled, 2 queued, 3 ready, 4 running
                        l.Add(new Info { Name = n, Enabled = t.Enabled, State = st == 1 ? "Disabled" : st == 4 ? "Running" : st == 2 ? "Queued" : "Ready", LastRun = lr.Year > 2000 ? lr : (DateTime?)null });
                    }
                    catch { }
                }
            }
            catch { }
            return l;
        }
    }
}
