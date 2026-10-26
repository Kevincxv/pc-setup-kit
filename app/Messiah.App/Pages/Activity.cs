using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Shapes;

namespace Messiah.Pages
{
    // Activity (dashboard.ps1's Build-Page 'Activity/...'): what the maintenance did and found, every crash, the health over
    // time, the alerts
    static class Activity
    {
        static SolidColorBrush B(string k) => Theme.B[k];
        internal static TextBlock Foot(string t) => Ui.Text(t, B("Sub"), 12, null, "4,2,0,0");

        // --- Checks: the last check, the to-do list, Claude's own runs, the schedule, what maintenance did
        public static List<UIElement> Checks(Snapshot s)
        {
            var o = new List<UIElement>();
            var last = s.Sec("Last background check"); var needs = s.Sec("Needs you"); var hidden = s.Sec("Hidden Claude"); var sched = s.Sec("Scheduled checks");
            o.Add(Ui.Card("Last background check", "E9D9", last.Lines.Cast<object>(), new[] { Ui.Btn("E768", "Run maintenance now", Actions.RunMaint, accent: true), Ui.Btn("E8A5", "Full report", Actions.FullReport) }));
            // the to-do list lives on Home (one place for it - 10/22 audit: the same card twice); here only how many, and the way there
            var nTodo = needs.Lines.Count(l => l.Level == "warn");
            if (nTodo > 0) o.Add(Ui.Card("Needs you", "E7BA", new object[] { new Line($"{nTodo} thing{Kit.S(nTodo)} need{(nTodo == 1 ? "s" : "")} you - listed on Home.", "warn") }, new[] { Ui.Btn("E80F", "Open Home", () => Shell.ShowPage("Home")), Ui.Btn("E8A5", "Open the to-do list", Actions.Todo) }, calm: true));
            if (s.Ai && hidden != null)
            {
                var hl = hidden.Lines.Select(l => (object)new Line(Regex.Replace(Regex.Replace(Regex.Replace(l.Text, @"\(improve\)", "(looked for improvements)"), @"\(maintain\)", "(maintenance)"), "^Self-improvement:", "Improving Messiah:"), l.Level)).ToList();
                hl.Add(new Line("About 2 minutes after each login, Claude handles anything in the report that needs judgment, then looks for ways to make Messiah better (at most once a day).", "dim"));
                o.Add(Ui.Card("Claude's own checks", "E90F", hl, new[] { Ui.Btn("E890", "Watch live", Actions.WatchLive), Ui.Btn("E8F1", "Self-improvement journal", Actions.Journal), Ui.Btn("E8B7", "Run logs", Actions.Logs) }));
            }
            var pairs = sched.Lines.Select(l => { var m = Regex.Match(l.Text, @"^([^:]+):\s+(.*)$"); return m.Success ? (m.Groups[1].Value, m.Groups[2].Value, l.Level) : ("", l.Text, l.Level); });
            o.Add(Ui.Card("Scheduled checks", "E787", new object[] { Ui.Rows(pairs), new Line("Everything here runs by itself. Checks wait while a game is running, and anything that needs a restart finishes the next time you turn the PC off.", "dim") }));
            // (10/25, the owner: "a long list of text" - app updates on one day make one line, and the newest 8 show; the rest
            // are a click away)
            var rows = Grouped(s.Timeline).Select(t => (t.When, t.Text, "info")).ToList();
            if (rows.Count == 0) rows.Add(("", "Nothing changed yet - the checks found everything in order.", "dim"));
            var did = new List<object> { Ui.Rows(rows.Take(8)) };
            if (rows.Count > 8)
            {
                var rest = Ui.Rows(rows.Skip(8)); rest.Visibility = Visibility.Collapsed; did.Add(rest);
                Button more = null; more = Ui.Btn("E70D", $"Show all {rows.Count}", () => { var open = rest.Visibility != Visibility.Visible; rest.Visibility = open ? Visibility.Visible : Visibility.Collapsed; ((TextBlock)((StackPanel)more.Content).Children[1]).Text = open ? "Show fewer" : $"Show all {rows.Count}"; }, small: true);
                more.HorizontalAlignment = HorizontalAlignment.Left; more.Margin = Ui.Th("0,8,0,0"); did.Add(more);
            }
            o.Add(Ui.Card("What maintenance did", "E90F", did));
            return o;
        }

