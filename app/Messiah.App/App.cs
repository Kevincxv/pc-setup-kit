using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Windows.Threading;

namespace Messiah
{
    public class App : Application
    {
        // While the PowerShell app is still the live one, this one runs side by side under names of its own (its own
        // single-instance lock, show signal, window-handle file - the tray reads app-window.txt for the live app).
        // --live: the names of the app (the switch-over).
        public static class Names
        {
            public static string Mutex = @"Local\MessiahApp.Next", ShowEvent = @"Local\MessiahAppShow.Next", QuitEvent = @"Local\MessiahAppQuit.Next", HwndFile = "app-window-next.txt", RequestFile = "app-request-next.txt", PlaceFile = "app-window-place.txt", LastFile = "app-last-next.txt";
            // tests (PCKIT_IN_TESTS): each test's copy its own names, from its sandbox home - 10/25: tests run side by side,
            // and a copy that found another test's window open handed over to it and ended (the update-offer test failed)
            public static void Isolate() { var h = "." + ((uint)(Environment.GetEnvironmentVariable("USERPROFILE") ?? "").ToLowerInvariant().GetHashCode()).ToString("x"); Mutex += h; ShowEvent += h; QuitEvent += h; }
            public static void Live() { Mutex = @"Local\PCSetupKitStatusWindow"; ShowEvent = @"Local\MessiahAppShow"; QuitEvent = @"Local\MessiahAppQuit"; HwndFile = "app-window.txt"; RequestFile = "app-request.txt"; LastFile = "app-last.txt"; }
        }

