using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Microsoft.Win32;

namespace Messiah.Tray
{
    // Telling the owner something: a Windows notification (Action Center keeps it; Focus Assist and "do not disturb"
    // hold it) where Windows allows them, else the app's own small note in the corner - never taking focus, gone after a
    // while. A click does what it says (a "messiah:" link: the app opens there).
    static class Notes
    {
        public const string Aumid = "Messiah.PCSetupKit";
        static Window note; static DispatcherTimer closeTimer;

        // the app as a sender of notifications (its name and icon) and the "messiah:" links a click follows - per user,
        // no admin rights; once per start (cheap)
        public static void Register()
        {
            try
            {
                var exe = System.Diagnostics.Process.GetCurrentProcess().MainModule.FileName;
                var png = Path.Combine(Path.GetDirectoryName(exe), "messiah.png");
                var ico = Path.Combine(Kit.TrayDir, "app.ico");
                if (File.Exists(ico) && (!File.Exists(png) || File.GetLastWriteTime(png) < File.GetLastWriteTime(ico)))
                    using (var i = new Icon(ico, 256, 256)) using (var b = i.ToBitmap()) b.Save(png, System.Drawing.Imaging.ImageFormat.Png);
                using (var k = Registry.CurrentUser.CreateSubKey(@"Software\Classes\AppUserModelId\" + Aumid))
                { k.SetValue("DisplayName", TrayLogic.Name); if (File.Exists(png)) k.SetValue("IconUri", png); }
                using (var k = Registry.CurrentUser.CreateSubKey(@"Software\Classes\messiah"))
                {
                    k.SetValue("", "URL:Messiah"); k.SetValue("URL Protocol", "");
                    using (var c = k.CreateSubKey(@"shell\open\command")) c.SetValue("", $"\"{exe}\" --live --uri \"%1\"");
                }
            }
            catch (Exception e) { TrayLogic.Error("notes register: " + e.Message); }
        }

        // link: what a click opens - "page=Chat", "chat=<tab>" or "" (the app); seconds: the corner note's time
        public static void Show(string text, string link = "", int seconds = 20)
        {
            if (Kit.InTests) return;
            if (Toast(text, link)) return;
            Corner(text, link, seconds);
        }

        // --- a Windows notification (WinRT, found at run time: no Windows SDK needed to build). False: not allowed here
        // (notifications switched off - the kit's "All app notifications off" - or Windows refuses), use the corner note.
        static bool Toast(string text, string link)
        {
            try
            {
                var mgr = Type.GetType("Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime");
                var xmlT = Type.GetType("Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime");
                var toastT = Type.GetType("Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType=WindowsRuntime");
                if (mgr == null || xmlT == null || toastT == null) return false;
                var notifier = mgr.GetMethod("CreateToastNotifier", new[] { typeof(string) }).Invoke(null, new object[] { Aumid });
                if (notifier.GetType().GetProperty("Setting").GetValue(notifier).ToString() != "Enabled") return false;
                var lines = text.Split('\n'); string X(string s) => System.Security.SecurityElement.Escape(s);
                var xml = $"<toast activationType=\"protocol\" launch=\"messiah:{X(link)}\"><visual><binding template=\"ToastGeneric\"><text>{X(lines[0])}</text>" +
                          string.Concat(lines.Skip(1).Take(2).Select(l => $"<text>{X(l)}</text>")) + "</binding></visual></toast>";
                var doc = Activator.CreateInstance(xmlT); xmlT.GetMethod("LoadXml", new[] { typeof(string) }).Invoke(doc, new object[] { xml });   // (LoadXml has two overloads)
                var toast = Activator.CreateInstance(toastT, doc);
                notifier.GetType().GetMethod("Show", new[] { toastT }).Invoke(notifier, new[] { toast });
                return true;
            }
            catch (Exception e) { TrayLogic.Error("toast: " + (e.InnerException ?? e).Message); return false; }
        }

        // --- the corner note: dark card bottom-right, fades in, never takes focus
        static void Corner(string text, string link, int seconds)
        {
            Close();
            var accent = (SolidColorBrush)new BrushConverter().ConvertFrom("#60CDFF"); var dim = (SolidColorBrush)new BrushConverter().ConvertFrom("#8A8A8A");
            var head = new DockPanel();
            var x = new TextBlock { Text = "✕", Foreground = dim, FontSize = 13, Cursor = Cursors.Hand, Margin = new Thickness(8, 0, 0, 0) }; x.MouseLeftButtonUp += (s, e) => { e.Handled = true; Close(); };
            DockPanel.SetDock(x, Dock.Right); head.Children.Add(x);
            head.Children.Add(new TextBlock { Text = TrayLogic.Name, Foreground = accent, FontWeight = FontWeights.Bold, FontSize = 13 });
            var body = new StackPanel { Width = 330 };
            body.Children.Add(head);
            body.Children.Add(new TextBlock { Text = text, Foreground = (SolidColorBrush)new BrushConverter().ConvertFrom("#F0F0F0"), FontSize = 13, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 6, 0, 0) });
            body.Children.Add(new TextBlock { Text = link.StartsWith("chat=") ? "Click to open the chat" : link == "-" ? "Click to close" : "Click for details", Foreground = dim, FontSize = 11, Margin = new Thickness(0, 10, 0, 0) });
            var card = new Border { Background = (SolidColorBrush)new BrushConverter().ConvertFrom("#202020"), BorderBrush = (SolidColorBrush)new BrushConverter().ConvertFrom("#3A3A3A"), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8), Padding = new Thickness(20, 16, 20, 16), Child = body, Cursor = Cursors.Hand };
            card.MouseLeftButtonUp += (s, e) => { Close(); if (link != "-") Open(link); };
            note = new Window { WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = System.Windows.Media.Brushes.Transparent, ShowActivated = false, ShowInTaskbar = false, Topmost = true, SizeToContent = SizeToContent.WidthAndHeight, Content = card, FontFamily = new System.Windows.Media.FontFamily("Segoe UI Variable Text, Segoe UI"), Opacity = 0 };
            note.SourceInitialized += (s, e) => { var h = new WindowInteropHelper(note).Handle; Native.SetWindowLong(h, -20, Native.GetWindowLong(h, -20) | 0x08000000 | 0x80); };   // no-activate, tool window
            note.Loaded += (s, e) => { var wa = SystemParameters.WorkArea; note.Left = wa.Right - note.ActualWidth - 16; note.Top = wa.Bottom - note.ActualHeight - 16; note.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(150))); };
            note.Show();
            closeTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(seconds) }; closeTimer.Tick += (s, e) => Close(); closeTimer.Start();
        }
        public static void Close() { closeTimer?.Stop(); try { note?.Close(); } catch { } note = null; }

        // what a click opens (a toast's "messiah:" link arrives the same way, through App's --uri)
        public static void Open(string link)
        {
            var m = System.Text.RegularExpressions.Regex.Match(link ?? "", @"^(page|chat)=([\w/-]*)$");
            // (the request file, as the show signal from another start: ShowApp reads it - a chat tab, or a page)
            if (m.Success) try { File.WriteAllText(Kit.P(App.Names.RequestFile), m.Groups[1].Value + "=" + m.Groups[2].Value); } catch { }
            Shell.W?.ShowApp();
        }
    }
}
