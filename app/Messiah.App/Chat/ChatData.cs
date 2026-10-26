using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Management;
using System.Text;
using System.Text.RegularExpressions;

namespace Messiah.Chat
{
    // The chat with Claude (chat-host.ps1, started by the elevated tray - app command 13): the app drops messages in
    // <chat>\inbox and follows <chat>\events.jsonl; <chat>\state.json says what it's doing. The main chat is .claude\chat,
    // more run side by side in .claude\chats\<id> (tabs). What a chat shows when it opens is its conversation's transcript.
    static class ChatData
    {
        public static string Main => Kit.P("chat");
        public static string ProjDir => Kit.P(@"projects\C--WINDOWS-system32");
        public static readonly HashSet<string> Closing = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        // the chats running here, pinned tabs first
        public static List<string> Dirs()
        {
            var all = new List<string> { Main };
            try { if (Directory.Exists(Kit.P("chats"))) all.AddRange(Directory.GetDirectories(Kit.P("chats")).OrderBy(x => x, StringComparer.OrdinalIgnoreCase).Where(x => !Closing.Contains(x))); } catch { }
            return all.Where(Pinned).Concat(all.Where(d => !Pinned(d))).ToList();
        }
        public static bool Pinned(string d) => File.Exists(Path.Combine(d, "pinned.txt"));
        public static Dictionary<string, object> State(string d) => Data.ChatState(d);
        public static string Session(string d) { var s = State(d); var id = Json.S(s, "session"); return id != "" ? id : Kit.FirstLine(Path.Combine(d, "session.txt")); }
        public static string OwnTitle(string d) => Kit.FirstLine(Path.Combine(d, "title.txt"));

        // a message or command for a chat's host; its host started when it isn't running (through the tray: elevated)
        public static void Send(string d, Dictionary<string, object> obj)
        {
            if (Kit.InTests) return;   // (a test never starts Claude or writes into a chat)
            Directory.CreateDirectory(Path.Combine(d, "inbox"));
            File.WriteAllText(Path.Combine(d, "inbox", $"{DateTime.Now:yyyyMMddHHmmssfff}-{new Random().Next()}.json"), Kit.ToJson(obj), new UTF8Encoding(false));
            StartHost(d);
        }
        public static void StartHost(string d)
        {
            if (State(d) != null) return;
            if (!Actions.SendTray(Actions.Cmd.ChatHost))
                Process.Start(new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -File \"{Kit.P("chat-host.ps1")}\"{(d.Equals(Main, StringComparison.OrdinalIgnoreCase) ? "" : $" -Dir \"{d}\"")}") { UseShellExecute = false, CreateNoWindow = true });
        }

        // a file Claude is still writing: read it anyway
        public static IEnumerable<string> ReadShared(string file)
        {
            var o = new List<string>();
            try { using (var fs = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) using (var sr = new StreamReader(fs, Encoding.UTF8)) { string l; while ((l = sr.ReadLine()) != null) o.Add(l); } } catch { }
            return o;
        }
        // what a tool call is doing, in a few words (chat-host.ps1's Get-Step: the same words)
        public static string StepText(object c)
        {
            var i = Json.Get(c, "input"); var name = Json.S(c, "name");
            string what = Json.S(i, "description") != "" ? Json.S(i, "description") : Json.S(i, "file_path") != "" ? Path.GetFileName(Json.S(i, "file_path")) : Json.S(i, "pattern") != "" ? "searching for " + Json.S(i, "pattern")
                : Json.S(i, "url") != "" ? Json.S(i, "url") : Json.S(i, "query") != "" ? Json.S(i, "query") : Json.S(i, "prompt") != "" ? Json.S(i, "prompt").Substring(0, Math.Min(60, Json.S(i, "prompt").Length)) : "";
            var verb = Regex.IsMatch(name, "^(Bash|PowerShell)$") ? "Running" : name == "Read" ? "Reading" : Regex.IsMatch(name, "^(Edit|Write|MultiEdit)$") ? "Editing" : Regex.IsMatch(name, "^(Grep|Glob)$") ? "Searching" : name.StartsWith("Web") ? "Looking up" : Regex.IsMatch(name, "^(Agent|Task)$") ? "Helper" : name;
            return verb + (what != "" ? ": " + what : "");
        }
        // a conversation from its transcript: what was asked (here, in the terminal or on the phone), the answers and the
        // steps - the last max of them
        public static List<(string T, string X)> Transcript(string id, int max = 160)
        {
            var o = new List<(string, string)>(); if (string.IsNullOrEmpty(id)) return o;
            var file = Path.Combine(ProjDir, id + ".jsonl"); if (!File.Exists(file)) return o;
            var lines = ReadShared(file).Where(l => Regex.IsMatch(l, "\"type\":\"(user|assistant)\"") && !Regex.IsMatch(l, "\"isSidechain\":true|\"type\":\"tool_result\"")).ToList();
            if (lines.Count > max * 2) lines = lines.Skip(lines.Count - max * 2).ToList();
            foreach (var l in lines)
            {
                var j = Kit.ParseJson(l) as Dictionary<string, object>; if (j == null) continue;
                var type = Json.S(j, "type"); var msg = Json.Get(j, "message"); var c = Json.Get(msg, "content");
                if (type == "user")
                {
                    if (Json.B(j, "isMeta") || Json.B(j, "isCompactSummary")) continue;
                    var x = c is string s ? s : string.Join("\n", Json.L(c).Where(b => Json.S(b, "type") == "text").Select(b => Json.S(b, "text")));
                    if (x.Trim() != "" && !x.TrimStart().StartsWith("<")) o.Add(("user", x));
                }
                else if (type == "assistant")
                    foreach (var b in Json.L(c))
                    {
                        if (Json.S(b, "type") == "text" && Json.S(b, "text").Trim() != "") o.Add(("text", Json.S(b, "text")));
                        else if (Json.S(b, "type") == "tool_use") o.Add(("tool", StepText(b)));
                    }
            }
            return o.Skip(Math.Max(0, o.Count - max)).ToList();
        }

