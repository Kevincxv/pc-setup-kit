using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace Messiah
{
    // Windows' app theme (Settings > Personalization > Colors). Cards are see-through layers (Windows 11 style), so they
    // work on the Mica backdrop and on the plain background used where Mica isn't available. (dashboard.ps1's $c)
    static class Theme
    {
        public static bool Light;
        public static Dictionary<string, string> C;
        public static readonly Dictionary<string, SolidColorBrush> B = new Dictionary<string, SolidColorBrush>();
        public static readonly FontFamily Icons = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets");
        public static readonly FontFamily Display = new FontFamily("Segoe UI Variable Display, Segoe UI");
        public static readonly FontFamily TextFont = new FontFamily("Segoe UI Variable Text, Segoe UI");
        public static readonly FontFamily Mono = new FontFamily("Cascadia Mono, Consolas");

        public static void Load()
        {
            try { Light = (int)(Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 0) ?? 0) == 1; } catch { Light = false; }
            C = Light ? new Dictionary<string, string> {
                ["Bg"] = "#F3F3F3", ["Card"] = "#CCFFFFFF", ["CardHover"] = "#F2FFFFFF", ["Border"] = "#12000000", ["Text"] = "#E4000000", ["Sub"] = "#9E000000", ["Accent"] = "#5B57E8",
                ["Ok"] = "#0F7B0F", ["Warn"] = "#9D5D00", ["Btn"] = "#CCFFFFFF", ["BtnHover"] = "#F5FFFFFF", ["Seg"] = "#0C000000", ["SegSel"] = "#FFFFFFFF", ["NavHover"] = "#08000000",
                ["Grad1"] = "#7C5CFF", ["Grad2"] = "#3E8BF2", ["OnAccent"] = "#FFFFFF", ["Chart"] = "#6D5AE6", ["Divider"] = "#0F000000", ["Toast"] = "#FFFBFBFB" }
            : new Dictionary<string, string> {
                ["Bg"] = "#202020", ["Card"] = "#0FFFFFFF", ["CardHover"] = "#16FFFFFF", ["Border"] = "#14FFFFFF", ["Text"] = "#FFFFFF", ["Sub"] = "#C5FFFFFF", ["Accent"] = "#A8A6FF",
                ["Ok"] = "#6CCB5F", ["Warn"] = "#FFC83D", ["Btn"] = "#12FFFFFF", ["BtnHover"] = "#1CFFFFFF", ["Seg"] = "#0CFFFFFF", ["SegSel"] = "#1FFFFFFF", ["NavHover"] = "#0AFFFFFF",
                ["Grad1"] = "#7C5CFF", ["Grad2"] = "#3E8BF2", ["OnAccent"] = "#FFFFFF", ["Chart"] = "#8F7DFF", ["Divider"] = "#10FFFFFF", ["Toast"] = "#FF2C2C2C" };   // Chart: validated (dataviz) on each surface
            B.Clear();
            foreach (var kv in C) { var b = new SolidColorBrush((Color)ColorConverter.ConvertFromString(kv.Value)); b.Freeze(); B[kv.Key] = b; }
        }
        // the brushes and fonts as resources for the XAML (Styles.xaml uses {DynamicResource c.Btn} and so on)
        public static void Apply(ResourceDictionary rd)
        {
            foreach (var kv in B) rd["c." + kv.Key] = kv.Value;
            rd["c.Grad1Color"] = (Color)ColorConverter.ConvertFromString(C["Grad1"]);
            rd["c.Grad2Color"] = (Color)ColorConverter.ConvertFromString(C["Grad2"]);
            rd["f.Icons"] = Icons; rd["f.Display"] = Display;
        }
        public static SolidColorBrush Level(string lv) => lv == "ok" ? B["Ok"] : lv == "warn" ? B["Warn"] : lv == "dim" ? B["Sub"] : B["Text"];
        public static SolidColorBrush Tint(SolidColorBrush b, byte alpha) { var c = b.Color; c.A = alpha; var t = new SolidColorBrush(c); t.Freeze(); return t; }   // a status color, faint
        public static Brush OnColor => Light ? Brushes.White : Brushes.Black;   // text on an Ok/Warn badge
        public static Brush Gradient(double angle = 45) => new LinearGradientBrush((Color)ColorConverter.ConvertFromString(C["Grad1"]), (Color)ColorConverter.ConvertFromString(C["Grad2"]), angle);
    }
}
