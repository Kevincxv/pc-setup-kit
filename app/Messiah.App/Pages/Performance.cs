using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using Sh = System.Windows.Shapes;

namespace Messiah.Pages
{
    // Activity > Performance (10/21): how the games run - each game's last minute second by second (its frame rate, and its
    // slowest frame each second: the hitches you feel), its frame rate over the sessions, and what a graphics driver or
    // Windows update did to it (the sessions before and after, side by side). From game-perf.ps1's samples (perf-history.json:
    // a minute every 25 minutes while a game is played - not its menus).
    static class Performance
    {
        static Brush B(string k) => Theme.B[k];
        static double Num(object o) { try { return Convert.ToDouble(o, System.Globalization.CultureInfo.InvariantCulture); } catch { return 0; } }

        public static List<UIElement> Build(Snapshot s)
        {
            var o = new List<UIElement>();
            var games = s.Perf.Where(r => Json.S(r, "game") != "" && Kit.Date(Json.Get(r, "date")) != null).GroupBy(r => Json.S(r, "game"))
                .OrderByDescending(g => Kit.Date(Json.Get(g.Last(), "date"))).ToList();
            if (games.Count == 0)
                o.Add(Ui.Card("Nothing measured yet", "E7FC", new object[] { new Line("While you play, a minute of each game is measured (every 25 minutes; menus and lobbies don't count): its frame rate, the slowest frames, the graphics card's heat. Play a game for a few minutes and it shows here.", "dim") }));
            foreach (var g in games.Take(6)) o.Add(Game(g.Key, g.ToList()));
            var tune = Tuning(s); if (tune != null) o.Add(tune);
            if (games.Count > 0) o.Add(Updates(games));
            var drv = DriverTest(s); if (drv != null) o.Add(drv);
            o.Add(Heat(s));
            if (games.Count > 0) o.Add(Activity.Foot("Measured with Intel's PresentMon for one minute while the game runs. 1% low: only 1 frame in 100 is slower - what you feel as smoothness. A hitch: a frame over 50 ms."));
            return o;
        }

        // --- tuning by measurement (game-tune.ps1): the setting being tried both ways in your matches, and what each test found
        static readonly Dictionary<string, string> GameNames = new Dictionary<string, string> { ["cod"] = "Call of Duty" };
        internal static string Say(string id, string v)
        {
            switch (id)
            {
                case "reflex": return v == "Enabled + boost" ? "Reflex Boost on" : "Reflex Boost off";
                case "vram": return double.TryParse(v, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var x) ? $"a {Math.Round(x * 100)}% video memory budget" : v;
                case "workers": return v == "-1" ? "automatic renderer threads" : $"{v} renderer threads";
                default: return v;
            }
        }
        static UIElement Tuning(Snapshot s)
        {
            var t = s.Tune; var a = Json.Get(t, "active") as Dictionary<string, object>; var done = Json.L(t, "done").OfType<Dictionary<string, object>>().ToList();
            if (a == null && done.Count == 0) return null;
            var lines = new List<object>();
            if (a != null)
            {
                string id = Json.S(a, "id"), game = Json.S(a, "game"); var since = Kit.Date(Json.Get(a, "started")) ?? DateTime.MinValue;
                int Count(string arm) => s.Perf.Count(r => Json.S(r, "game") == game && Json.S(r, "tune") == id + ":" + arm && (Kit.Date(Json.Get(r, "date")) ?? DateTime.MinValue) >= since);
                int na = Count("a"), nb = Count("b"); var on = Json.S(a, "arm") == "b" ? Json.S(a, "b") : Json.S(a, "a");
                lines.Add(new Line($"Trying now in {(GameNames.TryGetValue(game, out var gn) ? gn : game)}: {Say(id, Json.S(a, "a"))} (as before) against {Say(id, Json.S(a, "b"))} - {Math.Min(na, 4) + Math.Min(nb, 4)} of 8 minutes of play measured. On now: {Say(id, on)}.", "info"));
                lines.Add(new Line("Switched only while the game is closed, back and forth so one evening doesn't decide it. The other value is kept only if it is clearly faster; anything else changing in the middle (a driver, Windows) ends the test with your setting back.", "dim"));
            }
            else if (Json.Get(s.GpuState, "trial") is Dictionary<string, object> tr && Json.S(tr, "verdict") == "")
                lines.Add(new Line("Waiting: a new graphics driver is being tested first (a setting tried at the same time would muddy both results).", "dim"));
            var rows = new List<(string, string, string)>();
            foreach (var d in done.AsEnumerable().Reverse().Take(8))
            {
                string id = Json.S(d, "id"), why = Json.S(d, "why"), kept = Json.S(d, "kept"); var at = Kit.Date(Json.Get(d, "at"));
                double? aL = Json.N(d, "aLow"), bL = Json.N(d, "bLow"), aF = Json.N(d, "aFps"), bF = Json.N(d, "bFps");
                string Pct(double x, double y) => y > 0 ? $"{(x >= y ? "+" : "")}{Math.Round((x - y) / y * 100)}%" : "";
                var nums = aL != null && bL != null && aF != null && bF != null ? $" (1% low {Math.Round(aL.Value)} -> {Math.Round(bL.Value)} fps {Pct(bL.Value, aL.Value)}, average {Math.Round(aF.Value)} -> {Math.Round(bF.Value)} fps)" : "";
                string text, level;
                if (why == "faster") { text = $"{Say(id, Json.S(d, "b"))} is faster than {Say(id, Json.S(d, "a"))}{nums} - switched to it"; level = "ok"; }
                else if (why == "no faster") { text = $"{Say(id, Json.S(d, "b"))} was no faster{nums} - kept {Say(id, Json.S(d, "a"))}"; level = "info"; }
                else { text = $"{Json.S(d, "label")}: stopped - {why}{(kept != "" ? $"; {Say(id, kept)} kept" : "")}"; level = "dim"; }
                rows.Add((at?.ToString("MMM d") ?? "", text, level));
            }
            if (rows.Count > 0) lines.Add(Ui.Rows(rows));
            return Ui.Card("Tuned by measuring", "E9E9", lines.ToArray());
        }

