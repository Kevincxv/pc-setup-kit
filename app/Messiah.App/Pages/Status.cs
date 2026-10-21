using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;

namespace Messiah.Pages
{
    // Status (dashboard.ps1's Build-Page 'Status'): every optimization Messiah keeps in place - the summary on top, then a
    // card per group; each row opens its details with a click, and one that needs a look has its fix-it button
    static class Status
    {
        static SolidColorBrush B(string k) => Theme.B[k];
        // the filter and the search stay while the page refreshes; which rows are open stays for the next start (AppLast)
        public static string Filter = "all", Search = "";
        static readonly List<(FrameworkElement El, StatusRow Row)> rows = new List<(FrameworkElement, StatusRow)>();
        static readonly Dictionary<string, Border> cards = new Dictionary<string, Border>();
        static TextBlock empty;

        public static List<UIElement> Build(Snapshot s, bool test = false)
        {
            var o = new List<UIElement>(); var sm = s.Sm;
            if (Shell.CheckingSince != null && !sm.Checking)   // a check the owner started has finished (or given up)
            {
                Shell.Say(sm.At != null && sm.At >= Shell.CheckingSince ? $"Check finished - {(sm.Warn > 0 ? $"{sm.Warn} need{(sm.Warn == 1 ? "s" : "")} a look" : "everything is in place")}." : "The check is taking longer than usual - this page updates by itself when it finishes.");
                Shell.CheckingSince = null;
            }
            var hl = sm.Checking ? ("info", "E895", "Checking everything now...") : sm.At == null ? ("dim", "E9F5", "Not checked yet") : sm.Warn > 0 ? ("warn", sm.Warn.ToString(), $"{sm.Warn} need{(sm.Warn == 1 ? "s" : "")} a look") : sm.Stale ? ("warn", "E9F5", "Not checked lately") : ("ok", "E73E", $"All {sm.Ok} in place");
            var hero = new Grid();
            hero.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); hero.ColumnDefinitions.Add(new ColumnDefinition());
            var ring = Ui.Ring(64, 4, 24, hl.Item1, hl.Item2, hl.Item1 == "info" ? B("Accent") : null); ring.Margin = Ui.Th("0,0,20,0");
            if (sm.Checking && !test)   // (the sync arrows turn while it checks)
            {
                var mid = (FrameworkElement)ring.Children[2]; var rot = new RotateTransform(); mid.RenderTransformOrigin = new Point(0.5, 0.5); mid.RenderTransform = rot;
                rot.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, 360, TimeSpan.FromSeconds(1.6)) { RepeatBehavior = RepeatBehavior.Forever });
            }
            var txt = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            var ht = Ui.Text(hl.Item3, B("Text"), 22, FontWeights.SemiBold, "0"); ht.FontFamily = Theme.Display; txt.Children.Add(ht);
            var sub = sm.Checking ? "Settings, services, apps, the power plan, the NVIDIA profile and the monitors - this page updates by itself when it is done (usually under a minute)."
                : $"{(sm.At != null ? "Checked " + Kit.FormatWhen(sm.At.Value) : "The first check runs a few minutes after login")} · checked again at every login, every 4 hours and 2 minutes after each Windows or driver update - anything an update changes back is put back by itself. Click a row for details.";
            txt.Children.Add(Ui.Text(sub, B("Sub"), 13, null, "0,4,0,0"));
            Grid.SetColumn(txt, 1); hero.Children.Add(ring); hero.Children.Add(txt);
            var chk = Ui.Btn("E72C", sm.Checking ? "Checking..." : "Check now", Actions.CheckNow, accent: true); chk.IsEnabled = !sm.Checking;
            var hc = Ui.Card(null, null, new object[] { hero }, new UIElement[] { chk, Ui.Btn("E7B3", "Preview changes", Actions.PreviewTweaks), Ui.Btn("E713", "Choose what Messiah changes", () => Shell.ShowPage("Settings", "Windows")), Ui.Btn("E8C8", "Copy a report", Actions.CopyReport) });
            hc.Padding = Ui.Th("24,20"); o.Add(hc);

            // filters (All / Needs a look / Put back / Off, with counts) and a search box: rows are hidden in place, no redraw
            var cnt = new Dictionary<string, int> { ["all"] = sm.Rows.Count, ["warn"] = sm.Rows.Count(r => r.Level == "warn"), ["back"] = sm.Rows.Count(r => (r.State ?? "").StartsWith("Put back")), ["off"] = sm.Rows.Count(r => r.Level == "dim") };
            var fbar = new DockPanel { Margin = Ui.Th("0,0,0,14"), LastChildFill = false };
            var seg = new Border { Background = B("Seg"), CornerRadius = new CornerRadius(8), Padding = new Thickness(3), VerticalAlignment = VerticalAlignment.Center };
            var pills = new StackPanel { Orientation = Orientation.Horizontal };
            foreach (var (id, label) in new[] { ("all", "All"), ("warn", "Needs a look"), ("back", "Put back"), ("off", "Off") })
            {
                var rb = new RadioButton { GroupName = "stf", Tag = id, Content = $"{label}  {cnt[id]}", IsChecked = Filter == id, Style = (Style)Application.Current.FindResource("Pill") };
                AutomationProperties.SetName(rb, $"Show: {label}, {cnt[id]}");
                rb.Checked += (x, e) => { Filter = id; Apply(); }; pills.Children.Add(rb);
            }
            seg.Child = pills; DockPanel.SetDock(seg, Dock.Left); fbar.Children.Add(seg);
            var sbx = new Border { Background = B("Seg"), CornerRadius = new CornerRadius(8), Padding = Ui.Th("10,0"), Width = 240, VerticalAlignment = VerticalAlignment.Center, Margin = Ui.Th("12,0,0,0") };
            var sg = new Grid();
            var shint = Ui.Text("Search optimizations...", B("Sub"), 13, null, "0,6,0,6"); shint.IsHitTestVisible = false;
            var stb = new TextBox { Text = Search, FontSize = 13, Background = Brushes.Transparent, BorderThickness = new Thickness(0), Foreground = B("Text"), CaretBrush = B("Text"), Padding = Ui.Th("0,6,0,6"), VerticalContentAlignment = VerticalAlignment.Center };
            AutomationProperties.SetName(stb, "Search optimizations");
            shint.Visibility = Search != "" ? Visibility.Collapsed : Visibility.Visible;
            stb.TextChanged += (x, e) => { Search = stb.Text; shint.Visibility = stb.Text != "" ? Visibility.Collapsed : Visibility.Visible; Apply(); };
            stb.PreviewKeyDown += (x, e) => { if (e.Key == Key.Escape && stb.Text != "") { stb.Text = ""; e.Handled = true; } };
            sg.Children.Add(shint); sg.Children.Add(stb); sbx.Child = sg; DockPanel.SetDock(sbx, Dock.Right); fbar.Children.Add(sbx);
            o.Add(new Border { Tag = "filters", Child = fbar });

            rows.Clear(); cards.Clear();
            foreach (var g in sm.Rows.Select(r => r.Card).Distinct())
            {
                var rs = new List<object>();
                foreach (var row in sm.Rows.Where(r => r.Card == g)) { var el = Row(row); rows.Add((el, row)); rs.Add(el); }
                var cd = Ui.Card(g, g == "Speed and games" ? "E945" : g == "Privacy and clutter" ? "E72E" : g == "This PC" ? "E7F4" : "E895", rs);
                cards[g] = cd; o.Add(cd);
            }
            empty = Ui.Text("Nothing matches - try another filter or search.", B("Sub"), 13, null, "4,4,0,0"); o.Add(empty);
            Apply();
            return o;
        }

        // the filter and the search: rows and cards hidden in place
        static void Apply()
        {
            var q = (Search ?? "").Trim();
            foreach (var (el, r) in rows)
            {
                bool show = Filter == "warn" ? r.Level == "warn" : Filter == "back" ? (r.State ?? "").StartsWith("Put back") : Filter == "off" ? r.Level == "dim" : true;
                if (show && q != "") show = r.Words.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0;
                el.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
            }
            foreach (var kv in cards) kv.Value.Visibility = rows.Any(x => x.Row.Card == kv.Key && x.El.Visibility == Visibility.Visible) ? Visibility.Visible : Visibility.Collapsed;
            if (empty != null) empty.Visibility = rows.Any(x => x.El.Visibility == Visibility.Visible) ? Visibility.Collapsed : Visibility.Visible;
        }

        // one line: a status dot, the optimization, what the last check found on the right (and a line under it); a click
        // (or Enter / Space) opens its details - a chevron says so
        static FrameworkElement Row(StatusRow row)
        {
            var r = new DockPanel { Margin = Ui.Th("-8,1,-8,1"), Background = Brushes.Transparent };
            var dot = new Ellipse { Width = 10, Height = 10, Fill = Theme.Level(row.Level), VerticalAlignment = VerticalAlignment.Top, Margin = Ui.Th("8,10,14,0") }; DockPanel.SetDock(dot, Dock.Left); r.Children.Add(dot);
            var has = row.More != null && row.More.Count > 0;
            TextBlock chev = null;
            if (has) { chev = Ui.Glyph("E70D", 10, B("Sub")); chev.VerticalAlignment = VerticalAlignment.Top; chev.Margin = Ui.Th("12,8,8,0"); DockPanel.SetDock(chev, Dock.Right); r.Children.Add(chev); }
            var st = Ui.Text(row.State, row.Level == "warn" ? B("Warn") : B("Sub"), 13, null, has ? "16,5,0,0" : "16,5,8,0"); st.TextWrapping = TextWrapping.NoWrap; st.VerticalAlignment = VerticalAlignment.Top; DockPanel.SetDock(st, Dock.Right); r.Children.Add(st);
            var l = new StackPanel { Margin = Ui.Th("0,4,0,4") };
            l.Children.Add(Ui.Text(row.Title, row.Level == "dim" ? B("Sub") : B("Text"), 14, null, "0"));
            if (!string.IsNullOrEmpty(row.Detail)) l.Children.Add(Ui.Text(row.Detail, B("Sub"), 12, null, "0,1,0,0"));
            if (row.Fix != null)
            {
                var fp = new WrapPanel { Margin = Ui.Th("0,6,0,0") }; var fx = row.Fix.Value;
                fp.Children.Add(Ui.Btn(fx.Glyph, fx.Label, () => Actions.Run(fx.Action), small: true));
                fp.MouseLeftButtonUp += (x, e) => e.Handled = true;   // (a click beside the button doesn't open the details)
                l.Children.Add(fp);
            }
            if (has)
            {
                // the details: a faint panel with a line on its left, out of the way until asked for
                var mb = new Border { Tag = "more", BorderBrush = B("Divider"), BorderThickness = Ui.Th("2,0,0,0"), Padding = Ui.Th("12,2,0,2"), Margin = Ui.Th("0,8,0,4"), Cursor = Cursors.Arrow };
                var mp = new StackPanel();
                foreach (var m in row.More)
                {
                    if (m.Action != null)
                    {
                        var b = Ui.Btn(m.Glyph, m.Text, () => Actions.Run(m.Action), small: true); b.HorizontalAlignment = HorizontalAlignment.Left; b.Margin = Ui.Th(m.Action.StartsWith("Page:") ? "0,6,0,0" : "0,2,0,4"); mp.Children.Add(b);
                        continue;
                    }
                    var t = Ui.Text("", B("Sub"), 12, null, "0,2,0,2");
                    if (!string.IsNullOrEmpty(m.Label)) t.Inlines.Add(new Run(m.Label + "  ") { Foreground = B("Text"), FontWeight = FontWeights.SemiBold });
                    t.Inlines.Add(new Run(m.Text)); mp.Children.Add(t);
                }
                mb.Child = mp;
                bool open = AppLast.OpenRows.Contains(row.Title);
                mb.Visibility = open ? Visibility.Visible : Visibility.Collapsed; if (open) chev.Text = "";
                mb.MouseLeftButtonUp += (x, e) => e.Handled = true;   // (selecting in the details doesn't close them)
                l.Children.Add(mb);
                Action toggle = () =>
                {
                    var show = mb.Visibility != Visibility.Visible;
                    mb.Visibility = show ? Visibility.Visible : Visibility.Collapsed; chev.Text = show ? "" : "";
                    if (show) AppLast.OpenRows.Add(row.Title); else AppLast.OpenRows.Remove(row.Title); AppLast.Save();
                };
                r.Cursor = Cursors.Hand; r.ToolTip = "Details";
                // the keyboard too: Tab reaches the row, Enter or Space opens its details (a faint highlight shows where focus is)
                r.Focusable = true; KeyboardNavigation.SetIsTabStop(r, true); r.FocusVisualStyle = null;
                AutomationProperties.SetName(r, $"{row.Title} - {row.State}"); AutomationProperties.SetHelpText(r, "Press Enter for details");
                r.GotKeyboardFocus += (x, e) => r.Background = B("CardHover"); r.LostKeyboardFocus += (x, e) => r.Background = Brushes.Transparent;
                r.KeyDown += (x, e) => { if ((e.Key == Key.Return || e.Key == Key.Space) && e.OriginalSource == r) { toggle(); e.Handled = true; } };
                r.MouseEnter += (x, e) => r.Background = B("CardHover"); r.MouseLeave += (x, e) => r.Background = Brushes.Transparent;
                r.MouseLeftButtonUp += (x, e) => toggle();
            }
            r.Children.Add(l); r.Tag = new RowInfo { Row = row };
            return r;
        }
    }
    class RowInfo { public StatusRow Row; }
}
