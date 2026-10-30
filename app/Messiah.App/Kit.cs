using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;

namespace Messiah
{
    // Where things are, and the small readers every page uses (dashboard.ps1's Get-Opt / Set-Opt / Read-Json /
    // Format-When / Format-Line, with the same rules)
    static class Kit
    {
        // %USERPROFILE%, as the scripts have it ($env:USERPROFILE\.claude, \Documents\Messiah Tray, \Documents\PC Setup Kit
        // report.txt) - not the shell's Documents folder, which may be moved (OneDrive); a test's sandbox home too
        public static string Home = Environment.GetEnvironmentVariable("USERPROFILE") is string u && u != "" ? u : Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        public static string Cl = Environment.GetEnvironmentVariable("PCKIT_CLAUDE_DIR") is string d && d != "" ? d : Path.Combine(Home, ".claude");
        public static string TrayDir = Path.Combine(Home, "Documents", "Messiah Tray");
        // the Documents folder as settings-backup.ps1 has it: the shell's own (may be moved) only for the real profile,
        // else Home\Documents - a demo profile's backup card shows the demo's backup, not the owner's (10/28)
        public static bool RealHome => string.Equals(Home.TrimEnd('\\'), Environment.GetFolderPath(Environment.SpecialFolder.UserProfile).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
        public static string Docs => RealHome ? Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments) : Path.Combine(Home, "Documents");
        public static string KitDir = @"C:\PCSetupKit";
        public static bool InTests => !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("PCKIT_IN_TESTS"));
        public static string P(string name) => Path.Combine(Cl, name);

        // --- files: never an error for a missing or busy file (the maintenance writes them all the time)
        public static string[] Lines(string file)
        {
            for (int i = 0; i < 3; i++)
            {
                try { return File.Exists(file) ? File.ReadAllLines(file, Encoding.UTF8) : new string[0]; }
                catch (IOException) { Thread.Sleep(40); }
                catch { return new string[0]; }
            }
            return new string[0];
        }
        public static string Text(string file) { try { return File.Exists(file) ? File.ReadAllText(file, Encoding.UTF8) : ""; } catch { return ""; } }
        public static string FirstLine(string file) => (Lines(file).FirstOrDefault() ?? "").Trim();
        // a saved check's time (10/27): its name (report-yyyyMMdd-HHmmss[-update].txt, claude-bg-maint.ps1) - a copied or
        // restored history gets today's file time, which made weeks of reports look like the first week; else the file time
        public static DateTime ReportTime(FileInfo f)
        {
            var m = Regex.Match(f.Name, @"^report-(\d{8}-\d{6})");
            return m.Success && DateTime.TryParseExact(m.Groups[1].Value, "yyyyMMdd-HHmmss", CultureInfo.InvariantCulture, DateTimeStyles.None, out var t) ? t : f.LastWriteTime;
        }
        public static DateTime? Stamp(string path) { try { if (File.Exists(path)) return File.GetLastWriteTime(path); if (Directory.Exists(path)) return Directory.GetLastWriteTime(path); } catch { } return null; }

