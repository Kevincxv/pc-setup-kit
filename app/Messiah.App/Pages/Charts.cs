using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using Sh = System.Windows.Shapes;

namespace Messiah.Pages
{
    // one point of a chart: when, the value, what else was going on then (said on hover), and a key a click picks it by
    class ChartPt { public DateTime D; public double V; public string More; public string Key; }
    // the point picked on a chart, shared by the charts showing the same sessions (a game's frame rate and its 1% low)
    class ChartSel { public string Key; public event Action Changed; public void Set(string k) { Key = k; Changed?.Invoke(); } }
    // what the test mode reaches (the chart canvas's DataContext): hover, click and the range without a mouse
    class ChartCtl { public Func<int, string> Hover; public Action<int> Click; public Action<string> Range; public int Count; }

    // The charts over time (10/22, the owner's request: interactive): point at it - the value, its date and what else was going
    // on then (driver, RAM speed, the setting being tried...) in the line under the chart; arrows keys do the same; a dashed
    // mark where something changed (a driver, Windows, EXPO, the game's settings, a tuning test); 7 days / 30 days / all;
    // a chart of sessions can be clicked to open that session. Fits its card's width. Never zoom or drag: a few hundred
    // points at most, nothing more to find that way.
    static class Charts
    {
        static SolidColorBrush B(string k) => Theme.B[k];
        static readonly string[] RangeNames = { "7 days", "30 days", "All" };
        static readonly Dictionary<string, string> rangeOf = new Dictionary<string, string>();   // (by the chart's title: kept across redraws)
        static double Median(List<double> v) { var s = v.OrderBy(x => x).ToList(); int m = s.Count / 2; return s.Count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2; }

