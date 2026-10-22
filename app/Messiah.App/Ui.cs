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

        public static TextBlock Text(string t, Brush brush = null, double size = 14, FontWeight? weight = null, string margin = "0,1,0,1") =>
            new TextBlock { Text = t ?? "", TextWrapping = TextWrapping.Wrap, Foreground = brush ?? B("Text"), FontSize = size, FontWeight = weight ?? FontWeights.Normal, Margin = Th(margin) };
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
            var tb = Text(text, level == "dim" ? B("Sub") : B("Text"), level == "dim" ? 12 : 14, null, "0");
            if (glyph == null) { tb.Margin = Th("0,3,0,3"); return tb; }
            var row = new DockPanel { Margin = Th("0,4,0,4") };
            var g = Glyph(glyph, 14, gb); g.VerticalAlignment = VerticalAlignment.Top; g.Margin = Th("0,2,10,0"); DockPanel.SetDock(g, Dock.Left);
            row.Children.Add(g); row.Children.Add(tb); return row;
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
            if (go != null)
            {
                b.Cursor = Cursors.Hand; b.ToolTip = "Open"; b.Focusable = true; b.FocusVisualStyle = null;
                AutomationProperties.SetName(b, $"{label} - {value}. {sub}");
                Action open = () => { var p = go.Split(new[] { '/' }, 2); Shell.ShowPage(p[0], p.Length > 1 ? p[1] : null); };
                b.GotKeyboardFocus += (s, e) => b.Background = B("CardHover"); b.LostKeyboardFocus += (s, e) => b.Background = B("Card");
                b.KeyDown += (s, e) => { if (e.Key == Key.Return || e.Key == Key.Space) { open(); e.Handled = true; } };
                b.MouseEnter += (s, e) => b.Background = B("CardHover"); b.MouseLeave += (s, e) => b.Background = B("Card");
                b.MouseLeftButtonUp += (s, e) => open();
            }
            b.Tag = new CardInfo { Title = label, Tile = $"{label}: {value} / {sub}" };
            return b;
        }

        // a setting with a switch on the right; what it does, then what "off" means on a line of its own
        public static DockPanel SwitchRow(string title, string sub, bool on, Action<CheckBox> click, string tag = null)
        {
            var r = new DockPanel { Margin = Th("0,0,0,16") };
            var s = new CheckBox { IsChecked = on, VerticalAlignment = VerticalAlignment.Center, Tag = tag, Margin = Th("20,0,0,0") };
            s.Style = (Style)Application.Current.FindResource("Switch"); DockPanel.SetDock(s, Dock.Right);
            AutomationProperties.SetName(s, title); AutomationProperties.SetHelpText(s, sub);
            s.Click += (x, e) => { try { click?.Invoke(s); } catch (Exception ex) { Shell.Say("Couldn't do that: " + ex.Message); } };
            var l = new StackPanel();
            l.Children.Add(Text(title, B("Text"), 14, null, "0"));
            // one line of what it does; the rest (the details, what "off" means) behind "More" - 10/22 audit: three-line
            // descriptions under every switch were a wall of text (PowerToys' settings cards show one line and expand)
            var parts = Regex.Split(sub ?? "", @"(?<=\.|\))\s+(?=Off(?: again)?: |Off \(default\): )");
            var fm = Regex.Match(parts[0], @"^(.{30,}?[.:])\s+(?=[A-Z(])(.+)$");
            var first = fm.Success ? fm.Groups[1].Value : parts[0];
            var rest = string.Join(" ", new[] { fm.Success ? fm.Groups[2].Value : "" }.Concat(parts.Skip(1)).Where(x => x != ""));
            var line = new TextBlock { Foreground = B("Sub"), FontSize = 12, Margin = Th("0,2,0,0"), TextWrapping = TextWrapping.Wrap };
            line.Inlines.Add(new System.Windows.Documents.Run(first));
            l.Children.Add(line);
            if (rest != "")
            {
                var more = Text(rest, B("Sub"), 12, null, "0,3,0,0"); more.Visibility = Visibility.Collapsed; more.Tag = "more";
                var link = new System.Windows.Documents.Hyperlink(new System.Windows.Documents.Run("More")) { Foreground = B("Accent"), TextDecorations = null };
                AutomationProperties.SetName(link, "More about " + title);
                link.Click += (x, e) => { var open = more.Visibility != Visibility.Visible; more.Visibility = open ? Visibility.Visible : Visibility.Collapsed; ((System.Windows.Documents.Run)link.Inlines.FirstInline).Text = open ? "Less" : "More"; };
                line.Inlines.Add(new System.Windows.Documents.Run("  ")); line.Inlines.Add(link);
                l.Children.Add(more);
            }
            r.Children.Add(s); r.Children.Add(l); return r;
        }

        // label | value table; rows are (label, value, level)
        public static Grid Rows(IEnumerable<(string Label, string Value, string Level)> rows)
        {
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); g.ColumnDefinitions.Add(new ColumnDefinition());
            int i = 0;
            foreach (var p in rows)
            {
                g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                var a = Text(p.Label, B("Sub"), 13, null, "0,5,24,5"); Grid.SetRow(a, i);
                var b = Text(Kit.FormatLine(p.Value), Theme.Level(p.Level), 14, null, "0,5,0,5"); Grid.SetRow(b, i); Grid.SetColumn(b, 1);
                g.Children.Add(a); g.Children.Add(b); i++;
            }
            g.Tag = "rows"; return g;
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
    class CardInfo { public string Title; public string Tile; public bool Wide; }   // Wide: across all columns on a wide window (MainWindow.Flow)
}