        // the same day's "Updated app: X" lines as one: "Updated 5 apps: 7zip, AutoHotkey, ..." (winget ids made readable)
        internal static List<(string When, string Text)> Grouped(List<(string When, string Text)> tl)
        {
            var o = new List<(string When, string Text)>();
            string Name(string id) { var p = id.Trim().Split('.'); return string.Join(" ", p.Where((x, i) => i == 0 || !x.Equals(p[0], StringComparison.OrdinalIgnoreCase))); }
            const string U = "Updated app: ";
            for (int i = 0; i < tl.Count; i++)
            {
                int j = i; while (tl[i].Text.StartsWith(U) && j + 1 < tl.Count && tl[j + 1].When == tl[i].When && tl[j + 1].Text.StartsWith(U)) j++;   // (next to each other, the same check)
                if (j == i) { o.Add(tl[i]); continue; }
                var names = tl.Skip(i).Take(j - i + 1).Select(x => Name(x.Text.Substring(U.Length))).Distinct().ToList();
                o.Add((tl[i].When, $"Updated {names.Count} apps: {string.Join(", ", names)}")); i = j;
            }
            return o;
        }

        // --- Stability: every blue screen and power-off, the owner's answers, and what changed - the crash hunt at one glance
        // the memory test (ram-check.ps1): the nightly test's and the deep test's results, and the deep test's button
        static UIElement MemoryTest(Snapshot s)
        {
            var armed = Kit.Date(Json.Get(s.RamState, "bootArmed"));
            var lines = new List<object>();
            if (armed != null) lines.Add(new Line("The deep test is set for the next start-up: restart the PC yourself when you can leave it for a few hours (best at night). Windows loads by itself after it, and the result shows here.", "info"));
            var rows = s.RamChecks.Take(6).Select(r => (Kit.FormatWhen(r.At, dateOnly: true), (r.Kind == "boottest" ? "Deep test at start-up - " : "Nightly test - ") + r.Result + (r.Setup.StartsWith("1 stick") ? $" ({r.Setup.Replace("1 stick(s), ", "one stick, ")})" : ""), r.Bad ? "warn" : "ok")).ToList();
            if (rows.Count > 0) lines.Add(Ui.Rows(rows));
            else lines.Add(new Line("No results yet. The nightly test runs by itself once the PC has been left alone for 30 minutes (no game): most of the free memory is filled with patterns and read back, again and again - it stops the moment you touch the mouse or keyboard. Every night while blue screens keep coming, else once a month.", "dim"));
            if (s.RamChecks.Any(r => r.Bad)) lines.Add(new Line("Errors mean faulty memory - test one stick at a time to find which (the RAM stick test).", "warn"));
            var btn = armed != null ? Ui.Btn("E711", "Cancel the deep test", () => Actions.RamBoot(false)) : Ui.Btn("E950", "Deep test at the next start-up", () => Actions.RamBoot(true));
            return Ui.Card("Memory test", "E950", lines.ToArray(), new[] { btn });
        }

