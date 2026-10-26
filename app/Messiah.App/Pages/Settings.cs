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

        public static List<UIElement> General(Snapshot s)
        {
            var o = new List<UIElement>();
            var ai = s.Ai;
            var aiRow = Ui.SwitchRow("AI assistant (Claude)", ai ? "On: Messiah sessions (Claude Code with admin rights) with your Claude account, and Claude's own maintenance checks. Off: its sessions close; Claude Code and your conversations stay."
                : "Sign in with your own Claude account (Claude Code comes with Claude's Pro and Max plans) and Claude looks after the PC with you. Everything else works without it.", ai,
                sw => { if (sw.IsChecked == true) { if (!Actions.AiOn()) sw.IsChecked = false; } else Actions.AiOff(); });
            var openRow = Ui.SwitchRow("Open Messiah when I log in", "This window opens once per start-up (not while a game is fullscreen). Off: Messiah starts quietly in the hidden tray (^ next to the clock) and works on its own.", Kit.Opt("openatlogin", "off") == "on",
                sw => { Kit.SetOpt("openatlogin", OnOff(sw.IsChecked == true)); Shell.Say("Saved - " + (sw.IsChecked == true ? "this window opens at login." : "Messiah starts in the hidden tray at login.")); });
            // (the tray's Alert(): off by default - the owner's rule 10/10, nothing pops up by itself)
            var noteRow = Ui.SwitchRow("Show alerts in the corner", "A small note in the corner of the screen when something needs you or an update finished (never over a game). Off (default): nothing pops up - it waits on Home and under Health > Alerts, and the tray icon's tooltip counts what needs you.", Kit.Opt("cornernotes", "off") == "on",
                sw => { Kit.SetOpt("cornernotes", OnOff(sw.IsChecked == true)); Shell.Say("Saved - " + (sw.IsChecked == true ? "alerts show in the corner." : "nothing pops up; alerts wait here.")); });
            // (restart-night.ps1: on by default, except on the PC the kit is made on)
            var nightRow = Ui.SwitchRow("Restart at night to finish updates", "When an update waits for a restart, the PC restarts between 3:30 and 5:30 AM - only if nobody has used it for an hour, no game is running and it is plugged in. A 5-minute warning first (the tray's Cancel restart stops it). Off: updates finish whenever you restart.",
                Kit.Opt("nightrestart", File.Exists(Kit.P("publish-kit.ps1")) ? "off" : "on") == "on",
                sw => { Kit.SetOpt("nightrestart", OnOff(sw.IsChecked == true)); Shell.Say("Saved - " + (sw.IsChecked == true ? "pending updates finish with a restart at night while the PC is unused." : "updates finish whenever you restart.")); });
            // (10/22 audit: grouped by what they are about - Claude, start-up and alerts, games, crashes and hardware - not one long list)
            o.Add(Ui.Card("AI assistant", "E99A", new object[] { aiRow }));
            o.Add(Ui.Card("Start-up, alerts and restarts", "E713", new object[] { openRow, noteRow, nightRow }));
            // the Status tab's details: settings in plain words, or by their registry names (for whoever knows them)
            o.Add(Ui.Card("Display", "E7F4", new object[] { Ui.SwitchRow("Show technical names", "In a Status row's details, the settings by their registry names (AllowTelemetry, HwSchMode...) instead of in plain words. Off (default): plain words.", Kit.Opt("technames", "off") == "on",
                sw => { Kit.SetOpt("technames", OnOff(sw.IsChecked == true)); Shell.Say("Saved."); }) }));
            // gaming options (gaming-check.ps1 / nvidia-settings.ps1 apply them at the next check)
            var games = new[] {
                ("defenderexclusions", "off", "Microsoft Defender skips my game folders", "Less stutter while games load and build their shaders. A small security trade-off: files in those folders are no longer scanned. Off (the default): Defender scans them like everything else."),
                ("nvidiasettings", "on", "NVIDIA driver settings for games", "Low-latency mode on and an unlimited shader cache (less stutter), set in the driver for every game, and put back if anything resets them. Off: no longer applied (the driver keeps the last values until changed in the NVIDIA Control Panel)."),
                ("gameboost", "on", "Background programs step back while I play", "While a game runs, browsers, the Claude and Codex sessions and Steam's web pages run at a lower priority and the game at a higher one - back as they were once you quit. Voice chat, music and audio are left alone. Off: Windows decides."),
                ("gamesettings", "on", "Keep my game settings", "Call of Duty: a game update or a new graphics driver can put your settings back to the game's \"recommended\" ones - your tuned ones go back in by themselves (what you change in the game yourself is kept). After a new driver it also reminds you to let the game compile its shaders at the main menu. Off: left as the game sets them."),
                ("autorollback", "on", "Undo a graphics driver that crashes or is slower", "A new graphics driver is on test for its first two weeks: if it causes freezes or blue screens, or your games run clearly slower on it than on the one before, it is swapped back to the one before by itself, and held back until a newer version comes. Off: you get a warning with a one-click button instead."),
                ("gametune", "on", "Tune my games by measuring", "Call of Duty's settings that only change speed (never how it looks) are tried both ways in your own matches - switched only while the game is closed - and the faster one is kept. Results: Games > Performance. Off: a test under way ends with your setting back."),
                ("cputemp", "on", "Measure the processor's temperature", "Windows can't read it by itself: a small signed driver (PawnIO, open source - the one LibreHardwareMonitor and FanControl use) and LibreHardwareMonitor's library read the processor's own sensor - while you play and at idle (Games > Performance: Heat and wear). Off: both are removed at the next check."),
                ("ramcheck", "on", "Test the memory at night", "Once the PC has been left alone for 30 minutes (no game), most of the free memory is filled with patterns and read back, again and again - a flipped bit means faulty memory. It stops the moment you touch the mouse or keyboard. Every night while blue screens keep coming, else once a month. Results: Health > Stability."),
                ("fancheck", "on", "Watch the fans", "The graphics card's fans stuck high while it is idle and cool go back to automatic (quiet when cool), and a stopped CPU fan or water-cooling pump is a warning. Fan curves stay the BIOS's own. Off: the fans aren't watched.") };
            // the crash and hardware-health ones get their own card
            var health = new[] { "autorollback", "cputemp", "ramcheck", "fancheck" };
            UIElement Row((string, string, string, string) g) => Ui.SwitchRow(g.Item3, g.Item4, Kit.Opt(g.Item1, g.Item2) == "on",
                sw => { Kit.SetOpt(g.Item1, OnOff(sw.IsChecked == true)); Shell.Say("Saved - applied at the next check (or click Run maintenance now)."); }, g.Item1);
            o.Add(Ui.Card("Games", "E7FC", games.Where(g => !health.Contains(g.Item1)).Select(g => (object)Row(g))));
            o.Add(Ui.Card("Crashes and hardware health", "E95E", games.Where(g => health.Contains(g.Item1)).Select(g => (object)Row(g))));
            // backup
            var bl = new List<object> { s.LastBackup != null ? new Line($"Last backup: {s.LastBackup.LastWriteTime:ddd MMM d, h:mm tt} in {s.LastBackup.DirectoryName}") : Dim("No backup yet - the first one is made at the next weekly maintenance."),
                Dim("Weekly: wallpaper, dark mode, colours, taskbar, mouse, Start pins, game settings and Messiah's memory. Reinstalling Windows with the install USB brings them back by itself; plug in the USB once in a while and a copy goes onto it too.") };
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
            return o;
        }

        // every change the kit makes, each one the owner's to keep or not (tweaks.ps1 reads "tweak.<id>=off", puts back what
        // it had changed, and keeps to the choice after updates) - in groups
        public static List<UIElement> Windows(Snapshot s)
        {
            var o = new List<UIElement> { Ui.Card("Preview", "E7B3", new object[] { Dim("See exactly what Messiah would change on this PC right now - each setting with its current and new value, what Windows refuses, and what is already in place. Nothing is changed.") }, new[] { Ui.Btn("E7B3", "Preview changes", Actions.PreviewTweaks) }) };
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
            o.Add(Ui.Card("Your setup", "E8F1", new object[] { new Line($"Messiah's switches and your choices of Windows changes - {mine.Count} chosen on this PC. Save them to a file and load them on another PC (or after reinstalling Windows), or start from a preset.", "info"),
                Dim("Recommended: Messiah's own defaults (your Windows choices stay). Everything for gaming: every game feature on - Defender skipping game folders, NVIDIA settings, Game Mode, keeping and tuning game settings, the driver test, temperatures and fans.") },
                new[] { Ui.Btn("E74E", "Save to a file...", Actions.ExportSetup), Ui.Btn("E8E5", "Load a setup...", Actions.ImportSetup), Ui.Btn("E7FC", "Everything for gaming", () => Actions.Preset("gaming")), Ui.Btn("E777", "Recommended", () => Actions.Preset("recommended")) }));
            var kl = new List<object> { new Line($"{(s.KitVersion != "" ? $"Version {s.KitVersion}, since {s.KitSince:MMM d}. " : "")}It updates itself (checks every 4 hours) and tests itself after each update.") };
            if (s.PrevVersion != "") kl.Add(Dim($"The version before ({s.PrevVersion}) is kept: Undo goes back to it."));
            if (s.Ai && Data.ClaudeVersion() != "") kl.Add(Dim($"Claude Code {Data.ClaudeVersion()} - updates itself; an idle hidden session moves onto a new version by itself."));
            o.Add(Ui.Card("Messiah updates", "E895", kl, new[] { Ui.Btn("E90F", "Repair Messiah", Actions.Repair), Ui.Btn("E7A7", "Undo the last update", Actions.Rollback) }));
            // the graphics driver, with the one-click way back to the one before (gpu-rollback.ps1, through the tray)
            if (s.Gpu != null)
            {
                var held = Kit.FirstLine(Kit.P("gpu-hold.txt"));
                var gl = new List<object> { new Line($"{s.Gpu.Name} - driver {s.Gpu.Version}{(s.Gpu.Date != null ? $" from {s.Gpu.Date:MMM d, yyyy}" : "")}"),
                    Dim("Updated by itself. If games crash, freeze or run worse since the last update, go back to the driver before it - a restore point is made first, and the newer one isn't installed again (a later version is).") };
                if (held != "") gl.Add(Dim($"You went back from {held} - versions up to it are skipped."));
                o.Add(Ui.Card("Graphics driver", "E7F4", gl, new[] { Ui.Btn("E7A7", "Go back to the previous driver", Actions.GpuRollback) }));
            }
            if (s.Bios != null)
                o.Add(Ui.Card("Motherboard and BIOS", "E950", new object[] { new Line($"{s.Bios.Maker} {s.Bios.Model} - BIOS {s.Bios.Version} from {s.Bios.Date}"), Dim("A newer BIOS fixes stability and security problems; the kit reminds you when this one is over a year old. Updating it: " + s.Bios.Steps) },
                    new[] { Ui.Btn("E774", "Open its BIOS page", () => Actions.Open(s.Bios.Url)) }));
            o.Add(Ui.Card("Install USB", "E88E", new object[] { Dim("Makes a USB stick that installs Windows 11 on a new PC (or reinstalls this one) and sets it up by itself - Windows from Microsoft, the newest kit, and optionally this PC's settings. The stick is erased; takes 20-40 minutes.") }, new[] { Ui.Btn("E88E", "Make an install USB", Actions.MakeUsb) }));
            o.Add(Ui.Card("About", "E946", new object[] { new Line("Messiah" + (s.KitVersion != "" ? " " + s.KitVersion : "")), Dim("Keeps this PC updated, tuned and checked by itself, and updates itself. Tips: Ctrl+Alt+M opens this window from anywhere; Ctrl+K searches everything in it.") },
                new[] { Ui.Btn("E8F1", "Take the tour", () => Shell.W.ShowTour(0)) }));
            // help from someone else: what they need, on the clipboard (no names, paths or e-mail addresses)
            o.Add(Ui.Card("Get help", "E897", new object[] { Dim("Something not right? Copy a short report - versions, hardware, anything that isn't green, what needs you and the last check - and paste it into a message to whoever helps you. Nothing personal is in it.") }, new[] { Ui.Btn("E8C8", "Copy a report for help", Actions.CopyReport) }));
            o.Add(Ui.Card("Uninstall", "E74D", new object[] { Dim("Removes Messiah - the tray icon, the automatic maintenance and this app. Your apps, files and games stay; it asks whether to put back the Windows settings it changed.") }, new[] { Ui.Btn("E74D", "Uninstall Messiah...", Actions.Uninstall) }));
            return o;
        }
    }
}