        // --- a new graphics driver on test (gpu-watch.ps1): measured against the one before; clearly slower = back by itself
        static UIElement DriverTest(Snapshot s)
        {
            if (!(Json.Get(s.GpuState, "trial") is Dictionary<string, object> tr)) return null;
            var since = Kit.Date(Json.Get(tr, "since")); if (since == null || since < DateTime.Now.AddDays(-30)) return null;
            string drv = Json.S(tr, "driver"), from = Json.S(tr, "from"), verdict = Json.S(tr, "verdict"), text = Json.S(tr, "text");
            Line l;
            if (verdict == "")
            {
                var n = s.Perf.Where(r => Json.S(r, "driver") == drv && (Kit.Date(Json.Get(r, "date")) ?? DateTime.MinValue) >= since).GroupBy(r => Json.S(r, "game")).Select(g => g.Count()).DefaultIfEmpty(0).Max();
                l = new Line($"Driver {drv} (since {Kit.FormatWhen(since.Value, dateOnly: true)}) is on test against {from}: {Math.Min(n, 3)} of 3 minutes of play measured on it. If your games run clearly slower on it, Messiah goes back to {from} by itself.", "info");
            }
            else if (verdict == "passed") l = new Line($"Driver {drv} passed its test - {text}", "ok");
            else if (verdict == "rolled back") l = new Line($"Driver {drv} was undone - {text}", "warn");
            else if (verdict == "slower") l = new Line($"Driver {drv} is slower - {text}. Settings > Tools > Go back to the previous graphics driver", "warn");
            else l = new Line($"Driver {drv}: {text}", "dim");
            return Ui.Card("Graphics driver test", "E7F8", new object[] { l });
        }