        public static List<UIElement> Stability(Snapshot s, double width)
        {
            var o = new List<UIElement>();
            var evs = s.Power; var chs = s.Changes;
            if (evs.Count == 0 && chs.Count == 0) { o.Add(Ui.Card("Stability", "E9D9", new object[] { new Line("Nothing recorded yet - the record is made at the next check.", "dim") })); o.Add(MemoryTest(s)); return o; }
            bool IsCrash(Data.PowerEvent e) => e.Kind == "bsod" || e.Answer != "me";   // (a power-off the owner made isn't one)
            var lastC = evs.Where(IsCrash).OrderBy(e => e.At).LastOrDefault();
            var d90 = DateTime.Now.AddDays(-90);
            int Off(Func<Data.PowerEvent, bool> f) => evs.Count(e => e.Kind == "off" && e.At > d90 && f(e));
            var tiles = Ui.Pairs(new UniformGrid { Columns = 3, Margin = Ui.Th("0,0,-12,2") });
            foreach (var (label, big, sub) in new[] {
                ("Days since the last crash", lastC != null ? Math.Round((DateTime.Now - lastC.At).TotalDays).ToString() : "-", lastC != null ? $"{(lastC.Kind == "bsod" ? "Blue screen " + lastC.Code : lastC.Answer == "froze" ? "Went off by itself" : "Went off - not answered yet")}, {Kit.FormatWhen(lastC.At)}" : "None recorded"),
                ("Blue screens, 90 days", evs.Count(e => e.Kind == "bsod" && e.At > d90).ToString(), "Each with a crash dump"),
                ("Power-offs, 90 days", Off(e => true).ToString(), $"{Off(e => e.Answer == "me")} by you, {Off(e => e.Answer == "froze")} froze" + (Off(e => e.Answer == "" && e.At > DateTime.Now.AddDays(-30)) is int na && na > 0 ? $", {na} to answer on Home" : "")) })
            {
                var tsp = new StackPanel();
                tsp.Children.Add(Ui.Text(label, B("Sub"), 12, null, "0"));
                var bt = Ui.Text(big, B("Text"), 28, FontWeights.SemiBold, "0,2,0,0"); bt.FontFamily = Theme.Display; tsp.Children.Add(bt);
                tsp.Children.Add(Ui.Text(sub, B("Sub"), 12, null, "0,2,0,0"));
                var tc = Ui.Card(null, null, new object[] { tsp }); tc.Margin = Ui.Th("0,0,12,14"); ((CardInfo)tc.Tag).Tile = $"{label}: {big} / {sub}"; tiles.Children.Add(tc);
            }
            o.Add(tiles);
            o.Add(MemoryTest(s));
            // the timeline: three lanes - blue screens, power-offs, changes - over the last 120 days. Each kind has its own
            // shape as well as its color (never color alone), a legend, and hover details on every mark.
            var t1 = DateTime.Now; var t0 = t1.AddDays(-120);
            double W = width > 600 ? Math.Min(1400, width - 64) : 640, L = 96, H = 128;   // (W: the card's width; narrower windows shrink it)
            var lane = new Dictionary<string, double> { ["bsod"] = 26, ["off"] = 62, ["change"] = 98 };
            double ToX(DateTime d) => L + (d.Ticks - t0.Ticks) / (double)(t1.Ticks - t0.Ticks) * (W - L - 10);
            var cv = new Canvas { Width = W, Height = H + 18 };
            foreach (var (name, key) in new[] { ("Blue screens", "bsod"), ("Power-offs", "off"), ("Changes", "change") })
            {
                var y = lane[key];
                cv.Children.Add(new Line_ { X1 = L, X2 = W - 4, Y1 = y, Y2 = y, Stroke = B("Border"), StrokeThickness = 1 }.Make());
                var lt = Ui.Text(name, B("Sub"), 12, null, "0"); Canvas.SetLeft(lt, 0); Canvas.SetTop(lt, y - 9); cv.Children.Add(lt);
            }
            for (var m = new DateTime(t0.Year, t0.Month, 1).AddMonths(1); m < t1; m = m.AddMonths(1))   // month ticks, recessive
            {
                var mx = ToX(m);
                cv.Children.Add(new Line_ { X1 = mx, X2 = mx, Y1 = 10, Y2 = H - 12, Stroke = B("Border"), StrokeThickness = 1, Dash = true }.Make());
                var mt = Ui.Text(m.ToString("MMM"), B("Sub"), 11, null, "0"); Canvas.SetLeft(mt, mx - 10); Canvas.SetTop(mt, H + 1); cv.Children.Add(mt);
            }
            var bg = (SolidColorBrush)new BrushConverter().ConvertFromString(Theme.C["Bg"]);
            void Mark(Shape shape, double x, double y, string tip)
            {
                shape.ToolTip = tip; shape.Cursor = System.Windows.Input.Cursors.Hand;
                Canvas.SetLeft(shape, x - shape.Width / 2); Canvas.SetTop(shape, y - shape.Height / 2); cv.Children.Add(shape);
                var hit = new Rectangle { Width = 18, Height = 22, Fill = Brushes.Transparent, ToolTip = tip, Cursor = System.Windows.Input.Cursors.Hand };   // (a target bigger than the mark)
                Canvas.SetLeft(hit, x - 9); Canvas.SetTop(hit, y - 11); cv.Children.Add(hit);
            }
            var ans = new Dictionary<string, string> { ["me"] = "you turned it off", ["froze"] = "you said it froze or went off by itself", ["unsure"] = "you weren't sure", [""] = "not answered yet" };
            string Ans(string a) => ans.TryGetValue(a ?? "", out var t) ? t : "not answered yet";
            foreach (var e in evs.Where(e => e.At > t0))
            {
                var x = ToX(e.At); var when = e.At.ToString("ddd MMM d, h:mm tt");
                if (e.Kind == "bsod") Mark(new Ellipse { Width = 12, Height = 12, Fill = B("Warn"), Stroke = bg, StrokeThickness = 2 }, x, lane["bsod"], $"{when}: blue screen {e.Code}");
                else if (e.Answer == "me") Mark(new Ellipse { Width = 9, Height = 9, Fill = B("Sub"), Stroke = bg, StrokeThickness = 2 }, x, lane["off"], $"{when}: went off - you turned it off");
                else Mark(new Ellipse { Width = 12, Height = 12, Fill = bg, Stroke = B("Warn"), StrokeThickness = 2 }, x, lane["off"], $"{when}: went off without a blue screen - {Ans(e.Answer)}");
            }
            foreach (var c in chs.Where(c => c.At > t0))
                Mark(new Rectangle { Width = 9, Height = 9, Fill = B("Chart"), Stroke = bg, StrokeThickness = 1.5, RenderTransformOrigin = new Point(0.5, 0.5), RenderTransform = new RotateTransform(45) }, ToX(c.At), lane["change"], $"{c.At:ddd MMM d}{(c.Approx ? " (about)" : "")}: {c.What} {c.From} → {c.To}");
            var vb = new Viewbox { Stretch = Stretch.Uniform, StretchDirection = StretchDirection.DownOnly, HorizontalAlignment = HorizontalAlignment.Left, Margin = Ui.Th("0,6,0,0"), Child = cv };
            // legend: shape + words for every kind
            var lg = new WrapPanel { Margin = Ui.Th("0,10,0,0") };
            foreach (var (shape, words) in new (Shape, string)[] {
                (new Ellipse { Width = 10, Height = 10, Fill = B("Warn") }, "Blue screen"),
                (new Ellipse { Width = 10, Height = 10, Stroke = B("Warn"), StrokeThickness = 2 }, "Went off by itself (or not answered)"),
                (new Ellipse { Width = 8, Height = 8, Fill = B("Sub") }, "You turned it off"),
                (new Rectangle { Width = 8, Height = 8, Fill = B("Chart"), RenderTransformOrigin = new Point(0.5, 0.5), RenderTransform = new RotateTransform(45) }, "A change (driver, BIOS, RAM)") })
            {
                shape.VerticalAlignment = VerticalAlignment.Center; shape.Margin = Ui.Th("0,0,6,0");
                var lsp = new StackPanel { Orientation = Orientation.Horizontal, Margin = Ui.Th("0,0,18,4") }; lsp.Children.Add(shape); lsp.Children.Add(Ui.Text(words, B("Sub"), 12, null, "0"));
                lg.Children.Add(lsp);
            }
            var tsp2 = new StackPanel { Tag = $"CHART: Stability timeline | {evs.Count(e => e.At > t0)} event(s), {chs.Count(c => c.At > t0)} change(s)" }; tsp2.Children.Add(vb); tsp2.Children.Add(lg);
            o.Add(Ui.Wide(Ui.Card("Last 120 days", "E9D9", new object[] { tsp2 })));
            // the same, as a list (the table view: every event in words, newest first)
            var rows = evs.Select(e => (e.At, e.Kind == "bsod" ? "Blue screen " + e.Code : "Went off without a blue screen - " + Ans(e.Answer), IsCrash(e) ? "info" : "dim"))
                .Concat(chs.Select(c => (c.At, $"{c.What}: {c.From} → {c.To}{(c.Approx ? " (date approximate)" : "")}", "dim")))
                .OrderByDescending(r => r.Item1).Take(40).Select(r => (At: r.Item1, Label: Kit.FormatWhen(r.Item1), Text: r.Item2, Level: r.Item3)).ToList();
            // (10/25, "a long list of text": the newest 10 of the chart's 120 days; the rest - older ones too - a click away)
            var recent = rows.Where(r => r.At > t0).Take(10).ToList(); var rest = rows.Skip(recent.Count).ToList();
            var wl = new List<object> { Ui.Rows(recent.Count > 0 ? recent.Select(r => (r.Label, r.Text, r.Level)) : new[] { ("", "Nothing in the last 120 days.", "ok") }) };
            if (rest.Count > 0)
            {
                var more = Ui.Rows(rest.Select(r => (r.Label, r.Text, r.Level))); more.Visibility = Visibility.Collapsed; wl.Add(more);
                Button mb = null; mb = Ui.Btn("E70D", $"Show {rest.Count} more", () => { var open = more.Visibility != Visibility.Visible; more.Visibility = open ? Visibility.Visible : Visibility.Collapsed; ((TextBlock)((StackPanel)mb.Content).Children[1]).Text = open ? "Show fewer" : $"Show {rest.Count} more"; }, small: true);
                mb.HorizontalAlignment = HorizontalAlignment.Left; mb.Margin = Ui.Th("0,8,0,0"); wl.Add(mb);
            }
            o.Add(Ui.Card("What happened", "E81C", wl));
            o.Add(Foot("From Windows' own log (back to when it starts) - recorded at every login. Hover over a mark for details."));
            return o;
        }

