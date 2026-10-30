using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;

namespace Messiah.Pages
{
    // Settings (dashboard.ps1's Build-Page 'Settings/...'): everything Messiah does is the owner's to switch on or off,
    // each change it makes in Windows, and the tools (updates, repairs, drivers, the BIOS, the install USB)
    static class Settings
    {
        static Line Dim(string t) => new Line(t, "dim");
        static string OnOff(bool b) => b ? "on" : "off";
        // Restart at night (restart-night.ps1): on by default, except on the PC the kit is made on - Checks' footer reads it too
        internal static bool NightRestart => Kit.Opt("nightrestart", File.Exists(Kit.P("publish-kit.ps1")) ? "off" : "on") == "on";

        // the Your setup card's first line - with nothing chosen it read '0 chosen on this PC' (10/27)
        public static string SetupLine(int chosen) =>
            $"Messiah's switches and your choices of Windows changes: {(chosen == 0 ? "none chosen yet, so this PC runs on Messiah's defaults" : $"{chosen} chosen on this PC")}. Save them to a file and load them on another PC (or after reinstalling Windows), or start from a preset.";

        // when the next settings backup is made: settings-backup.ps1 runs at every background check (periodic-maint.ps1, never
        // under a game) and skips itself while the newest is under 6 days old (10/28: with none yet it said 'at the next
        // weekly maintenance' - it's the next check; with one, nothing said when the next comes)
        public static string BackupWhen(DateTime? last)
        {
            if (last == null) return "No backup yet - the first one is made at the next check (or click Back up now).";
            var next = last.Value.AddDays(6);
            return next <= DateTime.Now ? "The next one is made at the next check." : $"The next one is made at the first check after {next:ddd MMM d}.";
        }

        // the backup card's other lines (10/28: it read 'Weekly:wallpaper, ... colours' and 'Last backup: Tue Oct 27, 4:11 AM
        // in C:\Users\<name>\Documents\PC Setup Kit Backup' - now 'Last backup yesterday 4:11 AM, in Documents\...')
        public const string BackupWhat = "Every week: your wallpaper, dark mode, colors, taskbar, mouse, Start pins, game settings and Messiah's memory. The install USB brings them back after a reinstall; plug it in now and then for a copy.";
        public static string BackupLast(DateTime at, string dir, string docs = null)
        {
            // (both full paths: a short-name home like C:\Users\RUNNER~1 comes back long from DirectoryInfo - 10/30, GitHub's runner)
            string Full(string p) { try { return p == null || p == "" ? p : new DirectoryInfo(p).FullName; } catch { return p; } }
            docs = (Full(docs ?? Kit.Docs) ?? "").TrimEnd('\\'); dir = Full(dir);
            if (docs != "" && dir != null && dir.StartsWith(docs + "\\", StringComparison.OrdinalIgnoreCase)) dir = "Documents" + dir.Substring(docs.Length);
            return $"Last backup {Kit.FormatWhen(at)}, in {dir}";
        }

        // the two presets - the note and the buttons both come from here, so they read in the same order (10/27: the note
        // explained Recommended first, the buttons put Everything for gaming first). One short line each, and the same words
        // as the button's tooltip (10/28: one dense run-on line; it named a 'Game Mode' the preset doesn't touch). Plain
        // sentences after the name's colon (10/28: a semicolon, and 'gaming: every game switch on: ...' - two colons in a row)
        public static readonly (string Name, string Id, string Glyph, string About)[] Presets = {
            ("Recommended", "recommended", "E777", "Messiah's defaults. Your own Windows choices stay"),
            ("Everything for gaming", "gaming", "E7FC", "Every game switch on. Defender skips game folders, NVIDIA settings are set, games come first, game settings are kept and tuned, plus the driver test, CPU temperature and fans") };
        public static string[] PresetLines => Presets.Select(p => $"{p.Name}: {p.About}.").ToArray();

