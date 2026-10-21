using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Windows;

namespace Messiah
{
    // What the buttons do (dashboard.ps1's $act). What needs admin rights goes through the tray, which runs elevated and
    // listens for this registered message (its window handle is in tray-hwnd.txt); without the tray, a prompt instead.
    static class Actions
    {
        static readonly uint TrayMsg = Native.RegisterWindowMessage("PCSetupKitAppCommand");
        public enum Cmd { NewSession = 1, ShowSessions = 2, HideSessions = 3, RunMaint = 4, Optimize = 5, WatchLive = 6, ApplyTweaks = 7, Repair = 8, Rollback = 9, AiOn = 10, AiOff = 11, GpuRollback = 12, ChatHost = 13 }
        public static bool SendTray(Cmd n)
        {
            if (!long.TryParse(Kit.FirstLine(Kit.P("tray-hwnd.txt")), out var hl)) return false;
            var h = new IntPtr(hl);
            return h != IntPtr.Zero && Native.IsWindow(h) && Native.PostMessage(h, TrayMsg, new IntPtr((int)n), IntPtr.Zero);
        }
        static string PsArgs(string file, bool keep = false, string extra = "") => $"-NoProfile -ExecutionPolicy Bypass {(keep ? "-NoExit " : "")}-File \"{Kit.P(file)}\" {extra}".Trim();
        static void Ps(string file, bool keep = false, string extra = "", bool admin = false, bool hidden = false) =>
            Process.Start(new ProcessStartInfo("powershell.exe", PsArgs(file, keep, extra)) { UseShellExecute = true, Verb = admin ? "runas" : "", WindowStyle = hidden ? ProcessWindowStyle.Hidden : ProcessWindowStyle.Normal });
        public static void Open(string target, string args = null) { try { Process.Start(new ProcessStartInfo(target, args ?? "") { UseShellExecute = true }); } catch (Exception e) { Shell.Say("Couldn't open it: " + e.Message); } }
        static void StartTask(string name) { try { Process.Start(new ProcessStartInfo("schtasks.exe", $"/Run /TN \"{name}\"") { UseShellExecute = false, CreateNoWindow = true }); } catch { } }