        // --- Trends: health over time - one measure per chart, each with its own scale (never two on one axis); the current
        // value as the big number; the usual level as a faint dashed line; every point has a tooltip
        public static List<UIElement> Trends(Snapshot s)
        {
            var o = new List<UIElement>();
            IEnumerable<(DateTime D, double V)> Pt(string field, bool perBoot = false)
            {
                var rows = s.Health.Where(r => Json.N(r, field) != null);
                if (perBoot) return rows.Where(r => Kit.Date(Json.Get(r, "bootAt")) != null).GroupBy(r => Json.S(r, "bootAt")).Select(g => g.Last()).Select(r => (Kit.Date(Json.Get(r, "bootAt")).Value, Json.N(r, field).Value));
                return rows.Select(r => (Kit.Date(Json.Get(r, "date")).Value, Json.N(r, field).Value));
            }
            IEnumerable<(DateTime D, double V)> Gp(IEnumerable<Dictionary<string, object>> rows, string field) =>
                (rows ?? Enumerable.Empty<Dictionary<string, object>>()).Where(r => Json.N(r, field) != null).Select(r => (Kit.Date(Json.Get(r, "date")).Value, Json.N(r, field).Value));
            // the PC's own vitals over time - the games are on Games > Performance (10/25: their charts were in both places)
            var grid = Ui.Pairs(new UniformGrid { Columns = 2, Margin = Ui.Th("0,0,-14,0") });
            var charts = new List<Border> { Chart("Start-up time", " s", Pt("boot", true), 1, 10), Chart("Free space on C:", " GB", Pt("freeGB"), 0, 20),
                Chart("Graphics card at idle", " °C", Pt("gpuIdle"), 0, 10), Chart("SSD temperature", " °C", Pt("ssdTemp"), 0, 10) };
            if (Pt("cpuIdle").Any()) charts.Add(Chart("Processor at idle", " °C", Pt("cpuIdle"), 0, 10));
            charts.Add(Chart("Internet ping at idle", " ms", Gp(s.Net, "ping"), 0, 10));
            foreach (var ch in charts) { ch.Margin = Ui.Th("0,0,14,14"); grid.Children.Add(ch); }
            o.Add(grid);
            o.Add(Foot("Recorded at every check (at each login and once a day). Idle temperatures are taken only while the PC is idle, so a game never skews them. Your games: Games > Performance."));
            return o;
        }
        static double? Median(List<double> v) { if (v.Count == 0) return null; var s = v.OrderBy(x => x).ToList(); int m = s.Count / 2; return s.Count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2; }
        // (the interactive chart, 10/22: Charts.Chart - hover, change marks, 7 days / 30 days / all, a click)
        internal static Border Chart(string title, string unit, IEnumerable<(DateTime D, double V)> data, int decimals, double minSpan) =>
            Charts.Chart(title, unit, data.Select(p => new ChartPt { D = p.D, V = p.V }), decimals, minSpan);

