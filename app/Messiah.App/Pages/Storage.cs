using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Messiah.Pages
{
    // Games > Storage (10/25, the owner: "move games between drives and clean leftover shader caches and duplicate
    // installs"): storage.ps1's storage.json - each drive's space, the games on it (Steam games can be moved to another
    // drive), what uninstalled games left behind (cleaned with one click; the monthly cleanup does it by itself), and the
    // same game installed twice. What's being done right now: storage-status.json.
    static class Storage
    {
        static SolidColorBrush B(string k) => Theme.B[k];
        static string Size(double? gb) => gb == null ? "-" : gb >= 10 ? $"{Math.Round(gb.Value):N0} GB" : gb >= 1 ? $"{gb.Value:0.0} GB" : $"{Math.Round(gb.Value * 1024):N0} MB";

        // a list in the file - or one item on its own (PowerShell writes a list of one as the item: 10/25, one drive read as 7)
        static List<object> Items(object j, string key) => Json.Get(j, key) is IDictionary<string, object> one ? new List<object> { one } : Json.L(j, key).ToList();

        public static List<UIElement> Build(Snapshot s)
        {
            var o = new List<UIElement>(); var j = s.Storage;
            // what's being done (a move, a cleanup) - or how the last one ended, for half an hour
            var st = s.StorageStatus; var at = Kit.Date(Json.Get(st, "at"));
            if (st != null && at != null && (DateTime.Now - at.Value).TotalMinutes < 30)
            {
                var state = Json.S(st, "state"); var pct = Json.N(st, "pct");
                if (state == "working" && (DateTime.Now - at.Value).TotalMinutes < 5)
                    o.Add(Ui.Wide(Ui.Card("Working on it", "E895", new object[] { new Line(Json.S(st, "text") + (pct != null && pct < 100 ? $" - {pct:0}%" : "") + ". It shows here when it's done.") })));
                else if (state == "failed") o.Add(Ui.Wide(Ui.Card("That didn't work", "E7BA", new object[] { new Line(Json.S(st, "text"), "warn") })));
                else if (state == "done") o.Add(Ui.Wide(Ui.Card("Done", "E73E", new object[] { new Line(Json.S(st, "text"), "ok") })));
            }
            if (j == null)
            {
                o.Add(Ui.Card("Storage", "EDA2", new object[] { new Line("Not looked at yet - the next background check lists your drives, the games on them and what uninstalled games left behind.", "dim") },
                    new[] { Ui.Btn("E72C", "Look now", () => Actions.Storage(new Dictionary<string, object> { ["cmd"] = "scan" }, "Looking at the drives - a few seconds.")) }));
                return o;
            }
            var drives = Items(j, "drives"); var games = Items(j, "games");

            // the drives: free space as a bar, SSD or not, the Windows drive
            var dl = new List<object>();
            foreach (var d in drives)
            {
                double size = Json.N(d, "sizeGB") ?? 0, free = Json.N(d, "freeGB") ?? 0; var used = size - free;
                var row = new StackPanel { Margin = Ui.Th("0,4,0,10") };
                var head = new DockPanel();
                var right = Ui.Text($"{Size(free)} free of {Size(size)}", free < size * 0.1 ? B("Warn") : B("Sub"), 13, null, "12,0,0,0"); DockPanel.SetDock(right, Dock.Right); head.Children.Add(right);
                head.Children.Add(Ui.Text($"{Json.S(d, "letter")}:{(Json.S(d, "label") != "" ? " " + Json.S(d, "label") : "")}  -  {(Json.B(d, "ssd") ? "SSD" : "hard drive")}{(Json.B(d, "system") ? ", Windows" : "")}", B("Text"), 14, null, "0"));
                row.Children.Add(head);
                var bar = new Grid { Height = 8, Margin = Ui.Th("0,6,0,0") };
                bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(0.001, used), GridUnitType.Star) }); bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(0.001, free), GridUnitType.Star) });
                var u = new Border { Background = free < size * 0.1 ? B("Warn") : B("Accent"), CornerRadius = new CornerRadius(4, 0, 0, 4) }; var f = new Border { Background = B("Seg"), CornerRadius = new CornerRadius(0, 4, 4, 0) }; Grid.SetColumn(f, 1);
                bar.Children.Add(u); bar.Children.Add(f); row.Children.Add(bar);
                var onIt = games.Where(g => Json.S(g, "drive") == Json.S(d, "letter")).ToList();
                if (onIt.Count > 0) row.Children.Add(Ui.Text($"Games: {Size(onIt.Sum(g => Json.N(g, "sizeGB") ?? 0))} in {onIt.Count}", B("Sub"), 12.5, null, "0,4,0,0"));
                dl.Add(Ui.Measured(row));
            }
            if (dl.Count > 0) o.Add(Ui.Wide(Ui.Card("Drives", "EDA2", dl)));

            // the games, biggest first; a Steam game can go to another drive that has room
            if (games.Count > 0)
            {
                var gl = new List<object>();
                foreach (var g in games)
                {
                    var gb = Json.N(g, "sizeGB") ?? 0;
                    var row = new DockPanel { Margin = Ui.Th("0,3,0,3") };
                    var btns = new StackPanel { Orientation = Orientation.Horizontal }; DockPanel.SetDock(btns, Dock.Right);
                    if (Json.B(g, "movable"))
                        foreach (var d in drives.Where(d => Json.S(d, "letter") != Json.S(g, "drive") && (Json.N(d, "freeGB") ?? 0) > gb + 5))
                        {
                            var to = Json.S(d, "letter"); var name = Json.S(g, "name"); var id = Json.S(g, "id");
                            var b = Ui.Btn("E8DE", $"Move to {to}:", () =>
                            {
                                if (MessageBox.Show($"Move {name} ({Size(gb)}) to {to}:?\n\nSteam closes for the move and opens again after. The game stays where it is unless the copy checks out. It takes a few minutes.", "Move a game", MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return;
                                Actions.Storage(new Dictionary<string, object> { ["cmd"] = "move", ["appid"] = id, ["to"] = to }, $"Moving {name} to {to}: - in the background.");
                            }, small: true);
                            b.Margin = Ui.Th("8,0,0,0"); btns.Children.Add(b);
                        }
                    row.Children.Add(btns);
                    var size = Ui.Text(Size(gb), B("Sub"), 13, null, "12,0,0,0"); size.VerticalAlignment = VerticalAlignment.Center; size.Width = 70; size.TextAlignment = TextAlignment.Right; DockPanel.SetDock(size, Dock.Right); row.Children.Add(size);
                    var nm = Ui.Text(Json.S(g, "name"), B("Text"), 14, null, "0"); nm.VerticalAlignment = VerticalAlignment.Center;
                    var where = Ui.Text($"{Json.S(g, "store")} - {Json.S(g, "drive")}:", B("Sub"), 12, null, "10,0,0,0"); where.VerticalAlignment = VerticalAlignment.Center;
                    var left = new WrapPanel { VerticalAlignment = VerticalAlignment.Center }; left.Children.Add(nm); left.Children.Add(where); row.Children.Add(left);
                    gl.Add(Ui.Measured(row));
                }
                if (drives.Count < 2) gl.Add(new Line("With a second drive, Steam games can be moved here with one click (Steam does the rest).", "dim"));
                o.Add(Ui.Card("Games", "E7FC", gl));
            }

            // what uninstalled games left behind: the safe ones in one click; a folder that may hold saves, one at a time
            var left0 = Items(j, "leftovers");
            var safe = left0.Where(x => Json.B(x, "safe")).ToList(); var look = left0.Where(x => !Json.B(x, "safe")).ToList();
            var ll = new List<object>(); var lb = new List<UIElement>();
            if (left0.Count == 0) ll.Add(new Line("Nothing - no uninstalled game left anything behind.", "ok"));
            if (safe.Count > 0)
            {
                ll.Add(new Line($"{safe.Count} leftover{Kit.S(safe.Count)} of uninstalled games - {Size(safe.Sum(x => Json.N(x, "sizeGB") ?? 0))}: shader caches, Workshop mods and unfinished downloads. Steam fetches them again if a game comes back."));
                lb.Add(Ui.Btn("E74D", "Clean them up", () => Actions.Storage(new Dictionary<string, object> { ["cmd"] = "clean" }, "Removing the leftovers - a few seconds."), accent: true));
            }
            foreach (var x in look)
            {
                var p = Json.S(x, "path");
                var row = new DockPanel { Margin = Ui.Th("0,6,0,2") };
                var bs = new StackPanel { Orientation = Orientation.Horizontal }; DockPanel.SetDock(bs, Dock.Right);
                var open = Ui.Btn("E838", "Show", () => Actions.Open("explorer.exe", $"\"{p}\""), small: true); open.Margin = Ui.Th("8,0,0,0"); bs.Children.Add(open);
                var bin = Ui.Btn("E74D", "To the Recycle Bin", () =>
                {
                    if (MessageBox.Show($"Move this folder to the Recycle Bin?\n\n{p}\n\nNo installed game uses it, but an old game may have kept saves or settings in it - have a look first if you're unsure. It can be restored from the Recycle Bin.", "Leftover folder", MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return;
                    Actions.Storage(new Dictionary<string, object> { ["cmd"] = "recycle", ["path"] = p }, "Moving it to the Recycle Bin.");
                }, small: true);
                bin.Margin = Ui.Th("8,0,0,0"); bs.Children.Add(bin); row.Children.Add(bs);
                var t = Ui.Text($"{Json.S(x, "name")} - {Size(Json.N(x, "sizeGB"))}", B("Text"), 14, null, "0"); t.VerticalAlignment = VerticalAlignment.Center; row.Children.Add(t);
                ll.Add(Ui.Measured(row));
            }
            o.Add(Ui.Card("Left behind by uninstalled games", "E74D", ll, lb));

            // the same game installed twice
            var dup = Items(j, "duplicates");
            if (dup.Count > 0)
            {
                var dd = new List<object>();
                foreach (var x in dup) { dd.Add(Ui.Text(Json.S(x, "name"), B("Text"), 14, FontWeights.SemiBold, "0,6,0,2")); foreach (var pl in Json.L(x, "places")) dd.Add(new Line("•  " + pl, "dim")); }
                dd.Add(new Line("Messiah never removes one of them by itself - uninstall the copy you don't play from its own launcher (or Windows' Installed apps).", "dim"));
                o.Add(Ui.Card("Installed twice", "E8C8", dd));
            }
            var when = Kit.Date(Json.Get(j, "date"));
            o.Add(new Border { Child = Ui.Text($"Looked {(when != null ? Kit.FormatWhen(when.Value) : "-")} - once a day. The monthly cleanup removes the safe leftovers by itself.", B("Sub"), 12, null, "4,4,0,0") });
            return o;
        }
    }
}
