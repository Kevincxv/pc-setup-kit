using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace Messiah
{
    // What the pages call (dashboard.ps1's Say, Show-Page, Update-View -Force)
    static class Shell
    {
        public static MainWindow W;
        public static DateTime? CheckingSince;
        public static void Say(string t) => W?.Say(t);
        public static void ShowPage(string p, string sub = null) => W?.ShowPage(p, sub);
        public static void Refresh(bool force) => W?.Refresh(force);
        public static DateTime? SeenBefore;   // when the owner last closed the window (Home's "Since you last looked"; tests: PCKIT_SINCE_TEST)
    }

    public partial class MainWindow : Window
    {
        // --- pages: five tabs, each with one job, and their pages (the pills beside the page title). 10/25, the owner: "flows
        // really good and follows best practice" - Fluent's top navigation is for 5 or fewer sections; Activity had six unrelated
        // pages and the game charts were in two places. The pages keep their own names (keys): an old link - "Activity/
        // Performance", "Status", a notification's, the tray's, app-last.txt - opens the page in its new place.
        internal static readonly (string Tab, string Glyph, (string Label, string Key)[] Pages)[] Tabs = {
            ("Home", "E80F", new[] { ("Home", "Home") }),
            ("Games", "E7FC", new[] { ("Performance", "Activity/Performance"), ("Storage", "Activity/Storage") }),
            ("Health", "E95E", new[] { ("Stability", "Activity/Stability"), ("Trends", "Activity/Trends"), ("Checks", "Activity/Checks"), ("Alerts", "Activity/Alerts") }),
            ("Optimizations", "EA18", new[] { ("In place", "Status"), ("Choose", "Settings/Windows") }),
            ("Settings", "E713", new[] { ("General", "Settings/General"), ("Tools", "Settings/Tools") }) };
        static readonly (string Tab, string Glyph, (string Label, string Key)[] Pages) WelcomeTab = ("Welcome", "E8E1", new[] { ("Welcome", "Welcome") });
        (string Tab, string Glyph, (string Label, string Key)[] Pages)[] AllTabs => (WelcomeShown ? new[] { WelcomeTab } : new (string, string, (string, string)[])[0]).Concat(Tabs).ToArray();
        static readonly Dictionary<string, string> Subs = new Dictionary<string, string> {
            ["Welcome"] = "Your PC is set up. Here is what happened and what happens from now on.",
            ["Status"] = "Every optimization Messiah keeps in place on this PC - and whether it still is.",
            ["Activity/Checks"] = "What the maintenance found, what it did, and when it runs next.", ["Activity/Trends"] = "How this PC has been doing over time.",
            ["Activity/Stability"] = "Every blue screen and power-off, and what changed around them.", ["Activity/Performance"] = "How your games run - each minute measured while you play, and what updates did to them.", ["Activity/Alerts"] = "What Messiah had to say - kept here instead of popping up.", ["Activity/Storage"] = "Your drives, the games on them and what uninstalled games left behind.",
            ["Settings/General"] = "Everything Messiah does is yours to switch on or off.", ["Settings/Windows"] = "Each change Messiah makes in Windows - keep it or not.",
            ["Settings/Tools"] = "Updates, repairs, drivers, the BIOS and the install USB." };
        static readonly Dictionary<string, string> OldPages = new Dictionary<string, string> { ["Overview"] = "Home", ["Sessions"] = "Home", ["Maintenance"] = "Activity/Checks", ["Schedule"] = "Activity/Checks", ["History"] = "Activity/Trends", ["Notifications"] = "Activity/Alerts", ["Activity"] = "Activity/Checks" };
        readonly Dictionary<string, string> sub = Tabs.ToDictionary(t => t.Tab, t => t.Pages[0].Key);   // each tab's page now (its key)
        readonly Dictionary<string, (RadioButton Button, TextBlock Count)> nav = new Dictionary<string, (RadioButton, TextBlock)>();
        string onPage = "Home";
        Snapshot snap; string shownSig; int loading;
        readonly DispatcherTimer noteTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(12) };
        readonly DispatcherTimer timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(60) };   // (the files are watched - MainWindow.Live.cs; this covers what changes with the clock)
        public bool Quit;

        public MainWindow()
        {
            InitializeComponent();
            Shell.W = this;
            noteTimer.Tick += (s, e) => { NoteBar.Visibility = Visibility.Collapsed; noteTimer.Stop(); };
            NoteAct.Click += (s, e) => noteAct?.Invoke();
            timer.Tick += (s, e) => Refresh(false);
            SourceInitialized += (s, e) => OnSource();
            SizeChanged += (s, e) => UpdateLayout2();
            Scroll.SizeChanged += (s, e) => UpdateColumns();
            Closing += (s, e) => { SavePlace(); if (!Quit) { e.Cancel = true; HideApp(); } };
            Closed += (s, e) => Application.Current.Shutdown();
            LoadIcon(); RestorePlace(); BuildNav(); InitChat(); InitExtras(); InitLive(); InitDrop();
        }

        // --- the window: its icon (the tray's app.ico), Mica and a title bar in the theme (Windows 11), where it was
        void LoadIcon()
        {
            try
            {
                Native.SetCurrentProcessExplicitAppUserModelID("PCSetupKit.App");   // its own taskbar button
                var ico = Path.Combine(Kit.TrayDir, "app.ico");
                if (File.Exists(ico))
                {
                    var dec = new IconBitmapDecoder(new Uri(ico), BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
                    Icon = dec.Frames.FirstOrDefault(f => f.PixelWidth == 32) ?? dec.Frames[0];
                    Logo.Source = dec.Frames.OrderByDescending(f => f.PixelWidth).First();
                }
            }
            catch { }
        }
        void OnSource()
        {
            var h = new WindowInteropHelper(this).Handle;
            try { File.WriteAllText(Kit.P(App.Names.HwndFile), ((long)h).ToString()); } catch { }
            try
            {
                int v = Theme.Light ? 0 : 1; Native.DwmSetWindowAttribute(h, 20, ref v, 4);
                if (Environment.OSVersion.Version.Build >= 22621)
                {
                    v = 2;   // DWMWA_SYSTEMBACKDROP_TYPE = Mica
                    if (Native.DwmSetWindowAttribute(h, 38, ref v, 4) == 0)
                    {
                        var m = new Native.MARGINS { L = -1, R = -1, T = -1, B = -1 }; Native.DwmExtendFrameIntoClientArea(h, ref m);
                        HwndSource.FromHwnd(h).CompositionTarget.BackgroundColor = Colors.Transparent;
                        Background = Brushes.Transparent;
                    }
                }
            }
            catch { }
            FitToScreen();
        }
        void RestorePlace()
        {
            var pl = Kit.FirstLine(Kit.P(App.Names.PlaceFile)).Split(',');
            if (pl.Length >= 5 && double.TryParse(pl[0], out var l) && double.TryParse(pl[1], out var t) && double.TryParse(pl[2], out var w) && double.TryParse(pl[3], out var hh)
                && SystemParameters.VirtualScreenLeft <= l + 80 && l + 80 <= SystemParameters.VirtualScreenLeft + SystemParameters.VirtualScreenWidth && w >= MinWidth && hh >= MinHeight)
            { Left = l; Top = t; Width = w; Height = hh; if (pl[4] == "max") WindowState = WindowState.Maximized; }
            else
            {
                var a = SystemParameters.WorkArea;
                // (tests: a window a test opens goes on a second monitor when there is one - never over the owner's game on the
                // main one; 10/25, the owner: work on the app happens on the Dell)
                if (Kit.InTests) { var sec = System.Windows.Forms.Screen.AllScreens.FirstOrDefault(x => !x.Primary); if (sec != null) { var wa = sec.WorkingArea; a = new Rect(wa.Left, wa.Top, wa.Width, wa.Height); } }
                Width = Math.Min(1040, a.Width); Height = Math.Min(780, a.Height); Left = a.Left + (a.Width - Width) / 2; Top = a.Top + (a.Height - Height) / 2;
            }
        }
        void SavePlace()
        {
            var b = RestoreBounds; if (b.IsEmpty) return;
            try { File.WriteAllText(Kit.P(App.Names.PlaceFile), $"{Math.Round(b.Left)},{Math.Round(b.Top)},{Math.Round(b.Width)},{Math.Round(b.Height)},{(WindowState == WindowState.Maximized ? "max" : "normal")}"); } catch { }
        }
        // the window inside its screen (a smaller screen, another resolution, a monitor unplugged)
        // the work area of the screen the window is on (not always the main one)
        internal Rect WorkArea()
        {
            try
            {
                var wa = System.Windows.Forms.Screen.FromHandle(new WindowInteropHelper(this).Handle).WorkingArea;
                var src = PresentationSource.FromVisual(this); var m = src?.CompositionTarget.TransformFromDevice ?? Matrix.Identity;
                return new Rect(m.Transform(new Point(wa.Left, wa.Top)), m.Transform(new Point(wa.Right, wa.Bottom)));
            }
            catch { return SystemParameters.WorkArea; }
        }
        internal bool Auditing;   // (--audit: the window sits off the screen, at the sizes asked for)
        void FitToScreen()
        {
            if (WindowState != WindowState.Normal || Auditing) return;
            var a = WorkArea();
            if (Width > a.Width) Width = Math.Max(MinWidth, a.Width);
            if (Height > a.Height) Height = Math.Max(MinHeight, a.Height);
            if (Left + Width > a.Right) Left = a.Right - Width;
            if (Top + Height > a.Bottom) Top = a.Bottom - Height;
            if (Left < a.Left) Left = a.Left;
            if (Top < a.Top) Top = a.Top;
        }

        // --- show / hide (closing only hides it: the next open is instant; hidden, it does nothing but wait)
        public void ShowApp()
        {
            bool wasHidden = Visibility != Visibility.Visible;
            if (wasHidden) { Shell.SeenBefore = AppLast.Seen; Show(); }
            if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
            timer.Start(); fast.Start(); StartWatching();
            // (a window shown for the first time loads its tabs after this: a page asked for is chosen once they have - else
            // the first load put it back to the one before; 10/21: the welcome page, a notification's page)
            if (wasHidden) Dispatcher.BeginInvoke(new Action(ReadRequest), System.Windows.Threading.DispatcherPriority.Loaded); else ReadRequest();
            if (wasHidden) Refresh(false);
            Activate(); Native.SetForegroundWindow(new WindowInteropHelper(this).Handle);
        }
        void HideApp() { Hide(); timer.Stop(); fast.Stop(); StopWatching(); ShowChatMenu(false); AppLast.Seen = DateTime.Now; AppLast.Save(); }

        // another start asked for a page (app-request.txt "page=<Page>[/<Sub>]")
        internal bool pageAsked;
        void ReadRequest()
        {
            var f = Kit.P(App.Names.RequestFile); if (!File.Exists(f)) return;
            var r = Kit.FirstLine(f); try { File.Delete(f); } catch { } pageAsked = r != "";
            var m = System.Text.RegularExpressions.Regex.Match(r, @"^page=(\w+)(?:/(\w+))?$");
            if (m.Success) { if (m.Groups[1].Value == "Chat") { if (snap == null || snap.Ai) ShowChat(true); } else ShowPage(m.Groups[1].Value, m.Groups[2].Success ? m.Groups[2].Value : null); }
            else ReadChatRequest(r);
        }

        // --- the tabs
        internal void BuildNav()
        {
            NavList.Children.Clear(); nav.Clear();
            foreach (var (p, g, pp) in AllTabs)
            {
                if (!sub.ContainsKey(p)) sub[p] = pp[0].Key;
                var rb = new RadioButton { GroupName = "nav", Tag = p, ToolTip = p, Style = (Style)FindResource("Tab") }; AutomationProperties.SetName(rb, p);
                var row = new StackPanel { Orientation = Orientation.Horizontal };
                var gl = Ui.Glyph(g, 14); gl.Margin = Ui.Th("0,0,8,0"); row.Children.Add(gl);
                row.Children.Add(Ui.Text(p, Theme.B["Text"], 14, null, "0"));
                var count = new Border { CornerRadius = new CornerRadius(8), Background = Theme.B["Warn"], Padding = Ui.Th("6,0"), MinWidth = 18, Margin = Ui.Th("8,0,0,0"), Visibility = Visibility.Collapsed, VerticalAlignment = VerticalAlignment.Center };
                var ct = Ui.Text("", Theme.OnColor, 11, FontWeights.SemiBold, "0"); ct.HorizontalAlignment = HorizontalAlignment.Center; count.Child = ct;
                row.Children.Add(count); rb.Content = row;
                nav[p] = (rb, ct);
                rb.Checked += (s, e) => { onPage = p; Say(""); UpdateSub(); Scroll.ScrollToTop(); Draw(true); };
                NavList.Children.Add(rb);
            }
            UpdateLayout2();   // (new tabs have their words: a narrow window takes them off again - 10/25 audit, after the welcome page)
        }
        // a page by its key ("Activity/Performance", "Status"), by tab and page ("Games", "Storage"), or a tab ("Health"): the
        // tab it's in, opened on it
        public void ShowPage(string p, string s = null)
        {
            var key = s != null ? p + "/" + s : p;
            if (OldPages.TryGetValue(key, out var np) || (s == null && OldPages.TryGetValue(p, out np))) key = np;
            string tab = null, page = null;
            foreach (var t in AllTabs)
            {
                var hit = t.Pages.FirstOrDefault(x => x.Key == key || (t.Tab == p && x.Label == s));
                if (hit.Key != null) { tab = t.Tab; page = hit.Key; break; }
                if (t.Tab == p && s == null) { tab = t.Tab; break; }   // (a tab: the page it was on)
            }
            if (tab == null || !nav.ContainsKey(tab)) return;
            if (page != null) sub[tab] = page;
            if (nav[tab].Button.IsChecked == true) { onPage = tab; UpdateSub(); Draw(true); } else nav[tab].Button.IsChecked = true;
        }
        void UpdateSub()
        {
            SubNav.Children.Clear();
            var pages = AllTabs.FirstOrDefault(t => t.Tab == onPage).Pages ?? new (string, string)[0];
            SubBox.Visibility = pages.Length > 1 ? Visibility.Visible : Visibility.Collapsed;
            foreach (var (label, key) in pages.Length > 1 ? pages : new (string, string)[0])
            {
                var rb = new RadioButton { GroupName = "sub", Tag = key, Content = label, IsChecked = key == sub[onPage], Style = (Style)FindResource("Pill") };
                rb.Checked += (x, e) => { sub[onPage] = key; Say(""); Scroll.ScrollToTop(); Draw(true); };
                SubNav.Children.Add(rb);
            }
        }
        string PageKey => sub.TryGetValue(onPage, out var k) ? k : onPage;

        // --- the data: read in the background, drawn when it arrives (and again only when something changed)
        public void Refresh(bool force)
        {
            if (Interlocked.Exchange(ref loading, 1) == 1) { if (force) shownSig = null; return; }
            var since = Shell.CheckingSince;
            Task.Run(() =>
            {
                Snapshot r = null; try { r = Snapshot.Load(since); } catch (Exception e) { App.Log("snapshot: " + e); }
                Dispatcher.BeginInvoke(new Action(() =>
                {
                    Interlocked.Exchange(ref loading, 0);
                    if (r == null) return;
                    snap = r;
                    if (force || snap.Sig + PageKey != shownSig) Draw(false);
                }));
            });
        }
        public void Draw(bool pageChanged)
        {
            if (snap == null) { Refresh(true); return; }
            var todo = snap.Sec("Needs you").Lines.Count(l => l.Level == "warn");
            AiPill.Visibility = snap.Ai ? Visibility.Visible : Visibility.Collapsed; if (!snap.Ai && ChatPanel.Visibility == Visibility.Visible) ShowChat(false);
            var badge = (Border)nav["Home"].Count.Parent; var badgeWas = badge.Visibility;
            nav["Home"].Count.Text = todo > 0 ? todo.ToString() : ""; badge.Visibility = todo > 0 ? Visibility.Visible : Visibility.Collapsed;
            if (badge.Visibility != badgeWas) UpdateLayout2();   // (the badge makes the tabs wider: the top bar fits again - 10/25 audit)
            shownSig = snap.Sig + PageKey;
            if (AppLast.Page != PageKey) { AppLast.Page = PageKey; AppLast.Save(); }   // (where to open next time)
            PageTitle.Text = onPage == "Welcome" ? "Welcome to Messiah" : onPage; Subs.TryGetValue(PageKey, out var st); PageSub.Text = st ?? "";
            Header.Visibility = onPage == "Home" ? Visibility.Collapsed : Visibility.Visible;
            PageContent.Children.Clear(); PageError = null;
            List<UIElement> els;
            try { els = BuildPage(PageKey, snap); }
            catch (Exception e)
            {   // one page failing never takes the window down: it says so (the tests look for PAGE ERROR)
                PageError = e.Message;
                els = new List<UIElement> { Ui.Card("This page couldn't be shown", "E783", new object[] { new Line("Something in its data is damaged. The other pages work; the next maintenance usually repairs it.", "warn"), new Line(e.Message, "dim") }) };
            }
            Flow(els);
            UpdateColumns();
        }

        // --- a wide window uses its width (10/22, the owner: "a lot of wasted space on the side"): the page's cards in 2
        // columns from 1720 px of room, 3 from 2600 - each card into the shortest column, in order; what is wide (a page's
        // summary, the tiles, a timeline, a note) across all of them, and the columns start again under it
        int flowCols = 1;
        int FlowCols()
        {
            var w = Math.Min(Body.MaxWidth, Scroll.ActualWidth) - Body.Margin.Left - Body.Margin.Right;
            return onPage == "Welcome" ? 1 : w >= 2600 ? 3 : w >= 1720 ? 2 : 1;
        }
        static bool IsWide(UIElement el) => !(el is Border b && b.Tag is CardInfo ci && !ci.Wide);
        void Flow(List<UIElement> els)
        {
            flowCols = FlowCols();
            if (flowCols == 1) { foreach (var el in els) PageContent.Children.Add(el); return; }
            const double gap = 14;
            var colW = (Math.Min(Body.MaxWidth, Scroll.ActualWidth) - Body.Margin.Left - Body.Margin.Right - gap * (flowCols - 1)) / flowCols;
            StackPanel[] cols = null; double[] h = null;
            foreach (var el in els)
            {
                if (IsWide(el)) { cols = null; PageContent.Children.Add(el); continue; }
                if (cols == null)
                {
                    var sec = new Grid(); cols = new StackPanel[flowCols]; h = new double[flowCols];
                    for (int i = 0; i < flowCols; i++)
                    {
                        sec.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                        cols[i] = new StackPanel { Margin = new Thickness(0, 0, i < flowCols - 1 ? gap : 0, 0) }; Grid.SetColumn(cols[i], i); sec.Children.Add(cols[i]);
                    }
                    PageContent.Children.Add(sec);
                }
                el.Measure(new Size(colW, double.PositiveInfinity));
                var k = Array.IndexOf(h, h.Min()); cols[k].Children.Add(el); h[k] += el.DesiredSize.Height + gap;
            }
        }
        public string PageError;
        internal List<UIElement> BuildPage(string key, Snapshot s)
        {
            switch (key)
            {
                case "Welcome": return Pages.Welcome.Build(s);
                case "Home": return Pages.Home.Build(s);
                case "Status": return Pages.Status.Build(s);
                case "Activity/Checks": return Pages.Activity.Checks(s);
                case "Activity/Stability": return Pages.Activity.Stability(s, PageContent.ActualWidth);
                case "Activity/Trends": return Pages.Activity.Trends(s);
                case "Activity/Performance": return Pages.Performance.Build(s);
                case "Activity/Alerts": return Pages.Activity.Alerts(s);
                case "Activity/Storage": return Pages.Storage.Build(s);
                case "Settings/General": return Pages.Settings.General(s);
                case "Settings/Windows": return Pages.Settings.Windows(s);
                case "Settings/Tools": return Pages.Settings.Tools(s);
                default: return Pages.Home.Build(s);   // (an unknown page - an old app-last.txt: Home)
            }
        }

        // --- a short note floating at the bottom; it goes away by itself after 12 seconds
        public void Say(string t) { if (string.IsNullOrEmpty(t) && noteAct != null) return; NoteAct.Visibility = Visibility.Collapsed; noteAct = null; Note.Text = t ?? ""; NoteBar.Visibility = string.IsNullOrEmpty(t) ? Visibility.Collapsed : Visibility.Visible; noteTimer.Stop(); if (!string.IsNullOrEmpty(t)) noteTimer.Start(); }

        // a note with a button that stays until it is clicked (10/21: a new version waiting while the window is open);
        // a Say after it replaces it - the one who offered it offers it again
        Action noteAct;
        public bool Offering => NoteAct.Visibility == Visibility.Visible;
        public void Offer(string t, string button, Action act)
        {
            Note.Text = t; NoteAct.Content = button; AutomationProperties.SetName(NoteAct, button); noteAct = act;
            NoteAct.Visibility = Visibility.Visible; NoteBar.Visibility = Visibility.Visible; noteTimer.Stop();
        }

        // --- the layout follows the window's width (less margin, the app's name and the button words go as it narrows)
        void UpdateColumns()
        {
            var g = Pages.Home.TileGrid; if (g == null || Scroll.ActualWidth <= 0) return;
            g.Columns = Math.Max(1, Math.Min(Math.Max(1, Math.Min(5, g.Children.Count)), (int)Math.Floor(Math.Min(Body.MaxWidth, Scroll.ActualWidth - 2 * Body.Margin.Left) / 200)));
        }
        // the top bar fits its width by itself (10/25: fixed widths broke with each new tab - 800 px slid Settings under Search):
        // everything with its words first; then, while it doesn't fit, the words go - the buttons' on the right, the app's
        // name, the tabs' (their icons stay, the names in their tooltips). The tabs sit centered on the window when there's
        // room for that, else between the logo and the buttons.
        void FitTopBar(double avail)
        {
            void Words(bool side, bool name, bool tabs, bool logo = true)
            {
                Logo.Visibility = logo ? Visibility.Visible : Visibility.Collapsed;
                if (AiPill.Content is StackPanel ap && ap.Children.Count > 1) ap.Children[1].Visibility = side ? Visibility.Visible : Visibility.Collapsed;
                if (sBtn?.Content is StackPanel sp && sp.Children.Count > 1) { sp.Children[1].Visibility = side ? Visibility.Visible : Visibility.Collapsed; sBtn.Padding = side ? Ui.Th("12,6") : Ui.Th("9,6"); }
                AppName.Visibility = name ? Visibility.Visible : Visibility.Collapsed;
                foreach (var n in nav.Values) { var row = (StackPanel)n.Button.Content; row.Children[1].Visibility = tabs ? Visibility.Visible : Visibility.Collapsed; ((FrameworkElement)row.Children[0]).Margin = tabs ? Ui.Th("0,0,8,0") : new Thickness(0); }
            }
            double W(UIElement e) { e.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity)); return e.DesiredSize.Width; }   // (after TopBar.UpdateLayout - else the sizes from before a word went)
            var parts = TopBar.Children.Cast<UIElement>().ToList();
            UIElement left = parts.FirstOrDefault(c => Grid.GetColumn(c) == 0), mid = parts.FirstOrDefault(c => Grid.GetColumn(c) == 1), right = parts.FirstOrDefault(c => Grid.GetColumn(c) == 2);
            double Need(bool centered) { double l = left != null ? W(left) : 0, r = right != null ? W(right) : 0, c = mid != null ? W(mid) : 0; return centered ? c + 2 * Math.Max(l, r) + 32 : l + c + r + 32; }
            bool centered = true;
            foreach (var (side, name, tabs, logo) in new[] { (true, true, true, true), (false, true, true, true), (false, false, true, true), (false, false, false, true), (false, false, false, false) })
            {
                Words(side, name, tabs, logo); TopBar.UpdateLayout();
                if (Need(true) <= avail) { centered = true; break; }
                if (Need(false) <= avail) { centered = false; break; }
                centered = false;
            }
            var star = new GridLength(1, GridUnitType.Star);
            TopBar.ColumnDefinitions[0].Width = centered ? star : GridLength.Auto; TopBar.ColumnDefinitions[2].Width = centered ? star : GridLength.Auto; TopBar.ColumnDefinitions[1].Width = centered ? GridLength.Auto : star;
        }
        void UpdateLayout2()
        {
            var w = ActualWidth; if (w <= 0) return;
            bool chat = ChatPanel.Visibility == Visibility.Visible, full = chat && w < 900; double mainW;
            var star = new GridLength(1, GridUnitType.Star);
            if (full) { MainCol.MinWidth = 0; MainCol.Width = new GridLength(0); ChatCol.MinWidth = 0; ChatCol.MaxWidth = double.PositiveInfinity; ChatCol.Width = star; ChatSplit.Visibility = Visibility.Collapsed; mainW = 0; }
            else if (chat)
            {
                MainCol.Width = star; MainCol.MinWidth = 360; ChatCol.MinWidth = 320; ChatCol.MaxWidth = Math.Max(320, w - 380);
                // the chat as wide as it was made (dragged), but the page keeps about half of a smaller window (10/25: a chat
                // dragged wide on the 2560 px screen left the page a 370 px strip in a half-screen window); a drag just made: as dragged
                var room = dragged ? ChatCol.MaxWidth : Math.Max(320, w - Math.Max(380, Math.Min(900, w * 0.45))); dragged = false;
                ChatCol.Width = new GridLength(Math.Min(chatW, room));
                ChatSplit.Visibility = Visibility.Visible; mainW = w - ChatCol.Width.Value;
            }
            else { MainCol.Width = star; MainCol.MinWidth = 0; ChatCol.MinWidth = 0; ChatCol.Width = new GridLength(0); ChatSplit.Visibility = Visibility.Collapsed; mainW = w; }
            var m = mainW < 640 ? 12 : 24;
            TopBar.Margin = new Thickness(m, 14, m, 4); Body.Margin = new Thickness(m, 14, m, 28); NowBar.Margin = new Thickness(m, 8, m, 0);
            var chrome = Content is FrameworkElement ce && ce.ActualWidth > 0 ? Math.Max(0, ActualWidth - ce.ActualWidth) : 16;   // (the window's own frame)
            FitTopBar(mainW - 2 * m - (full || !chat ? chrome : 0));
            var narrow = mainW < 660;   // the page's own tabs go under its title
            DockPanel.SetDock(SubBox, narrow ? Dock.Bottom : Dock.Right);
            SubBox.HorizontalAlignment = narrow ? HorizontalAlignment.Left : HorizontalAlignment.Stretch; SubBox.Margin = narrow ? Ui.Th("0,12,0,0") : Ui.Th("16,0,0,0");
            UpdateColumns();
            if (snap != null && FlowCols() != flowCols) Dispatcher.BeginInvoke(new Action(() => Draw(false)), DispatcherPriority.Background);   // (the columns follow the window)
        }
    }
}
