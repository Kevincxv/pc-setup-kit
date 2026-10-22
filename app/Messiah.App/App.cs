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
                else if (a == "after" && i + 1 < args.Length) int.TryParse(args[++i], out after);   // (Restart into an update: the copy before)
            }
            if (trayTest != null) return Tray.TrayLogic.Test(trayTest, fs);
            AppDomain.CurrentDomain.UnhandledException += (s, e) => Log("crash: " + e.ExceptionObject);
            if (test) return RunTest(page);
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
                    // open on screen: never swapped under the owner - offered, and done when they click (10/21: until then an
                    // open window kept the old version with nothing said)
                    if (w.Visibility == Visibility.Visible)
                    {
                        if (!w.Offering) w.Offer("A new version of Messiah is ready.", "Restart", () =>
                        {
                            try { File.WriteAllText(Kit.P(Names.RequestFile), "page=" + AppLast.Page); } catch { }
                            var keep = RestartArgs(args, Process.GetCurrentProcess().Id);
                            try { Process.Start(new ProcessStartInfo(self, string.Join(" ", keep)) { UseShellExecute = false }); } catch (Exception ex) { Log("update: " + ex.Message); return; }
                            w.Quit = true; w.Close();
                        });
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
                if (timing) w.ContentRendered += (s, e) => { try { File.AppendAllText(Path.Combine(Path.GetTempPath(), "messiah-app-timing.txt"), $"{DateTime.Now:s} on screen after {sw.ElapsedMilliseconds} ms\r\n"); } catch { } };
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

        // what went wrong, for /self-improve (.claude\app-errors.log, kept short)
        public static void Log(string what)
        {
            try { var f = Kit.P("app-errors.log"); if (File.Exists(f) && new FileInfo(f).Length > 200000) File.Delete(f); File.AppendAllText(f, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss}  {what}\r\n"); } catch { }
        }
        // --test: every page built once and printed as text - what the tests read (the PowerShell app's -Test format)
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
                var sw = Stopwatch.StartNew(); var snap = Snapshot.Load(); o.AppendLine($"DATA: read in {sw.ElapsedMilliseconds} ms");
                foreach (var key in new[] { "Welcome", "Home", "Status", "Activity/Checks", "Activity/Stability", "Activity/Trends", "Activity/Performance", "Activity/Alerts", "Settings/General", "Settings/Windows", "Settings/Tools" })
                {
                    sw.Restart();
                    List<UIElement> els; string err = null;
                    try { els = w.BuildPage(key, snap); } catch (Exception e) { els = new List<UIElement>(); err = e.ToString(); }
                    o.AppendLine($"PAGE: {key}  (built in {sw.ElapsedMilliseconds} ms)"); if (err != null) o.AppendLine("PAGE ERROR: " + err);
                    foreach (var el in els) Dump(el, o);
                    foreach (var el in els) foreach (var miss in Unnamed(el)) o.AppendLine($"A11Y: {key}: {miss}");
                }
                foreach (var miss in Unnamed(w.Content)) o.AppendLine($"A11Y: window: {miss}");   // (the window's own parts: the tabs, the chat)
                foreach (var l in w.ChatSelfTest()) o.AppendLine(l);
                foreach (var l in Pages.Performance.ChartSelfTest()) o.AppendLine(l);
                foreach (var l in new Tray.QuickPanel(null, null, null).Words()) o.AppendLine(l.StartsWith("A11Y") ? l : "QUICK: " + l);
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
                        var words = d is ContentControl cc ? Words(cc.Content) : d is System.Windows.Documents.Hyperlink hl ? new System.Windows.Documents.TextRange(hl.ContentStart, hl.ContentEnd).Text : "";
                        if (string.IsNullOrWhiteSpace(name) && string.IsNullOrWhiteSpace(Regex.Replace(words ?? "", @"[\uE000-\uF8FF\u2715]", "")) && !(d is TextBox tb && tb.IsReadOnly))
                            yield return $"{d.GetType().Name} {(dep as FrameworkElement)?.Name} {(dep as FrameworkElement)?.ToolTip as string}".Trim();
                    }
                    foreach (var ch in LogicalTreeHelper.GetChildren(dep)) stack.Push(ch);
                }
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
            if (el is TextBlock note && note.Visibility == Visibility.Visible) { o.AppendLine("NOTE: " + note.Text); return; }
            if (el is UniformGrid ug) { foreach (UIElement c in ug.Children) if (c is Border b && b.Tag is CardInfo ci && ci.Tile != null) o.AppendLine("  TILE: " + ci.Tile); else Dump(c, o); return; }
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
                        foreach (var rr in g.Children.OfType<TextBlock>().GroupBy(x => Grid.GetRow(x))) o.AppendLine("  " + string.Join(": ", rr.Select(x => x.Text).Where(x => x != "")));
                    foreach (var tb in Texts(card.Child).SkipWhile((x, i) => i == 0 && x == info.Title)) o.AppendLine("  " + tb);   // (its lines of words - a game's card, 10/22)
                    foreach (var ch in charts) o.AppendLine("  " + ch.Tag);
                    return;
                }
                foreach (var g in Find<Grid>(card.Child).Where(x => (x.Tag as string) == "rows"))
                    foreach (var rr in g.Children.OfType<TextBlock>().GroupBy(x => Grid.GetRow(x))) o.AppendLine("  " + string.Join(": ", rr.Select(x => x.Text).Where(x => x != "")));
                foreach (var tb in Texts(card.Child).SkipWhile((x, i) => i == 0 && x == info.Title)) o.AppendLine("  " + tb);
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
