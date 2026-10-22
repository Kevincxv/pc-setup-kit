using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Shapes;

namespace Messiah.Pages
{
    // Home (dashboard.ps1's Build-Page 'Home'): the status at one glance, what needs the owner, the main facts as tiles
    static class Home
    {
        static SolidColorBrush B(string k) => Theme.B[k];
        public static UniformGrid TileGrid;   // (the window sets its columns to its width)

        public static List<UIElement> Build(Snapshot s)
        {
            var o = new List<UIElement>();
            var needs = s.Sec("Needs you"); var last = s.Sec("Last background check"); var sched = s.Sec("Scheduled checks"); var wait = s.Sec("Waiting for");
            var todo = needs.Lines.Where(l => l.Level == "warn").ToList(); var warn = last.Lines.Where(l => l.Level == "warn").ToList();
            var sm = s.Sm;
            (string Lv, string Mid, string Say) st =
                todo.Count > 0 ? ("warn", todo.Count.ToString(), $"{todo.Count} thing{Kit.S(todo.Count)} need{(todo.Count == 1 ? "s" : "")} you") :
                warn.Count > 0 ? ("warn", "E9F5", "The last check found something - it is being handled") :
                sm.Warn > 0 ? ("warn", sm.Warn.ToString(), $"{sm.Warn} optimization{Kit.S(sm.Warn)} need{(sm.Warn == 1 ? "s" : "")} a look") :
                ("ok", "E73E", "All good - nothing needs you");
            var when = last.Lines.FirstOrDefault(l => Regex.IsMatch(l.Text, "^(Checked|No report)"));
            // the status at one glance: a ring in the status color (the number of things that need the owner, or a check
            // mark), one sentence, when it was last checked - and the main actions under it
            var hero = new Grid();
            hero.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); hero.ColumnDefinitions.Add(new ColumnDefinition());
            var ring = Ui.Ring(96, 5, 34, st.Lv, st.Mid); ring.Margin = Ui.Th("0,0,24,0");
            var txt = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            var ht = Ui.Text(st.Say, B("Text"), 26, FontWeights.SemiBold, "0"); ht.FontFamily = Theme.Display; txt.Children.Add(ht);
            DateTime? whenAt = null; if (when != null) { var m = Regex.Match(when.Text, "^Checked (.+?)( in |$)"); if (m.Success && DateTime.TryParse(m.Groups[1].Value, out var d)) whenAt = d; }
            var whenTxt = whenAt != null ? "Last check " + Kit.FormatWhen(whenAt.Value) : when != null ? when.Text : "No check yet - the first one runs a few minutes after login";
            txt.Children.Add(Ui.Text(whenTxt + (s.KitVersion != "" ? $"  ·  Messiah {s.KitVersion}, updates by itself" : ""), B("Sub"), 13, null, "0,4,0,0"));
            Grid.SetColumn(txt, 1); hero.Children.Add(ring); hero.Children.Add(txt);
            bool statusFirst = sm.Warn > 0 && todo.Count == 0 && warn.Count == 0;
            var heroBtns = new List<UIElement>();
            if (statusFirst) heroBtns.Add(Ui.Btn("EA18", "Open Status", () => Shell.ShowPage("Status"), accent: true));
            heroBtns.Add(Ui.Btn("E768", "Run maintenance now", Actions.RunMaint, accent: !statusFirst && todo.Count == 0));   // (something needs the owner: that is the next step - the card under it - not maintenance)
            heroBtns.Add(Ui.Btn("E945", "Optimize this PC", Actions.Optimize));
            var hc = Ui.Card(null, null, new object[] { hero }, heroBtns); hc.Padding = Ui.Th("26,24"); o.Add(Ui.Wide(hc));

