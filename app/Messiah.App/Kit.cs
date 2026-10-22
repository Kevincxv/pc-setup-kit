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
        public static DateTime? Stamp(string path) { try { if (File.Exists(path)) return File.GetLastWriteTime(path); if (Directory.Exists(path)) return Directory.GetLastWriteTime(path); } catch { } return null; }

        // --- kit-options.txt ("key=value" lines; the tray and the scripts read it too)
        public static string Opt(string key, string dflt)
        {
            var rx = new Regex(@"^\s*" + Regex.Escape(key) + @"\s*=", RegexOptions.IgnoreCase);
            var l = Lines(P("kit-options.txt")).FirstOrDefault(x => rx.IsMatch(x));
            return l == null ? dflt : l.Split(new[] { '=' }, 2)[1].Trim();
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
                    File.WriteAllLines(f, lines); return true;
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

        // --- dates: "today 10:35 AM", "yesterday 9:02 PM", "Mon 8:15 AM" (this week), "Sep 20" (older)
        public static string FormatWhen(DateTime d, bool shortForm = false, bool dateOnly = false)
        {
            int days = (DateTime.Today - d.Date).Days;
            string at = dateOnly ? "" : " " + d.ToString("h:mm tt", CultureInfo.CurrentCulture);
            if (days == 0) return shortForm && !dateOnly ? d.ToString("h:mm tt") : "today" + at;
            if (days == 1) return "yesterday" + at;
            if (days == -1) return "tomorrow" + at;
            if (days > 0 && days < 7) return d.ToString("ddd") + at;
            return d.ToString("MMM d");
        }
        static readonly Regex DateRx = new Regex(@"\b\d{1,2}/\d{1,2}/\d{4}(?: \d{1,2}:\d\d(?::\d\d)?(?: [AP]M)?)?");
        // report lines in plain words: "10/10/2026 9:01 AM" -> "today 9:01 AM", "in 48s" -> "(took 48 s)"
        public static string FormatLine(string t)
        {
            t = DateRx.Replace(t ?? "", m => DateTime.TryParse(m.Value, out var d) ? (m.Value.Contains(":") ? FormatWhen(d) : FormatWhen(d, dateOnly: true)) : m.Value);
            return Regex.Replace(t, @" in (\d+)s\b", " (took $1 s)");
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