        // --- kit-options.txt ("key=value" lines; the tray and the scripts read it too)
        // 10/26: read once per change of the file (its time and size), not once per call - PlainNames.Of asks for
        // 'technames' for every setting name, ~10 of the checks' 28 ms at start-up were reading this file again and again
        public static string Opt(string key, string dflt) => Opts().TryGetValue(key.Trim(), out var v) ? v : dflt;
        static Tuple<string, DateTime?, long, Dictionary<string, string>> optCache;   // (one reference: the live-read threads ask too)
        public static int OptReads;   // (how often the file was read - --test's OPTCACHE line)
        static Dictionary<string, string> Opts()
        {
            var f = P("kit-options.txt"); DateTime? at = null; long size = -1;
            try { var fi = new FileInfo(f); if (fi.Exists) { at = fi.LastWriteTimeUtc; size = fi.Length; } } catch { }
            var c = optCache;
            if (c != null && c.Item1 == f && c.Item2 == at && c.Item3 == size) return c.Item4;
            var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var l in Lines(f))
            {
                var i = l.IndexOf('='); if (i < 0) continue;
                var k = l.Substring(0, i).Trim(); if (k.Length > 0 && !map.ContainsKey(k)) map[k] = l.Substring(i + 1).Trim();   // (the first line of a key wins, as before)
            }
            Interlocked.Increment(ref OptReads); optCache = Tuple.Create(f, at, size, map); return map;
        }
        public static bool SetOpt(string key, string value)
        {
            var f = P("kit-options.txt"); var rx = new Regex(@"^\s*" + Regex.Escape(key) + @"\s*=", RegexOptions.IgnoreCase);
            for (int i = 0; i < 10; i++)   // (the tray and the AI switch write it too: a moment's clash is retried)
            {
                try
                {
                    var lines = (File.Exists(f) ? File.ReadAllLines(f) : new string[0]).Where(x => !rx.IsMatch(x)).ToList();
                    if (!string.IsNullOrEmpty(value)) lines.Add(key + "=" + value);   // (empty: the line goes - back to the default)
                    File.WriteAllLines(f, lines); optCache = null; return true;
                }
                catch { Thread.Sleep(100); }
            }
            return false;
        }

        // --- the AI assistant (ai-enabled.ps1's rule: kit-options "claude=on"; an install from before the option: the
        // Messiah shortcuts say it was on)
        public static bool AiOn()
        {
            if (File.Exists(P("kit-options.txt"))) return Lines(P("kit-options.txt")).Any(x => Regex.IsMatch(x, @"^\s*claude\s*=\s*on\s*$", RegexOptions.IgnoreCase));
            var home = Path.GetDirectoryName(Cl);
            return File.Exists(P("admin-sessions.txt")) || File.Exists(P("Messiah Session.lnk")) ||
                File.Exists(Path.Combine(home, @"AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Messiah.lnk")) ||
                File.Exists(Path.Combine(home, @"AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Claude (Admin).lnk"));
        }

        // --- JSON: objects come back as Dictionary<string, object>, lists as object[]; Json.S / Json.N read them safely
        static readonly JavaScriptSerializer Ser = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
        public static Dictionary<string, object> ReadJson(string file)
        {
            try { var t = Text(file); if (t.Trim() == "") return null; return Ser.DeserializeObject(t) as Dictionary<string, object>; } catch { return null; }
        }
        public static object ParseJson(string text) { try { return Ser.DeserializeObject(text); } catch { return null; } }
        public static string ToJson(object o) => Ser.Serialize(o);

        // --- dates: "today 10:35 AM", "yesterday 9:02 PM", "Mon Oct 26 8:15 AM" (this week), "Sep 20" (older)
        public static string FormatWhen(DateTime d, bool shortForm = false, bool dateOnly = false)
        {
            int days = (DateTime.Today - d.Date).Days;
            string at = dateOnly ? "" : " " + d.ToString("h:mm tt", CultureInfo.CurrentCulture);
            if (days == 0) return shortForm && !dateOnly ? d.ToString("h:mm tt") : "today" + at;
            if (days == 1) return "yesterday" + at;
            if (days == -1) return "tomorrow" + at;
            // (10/28: 'Last backup Mon 12:00 PM' was a bare weekday where Checks' list and the backup card's next line give the date)
            if (days > 0 && days < 7) return d.ToString("ddd MMM d") + at;
            // (10/28: a blue screen from last year in Stability's list read 'Oct 8' like this year's - the year when it isn't this one)
            return d.ToString(d.Year == DateTime.Today.Year ? "MMM d" : "MMM d, yyyy");
        }
        // a chart point or mark in full: "Wed Oct 8, 3:00 AM" - the year too when it isn't this one (Stability's 120 days cross New Year in January)
        public static string Stamp(DateTime d, bool time = true) =>
            d.ToString(d.Year == DateTime.Today.Year ? "ddd MMM d" : "ddd MMM d, yyyy") + (time ? d.ToString(", h:mm tt") : "");
        static readonly Regex DateRx = new Regex(@"\b\d{1,2}/\d{1,2}/\d{4}(?: \d{1,2}:\d\d(?::\d\d)?(?: [AP]M)?)?");
        // report lines in plain words: "10/10/2026 9:01 AM" -> "today 9:01 AM", "in 48s" -> "(took 48 s)", "in 64s" -> "(took about a minute)"
        public static string FormatLine(string t)
        {
            t = DateRx.Replace(t ?? "", m => DateTime.TryParse(m.Value, out var d) ? (m.Value.Contains(":") ? FormatWhen(d) : FormatWhen(d, dateOnly: true)) : m.Value);
            return Regex.Replace(t, @" in (\d+)s\b", m => " (took " + Took(int.Parse(m.Groups[1].Value)) + ")");
        }
        // 64 s reads slower than 'about a minute' (10/28); under a minute the seconds stay
        public static string Took(int s)
        {
            if (s < 60) return s + " s";
            int min = (int)Math.Round(s / 60.0, MidpointRounding.AwayFromZero);
            return min <= 1 ? "about a minute" : $"about {min} minutes";
        }
        public static DateTime? Date(object v) => v != null && DateTime.TryParse(v.ToString(), out var d) ? d : (DateTime?)null;
        public static string Plural(int n, string one, string many) => n == 1 ? one : many;
        public static string S(int n) => n == 1 ? "" : "s";
    }

    // reading the JavaScriptSerializer's dictionaries without a cast on every line
    static class Json
    {
        public static object Get(object o, string key) => o is IDictionary<string, object> d && d.TryGetValue(key, out var v) ? v : null;
        public static string S(object o, string key) => Get(o, key)?.ToString() ?? "";
        public static double? N(object o, string key) { var v = Get(o, key); if (v == null) return null; return double.TryParse(Convert.ToString(v, CultureInfo.InvariantCulture), NumberStyles.Float, CultureInfo.InvariantCulture, out var n) ? n : (double?)null; }
        public static bool B(object o, string key) { var v = Get(o, key); return v is bool b ? b : v != null && v.ToString().Equals("true", StringComparison.OrdinalIgnoreCase); }
        public static IEnumerable<object> L(object o, string key) => Get(o, key) is IEnumerable e && !(Get(o, key) is string) ? e.Cast<object>() : Enumerable.Empty<object>();
        public static IEnumerable<object> L(object o) => o is IEnumerable e && !(o is string) && !(o is IDictionary<string, object>) ? e.Cast<object>() : Enumerable.Empty<object>();
    }
}