            // what happened while the window was closed (since the owner last looked) - nothing: no card
            if (s.Since != null && s.Since.Count > 0 && s.SinceAt != null) o.Add(Ui.Card("Since you last looked", "E81C", s.Since.Cast<object>().Concat(new object[] { new Line($"{Kit.FormatWhen(s.SinceAt.Value)} - the details are under Activity.", "dim") }).ToArray()));
            // playing right now: everything heavy waits - said, so a quiet Messiah isn't a broken one
            if (s.Playing != "") o.Add(Ui.Card("Playing " + s.Playing, "E7FC", new object[] { new Line("Updates, checks and cleanup wait until you're done - nothing runs that could slow the game or take over the screen. They catch up by themselves afterwards.") }));
            // what's new after an update: until "Got it", three weeks at most
            if (s.WhatsNew != null)
            {
                var pts = Json.L(s.WhatsNew, "points").Select(x => x?.ToString()).Where(x => !string.IsNullOrEmpty(x)).Take(6).Select(x => (object)new Line("- " + x)).ToList();
                if (pts.Count == 0) pts.Add(new Line("Small fixes and improvements."));
                var ver = Json.S(s.WhatsNew, "version"); var url = Json.S(s.WhatsNew, "url");
                var nb = new List<UIElement> { Ui.Btn("E73E", "Got it", () => { Kit.SetOpt("newsseen", ver); Shell.Refresh(true); }, accent: true) };
                if (url != "") nb.Add(Ui.Btn("E774", "All release notes", () => Actions.Open(url)));
                o.Add(Ui.Card($"What's new in Messiah {ver}", "E789", pts, nb));
            }
            if (s.Paused != null) o.Add(Ui.Card("Maintenance paused", "E769", new object[] { new Line($"Until {s.Paused:ddd h:mm tt} - updates, checks and cleanup wait (the tray's Pause maintenance).", "warn") },
                new[] { Ui.Btn("E768", "Resume now", () => { Kit.SetOpt("pause-until", ""); Shell.Say("Maintenance runs again as usual."); Shell.Refresh(true); }) }, calm: true));
            if (todo.Count > 0) o.Add(Ui.Card("Needs you", "E7BA", TodoLines(needs.Lines, s.Ram != null && s.Ram.Count > 0), null, calm: true));

            // the PC went off without a blue screen: did the owner do that? - one at a time, newest first, last 30 days
            var ask = s.Power.Where(e => e.Kind == "off" && e.Answer == "" && e.Key > DateTime.Now.AddDays(-30)).OrderByDescending(e => e.Key).ToList();
            if (ask.Count > 0)
            {
                var q = ask[0];
                var ql = new object[] {
                    new Line($"The PC went off {Kit.FormatWhen(q.At)} without a blue screen{(q.Key != q.At ? $" (it started again {Kit.FormatWhen(q.Key)})" : "")}. Did you turn it off - the power button, the switch, unplugged?", "warn"),
                    new Line($"Your answer tells a freeze or power problem apart from a normal power-off - that changes what the crash hunt looks at next.{(ask.Count > 1 ? $" ({ask.Count - 1} more after this one.)" : "")}", "dim") };
                var qb = new[] { ("E7E8", "Yes, I turned it off", "me"), ("E7BA", "No - it froze or went off by itself", "froze"), ("E897", "Not sure", "unsure") }
                    .Select(a => (UIElement)Ui.Btn(a.Item1, a.Item2, () => { Data.RunPs("power-log.ps1", $"-Answer {a.Item3} -Key {q.KeyText}"); Shell.Say(a.Item3 == "froze" ? "Thanks - noted as a freeze. Claude looks at it with the crash hunt." : "Thanks - noted."); Shell.Refresh(true); }, accent: a.Item3 == "froze")).ToList();
                o.Add(Ui.Card("Did you turn it off?", "E7E8", ql, qb, calm: true));
            }
            // the RAM stick test, while it runs: where the owner is in it and what to do next
            if (s.Ram != null && s.Ram.Count > 0)
                o.Add(Ui.Card("RAM stick test", "E950", s.Ram.Cast<object>(), s.Ai ? new[] { Ui.Btn("E99A", "Ask Claude about it", () => Actions.AskClaude("Help me with the RAM stick test: where am I, and what do I do next?")) } : null, calm: true));

