using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
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
    //   CONTRAST words too faint against what is behind them (WCAG AA: 4.5:1, large text and icons 3:1)
    //   DASH     a wrapped line ending in ' -', which reads like it was cut off
    // (10/25, the owner: "more audits like this to ensure there are no visual bugs". The window sits off the screen; the
    // chat is never started - PCKIT_IN_TESTS. PCKIT_THEME=light|dark picks the theme.)
    public partial class MainWindow
    {
        static readonly string[] AuditPages = { "Welcome", "Home", "Status", "Activity/Checks", "Activity/Stability", "Activity/Trends", "Activity/Performance", "Activity/Storage", "Activity/Alerts", "Settings/General", "Settings/Windows", "Settings/Tools", "Tour" };

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
                        var p = key.Split('/'); tourOver.Visibility = Visibility.Collapsed;
                        if (key == "Tour") ShowTour(0); else ShowPage(p[0], p.Length > 1 ? p[1] : null);   // (the tour's card over Home, on its own - not left over every page)
                        Draw(true); Pump(); UpdateLayout(); Pump();
                        var name = $"{theme}-{(chat ? "chat-" : "")}{w}-{key.Replace('/', '-')}";
                        foreach (var f in Check((FrameworkElement)Content)) o.Add($"AUDIT {name}: {f}");
                        if (shots) { Save((FrameworkElement)Content, Path.Combine(dir, name + ".png")); Save(Body, Path.Combine(dir, name + "-full.png")); }
                    }
                }
            // the chat with a sample conversation, a draft and files: alone where it fills the window (under 900 px), beside
            // Home from there on (10/27 - the wide chat's box had only ever been audited empty)
            var drafts = 0; var beside = 0;
            foreach (var w in widths)
            {
                Width = w; Height = height; ShowChat(true); ChatList.Children.Clear();
                if (w >= 900) { tourOver.Visibility = Visibility.Collapsed; ShowPage("Home", null); Draw(true); }
                AddItem("user", "Why is my PC stuttering in Call of Duty? Attached: C:\\Windows\\win.ini");
                AddItem("tool", "Reading game-perf.json"); AddItem("tool", "Running health-check.ps1");
                AddItem("text", "Your stutter comes from the new graphics driver - rolling it back fixes it.\n\n## What I found\n- **1% lows** dropped from 144 to 98 fps after the driver update, in every match since Thursday.\n  - Only in Call of Duty; NBA 2K is unchanged.\n- See [the driver notes](https://example.com/notes) and `C:\\Windows\\System32`.\n\n| Game | Before | After |\n|---|---|---|\n| Call of Duty | 187 | 171 |\n\n## What to do\n1. Close the game.\n2. Click **Undo the driver** on Home - it takes about two minutes and needs no restart.\n\n> The new driver comes back by itself once NVIDIA fixes it.\n\n---\n```\nnvidia-smi -q\n```");
                AddItem("error", "Invalid API key · Please run /login");
                // a half-typed answer that wraps past the box's MaxHeight, and files going with it (a long name trims)
                ChatInput.Text = "It started after Thursday's update, I think. Before that the game held 187 fps all match.\nNow it drops in the gulag and when I turn fast, and the 1% lows feel worse than the number says.\nI also moved the game to D: last week - could that be it? Here are two screenshots and the log:\nIt's the same on every map, with or without Discord open.";
                attach.Clear(); attach.AddRange(new[] { @"C:\Users\Demo\.claude\chat-attachments\screenshot-2026-10-27-0412.png", @"C:\Users\Demo\Pictures\Call of Duty stutter in the gulag after the driver update.jpg", @"C:\Users\Demo\Documents\game-perf.json" }); UpdateAttach();
                Pump(); UpdateLayout(); Pump(); drafts++; if (w >= 900) beside++;
                var name = $"{theme}-{(w >= 900 ? "chatdraft" : "chatonly")}-{w}";
                foreach (var f in Check((FrameworkElement)Content)) o.Add($"AUDIT {name}: {f}");
                if (shots) Save((FrameworkElement)Content, Path.Combine(dir, name + ".png"));
                ChatInput.Text = ""; ClearAttach();
            }
            ShowChat(false); Hide();
            o.Add($"AUDIT DONE: {theme}, widths {string.Join(",", widths)} - {o.Count} finding(s), contrast of {contrastChecked} texts checked - pages: {string.Join(" ", AuditPages)} - chat with a draft and files: {drafts} width(s), {beside} beside a page");
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
                    else if (CutByParent(t2, root) is string cut) found.Add($"CLIP {Name(e)} {cut}");
                }
                else if (CutByParent(e, root) is string cut) found.Add($"CLIP {Name(e)} {cut}");
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
            // CONTRAST: words against what's behind them under WCAG AA - 4.5:1, 3:1 for large text and icons (10/26)
            foreach (var t in all.OfType<TextBlock>())
            {
                if (string.IsNullOrWhiteSpace(t.Text) || !t.IsEnabled || !(t.Foreground is SolidColorBrush fg)) continue;   // (switched-off controls are exempt)
                contrastChecked++;
                var icon = IsIcon(t); var large = icon || t.FontSize >= 24 || t.FontSize >= 18.66 && t.FontWeight.ToOpenTypeWeight() >= 600;
                var worst = Behind(t).Select(bg => Ratio(Over(fg.Color, Fade(t), bg), bg)).DefaultIfEmpty(21).Min();
                if (worst + 0.05 < (large ? 3 : 4.5)) found.Add($"CONTRAST {Name(t)} {worst:0.0}:1, needs {(large ? 3 : 4.5)}:1");
                // DASH: a line that wraps right after ' -' (10/28)
                if (DashEnd(t) is string dash) found.Add($"DASH {Name(t)} breaks after the dash: '{dash}'");
                // LONEMORE: a setting's 'More' link wrapped onto a line of its own (10/28)
                if (LoneMore(t)) found.Add($"LONEMORE {Name(t)} 'More' sits alone on the last line");
            }
            return found.Distinct();
        }
        int contrastChecked;
        static bool IsIcon(TextBlock t) => t.FontFamily.Source.IndexOf("Icons", StringComparison.OrdinalIgnoreCase) >= 0 || t.FontFamily.Source.IndexOf("MDL2", StringComparison.OrdinalIgnoreCase) >= 0;
        // the opacity it's drawn with: its own and every parent's
        static double Fade(DependencyObject d) { double o = 1; for (var p = d; p != null; p = VisualTreeHelper.GetParent(p)) if (p is UIElement u) o *= u.Opacity; return o; }
        // the colors behind an element: the window's background with every see-through layer above it laid on top (a
        // gradient: each of its ends - the text may sit on either)
        static List<Color> Behind(DependencyObject d)
        {
            var layers = new List<Brush>();
            for (var p = d; p != null; p = VisualTreeHelper.GetParent(p))
            {
                var b = p is Border bd ? bd.Background : p is Panel pn ? pn.Background : p is TextBlock tb ? tb.Background : null;
                if (b != null) layers.Insert(0, b);
            }
            var o = new List<Color> { Theme.B["Bg"].Color };
            foreach (var b in layers)
            {
                var cs = b is SolidColorBrush s ? new[] { s.Color } : b is GradientBrush g ? g.GradientStops.Select(x => x.Color).ToArray() : new Color[0];
                if (cs.Length == 0) continue;   // (an image or a pattern: can't be told)
                o = o.SelectMany(under => cs.Select(c => Over(c, b.Opacity, under))).Distinct().ToList();
            }
            return o;
        }
        static Color Over(Color c, double fade, Color under)
        {
            var a = c.A / 255.0 * fade; byte M(byte x, byte y) => (byte)Math.Round(x * a + y * (1 - a));
            return Color.FromRgb(M(c.R, under.R), M(c.G, under.G), M(c.B, under.B));
        }
        internal static double Ratio(Color a, Color b)
        {
            double L(Color c) { double Ch(byte v) { var x = v / 255.0; return x <= 0.04045 ? x / 12.92 : Math.Pow((x + 0.055) / 1.055, 2.4); } return 0.2126 * Ch(c.R) + 0.7152 * Ch(c.G) + 0.0722 * Ch(c.B); }
            double la = L(a), lb = L(b); return (Math.Max(la, lb) + 0.05) / (Math.Min(la, lb) + 0.05);
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
        // a wrapped line that ends in ' -': the break falls between a dash and the word after it, so the line reads cut off
        // (10/28: Optimizations' Edge switch '...game launchers need -' / 'stays.', the memory test's note - found by eye).
        // The prefix up to the dash is laid out at the block's width; if one more word makes it a line taller, the line
        // breaks right after the dash. Returns the words before the break, or null.
        // Text made of several Runs (Ui.Rows' values, Linked texts, a bold word) is laid out with each Run's own font (10/28).
        internal static string DashEnd(TextBlock t)
        {
            if (t.TextWrapping == TextWrapping.NoWrap || IsIcon(t)) return null;
            var w = t.ActualWidth - t.Padding.Left - t.Padding.Right; if (w < 20) return null;
            var sb = new System.Text.StringBuilder(); var runs = new List<(int At, int Len, TextElement Of)>();
            if (t.Inlines.Count == 0) sb.Append(t.Text ?? "");
            else if (!Flatten(t.Inlines, sb, runs)) return null;   // (a control inside the text: can't be measured as words)
            var s = sb.ToString(); if (s.IndexOf(" - ", StringComparison.Ordinal) < 0) return null;
            var tf = new Typeface(t.FontFamily, t.FontStyle, t.FontWeight, t.FontStretch);
            double H(int n)
            {
#pragma warning disable CS0618
                var ft = new FormattedText(s.Substring(0, n), System.Globalization.CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, tf, t.FontSize, Brushes.Black) { MaxTextWidth = w };
#pragma warning restore CS0618
                foreach (var r in runs)
                {
                    var len = Math.Min(r.Len, n - r.At); if (len <= 0) continue;
                    ft.SetFontFamily(r.Of.FontFamily, r.At, len); ft.SetFontSize(r.Of.FontSize, r.At, len);
                    ft.SetFontWeight(r.Of.FontWeight, r.At, len); ft.SetFontStyle(r.Of.FontStyle, r.At, len);
                }
                return ft.Height;
            }
            for (int i = s.IndexOf(" - ", StringComparison.Ordinal); i >= 0; i = s.IndexOf(" - ", i + 1, StringComparison.Ordinal))
            {
                var end = s.IndexOfAny(new[] { ' ', '\n' }, i + 3); var next = end < 0 ? s.Substring(i + 3) : s.Substring(i + 3, end - i - 3);
                if (next.Length == 0) continue;
                var pre = s.Substring(0, i + 2);
                if (H(i + 3 + next.Length) > H(i + 2) + 1) { var from = Math.Max(0, pre.Length - 40); return pre.Substring(from).Replace("\n", " ") + " | " + next; }
            }
            return null;
        }
        // a wrapped text ending in a 'More' / 'Less' link that sits on a line of its own: the text without the link is as
        // tall as the text with it minus a line (10/28: Show technical names at 1366, Razer and Logitech's before)
        internal static bool LoneMore(TextBlock t)
        {
            if (t.TextWrapping == TextWrapping.NoWrap || !(t.Inlines.LastInline is Hyperlink)) return false;
            var w = t.ActualWidth - t.Padding.Left - t.Padding.Right; if (w < 20) return false;
            var sb = new System.Text.StringBuilder(); if (!Flatten(t.Inlines, sb, new List<(int, int, TextElement)>())) return false;
            var s = sb.ToString(); if (!s.EndsWith("More") && !s.EndsWith("Less")) return false;
            var tf = new Typeface(t.FontFamily, t.FontStyle, t.FontWeight, t.FontStretch);
#pragma warning disable CS0618
            double H(string x) => new FormattedText(x, System.Globalization.CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, tf, t.FontSize, Brushes.Black) { MaxTextWidth = w }.Height;
#pragma warning restore CS0618
            var before = s.Substring(0, s.Length - 4).TrimEnd(' ', ' ');
            // the link takes an extra line, and a plain space before it lets the break fall right there (no-break spaces
            // carry the last word down with it)
            return before != "" && H(s) > H(before) + H("M") / 2 && s.Substring(before.Length, s.Length - 4 - before.Length).Contains(" ");
        }
        // a TextBlock's Runs as one string, with where each Run sits (Spans and Hyperlinks: their Runs; a LineBreak: '\n')
        static bool Flatten(InlineCollection ins, System.Text.StringBuilder sb, List<(int, int, TextElement)> runs)
        {
            foreach (var x in ins)
            {
                if (x is Run r) { var s = r.Text ?? ""; runs.Add((sb.Length, s.Length, r)); sb.Append(s); }
                else if (x is LineBreak) sb.Append('\n');
                else if (x is Span sp) { if (!Flatten(sp.Inlines, sb, runs)) return false; }
                else return false;
            }
            return true;
        }
        // words or a button that got all the room they asked for, inside a panel that didn't - the panel cuts them off, they
        // have no clip of their own (10/28: Trends' half-width cards at 800 - a line in a sideways StackPanel ran past the
        // DockPanel around it and lost its date). Up to the nearest scroller: past that it's OUTSIDE's to find.
        internal static string CutByParent(FrameworkElement e, Visual root)
        {
            double w = e.ActualWidth, x = 0;
            if (e is TextBlock t && Need(t) is double need && need > 0 && need < w)
            {   // (the words, not the block: a stretched line's empty end may be cut)
                x = t.TextAlignment == TextAlignment.Right ? w - need : t.TextAlignment == TextAlignment.Center ? (w - need) / 2 : 0; w = need;
            }
            if (w < 2) return null;
            Rect r; try { r = e.TransformToAncestor(root).TransformBounds(new Rect(x, 0, w, Math.Max(e.ActualHeight, 1))); } catch { return null; }
            var full = r.Width;
            for (var p = VisualTreeHelper.GetParent(e); p != null && p != root; p = VisualTreeHelper.GetParent(p))
            {
                if (p is ScrollContentPresenter || p is ScrollViewer) break;
                if (!(p is FrameworkElement fe) || !(LayoutInformation.GetLayoutClip(fe) is Geometry g) || g.Bounds.IsEmpty) continue;
                Rect c; try { c = fe.TransformToAncestor(root).TransformBounds(g.Bounds); } catch { continue; }
                var both = Rect.Intersect(r, c); if (both.IsEmpty) return null;   // (out of sight up or down - a fold opening: not cut sideways)
                r = both;
            }
            return r.Width + 1 < full ? $"shows {r.Width:0} of {full:0} px - cut by the panel around it" : null;
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