        // --- heat and wear: the graphics card, the processor and the SSD - while gaming and over time
        static UIElement Heat(Snapshot s)
        {
            var rows = new List<(string, string, string)>();
            var g = s.Perf.LastOrDefault(r => Json.N(r, "gpuTemp") != null); var h = s.HealthLast;
            var gpu = new List<string>(); var gl = "info";
            if (g != null)
            {
                var thr = Json.S(g, "throttle");
                gpu.Add($"up to {Json.N(g, "gpuTemp")} C while gaming" + (Json.N(g, "gpuFan") is double gf ? $", fan {gf}%" : "") + (Json.N(g, "gpuPower") is double gp ? $", {gp} W" : "") + (thr != "" ? $" - it slowed itself down ({thr.Replace(",", " and ")} limit)" : ""));
                if (thr != "" || (Json.N(g, "gpuTemp") ?? 0) >= 85) gl = "warn";
            }
            if (Json.N(h, "gpuIdle") is double gi) gpu.Add($"{gi} C at idle" + (Json.N(h, "gpuIdleFan") is double fi ? $", fan {fi}%" : ""));
            rows.Add(("Graphics card", gpu.Count > 0 ? string.Join("; ", gpu) : "measured from your next game", gpu.Count > 0 ? gl : "dim"));
            var c = s.Perf.LastOrDefault(r => Json.N(r, "cpuLimit") != null);
            if (c != null)
            {
                var lim = Json.N(c, "cpuLimit") ?? 100;
                rows.Add(("Processor", lim >= 95 ? $"at full speed while gaming ({Json.N(c, "cpuPerf")}% of its base speed)" : $"held back to {lim}% of its speed while gaming - nearly always heat: the CPU cooler's fan or pump, its dust, the case's air flow", lim >= 95 ? "ok" : "warn"));
            }
            else rows.Add(("Processor", "measured from your next game (its temperature can't be read without a kernel driver; how much it is held back can)", "dim"));
            if (h != null && (Json.N(h, "ssdTemp") != null || Json.N(h, "ssdWear") != null))
            {
                var mx = Json.N(h, "ssdTempMax");
                var parts = new List<string>();
                if (Json.N(h, "ssdTemp") is double t0) parts.Add($"{t0} C now");
                if (mx != null) parts.Add($"{mx} C at its hottest{(mx >= 80 ? " (it slows itself down from about 80 C - a heatsink helps)" : "")}");
                if (Json.N(h, "ssdWear") is double w) parts.Add($"{w}% worn");
                rows.Add(("SSD", string.Join(", ", parts), mx >= 80 ? "warn" : "info"));
            }
            var lines = new List<object> { Ui.Rows(rows) };
            var grid = new UniformGrid { Columns = 2, Margin = Ui.Th("0,8,-14,0") };
            var gt = s.Perf.Where(r => Json.N(r, "gpuTemp") != null && Kit.Date(Json.Get(r, "date")) != null).Select(r => (Kit.Date(Json.Get(r, "date")).Value, Json.N(r, "gpuTemp").Value)).ToList();
            if (gt.Count >= 2) grid.Children.Add(Pad(Activity.Chart("Graphics card while gaming", " C", gt, 0, 10)));
            var it = s.Health.Where(r => Json.N(r, "gpuIdle") != null && Kit.Date(Json.Get(r, "date")) != null).Select(r => (Kit.Date(Json.Get(r, "date")).Value, Json.N(r, "gpuIdle").Value)).ToList();
            if (it.Count >= 2) grid.Children.Add(Pad(Activity.Chart("Graphics card at idle", " C", it, 0, 10)));
            if (grid.Children.Count > 0) lines.Add(grid);
            lines.Add(new Line("Warming up over the months usually means dust - Messiah says when it's time to clean the fans and filters.", "dim"));
            return Ui.Card("Heat and wear", "E9CA", lines.ToArray());
        }

        // one game: the last session's numbers, its minute second by second, and its frame rate over the sessions
        static UIElement Game(string game, List<Dictionary<string, object>> rows)
        {
            var last = rows.Last(); var when = Kit.Date(Json.Get(last, "date")).Value;
            var fps = Json.N(last, "fps") ?? 0; var low = Json.N(last, "low1") ?? 0; var st = (int)(Json.N(last, "stutters") ?? 0);
            var usual = Median(rows.Select(r => Json.N(r, "fps") ?? 0).ToList());
            var lines = new List<object>
            {
                new Line($"{Math.Round(fps)} fps average, 1% low {Math.Round(low)} fps, {st} hitch{(st == 1 ? "" : "es")} - {Kit.FormatWhen(when)}" +
                    (rows.Count > 1 ? $" (usual {Math.Round(usual)} fps over {rows.Count} sessions)" : ""), fps < usual * 0.9 && rows.Count > 2 ? "warn" : "info")
            };
            var gt = Json.N(last, "gpuTemp"); var thr = Json.S(last, "throttle");
            if (gt != null) lines.Add(new Line($"Graphics card up to {gt} C, {Json.N(last, "gpuUse") ?? 0}% busy{(thr != "" ? $" - it slowed itself down ({thr.Replace(",", " and ")} limit)" : "")}", thr != "" ? "warn" : "dim"));
            // drivers' time on the busiest core while playing (interrupts and deferred calls): over 15% steals time from the game
            var dpc = Json.N(last, "dpcMax");
            if (dpc != null) lines.Add(new Line(dpc >= 15 ? $"Drivers took up to {dpc}% of a core while you played - enough to cause stutters the frame rate hides (audio, network or USB drivers are the usual ones)" : $"Drivers took up to {dpc}% of a core while you played - fine", dpc >= 15 ? "warn" : "dim"));
            var per = Json.L(last, "perSec").Select(Num).ToList(); var worst = Json.L(last, "worstMs").Select(Num).ToList();
            var grid = new UniformGrid { Columns = 2, Margin = Ui.Th("0,8,-14,0") };
            if (per.Count >= 2)
            {
                grid.Children.Add(Pad(Curve("The last minute, second by second", " fps", per, false)));
                grid.Children.Add(Pad(Curve("Its slowest frame each second", " ms", worst, true)));
            }
            var hist = rows.Select(r => (Kit.Date(Json.Get(r, "date")).Value, Json.N(r, "fps") ?? 0)).ToList();
            if (hist.Count >= 2) grid.Children.Add(Pad(Activity.Chart("Frame rate, each session", " fps", hist, 0, 20)));
            var lowH = rows.Select(r => (Kit.Date(Json.Get(r, "date")).Value, Json.N(r, "low1") ?? 0)).ToList();
            if (lowH.Count >= 2) grid.Children.Add(Pad(Activity.Chart("1% low, each session", " fps", lowH, 0, 20)));
            if (grid.Children.Count > 0) lines.Add(grid);
            else lines.Add(new Line("The second-by-second view shows from the next session on (sessions measured before 10/21 kept only the totals).", "dim"));
            return Ui.Card(game, "E7FC", lines.ToArray());
        }
        static UIElement Pad(UIElement e) { ((FrameworkElement)e).Margin = Ui.Th("0,0,14,14"); return e; }