            // the tiles: the main facts at a glance, each a way into its page
            var tiles = new UniformGrid { Columns = 4, Margin = Ui.Th("0,0,-12,2") }; TileGrid = tiles;
            var gs = Kit.ReadJson(Kit.P("guard-state.json"));
            int nAll = sm.Ok + sm.Warn; bool guardOld = sm.At != null && sm.Stale;
            var guardVal = sm.Warn > 0 ? $"{sm.Warn} need{(sm.Warn == 1 ? "s" : "")} a look" : sm.At != null ? $"{sm.Ok} of {nAll} in place" : "Ready";
            var firstWarn = sm.Rows.FirstOrDefault(r => r.Level == "warn");
            var fixedN = (int)(Json.N(gs, "fixed") ?? 0);
            var guardSub = firstWarn != null ? firstWarn.State + " - see Status" : sm.At == null ? "Checked every 4 hours" : guardOld ? $"Last checked {Kit.FormatWhen(sm.At.Value, shortForm: true)} - it runs again soon"
                : fixedN > 0 ? $"{fixedN} put back {Kit.FormatWhen(sm.At.Value, shortForm: true)}" : $"Checked {Kit.FormatWhen(sm.At.Value, shortForm: true)} - all in place";
            if (sm.Warn > 0) guardOld = true;   // (the tile in the warning color)
            var next = sched.Lines.Select(l => Regex.Match(l.Text, @"^([^:]+):\s+(.*)$")).FirstOrDefault(m => m.Success);
            var p = s.PerfLast; var h = s.HealthLast; var free = Json.N(h, "freeGB");
            tiles.Children.Add(Ui.Tile("EA18", "Guarded", guardVal, guardSub, guardOld ? "warn" : "info", "Status"));
            tiles.Children.Add(Ui.Tile("E7FC", "Last game", p != null ? $"{Math.Round(Json.N(p, "fps") ?? 0)} fps" : "Nothing yet", p != null ? $"{Data.GameName(Json.S(p, "game"))}, 1% low {Math.Round(Json.N(p, "low1") ?? 0)} fps" : "Measured while you play", "info", "Activity/Trends"));
            tiles.Children.Add(Ui.Tile("EDA2", "Free space on C:", free != null ? $"{Math.Round(free.Value)} GB" : "-", "Cleaned up every week", free != null && free < 30 ? "warn" : "info", "Activity/Trends"));
            tiles.Children.Add(Ui.Tile("E787", "Next", next != null ? next.Groups[1].Value : "At login", next != null ? Kit.FormatLine(next.Groups[2].Value) : "And every 4 hours", "info", "Activity/Checks"));
            o.Add(tiles);
            if (wait.Lines.Any(l => !l.Text.StartsWith("Nothing"))) o.Add(Ui.Card(wait.Title, "E777", wait.Lines.Cast<object>()));
            if (s.Ai)
            {
                var cs = s.Chat;
                var line = new Line(cs != null && Json.B(cs, "busy") ? "Working right now" + (Json.S(cs, "step") != "" ? ": " + Json.S(cs, "step") : "") : cs != null ? "Ready - your conversation is kept, so you can pick up where you left off" : "Chat with Claude right here - it can look at this PC and fix things, with admin rights");
                o.Add(Ui.Card("Claude", "E99A", new object[] { line, new Line("Your Claude account; what it does shows in the chat as it happens. Nothing runs in a terminal.", "dim") }, new[] { Ui.Btn("E8BD", "Open chat", Actions.OpenChat, accent: true) }));
            }
            return o;
        }

