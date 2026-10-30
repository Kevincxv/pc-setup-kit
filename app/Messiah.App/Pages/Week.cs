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
        // a driver install's own line (driver-check.ps1; the same as claude-bg-maint's after-update trigger). Was
        // '^(Driver|NVIDIA|AMD chipset): .*installed', which also counted 'NVIDIA: 566.03 installed; no NVIDIA app
        // recommendation...' (a check, not an install) and '... hidden, not installed' - one update read '2 drivers' (10/28)
        internal const string Drivers = @"^(Driver: .* - installed$|NVIDIA: installed|AMD (Radeon|chipset): installed)";
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
                if (f != null) { parts.Add($"{f:0} fps per session" + (fb != null ? $" ({Pct(f.Value, fb.Value)})" : "")); if (fb != null && f < fb * 0.92) lvl = "warn"; }
                var lo = Med(mine.Select(r => Json.N(r, "low1"))); if (lo != null) parts.Add($"1% low {lo:0}");
                if (parts.Count > 0) o.Add((Data.GameName(g), string.Join(", ", parts), lvl));
            }
            // crashes: blue screens and the PC going off by itself (not the owner turning it off)
            var cr = s.Power.Where(e => e.At >= from && e.At <= now && (e.Kind == "bsod" || e.Answer != "me")).ToList();   // (Stability's own count: a power-off not answered yet counts)
            o.Add(("Crashes", cr.Count == 0 ? "None" : $"{cr.Count} - {string.Join(", ", cr.Select(e => e.Kind == "bsod" ? "blue screen " + e.Code : e.Answer == "froze" ? "went off by itself" : "went off (not answered yet)").Distinct())}", cr.Count == 0 ? "ok" : "warn"));
            // what the checks did (the week's saved reports)
            var lines = (reports ?? ReadReports(from)).SelectMany(x => x).Select(x => x.Trim()).Distinct().ToList();
            int N(string rx) => lines.Count(x => Regex.IsMatch(x, rx));
            int apps = N(@"^Updated app"), drv = N(Drivers), back = N(@"reverted \d+ - re-applied|had been reset .* re-applied"), kit = N(@"^PC Setup Kit updated");
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
                o.Add(("Connection", $"Ping {Med(net.Select(r => Json.N(r, "netPing"))):0} ms while playing, " + (bad == 0 ? "no lag" : $"lag in {bad} of {net.Count} measured minutes"), bad > net.Count / 4 ? "warn" : "info"));
            }
            // the hottest it got while gaming
            var gt = week.Select(r => Json.N(r, "gpuTemp")).Where(x => x != null).DefaultIfEmpty(null).Max(); var ct = week.Select(r => Json.N(r, "cpuTemp")).Where(x => x != null).DefaultIfEmpty(null).Max();
            // (10/28: each with a word - '73 °C' alone told a friend nothing; the card's own heat slowdown counts as hot whatever the number)
            var gHeat = week.Any(r => Json.S(r, "throttle").Contains("heat"));
            if (gt != null || ct != null) o.Add(("Hottest", string.Join(", ", new[] { gt != null ? $"Graphics card {gt:0} °C ({HeatWord(gt.Value, GpuHot, gHeat)})" : null, ct != null ? (gt != null ? "processor" : "Processor") + $" {ct:0} °C ({HeatWord(ct.Value, CpuHot, false)})" : null }.Where(x => x != null)), (gt ?? 0) >= GpuHot || gHeat || (ct ?? 0) >= CpuHot ? "warn" : "info"));
            return o;
        }
        // Heat and wear's limits (Performance.Heat warns from these); 'warm' is the last 7 °C below one
        public const double GpuHot = 85, CpuHot = 88;
        public static string HeatWord(double t, double hot, bool slowed) =>
            slowed ? "hot - it slowed itself down" : t >= hot ? "hot" : t >= hot - 7 ? "warm" : "normal";
        static IEnumerable<string[]> ReadReports(DateTime from)
        {
            var d = Kit.P("maint-history"); if (!Directory.Exists(d)) yield break;
            foreach (var f in new DirectoryInfo(d).GetFiles("report-*.txt").Where(x => Kit.ReportTime(x) >= from)) yield return Kit.Lines(f.FullName);
        }
        // the first week (10/26): no saved report older than a week - the card shows anyway, with a line saying it fills in
        // (before: a new install had no card at all, and "Nothing needed doing" before the first check had run)
        // (10/27: by the reports' names, not their file times; and only the newest 30 are kept, so checks that run often
        // could prune the first week's away - the schedule in maint-state.json remembers older ones)
        internal static DateTime? FirstReport()
        {
            var d = Kit.P("maint-history"); if (!Directory.Exists(d)) return null;
            var f = new DirectoryInfo(d).GetFiles("report-*.txt"); if (f.Length == 0) return null;
            var first = f.Min(Kit.ReportTime);
            var st = Kit.ReadJson(Kit.P("maint-state.json"));
            if (st != null) foreach (var v in st.Values) if (v is string sv && Regex.IsMatch(sv, @"^\d{4}-\d\d-\d\dT") && Kit.Date(sv) is DateTime t && t < first) first = t;
            return first;
        }
        internal static UIElement Card(Snapshot s)
        {
            var rows = Rows(s); var now = Now ?? DateTime.Now; var first = FirstReport();
            var since = first ?? now; var newWeek = since > now.AddDays(-7);
            if (first == null) rows = rows.Select(r => r.Label == "Maintenance" ? (r.Label, "Not checked yet - the first check runs in the background after login", r.Level) : r).ToList();
            // a week with no games, no crashes and nothing done: no card (nothing to say) - unless it's the first week
            if (!newWeek && rows.All(r => (r.Label == "Crashes" && r.Value == "None") || (r.Label == "Maintenance" && r.Value == "Nothing needed doing"))) return null;
            var body = new List<object> { Ui.Rows(rows, (l, v) => Go(l)) };
            if (newWeek) body.Add(new Line($"Your first week with Messiah - the games you play, any crashes and what the checks did fill in here as they happen. A full week from {Kit.FormatWhen(since.AddDays(7), dateOnly: true)}.", "dim"));
            return Ui.Card("This week", "E787", body);
        }
        // where a row goes (10/26, the owner's backlog: "each row opens its page"): a game to its own card on Performance, the
        // crashes to Stability, maintenance to Checks, the connection and the heat to their cards - the rows replace the two
        // buttons under the card and the "(Health > Stability)" pointers in the words
        internal static string Go(string label)
        {
            switch (label)
            {
                case "Crashes": return "Activity/Stability";
                case "Maintenance": return "Activity/Checks";
                case "Connection": return "Activity/Performance#Connection";
                case "Hottest": return "Activity/Performance#Heat and wear";
                default: return "Activity/Performance#" + label;   // (a game: its card has its name)
            }
        }
    }
}