        // something that changed between sessions - a graphics driver, Windows, the RAM speed (EXPO), Memory Integrity, the game's
        // own settings: each game's sessions on the one before and on the one after, side by side, and what it came to
        internal static readonly (string Field, string What)[] Changes = { ("driver", "Graphics driver"), ("build", "Windows"), ("ram", "RAM speed"), ("hvci", "Memory Integrity"), ("settings", "Your game settings") };
        static UIElement Updates(List<IGrouping<string, Dictionary<string, object>>> games)
        {
            var lines = new List<(string, string, string)>();
            foreach (var g in games) foreach (var v in Verdicts(g.Key, g.ToList())) lines.Add((v.When, v.Text, v.Level));
            if (lines.Count == 0) lines.Add(("", "Nothing changed between sessions yet - after the next change (a driver, Windows, EXPO, a setting), each game's sessions before and after show here with what it came to.", "dim"));
            return Ui.Card("Before and after changes", "E895", new object[] { Ui.Rows(lines.OrderByDescending(l => l.Item1).ToList()) });
        }
        internal static List<(string When, string Text, string Level, DateTime? Decided)> Verdicts(string game, List<Dictionary<string, object>> rows)
        {
            var o = new List<(string, string, string, DateTime?)>();
            foreach (var (field, what) in Changes)
            {
                var runs = new List<(string Ver, List<Dictionary<string, object>> Rows)>();
                foreach (var r in rows) { var v = Json.S(r, field); if (v == "") continue; if (runs.Count == 0 || runs[runs.Count - 1].Ver != v) runs.Add((v, new List<Dictionary<string, object>>())); runs[runs.Count - 1].Rows.Add(r); }
                for (int i = 1; i < runs.Count; i++)
                {
                    double A(List<Dictionary<string, object>> rr, string f) => rr.Average(r => Json.N(r, f) ?? 0);
                    var before = runs[i - 1].Rows; var after = runs[i].Rows;
                    double f0 = A(before, "fps"), f1 = A(after, "fps"), l0 = A(before, "low1"), l1 = A(after, "low1");
                    var pct = f0 > 0 ? (f1 - f0) / f0 * 100 : 0; var lpct = l0 > 0 ? (l1 - l0) / l0 * 100 : 0;
                    // a verdict once there are 2 sessions on each side (one minute can be a quiet moment or a busy one)
                    string verdict, level;
                    if (before.Count < 2 || after.Count < 2) { verdict = $"too early to tell - {after.Count} session(s) since"; level = "dim"; }
                    else if (pct <= -5 || lpct <= -8) { verdict = "worse"; level = "warn"; }
                    else if (pct >= 5 || lpct >= 8) { verdict = "better"; level = "ok"; }
                    else { verdict = "about the same"; level = "info"; }
                    var from = field == "settings" ? "" : $" {runs[i - 1].Ver} -> {runs[i].Ver}";
                    var at = Kit.Date(Json.Get(after[0], "date")).Value;
                    o.Add((at.ToString("MMM d"), $"{game} - {what}{from}: {verdict} - {Math.Round(f0)} -> {Math.Round(f1)} fps ({(pct >= 0 ? "+" : "")}{Math.Round(pct)}%), 1% low {Math.Round(l0)} -> {Math.Round(l1)} ({(lpct >= 0 ? "+" : "")}{Math.Round(lpct)}%)", level, before.Count >= 2 && after.Count >= 2 ? Kit.Date(Json.Get(after[1], "date")) : null));
                }
            }
            return o;
        }
        static double Median(List<double> v) { if (v.Count == 0) return 0; var s = v.OrderBy(x => x).ToList(); int m = s.Count / 2; return s.Count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2; }

