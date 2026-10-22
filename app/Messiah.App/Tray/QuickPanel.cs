using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Messiah.Tray
{
    // The tray icon's quick panel (10/22 - PowerToys' Quick Access, FanControl's tray): a left-click shows the status, the
    // processor's and graphics card's temperature now, the Game Mode switch and the main actions above the clock, without
    // opening the window; it closes when anything else is clicked. A double-click still opens the window.
    class QuickPanel : Window
    {
        readonly StackPanel body = new StackPanel();
        readonly TextBlock temps;
        public QuickPanel(Action open, Action runMaint, Action<int> pause)
        {
            WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; ShowInTaskbar = false; Topmost = true;
            SizeToContent = SizeToContent.WidthAndHeight; AllowsTransparency = true; Background = Brushes.Transparent;
            var card = new Border { Background = Theme.B["Card"], BorderBrush = Theme.B["Border"], BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12), Padding = Ui.Th("18,16"), Width = 340, Margin = Ui.Th("8") };
            card.Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 20, ShadowDepth = 3, Opacity = 0.35, Color = Colors.Black };
            card.Child = body; Content = card;
            var todo = TrayLogic.Todo().Count;
            var head = new DockPanel { Margin = Ui.Th("0,0,0,10") };
            var dot = new System.Windows.Shapes.Ellipse { Width = 10, Height = 10, Fill = todo > 0 ? Theme.B["Warn"] : Theme.B["Ok"], Margin = Ui.Th("0,0,10,0"), VerticalAlignment = VerticalAlignment.Center };
            head.Children.Add(dot);
            head.Children.Add(Ui.Text(todo > 0 ? $"{todo} thing{Kit.S(todo)} need{(todo == 1 ? "s" : "")} you" : "All good - nothing needs you", Theme.B["Text"], 15, FontWeights.SemiBold, "0"));
            body.Children.Add(head);
            var playing = Data.Playing();
            if (playing != "") body.Children.Add(Ui.Text($"Playing {Data.GameName(playing)} - maintenance waits", Theme.B["Sub"], 12, null, "0,0,0,8"));
            temps = Ui.Text("Processor ...\nGraphics card ...", Theme.B["Sub"], 13, null, "0,0,0,12");
            body.Children.Add(temps);
            // Game Mode: what runs beside a game steps back (kit-options.txt gameboost)
            var gm = Ui.SwitchRow("Game Mode", "Background programs step back while a game runs.", Kit.Opt("gameboost", "on") == "on", sw => Kit.SetOpt("gameboost", sw.IsChecked == true ? "on" : "off"), "gameboost");
            body.Children.Add(gm);
            var row = new WrapPanel();
            row.Children.Add(Ui.Btn("E8A7", "Open " + TrayLogic.Name, () => { Close(); open?.Invoke(); }, accent: true));
            row.Children.Add(Ui.Btn("E768", "Run maintenance", () => { Close(); runMaint?.Invoke(); }));
            row.Children.Add(Ui.Btn("E769", "Pause 2 h", () => { Close(); pause?.Invoke(2); }));
            body.Children.Add(row);
            Deactivated += (s, e) => { try { Close(); } catch { } };
            Loaded += (s, e) => { Place(); Activate(); };
            if (!Kit.InTests) Task.Run(() => ReadTemps());
        }
        // above the clock: the bottom-right of the main screen's work area (the taskbar's side)
        void Place()
        {
            var wa = SystemParameters.WorkArea; UpdateLayout();
            Left = wa.Right - ActualWidth - 4; Top = wa.Bottom - ActualHeight - 4;
        }
        // the temperatures now: the processor through cpu-temp.ps1 (its driver), the graphics card through nvidia-smi
        void ReadTemps()
        {
            string Run(string exe, string args) { try { using (var p = Process.Start(new ProcessStartInfo(exe, args) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true })) { var o = p.StandardOutput.ReadToEnd(); p.WaitForExit(15000); return o.Trim(); } } catch { return ""; } }
            var cpu = Run("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -File \"{Kit.P("cpu-temp.ps1")}\" -Print");
            var g = Run("nvidia-smi", "--query-gpu=temperature.gpu,fan.speed --format=csv,noheader,nounits").Split('\n').FirstOrDefault()?.Split(',').Select(x => x.Trim()).ToArray() ?? new string[0];
            var parts = new List<string>();
            parts.Add(cpu != "" ? $"Processor {cpu} °C" : "Processor -");
            if (g.Length >= 1 && double.TryParse(g[0], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var gt)) parts.Add($"Graphics card {Math.Round(gt)} °C" + (g.Length >= 2 && g[1] != "" ? (g[1] == "0" ? ", fans stopped" : $", fans {g[1]}%") : ""));
            Dispatcher.BeginInvoke(new Action(() => { temps.Text = string.Join("\n", parts); Place(); }));
        }
        // the panel's words (--test)
        public IEnumerable<string> Words() => App.Unnamed(this).Select(x => "A11Y: " + x).Concat(new[] { string.Join(" | ", Texts(body)).Replace("\n", " / ") });
        static IEnumerable<string> Texts(object el)
        {
            if (el is TextBlock tb) { var t = tb.Text != "" ? tb.Text : new System.Windows.Documents.TextRange(tb.ContentStart, tb.ContentEnd).Text; if (t != "") yield return t; yield break; }
            if (el is Button b) { yield return "[" + (System.Windows.Automation.AutomationProperties.GetName(b) is string n && n != "" ? n : b.ToolTip?.ToString()) + "]"; yield break; }
            if (el is Panel p) foreach (var c in p.Children) foreach (var s in Texts(c)) yield return s;
            if (el is Decorator d) foreach (var s in Texts(d.Child)) yield return s;
        }
    }
}
