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
        internal static TextBlock Foot(string t) => Ui.Linked(Ui.Text(t, B("Sub"), 12, null, "4,2,0,0"));

        // --- Checks: the last check, the to-do list, Claude's own runs, the schedule, what maintenance did
        // --- Claude usage (10/26, the owner: "monitor the tasks or things that take up the most tokens") - claude-usage.ps1's
        // claude-usage.json: the plan's session and week now, this week's use by kind, the heaviest conversations and steps, tips
        // (the three tables share one label width - align "usage", 10/27 - so their words start at the same place)
        internal static UIElement Usage(Dictionary<string, object> u)
        {
            if (u == null) return null;
            var lines = new List<object>(); var cur = Json.Get(u, "current");
            if (cur != null) lines.Add(new Line($"This session: {Json.S(cur, "session")}% used (resets {Json.S(cur, "sessionResets")})" + (Json.S(cur, "week") != "" ? $" · this week: {Json.S(cur, "week")}% (resets {Json.S(cur, "weekResets")})" : ""), (Json.N(cur, "session") ?? 0) >= 90 ? "warn" : "info"));
            var kinds = Json.L(u, "kinds").ToList();
            if (kinds.Count > 0) { lines.Add(Ui.Text("This week on this PC, by what it was for", Theme.B["Sub"], 12.5, null, "0,10,0,2")); lines.Add(Ui.Rows(kinds.Select(k => (Json.S(k, "kind"), $"{Json.S(k, "share")}%", "info")), align: "usage")); }
            var top = Json.L(u, "sessions").Take(3).ToList();
            if (top.Count > 0) { lines.Add(Ui.Text("The heaviest conversations", Theme.B["Sub"], 12.5, null, "0,10,0,2")); lines.Add(Ui.Rows(top.Select(t => ($"{Json.S(t, "share")}%", $"{Json.S(t, "title")} - {Lower1(Json.S(t, "kind"))},{Json.S(t, "replies")} replies", "info")), align: "usage")); }
            var steps = Json.L(u, "steps").Take(3).ToList();
            if (steps.Count > 0) { lines.Add(Ui.Text("The heaviest steps (what stays in the conversation is read again with every reply)", Theme.B["Sub"], 12.5, null, "0,10,0,2")); lines.Add(Ui.Rows(steps.Select(t => ($"~{Math.Round((Json.N(t, "tokens") ?? 0) / 1000)}k tokens", $"{Json.S(t, "tool")} {Json.S(t, "what")} - in '{Json.S(t, "session")}'", "info")), align: "usage")); }
            foreach (var t in Json.L(u, "tips")) lines.Add(new Line(t?.ToString(), "warn"));
            lines.Add(new Line("Counted from Claude Code's own records on this PC - measuring it uses no tokens. Shares weigh tokens the way the plan does (a reply's output more than what it re-reads).", "dim"));
            return Ui.Card("Claude usage", "E9D2", lines);
        }
        // a kind mid-sentence: only its first letter lower ("Improving Messiah" -> "improving Messiah", not "messiah")
        static string Lower1(string s) => s.Length > 0 ? char.ToLower(s[0]) + s.Substring(1) : s;

        // a scheduled check's 'when' the way Home's Next tile says it (10/26: "Oct 27, 2026" here, "Tomorrow" there): a date
        // within the next ~11 months as "Tomorrow" / "Nov 2", a later one keeps its year; "due now" before any check ran is
        // "After the first check" (a new install - every check is due), after that "Runs at the next check"
        internal static string SchedWhen(string v, bool checkedOnce)
        {
            var m = Regex.Match(v ?? "", @"^(due now|\w+ \d+, \d{4})(.*)$"); if (!m.Success) return v != null && v != "" ? char.ToUpper(v[0]) + v.Substring(1) : v;   // ("At the next login")
            string w = m.Groups[1].Value, rest = m.Groups[2].Value.Trim();
            if (w == "due now") w = checkedOnce ? "Runs at the next check" : "After the first check";
            else if (DateTime.TryParseExact(w, "MMM d, yyyy", null, System.Globalization.DateTimeStyles.None, out var d) && d < DateTime.Today.AddDays(330))
            { var f = Kit.FormatWhen(d, dateOnly: true); w = char.ToUpper(f[0]) + f.Substring(1); }
            return rest != "" ? w + "  " + rest : w;
        }

        // Scheduled checks soonest first (10/28: they came in Data's fixed order - 'Self-check Nov 1' sat under 'Full tune-up
        // Sep 22' of next year); due now first, then 'at the next login', then by date; a line without a date stays at the end
        internal static List<Line> SchedOrder(IEnumerable<Line> lines) => (lines ?? new List<Line>()).Select((l, i) =>
        {
            var m = Regex.Match(l.Text, @"^[^:]+:\s+(due now|at the next login|\w+ \d+, \d{4})");
            var at = !m.Success ? DateTime.MaxValue : m.Groups[1].Value == "due now" ? DateTime.MinValue : m.Groups[1].Value == "at the next login" ? DateTime.MinValue.AddDays(1)
                : DateTime.TryParseExact(m.Groups[1].Value, "MMM d, yyyy", null, System.Globalization.DateTimeStyles.None, out var d) ? d : DateTime.MaxValue;
            return (l, at, i);
        }).OrderBy(x => x.at).ThenBy(x => x.i).Select(x => x.l).ToList();

        // Scheduled checks' footer: when restart-only work finishes, by Settings' Restart at night (10/28: it always said 'the next
        // time you turn the PC off', also with the night restart on)
        internal static string SchedFooter(bool night) => "Everything here runs by itself. Checks wait while a game is running, and anything that needs a restart "
            + (night ? "finishes with a restart at night while the PC is unused (Settings > Restart at night)." : "finishes the next time you turn the PC off or restart.");

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
                // (10/25: improve-loop.ps1 - what the improvement rounds are doing, and today's)
                var im = Kit.ReadJson(Kit.P("improve-state.json"));
                if (im != null && Kit.Opt("improve", "on") != "off")
                {
                    var today = Json.L(im, "rounds").Where(r => Kit.Date(Json.Get(r, "at"))?.Date == DateTime.Today).ToList();
                    hl.Add(new Line($"Improving Messiah: {Json.S(im, "text")}" + (today.Count > 0 ? $" Today: {today.Count} round{Kit.S(today.Count)}, {today.Count(r => Json.S(r, "result") == "done")} landed." : ""), Json.S(im, "state") == "working" ? "ok" : "info"));
                    foreach (var r in today.Where(r => Json.S(r, "result") == "done").Reverse().Take(3)) hl.Add(new Line($"{Kit.FormatWhen(Kit.Date(Json.Get(r, "at")).Value)}: {Json.S(r, "item")}", "dim"));
                }
                hl.Add(new Line("About 2 minutes after each login, Claude handles anything in the report that needs judgment, then looks for ways to make Messiah better (at most once a day).", "dim"));
                o.Add(Ui.Card("Claude's own checks", "E90F", hl, new[] { Ui.Btn("E890", "Watch live", Actions.WatchLive), Ui.Btn("E8F1", "Self-improvement journal", Actions.Journal), Ui.Btn("E8B7", "Run logs", Actions.Logs) }));
                var use = Usage(Kit.ReadJson(Kit.P("claude-usage.json"))); if (use != null) o.Add(use);
            }
            var once = Week.FirstReport() != null;
            var pairs = SchedOrder(sched.Lines).Select(l => { var m = Regex.Match(l.Text, @"^([^:]+):\s+(.*)$"); return m.Success ? (m.Groups[1].Value, SchedWhen(m.Groups[2].Value, once), l.Level) : ("", l.Text, l.Level); });
            o.Add(Ui.Card("Scheduled checks", "E787", new object[] { Ui.Rows(pairs), new Line(SchedFooter(Settings.NightRestart), "dim") }));
            // (10/25, the owner: "a long list of text" - app updates on one day make one line, and the newest 8 show; the rest
            // are a click away)
            o.Add(Ui.Card("What maintenance did", "E90F", Days(Grouped(s.Timeline))));
            return o;
        }

        // (10/26: each line said its own "today 3:10 AM" - now a heading per day, the check's time once beside its first
        // line. The newest days up to 8 lines show (always the newest day whole); the earlier days are a click away)
        static List<object> Days(List<(DateTime When, string Text)> tl)
        {
            if (tl.Count == 0) return new List<object> { new Line("Nothing changed yet - the checks found everything in order.", "dim") };
            var all = new StackPanel(); Grid.SetIsSharedSizeScope(all, true);   // (the times line up across the days)
            var rest = new StackPanel { Visibility = Visibility.Collapsed };
            int shown = 0, hidden = 0;
            foreach (var day in tl.GroupBy(t => t.When.Date))
            {
                var n = day.Count(); var later = shown > 0 && shown + n > 8;
                var to = later ? rest : all;
                if (later) hidden++; else shown += n;
                var h = Ui.Text(DayName(day.Key), B("Text"), 14, FontWeights.SemiBold, to.Children.Count == 0 && to == all ? "0,0,0,2" : "0,12,0,2");
                h.Tag = $"day:{n}"; to.Children.Add(h);
                DateTime? prev = null;
                var g = Ui.Rows(day.Select(t => { var r = (t.When == prev ? "" : t.When.ToString("h:mm tt"), t.Text, "info"); prev = t.When; return r; }));
                g.ColumnDefinitions[0].SharedSizeGroup = "when"; to.Children.Add(g);
            }
            var did = new List<object> { all };
            if (hidden > 0)
            {
                all.Children.Add(rest);
                var say = $"Show {hidden} earlier day{Kit.S(hidden)}";
                Button more = null; more = Ui.Btn("E70D", say, () => { var open = rest.Visibility != Visibility.Visible; rest.Visibility = open ? Visibility.Visible : Visibility.Collapsed; ((TextBlock)((StackPanel)more.Content).Children[1]).Text = open ? "Show fewer" : say; }, small: true);
                more.HorizontalAlignment = HorizontalAlignment.Left; more.Margin = Ui.Th("0,8,0,0"); did.Add(more);
            }
            return did;
        }
        // "Today", "Yesterday", "Saturday, Oct 24" (this week), "Sep 20"
        // The note under What happened about old power-offs nobody answered (10/27: it said 3 while the chart above showed
        // 2 hollow marks - the third was from before the chart's 120 days, so it says where those are)
        internal static string OldNote(int open, int beforeChart)
        {
            var one = open == 1;
            var where = beforeChart <= 0 ? "" : beforeChart == open ? (one ? " (before the chart)" : " (all before the chart)") : $" ({beforeChart} before the chart)";
            return $"{open} power-off{Kit.S(open)} from over 30 days ago{where} {(one ? "was" : "were")} never answered, so {(one ? "it counts" : "they count")} as {(one ? "a crash" : "crashes")} here. If you don't remember {(one ? "it" : "them")} freezing, you most likely turned the PC off yourself.";
        }
        // The Power-offs tile's line: only the kinds there are (10/27: it read "1 by you, 0 froze, 1 not answered", and a
        // "Not sure" answer wasn't counted at all)
        internal static string OffSub(int me, int froze, int unsure, int toAnswer, int notAnswered)
        {
            var p = new List<string>();
            if (me > 0) p.Add($"{me} by you");
            if (froze > 0) p.Add($"{froze} went off by itself");
            if (unsure > 0) p.Add($"{unsure} not sure");
            if (toAnswer > 0) p.Add($"{toAnswer} to answer on Home");
            if (notAnswered > 0) p.Add($"{notAnswered} not answered");
            return p.Count == 0 ? "None recorded" : string.Join(", ", p);
        }
        // the Blue screens tile's line: the stop code(s) (10/28: it said "Each with a crash dump" with none, and power-log.ps1
        // reads the code from Windows' log - a dump isn't always there)
        internal static string BsodSub(IList<string> codes)
        {
            var c = codes.Select(x => (x ?? "").Trim()).Where(x => x != "").Distinct().ToList();
            return codes.Count == 0 ? "None recorded"
                : c.Count == 0 ? "Stop code not recorded"
                : c.Count == 1 ? "Stop code " + c[0] + (codes.Count == 1 ? "" : " each time")
                : $"{c.Count} different stop codes";
        }
        // "Days since the last crash": what the last one was, in the Power-offs tile's words (10/27: a not-sure one read
        // "Went off - you weren't sure", an unanswered one "Went off - not answered yet" without saying where to answer)
        internal static string LastCrash(string kind, string code, string answer, bool old) =>
            kind == "bsod" ? ("Blue screen " + code).Trim()
            : answer == "froze" ? "Went off by itself"
            : answer == "unsure" ? "Went off - not sure why"
            : old ? "Went off - not answered" : "Went off - answer it on Home";

        // a day heading: Today, Yesterday, else the weekday for every day (10/28: "Sunday, Oct 25" sat above a bare "Oct 8"),
        // and the year only when it isn't this one
        internal static string DayName(DateTime d)
        {
            int days = (DateTime.Today - d.Date).Days;
            return days == 0 ? "Today" : days == 1 ? "Yesterday" : d.ToString(d.Year == DateTime.Today.Year ? "dddd, MMM d" : "dddd, MMM d, yyyy");
        }

        // the same check's "Updated app: X" lines as one: "Updated 5 apps: 7zip, AutoHotkey, ..." (winget ids made readable)
        internal static List<(DateTime When, string Text)> Grouped(List<(DateTime When, string Text)> tl)
        {
            var o = new List<(DateTime When, string Text)>();
            const string U = "Updated app: ";
            for (int i = 0; i < tl.Count; i++)
            {
                int j = i; while (tl[i].Text.StartsWith(U) && j + 1 < tl.Count && tl[j + 1].When == tl[i].When && tl[j + 1].Text.StartsWith(U)) j++;   // (next to each other, the same check)
                if (j == i) { o.Add((tl[i].When, Data.AppLine(tl[i].Text))); continue; }
                var names = tl.Skip(i).Take(j - i + 1).Select(x => Data.AppName(x.Text.Substring(U.Length))).Distinct().ToList();
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
            // (under 200 characters, so it isn't folded - 10/26: it ended in "..." at every width; whole sentences, no dash - 10/28: one
            // at a line's end read like a cut-off)
            else lines.Add(new Line("No results yet. The nightly test runs by itself once the PC sits idle for 30 minutes (no game) and stops when you touch it. It runs every night while blue screens keep coming, else once a month.", "dim"));
            if (s.RamChecks.Any(r => r.Bad)) lines.Add(new Line("Errors mean faulty memory - test one stick at a time to find which (the RAM stick test).", "warn"));
            var btn = armed != null ? Ui.Btn("E711", "Cancel the deep test", () => Actions.RamBoot(false)) : Ui.Btn("E950", "Deep test at the next start-up", () => Actions.RamBoot(true));
            return Ui.Card("Memory test", "E950", lines.ToArray(), new[] { btn });
        }

        public static List<UIElement> Stability(Snapshot s, double width)
        {
            var o = new List<UIElement>();
            var evs = s.Power; var chs = s.Changes;
            if (evs.Count == 0 && chs.Count == 0) { o.Add(Ui.Card("Stability", "E9D9", new object[] { new Line("Nothing recorded yet - the record is made at the next check.", "dim") })); o.Add(MemoryTest(s)); return o; }
            bool IsCrash(Data.PowerEvent e) => Actions.IsCrash(e);   // (a power-off the owner made isn't one)
            var lastC = evs.Where(IsCrash).OrderBy(e => e.At).LastOrDefault();
            // (10/26: power-offs from 2025 said "not answered yet" - Home only asks about the last 30 days, so an older one
            // isn't waiting for anything: "not answered", and one click below answers them all)
            var d30 = DateTime.Now.AddDays(-30);
            var ans = new Dictionary<string, string> { ["me"] = "you turned it off", ["froze"] = "you said it froze or went off by itself", ["unsure"] = "you weren't sure" };
            string Ans(Data.PowerEvent e) => ans.TryGetValue(e.Answer ?? "", out var t) ? t : e.Key < d30 ? "not answered" : "not answered yet";
            var oldOpen = evs.Count(e => e.Kind == "off" && string.IsNullOrEmpty(e.Answer) && e.Key < d30);
            // (10/28: the tiles counted 90 days while the chart and What happened cover 120 - "1 not answered" in the tile but
            // 2 hollow marks in the chart; now one window for all)
            var d120 = DateTime.Now.AddDays(-120);
            int Off(Func<Data.PowerEvent, bool> f) => evs.Count(e => e.Kind == "off" && e.At > d120 && f(e));
            var tiles = Ui.Pairs(new UniformGrid { Columns = 3, Margin = Ui.Th("0,0,-12,2") });
            // (10/27: a tile with something to count opens the list below, "What happened", where those events are)
            const string list = "Activity/Stability#What happened";
            foreach (var (label, big, sub) in new[] {
                ("Days since the last crash", lastC != null ? Math.Round((DateTime.Now - lastC.At).TotalDays).ToString() : "-", lastC != null ? $"{LastCrash(lastC.Kind, lastC.Code, lastC.Answer, lastC.Key < d30)}, {Kit.FormatWhen(lastC.At)}" : "None recorded"),
                ("Blue screens, 120 days", evs.Count(e => e.Kind == "bsod" && e.At > d120).ToString(), BsodSub(evs.Where(e => e.Kind == "bsod" && e.At > d120).Select(e => e.Code).ToList())),
                ("Power-offs, 120 days", Off(e => true).ToString(), OffSub(Off(e => e.Answer == "me"), Off(e => e.Answer == "froze"), Off(e => e.Answer == "unsure"),
                    Off(e => string.IsNullOrEmpty(e.Answer) && e.Key >= d30), Off(e => string.IsNullOrEmpty(e.Answer) && e.Key < d30))) })
            {
                var tsp = new StackPanel();
                tsp.Children.Add(Ui.Text(label, B("Sub"), 12, null, "0"));
                var bt = Ui.Text(big, B("Text"), 28, FontWeights.SemiBold, "0,2,0,0"); bt.FontFamily = Theme.Display; tsp.Children.Add(bt);
                tsp.Children.Add(Ui.Text(sub, B("Sub"), 12, null, "0,2,0,0"));
                var tc = Ui.Card(null, null, new object[] { tsp }); tc.Margin = Ui.Th("0,0,12,14"); ((CardInfo)tc.Tag).Tile = $"{label}: {big} / {sub}";
                var none = label.StartsWith("Days") ? lastC == null : big == "0";   // (0 days since = a crash today)
                Ui.Opens(tc, none ? null : list, $"{label} - {big}. {sub}"); tiles.Children.Add(tc);
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

            foreach (var e in evs.Where(e => e.At > t0))
            {
                var x = ToX(e.At); var when = Kit.Stamp(e.At);
                if (e.Kind == "bsod") Mark(new Ellipse { Width = 12, Height = 12, Fill = B("Warn"), Stroke = bg, StrokeThickness = 2 }, x, lane["bsod"], $"{when}: blue screen {e.Code}");
                else if (e.Answer == "me") Mark(new Ellipse { Width = 9, Height = 9, Fill = B("Sub"), Stroke = bg, StrokeThickness = 2 }, x, lane["off"], $"{when}: went off - you turned it off");
                else Mark(new Ellipse { Width = 12, Height = 12, Fill = bg, Stroke = B("Warn"), StrokeThickness = 2 }, x, lane["off"], $"{when}: went off without a blue screen - {Ans(e)}");
            }
            foreach (var c in chs.Where(c => c.At > t0))
                Mark(new Rectangle { Width = 9, Height = 9, Fill = B("Chart"), Stroke = bg, StrokeThickness = 1.5, RenderTransformOrigin = new Point(0.5, 0.5), RenderTransform = new RotateTransform(45) }, ToX(c.At), lane["change"], $"{Kit.Stamp(c.At, false)}{(c.Approx ? " (about)" : "")}: {c.What} {c.From} → {c.To}");
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
            var rows = evs.Select(e => (e.At, e.Kind == "bsod" ? "Blue screen " + e.Code : "Went off without a blue screen (" + Ans(e) + ")", IsCrash(e) ? "info" : "dim"))
                .Concat(chs.Select(c => (c.At, $"{c.What}: {c.From} → {c.To}{(c.Approx ? " (date approximate)" : "")}", "dim")))
                .OrderByDescending(r => r.Item1).Take(40).Select(r => (At: r.Item1, Label: Kit.FormatWhen(r.Item1), Text: r.Item2, Level: r.Item3)).ToList();
            // (10/25, "a long list of text": the newest 10 of the chart's 120 days; the rest - older ones too - a click away)
            var recent = rows.Where(r => r.At > t0).Take(10).ToList(); var rest = rows.Skip(recent.Count).ToList();
            // (with nothing recent - only older ones, none at all returned above - a plain line like Alerts': an empty-label
            // row sat indented under the date column)
            var wl = new List<object> { recent.Count > 0 ? (object)Ui.Rows(recent.Select(r => (r.Label, r.Text, r.Level)), align: "stability")
                : new Line($"Nothing in the last 120 days - the older {(rest.Count == 1 ? "one is" : "ones are")} under Show {rest.Count} more.", "dim") };
            if (rest.Count > 0)
            {
                var more = Ui.Rows(rest.Select(r => (r.Label, r.Text, r.Level)), align: "stability"); more.Visibility = Visibility.Collapsed; wl.Add(more);
                Button mb = null; mb = Ui.Btn("E70D", $"Show {rest.Count} more", () => { var open = more.Visibility != Visibility.Visible; more.Visibility = open ? Visibility.Visible : Visibility.Collapsed; ((TextBlock)((StackPanel)mb.Content).Children[1]).Text = open ? "Show fewer" : $"Show {rest.Count} more"; }, small: true);
                mb.HorizontalAlignment = HorizontalAlignment.Left; mb.Margin = Ui.Th("0,8,0,0"); wl.Add(mb);
            }
            if (oldOpen > 0) wl.Add(new Line(OldNote(oldOpen, evs.Count(e => e.Kind == "off" && string.IsNullOrEmpty(e.Answer) && e.At <= t0)), "dim"));
            // (10/26: "Copy a crash report" - the last crash, its code's name, the dump's analysis and what changed before it,
            // ready to paste into a forum post)
            var acts = new List<UIElement>();
            if (lastC != null) acts.Add(Ui.Btn("E8C8", "Copy a crash report", () => Actions.CopyCrashReport(s)));
            if (oldOpen > 0) acts.Add(Ui.Btn("E73E", oldOpen == 1 ? "I turned that one off" : $"I turned those {oldOpen} off", () => { Data.RunPs("power-log.ps1", "-Answer me -Old"); Shell.Say("Thanks - noted. Those don't count as crashes any more."); Shell.Refresh(true); }));
            o.Add(Ui.Card("What happened", "E81C", wl, acts.Count > 0 ? acts.ToArray() : null));
            o.Add(Foot("From Windows' own log (back to when it starts) - recorded at every login. Hover over a mark for details."));
            return o;
        }

        // --- Trends: health over time - one measure per chart, each with its own scale (never two on one axis); the current
        // value as the big number; the usual level as a faint dashed line (C:'s free space: how far it moved instead); every point has a tooltip
        // (a chart shows an amber change mark: the window's subtitle names it too - only then, 10/28)
        static List<Border> trendCharts = new List<Border>();
        internal static string TrendsSub(string plain, IEnumerable<Border> charts = null) => (charts ?? trendCharts).Any(Charts.ShowsMark) ? TrendsMarkSub : plain;
        internal const string TrendsMarkSub = "How this PC has been doing over time. Point at a chart to read a day, or at an amber line for what changed.";
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
            var charts = new List<Border> { Chart("Start-up time", " s", Pt("boot", true), 1, 10), Chart("Free space on C:", " GB", Pt("freeGB"), 0, 20, drift: true, marks: FreeDrops(Pt("freeGB"), GamesOnC(s))),
                Chart("Graphics card at idle", " °C", Pt("gpuIdle"), 0, 10), Chart("SSD temperature", " °C", Pt("ssdTemp"), 0, 10) };
            if (Pt("cpuIdle").Any()) charts.Add(Chart("Processor at idle", " °C", Pt("cpuIdle"), 0, 10));
            charts.Add(Chart("Internet ping at idle", " ms", Gp(s.Net, "ping"), 0, 10));
            foreach (var ch in charts) { ch.Margin = Ui.Th("0,0,14,14"); grid.Children.Add(ch); }
            trendCharts = charts;
            o.Add(grid);
            o.Add(Foot("Recorded at every check (at each login and once a day). Idle temperatures are taken only while the PC is idle, so a game never skews them. Your games: Games > Performance."));
            return o;
        }
        static double? Median(List<double> v) { if (v.Count == 0) return null; var s = v.OrderBy(x => x).ToList(); int m = s.Count / 2; return s.Count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2; }
        // (the interactive chart, 10/22: Charts.Chart - hover, change marks, 7 days / 30 days / all, a click)
        internal static Border Chart(string title, string unit, IEnumerable<(DateTime D, double V)> data, int decimals, double minSpan, bool drift = false,
            IEnumerable<(DateTime D, string Text)> marks = null) =>
            Charts.Chart(title, unit, data.Select(p => new ChartPt { D = p.D, V = p.V }), decimals, minSpan, marks, drift: drift, hint: false, dated: true);   // (the hint is in Trends' subtitle, once; a stale chart names its day)

        // C:'s free space: a mark where it dropped 20 GB or more from one check to the next (10/27) - naming the game whose
        // folder appeared between the two checks when the storage scan has one (a game folder made then, at least half the drop)
        internal static List<(DateTime D, string Text)> FreeDrops(IEnumerable<(DateTime D, double V)> pts, IEnumerable<(string Name, DateTime Made, double GB)> games)
        {
            var p = pts.OrderBy(x => x.D).ToList(); List<(string Name, DateTime Made, double GB)> g = null; var o = new List<(DateTime D, string Text)>();
            for (int i = 1; i < p.Count; i++)
            {
                var drop = p[i - 1].V - p[i].V; if (drop < 20) continue;
                g = g ?? games.ToList();   // (the folders are read only when there is a drop)
                var game = g.Where(x => x.Made > p[i - 1].D && x.Made <= p[i].D && x.GB >= drop / 2).OrderByDescending(x => x.GB).Select(x => x.Name).FirstOrDefault();
                o.Add((p[i].D, $"{Math.Round(drop)} GB less free" + (game != null ? $" - {game} installed" : "")));
            }
            return o;
        }
        static IEnumerable<(string Name, DateTime Made, double GB)> GamesOnC(Snapshot s) =>
            (s.Storage == null ? Enumerable.Empty<object>() : Json.L(s.Storage, "games")).Where(x => Json.S(x, "drive") == "C" && System.IO.Directory.Exists(Json.S(x, "path") ?? ""))
                .Select(x => (Json.S(x, "name"), System.IO.Directory.GetCreationTime(Json.S(x, "path")), Json.N(x, "sizeGB") ?? 0));

        // --- Alerts: what Messiah had to say - recent ones, then earlier and resolved ones
        // where an alert's row goes (10/27): a to-do still open to Home's Needs you, updates waiting for the PC to be turned off
        // and maintenance to Checks, a blue screen or crash to Stability; a resolved one, a chat's "Claude finished" and the rest stay plain
        internal static string AlertGo(string text)
        {
            text = text ?? "";
            if (text.EndsWith("(resolved)")) return null;
            if (text.StartsWith("Needs you")) return "Home#Needs you";
            if (Regex.IsMatch(text, @"update\(s\)/fix\(es\) will finish|^(Hidden )?[Mm]aintenance (started|is already running)")) return "Activity/Checks";
            if (!text.StartsWith("Claude finished") && Regex.IsMatch(text, @"(?i)blue screen|crash")) return "Activity/Stability";
            return null;
        }
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
                var when = Kit.Stamp(n.When); var op = IsOpen(n.Text);
                if (op == false) earlier.Add((when, n.Text + "  (resolved)", "dim"));
                else if (n.When < DateTime.Now.AddDays(-7)) earlier.Add((when, n.Text, "dim"));
                else recent.Add((when, n.Text, "info"));
            }
            // with nothing recent a plain line like Stability's and Checks' empty states (an empty-label row sat indented
            // under the time column)
            object body = recent.Count > 0 ? (object)Ui.Rows(recent, (l, v) => AlertGo(v), "alerts")
                : new Line(notes.Count > 0 ? "Nothing new this week - the older ones are under Earlier and resolved." : "No alerts yet - a crash, a drive filling up or a driver to try would show here.", "dim");
            o.Add(Ui.Card("Alerts", "EA8F", new object[] { body },notes.Count > 0 ? new[] { Ui.Btn("E74D", "Clear", () => { try { System.IO.File.WriteAllText(Kit.P("notifications.log"), ""); } catch { } Shell.Refresh(true); }) } : null));
            if (earlier.Count > 0) o.Add(Ui.Card("Earlier and resolved", "E81C", new object[] { Ui.Rows(earlier.Take(30), (l, v) => AlertGo(v), "alerts") }));
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