        // --- Alerts: what Messiah had to say - recent ones, then earlier and resolved ones
        public static List<UIElement> Alerts(Snapshot s)
        {
            var o = new List<UIElement>();
            var notes = s.Notes.OrderByDescending(n => n.When).Take(80).ToList();
            // a "Needs you" alert whose item is no longer on the to-do list was resolved, and anything over a week old is
            // earlier news: both move to a quieter card under the recent ones
            var open = s.Sec("Needs you").Lines.Where(l => l.Level == "warn").Select(l => Regex.Replace(l.Text, "^- ", "").Trim()).ToList();
            bool? IsOpen(string t)
            {
                var m = Regex.Match(t, @"^Needs you[^:]*:\s*(.+?)(\s*/\s*\+ \d+ more)?$"); if (!m.Success) return null;
                var head = Regex.Replace(m.Groups[1].Value.Trim(), @"\s*\.\.\.$", ""); var k = head.Substring(0, Math.Min(40, head.Length));
                return open.Any(x => x.StartsWith(k));
            }
            var recent = new List<(string, string, string)>(); var earlier = new List<(string, string, string)>();
            foreach (var n in notes)
            {
                var when = n.When.ToString("ddd MMM d, h:mm tt"); var op = IsOpen(n.Text);
                if (op == false) earlier.Add((when, n.Text + "  (resolved)", "dim"));
                else if (n.When < DateTime.Now.AddDays(-7)) earlier.Add((when, n.Text, "dim"));
                else recent.Add((when, n.Text, "info"));
            }
            var rows = recent.Count > 0 ? recent : new List<(string, string, string)> { ("", notes.Count > 0 ? "Nothing new this week." : "No alerts yet.", "dim") };
            o.Add(Ui.Card("Alerts", "EA8F", new object[] { Ui.Rows(rows) }, notes.Count > 0 ? new[] { Ui.Btn("E74D", "Clear", () => { try { System.IO.File.WriteAllText(Kit.P("notifications.log"), ""); } catch { } Shell.Refresh(true); }) } : null));
            if (earlier.Count > 0) o.Add(Ui.Card("Earlier and resolved", "E81C", new object[] { Ui.Rows(earlier.Take(30)) }));
            o.Add(Foot("Messiah never pops up by itself: what it has to say is kept here. Settings > General > Show alerts in the corner brings the small corner notes back."));
            return o;
        }
    }

    // a line for the charts (Line clashes with the card lines' class name)
    class Line_
    {
        public double X1, X2, Y1, Y2, StrokeThickness = 1, DashA = 2, DashB = 3; public Brush Stroke; public bool Dash;
        public System.Windows.Shapes.Line Make()
        {
            var l = new System.Windows.Shapes.Line { X1 = X1, X2 = X2, Y1 = Y1, Y2 = Y2, Stroke = Stroke, StrokeThickness = StrokeThickness };
            if (Dash) l.StrokeDashArray = new DoubleCollection(new[] { DashA, DashB });
            return l;
        }
    }
}