        [STAThread]
        public static int Main(string[] args)
        {
            var sw = Stopwatch.StartNew();
            string page = null, uri = null, trayTest = null; bool background = false, test = false, timing = false, tray = false, fs = false; int after = 0;
            for (int i = 0; i < args.Length; i++)
            {
                var a = args[i].TrimStart('-', '/').ToLowerInvariant();
                if (a == "page" && i + 1 < args.Length) page = args[++i];
                else if (a == "background") background = true;
                else if (a == "test") test = true;
                else if (a == "timing") timing = true;
                else if (a == "live") Names.Live();
                else if (a == "tray") tray = true;   // (the "Messiah Tray" task at login: the app with its tray icon - TrayHost)
                else if (a == "uri" && i + 1 < args.Length) uri = Regex.Replace(args[++i], "^messiah:/*", "", RegexOptions.IgnoreCase).TrimEnd('/');   // (a notification clicked)
                else if (a == "tray-test" && i + 1 < args.Length) trayTest = args[++i];
                else if (a == "fs") fs = true;
                else if (a == "quick") return QuickTest();   // (the tray's quick panel on its own - to look at it)
                else if (a == "audit" && i + 1 < args.Length) return RunAudit(args[i + 1], args.Skip(i + 2).ToArray());   // (MainWindow.Audit.cs: --audit <folder> [--widths 480,800] [--noshots])
                else if (a == "after" && i + 1 < args.Length) int.TryParse(args[++i], out after);   // (Restart into an update: the copy before)
            }
            if (Kit.InTests && Names.Mutex.EndsWith(".Next")) Names.Isolate();   // (never --live: the real app's names stay the real app's)
            if (trayTest != null) return Tray.TrayLogic.Test(trayTest, fs);
            AppDomain.CurrentDomain.UnhandledException += (s, e) => Log("crash: " + e.ExceptionObject);
            if (test) { SelfTesting = true; return RunTest(page); }
            // restarted into an update: the copy before ends first (else this one would only hand over to it)
            if (after > 0) try { using (var old = Process.GetProcessById(after)) old.WaitForExit(20000); } catch { }

            // one window: a second start hands over to the open one (it may be hidden - closing only hides it)
            // (both open to this user by name: the tray starts it with admin rights, the Start menu without - an admin
            // process's objects are otherwise closed to the same user's normal ones)
            var me = System.Security.Principal.WindowsIdentity.GetCurrent().User;
            var ms = new System.Security.AccessControl.MutexSecurity();
            ms.AddAccessRule(new System.Security.AccessControl.MutexAccessRule(me, System.Security.AccessControl.MutexRights.FullControl, System.Security.AccessControl.AccessControlType.Allow));
            Mutex mutex; try { mutex = new Mutex(false, Names.Mutex, out _, ms); } catch (UnauthorizedAccessException) { mutex = null; }
            bool first; try { first = mutex != null && mutex.WaitOne(0); } catch (AbandonedMutexException) { first = true; }
            // the tray (at login, or after an update): it is the app - a copy already running (opened from the Start menu, or the
            // version before an update) is asked to make way; one that can't yet (open on screen, from before 10/21) ends once
            // it is closed and hidden: waited for as long as that takes
            if (!first && tray && mutex != null)
            {
                bool logged = false;
                while (!first)
                {
                    if (EventWaitHandle.TryOpenExisting(Names.QuitEvent, out var q)) q.Set();
                    try { first = mutex.WaitOne(TimeSpan.FromSeconds(30)); } catch (AbandonedMutexException) { first = true; }
                    if (!first && !logged) { Log("tray: waiting for the open app window to close (an older copy)"); logged = true; }
                }
            }
            if (!first)
            {
                if (background) return 0;
                var req = uri != null && Regex.IsMatch(uri, @"^(page|chat)=[\w/-]*$") ? uri : page != null ? "page=" + page : null;
                if (req != null) try { File.WriteAllText(Kit.P(Names.RequestFile), req); } catch { }
                if (EventWaitHandle.TryOpenExisting(Names.ShowEvent, out var sig)) { Native.AllowSetForegroundWindow(-1); sig.Set(); }
                return 0;
            }
            var es = new System.Security.AccessControl.EventWaitHandleSecurity();
            es.AddAccessRule(new System.Security.AccessControl.EventWaitHandleAccessRule(me, System.Security.AccessControl.EventWaitHandleRights.FullControl, System.Security.AccessControl.AccessControlType.Allow));
            var showEvt = new EventWaitHandle(false, EventResetMode.AutoReset, Names.ShowEvent, out _, es);
            var quitEvt = new EventWaitHandle(false, EventResetMode.AutoReset, Names.QuitEvent, out _, es);

            // the copies an update moved aside (MessiahApp.exe.<pid>.old - still running then): gone once nothing runs them
            // (10/25: two from 10/22 were still there)
            try { foreach (var f in Directory.GetFiles(Path.GetDirectoryName(Process.GetCurrentProcess().MainModule.FileName), "*.old")) try { File.Delete(f); } catch { } } catch { }
            Theme.Load();
            var app = new App { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            // a fault in a click or a page never closes the window: logged, said
            app.DispatcherUnhandledException += (s, e) => { Log("ui: " + e.Exception); e.Handled = true; Shell.Say("Something went wrong there - it's logged; try again."); };
            app.Resources.MergedDictionaries.Add(new ResourceDictionary { Source = new Uri("pack://application:,,,/MessiahApp;component/Styles.xaml") });
            Theme.Apply(app.Resources);
            bool asked = page != null;   // (-page: not the one from last time - the tour does not take it over)
            AppLast.Load(); if (page == null && AppLast.Page != "") page = AppLast.Page;
            var w = new MainWindow { pageAsked = asked };
            if (page == "Welcome") { w.startPage = "Welcome"; w.BuildNav(); }
            if (page == "Chat") w.ContentRendered += (s, e) => w.ShowChat(true);   // (-page Chat: open with the chat - the tray's Ask Claude)
            else if (page != null) w.ShowPage(page.Split('/')[0], page.Contains("/") ? page.Split('/')[1] : null);
            w.Refresh(true);
            // another start (the tray, Ctrl+Alt+M, the Start menu) asks it to show itself: waited for on a thread of its own
            var t = new Thread(() => { while (true) { showEvt.WaitOne(); w.Dispatcher.BeginInvoke(new Action(w.ShowApp)); } }) { IsBackground = true }; t.Start();
            // the tray starting asks this copy to make way: an open window comes back on the same page in the new copy
            var tq = new Thread(() => { quitEvt.WaitOne(); w.Dispatcher.BeginInvoke(new Action(() => { if (w.IsVisible) try { File.WriteAllText(Kit.P(Names.RequestFile), "page=" + AppLast.Page); } catch { } w.Quit = true; w.Close(); })); }) { IsBackground = true }; tq.Start();
            Tray.TrayHost host = null;
            if (tray) { host = new Tray.TrayHost(w); host.Start(); w.Closed += (s, e) => host.Stop(); }
            // an update to this program: the hidden copy ends, so the next open runs the new one
            var self = Process.GetCurrentProcess().MainModule.FileName; var selfAt = File.GetLastWriteTime(self);
            var upd = new DispatcherTimer { Interval = TimeSpan.FromSeconds(30) };
            upd.Tick += (s, e) =>
            {
                try
                {
                    if (File.GetLastWriteTime(self) == selfAt) return;
                    // open on screen: the new version takes over by itself once the owner has left the window alone for a
                    // minute (10/27, the owner: "when you release a new feature it restarts the app for me and it's always up
                    // to date") - back on the same page; the chat runs in its own process and carries on. Never under a chat
                    // message being written; while he's using the window: offered (Restart), and done at the next quiet minute.
                    if (w.Visibility == Visibility.Visible)
                    {
                        void Restart()
                        {
                            try { File.WriteAllText(Kit.P(Names.RequestFile), "page=" + AppLast.Page); } catch { }
                            var keep = RestartArgs(args, Process.GetCurrentProcess().Id);
                            try { Process.Start(new ProcessStartInfo(self, string.Join(" ", keep)) { UseShellExecute = false }); } catch (Exception ex) { Log("update: " + ex.Message); return; }
                            w.Quit = true; w.Close();
                        }
                        var idle = int.TryParse(Environment.GetEnvironmentVariable("PCKIT_UPDATE_IDLE"), out var sec) ? sec : 60;   // (tests: longer, to see the offer)
                        if ((DateTime.Now - w.LastInput).TotalSeconds >= idle && !w.Drafting) { Restart(); return; }
                        if (!w.Offering) w.Offer("A new version of Messiah is ready - it restarts by itself when you leave it for a minute.", "Restart now", Restart);
                        return;
                    }
                    // (the tray: the new version starts right away and takes over - it waits for this one to end)
                    if (tray && File.Exists(self)) Process.Start(new ProcessStartInfo(self, string.Join(" ", args.Select(x => x.Contains(" ") ? "\"" + x + "\"" : x))) { UseShellExecute = false });
                    w.Quit = true; w.Close();
                }
                catch (Exception ex) { Log("update: " + ex.Message); }
            };
            upd.Start();
            if (uri != null) w.ContentRendered += (s, e) => Tray.Notes.Open(uri);
            if (background || (tray && uri == null)) { new WindowInteropHelper(w).EnsureHandle(); if (tray && File.Exists(Kit.P(Names.RequestFile))) w.ShowApp(); }   // (the tray: hidden - unless the copy it replaced was open)
            else
            {
                if (timing) { Timing = sw; w.ContentRendered += (s, e) => TimingNote($"on screen after {sw.ElapsedMilliseconds} ms"); }
                w.ShowApp();
            }
            app.Run();
            GC.KeepAlive(mutex);
            return 0;
        }

        // Restart into an update: the new copy keeps what this one is (--live: the app's own names, --tray: the tray) - never
        // the page it was opened on (the request file carries that). 10/22: "^[-/]" missed "--live", and the restarted copy
        // ran without the tray.
        internal static IEnumerable<string> RestartArgs(string[] args, int pid) =>
            args.Where(x => Regex.IsMatch(x, "^(--?|/)(live|tray)$", RegexOptions.IgnoreCase)).Concat(new[] { "--after", pid.ToString() });

        static int QuickTest()
        {
            Theme.Load();
            var app = new App { ShutdownMode = ShutdownMode.OnLastWindowClose };
            app.Resources.MergedDictionaries.Add(new ResourceDictionary { Source = new Uri("pack://application:,,,/MessiahApp;component/Styles.xaml") });
            Theme.Apply(app.Resources);
            var q = new Tray.QuickPanel(null, null, null); q.Show(); app.Run(); return 0;
        }

        // --timing: how long the window took to show, and its first page with data (and each part of that data) - %TEMP%\messiah-app-timing.txt
        internal static Stopwatch Timing;
        internal static void TimingNote(string what) { try { File.AppendAllText(Path.Combine(Path.GetTempPath(), "messiah-app-timing.txt"), $"{DateTime.Now:s} {what}\r\n"); } catch { } }

        // what went wrong, for /self-improve (.claude\app-errors.log, kept short)
        public static void Log(string what)
        {
            try { var f = Kit.P("app-errors.log"); if (File.Exists(f) && new FileInfo(f).Length > 200000) File.Delete(f); File.AppendAllText(f, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss}  {what}\r\n"); } catch { }
        }
        // --test: every page built once and printed as text - what the tests read (the PowerShell app's -Test format)
        internal static bool SelfTesting;   // (--test / --audit: nothing is started - no chat, no tray command)
        static int RunAudit(string dir, string[] rest)
        {
            Environment.SetEnvironmentVariable("PCKIT_IN_TESTS", "1");   // (the chat is never started, nothing is written to it)
            var widths = new[] { 480, 800, 1040, 1366, 1920, 2560 }; bool shots = true;
            for (int i = 0; i < rest.Length; i++)
            {
                var a = rest[i].TrimStart('-', '/').ToLowerInvariant();
                if (a == "widths" && i + 1 < rest.Length) widths = rest[++i].Split(',').Select(int.Parse).ToArray();
                else if (a == "noshots") shots = false;
            }
            var o = new StringBuilder();
            var t = new Thread(() =>
            {
                Theme.Load();
                var app = new App { ShutdownMode = ShutdownMode.OnExplicitShutdown };
                app.Resources.MergedDictionaries.Add(new ResourceDictionary { Source = new Uri("pack://application:,,,/MessiahApp;component/Styles.xaml") });
                Theme.Apply(app.Resources);
                try { foreach (var l in new MainWindow().RunAudit(dir, widths, 900, shots)) o.AppendLine(l); }
                catch (Exception e) { o.AppendLine("AUDIT ERROR: " + e); }
            });
            t.SetApartmentState(ApartmentState.STA); t.Start(); t.Join();
            var outp = Console.OpenStandardOutput(); var bytes = new UTF8Encoding(false).GetBytes(o.ToString()); outp.Write(bytes, 0, bytes.Length); outp.Flush();
            return 0;
        }
        static int RunTest(string page)
        {
            var o = new StringBuilder();
            var t = new Thread(() =>
            {
                Theme.Load();
                var app = new App { ShutdownMode = ShutdownMode.OnExplicitShutdown };
                app.Resources.MergedDictionaries.Add(new ResourceDictionary { Source = new Uri("pack://application:,,,/MessiahApp;component/Styles.xaml") });
                Theme.Apply(app.Resources);
                var w = new MainWindow();
                if (page == "Welcome") { w.startPage = "Welcome"; w.BuildNav(); }
                o.AppendLine("WINDOW: " + w.Title);
                o.AppendLine("RESTART ARGS: " + string.Join(" ", RestartArgs(new[] { "--live", "--tray", "--page", "Status" }, 42)) + " / " + string.Join(" ", RestartArgs(new[] { "--live", "--page", "Home" }, 7)));
                o.AppendLine("NAV: " + string.Join(" | ", w.NavList.Children.OfType<RadioButton>().Select(r => r.Tag)));
                // the keys: Ctrl+3 Health, Ctrl+Tab twice its third page, Ctrl+Shift+Tab back, Ctrl+Shift+Tab from the first = the last;
                // Ctrl+1 Home (one page: Ctrl+Tab stays); Ctrl+9 nothing
                var keys = new List<string>(); Func<string> at = () => w.PageKey;
                w.NavKey(System.Windows.Input.Key.D3, false); keys.Add(at()); w.NavKey(System.Windows.Input.Key.Tab, false); w.NavKey(System.Windows.Input.Key.Tab, false); keys.Add(at());
                w.NavKey(System.Windows.Input.Key.Tab, true); keys.Add(at()); w.NavKey(System.Windows.Input.Key.Tab, true); w.NavKey(System.Windows.Input.Key.Tab, true); keys.Add(at());
                w.NavKey(System.Windows.Input.Key.NumPad1, false); w.NavKey(System.Windows.Input.Key.Tab, false); keys.Add(at()); keys.Add(w.NavKey(System.Windows.Input.Key.D9, false).ToString());
                o.AppendLine("KEYS: " + string.Join(" > ", keys) + " | tips: " + string.Join(" | ", w.NavList.Children.OfType<RadioButton>().Select(r => r.ToolTip)));
                // a row's page (Home's This week): the page, and a card on it by name; Health back on Stability after
                var opened = new List<string>(); foreach (var go in new[] { "Activity/Performance#Heat and wear", "Activity/Checks", "Activity/Stability" }) { w.Open(go); opened.Add(w.PageKey); }
                o.AppendLine("OPEN: " + string.Join(" > ", opened));   // (the scroll to the card needs the page drawn: --audit shows it)
                // Ctrl+/: the shortcuts card on Settings > General, and what it lists (with the AI assistant on / off)
                w.Open("Settings/General#Keyboard shortcuts");
                o.AppendLine($"SHORTCUTS: {w.PageKey} | {string.Join(", ", Pages.Settings.Shortcuts(true).Select(k => k.Item1))} | no AI: {Pages.Settings.Shortcuts(false).Count}");
                { var ks = Pages.Settings.Shortcuts(true); o.AppendLine($"KEYWORDS: {ks.Count(k => k.Item2.Contains(";") || k.Item2.Contains(" - "))} of {ks.Count} join with a semicolon or dash | {ks[0].Item2}"); }
                w.ShowPage("Health", "Stability"); w.NavKey(System.Windows.Input.Key.D1, false);   // (back as it was: Health on its first page, Home open)
                // winget ids as the checks' lines say them ("Valve.Steam" -> "Steam")
                o.AppendLine("APPNAMES: " + string.Join(" | ", new[] { "Valve.Steam", "Discord.Discord", "Microsoft.WindowsTerminal", "OpenJS.NodeJS.LTS", "Microsoft.WindowsAppRuntime.1.8", "Microsoft.VCRedist.2013.x64", "Google.Chrome", "Microsoft.msodbcsql.17", "Python.Python.3.12" }.Select(Data.AppName)));
                var sw = Stopwatch.StartNew(); var snap = Snapshot.Load(); o.AppendLine($"DATA: read in {sw.ElapsedMilliseconds} ms ({snap.Times})"); o.AppendLine($"CLAUDEVER: {Data.ClaudeVersion()} from {Data.ClaudeVersionFrom}");
                {   // hardware.json: the last driver / BIOS read comes back the same; an empty or broken file gives nothing
                    var hw = Data.HwFromJson(Kit.ParseJson(Kit.ToJson(Data.HwToJson(new Data.Gpu { Name = "NVIDIA GeForce RTX 5070", Version = "32.0.15.8157", Date = new DateTime(2026, 9, 30) }, new Data.Bios { Maker = "ASUSTeK", Model = "ROG STRIX B650", Version = "3602", Date = "2026-08-01", Url = "u", Steps = "s" }))) as Dictionary<string, object>);
                    var none = Data.HwFromJson(Kit.ParseJson("{\"gpu\":null,\"bios\":{}}") as Dictionary<string, object>);
                    o.AppendLine($"HWCACHE: {hw.Gpu?.Name} {hw.Gpu?.Version} {hw.Gpu?.Date:yyyy-MM-dd} | {hw.Bios?.Maker} {hw.Bios?.Model} {hw.Bios?.Version} {hw.Bios?.Date} {hw.Bios?.Steps} | empty {(none.Gpu == null && none.Bios == null && Data.HwFromJson(null).Gpu == null ? "none" : "SOME")}");
                    // the driver as a gamer knows it: NVIDIA's own number; AMD / Intel and odd versions as Windows says them
                    o.AppendLine("DRIVERVER: " + string.Join(" | ", new[] { ("NVIDIA GeForce RTX 4070 Ti", "32.0.15.6094"), ("NVIDIA GeForce RTX 3060", "31.0.15.3699"), ("AMD Radeon RX 7800 XT", "32.0.21042.62"), ("NVIDIA GeForce GTX 1060", "26.21.14.4120"), ("NVIDIA GeForce RTX 4070", "beta"), ("NVIDIA GeForce RTX 4070", "") }
                        .Select(x => Data.Gpu.ShownVersion(x.Item1, x.Item2))));
                }
                {   // a switch that is one In place row by itself has one name on both pages (10/27: "Remove Edge completely" / "Edge removed completely")
                    var titles = TweakCatalog.Groups.SelectMany(g => g.Items).ToDictionary(i => i.Id, i => i.Title);
                    var diff = StatusModel.Catalog.Where(c => c.Keys.Length == 1 && c.Keys[0] == c.Group && titles.ContainsKey(c.Group) && titles[c.Group] != c.Title)
                        .Select(c => $"{titles[c.Group]} / {c.Title}").ToList();
                    o.AppendLine($"SWITCHNAMES: {StatusModel.Catalog.Count(c => c.Keys.Length == 1 && c.Keys[0] == c.Group)} one-switch rows, " + (diff.Count == 0 ? "same names" : "differ: " + string.Join(" | ", diff)));
                    // 10/27: a row that is only its switch's own section reads like the switch ("Razer and Logitech auto-installers
                    // blocked" was "... apps don't install by themselves"), and a row that also holds another switch names it
                    // (Hibernation off sat in "Best power plan, USB sleep off" - turned off on Choose, nowhere to be found on In place)
                    var own = StatusModel.Catalog.Where(c => c.Keys.Length == 1 && c.Keys[0].StartsWith("#") && c.About == null && c.Group != null && titles.ContainsKey(c.Group) && titles[c.Group] != c.Title)
                        .Select(c => $"{titles[c.Group]} / {c.Title}");
                    var inside = StatusModel.Catalog.SelectMany(c => c.Keys.Where(k => k != c.Group && titles.ContainsKey(k)).Select(k => (c.Title, k)))
                        .Where(x => x.Title.IndexOf(titles[x.k].Split(' ')[0], StringComparison.OrdinalIgnoreCase) < 0).Select(x => $"{titles[x.k]} not named in {x.Title}");
                    // and every Choose switch has a row (10/27: Xbox Game Bar removed and SysMain off had none)
                    var none = titles.Keys.Where(k => !StatusModel.Catalog.Any(c => c.Keys.Contains(k) || c.Group == k)).Select(k => $"{titles[k]} has no row");
                    var bad = own.Concat(inside).Concat(none).ToList();
                    // a switch's one line says what it does - 10/27: OneDrive's read only 'Off: OneDrive comes back ...'
                    var offOnly = TweakCatalog.Groups.SelectMany(g => g.Items).Where(i => Regex.IsMatch(Ui.SubLine(i.About).First, @"^Off(?: again| \(default\))?:")).Select(i => i.Title).ToList();
                    o.AppendLine($"SWITCHLINES: {TweakCatalog.Groups.Sum(g => g.Items.Count())} switches, " + (offOnly.Count == 0 ? "each says what it does" : "only what off means: " + string.Join(" | ", offOnly)));
                    // and never stops inside brackets - 10/28: the temperature switch's line ended '... at idle (Games > Performance:'
                    bool Open(string s) => s.Count(c => c == '(') != s.Count(c => c == ')');
                    var temp = Ui.SubLine("Windows can't read it by itself: a small driver reads the sensor - while you play and at idle (Games > Performance: Heat and wear). Off: both are removed.");
                    var openLines = TweakCatalog.Groups.SelectMany(g => g.Items).Where(i => Open(Ui.SubLine(i.About).First)).Select(i => i.Title).ToList();
                    o.AppendLine("SUBLINEBRACKETS: " + (Open(temp.First) ? "stops inside: " + temp.First : "sample whole") + " | " + (openLines.Count == 0 ? "no switch stops inside" : "stops inside: " + string.Join(" | ", openLines)));
                    // a page name at the very start of a text (10/28: PAGELINKS read the link as ' > Status')
                    { var lt = Ui.Linked(Ui.Text("Optimizations > In place names each setting.", Theme.B["Sub"], 12, null, "0"));
                      string Of(System.Windows.Documents.Inline i) => i is System.Windows.Documents.Run r ? "run '" + r.Text + "'" : i is System.Windows.Documents.Hyperlink h ? "link '" + LinkText(h) + "'" : i.GetType().Name;
                      var plain = Ui.Text("Optimizations > In place names each setting.", Theme.B["Sub"], 12, null, "0");
                      lt.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity)); plain.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
                      o.AppendLine($"LINKSTART: {string.Join(" + ", lt.Inlines.Select(Of))} | text '{lt.Text}' | {lt.DesiredSize.Width:0} of {plain.DesiredSize.Width:0} px"); }
                    o.AppendLine($"SWITCHROWS: {StatusModel.Catalog.Count(c => c.Keys.Count(k => k != c.Group && titles.ContainsKey(k)) > 0)} rows with another switch inside, " + (bad.Count == 0 ? "each named" : "missing: " + string.Join(" | ", bad)));
                }
                {   // a switch tweaks.ps1 keeps off on purpose on this PC says so (10/27: Game Bar "In place" on a dual-CCD X3D)
                    string K(string g, string js) { var r = StatusModel.KeptOnPurpose(g, Kit.ParseJson(js)); return r == null ? "-" : r.Value.State; }
                    o.AppendLine($"KEPTROWS: x3d game-bar {K("game-bar", "{\"dualX3D\":true}")} | x3d sysmain {K("sysmain-off", "{\"dualX3D\":true}")} | hdd sysmain {K("sysmain-off", "{\"sysHdd\":true}")} | plain {K("game-bar", "{\"dualX3D\":false}")}");
                    StatusModel M(params string[] st) { var m = new StatusModel(); foreach (var x in st) m.Rows.Add(new StatusRow { Level = "ok", State = x }); return m; }
                    o.AppendLine($"KEPTHEAD: {M("In place", "In place", "Kept - your processor needs it").AllInPlace} | {M("In place", "Put back today").AllInPlace}");
                    { var d = DateTime.Today; var tr = (d, "trying a 75% video memory budget"); var dr = (d, "Graphics driver 560.94");   // (a game's chart legend and Before and after: Messiah's own tries named)
                      o.AppendLine($"MARKNOTE: {Pages.Performance.MarkNote(new List<(DateTime, string)> { tr })} | {Pages.Performance.MarkNote(new List<(DateTime, string)> { dr })} | {Pages.Performance.MarkNote(new List<(DateTime, string)> { tr, dr })} | {Pages.Performance.NoChanges(true)}"); }
                    o.AppendLine($"OFFSUB: {Pages.Activity.OffSub(1, 0, 0, 0, 1)} | {Pages.Activity.OffSub(0, 1, 2, 1, 0)} | {Pages.Activity.OffSub(0, 0, 0, 0, 0)}");   // (Stability's Power-offs tile)
                    o.AppendLine($"BSODSUB: {Pages.Activity.BsodSub(new List<string>())} | {Pages.Activity.BsodSub(new List<string> { "0x109" })} | {Pages.Activity.BsodSub(new List<string> { "0x109", "0x109" })} | {Pages.Activity.BsodSub(new List<string> { "0x109", "0x3B" })} | {Pages.Activity.BsodSub(new List<string> { "" })}");   // (Stability's Blue screens tile)
                    o.AppendLine($"LASTCRASH: {Pages.Activity.LastCrash("bsod", "0x109", null, false)} | {Pages.Activity.LastCrash("off", null, "froze", false)} | {Pages.Activity.LastCrash("off", null, "unsure", false)} | {Pages.Activity.LastCrash("off", null, null, false)} | {Pages.Activity.LastCrash("off", null, "", true)}");   // (Stability's first tile)
                    {   // (10/28: This week's values start with a capital like 'None' and '5 app updates' - was 'graphics card 73 °C', 'ping 23 ms')
                        Dictionary<string, object> P(double days, string k, double v) => new Dictionary<string, object> { ["date"] = DateTime.Now.AddDays(-days).ToString("s"), ["game"] = "cod", [k] = v };
                        string W(params Dictionary<string, object>[] rows) { var sn = new Snapshot { Perf = rows.ToList(), Power = new List<Data.PowerEvent>(), Net = new List<Dictionary<string, object>>() }; return string.Join(" | ", Pages.Week.Rows(sn, new string[0], new List<string[]>()).Where(r => r.Label == "Hottest" || r.Label == "Connection").Select(r => r.Value)); }
                        o.AppendLine($"WEEKCAPS: {W(P(1, "gpuTemp", 73), P(1, "cpuTemp", 61))} | {W(P(1, "cpuTemp", 61))} | {W(P(1, "netPing", 23))}");
                        var thr = P(1, "gpuTemp", 70); thr["throttle"] = "heat,power";   // (10/28: each temperature with normal / warm / hot)
                        o.AppendLine($"WEEKHEAT: {W(P(1, "gpuTemp", 79), P(1, "cpuTemp", 80))} | {W(P(1, "gpuTemp", 86), P(1, "cpuTemp", 81))} | {W(thr)} | {W(P(1, "cpuTemp", 90))}");
                        string WeekMaint(params string[] rep) { var sn = new Snapshot { Perf = new List<Dictionary<string, object>>(), Power = new List<Data.PowerEvent>(), Net = new List<Dictionary<string, object>>() }; return Pages.Week.Rows(sn, new string[0], new List<string[]> { rep }).First(r => r.Label == "Maintenance").Value; }
                        o.AppendLine($"WEEKDRIVERS: {WeekMaint("NVIDIA: updating 560.94 -> 566.03...", "NVIDIA: installed 566.03", "NVIDIA: 566.03 installed; no NVIDIA app recommendation file to compare against")} | {WeekMaint("Driver: 'Realtek Audio' is for a device that is switched off - hidden, not installed", "NVIDIA: could not read installed driver version (nvidia-smi failed)")} | {WeekMaint("Driver: Intel - Net - 1.2.3 - installed", "AMD Radeon: installed 25.9.1", "AMD chipset: installed 7.06 - REBOOT to finish (whenever you next restart)")}");   // (10/28: one update read '2 drivers')
                        string L(Data.Session ss) => Data.SessionLines(ss).Last().Text;   // (Last session's temperatures get the same words - 10/28)
                        o.AppendLine($"SESSIONHEAT: {L(new Data.Session { Game = "cod", End = DateTime.Now, Minutes = 30, Samples = 2, Fps = 200, Low = 150, GpuTemp = 72, CpuTemp = 81.5 })} | {L(new Data.Session { Game = "cod", End = DateTime.Now, Minutes = 30, Samples = 1, Fps = 200, Low = 150, GpuTemp = 70, GpuSlowed = true })}");
                    }
                {   // (the audit's DASH check: the Edge switch's old line at the width where it broke after 'need -', and the same words without the dash - 10/28)
                    string D(string s, double w) { var tb = new System.Windows.Controls.TextBlock { Text = s, TextWrapping = TextWrapping.Wrap, FontSize = 14, FontFamily = new System.Windows.Media.FontFamily("Segoe UI") }; tb.Measure(new Size(w, double.PositiveInfinity)); tb.Arrange(new Rect(0, 0, w, tb.DesiredSize.Height)); return Messiah.MainWindow.DashEnd(tb) ?? "none"; }
                    var edge = "Off unless you turn it on. Uninstalls the Edge browser for good. WebView2 - the part apps and game launchers need - stays.";
                    o.AppendLine($"DASHEND: {D(edge, TextW(edge.Substring(0, edge.Length - 6)) + 4)} | {D(edge.Replace(" - the part", ", which").Replace(" need - stays", " need, stays"), TextW(edge.Substring(0, edge.Length - 6)) + 4)} | {D(edge, 2000)}");
                    // (several Runs - a bold start and the rest, like Ui.Rows' values: the same break is found)
                    var runsTb = new System.Windows.Controls.TextBlock { TextWrapping = TextWrapping.Wrap, FontSize = 14, FontFamily = new System.Windows.Media.FontFamily("Segoe UI") };
                    runsTb.Inlines.Add(new System.Windows.Documents.Run("Off unless you turn it on.") { FontWeight = FontWeights.SemiBold }); runsTb.Inlines.Add(new System.Windows.Documents.Run(edge.Substring(26)));
                    var tw = TextW(edge.Substring(0, edge.Length - 6)) + 4; runsTb.Measure(new Size(tw, double.PositiveInfinity)); runsTb.Arrange(new Rect(0, 0, tw, runsTb.DesiredSize.Height));
                    o.AppendLine($"DASHRUNS: {Messiah.MainWindow.DashEnd(runsTb) ?? "none"}");
                    // (the LONEMORE check: a line just wide enough for its words - with plain spaces 'More' drops alone onto a
                    // line of its own, with SwitchRow's no-break spaces it doesn't; both laid out by WPF - 10/28)
                    string Lone(string sep)
                    {
                        var words = "A row's details name each setting by its registry name instead of in plain words.";
                        var tb = new System.Windows.Controls.TextBlock { TextWrapping = TextWrapping.Wrap, FontSize = 12, FontFamily = new System.Windows.Media.FontFamily("Segoe UI") };
                        tb.Inlines.Add(new System.Windows.Documents.Run(words + sep)); tb.Inlines.Add(new System.Windows.Documents.Hyperlink(new System.Windows.Documents.Run("More")));
                        var one = new System.Windows.Controls.TextBlock { Text = words, FontSize = 12, FontFamily = tb.FontFamily }; one.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
                        var w = one.DesiredSize.Width + 4; tb.Measure(new Size(w, double.PositiveInfinity)); tb.Arrange(new Rect(0, 0, w, tb.DesiredSize.Height));
                        return $"{(Messiah.MainWindow.LoneMore(tb) ? "lone" : "not lone")} ({Math.Round(tb.DesiredSize.Height / one.DesiredSize.Height)} lines)";
                    }
                    o.AppendLine($"LONEMORE: plain {Lone("  ")} | no-break {Lone("  ")}");
                    double TextW(string s) { var t = new System.Windows.Controls.TextBlock { Text = s, FontSize = 14, FontFamily = new System.Windows.Media.FontFamily("Segoe UI") }; t.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity)); return t.DesiredSize.Width; }
                }
                o.AppendLine($"OLDNOTE: {Pages.Activity.OldNote(3, 1).Split('.')[0]} | {Pages.Activity.OldNote(1, 1).Split('.')[0]} | {Pages.Activity.OldNote(2, 0).Split('.')[0]}");   // (Stability's note: unanswered ones from before the chart named)
                o.AppendLine($"BACKUPWHEN: {Pages.Settings.BackupWhen(null)} | {Pages.Settings.BackupWhen(DateTime.Now.AddDays(-1))} | {Pages.Settings.BackupWhen(DateTime.Now.AddDays(-10))}");   // (Settings' backup card: when the next one is made)
                o.AppendLine($"BACKUPLAST: {Pages.Settings.BackupLast(DateTime.Today.AddDays(-1).AddHours(4), @"C:\Users\x\Documents\PC Setup Kit Backup", @"C:\Users\x\Documents")} | {Pages.Settings.BackupLast(DateTime.Today.AddDays(-1), @"D:\PC Setup Kit Backup", @"C:\Users\x\Documents")} | {Pages.Settings.BackupWhat.Split(',')[0]}");   // (its lines in the app's words, 10/28)
                { var lb = Data.LastSettingsBackup(); o.AppendLine($"BACKUPFOUND: {(Kit.RealHome ? "real" : "made-up")} home | {(lb == null ? "none" : Pages.Settings.BackupLast(lb.LastWriteTime, lb.DirectoryName))}"); }   // (a made-up home's own Documents, 10/28)
                    o.AppendLine("ARTICLE: " + string.Join(" | ", new[] { "0.850000", "0.750000", "0.080000", "0.110000", "0.180000", "0.800000", "1.000000" }.Select(v => Pages.Performance.Say("vram", v))));   // a/an by how the number is read aloud
                    var gAt = DateTime.Now.AddMinutes(-5);
                    o.AppendLine($"GUARDSUB: {Pages.Home.GuardSub(null, gAt, false, 0).Split(new[] { ", " }, StringSplitOptions.None).Last()} | {Pages.Home.GuardSub(null, gAt, false, 2).Split(' ')[0]} put back | {Pages.Home.GuardSub(null, null, false, 0)} | {Pages.Home.GuardSub("Off", gAt, false, 0)}");   // (Home's Guarded tile: no 'in place' twice)
                    o.AppendLine($"KEPTSUB: {Pages.Home.GuardSub(null, gAt, false, 0, new[] { Pages.Home.KeptName("Xbox Game Bar removed") })} | {Pages.Home.GuardSub(null, gAt, false, 0, new[] { Pages.Home.KeptName("SysMain (app prefetch) off"), "x" })} | {Pages.Home.GuardSub(null, gAt, false, 2, new[] { "x" }).Split(' ')[0]} put back");   // (the tile names what '1 kept' is - 10/28)
                    var bl = Pages.Settings.BiosLines(new Data.Bios { Maker = "ASUSTeK", Model = "ROG STRIX B650", Version = "3602", Date = "2026-08-01", Url = "https://www.asus.com/supportonly/ROG%20STRIX%20B650/helpdesk_bios/",
                        Steps = "1. Open https://www.asus.com/supportonly/ROG%20STRIX%20B650/helpdesk_bios/ and download the newest BIOS (newer than 3602 from 2026-08-01). 2. Unzip it." });
                    o.AppendLine($"BIOSCARD: {bl[0].Replace(' ', ' ')} | {(string.Join(" ", bl).Contains("http") ? "ADDRESS" : "no address")} | {string.Join(" / ", bl.Skip(2))}");   // (Settings > Tools: no raw address, a readable date)
                    o.AppendLine($"HEADDATE: {(bl[0].Split(new[] { " from " }, StringSplitOptions.None).Last().Contains(' ') ? "splits" : "one piece")} | {Pages.Settings.HeadDate("Oct 16, 2026").Replace(' ', '~')}");   // (Tools' driver and BIOS heads: '2026' never alone on a line at 480 - 10/28)
                    try
                    {   // (Tools' BIOS card: the steps folded under 'How to update it', a click opens them and the link says how to fold them - 10/28)
                        var fl = Ui.FoldLines(bl[1], Pages.Settings.BiosFold, "Hide the steps", bl.Skip(3));
                        var body = (FrameworkElement)fl.Children[1]; var lead = (System.Windows.Controls.TextBlock)fl.Children[0];
                        var link = lead.Inlines.OfType<System.Windows.Documents.Hyperlink>().Last(); string Ln() => ((System.Windows.Documents.Run)link.Inlines.FirstInline).Text.Replace(' ', ' ');
                        var shut = $"{body.Visibility} {((System.Windows.Controls.Panel)body).Children.Count} steps, '{Ln()}'";
                        link.RaiseEvent(new RoutedEventArgs(System.Windows.Documents.Hyperlink.ClickEvent));
                        o.AppendLine($"BIOSFOLD: {shut} | {body.Visibility}, '{Ln()}' | {bl[1]}");
                    }
                    catch (Exception ex) { o.AppendLine("BIOSFOLD: error " + ex.Message); }
                    o.AppendLine("BOARDMAKER: " + string.Join(" | ", new[] { "ASUSTeK COMPUTER INC.", "Micro-Star International Co., Ltd.", "Gigabyte Technology Co., Ltd.", "ASRock", "Acme Boards Inc.", "" }.Select(Pages.Settings.BoardMaker)));   // (Tools' BIOS card: the name on the box)
            o.AppendLine($"ABOUTLINE: {Pages.Settings.AboutLine("v2.4.1", DateTime.Today.AddDays(-1).AddHours(4), null)} | {Pages.Settings.AboutLine("", null, DateTime.Today.AddDays(-1).AddHours(4))} | {Pages.Settings.AboutLine("", null, null)}");   // (About: which version, and when it came - 10/28)
            o.AppendLine($"ABOUTNOTE: {(Pages.Settings.AboutNote.Contains("Ctrl+Alt+M") || Pages.Settings.AboutNote.Contains(";") ? "repeats keys" : "plain")} | {Pages.Settings.AboutNote}");   // (the keys only on Keyboard shortcuts - 10/28)
                    o.AppendLine($"SETUPLINE: {Pages.Settings.SetupLine(0).Split(new[] { ": ", ". " }, StringSplitOptions.None)[1]} | {Pages.Settings.SetupLine(3).Split(new[] { ": ", ". " }, StringSplitOptions.None)[1]}");   // (Settings > Tools' Your setup: no '0 chosen')
                    o.AppendLine($"PRESETS: {string.Join(", ", Pages.Settings.Presets.Select(p => p.Name))} | {string.Join(" / ", Pages.Settings.PresetLines)}");   // (the note explains them in the buttons' order, one line each)
                    o.AppendLine($"KITLINE: {Data.AppLine("PC Setup Kit updated v2026.10.20 -> v2026.10.25")} | {Data.AppLine("PC Setup Kit updated v2026.10.25")} | {Data.AppLine("Removed temporary files (800 MB)")}");   // (Checks / Since you last looked: the app's own name)
                    o.AppendLine($"DRIVERLINE: {Data.AppLine(Data.WithWas(new[] { "NVIDIA: updating 560.94 -> 566.03...", "NVIDIA: installed 566.03" })[1])} | {Data.AppLine(Data.WithWas(new[] { "AMD Radeon: installed 24.10.1" })[0])} | {Data.AppLine("NVIDIA: 566.03 is up to date")}");   // (Checks: the graphics driver in plain words - 10/28)
                    // (What maintenance did: changes only - a line that just mentions an install stays out, 10/28)
                    o.AppendLine("DIDLINES: " + string.Join(" | ", new[] { "NVIDIA: installed 566.03", "NVIDIA: 560.94 installed; no NVIDIA app recommendation file to compare against", "Driver: Realtek Audio - installed",
                        "Disk Cleanup: skipped - Windows was installed 3 day(s) ago, nothing to clean yet", "Reminder: startup audit - new auto-start entries not signed by their maker: X (fine if you just installed it)",
                        "Steam: moved leftover folders of uninstalled games to the Recycle Bin: Hunt" }.Select(x => (Data.Did(x) ? "did " : "not ") + x.Split(':')[0])));
                    o.AppendLine($"KEPTTILE: {M("In place", "In place", "Kept - your processor needs it").TileInPlace} | {M("In place", "Put back today").TileInPlace}");   // (Home's tile; the report's STATUS line uses AllInPlace)
                }
                {   // Trends says 'point at a chart' once in its subtitle, not under each of its 6 charts (10/27); a lone chart still says it
                    IEnumerable<DependencyObject> Tree(DependencyObject d) { yield return d; foreach (var c in LogicalTreeHelper.GetChildren(d).OfType<DependencyObject>()) foreach (var x in Tree(c)) yield return x; }
                    int Hints(Border b) => Tree(b).OfType<TextBlock>().Count(t => (t.Text ?? "").Contains("to read a day"));
                    var tw2 = new[] { (DateTime.Now.AddDays(-2), 40.0), (DateTime.Now, 42.0) };
                    o.AppendLine($"TRENDHINT: trends chart {Hints(Pages.Activity.Chart("Test", " °C", tw2, 0, 10))} | lone chart {Hints(Pages.Charts.Chart("Test", " °C", tw2.Select(p => new Pages.ChartPt { D = p.Item1, V = p.Item2 }), 0, 10))} | subtitle {(Messiah.MainWindow.Subs.TryGetValue("Activity/Trends", out var trSub) && trSub.Contains("Point at a chart") ? "says it" : "doesn't")}");
                    o.AppendLine($"SUBDASH: {Messiah.MainWindow.Subs.Count(kv => kv.Value.Contains(" - "))} of {Messiah.MainWindow.Subs.Count} subtitles join with a dash | Choose {Messiah.MainWindow.Subs["Settings/Windows"]}");
                    o.AppendLine($"HERODASH: {new[] { Pages.Home.AllGood, Pages.Home.Handling, Pages.Home.NoCheckYet }.Count(t => t.Contains(" - "))} of 3 headline states join with a dash | {Pages.Home.AllGood}");
                    {   // Home's tile sub lines and the Claude card (10/28: 'Checked 2h ago - nothing undone', 'Off - see Status' for a tab named Optimizations)
                        var hs = new[] { Pages.Activity.SchedWhen("due now", true), Pages.Home.GuardSub("Off", DateTime.Now, false, 0), Pages.Home.GuardSub(null, DateTime.Now, true, 0),
                            Pages.Home.GuardSub(null, DateTime.Now, false, 0), Pages.Home.GuardSub(null, DateTime.Now, false, 0, new[] { "a", "b" }), Pages.Home.ClaudeReady, Pages.Home.ClaudeNew };
                        o.AppendLine($"HOMESUBDASH: {hs.Count(t => t.Contains(" - "))} of {hs.Length} join with a dash | {(hs.Any(t => t.Contains("Status")) ? "says Status" : "no Status")} | {hs[1]} | {hs[5]}");
                    }
                    {   // Settings > Tools' grey notes and the presets (10/28: 'go back to the driver before it - a restore point...', 'Removes Messiah - the tray icon...')
                        var tn = new[] { Pages.Settings.DriverNote, Pages.Settings.HelpNote, Pages.Settings.UninstallNote, Pages.Settings.HeldNote("566.03"), Pages.Settings.ClaudeNote("2.1.0") }
                            .Concat(Pages.Settings.Presets.Select(p => p.About)).ToArray();
                        o.AppendLine($"TOOLSDASH: {tn.Count(t => t.Contains(" - "))} of {tn.Length} join with a dash | {tn[2]}");
                        o.AppendLine($"USBNOTE: {(Pages.Settings.UsbNote.Contains(";") || Pages.Settings.UsbNote.Contains(" min.") ? "terse" : "plain")} | {Pages.Settings.UsbNote.Substring(Pages.Settings.UsbNote.IndexOf("It erases"))}");   // (Install USB: was 'Erases it; 20-40 min.' - 10/28)
                    }
                    // the amber line is named in the subtitle only when a chart shows one in its range (10/28)
                    var mk2 = new[] { (DateTime.Now.AddDays(-1), "Call of Duty installed") };
                    o.AppendLine($"TRENDMARK: with a mark {(Pages.Charts.ShowsMark(Pages.Activity.Chart("Test", " GB", tw2, 0, 10, marks: mk2)) ? "shows" : "doesn't")} | none {(Pages.Charts.ShowsMark(Pages.Activity.Chart("Test", " GB", tw2, 0, 10)) ? "shows" : "doesn't")} | before the chart {(Pages.Charts.ShowsMark(Pages.Activity.Chart("Test", " GB", tw2, 0, 10, marks: new[] { (DateTime.Now.AddDays(-90), "old") })) ? "shows" : "doesn't")} | sub {(Pages.Activity.TrendsMarkSub.Contains("amber line") && Pages.Activity.TrendsMarkSub.StartsWith(trSub.TrimEnd('.')) ? "ok" : "differs")}");
                    // ... and follows a range change: 7 days leaves a 20-day-old mark out, All brings it back (10/28)
                    {
                        var tw40 = Enumerable.Range(0, 9).Select(i => (DateTime.Now.AddDays(-40 + i * 5), 900.0 - i * 10)).ToArray();
                        var rb = Pages.Activity.Chart("Test", " GB", tw40, 0, 10, marks: new[] { (DateTime.Now.AddDays(-20), "Call of Duty installed") });
                        var rc = (Pages.ChartCtl)Tree(rb).OfType<Canvas>().First(c => c.DataContext is Pages.ChartCtl).DataContext;
                        int fired = 0; Action f = () => fired++; Pages.Charts.RangeChanged += f;
                        string Sub() => Pages.Activity.TrendsSub("plain", new[] { rb }) == "plain" ? "plain" : "amber";
                        var at30 = Sub(); rc.Range("7 days"); var at7 = Sub(); rc.Range("All"); var atAll = Sub(); rc.Range("30 days");
                        Pages.Charts.RangeChanged -= f;
                        o.AppendLine($"TRENDRANGE: 30 days {at30} | 7 days {at7} | All {atAll} | told {fired}");
                    }
                    // a chart of checks whose newest point is days old names that day (Start-up time: cold starts only, 10/28)
                    string Tg(Border b) => Tree(b).OfType<StackPanel>().First(x => x.Tag is string t && t.StartsWith("CHART:")).Tag.ToString().Split('|')[1].Trim();
                    var old2 = new[] { (DateTime.Now.AddDays(-9), 9.0), (DateTime.Now.AddDays(-5), 8.0) };
                    o.AppendLine($"STALECHART: old {Tg(Pages.Activity.Chart("Old", " s", old2, 1, 10))} | fresh {Tg(Pages.Activity.Chart("Fresh", " s", tw2, 0, 10))}");
                    // the layout audit finds a line a panel cuts off, though the line itself got all the room it asked for (10/28)
                    string Cut(string words, bool wrap)
                    {
                        var tb = new TextBlock { Text = words, FontSize = 14, TextWrapping = wrap ? TextWrapping.Wrap : TextWrapping.NoWrap };
                        var dp = new DockPanel(); var row = new StackPanel { Orientation = Orientation.Horizontal };
                        if (wrap) dp.Children.Add(tb); else { row.Children.Add(tb); dp.Children.Add(row); }
                        var box = new Border { Width = 200, Child = dp }; box.Measure(new Size(200, 100)); box.Arrange(new Rect(0, 0, 200, 100));
                        return Messiah.MainWindow.CutByParent(tb, box) ?? "whole";
                    }
                    o.AppendLine($"AUDITCUT: long {Cut("Free space down 100 GB since Sep 29, 2026", false)} | short {Cut("down 1 GB", false)} | wrapped {Cut("Free space down 100 GB since Sep 29, 2026", true)}");
                    // ... and with no hint, no blank row under the chart: the readout takes the dates line's place when pointed at (10/27)
                    string Foot(Border b)
                    {
                        var sp = Tree(b).OfType<StackPanel>().First(x => x.Tag is string t && t.StartsWith("CHART:"));
                        var ctl = (Pages.ChartCtl)Tree(b).OfType<Canvas>().First(c => c.DataContext is Pages.ChartCtl).DataContext;
                        string Shown() => string.Join(" ", Tree(sp.Children[sp.Children.Count - 1]).OfType<FrameworkElement>().Where(e => (e is TextBlock || e is DockPanel) && e.Visibility == Visibility.Visible && !(e.Parent is DockPanel)).Select(e => e is DockPanel ? "dates" : "readout"));
                        var idle = Shown(); ctl.Hover(0); var on = Shown(); ctl.Hover(-1);
                        return $"{sp.Children.Count} rows, {idle} -> pointed {on}";
                    }
                    // a mark's words are read anywhere along its dashed line (5 px either side), not only on its 8 px triangle (10/28)
                    {
                        var mp = new[] { (-10, 100.0), (-5, 90.0), (0, 40.0) }.Select(p => new Pages.ChartPt { D = DateTime.Today.AddDays(p.Item1), V = p.Item2 });
                        var mb = Pages.Charts.Chart("Marks", " GB", mp, 0, 10, new[] { (DateTime.Today.AddDays(-3), "Call of Duty installed") }, drift: true);
                        var mc = (Pages.ChartCtl)Tree(mb).OfType<Canvas>().First(c => c.DataContext is Pages.ChartCtl).DataContext;
                        string Kind(string t) => t.EndsWith(": Call of Duty installed") ? "mark" : t.Contains("(changed: Call of Duty installed)") ? "point after it" : t.Contains(" GB") ? "point" : "idle";
                        o.AppendLine($"MARKHOVER: on the line {Kind(mc.Near(0, 0))} | 4 px off {Kind(mc.Near(0, -4))} | 30 px off {Kind(mc.Near(0, -30))} | keys {Kind(mc.Hover(2))} | '{mc.Near(0, 1)}'");
                    }
                    o.AppendLine($"CHARTFOOT: trends chart {Foot(Pages.Activity.Chart("Test", " °C", tw2, 0, 10))} | lone chart {Foot(Pages.Charts.Chart("Test", " °C", tw2.Select(p => new Pages.ChartPt { D = p.Item1, V = p.Item2 }), 0, 10))}");
                }
                { var h0 = StatusModel.HistBuilt; Snapshot.Load(); o.AppendLine($"HISTRX: {StatusModel.HistBuilt} history patterns kept, a second read built {StatusModel.HistBuilt - h0}"); }
                { var r0 = Kit.OptReads; for (int i = 0; i < 300; i++) Kit.Opt("technames", "off"); var opts = Kit.Lines(Kit.P("kit-options.txt"));
                  // (the same answer the old way gave: the first 'key=' line, any case, spaces around the key)
                  string Old(string k) { var l = opts.FirstOrDefault(x => System.Text.RegularExpressions.Regex.IsMatch(x, @"^\s*" + System.Text.RegularExpressions.Regex.Escape(k) + @"\s*=", System.Text.RegularExpressions.RegexOptions.IgnoreCase)); return l == null ? "-" : l.Split(new[] { '=' }, 2)[1].Trim(); }
                  var keysSeen = opts.Select(x => x.Split('=')[0].Trim()).Where(x => x.Length > 0).Concat(new[] { "technames", "no.such.key" }).Distinct().ToList();
                  o.AppendLine($"OPTCACHE: 300 asks, {Kit.OptReads - r0} file reads | {keysSeen.Count(k => Kit.Opt(k, "-") == Old(k))} of {keysSeen.Count} keys as before"); }
                foreach (var key in new[] { "Welcome", "Home", "Status", "Activity/Checks", "Activity/Stability", "Activity/Trends", "Activity/Performance", "Activity/Storage", "Activity/Alerts", "Settings/General", "Settings/Windows", "Settings/Tools" })
                {
                    sw.Restart();
                    List<UIElement> els; string err = null;
                    try { els = w.BuildPage(key, snap); } catch (Exception e) { els = new List<UIElement>(); err = e.ToString(); }
                    o.AppendLine($"PAGE: {key}  (built in {sw.ElapsedMilliseconds} ms)"); if (err != null) o.AppendLine("PAGE ERROR: " + err);
                    foreach (var el in els) Dump(el, o);
                    foreach (var el in els) foreach (var miss in Unnamed(el)) o.AppendLine($"A11Y: {key}: {miss}");
                    // every 'Tab > Page' on the page that opens it (Ui.Linked - footers, lines, switches' words)
                    var pl = els.SelectMany(GoLinks).ToList();
                    if (pl.Count > 0) o.AppendLine($"PAGELINKS: {key}: " + string.Join(" | ", pl));
                    // the grey lines folded to two lines (over 200 characters): how long each is, so the ones just over can be shortened
                    foreach (var tb in els.SelectMany(Find<TextBlock>).Where(t => t.TextTrimming == TextTrimming.WordEllipsis && t.Cursor == System.Windows.Input.Cursors.Hand))
                        o.AppendLine($"FOLDED: {key}: {tb.Text.Length} | {(tb.Text.Length > 60 ? tb.Text.Substring(0, 60) : tb.Text)}");
                }
                foreach (var miss in Unnamed(w.Content)) o.AppendLine($"A11Y: window: {miss}");   // (the window's own parts: the tabs, the chat)
                // the card Open lands on flashes: a card its own border, a group of settings each setting's card
                var gen = w.BuildPage("Settings/General", snap).OfType<Border>().ToList();
                var fc = gen.FirstOrDefault(b => (b.Tag as CardInfo)?.Title == "Keyboard shortcuts"); var fg = gen.FirstOrDefault(b => (b.Tag as CardInfo)?.Title == "Display");
                o.AppendLine($"FLASH: card {(fc == null ? -1 : Ui.Flash(fc))} accent {(fc?.BorderBrush as System.Windows.Media.SolidColorBrush)?.Color == Theme.B["Accent"].Color} | group {(fg == null ? -1 : Ui.Flash(fg))}");
                o.AppendLine("SORT: " + Pages.Storage.SortLine(snap));
                o.AppendLine("SHARE: " + Pages.Storage.ShareLine(snap));   // (each game's share of its drive - the thin bar under it)
                o.AppendLine("FREES: " + Pages.Storage.FreesLine(snap));   // (a big game on a nearly full drive: what moving it would free)
                o.AppendLine("LOOKED: " + Data.Looked(new[] { "Checked 10/27/2026 12:19 PM in 30s", "[Drivers]", "NVIDIA: 621.01 is up to date", "Other drivers: all up to date (Windows Update)",
                    "Claude Code: 2.1.311 (up to date)", "Crashes: none since last check", "Tweaks: all still applied", "Apps: 2 update(s) available (Git) - the weekly app update installs them",
                    "Call of Duty tuning: kept Reflex Boost on", "Game saves: 2 of 14 games had new saves", "Next: App updates Nov 3" }) + " | " + Data.Looked(new[] { "Checked 10/27/2026 12:19 PM in 30s" }) + "|");   // (Checks' 'All fine' says what it looked at)
                o.AppendLine($"SCANNED: {Pages.Storage.Scanned(DateTime.Today.AddHours(0.2))} | {Pages.Storage.Scanned(null)}");   // (Storage's footer: when the scan ran - was "Looked ...")
                o.AppendLine("STORES: " + Pages.Storage.StoresLine(snap));   // (each game row's store - a folder game a Steam shortcut starts says so)
                o.AppendLine("STARTS: " + Pages.Storage.StartsLine(snap));   // (Installed twice: which copy its launcher starts)
                {   // (a drive's games line: a game installed twice on it is one game, named)
                    object Gm(string p, double gb) => new Dictionary<string, object> { ["path"] = p, ["sizeGB"] = gb };
                    var on = new List<object> { Gm(@"C:\Steam\steamapps\common\COD", 245), Gm(@"C:\Games\NBA 2K23", 132.3), Gm(@"C:\Steam\steamapps\common\NBA 2K23", 118) };
                    var dupe = new List<object> { new Dictionary<string, object> { ["name"] = "NBA 2K23", ["places"] = new object[] { @"Steam: C:\Steam\steamapps\common\NBA 2K23 (118 GB)", @"Folder: C:\Games\NBA 2K23 (132 GB)" } } };
                    o.AppendLine($"GAMESLINE: {Pages.Storage.GamesLine(on, dupe)} | {Pages.Storage.GamesLine(on.Take(2).ToList(), dupe)} | {Pages.Storage.GamesLine(on, null)}");
                }
                o.AppendLine("CRASHREPORT: " + string.Join(" / ", Actions.CrashReport(snap, machine: false).Split(new[] { "\r\n" }, StringSplitOptions.None).Skip(1).Where(x => x != "")) + $" | names: {Actions.BugName("0x00000109")}, {Actions.BugName("124")}, {Actions.BugName("0x1234")}");   // (Stability's Copy a crash report, without the PC's own parts)
                {   // (Ctrl+K search's "Copy a crash report": there with a crash recorded, not with only the owner's own power-offs)
                    var was = w.snap; string Hit() { w.snap = snap; return w.SearchIndex().FirstOrDefault(h => h.Title == "Copy a crash report")?.Sub ?? "none"; }
                    var keep = snap.Power ?? new List<Data.PowerEvent>(); var with = Hit(); snap.Power = keep.Where(e => !Actions.IsCrash(e)).ToList(); var without = Hit(); snap.Power = keep; w.snap = was;
                    o.AppendLine($"SEARCHCRASH: {with} | only the owner's power-offs: {without}");
                }
                {   // (... a folder nothing starts, one a shortcut reaches through its junction, a near name that isn't inside, one with its own installer)
                    var ex = new[] { @"C:\.preserve\2k17\NBA2K17.exe" };
                    o.AppendLine("STARTSCASES: " + string.Join(" | ", Pages.Storage.Starts(@"Folder: C:\Games\A (5 GB)", ex), Pages.Storage.Starts(@"Folder: C:\Games\NBA 2K17 (60 GB)", ex, @"C:\.preserve\2k17"),
                        Pages.Storage.Starts(@"Folder: C:\Games\NBA 2K1 (60 GB)", new[] { @"C:\Games\NBA 2K17\x.exe" }), Pages.Storage.Starts(@"Other: D:\Riot\Valorant (30 GB)", ex)));
                }
                {   // (Games > Storage: a row without a Move button says why in its tooltip - made-up C: and D:)
                    var dr = new List<object> { new Dictionary<string, object> { ["letter"] = "C", ["freeGB"] = 50.0 }, new Dictionary<string, object> { ["letter"] = "D", ["freeGB"] = 100.0 } };
                    object G(string store, double gb, bool mv) => new Dictionary<string, object> { ["name"] = "G", ["drive"] = "C", ["sizeGB"] = gb, ["movable"] = mv, ["store"] = store };
                    string W(string store, double gb, bool mv) { var x = Pages.Storage.WhyNoMove(G(store, gb, mv), dr, store); return x == "" ? "none" : x.Split(' ')[0]; }
                    o.AppendLine($"WHYNOMOVE: steam {W("Steam", 40, true)} | too big {W("Steam", 200, true)} | epic {W("Epic", 40, false)} | shortcut {W("Steam shortcut", 40, false)} | own {W("Other", 40, false)} | folder {W("Folder", 40, false)} | one drive {(Pages.Storage.WhyNoMove(G("Epic", 40, false), dr.Take(1).ToList(), "Epic") == "" ? "none" : "said")}");
                }
                {   // (Games > Storage: a long game name trims and keeps 'Epic - D:' beside it on one line; a short one sizes to itself)
                    string NT(string name, double w)
                    {
                        var g = Pages.Storage.NameTag(name, "Epic - D:"); g.Measure(new Size(w, double.PositiveInfinity)); g.Arrange(new Rect(g.DesiredSize));
                        var nm = (TextBlock)g.Children[0]; var tag = (TextBlock)g.Children[1];
                        nm.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity)); var full = nm.DesiredSize.Width;
                        return $"{(g.DesiredSize.Height < 30 ? "one line" : "two lines")} {(g.DesiredSize.Width <= w + 0.5 ? "fits" : "spills")} {(tag.ActualWidth + 0.5 >= tag.DesiredSize.Width && tag.ActualWidth > 0 ? "tag whole" : "tag cut")} {(nm.ActualWidth + 1 < full - 10 ? "trimmed" : "whole")}";
                    }
                    o.AppendLine($"NAMETAG: long {NT("Tom Clancy's Rainbow Six Siege - Operation Deadly Omen Edition", 300)} | short {NT("Apex Legends", 300)}");
                }
                {   // (Home's Next tile: before any check, then the soonest of the scheduled checks, then a due one first)
                    var sc = new Section(); string D(int n) => DateTime.Now.AddDays(n).ToString("MMM d, yyyy");
                    sc.Lines.Add(new Line($"App updates:       {D(5)}")); sc.Lines.Add(new Line($"Cleanup:           {D(2)}  (every month: temporary files, old drivers, a restore point)")); sc.Lines.Add(new Line($"Benchmark:         {D(40)}  (every 3 months, compared with day one)"));
                    string N((string Value, string Sub) t) => t.Value + " / " + t.Sub;
                    sc.Lines.Add(new Line($"Self-check:        {D(1)}  (the app tests itself every week and after updates). Last run Oct 25: all fine."));   // (left out - the soonest here)
                    var a = N(Pages.Home.NextCheck(sc, false)); var b = N(Pages.Home.NextCheck(sc, true));
                    sc.Lines.Add(new Line("Dust reminder:     due now  (every 6 months)"));
                    var only = new Section(); only.Lines.Add(new Line($"Self-check:        {D(1)}  (the app tests itself every week)"));
                    o.AppendLine($"NEXT: {a} | {b} | {N(Pages.Home.NextCheck(sc, true))} | {N(Pages.Home.NextCheck(new Section(), true))} | {N(Pages.Home.NextCheck(only, true))}");
                    // (Home's Claude card: "Close chat" while the chat is open - its click, and the chat opened or closed elsewhere)
                    {
                        var panel = new System.Windows.Controls.Border { Visibility = Visibility.Collapsed };
                        var cb = Pages.Home.ChatBtn(panel, on => panel.Visibility = on ? Visibility.Visible : Visibility.Collapsed);
                        string T() => System.Windows.Automation.AutomationProperties.GetName(cb) + (cb.Style == Application.Current.FindResource("AccentBtn") ? " (accent)" : "");
                        var c1 = T(); cb.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent)); var c2 = T();
                        cb.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent)); var c3 = T();
                        o.AppendLine($"CHATBTN: {c1} | {c2} | {c3} | closed again {panel.Visibility == Visibility.Collapsed}");
                    }
                    // (Home's Free space tile: the last check, else the storage scan's system drive, else C: read now)
                    var stj = new Dictionary<string, object> { ["drives"] = new List<object> { new Dictionary<string, object> { ["letter"] = "D", ["freeGB"] = 5.0 }, new Dictionary<string, object> { ["letter"] = "C", ["system"] = true, ["freeGB"] = 120.0 } } };
                    string F(double? v) => v == null ? "none" : Math.Round(v.Value).ToString();
                    o.AppendLine($"REPORTTIME: {Kit.ReportTime(new System.IO.FileInfo("report-20261013-163220-update.txt")):yyyy-MM-dd HH:mm:ss} | {Kit.ReportTime(new System.IO.FileInfo("report-20261027-121955.txt")):yyyy-MM-dd HH:mm:ss} | {(Kit.ReportTime(new System.IO.FileInfo("report-old.txt")).Year < 1700 ? "file time" : "?")}");
                    o.AppendLine($"FREEC: {F(Pages.Home.FreeC(new Dictionary<string, object> { ["freeGB"] = 80.4 }, stj, () => 42))} | {F(Pages.Home.FreeC(null, stj, () => 42))} | {F(Pages.Home.FreeC(null, null, () => 42))} | {F(Pages.Home.FreeC(null, null, () => throw new System.IO.IOException()))} | {(Pages.Home.FreeC(null, null) > 0 ? "read now" : "none")}");
                    // (Home's Last game tile: says when, opens the game's card on Performance)
                    var lgA = Pages.Home.LastGame(new Dictionary<string, object> { ["game"] = "cod", ["fps"] = 198.6, ["low1"] = 149.2, ["date"] = DateTime.Today.AddHours(-3).ToString("s") });
                    var lgB = Pages.Home.LastGame(null);
                    o.AppendLine($"LASTGAME: {lgA.Value} / {lgA.Sub} -> {lgA.Go} | {lgB.Value} / {lgB.Sub} -> {lgB.Go}");
                    // (Game check-up, 10/28: with the game's sessions the tile ends with the verdict in a few words; Home's Last
                    // session card says the whole verdict under its numbers when its last minute is the game's latest)
                    Dictionary<string, object> Lv(string g, double fps, double low, double busy, string at) => new Dictionary<string, object> { ["game"] = g, ["fps"] = fps, ["low1"] = low, ["frames"] = 8000, ["gpuBusy"] = busy, ["date"] = at };
                    var lvAt = DateTime.Today.AddHours(-3).ToString("s");
                    var lvCap = Lv("NBA2K20", 59.6, 57, 40, lvAt); var lvCpu = Lv("cod", 150, 110, 48, lvAt); var lvOld = Lv("cod", 150, 110, 48, DateTime.Today.AddDays(-9).ToString("s"));
                    var lvS = new Data.Session { Game = "cod", Start = DateTime.Today.AddHours(-4), End = DateTime.Today.AddHours(-2), Minutes = 120, Samples = 1, Fps = 150, Low = 110 };
                    o.AppendLine($"LASTVERDICT: {Pages.Home.LastGame(lvCap, new List<Dictionary<string, object>> { lvCap }, 240).Sub} | {Pages.Home.LastGame(lvCpu, new List<Dictionary<string, object>> { lvCap, lvCpu }, 240).Sub}"
                        + $" | {Pages.Home.LastGame(lvCpu, new List<Dictionary<string, object>> { lvCpu, lvOld }, 240).Sub}"
                        + $" | session: {Pages.Home.SessionLines(lvS, new List<Dictionary<string, object>> { lvCpu }, 240).ElementAtOrDefault(1)?.Text} | old: {Pages.Home.SessionLines(lvS, new List<Dictionary<string, object>> { lvOld }, 240).Count}");
                    // (Trends' Free space on C:: a mark at each drop of 20 GB+, naming the game whose folder appeared then)
                    var d0 = new DateTime(2026, 10, 1);
                    var drops = Pages.Activity.FreeDrops(new[] { (d0, 500.0), (d0.AddDays(1), 490.0), (d0.AddDays(2), 400.0), (d0.AddDays(4), 370.0) },
                        new[] { ("Call of Duty", d0.AddDays(1.5), 80.0), ("Small game", d0.AddDays(3), 5.0), ("Old game", d0.AddDays(-9), 90.0) });
                    o.AppendLine("FREEDROPS: " + string.Join(" | ", drops.Select(m => $"{m.D:MM-dd} {m.Text}")));
                    // (its line beside the number: the marked drop that is most of the fall, its day and why; a slow fill, a rise say only how far)
                    Func<double, string> gb = v => Math.Round(v) + " GB";
                    var fp = new List<(DateTime D, double V)> { (d0, 500.0), (d0.AddDays(1), 490.0), (d0.AddDays(2), 400.0), (d0.AddDays(4), 370.0) };
                    var slow = Enumerable.Range(0, 6).Select(i => (d0.AddDays(i), 500.0 - i * 10)).ToList();
                    o.AppendLine("DRIFTSINCE: " + Pages.Charts.DriftSince(fp, drops, gb, 0) + " | " + Pages.Charts.DriftSince(fp, new[] { (d0.AddDays(2), "90 GB less free") }, gb, 0)
                        + " | " + Pages.Charts.DriftSince(slow, drops, gb, 0) + " | " + Pages.Charts.DriftSince(new List<(DateTime D, double V)> { (d0, 400.0), (d0.AddDays(1), 450.0) }, null, gb, 0));
                    // (Checks' Scheduled checks: the same words - tomorrow, a date without its year, a far one with it, due)
                    string W(string v, bool once) => Pages.Activity.SchedWhen(v, once);
                    o.AppendLine($"SCHEDWHEN: {W(D(1), true)} | {W(D(40) + "  (every 3 months, compared with day one)", true)} | {(W(D(360), true) == D(360) ? "year kept" : W(D(360), true))} | {W("due now  (every 6 months)", true)} | {W("due now", false)}");
                    // (and soonest first: due, the next login, then by date; one without a date last)
                    var so = Pages.Activity.SchedOrder(new[] { new Line("Full tune-up:  " + D(330)), new Line("Cleanup:  " + D(12)), new Line("Notes:  later"), new Line("Self-check:  at the next login"), new Line("Benchmark:  due now"), new Line("App updates:  " + D(1)) });
                    o.AppendLine("SCHEDORDER: " + string.Join(", ", so.Select(l => l.Text.Split(':')[0])));
                    // (the footer says when restart-only work finishes, by Restart at night)
                    o.AppendLine($"SCHEDFOOT: {Pages.Activity.SchedFooter(true)} | {Pages.Activity.SchedFooter(false)}");
                    // (and so does the restart-pending card)
                    o.AppendLine($"RESTARTCARD: {Data.RestartFinish(true)} | {Data.RestartFinish(false)}");
                    // (Last background check's run time: seconds under a minute, else about N minutes)
                    o.AppendLine("DAYNAME: " + string.Join(" | ", new[] { 0, 1, 3, 20, 400 }.Select(n => Pages.Activity.DayName(DateTime.Today.AddDays(-n)))));
                    o.AppendLine("WHENYEAR: " + string.Join(" | ", new[] { 3, 20, 400 }.Select(n => Kit.FormatWhen(DateTime.Today.AddDays(-n).AddHours(9)))));
                    var e1 = Pages.Charts.Ends(DateTime.Today.AddDays(-3).AddHours(7), DateTime.Today.AddDays(-3).AddHours(19.5)); var e2 = Pages.Charts.Ends(DateTime.Today.AddDays(-3), DateTime.Today);
                    o.AppendLine($"ENDS: {e1.L} .. {e1.R} | {e2.L} .. {e2.R}");
                    // (no second-by-second view: the note goes under the first game card missing it, once; why depends on the date)
                    var sk = Pages.Performance.SecsNoteKey(new[] { ("a", new Dictionary<string, object> { ["perSec"] = new object[] { 60, 61 } }), ("b", new Dictionary<string, object>()), ("c", new Dictionary<string, object>()) });
                    o.AppendLine($"SECNOTE: {sk} | {Pages.Performance.SecsNote(new DateTime(2026, 10, 10))} | {Pages.Performance.SecsNote(new DateTime(2026, 10, 25))}");
                    o.AppendLine("STAMP: " + string.Join(" | ", new[] { 3, 400 }.Select(n => Kit.Stamp(DateTime.Today.AddDays(-n).AddHours(3)))) + " | " + Kit.Stamp(DateTime.Today.AddDays(-400), false));
                    {   // (Game check-up: a verdict per game - one made-up session of each kind on a 239 Hz screen, then this home's games)
                        Dictionary<string, object> S(double fps, double low, double frames, int st, double? busy, params double[] per)
                        {
                            var d = new Dictionary<string, object> { ["fps"] = fps, ["low1"] = low, ["frames"] = frames, ["stutters"] = st, ["perSec"] = per.Cast<object>().ToList() };
                            if (busy != null) d["gpuBusy"] = busy; return d;
                        }
                        string V(params Dictionary<string, object>[] rows) { var v = Pages.Performance.Verdict(rows.ToList(), 239); return v == null ? "none" : $"{v.Value.Kind}: {v.Value.Text}"; }
                        var flat = Enumerable.Repeat(60.0, 20).ToArray(); var wavy = Enumerable.Range(0, 20).Select(i => 150.0 + (i % 5) * 12).ToArray();
                        o.AppendLine("VERDICT: " + string.Join(" | ", V(S(236, 200, 14000, 2, 60, Enumerable.Repeat(236.0, 20).ToArray())), V(S(59.9, 48.6, 3593, 3, 13, flat)), V(S(59.9, 48.6, 3593, 3, 13)),
                            V(S(172, 120, 10000, 1, 55, wavy)), V(S(172, 120, 10000, 1, 97, wavy)), V(S(172, 120, 10000, 1, 80, wavy)),
                            V(S(190, 150, 11000, 0, 97, wavy), S(190, 150, 11000, 2, 97, wavy), S(172, 75, 7400, 21, 94, wavy)),
                            V(S(238, 199, 14289, 3, 40, wavy), S(59.9, 48.6, 3593, 3, 13), S(58.5, 50.6, 3504, 5, 27)), V(S(60, 51, 329, 0, 5)), V()));
                        // (and the line under it agrees: smooth at the screen's rate needs nothing raised, 70-89% busy is the processor's pace, 10/28)
                        string L(Dictionary<string, object> d) => Pages.Performance.Limit(d, ((List<object>)d["perSec"]).Select(Convert.ToDouble).ToList(), 239)?.Text ?? "none";
                        o.AppendLine("LIMITAGREE: " + string.Join(" | ", L(S(236, 200, 14000, 2, 97, Enumerable.Repeat(236.0, 20).ToArray())), L(S(59.9, 48.6, 3593, 3, 13, flat)), L(S(172, 120, 10000, 1, 80, wavy)), L(S(172, 120, 10000, 1, 97, wavy))));
                        // (under the latest session's verdict, which already says the limit and the busy %, only the advice is left)
                        string LS(Dictionary<string, object> d) => Pages.Performance.Limit(d, ((List<object>)d["perSec"]).Select(Convert.ToDouble).ToList(), 239, true)?.Text ?? "none";
                        o.AppendLine("LIMITSAID: " + string.Join(" | ", LS(S(59.9, 48.6, 3593, 3, 13, flat)), LS(S(172, 120, 10000, 1, 55, wavy)), LS(S(172, 120, 10000, 1, 97, wavy)), LS(S(172, 120, 10000, 1, 80, wavy)), LS(S(60, 51, 329, 0, 40, flat))));
                        // (a cap says where it probably comes from: the game's own limit, V-Sync at half rate; nothing for other kinds)
                        string CC(int hz, string gs, double fps) { var r = Enumerable.Repeat(fps, 20).ToArray(); return Pages.Performance.CapCause(Pages.Performance.Verdict(new List<Dictionary<string, object>> { S(fps, fps * 0.85, 5000, 0, 20, r) }, hz), hz, gs) ?? "none"; }
                        o.AppendLine("CAPCAUSE: " + string.Join(" | ", CC(239, "1", 59.9), CC(239, "0", 59.9), CC(240, "1", 120), CC(240, "", 120), CC(0, "1", 60), CC(239, "1", 236), CC(239, "1", 172.0 - 0.4)));
                        if (snap.Perf != null) foreach (var g in snap.Perf.GroupBy(r => Json.S(r, "game")))
                        { var v = Pages.Performance.Verdict(g.ToList(), Native.ScreenHz()); o.AppendLine($"VERDICT {Data.GameName(g.Key)}: {(v == null ? "none" : v.Value.Kind + ": " + v.Value.Text)}"); }
                    }
                    o.AppendLine("TOOK: " +string.Join(" | ", new[] { 48, 64, 95, 130, 600 }.Select(s => Kit.FormatLine($"Done in {s}s"))));
                }
                foreach (var l in w.ChatSelfTest()) o.AppendLine(l);
                foreach (var l in Pages.Performance.ChartSelfTest()) o.AppendLine(l);
                foreach (var l in new Tray.QuickPanel(null, null, null).Words()) o.AppendLine(l.StartsWith("A11Y") ? l : "QUICK: " + l);
                o.AppendLine("QUICKTEMP: " + (Tray.QuickPanel.CpuTempScript() == null ? "cpu-temp.ps1 missing - not started" : "cpu-temp.ps1 there"));
                // the RAM stick test, each stage (made-up logs - dashboard.ps1's same cases)
                string two = "2 stick(s), 32 GB in P0 CHANNEL A + P0 CHANNEL B", oA = "1 stick(s), 16 GB in P0 CHANNEL A", oB = "1 stick(s), 16 GB in P0 CHANNEL B";
                var bas = new[] { $"2026-10-05 09:54 | start | {two}", $"2026-10-10 11:30 | crash | {two}", $"2026-10-10 11:30 | start | {two}" };
                Func<int, string, int, string[]> st = (n, s, c) => Enumerable.Range(1, n).Select(i => $"2026-10-13 10:{i:d2} | start | {s}").Concat(Enumerable.Range(1, c).Select(i => $"2026-10-14 10:0{i} | crash | {s}")).ToArray();
                Func<string[][], string[]> cat = parts => parts.SelectMany(x => x).ToArray();
                Func<List<Line>, string> firsts = ls => string.Join(" ", ls.Where(x => x.Level != "dim").Select(x => x.Text.Split(':', '.')[0]));
                foreach (var (name, log, now) in new[] {
                    ("not started", bas, two), ("A running", cat(new[] { bas, st(3, oA, 0) }), oA), ("A clean", cat(new[] { bas, st(10, oA, 0) }), oA),
                    ("A crashed", cat(new[] { bas, st(2, oA, 1) }), oA), ("B running", cat(new[] { bas, st(10, oA, 0), st(4, oB, 0) }), oB),
                    ("A bad", cat(new[] { bas, st(2, oA, 1), st(10, oB, 0) }), oB), ("both bad", cat(new[] { bas, st(2, oA, 1), st(3, oB, 1) }), oB),
                    ("both clean", cat(new[] { bas, st(10, oA, 0), st(10, oB, 0) }), oB), ("back too soon", cat(new[] { bas, st(3, oA, 0) }), two) })
                    o.AppendLine($"RAMTEST {name}: {firsts(Data.RamTest(log, now, new string[0]))}");
                o.AppendLine($"RAMTEST A memory test errors: {firsts(Data.RamTest(cat(new[] { bas, st(1, oA, 0), new[] { $"2026-10-14 03:00 | stress | {oA} | 40 passes over 12 GB in 45 min at 4800 MT/s: 2 errors" } }), oA, new string[0]))}");
                o.AppendLine($"RAMTEST A off by the owner: {firsts(Data.RamTest(cat(new[] { bas, st(2, oA, 1) }), oA, new[] { "2026-10-14 10:01" }))}");
                // the help report (Settings > Tools > Copy a report for help), on one line
                if (Environment.GetEnvironmentVariable("PCKIT_REPORT_TEST") != null) o.AppendLine("REPORT: " + Actions.Report().Replace("\r", "").Replace("\n", " // "));
            });
            t.SetApartmentState(ApartmentState.STA); t.Start(); t.Join();
            var outp = Console.OpenStandardOutput(); var bytes = new UTF8Encoding(false).GetBytes(o.ToString()); outp.Write(bytes, 0, bytes.Length); outp.Flush();
            return 0;
        }
        // what a screen reader would announce without a name: a button, switch, link or field with no words of its own (an
        // icon only) and no AutomationProperties.Name - the --test check (the window's own parts and every page)
        internal static IEnumerable<string> Unnamed(object root)
        {
            var seen = new HashSet<object>(); var stack = new Stack<object>(); stack.Push(root);
            while (stack.Count > 0)
            {
                var d = stack.Pop(); if (d == null || !seen.Add(d)) continue;
                if (d is DependencyObject dep)
                {
                    if (d is ButtonBase || d is TextBox || d is System.Windows.Documents.Hyperlink)
                    {
                        var name = System.Windows.Automation.AutomationProperties.GetName(dep);
                        var words = d is ContentControl cc ? Words(cc.Content) : d is System.Windows.Documents.Hyperlink hl ? LinkText(hl) : "";
                        if (string.IsNullOrWhiteSpace(name) && string.IsNullOrWhiteSpace(Regex.Replace(words ?? "", @"[\uE000-\uF8FF\u2715]", "")) && !(d is TextBox tb && tb.IsReadOnly))
                            yield return $"{d.GetType().Name} {(dep as FrameworkElement)?.Name} {(dep as FrameworkElement)?.ToolTip as string}".Trim();
                    }
                    foreach (var ch in LogicalTreeHelper.GetChildren(dep)) stack.Push(ch);
                }
            }
        }
        // a link's words from its own runs - a TextRange over a Hyperlink that is a TextBlock's first inline reads ''
        // (10/28: PAGELINKS read ' > Status'; the link draws whole, only the read was wrong)
        static string LinkText(System.Windows.Documents.Span h) => string.Concat(h.Inlines.Select(i => i is System.Windows.Documents.Run r ? r.Text : i is System.Windows.Documents.Span s ? LinkText(s) : ""));
        static IEnumerable<string> GoLinks(object root)
        {
            var seen = new HashSet<object>(); var stack = new Stack<object>(); stack.Push(root);
            while (stack.Count > 0)
            {
                var d = stack.Pop(); if (!(d is DependencyObject dep) || !seen.Add(d)) continue;
                if (d is System.Windows.Documents.Hyperlink h && (h.Tag as string ?? "").StartsWith("go:")) yield return LinkText(h) + " > " + ((string)h.Tag).Substring(3);
                foreach (var ch in LogicalTreeHelper.GetChildren(dep)) stack.Push(ch);
            }
        }
        static string Words(object content)
        {
            if (content is string s) return s;
            if (content is TextBlock t) return t.Text;
            if (content is DependencyObject d) return string.Concat(LogicalTreeHelper.GetChildren(d).OfType<object>().Select(Words));
            return "";
        }
        static void Dump(UIElement el, StringBuilder o)
        {
            if (el is Border fb && (fb.Tag as string) == "filters") { o.AppendLine("FILTERS: " + string.Join(" | ", Find<RadioButton>(fb.Child).Select(r => r.Content + (r.IsChecked == true ? "*" : "")))); return; }
            if (el is TextBlock note && note.Visibility == Visibility.Visible)
            {
                o.AppendLine("NOTE: " + note.Text);
                // (a footer's page names that open their page - Ui.Linked)
                var links = note.Inlines.OfType<System.Windows.Documents.Hyperlink>().Where(h => (h.Tag as string ?? "").StartsWith("go:")).Select(h => LinkText(h) + " > " + ((string)h.Tag).Substring(3)).ToList();
                if (links.Count > 0) o.AppendLine("  LINK: " + string.Join(" | ", links));
                return;
            }
            if (el is UniformGrid ug) { foreach (UIElement c in ug.Children) if (c is Border b && b.Tag is CardInfo ci && ci.Tile != null) { o.AppendLine("  TILE: " + ci.Tile); if (ci.Go != null) o.AppendLine($"    GO: {ci.Go} ({b.ToolTip})"); } else Dump(c, o); return; }
            if (el is Border card && card.Tag is CardInfo info)
            {
                o.AppendLine("CARD: " + (string.IsNullOrEmpty(info.Title) ? "-" : info.Title));
                // a Status row: its words on one line, its details (behind a click) on the next
                var rowEls = Find<DockPanel>(card.Child).Where(x => x.Tag is Pages.RowInfo).ToList();
                if (rowEls.Count > 0)
                {
                    foreach (var re in rowEls)
                    {
                        var ri = ((Pages.RowInfo)re.Tag).Row;
                        o.AppendLine($"  {ri.Title} / {ri.State}{(string.IsNullOrEmpty(ri.Detail) ? "" : " / " + ri.Detail)}{(ri.Fix != null ? " [" + ri.Fix.Value.Label + "]" : "")}");
                        if (ri.More != null && ri.More.Count > 0) o.AppendLine("    MORE: " + string.Join(" | ", ri.More.Select(m => m.Action != null ? "[" + m.Text + "]" : (m.Label + "  " + m.Text).Trim())));
                    }
                    return;
                }
                var charts = All<StackPanel>(card.Child).Where(x => (x.Tag as string ?? "").StartsWith("CHART:")).ToList();
                if (charts.Count > 0)
                {
                    // (a card with charts: its label | value rows too - Heat and wear - then each chart)
                    foreach (var g in Find<Grid>(card.Child).Where(x => (x.Tag as string) == "rows"))
                        foreach (var rr in g.Children.OfType<TextBlock>().Where(x => (x.Tag as string) != "icon").GroupBy(x => Grid.GetRow(x))) o.AppendLine("  " + string.Join(": ", rr.Select(x => x.Text).Where(x => x != "")));
                    foreach (var tb in Texts(card.Child).SkipWhile((x, i) => i == 0 && x == info.Title)) o.AppendLine("  " + tb);   // (its lines of words - a game's card, 10/22)
                    foreach (var ch in charts) o.AppendLine("  " + ch.Tag);
                    return;
                }
                foreach (var g in Find<Grid>(card.Child).Where(x => (x.Tag as string) == "rows"))
                    foreach (var rr in g.Children.OfType<TextBlock>().Where(x => (x.Tag as string) != "icon").GroupBy(x => Grid.GetRow(x))) o.AppendLine("  " + string.Join(": ", rr.Select(x => x.Text).Where(x => x != "")));
                foreach (var tb in Texts(card.Child).SkipWhile((x, i) => i == 0 && x == info.Title)) o.AppendLine("  " + tb);
                // rows that open a page (Home's This week): which row goes where
                var gos = Find<Grid>(card.Child).Where(x => (x.Tag as string) == "rows").SelectMany(g => g.Children.OfType<Border>().Where(b => (b.Tag as string ?? "").StartsWith("go:"))
                    .Select(b => g.Children.OfType<TextBlock>().First(x => Grid.GetRow(x) == Grid.GetRow(b) && Grid.GetColumn(x) == 0).Text + " > " + ((string)b.Tag).Substring(3) + " (" + b.ToolTip + ")")).ToList();
                if (gos.Count > 0) o.AppendLine("  GO: " + string.Join(" | ", gos));
                // tables that share their label width with tables in other cards (Ui.Rows' align)
                var aligns = Find<Grid>(card.Child).Where(x => (x.Tag as string) == "rows").Select(g => g.ColumnDefinitions[0].SharedSizeGroup).Where(x => x != null).Distinct().ToList();
                if (aligns.Count > 0) o.AppendLine("  ALIGN: " + string.Join(" | ", aligns));
                // lines under a heading per day (What maintenance did, 10/26): each day and how many lines it has
                var days = All<TextBlock>(card.Child).Where(t => (t.Tag as string ?? "").StartsWith("day:")).Select(t => $"{t.Text} ({((string)t.Tag).Substring(4)})").ToList();
                if (days.Count > 0) o.AppendLine("  DAYS: " + string.Join(" | ", days));
                // a group of settings (Settings > General, 10/26): each setting on a card of its own - its title, icon, switch
                var sets = All<Border>(card.Child).Where(b => (b.Tag as string) == "setting").Select(b => b.Child as DockPanel).ToList();
                if (sets.Count > 0) o.AppendLine("  SETTINGS: " + string.Join(" | ", sets.Select(r => (r == null ? "?" : Texts(r).FirstOrDefault() + (r.Children.OfType<TextBlock>().Any(x => (x.Tag as string) == "icon") ? " +icon" : "") + (r.Children.OfType<CheckBox>().Any() ? " +switch" : "")))));
                // rows whose buttons share one column width (Storage's games, 10/27): the group and how many rows
                var bcols = All<Grid>(card.Child).Where(g => (g.Tag as string ?? "").StartsWith("btncol:")).GroupBy(g => ((string)g.Tag).Substring(7)).Select(x => $"{x.Key} ({x.Count()} rows)").ToList();
                if (bcols.Count > 0) o.AppendLine("  BTNCOL: " + string.Join(" | ", bcols));
                var btns = Find<Button>(card.Child).Select(b => b.ToolTip?.ToString()).Where(x => x != null).ToList();
                if (btns.Count > 0) o.AppendLine("  BUTTONS: " + string.Join(" | ", btns));
                return;
            }
        }
        // the words in an element, in order (icons and button labels left out)
        static IEnumerable<string> Texts(object el)
        {
            if (el is Button) yield break;
            if (el is TextBlock tb)
            {
                // (a line made of runs - a setting's one line with its "More" link - and the details behind it, collapsed: the
                // tests read them all)
                var tt = tb.Text != "" ? tb.Text : new System.Windows.Documents.TextRange(tb.ContentStart, tb.ContentEnd).Text;
                if ((tb.Tag as string) != "icon" && (tb.Visibility == Visibility.Visible || (tb.Tag as string) == "more") && tt != "") yield return tt;
                yield break;
            }
            if (el is Grid gr && (gr.Tag as string) == "rows") yield break;
            if (el is StackPanel ch && (ch.Tag as string ?? "").StartsWith("CHART:")) yield break;   // (a chart: said by its tag)
            if (el is Panel p) { foreach (var c in p.Children) foreach (var s in Texts(c)) yield return s; yield break; }
            if (el is Decorator d) foreach (var s in Texts(d.Child)) yield return s;
        }
        static IEnumerable<T> All<T>(object el) where T : class   // (every one, also inside another)
        {
            if (el is T x) yield return x;
            if (el is Panel p) foreach (var c in p.Children) foreach (var y in All<T>(c)) yield return y;
            if (el is Decorator d) foreach (var y in All<T>(d.Child)) yield return y;
        }
        static IEnumerable<T> Find<T>(object el) where T : class
        {
            if (el is T x) { yield return x; yield break; }
            if (el is Panel p) foreach (var c in p.Children) foreach (var y in Find<T>(c)) yield return y;
            if (el is Decorator d) foreach (var y in Find<T>(d.Child)) yield return y;
            if (el is ContentControl cc && !(el is Button)) foreach (var y in Find<T>(cc.Content)) yield return y;
        }
    }
}
