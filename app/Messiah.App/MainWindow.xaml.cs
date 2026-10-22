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
        // --- pages: three tabs, two of them with sub-pages (the pills on the right of the page title)
        static readonly Dictionary<string, string[]> SubPages = new Dictionary<string, string[]> { ["Activity"] = new[] { "Checks", "Stability", "Trends", "Performance", "Alerts" }, ["Settings"] = new[] { "General", "Windows", "Tools" } };
        static readonly Dictionary<string, string> Subs = new Dictionary<string, string> {
            ["Welcome"] = "Your PC is set up. Here is what happened and what happens from now on.",
            ["Status"] = "Every optimization Messiah keeps in place on this PC - and whether it still is.",
            ["Activity/Checks"] = "What the maintenance found, what it did, and when it runs next.", ["Activity/Trends"] = "How this PC has been doing over time.",
            ["Activity/Stability"] = "Every blue screen and power-off, and what changed around them.", ["Activity/Performance"] = "How your games run - each minute measured while you play, and what updates did to them.", ["Activity/Alerts"] = "What Messiah had to say - kept here instead of popping up.",
            ["Settings/General"] = "Everything Messiah does is yours to switch on or off.", ["Settings/Windows"] = "Each change Messiah makes in Windows - keep it or not.",
            ["Settings/Tools"] = "Updates, repairs, drivers, the BIOS and the install USB." };
        static readonly Dictionary<string, string> OldPages = new Dictionary<string, string> { ["Overview"] = "Home", ["Sessions"] = "Home", ["Maintenance"] = "Activity/Checks", ["Schedule"] = "Activity/Checks", ["History"] = "Activity/Trends", ["Notifications"] = "Activity/Alerts" };
        readonly Dictionary<string, string> sub = new Dictionary<string, string> { ["Activity"] = "Checks", ["Settings"] = "General" };
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
            else { var a = SystemParameters.WorkArea; Width = Math.Min(1040, a.Width); Height = Math.Min(780, a.Height); Left = a.Left + (a.Width - Width) / 2; Top = a.Top + (a.Height - Height) / 2; }
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
        void FitToScreen()
        {
            if (WindowState != WindowState.Normal) return;
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
            var pages = (WelcomeShown ? new[] { ("Welcome", "E8E1") } : new (string, string)[0]).Concat(new (string, string)[] { ("Home", "E80F"), ("Status", "EA18"), ("Activity", "E81C"), ("Settings", "E713") }).ToArray();
            foreach (var (p, g) in pages)
            {
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
        }
        public void ShowPage(string p, string s = null)
        {
            if (OldPages.TryGetValue(p, out var np)) { var x = np.Split('/'); p = x[0]; if (x.Length > 1) s = x[1]; }
            if (s != null) sub[p] = s;
            if (!nav.ContainsKey(p)) return;
            if (nav[p].Button.IsChecked == true) { onPage = p; UpdateSub(); Draw(true); } else nav[p].Button.IsChecked = true;
        }
        void UpdateSub()
        {
            SubNav.Children.Clear();
            SubPages.TryGetValue(onPage, out var list);
            SubBox.Visibility = list != null ? Visibility.Visible : Visibility.Collapsed;
            foreach (var s in list ?? new string[0])
            {
                var rb = new RadioButton { GroupName = "sub", Tag = s, Content = s, IsChecked = s == sub[onPage], Style = (Style)FindResource("Pill") };
                rb.Checked += (x, e) => { sub[onPage] = s; Say(""); Scroll.ScrollToTop(); Draw(true); };
                SubNav.Children.Add(rb);
            }
        }
        string PageKey => SubPages.ContainsKey(onPage) ? onPage + "/" + sub[onPage] : onPage;

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
            nav["Home"].Count.Text = todo > 0 ? todo.ToString() : ""; ((Border)nav["Home"].Count.Parent).Visibility = todo > 0 ? Visibility.Visible : Visibility.Collapsed;
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
            foreach (var el in els) PageContent.Children.Add(el);
            UpdateColumns();
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
            g.Columns = Math.Max(1, Math.Min(Math.Max(1, Math.Min(5, g.Children.Count)), (int)Math.Floor(Math.Min(1100, Scroll.ActualWidth - 2 * Body.Margin.Left) / 200)));
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
                if (!ChatCol.Width.IsAbsolute || ChatCol.Width.Value < 1) ChatCol.Width = new GridLength(Math.Min(chatW, ChatCol.MaxWidth));
                ChatSplit.Visibility = Visibility.Visible; mainW = w - ChatCol.Width.Value;
            }
            else { MainCol.Width = star; MainCol.MinWidth = 0; ChatCol.MinWidth = 0; ChatCol.Width = new GridLength(0); ChatSplit.Visibility = Visibility.Collapsed; mainW = w; }
            var m = mainW < 640 ? 12 : 24;
            TopBar.Margin = new Thickness(m, 14, m, 4); Body.Margin = new Thickness(m, 14, m, 28); NowBar.Margin = new Thickness(m, 8, m, 0);
            AppName.Visibility = mainW < 780 ? Visibility.Collapsed : Visibility.Visible;
            if (AiPill.Content is StackPanel ap && ap.Children.Count > 1) ap.Children[1].Visibility = mainW < 620 ? Visibility.Collapsed : Visibility.Visible;
            foreach (var n in nav.Values) { var row = (StackPanel)n.Button.Content; row.Children[1].Visibility = mainW < 560 ? Visibility.Collapsed : Visibility.Visible; ((FrameworkElement)row.Children[0]).Margin = mainW < 560 ? new Thickness(0) : Ui.Th("0,0,8,0"); }
            var narrow = mainW < 660;   // the page's own tabs go under its title
            DockPanel.SetDock(SubBox, narrow ? Dock.Bottom : Dock.Right);
            SubBox.HorizontalAlignment = narrow ? HorizontalAlignment.Left : HorizontalAlignment.Stretch; SubBox.Margin = narrow ? Ui.Th("0,12,0,0") : Ui.Th("16,0,0,0");
            UpdateColumns();
        }
    }
}