        public static void RunMaint() { if (!SendTray(Cmd.RunMaint)) StartTask("Claude Background Maintenance"); Shell.Say("Maintenance started in the background - the result shows here when it finishes."); }
        public static void Optimize() { if (!SendTray(Cmd.Optimize)) Ps("optimize.ps1", keep: true, admin: true); }
        public static void GpuRollback() { if (SendTray(Cmd.GpuRollback)) Shell.Say("A window opens with the driver versions - it asks before changing anything."); else Ps("gpu-rollback.ps1", keep: true, admin: true); }
        public static void CheckNow() { if (SendTray(Cmd.ApplyTweaks)) { Shell.CheckingSince = DateTime.Now.AddSeconds(-2); Shell.Refresh(true); } else { Shell.Say("The tray isn't running - it starts at the next login."); StartTask("Messiah Tray"); } }
        public static void FilesBackup() { Ps("files-backup.ps1", extra: "-Enable", hidden: true); Data.RunPs("todo.ps1", "-Id backup -Done"); Shell.Say("Backing up your files to that drive now - from now on it happens by itself whenever the drive is connected."); Shell.Refresh(true); }
        public static void DiagOff(string id)
        {
            var what = id == "verifier" ? "Driver Verifier" : id == "debug" ? "kernel debugging" : "test signing";
            if (MessageBox.Show($"Turn off {what}?\n\nIt stops at the next restart (Messiah never restarts the PC). Do this once you're done hunting the crash - if blue screens come back later, it can be turned on again.", "Crash-hunting mode", MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return;
            var (exe, a) = id == "verifier" ? ("verifier.exe", "/reset") : id == "debug" ? ("bcdedit.exe", "/debug off") : ("bcdedit.exe", "/set testsigning off");
            try { var p = Process.Start(new ProcessStartInfo(exe, a) { UseShellExecute = true, Verb = "runas", WindowStyle = ProcessWindowStyle.Hidden }); p.WaitForExit(); Shell.Say($"{char.ToUpper(what[0]) + what.Substring(1)} is off from the next restart."); Shell.Refresh(true); }
            catch (Exception e) { Shell.Say("Not turned off - " + e.Message); }
        }
        // the AI assistant switch (ai-toggle.ps1, through the tray: it needs admin rights)
        public static bool AiOn()
        {
            if (MessageBox.Show("Switch on the AI assistant?\n\nMessiah installs Claude Code (from claude.ai) and opens it so you can sign in with your own Claude account - Claude Code comes with Claude's Pro and Max plans. Then Claude can look after this PC with you (the /maintain and /pc-optimize checks).\n\nEverything else in Messiah works the same without it.", "AI assistant", MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return false;
            if (!SendTray(Cmd.AiOn)) Ps("ai-toggle.ps1", extra: "-On", admin: true);
            Shell.Say("Switching on the AI assistant - Claude Code installs, then a window opens for signing in (a minute or two)."); return true;
        }
        public static void AiOff() { if (!SendTray(Cmd.AiOff)) Ps("ai-toggle.ps1", extra: "-Off", admin: true, hidden: true); Shell.Say("AI assistant off - its sessions close. Claude Code and your conversations stay for when you switch it on again."); }
        // settings backups (settings-backup.ps1)
        public static void BackupNow()
        {
            Shell.Say("Backing up your settings...");
            System.Threading.Tasks.Task.Run(() => Data.RunPs("settings-backup.ps1", "-Force")).ContinueWith(t =>
            {
                var l = (t.Result ?? "").Split('\n').Select(x => x.Trim()).Where(x => x != "").ToList();
                Shell.W.Dispatcher.BeginInvoke(new Action(() => { Shell.Say(l.Count > 0 ? l[l.Count - 1] : "Backed up."); Shell.Refresh(true); }));
            });
        }
        public static void RestoreFrom()
        {
            var dlg = new Microsoft.Win32.OpenFileDialog { Title = "Pick a settings backup", Filter = "Settings backup (*.zip)|*.zip", InitialDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "PC Setup Kit Backup") };
            if (dlg.ShowDialog() != true) return;
            var o = Data.RunPs("settings-backup.ps1", $"-Restore -From {Data.Q(dlg.FileName)}");
            if (o.Contains("made on another PC"))
            {
                if (MessageBox.Show("This backup was made on another PC. Put its look and game settings on this one anyway?", "Restore settings", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
                o = Data.RunPs("settings-backup.ps1", $"-Restore -From {Data.Q(dlg.FileName)} -AnyPc");
            }
            var l = o.Split('\n').Select(x => x.Trim()).Where(x => x != "").ToList(); Shell.Say(l.Count > 0 ? l[l.Count - 1] : "Nothing to restore in that backup.");
        }
        // Messiah itself: repair (the current release again), undo the last update, the install USB, uninstall
        public static void Repair() { if (SendTray(Cmd.Repair)) Shell.Say("Repairing: the current version installs again (a window shows the result)."); else Ps("kit-update.ps1", keep: true, extra: "-Reinstall", admin: true); }
        public static void Rollback()
        {
            var pv = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), @"PCSetupKit\previous\version.txt");
            if (!File.Exists(pv)) { Shell.Say("There is no earlier version saved to go back to."); return; }
            if (MessageBox.Show($"Go back to {Kit.FirstLine(pv)}? The current version isn't installed again - the next release is.", "Undo the last update", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
            if (SendTray(Cmd.Rollback)) Shell.Say("Going back to the version before (a window shows the result)."); else Ps("kit-update.ps1", keep: true, extra: "-Rollback", admin: true);
        }
        public static void MakeUsb() { if (File.Exists(Kit.P("make-usb.ps1"))) { Ps("make-usb.ps1", keep: true, admin: true); Shell.Say("The install USB maker opened in its own window."); } else Shell.Say("The USB maker is missing - it comes with the next kit update."); }
        public static void Uninstall()
        {
            if (MessageBox.Show("Remove Messiah from this PC?\n\nThe tray icon, the automatic maintenance, updates and the app go away. Your apps, files and games stay. The removed files are kept in a folder in case you want them back.", "Uninstall Messiah", MessageBoxButton.OKCancel, MessageBoxImage.Warning) != MessageBoxResult.OK) return;
            var rv = MessageBox.Show("Also put back the Windows settings Messiah changed (telemetry, power plan, Game Bar, ...)?\n\nYes: Windows as it was before. No: keep them as they are now.", "Uninstall Messiah", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
            if (rv == MessageBoxResult.Cancel) return;
            var u = Path.Combine(Kit.KitDir, "uninstall.ps1");
            if (!File.Exists(u)) { Shell.Say("The uninstaller is missing - Repair the kit first (Settings > Tools)."); return; }
            Process.Start(new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -NoExit -File \"{u}\" -Yes{(rv == MessageBoxResult.Yes ? " -RevertTweaks" : "")}") { UseShellExecute = true, Verb = "runas" });
            Shell.W.Quit = true; Shell.W.Close();
        }
        // game saves (game-saves.ps1, Ludusavi)
        public static void GameSavesNow() { Ps("game-saves.ps1", extra: "-Run", hidden: true); Shell.Say("Backing up your game saves in the background - \"Last backup\" here updates when it's done (under a minute)."); }
        public static void GameSavesOpen() { var d = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Game Saves (Messiah)"); if (Directory.Exists(d)) Open("explorer.exe", $"\"{d}\""); else Shell.Say("No backup yet - click Back up now."); }
        public static void GameSavesRestore() { var r = Data.RunPs("game-saves.ps1", "-Restore"); Shell.Say(r != "" ? r : "Ludusavi opens - choose Restore, pick the game, and it puts the saves back."); }
        // a switch in Settings > Windows: saved, and applied now through the tray when it runs
        public static void SetTweak(string id, bool on)
        {
            Kit.SetOpt("tweak." + id, on ? "on" : "off");
            Shell.Say(SendTray(Cmd.ApplyTweaks) ? "Saved - applying it now (a few seconds; some changes need a restart)." : "Saved - applied at the next check (or click Run maintenance now).");
        }
        static void Notepad(string file, string none) { if (File.Exists(file)) Open("notepad.exe", $"\"{file}\""); else Shell.Say(none); }
        public static void FullReport() => Notepad(Kit.P("maint-report.txt"), "No report yet.");
        public static void Todo() => Notepad(Kit.P("maint-todo.txt"), "Nothing needs you right now.");
        public static void Journal() => Notepad(Kit.P("selfimprove-journal.md"), "No self-improvement runs yet.");
        public static void Logs() { if (Directory.Exists(Kit.P("maint-claude-log"))) Open("explorer.exe", $"\"{Kit.P("maint-claude-log")}\""); else Shell.Say("No hidden runs yet."); }
        public static void WatchLive() { if (!SendTray(Cmd.WatchLive)) Ps("maint-watch.ps1", keep: true); }
        // the chat isn't in this window yet: the current app opens on it
        public static void OpenChat() => Shell.W.ShowChat(true);
        public static void AskClaude(string text) { Shell.W.ShowChat(true); Shell.W.SendChat(text); }
        public static void OpenOld(string page) => Open("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"{Kit.P("dashboard.ps1")}\" -Page {page}");

        // the preview of tweaks.ps1 (-Audit): what Messiah would change right now, in a window of its own - nothing is changed
        public static void PreviewTweaks()
        {
            if (!File.Exists(Path.Combine(Kit.KitDir, "tweaks.ps1"))) { Shell.Say("The tweaks script is missing - Repair Messiah first (Settings > Tools)."); return; }
            try { Process.Start(new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -NoExit -Command \"& '{Path.Combine(Kit.KitDir, "tweaks.ps1")}' -Audit\"") { UseShellExecute = true, Verb = "runas" }); Shell.Say("The preview opens in its own window (about 10 seconds) - it lists what would change and changes nothing."); }
            catch (Exception e) { Shell.Say("The preview didn't open - " + e.Message); }
        }

        // "keep this value" (a Status row's history): the owner's own value for one setting, kept from then on - tweaks.ps1
        // reads "keep.<key>\<name>=<value>" from kit-options.txt and holds that value instead of Messiah's
        static void SetKeep(string full, string value)
        {
            var f = Kit.P("kit-options.txt"); var rx = new System.Text.RegularExpressions.Regex(@"^\s*keep\." + System.Text.RegularExpressions.Regex.Escape(full) + @"\s*=");
            var lines = Kit.Lines(f).Where(l => !rx.IsMatch(l)).ToList(); if (value != null) lines.Add($"keep.{full}={value}");
            File.WriteAllLines(f, lines);
        }
        public static void KeepValue(string full, string old)
        {
            var nm = PlainNames.Of(full);
            if (MessageBox.Show($"Keep \"{nm}\" at {(old == "(not set)" ? "Windows' default (not set)" : $"'{old}'")}?\n\nMessiah puts that value back now and keeps it that way after updates, instead of its own. Its row's details have a link to hand it back to Messiah.", "Keep this value", MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return;
            SetKeep(full, old); CheckNow(); Shell.Say($"Kept - {nm} stays the way you had it.");
        }
        public static void ManageAgain(string full) { SetKeep(full, null); CheckNow(); Shell.Say($"{PlainNames.Of(full)} is Messiah's to keep in place again."); }

        // "Copy a report for help": what someone helping needs, as text on the clipboard - versions, hardware, every
        // optimization that isn't plain green, what needs the owner, the last check. No names, paths or e-mail addresses.
        public static string Report()
        {
            var sm = StatusModel.Load(details: false);
            string hw = "";
            try
            {
                string Q1(string q, string p) { using (var s = new System.Management.ManagementObjectSearcher(q)) return string.Join(", ", s.Get().Cast<System.Management.ManagementObject>().Select(o => (o[p] ?? "").ToString().Trim()).Where(x => x != "")); }
                long ram = 0; using (var s = new System.Management.ManagementObjectSearcher("SELECT Capacity FROM Win32_PhysicalMemory")) foreach (System.Management.ManagementObject o in s.Get()) ram += Convert.ToInt64(o["Capacity"] ?? 0);
                hw = $"{Q1("SELECT Name FROM Win32_Processor", "Name").Split(',')[0]}; {Q1("SELECT Name FROM Win32_VideoController WHERE Status='OK'", "Name")}; {Math.Round(ram / 1073741824.0)} GB RAM";
            }
            catch { }
            string Reg(string n) => (Microsoft.Win32.Registry.GetValue(@"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion", n, "") ?? "").ToString();
            var L = new List<string> { $"Messiah report - {DateTime.Now:yyyy-MM-dd HH:mm}" };
            var kv = Kit.FirstLine(Path.Combine(Kit.KitDir, "kit-version.txt"));
            L.Add($"Messiah {(kv != "" ? kv : "(version unknown)")}; Windows {Reg("DisplayVersion")} build {Reg("CurrentBuild")}.{Reg("UBR")}");
            L.Add("PC: " + hw); L.Add("");
            L.Add($"STATUS: {(sm.Warn > 0 ? $"{sm.Warn} need{(sm.Warn == 1 ? "s" : "")} a look" : $"all {sm.Ok} in place")}{(sm.At != null ? $" (checked {sm.At:yyyy-MM-dd HH:mm})" : "")}");
            foreach (var r in sm.Rows.Where(r => r.Level == "warn" || (r.State ?? "").StartsWith("Put back"))) L.Add($"  [{(r.Level == "warn" ? "!" : "fixed")}] {r.Title}: {r.State}{(string.IsNullOrEmpty(r.Detail) ? "" : " - " + r.Detail)}");
            var offs = sm.Rows.Where(r => r.Level == "dim").Select(r => r.Title).ToList(); if (offs.Count > 0) L.Add("  Off by choice: " + string.Join("; ", offs));
            var keeps = StatusModel.ReadKeeps(); if (keeps.Count > 0) L.Add("  Kept by the owner: " + string.Join("; ", keeps.Keys.Select(PlainNames.Of)));
            var todo = Kit.Lines(Kit.P("maint-todo.txt")).Where(x => x.Trim() != "").ToList();
            L.Add(""); L.Add("NEEDS THE OWNER: " + (todo.Count > 0 ? "" : "nothing")); foreach (var t in todo) L.Add("  - " + t);
            L.Add(""); L.Add("LAST CHECK:"); foreach (var t in Kit.Lines(Kit.P("maint-report.txt"))) L.Add("  " + t);
            var txt = string.Join("\r\n", L);
            foreach (var (a, b) in new[] { (Kit.Home, "%USERPROFILE%"), (Environment.UserName, "<user>"), (Environment.MachineName, "<pc>") })
                if (!string.IsNullOrEmpty(a) && a.Length >= 3) txt = System.Text.RegularExpressions.Regex.Replace(txt, System.Text.RegularExpressions.Regex.Escape(a), b, System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            return System.Text.RegularExpressions.Regex.Replace(txt, @"[\w.+-]+@[\w-]+\.[\w.]+", "<email>");
        }
        public static void CopyReport() { Clipboard.SetText(Report()); Shell.Say("Copied - paste it into a message to whoever helps you. No names, paths or e-mail addresses are in it."); }

        // an action id from the status model (StatusRow.Fix, a details button)
        public static void Run(string id)
        {
            if (id == "CheckNow") CheckNow();
            else if (id == "RunMaint") RunMaint();
            else if (id.StartsWith("DiagOff:")) DiagOff(id.Substring(8));
            else if (id.StartsWith("Open:")) Open(id.Substring(5));
            else if (id.StartsWith("Page:")) { var p = id.Substring(5).Split('/'); Shell.ShowPage(p[0], p.Length > 1 ? p[1] : null); }
            else if (id.StartsWith("Keep:")) { var p = id.Substring(5).Split('\t'); KeepValue(p[0], p.Length > 1 ? p[1] : "(not set)"); }
            else if (id.StartsWith("Manage:")) ManageAgain(id.Substring(7));
        }
    }
}