        // a conversation's name: the one it was given, else Claude's title for it, else the last thing asked (from the
        // file's last 256 KB; kept until the file changes)
        public class Title { public string Text; public bool Hidden; }
        static readonly Dictionary<string, Title> titles = new Dictionary<string, Title>();
        public static Title SessionTitle(FileInfo f)
        {
            var key = f.FullName + "|" + f.LastWriteTime.Ticks;
            lock (titles) if (titles.TryGetValue(key, out var c)) return c;
            string tail = "";
            try { using (var fs = new FileStream(f.FullName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) { var n = (int)Math.Min(fs.Length, 262144); fs.Seek(-n, SeekOrigin.End); var buf = new byte[n]; fs.Read(buf, 0, n); tail = Encoding.UTF8.GetString(buf); } } catch { }
            string Pick(string k) { var m = Regex.Matches(tail, "\"" + k + "\":\"((?:[^\"\\\\]|\\\\.)*)\""); if (m.Count == 0) return null; try { return Kit.ParseJson("\"" + m[m.Count - 1].Groups[1].Value + "\"") as string; } catch { return null; } }
            var custom = Pick("customTitle"); Title t;
            if ((custom ?? "").StartsWith("Hidden maintenance") || Regex.IsMatch(Pick("lastPrompt") ?? "", "^(Login rehearsal|Smoke test from the Messiah app):")) t = new Title { Text = custom, Hidden = true };
            else
            {
                var title = custom ?? Pick("aiTitle") ?? Pick("lastPrompt");
                if (string.IsNullOrEmpty(title)) t = null;
                else { title = Regex.Replace(title, @"\s+", " ").Trim(); if (title.Length > 90) title = title.Substring(0, 87) + "..."; t = new Title { Text = title }; }
            }
            lock (titles) titles[key] = t;
            return t;
        }
        public static string ChatTitle(string d)
        {
            var o = OwnTitle(d); if (o != "") return o;
            var id = Session(d); var f = id != "" ? new FileInfo(Path.Combine(ProjDir, id + ".jsonl")) : null;
            var t = f != null && f.Exists ? SessionTitle(f) : null;
            return t?.Text ?? "New chat";
        }
        // earlier conversations, newest first; InUse: open somewhere else right now (a terminal, a hidden run)
        public class Earlier { public string Id, Title; public DateTime When; public bool InUse; }
        public static List<Earlier> Sessions()
        {
            var live = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try { using (var s = new ManagementObjectSearcher("SELECT CommandLine FROM Win32_Process WHERE Name='claude.exe'")) foreach (ManagementObject p in s.Get()) { var m = Regex.Match((p["CommandLine"] ?? "").ToString(), "--(session-id|resume)\\s+\"?([0-9a-fA-F-]{36})"); if (m.Success) live.Add(m.Groups[2].Value); } } catch { }
            var o = new List<Earlier>();
            try
            {
                foreach (var f in new DirectoryInfo(ProjDir).GetFiles("*.jsonl").OrderByDescending(x => x.LastWriteTime).Take(80))
                {
                    var t = SessionTitle(f); if (t == null || t.Hidden) continue;
                    var id = Path.GetFileNameWithoutExtension(f.Name);
                    o.Add(new Earlier { Id = id, Title = t.Text, When = f.LastWriteTime, InUse = live.Contains(id) || (DateTime.Now - f.LastWriteTime).TotalMinutes < 2 });   // (a terminal session: its command line has no id)
                }
            }
            catch { }
            return o;
        }
        // the chat's model and effort (mode.txt "model/effort", read by chat-host.ps1; 10/25, the owner: "no easy way to
        // select a model" - the button names the model, its menu picks model and effort apart)
        public static readonly (string Name, string Value, string About)[] Models = {
            ("Fable", "fable", "the most capable - if your plan has it"),
            ("Opus", "opus", "smart and thorough - the default"),
            ("Sonnet", "sonnet", "fast, easy on your plan's usage"),
            ("Haiku", "haiku", "fastest, for quick questions") };
        public static readonly (string Name, string Value, string About)[] Efforts = {
            ("Low", "low", "quick answers"), ("Medium", "medium", "the default"), ("High", "high", "hard problems like crash hunts"),
            ("Extra high", "xhigh", "harder still"), ("Max", "max", "slowest, uses the most") };
        public const string DefaultMode = "opus/medium";
        public static (string Model, string Effort) Mode(string d)
        {
            var m = Kit.FirstLine(Path.Combine(d, "mode.txt")).Trim().Split('/');
            return m.Length == 2 && Models.Any(x => x.Value == m[0]) && Efforts.Any(x => x.Value == m[1]) ? (m[0], m[1]) : ("opus", "medium");
        }
        public static string ModelName(string v) => Models.FirstOrDefault(x => x.Value == v).Name ?? v;
        public static string EffortName(string v) => Efforts.FirstOrDefault(x => x.Value == v).Name ?? v;
        // a conversation with nothing said yet (Claude Code writes the transcript at the first message)
        public static bool Empty(string d) { var id = Session(d); return id == "" || !File.Exists(Path.Combine(ProjDir, id + ".jsonl")); }
    }
}
