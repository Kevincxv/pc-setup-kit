using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace Messiah
{
    // Search everything (Ctrl+K, or the Search button top right), the tour, and the Welcome page's tab (dashboard.ps1's
    // Get-SearchIndex / Show-Search / Show-Tour / Get-Pages)
    public partial class MainWindow
    {
        // --- search: pages, every optimization on the Status tab, every switch in Settings and the main actions - type a
        // few letters, Enter (or a click) goes there
        class Hit_ { public string Title, Sub, Glyph; public Action Go; }
        Grid sOver; TextBox sBox; StackPanel sList; List<Hit_> sIndex = new List<Hit_>(), sHits = new List<Hit_>(); int sSel; Button sBtn; Border tourOver;

        List<Hit_> SearchIndex()
        {
            var ix = new List<Hit_>();
            void Add(string t, string sub, string g, Action go) => ix.Add(new Hit_ { Title = t, Sub = sub, Glyph = g, Go = go });
            foreach (var (pg, t, g) in new[] { ("Home", "Home", "E80F"), ("Status", "Status", "EA18"), ("Activity/Checks", "Checks - what the maintenance did", "E81C"), ("Activity/Trends", "Trends - charts over time", "E9D9"),
                ("Activity/Alerts", "Alerts", "EA8F"), ("Settings/General", "Settings - general", "E713"), ("Settings/Windows", "Settings - what Messiah changes in Windows", "E713"), ("Settings/Tools", "Tools - updates, repair, drivers, BIOS, install USB", "E90F") })
            { var p = pg.Split('/'); Add(t, "Page", g, () => ShowPage(p[0], p.Length > 1 ? p[1] : null)); }
            if (snap != null) foreach (var r in snap.Sm.Rows) { var title = r.Title; Add(r.Title, "Status - " + r.State, "EA18", () => { Pages.Status.Filter = "all"; Pages.Status.Search = title; ShowPage("Status"); Draw(true); }); }
            foreach (var (grp, items) in TweakCatalog.Groups) foreach (var i in items) Add(i.Title, "Settings > Windows - " + grp, "E713", () => ShowPage("Settings", "Windows"));
            foreach (var t in new[] { "AI assistant (Claude)", "Open Messiah when I log in", "Show alerts in the corner", "Restart at night to finish updates", "Microsoft Defender skips my game folders",
                "NVIDIA driver settings for games", "Undo a graphics driver that crashes", "Settings backup - back up now or restore", "Show technical names in Status details" }) Add(t, "Settings > General", "E713", () => ShowPage("Settings", "General"));
            foreach (var t in new[] { "Repair Messiah", "Undo the last update", "Go back to the previous graphics driver", "Motherboard and BIOS", "Make an install USB", "Uninstall Messiah", "Take the tour again" }) Add(t, "Settings > Tools", "E90F", () => ShowPage("Settings", "Tools"));
            Add("Run maintenance now", "Action", "E768", Actions.RunMaint);
            Add("Check every optimization now", "Action", "E72C", () => { ShowPage("Status"); Actions.CheckNow(); });
            Add("Copy a report for help", "Action - a summary to paste to whoever helps you", "E8C8", Actions.CopyReport);
            Add("Preview what Messiah would change", "Action", "E7B3", Actions.PreviewTweaks);
            Add("Take the tour", "Action - a short walk through the app", "E8F1", () => ShowTour(0));
            if (snap != null && snap.Ai) Add("Chat with Claude", "Action", "E99A", () => ShowChat(true));
            return ix;
        }
        // the box: over the window, near the top; Up/Down choose, Enter goes, Esc (or a click outside) closes
        void InitExtras()
        {
            var root = (Grid)TopBar.Parent;
            sOver = new Grid { Visibility = Visibility.Collapsed, Background = Theme.Tint(Theme.B["Bg"], 0x99) }; Grid.SetRowSpan(sOver, 3); Panel.SetZIndex(sOver, 50);
            var card = new Border { Width = 600, MaxHeight = 520, VerticalAlignment = VerticalAlignment.Top, HorizontalAlignment = HorizontalAlignment.Center, Margin = Ui.Th("24,70,24,24"), Padding = new Thickness(14), CornerRadius = new CornerRadius(12), Background = Theme.B["Toast"], BorderBrush = Theme.B["Border"], BorderThickness = new Thickness(1),   // (solid: the page and the line at the top don't show through)
                Effect = new DropShadowEffect { BlurRadius = 30, ShadowDepth = 6, Opacity = 0.35, Color = Colors.Black } };
            var dock = new DockPanel();
            var top = new DockPanel { Margin = Ui.Th("4,0,4,8") }; DockPanel.SetDock(top, Dock.Top);
            var sg = Ui.Glyph("E721", 16, Theme.B["Sub"]); sg.Margin = Ui.Th("0,0,10,0"); DockPanel.SetDock(sg, Dock.Left); top.Children.Add(sg);
            sBox = new TextBox { FontSize = 16, Background = Brushes.Transparent, BorderThickness = new Thickness(0), Foreground = Theme.B["Text"], CaretBrush = Theme.B["Text"], Padding = Ui.Th("0,4") }; AutomationProperties.SetName(sBox, "Search Messiah");
            top.Children.Add(sBox); dock.Children.Add(top);
            var hint = Ui.Text("Type to search pages, optimizations, settings and actions - Enter opens, Esc closes", Theme.B["Sub"], 12, null, "4,0,4,8"); DockPanel.SetDock(hint, Dock.Top); dock.Children.Add(hint);
            sList = new StackPanel(); dock.Children.Add(new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = sList });
            card.Child = dock; sOver.Children.Add(card); root.Children.Add(sOver);
            sBox.TextChanged += (s, e) => { sSel = 0; UpdateSearch(); };
            sBox.PreviewKeyDown += (s, e) =>
            {
                if (e.Key == Key.Down) { sSel = Math.Min(sSel + 1, Math.Max(0, sHits.Count - 1)); UpdateSearch(); e.Handled = true; }
                else if (e.Key == Key.Up) { sSel = Math.Max(0, sSel - 1); UpdateSearch(); e.Handled = true; }
                else if (e.Key == Key.Return) { InvokeHit(); e.Handled = true; }
                else if (e.Key == Key.Escape) { ShowSearch(false); e.Handled = true; }
            };
            sOver.MouseLeftButtonDown += (s, e) => { if (e.OriginalSource == sOver) ShowSearch(false); };
            // the button, top right (left of Ask Claude)
            sBtn = Ui.Btn("E721", "Search", () => ShowSearch(true)); sBtn.ToolTip = "Search everything (Ctrl+K)"; sBtn.Margin = Ui.Th("0,0,8,0"); sBtn.Padding = Ui.Th("12,6"); AutomationProperties.SetName(sBtn, "Search everything");
            TopBar.Children.Remove(AiPill);
            var tr = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
            Grid.SetColumn(tr, 2); tr.Children.Add(sBtn); tr.Children.Add(AiPill); TopBar.Children.Add(tr);
            // the tour's card at the bottom
            tourOver = new Border { Visibility = Visibility.Collapsed, VerticalAlignment = VerticalAlignment.Bottom, HorizontalAlignment = HorizontalAlignment.Center, MaxWidth = 620, Margin = Ui.Th("24,0,24,24"), Padding = Ui.Th("20,16"), CornerRadius = new CornerRadius(12), Background = Theme.B["Toast"], BorderBrush = Theme.B["Accent"], BorderThickness = new Thickness(1),
                Effect = new DropShadowEffect { BlurRadius = 30, ShadowDepth = 6, Opacity = 0.4, Color = Colors.Black } };
            Grid.SetRow(tourOver, 2); Panel.SetZIndex(tourOver, 40); root.Children.Add(tourOver);
            // Ctrl+K / Ctrl+F (outside the chat): search; Esc closes the tour
            PreviewKeyDown += (s, e) =>
            {
                bool ctrl = (Keyboard.Modifiers & ModifierKeys.Control) != 0;
                if (e.Handled) return;
                if (ctrl && (e.Key == Key.K || e.Key == Key.F) && !ChatInput.IsKeyboardFocused && !(e.Key == Key.F && ChatPanel.Visibility == Visibility.Visible && ChatPanel.IsKeyboardFocusWithin)) { ShowSearch(true); e.Handled = true; }
                else if (e.Key == Key.Escape && tourOver.Visibility == Visibility.Visible) { ShowTour(-1); e.Handled = true; }
            };
            // the tour, once: after setup's Welcome is done (not over it), not while a game runs
            ContentRendered += (s, e) => { if (Kit.Opt("tour", "") != "done" && Kit.Opt("welcome", "") != "pending" && onPage != "Welcome" && Data.Playing() == "") ShowTour(0); };
        }
        void UpdateSearch()
        {
            var q = sBox.Text.Trim(); var words = q.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            sHits = words.Length > 0
                ? sIndex.Where(h => words.All(w => (h.Title + " " + h.Sub).IndexOf(w, StringComparison.OrdinalIgnoreCase) >= 0))
                    .OrderBy(h => h.Title.StartsWith(q, StringComparison.OrdinalIgnoreCase) ? 0 : h.Title.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0 ? 1 : 2).Take(9).ToList()
                : sIndex.Where(h => h.Sub == "Page" || h.Sub.StartsWith("Action")).ToList();
            if (sSel >= sHits.Count) sSel = 0;
            sList.Children.Clear();
            for (int i = 0; i < sHits.Count; i++)
            {
                var h = sHits[i]; var idx = i;
                var row = new Border { CornerRadius = new CornerRadius(8), Padding = Ui.Th("10,7"), Cursor = Cursors.Hand, Tag = i, Background = i == sSel ? Theme.B["CardHover"] : Brushes.Transparent };
                var rp = new DockPanel(); var gl = Ui.Glyph(h.Glyph, 14, Theme.B["Accent"]); gl.Margin = Ui.Th("0,0,12,0"); DockPanel.SetDock(gl, Dock.Left); rp.Children.Add(gl);
                var tx = new StackPanel(); tx.Children.Add(Ui.Text(h.Title, Theme.B["Text"], 14, null, "0")); tx.Children.Add(Ui.Text(h.Sub, Theme.B["Sub"], 12, null, "0")); rp.Children.Add(tx); row.Child = rp;
                AutomationProperties.SetName(row, $"{h.Title}, {h.Sub}");
                row.MouseEnter += (s, e) => { sSel = idx; foreach (Border c in sList.Children.OfType<Border>()) c.Background = (int)c.Tag == sSel ? Theme.B["CardHover"] : Brushes.Transparent; };
                row.MouseLeftButtonUp += (s, e) => { sSel = idx; InvokeHit(); };
                sList.Children.Add(row);
            }
            if (sHits.Count == 0) sList.Children.Add(Ui.Text("Nothing found - try another word.", Theme.B["Sub"], 13, null, "10,6,0,6"));
        }
        void InvokeHit() { if (sSel >= sHits.Count) return; var h = sHits[sSel]; ShowSearch(false); try { h.Go(); } catch (Exception e) { Say("Couldn't open that: " + e.Message); } }
        void ShowSearch(bool on)
        {
            if (on) { sIndex = SearchIndex(); sBox.Text = ""; sSel = 0; UpdateSearch(); sOver.Visibility = Visibility.Visible; sBox.Focus(); }
            else sOver.Visibility = Visibility.Collapsed;
        }

        // --- the tour: once, after setup's Welcome (or Settings > Tools > Take the tour) - a card at the bottom walks through
        // the tabs, each opened behind it
        static readonly (string Page, string Sub, string Title, string Text)[] TourSteps = {
            ("Home", null, "Home - your PC at a glance", "The ring says whether anything needs you; the tiles under it open the details. Most days it just says all good."),
            ("Status", null, "Status - every optimization, kept in place", "Green means in place. Click any row for what it does and its history; a row that needs a look has its fix-it button. Filters and search are on top."),
            ("Activity", "Checks", "Activity - what Messiah did", "What each check found and fixed, charts of how the PC is doing over time, and alerts - Messiah never pops up, it writes here."),
            ("Settings", "Windows", "Settings - yours to choose", "Every change Messiah makes in Windows has its own switch. Tools has repairs, drivers, the BIOS and the install USB."),
            ("Status", null, "Search everything", "Press Ctrl+K anywhere (or the Search button top right) to jump to any page, setting or optimization.") };
        public void ShowTour(int i)
        {
            if (i < 0 || i >= TourSteps.Length) { tourOver.Visibility = Visibility.Collapsed; Kit.SetOpt("tour", "done"); return; }
            var st = TourSteps[i]; ShowPage(st.Page, st.Sub);
            var sp = new StackPanel(); var hd = new DockPanel();
            var n = Ui.Text($"{i + 1} of {TourSteps.Length}", Theme.B["Sub"], 12, null, "12,4,0,0"); DockPanel.SetDock(n, Dock.Right); hd.Children.Add(n);
            var tt = Ui.Text(st.Title, Theme.B["Text"], 17, FontWeights.SemiBold, "0"); tt.FontFamily = Theme.Display; hd.Children.Add(tt); sp.Children.Add(hd);
            sp.Children.Add(Ui.Text(st.Text, Theme.B["Sub"], 13, null, "0,6,0,12"));
            var bp = new WrapPanel(); bool last = i == TourSteps.Length - 1;
            bp.Children.Add(Ui.Btn("E711", "Skip the tour", () => ShowTour(-1)));
            if (i > 0) bp.Children.Add(Ui.Btn("E72B", "Back", () => ShowTour(i - 1)));
            var bn = Ui.Btn(last ? "E73E" : "E72A", last ? "Done" : "Next", () => ShowTour(last ? -1 : i + 1), accent: true); bp.Children.Add(bn);
            sp.Children.Add(bp); tourOver.Child = sp; tourOver.Visibility = Visibility.Visible; bn.Focus();
        }

        // --- the Welcome tab: after a new install (kit-options "welcome=pending"), until "Got it"
        bool welcomeDone;
        bool WelcomeShown => Kit.Opt("welcome", "") == "pending" || (startPage == "Welcome" && !welcomeDone);
        public string startPage;
        public void Welcomed() { Kit.SetOpt("welcome", "done"); welcomeDone = true; BuildNav(); ShowPage("Home"); if (Kit.Opt("tour", "") != "done") ShowTour(0); }
    }
}