        // a minute second by second: the frame rate as a line; the slowest frames as bars (amber over 50 ms - a hitch)
        static Border Curve(string title, string unit, List<double> vals, bool bars)
        {
            var sp = new StackPanel();
            var hero = new StackPanel { Orientation = Orientation.Horizontal };
            var head = bars ? vals.Max() : Median(vals);
            hero.Children.Add(Ui.Text(Math.Round(head) + unit, B("Text"), 26, FontWeights.SemiBold, "0"));
            var sub = Ui.Text(bars ? $"   worst - {vals.Count(v => v > 50)} hitch(es) over 50 ms" : $"   typical - lowest {Math.Round(vals.Min())}{unit}", B("Sub"), 12, null, "0,0,0,5"); sub.VerticalAlignment = VerticalAlignment.Bottom; hero.Children.Add(sub);
            sp.Children.Add(hero);
            double W = 330, H = 84, lo = bars ? 0 : vals.Min(), hi = Math.Max(vals.Max(), bars ? 60 : vals.Min() + 20);
            var pad = (hi - lo) * 0.1; if (!bars) lo -= pad; hi += pad;
            double X(int i) => vals.Count == 1 ? W / 2 : i / (double)(vals.Count - 1) * (W - 12) + 6; double Y(double v) => H - 4 - (v - lo) / (hi - lo) * (H - 8);
            var cv = new Canvas { Width = W, Height = H, Margin = Ui.Th("0,10,0,0"), HorizontalAlignment = HorizontalAlignment.Left };
            foreach (var gy in new[] { 4.0, H - 4 }) cv.Children.Add(new Sh.Line { X1 = 0, X2 = W, Y1 = gy, Y2 = gy, Stroke = B("Border"), StrokeThickness = 1 });
            if (bars)
            {
                var y50 = Y(50); cv.Children.Add(new Sh.Line { X1 = 0, X2 = W, Y1 = y50, Y2 = y50, Stroke = B("Warn"), StrokeThickness = 1, StrokeDashArray = new DoubleCollection { 4, 3 }, Opacity = 0.6 });
                double bw = Math.Max(2, (W - 12) / vals.Count - 1.5);
                for (int i = 0; i < vals.Count; i++)
                {
                    var r = new Sh.Rectangle { Width = bw, Height = Math.Max(1, H - 4 - Y(vals[i])), Fill = vals[i] > 50 ? B("Warn") : B("Chart"), RadiusX = 1, RadiusY = 1, ToolTip = $"Second {i + 1}: slowest frame {vals[i]} ms" };
                    Canvas.SetLeft(r, X(i) - bw / 2); Canvas.SetTop(r, Y(vals[i])); cv.Children.Add(r);
                }
            }
            else
            {
                var line = new Sh.Polyline { Stroke = B("Chart"), StrokeThickness = 2, StrokeLineJoin = PenLineJoin.Round };
                for (int i = 0; i < vals.Count; i++) line.Points.Add(new Point(X(i), Y(vals[i])));
                cv.Children.Add(line);
                for (int i = 0; i < vals.Count; i++) { var hit = new Sh.Ellipse { Width = 12, Height = 12, Fill = Brushes.Transparent, ToolTip = $"Second {i + 1}: {vals[i]} fps" }; Canvas.SetLeft(hit, X(i) - 6); Canvas.SetTop(hit, Y(vals[i]) - 6); cv.Children.Add(hit); }
            }
            sp.Children.Add(cv);
            sp.Children.Add(Ui.Text($"{vals.Count} seconds", B("Sub"), 11, null, "0,4,0,0"));
            sp.Tag = $"CHART: {title} | {vals.Count} seconds, {(bars ? "worst" : "typical")} {Math.Round(head)}{unit}";
            return Ui.Card(title, null, new object[] { sp });
        }
    }
}
