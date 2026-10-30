using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;

namespace Messiah
{
    // a line of a card: its words and its level (ok / info / warn / dim) - Get-KitStatus's @{ Text; Level }
    class Line
    {
        public string Text; public string Level;
        public Line(string text, string level = "info") { Text = text ?? ""; Level = level; }
    }

    // dashboard.ps1's building blocks (New-Text, New-Glyph, New-Line, New-Btn, New-Card, New-Tile, New-SwitchRow,
    // New-Rows, New-Section) - the same looks, measures and words
    static class Ui
    {
        static SolidColorBrush B(string k) => Theme.B[k];

        // (body text gets 1.45 lines of room - 10/25, the owner: text "hard to read ... a long list of text"; headings keep their own)
        public static TextBlock Text(string t, Brush brush = null, double size = 14, FontWeight? weight = null, string margin = "0,1,0,1")
        {
            var tb = new TextBlock { Text = t ?? "", TextWrapping = TextWrapping.Wrap, Foreground = brush ?? B("Text"), FontSize = size, FontWeight = weight ?? FontWeights.Normal, Margin = Th(margin) };
            if (size <= 14) { tb.LineHeight = Math.Round(size * 1.45); tb.LineStackingStrategy = LineStackingStrategy.BlockLineHeight; }
            return tb;
        }
        public const double Measure = 760;   // the longest a line of words gets (~95 characters; Fluent asks 50-60 for long reading - 10/25)
        // a row as wide as the card up to the reading width, from the left (a MaxWidth alone centers it - 10/25)
        public static Grid Measured(UIElement e)
        {
            var g = new Grid(); g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MaxWidth = Measure }); g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0.0001, GridUnitType.Star) });
            g.Children.Add(e); return g;
        }   // the longest a line of words gets (~110 characters) - a 2560 px card no longer makes 300-character lines
        // charts or tiles side by side, one under the other when each would get less than ~300 px (10/25 audit: at 480 px
        // the chart titles were cut and the 7 days / 30 days buttons sat on the big number)
        public static UniformGrid Pairs(UniformGrid g)
        {
            var most = g.Columns;
            g.SizeChanged += (s, e) => { var n = Math.Max(1, Math.Min(most, (int)(e.NewSize.Width / 300))); if (g.Columns != n) g.Columns = n; };
            return g;
        }
        public static TextBlock Glyph(string hex, double size = 16, Brush brush = null) =>
            new TextBlock { Text = ((char)Convert.ToInt32(hex, 16)).ToString(), FontFamily = Theme.Icons, FontSize = size, Foreground = brush ?? B("Text"), VerticalAlignment = VerticalAlignment.Center, Tag = "icon" };
        public static Thickness Th(string s) { var p = s.Split(',').Select(x => double.Parse(x, System.Globalization.CultureInfo.InvariantCulture)).ToArray(); return p.Length == 1 ? new Thickness(p[0]) : p.Length == 2 ? new Thickness(p[0], p[1], p[0], p[1]) : new Thickness(p[0], p[1], p[2], p[3]); }

        // a line with its status as an icon (warning, reminder, all fine) instead of colored text: easier to read, the
        // "WARNING:" / "Reminder:" words become the icon
        public static FrameworkElement LineEl(string text, string level)
        {
            text = Kit.FormatLine(Regex.Replace(Regex.Replace(text ?? "", "^- ", "•  "), @"\s{2,}", "  "));
            string glyph = null; Brush gb = null;
            if (Regex.IsMatch(text, @"^(WARNING|FAILED)\b:?\s*") || level == "warn") { glyph = "E7BA"; gb = B("Warn"); text = Regex.Replace(text, @"^WARNING:\s*", ""); }
            else if (Regex.IsMatch(text, @"^Reminder:\s*")) { glyph = "E946"; gb = B("Accent"); text = Regex.Replace(text, @"^Reminder:\s*", ""); }
            else if (level == "ok") { glyph = "E73E"; gb = B("Ok"); }
            if (text.Length > 0) text = char.ToUpper(text[0]) + text.Substring(1);
            var tb = Linked(Text(text, level == "dim" ? B("Sub") : B("Text"), level == "dim" ? 12.5 : 14, null, "0")); tb.MaxWidth = Measure; tb.HorizontalAlignment = HorizontalAlignment.Left;
            // a long explanation (a grey line) shows its first two lines; a click shows it all (10/25: walls of small text)
            if (level == "dim" && text.Length > 200) Fold(tb);
            if (glyph == null) { tb.Margin = Th("0,3,0,3"); return tb; }
            var row = new DockPanel { Margin = Th("0,4,0,4") };
            var g = Glyph(glyph, 14, gb); g.VerticalAlignment = VerticalAlignment.Top; g.Margin = Th("0,2,10,0"); DockPanel.SetDock(g, Dock.Left);
            row.Children.Add(g); row.Children.Add(tb); return row;
        }

        // long words folded to two lines ending in "..."; a click opens them all, another folds them again (the words stay whole
        // underneath - copying, search and the tests read all of them)
        public static void Fold(TextBlock tb)
        {
            tb.TextTrimming = TextTrimming.WordEllipsis; tb.MaxHeight = tb.LineHeight * 2; tb.Cursor = Cursors.Hand; tb.ToolTip = "Click to read all of it";
            tb.MouseLeftButtonUp += (s, e) => { var open = !double.IsInfinity(tb.MaxHeight); tb.MaxHeight = open ? double.PositiveInfinity : tb.LineHeight * 2; tb.ToolTip = open ? "Click to show less" : "Click to read all of it"; };
        }
        public static Button Btn(string glyph, string text, Action click, bool accent = false, bool small = false)
        {
            var sp = new StackPanel { Orientation = Orientation.Horizontal };
            sp.Children.Add(Glyph(glyph, small ? 12 : 14, accent ? B("OnAccent") : B("Text")));
            sp.Children.Add(new TextBlock { Text = text, Margin = Th("8,0,0,0"), VerticalAlignment = VerticalAlignment.Center });
            var b = new Button { Content = sp, ToolTip = text };
            AutomationProperties.SetName(b, text);   // (Narrator reads the words, not the icon)
            b.Style = (Style)Application.Current.FindResource(accent ? "AccentBtn" : small ? "SmallBtn" : "Btn");
            b.Click += (s, e) => { try { click?.Invoke(); } catch (Exception ex) { Shell.Say("Couldn't do that: " + ex.Message); } };
            return b;
        }
        public static Button IconBtn(string glyph, string tip, Action click, bool accent = false)
        {
            var b = new Button { ToolTip = tip, Content = Glyph(glyph, 14, accent ? B("OnAccent") : B("Text")) };
            b.Style = (Style)Application.Current.FindResource(accent ? "AccentBtn" : "Btn"); b.Margin = Th("4,0,0,0"); b.Padding = Th("9,7");
            AutomationProperties.SetName(b, tip);
            if (click != null) b.Click += (s, e) => { try { click(); } catch (Exception ex) { Shell.Say("Couldn't do that: " + ex.Message); } };
            return b;
        }

        // a card: a title with its icon chip, lines (or ready elements), buttons under them. calm: warn lines in the normal
        // text color (long text, the header says it)
        // a card that spans all columns on a wide window (a page's summary, a timeline)
        public static Border Wide(Border card) { if (card.Tag is CardInfo ci) ci.Wide = true; return card; }
        public static Border Card(string title, string glyph, IEnumerable<object> lines, IEnumerable<UIElement> buttons = null, bool calm = false)
        {
            var card = new Border { Background = B("Card"), BorderBrush = B("Border"), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12), Padding = Th("22,18"), Margin = Th("0,0,0,14") };
            var sp = new StackPanel();
            if (!string.IsNullOrEmpty(title))
            {
                var hd = new StackPanel { Orientation = Orientation.Horizontal, Margin = Th("0,0,0,10") };
                if (glyph != null)
                {
                    var chip = new Border { Width = 28, Height = 28, CornerRadius = new CornerRadius(8), Background = Theme.Tint(B("Accent"), 0x26), VerticalAlignment = VerticalAlignment.Center };
                    var cg = Glyph(glyph, 14, B("Accent")); cg.HorizontalAlignment = HorizontalAlignment.Center; chip.Child = cg;
                    hd.Children.Add(chip);
                }
                var t = Text(title, B("Text"), 16, FontWeights.SemiBold, "0"); t.VerticalAlignment = VerticalAlignment.Center; t.FontFamily = Theme.Display; if (glyph != null) t.Margin = Th("12,0,0,0");
                hd.Children.Add(t); sp.Children.Add(hd);
            }
            foreach (var l in lines ?? Enumerable.Empty<object>())
            {
                if (l is UIElement el) { sp.Children.Add(el); continue; }
                if (l is Line ln) sp.Children.Add(LineEl(ln.Text, calm && ln.Level == "warn" ? "info" : ln.Level));
            }
            var bl = buttons?.Where(x => x != null).ToList();
            if (bl != null && bl.Count > 0)
            {
                var wp = new WrapPanel { Margin = Th("0,14,0,-8") };
                foreach (var b in bl) wp.Children.Add(b);
                sp.Children.Add(wp);
            }
            card.Child = sp; card.Tag = new CardInfo { Title = title }; return card;
        }

        // a group of settings, Windows 11's way (10/26): the group's title, then each setting on a card of its own - its
        // icon, title and one line, the switch on the right (SettingsCard) - instead of one long card of switches
        public static Border Group(string title, string glyph, IEnumerable<UIElement> rows)
        {
            var sp = new StackPanel();
            var hd = new StackPanel { Orientation = Orientation.Horizontal, Margin = Th("2,0,0,10") };
            var chip = new Border { Width = 28, Height = 28, CornerRadius = new CornerRadius(8), Background = Theme.Tint(B("Accent"), 0x26), VerticalAlignment = VerticalAlignment.Center };
            var cg = Glyph(glyph, 14, B("Accent")); cg.HorizontalAlignment = HorizontalAlignment.Center; chip.Child = cg; hd.Children.Add(chip);
            var t = Text(title, B("Text"), 16, FontWeights.SemiBold, "12,0,0,0"); t.VerticalAlignment = VerticalAlignment.Center; t.FontFamily = Theme.Display; hd.Children.Add(t);
            sp.Children.Add(hd);
            foreach (var r in rows)
            {
                if (r is FrameworkElement fe) fe.Margin = Th("0");
                sp.Children.Add(new Border { Background = B("Card"), BorderBrush = B("Border"), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8), Padding = Th("16,12"), Margin = Th("0,0,0,4"), Child = r, Tag = "setting" });
            }
            return new Border { Margin = Th("0,0,0,14"), Child = sp, Tag = new CardInfo { Title = title } };
        }

        // "here": the card Shell.Open scrolled to - its border in the accent color for half a second, then back to the
        // usual border over a second (a Group has no border of its own: its settings' cards flash). Returns how many
        // borders flash. The card's own brush comes back after, so a theme change later still recolors it
        public static int Flash(Border card)
        {
            var bs = card.BorderThickness.Top > 0 ? new List<Border> { card }
                : ((card.Child as Panel)?.Children.OfType<Border>().Where(x => "setting".Equals(x.Tag)).ToList() ?? new List<Border>());
            var fade = SystemParameters.ClientAreaAnimation ? 1000 : 0;   // (animations off in Windows: the accent, then straight back)
            foreach (var b in bs)
            {
                var was = b.BorderBrush; var to = (was as SolidColorBrush)?.Color ?? B("Border").Color;
                var br = new SolidColorBrush(B("Accent").Color); b.BorderBrush = br;
                var a = new ColorAnimationUsingKeyFrames { Duration = TimeSpan.FromMilliseconds(600 + fade) };
                a.KeyFrames.Add(new DiscreteColorKeyFrame(B("Accent").Color, KeyTime.FromTimeSpan(TimeSpan.Zero)));
                a.KeyFrames.Add(new DiscreteColorKeyFrame(B("Accent").Color, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(600))));
                a.KeyFrames.Add(fade > 0 ? (ColorKeyFrame)new EasingColorKeyFrame(to, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(600 + fade)), new QuadraticEase())
                    : new DiscreteColorKeyFrame(to, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(600))));
                a.Completed += (s, e) => { if (b.BorderBrush == br) b.BorderBrush = was; };
                br.BeginAnimation(SolidColorBrush.ColorProperty, a);
            }
            return bs.Count;
        }

        public static TextBlock Section(string t) => Text(t, B("Sub"), 13, FontWeights.SemiBold, "4,14,0,10");   // a heading between groups of cards

        // a small status tile (Home): a label, the value big, one line under it; a click goes to its page ("Page/Sub")
        public static Border Tile(string glyph, string label, string value, string sub, string level, string go)
        {
            var b = new Border { Background = B("Card"), BorderBrush = B("Border"), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12), Padding = Th("18,14"), Margin = Th("0,0,12,12") };
            var sp = new StackPanel();
            var hd = new StackPanel { Orientation = Orientation.Horizontal };
            hd.Children.Add(Glyph(glyph, 14, B("Accent"))); var l = Text(label, B("Sub"), 12, null, "8,0,0,0"); l.VerticalAlignment = VerticalAlignment.Center; hd.Children.Add(l);
            sp.Children.Add(hd);
            var v = Text(value, level == "info" ? B("Text") : Theme.Level(level), 22, FontWeights.SemiBold, "0,8,0,0"); v.FontFamily = Theme.Display; sp.Children.Add(v);
            sp.Children.Add(Text(sub, B("Sub"), 12, null, "0,2,0,0"));
            b.Child = sp;
            b.Tag = new CardInfo { Title = label, Tile = $"{label}: {value} / {sub}" };
            Opens(b, go, $"{label} - {value}. {sub}");
            return b;
        }

        // a tile (or any card) that opens go on click / Enter - a page, or a page and its card: "Activity/Storage#Drives"
        // (10/27: Stability's tiles open its list the same way as Home's)
        public static void Opens(Border b, string go, string name)
        {
            if (go == null) return;
            b.Cursor = Cursors.Hand; b.ToolTip = "Open " + PageName(go); b.Focusable = true; b.FocusVisualStyle = null;
            AutomationProperties.SetName(b, name);
            Action open = () => Shell.Open(go);
            b.GotKeyboardFocus += (s, e) => b.Background = B("CardHover"); b.LostKeyboardFocus += (s, e) => b.Background = B("Card");
            b.KeyDown += (s, e) => { if (e.Key == Key.Return || e.Key == Key.Space) { open(); e.Handled = true; } };
            b.MouseEnter += (s, e) => b.Background = B("CardHover"); b.MouseLeave += (s, e) => b.Background = B("Card");
            b.MouseLeftButtonUp += (s, e) => open();
            if (b.Tag is CardInfo ci) ci.Go = go;
        }

        // a grey line ending in a link that opens more grey lines under it, and folds them again (10/28: the BIOS card's
        // five update steps were always open). The link's words have no-break spaces, so they wrap as one piece
        public static StackPanel FoldLines(string text, string open, string close, IEnumerable<string> more)
        {
            var sp = new StackPanel();
            var tb = LineEl(text, "dim") as TextBlock; sp.Children.Add(tb);
            var body = new StackPanel { Visibility = Visibility.Collapsed, Tag = "more" };
            foreach (var m in more) body.Children.Add(LineEl(m, "dim"));
            var link = new System.Windows.Documents.Hyperlink(new System.Windows.Documents.Run(open.Replace(' ', ' '))) { Foreground = B("Accent"), TextDecorations = null };
            AutomationProperties.SetName(link, open);
            link.Click += (x, e) => { var o = body.Visibility != Visibility.Visible; body.Visibility = o ? Visibility.Visible : Visibility.Collapsed; ((System.Windows.Documents.Run)link.Inlines.FirstInline).Text = (o ? close : open).Replace(' ', ' '); };
            tb.Inlines.Add(new System.Windows.Documents.Run("  ")); tb.Inlines.Add(link);
            sp.Children.Add(body); return sp;
        }

        // one line of what it does; the rest (the details, what "off" means) behind "More" - 10/22 audit: three-line
        // descriptions under every switch were a wall of text (PowerToys' settings cards show one line and expand)
        public static (string First, string More) SubLine(string sub)
        {
            var parts = Regex.Split(sub ?? "", @"(?<=\.|\))\s+(?=Off(?: again)?: |Off \(default\): )");
            // (the first stop outside brackets - 10/28: the temperature switch's line ended '... at idle (Games > Performance:')
            var fm = Regex.Matches(parts[0], @"(?<=^.{30,}?[.:])\s+(?=[A-Z(])").Cast<Match>()
                .FirstOrDefault(m => parts[0].Take(m.Index).Count(c => c == '(') == parts[0].Take(m.Index).Count(c => c == ')'));
            var first = fm != null ? parts[0].Substring(0, fm.Index) : parts[0];
            var rest = string.Join(" ", new[] { fm != null ? parts[0].Substring(fm.Index + fm.Length) : "" }.Concat(parts.Skip(1)).Where(x => x != ""));
            return (first, rest);
        }

        // a setting with a switch on the right; what it does, then what "off" means on a line of its own
        public static DockPanel SwitchRow(string title, string sub, bool on, Action<CheckBox> click, string tag = null, string glyph = null)
        {
            var r = new DockPanel { Margin = Th("0,0,0,16") };
            var s = new CheckBox { IsChecked = on, VerticalAlignment = VerticalAlignment.Center, Tag = tag, Margin = Th("20,0,0,0") };
            s.Style = (Style)Application.Current.FindResource("Switch"); DockPanel.SetDock(s, Dock.Right);
            AutomationProperties.SetName(s, title); AutomationProperties.SetHelpText(s, sub);
            s.Click += (x, e) => { try { click?.Invoke(s); } catch (Exception ex) { Shell.Say("Couldn't do that: " + ex.Message); } };
            if (glyph != null) { var ic = Glyph(glyph, 18, B("Text")); ic.Margin = Th("0,0,16,0"); ic.Width = 20; DockPanel.SetDock(ic, Dock.Left); r.Children.Add(ic); }   // (in a Group's card)
            var l = new StackPanel { MaxWidth = Measure, HorizontalAlignment = HorizontalAlignment.Left };
            l.Children.Add(Text(title, B("Text"), 14, null, "0"));
            var (first, rest) = SubLine(sub);
            var line = new TextBlock { Foreground = B("Sub"), FontSize = 12, Margin = Th("0,2,0,0"), TextWrapping = TextWrapping.Wrap };
            line.Text = first; Linked(line);   // (a page it names opens it - 'Results: Games > Performance')
            l.Children.Add(line);
            if (rest != "")
            {
                var more = Linked(Text(rest, B("Sub"), 12, null, "0,3,0,0")); more.Visibility = Visibility.Collapsed; more.Tag = "more";
                var link = new System.Windows.Documents.Hyperlink(new System.Windows.Documents.Run("More")) { Foreground = B("Accent"), TextDecorations = null };
                AutomationProperties.SetName(link, "More about " + title);
                link.Click += (x, e) => { var open = more.Visibility != Visibility.Visible; more.Visibility = open ? Visibility.Visible : Visibility.Collapsed; ((System.Windows.Documents.Run)link.Inlines.FirstInline).Text = open ? "Less" : "More"; };
                // (no-break spaces: 'More' wraps with the line's last word, never alone on a line of its own - 10/28: Show
                // technical names at 1366)
                line.Inlines.Add(new System.Windows.Documents.Run("  ")); line.Inlines.Add(link);
                l.Children.Add(more);
            }
            r.Children.Add(s); r.Children.Add(l); return r;
        }

        // label | value table; rows are (label, value, level). go: a row's page ("Page/Sub", "#Card" to scroll to a card) -
        // the whole row opens it, with a chevron on the right like a Windows settings row (10/26: Home's This week). go gets
        // the row's label and value (an alert's time says nothing about where it goes - its words do, 10/27). align: tables
        // with the same name share one label width, so two tables on a page line up (Alerts' two cards, 10/27 - the window
        // is the size scope)
        public static Grid Rows(IEnumerable<(string Label, string Value, string Level)> rows, Func<string, string, string> go = null, string align = null)
        {
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto, SharedSizeGroup = align }); g.ColumnDefinitions.Add(new ColumnDefinition());
            if (go != null) g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            int i = 0;
            foreach (var p in rows)
            {
                g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                var a = Text(p.Label, B("Sub"), 13, null, "0,5,24,5"); Grid.SetRow(a, i);
                var b = Text(Kit.FormatLine(p.Value), Theme.Level(p.Level), 14, null, "0,5,0,5"); Grid.SetRow(b, i); Grid.SetColumn(b, 1); b.MaxWidth = Measure; b.HorizontalAlignment = HorizontalAlignment.Left;
                var to = go?.Invoke(p.Label, p.Value);
                if (to != null)
                {
                    var where = PageName(to);
                    var hit = new Border { Background = Brushes.Transparent, CornerRadius = new CornerRadius(6), Margin = Th("-8,1,-8,1"), Cursor = Cursors.Hand, Focusable = true, FocusVisualStyle = null, ToolTip = "Open " + where, Tag = "go:" + to };
                    Grid.SetRow(hit, i); Grid.SetColumnSpan(hit, 3); AutomationProperties.SetName(hit, $"{p.Label}: {p.Value}. Open {where}");
                    Action open = () => Shell.Open(to);
                    hit.MouseEnter += (s, e) => hit.Background = B("CardHover"); hit.MouseLeave += (s, e) => { if (!hit.IsKeyboardFocused) hit.Background = Brushes.Transparent; };
                    hit.GotKeyboardFocus += (s, e) => hit.Background = B("CardHover"); hit.LostKeyboardFocus += (s, e) => hit.Background = Brushes.Transparent;
                    hit.KeyDown += (s, e) => { if (e.Key == Key.Return || e.Key == Key.Space) { open(); e.Handled = true; } };
                    hit.MouseLeftButtonUp += (s, e) => open();
                    a.IsHitTestVisible = b.IsHitTestVisible = false;   // (the row takes the click, the words lie on it)
                    var c = Glyph("E76C", 11, B("Sub")); c.Margin = Th("12,0,0,0"); c.IsHitTestVisible = false; Grid.SetRow(c, i); Grid.SetColumn(c, 2);
                    g.Children.Add(hit); g.Children.Add(c);
                }
                else if ((p.Value ?? "").Length > 160) Fold(b);   // (a long one - 63 update packages - two lines, a click for the rest)
                g.Children.Add(a); g.Children.Add(b); i++;
            }
            g.Tag = "rows"; return g;
        }
        // "Activity/Performance#Heat and wear" -> "Games > Performance" (the tab and page a row opens, for its tooltip)
        public static string PageName(string go)
        {
            var key = go.Split('#')[0];
            foreach (var t in MainWindow.Tabs) foreach (var pg in t.Pages) if (pg.Key == key) return t.Pages.Length > 1 ? $"{t.Tab} > {pg.Label}" : t.Tab;
            return key;
        }
        // a footer's "Games > Performance" opens that page (10/27: Trends' and Alerts' footers named a page in plain text) -
        // each "Tab > Page" in t becomes a link; the TextBlock's Text stays the same words. Also every LineEl and a switch's
        // words (10/27: 'Settings > Tools > Go back...' under a slower driver, 'Results: Health > Stability')
        public static TextBlock Linked(TextBlock tb)
        {
            var names = MainWindow.Tabs.Where(t => t.Pages.Length > 1).SelectMany(t => t.Pages.Select(pg => (Name: $"{t.Tab} > {pg.Label}", pg.Key))).ToList();
            var text = tb.Text; var at = 0;
            var ms = Regex.Matches(text, string.Join("|", names.Select(n => Regex.Escape(n.Name)))).Cast<Match>().ToList();
            if (ms.Count == 0) return tb;
            tb.Inlines.Clear();
            foreach (var m in ms)
            {
                if (m.Index > at) tb.Inlines.Add(new System.Windows.Documents.Run(text.Substring(at, m.Index - at)));
                var key = names.First(n => n.Name == m.Value).Key;
                var link = new System.Windows.Documents.Hyperlink(new System.Windows.Documents.Run(m.Value)) { Foreground = B("Accent"), TextDecorations = null, ToolTip = "Open " + m.Value, Tag = "go:" + key };
                AutomationProperties.SetName(link, "Open " + m.Value);
                link.Click += (s, e) => Shell.Open(key);
                tb.Inlines.Add(link); at = m.Index + m.Length;
            }
            if (at < text.Length) tb.Inlines.Add(new System.Windows.Documents.Run(text.Substring(at)));
            return tb;
        }

        // a ring with a number or a glyph inside (Home's and Status's headline)
        public static Grid Ring(double size, double stroke, double fontSize, string level, string mid, SolidColorBrush color = null)
        {
            var sb = color ?? Theme.Level(level);
            var ring = new Grid { Width = size, Height = size, VerticalAlignment = VerticalAlignment.Center };
            ring.Children.Add(new Ellipse { Fill = Theme.Tint(sb, 0x1F) });
            ring.Children.Add(new Ellipse { Stroke = sb, StrokeThickness = stroke });
            FrameworkElement m;
            if (Regex.IsMatch(mid, @"^\d+$")) { var t = Text(mid, sb, fontSize, FontWeights.SemiBold, "0"); t.FontFamily = Theme.Display; t.Tag = "icon"; m = t; }   // (Tag icon: the tests read the sentence, not the ring)
            else m = Glyph(mid, fontSize, sb);
            m.HorizontalAlignment = HorizontalAlignment.Center; m.VerticalAlignment = VerticalAlignment.Center; ring.Children.Add(m);
            return ring;
        }
    }
    class CardInfo { public string Title; public string Tile; public string Go; public bool Wide; }   // Wide: across all columns on a wide window (MainWindow.Flow)
}
