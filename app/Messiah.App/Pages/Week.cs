using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;

namespace Messiah.Pages
{
    // "This week" on Home (10/25, the owner: "the PC this week: FPS trend, crashes, what maintenance fixed"): one short
    // table from what's already recorded - the games (time played from game-sessions.log; the frame rate this week vs the
    // 3 weeks before, perf-history.json), crashes (power-log), what the checks did (maint-history), the connection while
    // playing and the hottest it got. A row only when there's something to say; no card in a week with nothing at all.
    static class Week
    {
        internal static DateTime? Now;   // (tests)
        static double? Med(IEnumerable<double?> v) { var s = v.Where(x => x != null).Select(x => x.Value).OrderBy(x => x).ToList(); return s.Count == 0 ? (double?)null : s[s.Count / 2]; }
        static string Pct(double now, double was) { var p = (now - was) / was * 100; return Math.Abs(p) < 3 ? "as usual" : $"{(p > 0 ? "+" : "")}{p:0}% vs usual"; }

        internal static List<(string Label, string Value, string Level)> Rows(Snapshot s, string[] sessionsLog = null, IEnumerable<string[]> reports = null)
        {
            var now = Now ?? DateTime.Now; var from = now.AddDays(-7); var o = new List<(string, string, string)>();
            DateTime? D(Dictionary<string, object> r) => Kit.Date(Json.Get(r, "date"));
            // the games: time played, and the frame rate against the 3 weeks before
            var played = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
            foreach (var l in sessionsLog ?? Kit.Lines(Kit.P("game-sessions.log")))
            {
                var m = Regex.Match(l, @"^(\S+) \| (\S+) \| (.+)$");
                if (m.Success && DateTime.TryParse(m.Groups[1].Value, out var a) && DateTime.TryParse(m.Groups[2].Value, out var b) && b >= from) { var g = m.Groups[3].Value.Trim(); played[g] = (played.TryGetValue(g, out var x) ? x : 0) + (b - (a < from ? from : a)).TotalMinutes; }
            }
            var week = s.Perf.Where(r => D(r) >= from && D(r) <= now).ToList();
            foreach (var g in week.Select(r => Json.S(r, "game")).Where(x => x != "").Concat(played.Keys).Distinct(StringComparer.OrdinalIgnoreCase).Take(4))
            {
                var mine = week.Where(r => Json.S(r, "game").Equals(g, StringComparison.OrdinalIgnoreCase)).ToList();
                var before = s.Perf.Where(r => Json.S(r, "game").Equals(g, StringComparison.OrdinalIgnoreCase) && D(r) < from && D(r) >= from.AddDays(-21)).ToList();
                var parts = new List<string>(); var lvl = "info";
                if (played.TryGetValue(g, out var min) && min >= 5) parts.Add(min >= 60 ? $"{min / 60:0.#} h played" : $"{min:0} min played");
                var f = Med(mine.Select(r => Json.N(r, "fps"))); var fb = Med(before.Select(r => Json.N(r, "fps")));
                if (f != null) { parts.Add($"{f:0} fps" + (fb != null ? $" ({Pct(f.Value, fb.Value)})" : "")); if (fb != null && f < fb * 0.92) lvl = "warn"; }
                var lo = Med(mine.Select(r => Json.N(r, "low1"))); if (lo != null) parts.Add($"1% low {lo:0}");
                if (parts.Count > 0) o.Add((Data.GameName(g), string.Join(", ", parts), lvl));
            }
            // crashes: blue screens and the PC going off by itself (not the owner turning it off)
            var cr = s.Power.Where(e => e.At >= from && e.At <= now && (e.Kind == "bsod" || e.Answer != "me")).ToList();   // (Stability's own count: a power-off not answered yet counts)
            o.Add(("Crashes", cr.Count == 0 ? "None" : $"{cr.Count} - {string.Join(", ", cr.Select(e => e.Kind == "bsod" ? "blue screen " + e.Code : e.Answer == "froze" ? "went off by itself" : "went off (not answered yet)").Distinct())} (Health > Stability)", cr.Count == 0 ? "ok" : "warn"));
            // what the checks did (the week's saved reports)
            var lines = (reports ?? ReadReports(from)).SelectMany(x => x).Select(x => x.Trim()).Distinct().ToList();
            int N(string rx) => lines.Count(x => Regex.IsMatch(x, rx));
            int apps = N(@"^Updated app"), drv = N(@"^(Driver|NVIDIA|AMD chipset): .*installed"), back = N(@"reverted \d+ - re-applied|had been reset .* re-applied"), kit = N(@"^PC Setup Kit updated");
            var freed = lines.Select(x => Regex.Match(x, @"freed ([\d.,]+) GB")).Where(m => m.Success).Sum(m => double.TryParse(m.Groups[1].Value, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var v) ? v : 0);
            var did = new List<string>();
            if (apps > 0) did.Add($"{apps} app update{Kit.S(apps)}"); if (drv > 0) did.Add($"{drv} driver{Kit.S(drv)}");
            if (back > 0) did.Add($"settings put back {back} time{Kit.S(back)}"); if (freed >= 0.1) did.Add($"{freed:0.#} GB cleaned up"); if (kit > 0) did.Add("Messiah updated itself");
            o.Add(("Maintenance", did.Count > 0 ? string.Join(", ", did) : "Nothing needed doing", "info"));
            // the connection while playing
            var net = week.Where(r => Json.N(r, "netPing") != null).ToList();
            if (net.Count > 0)
            {
                var idle = Connection.IdleOf(s.Net); var bad = net.Count(r => Connection.Bad(r, idle));
                o.Add(("Connection", $"ping {Med(net.Select(r => Json.N(r, "netPing"))):0} ms while playing, " + (bad == 0 ? "no lag" : $"lag in {bad} of {net.Count} measured minutes (Games > Performance)"), bad > net.Count / 4 ? "warn" : "info"));
            }
            // the hottest it got while gaming
            var gt = week.Select(r => Json.N(r, "gpuTemp")).Where(x => x != null).DefaultIfEmpty(null).Max(); var ct = week.Select(r => Json.N(r, "cpuTemp")).Where(x => x != null).DefaultIfEmpty(null).Max();
            if (gt != null || ct != null) o.Add(("Hottest", string.Join(", ", new[] { gt != null ? $"graphics card {gt:0} °C" : null, ct != null ? $"processor {ct:0} °C" : null }.Where(x => x != null)), (gt ?? 0) >= 85 || (ct ?? 0) >= 88 ? "warn" : "info"));
            return o;
        }
        static IEnumerable<string[]> ReadReports(DateTime from)
        {
            var d = Kit.P("maint-history"); if (!Directory.Exists(d)) yield break;
            foreach (var f in new DirectoryInfo(d).GetFiles("report-*.txt").Where(x => x.LastWriteTime >= from)) yield return Kit.Lines(f.FullName);
        }
        internal static UIElement Card(Snapshot s)
        {
            var rows = Rows(s);
            // a week with no games, no crashes and nothing done: no card (nothing to say)
            if (rows.All(r => (r.Label == "Crashes" && r.Value == "None") || (r.Label == "Maintenance" && r.Value == "Nothing needed doing"))) return null;
            return Ui.Card("This week", "E787", new object[] { Ui.Rows(rows) }, new[] { Ui.Btn("E9D2", "Performance", () => Shell.ShowPage("Activity", "Performance"), small: true), Ui.Btn("E81C", "What maintenance did", () => Shell.ShowPage("Activity", "Checks"), small: true) });
        }
    }
}
