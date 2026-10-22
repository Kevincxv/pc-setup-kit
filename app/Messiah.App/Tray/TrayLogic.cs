using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace Messiah.Tray
{
    // The tray's decisions, apart from the screen (Messiah Tray.ahk's functions until 10/21: the same files, words and
    // rules) - what the tooltip says, what to tell the owner and when, pausing. --tray-test runs them (tray-logic.ps1).
    static class TrayLogic
    {
        public const string Name = "Messiah";
        static string Notified => Kit.P("tray-notified.ini");

        // tray-notified.ini: [shown] key=value (what was told already)
        public static string Ini(string key)
        {
            foreach (var l in Kit.Lines(Notified)) { var m = Regex.Match(l, @"^\s*" + Regex.Escape(key) + @"\s*=(.*)$"); if (m.Success) return m.Groups[1].Value.Trim(); }
            return "";
        }
        public static void SetIni(string key, string value)
        {
            var lines = Kit.Lines(Notified).ToList(); int at = lines.FindIndex(l => Regex.IsMatch(l, @"^\s*" + Regex.Escape(key) + @"\s*="));
            if (at >= 0) lines[at] = key + "=" + value;
            else { if (!lines.Any(l => l.Trim() == "[shown]")) lines.Insert(0, "[shown]"); lines.Add(key + "=" + value); }
            try { File.WriteAllLines(Notified, lines, new UTF8Encoding(false)); } catch { }
        }
        static string Stamp(string f) => File.Exists(f) ? File.GetLastWriteTime(f).ToString("yyyyMMddHHmmss") : "";

        // hidden Claude maintenance running: a marker from this start-up, under an hour old
        public static bool MaintRunning()
        {
            var f = Kit.P("maint-claude-running"); if (!File.Exists(f)) return false;
            var t = File.GetLastWriteTime(f); return (DateTime.Now - t).TotalMinutes < 60 && t > Data.BootTime;
        }
        public static List<string> Todo() => Kit.Lines(Kit.P("maint-todo.txt")).Select(x => x.Trim()).Where(x => x != "").ToList();

        // the tooltip: how many things need the owner; hidden maintenance running
        public static string Tip(bool ai)
        {
            int n = Todo().Count;
            var tip = n > 0 ? $"{Name} - {n} maintenance item{(n == 1 ? " needs" : "s need")} you" : Name;
            if (ai && MaintRunning()) tip += $"\nHidden maintenance running (open {Name} > Activity > Watch live)";
            return tip;
        }

        // What to tell the owner (every 30 s): a new to-do list, a message from the maintenance (what's new, the weekly
        // summary), work waiting for the next shutdown - each once. Nothing while a game or video is fullscreen.
        public static string Notify(bool fullscreen)
        {
            if (fullscreen) return null;
            var f = Kit.P("maint-todo.txt"); var st = Stamp(f);
            if (st != "" && st != Ini("todo"))
            {
                var items = Todo(); SetIni("todo", st);
                if (items.Count > 0) { var first = items[0].Length > 110 ? items[0].Substring(0, 107) + "..." : items[0]; return $"Needs you ({items.Count}): {first}" + (items.Count > 1 ? $"\n+ {items.Count - 1} more" : ""); }
            }
            f = Kit.P("tray-news.txt"); st = Stamp(f);
            if (st != "" && st != Ini("news"))
            {
                SetIni("news", st);
                string txt; try { txt = File.ReadAllText(f).Trim(' ', '\r', '\n', '﻿'); } catch { txt = ""; }
                if (txt != "") return txt.Length > 330 ? txt.Substring(0, 327) + "..." : txt;
            }
            f = Kit.P("restart-ledger.json");
            if (File.Exists(f))
            {
                string txt; try { txt = File.ReadAllText(f); } catch { txt = ""; }
                int n = Regex.Matches(txt, "\"Kind\"").Count; var m = Regex.Match(txt, "\"boot\":\\s*\"([^\"]+)\"");
                var key = (m.Success ? m.Groups[1].Value : "") + "|" + n;
                if (n > 0 && key != Ini("restart")) { SetIni("restart", key); return $"{n} update(s)/fix(es) will finish the next time you turn the PC off.\nNo need to restart now - whenever suits you."; }
            }
            return null;
        }
        // The owner's rule (10/10): Messiah never pops up by itself - an alert goes to the app (Activity > Alerts) and the
        // tooltip, quietly; "Show alerts in the corner" (kit-options.txt cornernotes=on) shows it too. True: show it.
        public static bool Alert(string text) { LogNote(text); return Kit.Opt("cornernotes", "off") == "on"; }

        // every alert in notifications.log ("yyyy-MM-dd HH:mm|text", line breaks as " / "), the newest 200
        public static void LogNote(string text)
        {
            var f = Kit.P("notifications.log");
            try
            {
                File.AppendAllText(f, DateTime.Now.ToString("yyyy-MM-dd HH:mm") + "|" + text.Replace("\r", "").Replace("\n", " / ") + "\n", new UTF8Encoding(false));
                if (new FileInfo(f).Length > 60000) { var l = Kit.Lines(f).Where(x => x != "").ToArray(); File.WriteAllText(f, string.Join("\n", l.Skip(Math.Max(0, l.Length - 200))) + "\n", new UTF8Encoding(false)); }
            }
            catch { }
        }

        // Pause maintenance for some hours (0 = resume): kit-options.txt "pause-until=" (paused.ps1). What to say.
        public static string SetPause(int hours)
        {
            var f = Kit.P("kit-options.txt");
            var keep = Kit.Lines(f).Where(x => x.Trim() != "" && !Regex.IsMatch(x, @"^\s*pause-until\s*=")).ToList();
            var until = DateTime.Now.AddHours(hours);
            if (hours > 0) keep.Add("pause-until=" + until.ToString("yyyy-MM-ddTHH:mm:ss"));
            try { File.WriteAllText(f, string.Join("\n", keep) + "\n", new UTF8Encoding(false)); } catch { }
            return hours > 0 ? $"Maintenance paused until {until:ddd h:mm tt}.\nTray > Pause maintenance > Resume now to start it again." : "Maintenance runs again as usual.";
        }

        // At login: the welcome page once after a new install; else the window only with "Open at login" on, once per
        // start-up (a tray restart doesn't reopen it), held while a game is fullscreen (up to 15 min after boot).
        // Returns the page to open ("" = the app as it was), "wait" (try again in a minute), or null.
        public static string AtLogin(bool fullscreen)
        {
            if (Kit.InTests && Environment.GetEnvironmentVariable("PCKIT_LOGIN_TEST") == null) return null;
            var opts = Kit.Lines(Kit.P("kit-options.txt"));
            if (opts.Any(x => Regex.IsMatch(x, @"^\s*welcome\s*=\s*pending\s*$", RegexOptions.IgnoreCase)) && Ini("welcome") == "")
            {
                if (fullscreen) return "wait";
                SetIni("welcome", "1"); return "Welcome";
            }
            if (!opts.Any(x => Regex.IsMatch(x, @"^\s*openatlogin\s*=\s*on\s*$", RegexOptions.IgnoreCase))) return null;
            var boot = Data.BootTime; var last = Ini("status-boot");
            if (DateTime.TryParseExact(last, "yyyyMMddHHmmss", null, System.Globalization.DateTimeStyles.None, out var lb) && Math.Abs((boot - lb).TotalSeconds) < 120) return null;
            if (fullscreen && (DateTime.Now - boot).TotalMinutes < 15) return "wait";
            SetIni("status-boot", boot.ToString("yyyyMMddHHmmss"));
            return fullscreen ? null : "";
        }

        // Login rehearsal (rehearse-login.ps1): "ignorepids=" - sessions that stay open during the test and count as not
        // running; honored for 10 minutes after the file was written
        public static HashSet<int> RehearsalPids()
        {
            var m = new HashSet<int>(); var f = Kit.P("rehearsal.txt");
            if (File.Exists(f) && (DateTime.Now - File.GetLastWriteTime(f)).TotalMinutes < 10)
                foreach (var l in Kit.Lines(f)) { var mm = Regex.Match(l, "^ignorepids=(.*)"); if (mm.Success) foreach (var p in mm.Groups[1].Value.Split(',')) if (int.TryParse(p.Trim(), out var n)) m.Add(n); }
            return m;
        }

        // a chat's last answer, short (events.jsonl {"t":"text","text":...}); "-" when there's none
        public static string LastReply(string dir)
        {
            try
            {
                var lines = Kit.Lines(Path.Combine(dir, "events.jsonl"));
                for (int i = lines.Length - 1; i >= 0; i--)
                {
                    var e = Kit.ParseJson(lines[i]); if (Json.S(e, "t") != "text") continue;
                    var s = Regex.Replace(Regex.Replace(Json.S(e, "text"), @"[*`#]+", ""), @"\s+", " ").Trim();
                    return s == "" ? "-" : s.Length > 140 ? s.Substring(0, 137) + "..." : s;
                }
            }
            catch { }
            return "-";
        }

        // what the tray did wrong, for /self-improve - never an error box
        public static void Error(string what) { try { File.AppendAllText(Kit.P("tray-errors.log"), $"{DateTime.Now:yyyy-MM-dd HH:mm:ss}  {what}\n", Encoding.UTF8); } catch { } }

        // --tray-test <what> [fs]: the checks tray-logic.ps1 makes, printed
        public static int Test(string what, bool fs)
        {
            var o = new StringBuilder();
            int hours = 0; if (what.StartsWith("pause:")) { int.TryParse(what.Substring(6), out hours); what = "pause"; }
            switch (what)
            {
                case "tip": o.Append(Tip(Environment.GetEnvironmentVariable("TEST_AI") != "0")); break;
                case "running": o.Append(MaintRunning() ? "yes" : "no"); break;
                case "notify": { var t = Notify(fs); if (t != null && Alert(t)) o.Append(t.Replace("\n", " \\n ")); break; }
                case "ai": o.Append(Kit.AiOn() ? "on" : "off"); break;
                case "login": { var p = AtLogin(fs); if (p != null && p != "wait") o.Append("OPENED" + (p != "" ? " " + p : "")); break; }
                case "log": LogNote("First line\nsecond line"); break;
                case "log250": for (int i = 1; i <= 250; i++) LogNote($"note {i} " + new string('x', 300)); break;
                case "pause": o.Append(SetPause(hours).Replace("\n", " \\n ")); break;
                case "pids": foreach (var k in RehearsalPids()) o.Append(k).Append(','); break;
                case "reply": o.Append(LastReply(Kit.P("chat"))); break;
                case "error": Error("test error (a window that vanished mid-look)"); o.Append("still running"); break;
                case "menu": o.Append(TrayHost.MenuText(Environment.GetEnvironmentVariable("TEST_AI") != "0")); break;
                case "commands": foreach (var kv in TrayHost.Scripts) o.Append($"{(int)kv.Key} {kv.Key}: {kv.Value.How} {kv.Value.Script} {kv.Value.Args}".TrimEnd()).Append('\n'); break;
                case "hotkey": o.Append("Ctrl+Alt+M"); break;
                case "boost": o.Append(string.Join(",", TrayHost.Background)); break;
            }
            var b = new UTF8Encoding(false).GetBytes(o.ToString()); var s = Console.OpenStandardOutput(); s.Write(b, 0, b.Length); s.Flush();
            return 0;
        }
    }
}
