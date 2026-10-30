using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;

namespace Messiah.Pages
{
    // Welcome (dashboard.ps1's Build-Page 'Welcome'): after a new install, until "Got it" - what setup did, and what
    // happens from now on
    static class Welcome
    {
        public static List<UIElement> Build(Snapshot s)
        {
            var o = new List<UIElement>();
            var hero = new DockPanel();   // (10/25 audit: a row let the words run off a narrow window - docked, they wrap)
            var badge = new Border { Width = 56, Height = 56, CornerRadius = new CornerRadius(28), Margin = Ui.Th("0,0,18,0"), VerticalAlignment = VerticalAlignment.Center, Background = Theme.Gradient() };
            var bg = Ui.Glyph("E73E", 26, Theme.B["OnAccent"]); bg.HorizontalAlignment = HorizontalAlignment.Center; badge.Child = bg;
            var txt = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            txt.Children.Add(Ui.Text("This PC is ready", Theme.B["Text"], 22, FontWeights.SemiBold, "0"));
            txt.Children.Add(Ui.Text("Windows is updated, tuned for games and set up to look after itself. Nothing else to do.", Theme.B["Sub"], 13, null, "0,2,0,0"));
            DockPanel.SetDock(badge, Dock.Left); hero.Children.Add(badge); hero.Children.Add(txt);
            var btns = new List<UIElement> { Ui.Btn("E73E", "Got it", () => Shell.W.Welcomed(), accent: true) };
            // Chrome installed, Edge still the browser: Windows' own Chrome page, one "Set default" click (no program may switch it)
            var https = (Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice", "ProgId", "") ?? "").ToString();
            string where = Registry.GetValue(@"HKEY_LOCAL_MACHINE\SOFTWARE\RegisteredApplications", "Google Chrome", null) != null ? "registeredAppMachine" : Registry.GetValue(@"HKEY_CURRENT_USER\SOFTWARE\RegisteredApplications", "Google Chrome", null) != null ? "registeredAppUser" : null;
            if (where != null && (https == "" || https.StartsWith("MSEdge"))) btns.Add(Ui.Btn("E774", "Make Chrome your browser", () => Actions.Open($"ms-settings:defaultapps?{where}=Google%20Chrome")));
            o.Add(Ui.Card(null, null, new object[] { hero }, btns));
            // what setup did: the report's "WHAT WAS DONE" (optimize.ps1), the main lines
            var repF = Path.Combine(Kit.Home, "Documents", "PC Setup Kit report.txt");
            var rep = Kit.Lines(repF); int i = Array.IndexOf(rep, "WHAT WAS DONE"), j = Array.IndexOf(rep, "WHAT NEEDS YOU");
            var did = i >= 0 && j > i ? rep.Skip(i + 1).Take(j - i - 1).Select(x => x.Trim())
                .Where(x => x != "" && !Regex.IsMatch(x, @"^(WARNING|Reminder|Restore point|Next:|Checked|\[|Apps: \d|Crashes: none|Tweaks: all|Maintenance: running|Maintenance \(|Other drivers: all up to date|Next:)|FAILED|timed out|could not run"))
                .Distinct().Take(10).Select(x => (object)new Line("- " + x)).ToList() : new List<object>();
            if (did.Count == 0) did = new List<object> { new Line("- Windows updated, drivers and apps installed, the screen at its best resolution and refresh rate"), new Line("- Telemetry, ads and bloat off; the best power plan; games tuned (each change is yours to switch off in Settings)") };
            o.Add(Ui.Card("What was done", "E9D5", did, rep.Length > 0 ? new[] { Ui.Btn("E8A5", "The full report", () => Actions.Open("notepad.exe", $"\"{repF}\"")) } : null));
            o.Add(Ui.Card("From now on", "E823", new object[] {
                new Line("- At every login Messiah checks for updates, drivers, crashes, temperatures and disk space in the background, and waits while you play."),
                new Line("- It never restarts the PC: what needs a restart finishes the next time you turn it off."),
                new Line("- It updates itself, and puts your settings back after Windows updates."),
                new Line("- It works quietly from the hidden tray (^ next to the clock) and never pops up. Ctrl+Alt+M opens this window; Home says when something needs you.") }));
            var opt = new List<UIElement>();
            if (!s.Ai) opt.Add(Ui.Btn("E99A", "Switch on the AI assistant", () => Actions.AiOn()));
            opt.Add(Ui.Btn("E771", "Review what Messiah changes", () => Shell.ShowPage("Settings", "Windows")));
            opt.Add(Ui.Btn("E88E", "Make an install USB", Actions.MakeUsb));
            o.Add(Ui.Card("Optional", "E734", new object[] { new Line("None of this is needed. The AI assistant (Claude, with your own account) can look after the PC with you; an install USB sets up another PC - or this one again - the same way.", "dim") }, opt));
            return o;
        }
    }
}
