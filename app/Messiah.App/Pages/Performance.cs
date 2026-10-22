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
            {
                o.Add(Ui.Card("Nothing measured yet", "E7FC", new object[] { new Line("While you play, a minute of each game is measured (every 25 minutes; menus and lobbies don't count): its frame rate, the slowest frames, the graphics card's heat. Play a game for a few minutes and it shows here.", "dim") }));
                return o;
            }
            foreach (var g in games.Take(6)) o.Add(Game(g.Key, g.ToList()));
            o.Add(Updates(games));
            o.Add(Activity.Foot("Measured with Intel's PresentMon for one minute while the game runs. 1% low: only 1 frame in 100 is slower - what you feel as smoothness. A hitch: a frame over 50 ms."));
            return o;
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

        // a driver or Windows update: each game's sessions on the version before and on the one after
        static UIElement Updates(List<IGrouping<string, Dictionary<string, object>>> games)
        {
            var lines = new List<(string, string, string)>();
            foreach (var (field, what) in new[] { ("driver", "Graphics driver"), ("build", "Windows") })
                foreach (var g in games)
                {
                    var runs = new List<(string Ver, List<Dictionary<string, object>> Rows)>();
                    foreach (var r in g) { var v = Json.S(r, field); if (v == "") continue; if (runs.Count == 0 || runs[runs.Count - 1].Ver != v) runs.Add((v, new List<Dictionary<string, object>>())); runs[runs.Count - 1].Rows.Add(r); }
                    for (int i = 1; i < runs.Count; i++)
                    {
                        double A(List<Dictionary<string, object>> rr, string f) => rr.Average(r => Json.N(r, f) ?? 0);
                        var before = runs[i - 1].Rows; var after = runs[i].Rows;
                        double f0 = A(before, "fps"), f1 = A(after, "fps"), l0 = A(before, "low1"), l1 = A(after, "low1");
                        var pct = f0 > 0 ? (f1 - f0) / f0 * 100 : 0;
                        var level = pct <= -5 || (l0 > 0 && (l1 - l0) / l0 <= -0.08) ? "warn" : pct >= 5 ? "ok" : "info";
                        var at = Kit.Date(Json.Get(after[0], "date")).Value;
                        lines.Add((at.ToString("MMM d"), $"{g.Key} - {what} {runs[i - 1].Ver} -> {runs[i].Ver}: {Math.Round(f0)} -> {Math.Round(f1)} fps ({(pct >= 0 ? "+" : "")}{Math.Round(pct)}%), 1% low {Math.Round(l0)} -> {Math.Round(l1)} ({before.Count} session(s) before, {after.Count} after)", level));
                    }
                }
            if (lines.Count == 0) lines.Add(("", "No driver or Windows update between sessions yet - after the next one, each game's sessions before and after show here side by side.", "dim"));
            return Ui.Card("Before and after updates", "E895", new object[] { Ui.Rows(lines.OrderByDescending(l => l.Item1).ToList()) });
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