        // the BIOS card's lines: its date like the driver's (Jun 23, 2026), and the steps without the page's address -
        // the button under them opens it (a long maker's address with %20s was cut off mid-way). One line per step (10/27):
        // as one paragraph they folded after step 3, so 'turn EXPO back on' was never seen without a click
        // the board's maker by the name on the box, not Windows' company name (10/28: 'ASUSTeK COMPUTER INC. ROG STRIX ...');
        // a maker not in the list keeps its name without ', Inc.' / 'Co., Ltd.'
        static readonly (string Has, string Name)[] Makers = { ("asustek", "ASUS"), ("micro-star", "MSI"), ("gigabyte", "Gigabyte"), ("asrock", "ASRock"),
            ("biostar", "Biostar"), ("nzxt", "NZXT"), ("evga", "EVGA"), ("dell", "Dell"), ("hewlett", "HP"), ("lenovo", "Lenovo"), ("supermicro", "Supermicro") };
        public static string BoardMaker(string maker)
        {
            var m = (maker ?? "").Trim();
            foreach (var k in Makers) if (m.IndexOf(k.Has, StringComparison.OrdinalIgnoreCase) >= 0) return k.Name;
            return System.Text.RegularExpressions.Regex.Replace(m, @"[,.]?\s+(Inc|Corp(oration)?|Co\.?,?\s*Ltd|Ltd|LLC|GmbH|International)\.?$", "", System.Text.RegularExpressions.RegexOptions.IgnoreCase).Trim();
        }

        // Tools' grey notes, in plain sentences (10/28 - a ' - ' mid-sentence reads like a cut-off; --test TOOLSDASH)
        public const string DriverNote = "Updated by itself. If games crash, freeze or run worse since the last update, go back to the driver before it. A restore point is made first, and the newer one isn't installed again (a later version is).";
        public const string HelpNote = "Something not right? Copy a short report (versions, hardware, anything not green, what needs you, the last check) and paste it into a message to whoever helps you. Nothing personal is in it.";
        public const string UninstallNote = "Removes Messiah: the tray icon, the automatic maintenance and this app. Your apps, files and games stay, and it asks whether to put back the Windows settings it changed.";
        public const string UsbNote = "Makes a USB stick that installs Windows 11 from Microsoft on a new PC (or this one) and sets it up by itself: the newest kit, your settings if you like. It erases the stick. Takes 20-40 minutes.";
        // (10/28: its 'Tips: Ctrl+Alt+M ...; Ctrl+K ...' repeated General's Keyboard shortcuts card, which lacked Ctrl+Alt+M - the keys live there now)
        public const string AboutNote = "Keeps this PC updated, tuned and checked by itself, and updates itself. Ctrl+/ lists the keyboard shortcuts.";
        public static string HeldNote(string held) => $"You went back from {held}, so versions up to it are skipped.";
        public static string ClaudeNote(string ver) => $"Claude Code {ver} updates itself. An idle hidden session moves onto a new version by itself.";

        // About's first line: which version this is and when it came (10/28 - a friend asked "which version do I have?");
        // a copy without kit-version.txt (the owner's PC publishes, it doesn't update) says when the app itself was built
        public static string AboutLine(string ver, DateTime? since, DateTime? built)
        {
            if (ver != "") return $"Messiah {ver}" + (since != null ? $", updated {Kit.FormatWhen(since.Value)}" : "");
            return "Messiah" + (built != null ? $", this copy built {Kit.FormatWhen(built.Value)}" : "");
        }

        // a card head's date never splits: "Oct 16, 2026" with no-break spaces, so a narrow window wraps before it, not before "2026" (10/28)
        public static string HeadDate(string date) => date.Replace(' ', ' ');