        public static Border Chart(string title, string unit, IEnumerable<ChartPt> data, int decimals, double minSpan,
            IEnumerable<(DateTime D, string Text)> marks = null, Action<ChartPt> click = null, ChartSel sel = null)
        {
            var all = (data ?? Enumerable.Empty<ChartPt>()).Where(p => p != null).OrderBy(p => p.D).ToList();
            var mk = (marks ?? Enumerable.Empty<(DateTime D, string Text)>()).OrderBy(m => m.D).ToList();
            string Fmt(double v) => Math.Round(v, decimals) + unit;
            var sp = new StackPanel();
            var card = Ui.Card(title, null, new object[] { sp });
            if (all.Count < 2)
            {
                sp.Children.Add(Ui.Text(all.Count > 0 ? Fmt(all[0].V) : "-", B("Text"), 26, FontWeights.SemiBold, "0"));
                sp.Children.Add(Ui.Text("Collecting - the chart shows after a few checks.", B("Sub"), 12, null, "0,4,0,0"));
                sp.Tag = $"CHART: {title} | {all.Count} point(s)";
                return card;
            }
            var last = all[all.Count - 1];
            bool ranged = (last.D - all[0].D).TotalDays > 7;
            if (!rangeOf.TryGetValue(title, out var range)) range = (last.D - all[0].D).TotalDays > 30 ? "30 days" : "All";
            if (!ranged) range = "All";
            double W = 330, H = 84;
            List<ChartPt> pts = null; List<(DateTime D, string Text)> shown = null;
            Canvas cv = null; TextBlock readout = null; int hover = -1;

            // a point in words: when, its value, what else was going on, and what changed since the point before it
            string Say(int i)
            {
                var p = pts[i]; var s = $"{p.D:ddd MMM d, h:mm tt}: {Fmt(p.V)}" + (string.IsNullOrEmpty(p.More) ? "" : " - " + p.More);
                var prev = i > 0 ? pts[i - 1].D : DateTime.MinValue;
                var ch = mk.Where(m => m.D > prev && m.D <= p.D).Select(m => m.Text).Where(x => p.More == null || !p.More.Contains(x)).ToList();   // (not what the point says already)
                return ch.Count > 0 ? s + $" (changed: {string.Join(", ", ch)})" : s;
            }
            string Rest() => "Latest " + Say(pts.Count - 1);

            void DrawCanvas()
            {
                cv.Children.Clear(); cv.Width = W;
                var vals = pts.Select(p => p.V).ToList(); double lo = vals.Min(), hi = vals.Max(), usual = Median(vals);
                if (hi - lo < minSpan) { var mid = (hi + lo) / 2; hi = mid + minSpan / 2; lo = mid - minSpan / 2; }
                var pad = (hi - lo) * 0.12; lo -= pad; hi += pad;
                long t0 = pts[0].D.Ticks, t1 = pts[pts.Count - 1].D.Ticks; if (t1 == t0) t1 = t0 + 1;
                double X(DateTime d) => (d.Ticks - t0) / (double)(t1 - t0) * (W - 12) + 6; double Y(double v) => H - 4 - (v - lo) / (hi - lo) * (H - 8);
                foreach (var gy in new[] { 4, H - 4 }) cv.Children.Add(new Sh.Line { X1 = 0, X2 = W, Y1 = gy, Y2 = gy, Stroke = B("Border"), StrokeThickness = 1 });   // recessive frame lines
                var u = Y(usual); cv.Children.Add(new Sh.Line { X1 = 0, X2 = W, Y1 = u, Y2 = u, Stroke = B("Sub"), StrokeThickness = 1, StrokeDashArray = new DoubleCollection { 4, 3 }, Opacity = 0.5 });   // the usual level
                foreach (var m in shown)   // something changed here: a dashed upright line, its words on hover
                {
                    var x = X(m.D);
                    cv.Children.Add(new Sh.Line { X1 = x, X2 = x, Y1 = 4, Y2 = H - 4, Stroke = B("Warn"), StrokeThickness = 1, StrokeDashArray = new DoubleCollection { 2, 3 }, Opacity = 0.7 });
                    var tip = new Sh.Polygon { Points = new PointCollection { new Point(x - 4, 0), new Point(x + 4, 0), new Point(x, 5) }, Fill = B("Warn"), ToolTip = $"{m.D:MMM d}: {m.Text}" };
                    cv.Children.Add(tip);
                }
                var line = new Sh.Polyline { Stroke = B("Chart"), StrokeThickness = 2, StrokeLineJoin = PenLineJoin.Round, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, IsHitTestVisible = false };
                foreach (var p in pts) line.Points.Add(new Point(X(p.D), Y(p.V)));
                cv.Children.Add(line);
                var bg = (SolidColorBrush)new BrushConverter().ConvertFromString(Theme.C["Bg"]);
                Sh.Ellipse Dot(ChartPt p, double size, bool ring)
                {
                    var e = ring ? new Sh.Ellipse { Width = size, Height = size, Stroke = B("Chart"), StrokeThickness = 2, IsHitTestVisible = false }
                                 : new Sh.Ellipse { Width = size, Height = size, Fill = B("Chart"), Stroke = bg, StrokeThickness = 2, IsHitTestVisible = false };
                    Canvas.SetLeft(e, X(p.D) - size / 2); Canvas.SetTop(e, Y(p.V) - size / 2); return e;
                }
                cv.Children.Add(Dot(pts[pts.Count - 1], 10, false));   // the current value, ringed
                var picked = sel?.Key == null ? null : pts.FirstOrDefault(p => p.Key == sel.Key);
                if (picked != null && picked != pts[pts.Count - 1]) cv.Children.Add(Dot(picked, 15, true));   // the session opened below
                if (hover >= 0 && hover < pts.Count)
                {
                    var hx = X(pts[hover].D);
                    cv.Children.Add(new Sh.Line { X1 = hx, X2 = hx, Y1 = 4, Y2 = H - 4, Stroke = B("Sub"), StrokeThickness = 1, Opacity = 0.6, IsHitTestVisible = false });
                    cv.Children.Add(Dot(pts[hover], 9, false));
                }
            }
            int Nearest(double x)
            {
                long t0 = pts[0].D.Ticks, t1 = Math.Max(pts[pts.Count - 1].D.Ticks, t0 + 1);
                var t = t0 + (x - 6) / (W - 12) * (t1 - t0); int best = 0;
                for (int i = 1; i < pts.Count; i++) if (Math.Abs(pts[i].D.Ticks - t) < Math.Abs(pts[best].D.Ticks - t)) best = i;
                return best;
            }
            void Hover(int i) { hover = i; readout.Text = i >= 0 ? Say(i) : Rest(); readout.Foreground = i >= 0 ? B("Text") : B("Sub"); DrawCanvas(); }
            void Pick(int i) { if (click == null || i < 0) return; sel?.Set(pts[i].Key); click(pts[i]); }

            void Draw()
            {
                sp.Children.Clear(); hover = -1;
                pts = range == "All" ? all : all.Where(p => p.D >= last.D.AddDays(range == "7 days" ? -7 : -30)).ToList();
                if (pts.Count < 2) pts = all.Skip(all.Count - 2).ToList();
                shown = mk.Where(m => m.D > pts[0].D && m.D <= pts[pts.Count - 1].D).ToList();
                var vals = pts.Select(p => p.V).ToList(); var usual = Median(vals);
                var hero = new DockPanel();
                if (ranged)
                {
                    // 7 days / 30 days / All: the one shown in bold, the others links
                    var rt = new TextBlock { FontSize = 11.5, VerticalAlignment = VerticalAlignment.Bottom, Margin = Ui.Th("0,0,0,6"), Foreground = B("Sub") };
                    for (int k = 0; k < RangeNames.Length; k++)
                    {
                        var name = RangeNames[k]; if (k > 0) rt.Inlines.Add(new Run("  ·  "));
                        if (name == range) rt.Inlines.Add(new Run(name) { FontWeight = FontWeights.SemiBold, Foreground = B("Text") });
                        else { var hl = new Hyperlink(new Run(name)) { Foreground = B("Accent"), TextDecorations = null }; hl.Click += (s, e) => SetRange(name); AutomationProperties.SetName(hl, $"{title}: show {name}"); rt.Inlines.Add(hl); }
                    }
                    DockPanel.SetDock(rt, Dock.Right); hero.Children.Add(rt);
                }
                var hv = new StackPanel { Orientation = Orientation.Horizontal };
                hv.Children.Add(Ui.Text(Fmt(last.V), B("Text"), 26, FontWeights.SemiBold, "0"));
                var us = Ui.Text("   usual " + Fmt(usual), B("Sub"), 12, null, "0,0,0,5"); us.VerticalAlignment = VerticalAlignment.Bottom; hv.Children.Add(us);
                hero.Children.Add(hv); sp.Children.Add(hero);
                // the canvas: as wide as its card (redrawn when that changes); the mouse or the arrow keys read a point
                var host = new Grid { Margin = Ui.Th("0,10,0,0") };
                cv = new Canvas { Width = W, Height = H, HorizontalAlignment = HorizontalAlignment.Left, Background = Brushes.Transparent, Focusable = true, FocusVisualStyle = null, ClipToBounds = false };
                AutomationProperties.SetName(cv, $"{title} chart - the arrow keys read each point{(click != null ? ", Enter opens it" : "")}");
                if (click != null) cv.Cursor = Cursors.Hand;
                cv.MouseMove += (s, e) => { var i = Nearest(e.GetPosition(cv).X); if (i != hover) Hover(i); };
                cv.MouseLeave += (s, e) => Hover(-1);
                cv.MouseLeftButtonUp += (s, e) => { cv.Focus(); Pick(Nearest(e.GetPosition(cv).X)); };
                cv.KeyDown += (s, e) =>
                {
                    if (e.Key == Key.Left) { Hover(Math.Max(0, (hover < 0 ? pts.Count : hover) - 1)); e.Handled = true; }
                    else if (e.Key == Key.Right) { Hover(Math.Min(pts.Count - 1, hover + 1)); e.Handled = true; }
                    else if ((e.Key == Key.Enter || e.Key == Key.Space) && hover >= 0) { Pick(hover); e.Handled = true; }
                };
                cv.LostKeyboardFocus += (s, e) => { if (!cv.IsMouseOver) Hover(-1); };
                cv.DataContext = new ChartCtl { Hover = i => { Hover(i); return readout.Text; }, Click = Pick, Range = SetRange, Count = pts.Count };
                host.Children.Add(cv);
                host.SizeChanged += (s, e) => { var w = Math.Max(200, Math.Floor(e.NewSize.Width)); if (Math.Abs(w - W) > 6) { W = w; DrawCanvas(); } };
                sp.Children.Add(host);
                readout = new TextBlock { FontSize = 11.5, TextWrapping = TextWrapping.Wrap, Foreground = B("Sub"), Margin = Ui.Th("0,6,0,0"), MinHeight = 32, Text = Rest() };
                var axis = new DockPanel { Margin = Ui.Th("0,4,0,0") };
                var r = Ui.Text(pts[pts.Count - 1].D.ToString("MMM d"), B("Sub"), 11, null, "0"); DockPanel.SetDock(r, Dock.Right); axis.Children.Add(r);
                axis.Children.Add(Ui.Text($"{pts[0].D:MMM d}   ·   range {Fmt(vals.Min())} - {Fmt(vals.Max())}", B("Sub"), 11, null, "0"));
                sp.Children.Add(axis); sp.Children.Add(readout);
                DrawCanvas();
                sp.Tag = $"CHART: {title} | {pts.Count} points, now {Fmt(last.V)}, usual {Fmt(usual)}" +
                    (ranged ? $" | ranges: {string.Join(", ", RangeNames.Select(n => n == range ? n + "*" : n))}" : "") +
                    (shown.Count > 0 ? $" | marks: {string.Join("; ", shown.Select(m => m.Text))}" : "") +
                    (click != null ? " | click opens a session" : "") + $" | {Rest()}";
            }
            void SetRange(string name) { range = name; rangeOf[title] = name; Draw(); }
            if (sel != null) sel.Changed += () => { if (cv != null) DrawCanvas(); };
            Draw();
            return card;
        }
    }
}
