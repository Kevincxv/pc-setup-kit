using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
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

        // the games in the order picked above them (kit option storagesort, 10/26): biggest first, A to Z, or by drive (C
        // first, then the others; biggest first on each)
        public static List<object> Order(IEnumerable<object> games, string by)
        {
            Func<object, double> gb = g => Json.N(g, "sizeGB") ?? 0;
            if (by == "name") return games.OrderBy(g => Json.S(g, "name"), StringComparer.CurrentCultureIgnoreCase).ToList();
            if (by == "drive") return games.OrderBy(g => Json.S(g, "drive") == "C" ? "" : Json.S(g, "drive")).ThenByDescending(gb).ToList();
            return games.OrderByDescending(gb).ToList();
        }
        // (--test: each order's names)
        // The footer: when the scan last ran, in the words the other pages use ("Checked" there, "Scanned" for a scan; was "Looked").
        public static string Scanned(DateTime? when) => (when != null ? $"Scanned {Kit.FormatWhen(when.Value)}" : "Not scanned yet") + " - once a day. The monthly cleanup removes the safe leftovers by itself.";

        public static string SortLine(Snapshot s)
        {
            var games = s.Storage == null ? new List<object>() : Items(s.Storage, "games");
            return string.Join(" | ", new[] { "size", "name", "drive" }.Select(by => by + ": " + string.Join(", ", Order(games, by).Select(g => Json.S(g, "name")))));
        }

        // a game's share of its drive (0 to 1; -1 when the drive isn't in the list) - the thin bar under each game (10/26), so
        // the big ones stand out without reading the numbers
        static double Share(object g, List<object> drives)
        {
            var d = drives.FirstOrDefault(x => Json.S(x, "letter") == Json.S(g, "drive")); var size = d == null ? 0 : Json.N(d, "sizeGB") ?? 0;
            return size <= 0 ? -1 : Math.Min(1, Math.Max(0, (Json.N(g, "sizeGB") ?? 0) / size));
        }
        // a big game (10%+) on a nearly full drive (under 10% free - the Drives card's warning) says why its bar matters:
        // "Moving it to D: frees 13% of C:" when a Move button is there, else "13% of a nearly full C:"; "" otherwise (10/27)
        public static string FreesNote(object g, List<object> drives)
        {
            var share = Share(g, drives); var d = drives.FirstOrDefault(x => Json.S(x, "letter") == Json.S(g, "drive"));
            if (share < 0.1 || d == null || (Json.N(d, "freeGB") ?? 0) >= (Json.N(d, "sizeGB") ?? 0) * 0.1) return "";
            var gb = Json.N(g, "sizeGB") ?? 0; var pct = Math.Round(share * 100); var from = Json.S(g, "drive");
            var to = !Json.B(g, "movable") ? null : drives.Where(x => Json.S(x, "letter") != from && (Json.N(x, "freeGB") ?? 0) > gb + 5).OrderByDescending(x => Json.N(x, "freeGB") ?? 0).FirstOrDefault();
            return to != null ? $"Moving it to {Json.S(to, "letter")}: frees {pct}% of {from}:" : $"{pct}% of a nearly full {from}:";
        }
        public static string FreesLine(Snapshot s)
        {
            var drives = Items(s.Storage, "drives");
            var o = Items(s.Storage, "games").Select(g => Json.S(g, "name") + ": " + (FreesNote(g, drives) is var n && n != "" ? n : "-")).ToList();
            // (made-up cases: a movable 250 GB game on the same full C: with room on D:, and on a C: with room to spare)
            Dictionary<string, object> D(string l, double size, double free) => new Dictionary<string, object> { ["letter"] = l, ["sizeGB"] = size, ["freeGB"] = free };
            var big = new Dictionary<string, object> { ["name"] = "Big", ["drive"] = "C", ["sizeGB"] = 250.0, ["movable"] = true };
            o.Add("CASES: full C: + D: " + FreesNote(big, new List<object> { D("C", 1000, 50), D("D", 2000, 1500) }) + " | roomy C: " + (FreesNote(big, new List<object> { D("C", 1000, 400), D("D", 2000, 1500) }) is var r && r != "" ? r : "-") + " | D: too small " + FreesNote(big, new List<object> { D("C", 1000, 50), D("D", 500, 200) }));
            return string.Join(" | ", o);
        }
        public static string ShareLine(Snapshot s)
        {
            if (s.Storage == null) return "";
            var drives = Items(s.Storage, "drives");
            return string.Join(", ", Order(Items(s.Storage, "games"), "size").Select(g => { var x = Share(g, drives); return Json.S(g, "name") + " " + (x < 0 ? "-" : Math.Round(x * 100) + "%"); }));
        }

        // "Open folder" - the same button on a game, a leftover and each copy of a game installed twice (10/26); a folder
        // that's gone since the last look says so instead of explorer opening Documents
        static Button FolderBtn(string path)
        {
            var b = Ui.Btn("E838", "Open folder", () =>
            {
                if (Directory.Exists(path)) Actions.Open("explorer.exe", $"\"{path}\"");
                else Shell.Say($"That folder isn't there any more ({path}) - the next look at the drives updates the list.");
            }, small: true);
            b.ToolTip = "Open folder - " + path; b.Margin = Ui.Th("8,0,0,0");
            return b;
        }
        // a narrow window: a row's buttons go under its name - beside it they squeezed it into a thin column at 480 (games,
        // and the leftovers too since 10/26)
        static void UnderWhenNarrow(DockPanel row, StackPanel btns, FrameworkElement docked = null)
        {
            docked = docked ?? btns; btns.VerticalAlignment = VerticalAlignment.Center;
            row.SizeChanged += (x, e) =>
            {
                var narrow = row.ActualWidth < 520; if ((DockPanel.GetDock(docked) == Dock.Bottom) == narrow) return;
                DockPanel.SetDock(docked, narrow ? Dock.Bottom : Dock.Right);
                btns.HorizontalAlignment = narrow ? HorizontalAlignment.Left : docked != btns ? HorizontalAlignment.Right : HorizontalAlignment.Stretch;
                btns.Margin = Ui.Th(narrow ? "-8,6,0,2" : "0");
            };
        }
        // a row's buttons in a column as wide as the widest row's (SharedSizeGroup - the window is the scope), so the sizes
        // left of it line up whether a row has a Move button or not (10/27)
        static Grid BtnColumn(StackPanel btns, string group)
        {
            var g = new Grid { Tag = "btncol:" + group }; g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto, SharedSizeGroup = group });
            btns.HorizontalAlignment = HorizontalAlignment.Right; g.Children.Add(btns); DockPanel.SetDock(g, Dock.Right); return g;
        }
        // a leftover folder's name without storage.ps1's ' - no installed game uses this folder' (the row says that under it)
        public static string LeftName(string name)
        {
            var i = name.IndexOf(" - no installed game uses this folder", StringComparison.Ordinal);
            return i > 0 ? name.Substring(0, i) : name;
        }
        // a drive's games line (10/28): both copies of a game installed twice are games (storage.ps1), so 'in 3 games' would
        // count NBA 2K23 twice - 'Games: 495 GB in 2 games (NBA 2K23 twice)'; the size counts every copy, it's on the drive
        public static string GamesLine(List<object> onIt, List<object> dups)
        {
            var paths = new HashSet<string>(onIt.Select(g => Json.S(g, "path").TrimEnd('\\')), StringComparer.OrdinalIgnoreCase);
            var twice = new List<string>(); var extra = 0;
            foreach (var x in dups ?? new List<object>())
            {
                var n = Json.L(x, "places").Select(v => PlacePath(v?.ToString()).TrimEnd('\\')).Count(p => p != "" && paths.Contains(p));
                if (n >= 2) { extra += n - 1; twice.Add(Json.S(x, "name") + (n == 2 ? " twice" : $" {n} times")); }
            }
            var count = onIt.Count - extra;
            return $"Games: {Size(onIt.Sum(g => Json.N(g, "sizeGB") ?? 0))} in {count} game{(count == 1 ? "" : "s")}" + (twice.Count > 0 ? $" ({string.Join(", ", twice)})" : "");
        }
        // an "Installed twice" place, "Steam: C:\...\NBA 2K23 (100 GB)" (storage.ps1) -> its folder
        public static string PlacePath(string place)
        {
            var m = System.Text.RegularExpressions.Regex.Match(place ?? "", @"^[^:]+: (.+?)(?: \([\d.,]+ GB\))?$");
            return m.Success ? m.Groups[1].Value : "";
        }

        // which copy of a game installed twice its launcher starts (10/26) - so the owner knows which one is the spare: a
        // Steam / Epic copy is the one in that launcher's library; a folder copy is started when a Steam shortcut points into
        // it (or into the folder a junction points to - C:\Games\NBA 2K\NBA 2K17 -> .preserve); otherwise nothing starts it
        public static string Starts(string place, IEnumerable<string> shortcutExes, string linkTo = null)
        {
            var store = (place ?? "").Split(':')[0]; var path = PlacePath(place);
            if (store == "Steam") return "Steam's own copy - in its library";
            if (store == "Epic") return "Epic Games' own copy - in its library";
            bool Inside(string exe, string dir) => !string.IsNullOrEmpty(dir) && exe.StartsWith(dir.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase);
            if (path != "" && (shortcutExes ?? new string[0]).Any(e => Inside(e, path) || Inside(e, linkTo))) return "Your Steam shortcut starts this one";
            return store == "Other" ? "Its own installer put it here - in Windows' Installed apps" : "No launcher or shortcut starts this one";
        }
        // the programs of the Steam shortcuts ("Add a non-Steam game"): userdata\<id>\config\shortcuts.vdf keeps each one's exe as
        // \x01exe\0"C:\...\game.exe"\0 - a string's type byte, its key, its value (PCKIT_STEAM stands in for Steam's folder in the tests)
        public static List<string> SteamShortcuts()
        {
            var o = new List<string>();
            try
            {
                var steam = Environment.GetEnvironmentVariable("PCKIT_STEAM");
                if (string.IsNullOrEmpty(steam)) steam = (Microsoft.Win32.Registry.GetValue(@"HKEY_CURRENT_USER\Software\Valve\Steam", "SteamPath", "") ?? "").ToString().Replace('/', '\\');
                if (steam == "" || !Directory.Exists(Path.Combine(steam, "userdata"))) return o;
                foreach (var u in Directory.GetDirectories(Path.Combine(steam, "userdata")))
                {
                    var f = Path.Combine(u, "config", "shortcuts.vdf"); if (!File.Exists(f)) continue;
                    foreach (System.Text.RegularExpressions.Match m in System.Text.RegularExpressions.Regex.Matches(File.ReadAllText(f), "(?i)\u0001exe\0([^\0]*)\0"))
                        o.Add(m.Groups[1].Value.Trim().Trim('"'));
                }
            }
            catch { }
            return o;
        }
        // what a game's row says it came from (10/26): a folder game (C:\Games\...) that a Steam shortcut starts says
        // "Steam shortcut" - the same test as Starts, so the row and Installed twice agree
        public static string StoreOf(object g, IEnumerable<string> shortcutExes)
        {
            var store = Json.S(g, "store"); var path = Json.S(g, "path");
            if (store == "Steam" || store == "Epic" || path == "") return store;
            return Starts(store + ": " + path + " (0 GB)", shortcutExes, Json.S(g, "linkTo")).StartsWith("Your Steam shortcut") ? "Steam shortcut" : store;
        }
        // why a game row has no Move button while another drive is there (10/28) - the row's tooltip; "" when it has one
        // or there's only one drive (the card says so already). store = StoreOf's ("Steam shortcut" for a shortcut's folder)
        // A game row's name with its store and drive right after it, on one line: a long name ('Tom Clancy's Rainbow Six
        // Siege - Operation Deadly Omen Edition') trims, its whole name on hover, instead of pushing 'Epic - D:' onto a line
        // of its own. (A left-aligned grid sizes to its content, so the star column is the name's width until it runs out.)
        public static Grid NameTag(string name, string tag)
        {
            var g = new Grid { HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center, Margin = Ui.Th("0,0,10,0") };
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }); g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var nm = Ui.Text(name, B("Text"), 14, null, "0,0,10,0"); nm.VerticalAlignment = VerticalAlignment.Center; nm.TextWrapping = TextWrapping.NoWrap; nm.TextTrimming = TextTrimming.CharacterEllipsis; nm.ToolTip = name;
            var where = Ui.Text(tag, B("Sub"), 12, null, "0"); where.TextWrapping = TextWrapping.NoWrap; where.VerticalAlignment = VerticalAlignment.Center; Grid.SetColumn(where, 1);            g.Children.Add(nm); g.Children.Add(where);
            return g;
        }

        public static string WhyNoMove(object g, IList<object> drives, string store)
        {
            if (drives == null || drives.Count < 2) return "";
            var gb = Json.N(g, "sizeGB") ?? 0;
            if (Json.B(g, "movable"))
                return drives.Any(d => Json.S(d, "letter") != Json.S(g, "drive") && (Json.N(d, "freeGB") ?? 0) > gb + 5) ? "" : $"No other drive has room for it - it needs {Size(gb + 5)} free.";
            if (store == "Epic") return "Epic moves its own games: in the Epic Games launcher, Library > the game's ... > Manage > Move.";
            if (store == "Steam shortcut") return "Not a Steam game, so Steam can't move it. Moving it by hand means pointing its Steam shortcut at the new folder after.";
            if (store == "Other") return "It came with its own installer - to move it, uninstall it and install it again on the other drive.";
            return "Only Steam's own games move with one click here.";
        }
        public static string StoresLine(Snapshot s)
        {
            if (s.Storage == null) return "";
            var sc = SteamShortcuts(); return string.Join(" | ", Items(s.Storage, "games").Select(g => Json.S(g, "name") + ": " + StoreOf(g, sc)));
        }
        public static string StartsLine(Snapshot s)
        {
            if (s.Storage == null) return "";
            var sc = SteamShortcuts(); var games = Items(s.Storage, "games");
            return string.Join(" | ", Items(s.Storage, "duplicates").Select(x => Json.S(x, "name") + ": " + string.Join(" / ", Json.L(x, "places").Select(v => Starts(v?.ToString(), sc, LinkOf(games, v?.ToString()))))));
        }
        // a folder copy that's a junction: where it points (storage.ps1's linkTo on the game with that path)
        static string LinkOf(List<object> games, string place)
        {
            var p = PlacePath(place); return Json.S(games.FirstOrDefault(g => string.Equals(Json.S(g, "path"), p, StringComparison.OrdinalIgnoreCase)), "linkTo");
        }

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
                // named like File Explorer's This PC - 'Games (D:)', an unnamed drive 'Local Disk (C:)'
                var name = Json.S(d, "label").Trim(); if (name == "") name = "Local Disk";
                head.Children.Add(Ui.Text($"{name} ({Json.S(d, "letter")}:)  -  {(Json.B(d, "ssd") ? "SSD" : "hard drive")}{(Json.B(d, "system") ? ", Windows" : "")}", B("Text"), 14, null, "0"));
                row.Children.Add(head);
                var bar = new Grid { Height = 8, Margin = Ui.Th("0,6,0,0") };
                bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(0.001, used), GridUnitType.Star) }); bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(0.001, free), GridUnitType.Star) });
                var u = new Border { Background = free < size * 0.1 ? B("Warn") : B("Accent"), CornerRadius = new CornerRadius(4, 0, 0, 4) }; var f = new Border { Background = B("Seg"), CornerRadius = new CornerRadius(0, 4, 4, 0) }; Grid.SetColumn(f, 1);
                bar.Children.Add(u); bar.Children.Add(f); row.Children.Add(bar);
                var onIt = games.Where(g => Json.S(g, "drive") == Json.S(d, "letter")).ToList();
                if (onIt.Count > 0) row.Children.Add(Ui.Text(GamesLine(onIt, Items(j, "duplicates")), B("Sub"), 12.5, null, "0,4,0,0"));
                dl.Add(Ui.Measured(row));
            }
            if (dl.Count > 0) o.Add(Ui.Wide(Ui.Card("Drives", "EDA2", dl)));

            // the games, in the order picked (biggest first, A to Z, by drive); each opens its folder, a Steam game can go to
            // another drive that has room
            if (games.Count > 0)
            {
                var gl = new List<object>();
                var multi = games.Select(g => Json.S(g, "drive")).Distinct().Count() > 1;
                var by = Kit.Opt("storagesort", "size"); if (by != "name" && !(by == "drive" && multi)) by = "size";
                var list = new StackPanel(); var rowOf = new Dictionary<object, UIElement>(); var sc = SteamShortcuts();
                var seg = new Border { Background = B("Seg"), CornerRadius = new CornerRadius(8), Padding = new Thickness(3), HorizontalAlignment = HorizontalAlignment.Left, Margin = Ui.Th("0,0,0,8") };
                var pills = new StackPanel { Orientation = Orientation.Horizontal };
                foreach (var (id, label) in new[] { ("size", "Biggest first"), ("name", "A to Z"), ("drive", "By drive") })
                {
                    if (id == "drive" && !multi) continue;   // (all on one drive: nothing to sort by)
                    var rb = new RadioButton { GroupName = "storagesort", Content = label, IsChecked = by == id, Style = (Style)Application.Current.FindResource("Pill") };
                    AutomationProperties.SetName(rb, "Sort the games: " + label);
                    rb.Checked += (x, e) =>
                    {
                        list.Children.Clear(); foreach (var g in Order(games, id)) list.Children.Add(rowOf[g]);   // (in place - no redraw)
                        Kit.SetOpt("storagesort", id == "size" ? "" : id);
                    };
                    pills.Children.Add(rb);
                }
                seg.Child = pills; if (games.Count > 1) gl.Add(seg);
                foreach (var g in games)
                {
                    var gb = Json.N(g, "sizeGB") ?? 0; var path = Json.S(g, "path");
                    var row = new DockPanel { Margin = Ui.Th("0,3,0,3") };
                    var btns = new StackPanel { Orientation = Orientation.Horizontal }; var bcol = BtnColumn(btns, "storagegames");
                    Button of = null;   // (rightmost - so the Open folder buttons line up whether a row can move or not)
                    if (path != "") of = FolderBtn(path);
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
                    if (of != null) btns.Children.Add(of);
                    row.Children.Add(bcol);
                    var size = Ui.Text(Size(gb), B("Sub"), 13, null, "12,0,0,0"); size.VerticalAlignment = VerticalAlignment.Center; size.Width = 70; size.TextAlignment = TextAlignment.Right; DockPanel.SetDock(size, Dock.Right); row.Children.Add(size);
                    var left = new WrapPanel { VerticalAlignment = VerticalAlignment.Center }; left.Children.Add(NameTag(Json.S(g, "name"), $"{StoreOf(g, sc)} - {Json.S(g, "drive")}:"));   // (the gaps are right margins, so a part that wraps starts flush under the name)
                    var why = WhyNoMove(g, drives, StoreOf(g, sc));
                    if (why != "") { left.ToolTip = why; AutomationProperties.SetHelpText(left, why); }   // (quiet: no Move button - why)
                    var frees = FreesNote(g, drives);
                    if (frees != "") { var fn = Ui.Text(frees, B("Warn"), 12, null, "0"); fn.VerticalAlignment = VerticalAlignment.Center; left.Children.Add(fn); }
                    var share = Share(g, drives);
                    if (share < 0) row.Children.Add(left);
                    else
                    {   // (the thin bar: its share of the drive, in the Drives card's colors)
                        var col = new StackPanel { VerticalAlignment = VerticalAlignment.Center }; col.Children.Add(left);
                        var bar = new Grid { Height = 4, Margin = Ui.Th("0,4,0,2") }; AutomationProperties.SetName(bar, $"{Math.Round(share * 100)}% of {Json.S(g, "drive")}:");
                        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(0.001, share), GridUnitType.Star) }); bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(0.001, 1 - share), GridUnitType.Star) });
                        var u = new Border { Background = B("Accent"), CornerRadius = new CornerRadius(2, 0, 0, 2) }; var f = new Border { Background = B("Seg"), CornerRadius = new CornerRadius(0, 2, 2, 0) }; Grid.SetColumn(f, 1);
                        bar.Children.Add(u); bar.Children.Add(f);
                        var track = new Grid(); track.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MaxWidth = 240 }); track.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0.0001, GridUnitType.Star) });
                        track.Children.Add(bar); col.Children.Add(track); row.Children.Add(col);   // (the same length on every row - the left side's width changes with its buttons)
                    }
                    UnderWhenNarrow(row, btns, bcol);
                    var m = Ui.Measured(row); rowOf[g] = m;
                }
                foreach (var g in Order(games, by)) list.Children.Add(rowOf[g]);
                gl.Add(list);
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
                var bs = new StackPanel { Orientation = Orientation.Horizontal }; var bcol = BtnColumn(bs, "storagegames");   // (the Games list's column, so the sizes line up)
                bs.Children.Add(FolderBtn(p));
                var bin = Ui.Btn("E74D", "To the Recycle Bin", () =>
                {
                    if (MessageBox.Show($"Move this folder to the Recycle Bin?\n\n{p}\n\nNo installed game uses it, but an old game may have kept saves or settings in it - have a look first if you're unsure. It can be restored from the Recycle Bin.", "Leftover folder", MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return;
                    Actions.Storage(new Dictionary<string, object> { ["cmd"] = "recycle", ["path"] = p }, "Moving it to the Recycle Bin.");
                }, small: true);
                bin.Margin = Ui.Th("8,0,0,0"); bs.Children.Add(bin); row.Children.Add(bcol);
                // the size right-aligned like the Games list's, the reason as a dim line under the name (was 'Name - reason - 4.2 GB')
                var size = Ui.Text(Size(Json.N(x, "sizeGB")), B("Sub"), 13, null, "12,0,0,0"); size.VerticalAlignment = VerticalAlignment.Center; size.Width = 70; size.TextAlignment = TextAlignment.Right; DockPanel.SetDock(size, Dock.Right); row.Children.Add(size);
                var col = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
                var t = Ui.Text(LeftName(Json.S(x, "name")), B("Text"), 14, null, "0"); t.TextWrapping = TextWrapping.Wrap; col.Children.Add(t);
                var sub = Ui.Text("No installed game uses it. It may hold old saves.", B("Sub"), 12.5, null, "0,2,0,0"); sub.TextWrapping = TextWrapping.Wrap; col.Children.Add(sub);
                row.Children.Add(col);
                UnderWhenNarrow(row, bs, bcol);
                ll.Add(Ui.Measured(row));
            }
            o.Add(Ui.Card("Left behind by uninstalled games", "E74D", ll, lb));

            // the same game installed twice
            var dup = Items(j, "duplicates");
            if (dup.Count > 0)
            {
                var dd = new List<object>(); var sc = SteamShortcuts(); var allGames = Items(j, "games");
                foreach (var x in dup)
                {
                    dd.Add(Ui.Text(Json.S(x, "name"), B("Text"), 14, FontWeights.SemiBold, "0,6,0,2"));
                    // each copy: what starts it (the launcher's own, a Steam shortcut, nothing), then where - and opens its folder
                    foreach (var pl in Json.L(x, "places").Select(v => v?.ToString() ?? ""))
                    {
                        var pp = PlacePath(pl); var starts = Starts(pl, sc, LinkOf(allGames, pl));
                        if (pp == "") { dd.Add(new Line("•  " + pl, "dim")); continue; }
                        var row = new DockPanel { Margin = Ui.Th("0,2,0,2") };
                        var fb = FolderBtn(pp); fb.VerticalAlignment = VerticalAlignment.Center; DockPanel.SetDock(fb, Dock.Right); row.Children.Add(fb);
                        var tx = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
                        var t1 = Ui.Text("•  " + starts, B("Text"), 13, null, "0"); t1.TextWrapping = TextWrapping.Wrap; tx.Children.Add(t1);
                        var t2 = Ui.Text(pl, B("Sub"), 12, null, "14,0,0,0"); t2.TextWrapping = TextWrapping.Wrap; tx.Children.Add(t2);
                        row.Children.Add(tx);
                        dd.Add(Ui.Measured(row));
                    }
                }
                dd.Add(new Line("Messiah never removes one of them by itself - the copy nothing starts is usually the spare. Uninstall the one you don't play from its own launcher (or Windows' Installed apps).", "dim"));
                o.Add(Ui.Card("Installed twice", "E8C8", dd));
            }
            var when = Kit.Date(Json.Get(j, "date"));
            o.Add(new Border { Child = Ui.Text(Scanned(when), B("Sub"), 12, null, "4,4,0,0") });
            return o;
        }
    }
}