        public const string BiosFold = "How to update it";
        public static string[] BiosLines(Data.Bios b)
        {
            var date = DateTime.TryParseExact(b.Date, "yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out var d)
                ? d.ToString("MMM d, yyyy", System.Globalization.CultureInfo.InvariantCulture) : b.Date;
            var steps = (b.Steps ?? "").Replace($"Open {b.Url} and", "Open its BIOS page (the button below) and").Replace($" from {b.Date})", ")");
            return new[] { $"{BoardMaker(b.Maker)} {b.Model} - BIOS {b.Version}{(date != "" ? " from " + HeadDate(date) : "")}",
                "A newer BIOS fixes stability and security problems. Messiah reminds you when this one is over a year old.",
                "Updating it:" }.Concat(System.Text.RegularExpressions.Regex.Split(steps.Trim(), @"\s+(?=\d\.\s)").Where(t => t != "")).ToArray();
        }

        public static List<UIElement> General(Snapshot s)
        {
            var o = new List<UIElement>();
            var ai = s.Ai;
            var aiRow = Ui.SwitchRow("AI assistant (Claude)", ai ? "On: Messiah sessions (Claude Code with admin rights) with your Claude account, and Claude's own maintenance checks. Off: its sessions close; Claude Code and your conversations stay."
                : "Sign in with your own Claude account (Claude Code comes with Claude's Pro and Max plans) and Claude looks after the PC with you. Everything else works without it.", ai,
                sw => { if (sw.IsChecked == true) { if (!Actions.AiOn()) sw.IsChecked = false; } else Actions.AiOff(); }, null, "E8BD");
            var openRow = Ui.SwitchRow("Open Messiah when I log in", "This window opens once per start-up (not while a game is fullscreen). Off: Messiah starts quietly in the hidden tray (^ next to the clock) and works on its own.", Kit.Opt("openatlogin", "off") == "on",
                sw => { Kit.SetOpt("openatlogin", OnOff(sw.IsChecked == true)); Shell.Say("Saved - " + (sw.IsChecked == true ? "this window opens at login." : "Messiah starts in the hidden tray at login.")); }, null, "E7E8");
            // (the tray's Alert(): off by default - the owner's rule 10/10, nothing pops up by itself)
            var noteRow = Ui.SwitchRow("Show alerts in the corner", "A small note in the corner of the screen when something needs you or an update finished (never over a game). Off (default): nothing pops up - it waits on Home and under Health > Alerts, and the tray icon's tooltip counts what needs you.", Kit.Opt("cornernotes", "off") == "on",
                sw => { Kit.SetOpt("cornernotes", OnOff(sw.IsChecked == true)); Shell.Say("Saved - " + (sw.IsChecked == true ? "alerts show in the corner." : "nothing pops up; alerts wait here.")); }, null, "EA8F");
            // (restart-night.ps1: on by default, except on the PC the kit is made on)
            var nightRow = Ui.SwitchRow("Restart at night to finish updates", "When an update waits for a restart, the PC restarts between 3:30 and 5:30 AM. It waits until nobody has used it for an hour, no game is running and it is plugged in. A 5-minute warning first (the tray's Cancel restart stops it). Off: updates finish whenever you restart.",
                NightRestart,
                sw => { Kit.SetOpt("nightrestart", OnOff(sw.IsChecked == true)); Shell.Say("Saved - " + (sw.IsChecked == true ? "pending updates finish with a restart at night while the PC is unused." : "updates finish whenever you restart.")); }, null, "E708");
            // (10/22 audit: grouped by what they are about - Claude, start-up and alerts, games, crashes and hardware - not one long list)
            // (10/25: improve-loop.ps1 - the PC the kit is made on only; Claude improves the app round by round within the usage budget)
            var aiRows = new List<UIElement> { aiRow };
            if (ai && File.Exists(Kit.P("improve-loop.ps1")))
                aiRows.Add(Ui.SwitchRow("Keep improving Messiah", "Claude works through the improvement checklist one small round at a time - each one tested and installed here - while your Claude usage allows: up to 95% of a session (all of it just before it resets) and 85% of the week. Never while you play or use Claude yourself. Off: no rounds.", Kit.Opt("improve", "on") != "off",
                    sw => { Kit.SetOpt("improve", OnOff(sw.IsChecked == true)); Shell.Say("Saved - " + (sw.IsChecked == true ? "Claude keeps improving Messiah within your usage." : "no more improvement rounds.")); }, null, "E895"));
            o.Add(Ui.Group("AI assistant", "E99A", aiRows));
            o.Add(Ui.Group("Start-up, alerts and restarts", "E713", new UIElement[] { openRow, noteRow, nightRow }));
            // Optimizations > In place's details: settings in plain words, or by their registry names (for whoever knows them)
            // (10/28: said 'a Status row' - there is no Status page any more; the page's name is now a link)
            o.Add(Ui.Group("Display", "E7F4", new UIElement[] { Ui.SwitchRow("Show technical names", "A row's details on Optimizations > In place name each setting by its registry name (AllowTelemetry, HwSchMode...) instead of in plain words. Off (default): plain words.", Kit.Opt("technames", "off") == "on",
                sw => { Kit.SetOpt("technames", OnOff(sw.IsChecked == true)); Shell.Say("Saved."); }, null, "E943") }));
            // gaming options (gaming-check.ps1 / nvidia-settings.ps1 apply them at the next check)
            // (10/28: the temperature switch's one line was the driver's names and two dashes - what it shows first, the how under More;
            //  Keep my game settings' line was the why joined to the what by a dash - now what it does first)
            var games = new[] {
                ("defenderexclusions", "off", "Microsoft Defender skips my game folders", "Less stutter while games load and build their shaders. A small security trade-off: files in those folders are no longer scanned. Off (the default): Defender scans them like everything else."),
                ("nvidiasettings", "on", "NVIDIA driver settings for games", "Low-latency mode on and an unlimited shader cache (less stutter), set in the driver for every game, and put back if anything resets them. Off: no longer applied (the driver keeps the last values until changed in the NVIDIA Control Panel)."),
                ("gameboost", "on", "Background programs step back while I play", "While a game runs, browsers, the Claude and Codex sessions and Steam's web pages run at a lower priority and the game at a higher one. All back as they were once you quit. Voice chat, music and audio are left alone. Off: Windows decides."),
                ("gamesettings", "on", "Keep my game settings", "Puts your tuned Call of Duty settings back when a game update or a new graphics driver resets them to the game's \"recommended\" ones. What you change in the game yourself is kept. After a new driver it also reminds you to let the game compile its shaders at the main menu. Off: left as the game sets them."),
                ("autorollback", "on", "Undo a graphics driver that crashes or is slower", "A new graphics driver is on test for its first two weeks: if it causes freezes or blue screens, or your games run clearly slower on it than on the one before, it is swapped back to the one before by itself, and held back until a newer version comes. Off: you get a warning with a one-click button instead."),
                ("gametune", "on", "Tune my games by measuring", "Call of Duty's settings that only change speed (never how it looks) are tried both ways in your own matches (switched only while the game is closed), and the faster one is kept. Results: Games > Performance. Off: a test under way ends with your setting back."),
                ("cputemp", "on", "Measure the processor's temperature", "Shows how hot the processor runs while you play and at idle (Games > Performance: Heat and wear). Windows can't read it by itself, so a small signed, open-source driver (PawnIO, the one LibreHardwareMonitor and FanControl use) and LibreHardwareMonitor's library read the processor's own sensor. Off: both are removed at the next check."),
                ("ramcheck", "on", "Test the memory at night", "Checks the memory for faults while the PC sits unused (Results: Health > Stability). Once it has been left alone for 30 minutes (no game), most of the free memory is filled with patterns and read back, again and again: a bit that comes back flipped means faulty memory. It stops the moment you touch the mouse or keyboard. Every night while blue screens keep coming, else once a month."),
                ("fancheck", "on", "Watch the fans", "The graphics card's fans stuck high while it is idle and cool go back to automatic (quiet when cool), and a stopped CPU fan or water-cooling pump is a warning. Fan curves stay the BIOS's own. Off: the fans aren't watched.") };
            // each one's icon on its own card (10/26)
            var icons = new Dictionary<string, string> { ["defenderexclusions"] = "EA18", ["nvidiasettings"] = "E7F4", ["gameboost"] = "E945", ["gamesettings"] = "E74E",
                ["autorollback"] = "E7A7", ["gametune"] = "EC4A", ["cputemp"] = "E950", ["ramcheck"] = "E9D9", ["fancheck"] = "E9CA" };
            // the crash and hardware-health ones get their own group
            var health = new[] { "autorollback", "cputemp", "ramcheck", "fancheck" };
            UIElement Row((string, string, string, string) g) => Ui.SwitchRow(g.Item3, g.Item4, Kit.Opt(g.Item1, g.Item2) == "on",
                sw => { Kit.SetOpt(g.Item1, OnOff(sw.IsChecked == true)); Shell.Say("Saved - applied at the next check (or click Run maintenance now)."); }, g.Item1, icons[g.Item1]);
            o.Add(Ui.Group("Games", "E7FC", games.Where(g => !health.Contains(g.Item1)).Select(Row)));
            o.Add(Ui.Group("Crashes and hardware health", "E95E", games.Where(g => health.Contains(g.Item1)).Select(Row)));
            // backup
            var bl = new List<object> { s.LastBackup != null ? new Line(BackupLast(s.LastBackup.LastWriteTime, s.LastBackup.DirectoryName)) : Dim(BackupWhen(null)), Dim(BackupWhat) };
            if (s.LastBackup != null) bl.Insert(1, Dim(BackupWhen(s.LastBackup.LastWriteTime)));
            o.Add(Ui.Card("Settings backup", "E777", bl, new[] { Ui.Btn("E777", "Back up now", Actions.BackupNow), Ui.Btn("E896", "Restore from a backup...", Actions.RestoreFrom) }));
            // game saves (game-saves.ps1, Ludusavi): off until turned on
            if (File.Exists(Kit.P("game-saves.ps1")))
            {
                var gl = new List<object> { Ui.SwitchRow("Back up my game saves every day", "Every game's saves (Steam or not - Ludusavi knows 10,000+ games) go to Documents\\Game Saves (Messiah), zipped, the last 3 copies of each. Never while you play. With a backup drive set up, they go there too.", Kit.Opt("gamesaves", "off") == "on",
                    sw => { Kit.SetOpt("gamesaves", OnOff(sw.IsChecked == true)); Shell.Say(sw.IsChecked == true ? "On - the first backup runs at the next check (or click Back up now)." : "Off - the backups made so far stay."); }, "gamesaves") };
                var at = Kit.Date(Json.Get(s.GameSaves, "lastRun"));
                if (at != null) { var ign = Json.L(s.GameSaves, "ignored").Count(); gl.Add(Dim($"Last backup {Kit.FormatWhen(at.Value)}: {Json.S(s.GameSaves, "games")} games{(ign > 0 ? $" ({ign} cache file(s) left out - not saves)" : "")}")); }
                o.Add(Ui.Card("Game saves", "E7FC", gl, new[] { Ui.Btn("E777", "Back up now", Actions.GameSavesNow), Ui.Btn("E8B7", "Open the backups", Actions.GameSavesOpen), Ui.Btn("E896", "Restore saves...", Actions.GameSavesRestore) }));
            }
            // the keys in one place (10/26; Ctrl+/ opens this card from anywhere)
            o.Add(Ui.Card("Keyboard shortcuts", "E765", new object[] { Ui.Rows(Shortcuts(ai).Select(k => (k.Item1, k.Item2, "info"))) }, calm: true));
            return o;
        }
        // (MainWindow's WindowKeys / NavKey and the search's keys - change them together)
        public static List<(string, string)> Shortcuts(bool ai)
        {
            var l = new List<(string, string)> { ("Ctrl+K", "Search Messiah, or Ctrl+F outside the chat. Esc closes it"),
                ("Ctrl+Alt+M", "Opens Messiah from anywhere, even with the window closed"),
                ("Ctrl+1 to 5", "Home, Games, Health, Optimizations, Settings"),
                ("Ctrl+Tab", "The tab's next page (Ctrl+Shift+Tab: the one before)"),
                ("Ctrl+/", "This list") };
            if (ai) l.AddRange(new[] { ("Ctrl+T", "A new chat with Claude"), ("Ctrl+W", "Close the chat"),
                ("In the chat", "Ctrl+Tab the next chat, Ctrl+F find in the conversation, Ctrl+0 normal text size") });
            return l;
        }

        // every change the kit makes, each one the owner's to keep or not (tweaks.ps1 reads "tweak.<id>=off", puts back what
        // it had changed, and keeps to the choice after updates) - in groups
        public static List<UIElement> Windows(Snapshot s)
        {
            var o = new List<UIElement> { Ui.Card("Preview", "E7B3", new object[] { Dim("See exactly what Messiah would change on this PC right now: each setting with its current and new value, what Windows refuses, and what is already in place. Nothing is changed.") }, new[] { Ui.Btn("E7B3", "Preview changes", Actions.PreviewTweaks) }) };
            foreach (var (g, items) in TweakCatalog.Groups)
                o.Add(Ui.Card(g, g == "Speed and games" ? "E945" : g == "Privacy and clutter" ? "E72E" : "E895",
                    items.Select(i => (object)Ui.SwitchRow(i.Title, i.About, Kit.Opt("tweak." + i.Id, i.Default) != "off", sw => Actions.SetTweak(i.Id, sw.IsChecked == true), i.Id))));
            return o;
        }

        public static List<UIElement> Tools(Snapshot s)
        {
            var o = new List<UIElement>();
            // your setup in a file, and the two presets (10/22 - winutil's and Winhance's config files)
            var mine = Actions.CurrentSetup();
            o.Add(Ui.Card("Your setup", "E8F1", new object[] { new Line(SetupLine(mine.Count), "info") }.Concat(PresetLines.Select(Dim)).ToArray(),
                new[] { Ui.Btn("E74E", "Save to a file...", Actions.ExportSetup), Ui.Btn("E8E5", "Load a setup...", Actions.ImportSetup) }
                    .Concat(Presets.Select(p => { var b = Ui.Btn(p.Glyph, p.Name, () => Actions.Preset(p.Id)); b.ToolTip = $"{p.Name}: {p.About}."; return b; })).ToArray()));
            var kl = new List<object> { new Line($"{(s.KitVersion != "" ? $"Version {s.KitVersion}, since {s.KitSince:MMM d}. " : "")}It updates itself (checks every 4 hours) and tests itself after each update.") };
            if (s.PrevVersion != "") kl.Add(Dim($"The version before ({s.PrevVersion}) is kept: Undo goes back to it."));
            if (s.Ai && Data.ClaudeVersion() != "") kl.Add(Dim(ClaudeNote(Data.ClaudeVersion())));
            o.Add(Ui.Card("Messiah updates", "E895", kl, new[] { Ui.Btn("E90F", "Repair Messiah", Actions.Repair), Ui.Btn("E7A7", "Undo the last update", Actions.Rollback) }));
            // the graphics driver, with the one-click way back to the one before (gpu-rollback.ps1, through the tray)
            if (s.Gpu != null)
            {
                var held = Kit.FirstLine(Kit.P("gpu-hold.txt"));
                var gl = new List<object> { new Line($"{s.Gpu.Name} - driver {s.Gpu.Shown}{(s.Gpu.Date != null ? " from " + HeadDate(s.Gpu.Date.Value.ToString("MMM d, yyyy", System.Globalization.CultureInfo.InvariantCulture)) : "")}"),
                    Dim(DriverNote) };
                if (held != "") gl.Add(Dim(HeldNote(held)));
                o.Add(Ui.Card("Graphics driver", "E7F4", gl, new[] { Ui.Btn("E7A7", "Go back to the previous driver", Actions.GpuRollback) }));
            }
            if (s.Bios != null)
            {   // the steps behind a link: what it is first, how to update it when you want to (10/28: five steps always open)
                var bl = BiosLines(s.Bios);
                o.Add(Ui.Card("Motherboard and BIOS", "E950", new object[] { new Line(bl[0]), Ui.FoldLines(bl[1], BiosFold, "Hide the steps", bl.Skip(3)) },
                    new[] { Ui.Btn("E774", "Open its BIOS page", () => Actions.Open(s.Bios.Url)) }));
            }
            o.Add(Ui.Card("Install USB", "E88E", new object[] { Dim(UsbNote) }, new[] { Ui.Btn("E88E", "Make an install USB", Actions.MakeUsb) }));
            o.Add(Ui.Card("About", "E946", new object[] { new Line(AboutLine(s.KitVersion, s.KitSince, Kit.Stamp(System.Reflection.Assembly.GetEntryAssembly()?.Location ?? ""))), Dim(AboutNote) },
                new[] { Ui.Btn("E8F1", "Take the tour", () => Shell.W.ShowTour(0)) }));
            // help from someone else: what they need, on the clipboard (no names, paths or e-mail addresses)
            o.Add(Ui.Card("Get help", "E897", new object[] { Dim(HelpNote) }, new[] { Ui.Btn("E8C8", "Copy a report for help", Actions.CopyReport) }));
            o.Add(Ui.Card("Uninstall", "E74D", new object[] { Dim(UninstallNote) }, new[] { Ui.Btn("E74D", "Uninstall Messiah...", Actions.Uninstall) }));
            return o;
        }
    }
}