        // to-do items with their own buttons: the place to fix it where there is one, "Snooze a week" and "Dismiss"
        static (string Label, string Target)? TodoFix(string t)
        {
            var m = Regex.Match(t, @"(https://[^\s)]+?)[.,;]?(\s|$)"); if (m.Success) return ("Open the page", m.Groups[1].Value);
            if (Regex.IsMatch(t, "previous graphics driver")) return ("Go back to the previous driver", "kit:gpu-rollback");
            m = Regex.Match(t, @"^(.+?) is installed - .*the Uninstall button here"); if (m.Success) return ("Uninstall " + m.Groups[1].Value, "kit:uninstall:" + m.Groups[1].Value);
            if (Regex.IsMatch(t, "Back up your files to")) return ("Back up to this drive", "kit:files-backup");
            if (Regex.IsMatch(t, "activated")) return ("Activation settings", "ms-settings:activation");
            if (Regex.IsMatch(t, "hypervisor")) return ("Windows features", "optionalfeatures.exe");
            if (Regex.IsMatch(t, "Xbox Game Bar")) return ("Microsoft Store", "ms-windows-store://pdp/?ProductId=9NZKPSTSNW4P");
            if (Regex.IsMatch(t, "chipset driver")) return ("AMD drivers", "https://www.amd.com/en/support/download/drivers.html");
            if (Regex.IsMatch(t, "DNS server")) return ("Network settings", "ms-settings:network-status");
            if (Regex.IsMatch(t, "Wi-Fi")) return ("Wi-Fi settings", "ms-settings:network-wifi");
            if (Regex.IsMatch(t, "nothing is backed up|File History")) return ("File History", "control.exe /name Microsoft.FileHistory");
            if (Regex.IsMatch(t, @"Steam game\(s\) are on a hard drive")) return ("Steam storage", "steam://open/settings/");
            if (Regex.IsMatch(t, "Hz|refresh|monitor")) return ("Display settings", "ms-settings:display-advancedgraphics");
            if (Regex.IsMatch(t, "storage|full|free space")) return ("Storage settings", "ms-settings:storagesense");
            return null;
        }
        // ramTest: the RAM stick test runs - a to-do that changes the RAM speed (EXPO) waits for it (10/22 audit: Home said
        // "turn EXPO on" right above the test's "leave EXPO off")
        public static IEnumerable<object> TodoLines(IEnumerable<Line> lines, bool ramTest = false)
        {
            bool first = true;
            foreach (var l in lines)
            {
                if (l.Level != "warn") { yield return l; continue; }
                var text = Regex.Replace(l.Text, "^- ", "").Trim();
                var row = new DockPanel { Margin = Ui.Th(first ? "0,2,0,0" : "0,12,0,0") };
                if (!first) { var div = new Border { Height = 1, Background = B("Divider"), Margin = Ui.Th("0,0,0,12") }; DockPanel.SetDock(div, Dock.Top); row.Children.Add(div); }
                first = false;
                var dot = new Ellipse { Width = 10, Height = 10, Fill = B("Warn"), VerticalAlignment = VerticalAlignment.Top, Margin = Ui.Th("0,6,14,0") }; DockPanel.SetDock(dot, Dock.Left); row.Children.Add(dot);
                var body = new StackPanel();
                // long items: the first part as the line, the how-to behind "How to" (a wall of steps is hard to scan)
                string head = text, more = null;
                var hm = Regex.Match(text, @"^(.{30,160}?)(?: - |\. |: )(.+)$");
                if (text.Length > 140 && hm.Success) { head = hm.Groups[1].Value.TrimEnd('.') + "."; more = hm.Groups[2].Value; }
                body.Children.Add(Ui.Text(head, B("Text"), 14, null, "0"));
                if (ramTest && Regex.IsMatch(text, @"\bEXPO\b|\bXMP\b")) body.Children.Add(Ui.Text("Wait with this until the RAM stick test is done - the test needs EXPO off, so its starts and crashes compare.", B("Warn"), 13, null, "0,4,0,0"));
                TextBlock mt = null; if (more != null) { mt = Ui.Text(more, B("Sub"), 13, null, "0,6,0,0"); mt.Visibility = Visibility.Collapsed; body.Children.Add(mt); }
                var bp = new WrapPanel { Margin = Ui.Th("0,8,0,0") };
                if (mt != null) bp.Children.Add(Ui.Btn("E946", "How to", () => mt.Visibility = mt.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible, small: true));
                var fx = TodoFix(text);
                if (fx != null)
                {
                    var target = fx.Value.Target;
                    bp.Children.Add(Ui.Btn("E8A7", fx.Value.Label, () =>
                    {
                        if (target == "kit:gpu-rollback") Actions.GpuRollback();
                        else if (target.StartsWith("kit:uninstall:")) { Actions.Open("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -File \"{Kit.P("junk-apps.ps1")}\" -Remove \"{target.Substring(14)}\""); Shell.Say("Its own uninstaller opens - follow it; the item goes away once it is removed."); }
                        else if (target == "kit:files-backup") Actions.FilesBackup();
                        else { var em = Regex.Match(target, @"^(\S+\.exe)( (.+))?$"); if (em.Success) Actions.Open(em.Groups[1].Value, em.Groups[3].Value); else Actions.Open(target); }
                    }, small: true));
                }
                bp.Children.Add(Ui.Btn("E823", "Snooze a week", () => { Data.RunPs("todo.ps1", $"-Snooze {Data.Q(text)} -Days 7"); Shell.Say("Snoozed - it comes back in a week if it still needs you."); Shell.Refresh(true); }, small: true));
                bp.Children.Add(Ui.Btn("E711", "Dismiss", () => { Data.RunPs("todo.ps1", $"-Dismiss {Data.Q(text)}"); Shell.Say("Dismissed - it stays off the list for 90 days (Claude won't add the same item again)."); Shell.Refresh(true); }, small: true));
                body.Children.Add(bp); row.Children.Add(body);
                yield return row;
            }
        }
    }
}
