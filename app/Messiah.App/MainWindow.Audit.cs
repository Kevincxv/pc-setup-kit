using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace Messiah
{
    // --audit <folder>: every page at window widths from the smallest to a 2560 px screen, with the chat closed and open,
    // drawn whole - the part scrolled out of view too - into PNGs to look at, and what can be checked without looking:
    //   CLIP     words or a button cut off with no "..." (a box narrower than what's in it)
    //   OVERLAP  two buttons or boxes on top of each other
    //   OUTSIDE  something reaching past the right edge of the window or its column
    // (10/25, the owner: "more audits like this to ensure there are no visual bugs". The window sits off the screen; the
    // chat is never started - PCKIT_IN_TESTS. PCKIT_THEME=light|dark picks the theme.)
    public partial class MainWindow
    {
        static readonly string[] AuditPages = { "Welcome", "Home", "Status", "Activity/Checks", "Activity/Stability", "Activity/Trends", "Activity/Performance", "Activity/Storage", "Activity/Alerts", "Settings/General", "Settings/Windows", "Settings/Tools" };

        internal List<string> RunAudit(string dir, int[] widths, int height, bool shots)
        {
            var o = new List<string>(); Directory.CreateDirectory(dir);
            Auditing = true; ShowActivated = false; ShowInTaskbar = false; WindowState = WindowState.Normal; Left = -32000; Top = 0; Width = widths[0]; Height = height;
            Show(); Pump();
            snap = Snapshot.Load(); Pump();
            var theme = Theme.Light ? "light" : "dark";
            foreach (var chat in new[] { false, true })
                foreach (var w in widths)
                {
                    if (chat && w < 700) continue;   // (the chat takes the whole window there - one look is enough: Chat-only below)
                    Width = w; Height = height; ShowChat(chat); Pump();
                    foreach (var key in AuditPages)
                    {
                        if (key == "Welcome") { startPage = "Welcome"; BuildNav(); } else if (startPage == "Welcome") { startPage = null; BuildNav(); }
                        var p = key.Split('/'); ShowPage(p[0], p.Length > 1 ? p[1] : null); Draw(true); Pump(); UpdateLayout(); Pump();
                        var name = $"{theme}-{(chat ? "chat-" : "")}{w}-{key.Replace('/', '-')}";
                        foreach (var f in Check((FrameworkElement)Content)) o.Add($"AUDIT {name}: {f}");
                        if (shots) { Save((FrameworkElement)Content, Path.Combine(dir, name + ".png")); Save(Body, Path.Combine(dir, name + "-full.png")); }
                    }
                }
            // the chat alone, narrow (it fills the window under 900 px), with a sample conversation
            foreach (var w in widths.Where(x => x < 900))
            {
                Width = w; Height = height; ShowChat(true); ChatList.Children.Clear();
                AddItem("user", "Why is my PC stuttering in Call of Duty? Attached: C:\\Windows\\win.ini");
                AddItem("tool", "Reading game-perf.json"); AddItem("tool", "Running health-check.ps1");
                AddItem("text", "Your stutter comes from the new graphics driver - rolling it back fixes it.\n\n## What I found\n- **1% lows** dropped from 144 to 98 fps after the driver update, in every match since Thursday.\n  - Only in Call of Duty; NBA 2K is unchanged.\n- See [the driver notes](https://example.com/notes) and `C:\\Windows\\System32`.\n\n| Game | Before | After |\n|---|---|---|\n| Call of Duty | 187 | 171 |\n\n## What to do\n1. Close the game.\n2. Click **Undo the driver** on Home - it takes about two minutes and needs no restart.\n\n> The new driver comes back by itself once NVIDIA fixes it.\n\n---\n```\nnvidia-smi -q\n```");
                AddItem("error", "Invalid API key · Please run /login");
                Pump();
                var name = $"{theme}-chatonly-{w}";
                foreach (var f in Check((FrameworkElement)Content)) o.Add($"AUDIT {name}: {f}");
                if (shots) Save((FrameworkElement)Content, Path.Combine(dir, name + ".png"));
            }
            ShowChat(false); Hide();
            o.Add($"AUDIT DONE: {theme}, widths {string.Join(",", widths)} - {o.Count} finding(s)");
            return o;
        }
        void Pump()
        {
            for (int i = 0; i < 3; i++)
            {
                var f = new DispatcherFrame(); Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(() => f.Continue = false)); Dispatcher.PushFrame(f);
                UpdateLayout();
            }
        }
        static void Save(FrameworkElement el, string file)
        {
            if (el.ActualWidth < 1 || el.ActualHeight < 1) return;
            var h = Math.Min(el.ActualHeight, 12000);
            var rtb = new RenderTargetBitmap((int)Math.Ceiling(el.ActualWidth), (int)Math.Ceiling(h), 96, 96, PixelFormats.Pbgra32);
            var dv = new DrawingVisual();
            using (var dc = dv.RenderOpen()) { dc.DrawRectangle(Theme.B["Bg"], null, new Rect(0, 0, el.ActualWidth, h)); dc.DrawRectangle(new VisualBrush(el) { Stretch = Stretch.None, ViewboxUnits = BrushMappingMode.Absolute, Viewbox = new Rect(VisualTreeHelper.GetOffset(el).X, VisualTreeHelper.GetOffset(el).Y, el.ActualWidth, el.ActualHeight), AlignmentX = AlignmentX.Left, AlignmentY = AlignmentY.Top }, null, new Rect(0, 0, el.ActualWidth, el.ActualHeight)); }
            rtb.Render(dv);
            var enc = new PngBitmapEncoder(); enc.Frames.Add(BitmapFrame.Create(rtb)); using (var fs = File.Create(file)) enc.Save(fs);
        }

        // the checks: on what's shown (collapsed and hidden parts left out), in the window's own coordinates
        IEnumerable<string> Check(FrameworkElement root)
        {
            var all = new List<FrameworkElement>(); Walk(root, all);
            var found = new List<string>();
            string Name(FrameworkElement e)
            {
                string t = e is TextBlock tb ? tb.Text : e is ContentControl cc ? (cc.Content as string ?? Words(cc)) : e is TextBox bx ? "box:" + (System.Windows.Automation.AutomationProperties.GetName(bx) ?? "") : "";
                if (string.IsNullOrWhiteSpace(t)) t = System.Windows.Automation.AutomationProperties.GetName(e); if (string.IsNullOrWhiteSpace(t)) t = (e.ToolTip as string) ?? e.Name;
                t = (t ?? "").Replace("\n", " "); return $"{e.GetType().Name}[{(t.Length > 50 ? t.Substring(0, 50) + "..." : t)}]";
            }
            Rect R(FrameworkElement e) { try { return e.TransformToAncestor(root).TransformBounds(new Rect(0, 0, e.ActualWidth, e.ActualHeight)); } catch { return Rect.Empty; } }
            // CLIP: arranged smaller than it needs, without its own way of showing that (trimming, wrapping, a scroller)
            foreach (var e in all)
            {
                if (!(e is TextBlock || e is ButtonBase)) continue;
                if (e is TextBlock t && (t.TextTrimming != TextTrimming.None || t.TextWrapping != TextWrapping.NoWrap)) continue;
                var clip = LayoutInformation.GetLayoutClip(e);
                if (clip != null && !clip.Bounds.IsEmpty && (clip.Bounds.Width + 0.5 < e.ActualWidth || clip.Bounds.Height + 0.5 < e.ActualHeight || e.DesiredSize.Width > e.ActualWidth + 1))
                    found.Add($"CLIP {Name(e)} shows {clip.Bounds.Width:0}x{clip.Bounds.Height:0} of {e.ActualWidth:0}x{e.ActualHeight:0}");
                else if (e is TextBlock t2 && t2.ActualWidth > 0)
                {   // (text that needs more room than it got: measured on its own, unconstrained)
                    var need = Need(t2); if (need > t2.ActualWidth + 6) found.Add($"CLIP {Name(e)} needs {need:0} px, has {t2.ActualWidth:0}");   // (a few px: measuring differences, not cut)
                }
            }
            // OVERLAP: controls you click or type in, on top of one another
            var hits = all.Where(e => e is ButtonBase || e is TextBox).Select(e => (E: e, R: R(e))).Where(x => !x.R.IsEmpty && x.R.Width > 2 && x.R.Height > 2).ToList();
            for (int i = 0; i < hits.Count; i++)
                for (int j = i + 1; j < hits.Count; j++)
                {
                    if (IsAncestor(hits[i].E, hits[j].E) || IsAncestor(hits[j].E, hits[i].E)) continue;
                    if (Layer(hits[i].E) != Layer(hits[j].E)) continue;   // (a card floating over the page - the tour, search, a note - covers it on purpose)
                    var x = Rect.Intersect(hits[i].R, hits[j].R);
                    if (!x.IsEmpty && x.Width > 3 && x.Height > 3) found.Add($"OVERLAP {Name(hits[i].E)} and {Name(hits[j].E)} by {x.Width:0}x{x.Height:0}");
                }
            // OUTSIDE: past the window's right edge (things in a sideways scroller left out)
            foreach (var e in all.Where(e => e is TextBlock || e is ButtonBase || e is Border || e is Image))
            {
                var r = R(e); if (r.IsEmpty || r.Width < 2) continue;
                if (r.Right > root.ActualWidth + 1 && !InsideScroller(e, horizontal: true)) found.Add($"OUTSIDE {Name(e)} reaches {r.Right:0} of {root.ActualWidth:0} px");
                // (10/25: the page's own tabs ran past the scrolling area's edge - cut off there, inside the window)
                else if (Viewport(e) is ScrollViewer sv && sv.ComputedHorizontalScrollBarVisibility != Visibility.Visible && R(sv) is Rect vr && !vr.IsEmpty && r.Right > vr.Left + sv.ViewportWidth + 1)
                    found.Add($"OUTSIDE {Name(e)} reaches {r.Right - vr.Left:0} of {sv.ViewportWidth:0} px of its column");
            }
            return found.Distinct();
        }
        static string Words(DependencyObject d)
        {
            var o = new List<string>(); var st = new Stack<DependencyObject>(); st.Push(d);
            while (st.Count > 0) { var x = st.Pop(); if (x is TextBlock t && t.FontFamily.Source.IndexOf("Icons", StringComparison.OrdinalIgnoreCase) < 0 && t.FontFamily.Source.IndexOf("MDL2", StringComparison.OrdinalIgnoreCase) < 0) o.Add(t.Text); for (int i = VisualTreeHelper.GetChildrenCount(x) - 1; i >= 0; i--) st.Push(VisualTreeHelper.GetChild(x, i)); }
            return string.Join(" ", o.Where(s => !string.IsNullOrWhiteSpace(s)));
        }
        static double Need(TextBlock t)
        {
            if (t.Inlines.Count > 1 || string.IsNullOrEmpty(t.Text)) return 0;
#pragma warning disable CS0618
            var ft = new FormattedText(t.Text, System.Globalization.CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, new Typeface(t.FontFamily, t.FontStyle, t.FontWeight, t.FontStretch), t.FontSize, Brushes.Black);
#pragma warning restore CS0618
            return ft.WidthIncludingTrailingWhitespace + t.Padding.Left + t.Padding.Right;
        }
        static void Walk(DependencyObject d, List<FrameworkElement> into)
        {
            if (d is UIElement u && (u.Visibility != Visibility.Visible || u.Opacity < 0.05)) return;
            if (d is FrameworkElement z && ((z.ActualWidth < 1 || z.ActualHeight < 1) && VisualTreeHelper.GetChildrenCount(d) > 0 || LayoutInformation.GetLayoutClip(z) is Geometry g && !g.Bounds.IsEmpty && (g.Bounds.Width < 1 || g.Bounds.Height < 1))) return;   // (a column with no room - the page beside a full-window chat: nothing in it shows)
            if (d is FrameworkElement fe) into.Add(fe);
            if (d is RichTextBox) return;   // (a reply's own document: it wraps)
            for (int i = 0; i < VisualTreeHelper.GetChildrenCount(d); i++) Walk(VisualTreeHelper.GetChild(d, i), into);
        }
        object Layer(DependencyObject d)
        {
            for (var p = d; p != null; p = VisualTreeHelper.GetParent(p)) if (p == tourOver || p == sOver || p == NoteBar || p == ChatMenuPanel) return p;
            return null;
        }
        static bool IsAncestor(DependencyObject a, DependencyObject d) { for (var p = VisualTreeHelper.GetParent(d); p != null; p = VisualTreeHelper.GetParent(p)) if (p == a) return true; return false; }
        static ScrollViewer Viewport(DependencyObject d)
        {
            for (var p = VisualTreeHelper.GetParent(d); p != null; p = VisualTreeHelper.GetParent(p))
            {
                if (p is ScrollBar) return null;   // (the scroll bar itself sits beside the area it scrolls)
                if (p is ScrollViewer sv && !(sv.TemplatedParent is TextBoxBase)) return sv;
            }
            return null;
        }
        static bool InsideScroller(DependencyObject d, bool horizontal = false)
        {
            for (var p = VisualTreeHelper.GetParent(d); p != null; p = VisualTreeHelper.GetParent(p))
                if (p is ScrollViewer sv && (!horizontal || sv.HorizontalScrollBarVisibility != ScrollBarVisibility.Disabled && sv.ComputedHorizontalScrollBarVisibility == Visibility.Visible)) return true;
            return false;
        }
    }
}
