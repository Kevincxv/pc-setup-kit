using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using Sh = System.Windows.Shapes;

namespace Messiah.Pages
{
    // Games > Performance (10/21): how the games run - each game's last minute second by second (its frame rate, and its
    // slowest frame each second: the hitches you feel), its frame rate over the sessions, and what a graphics driver or
    // Windows update did to it (the sessions before and after, side by side). From game-perf.ps1's samples (perf-history.json:
    // a minute every 25 minutes while a game is played - not its menus).
    static class Performance
    {
        static Brush B(string k) => Theme.B[k];
        static double Num(object o) { try { return Convert.ToDouble(o, System.Globalization.CultureInfo.InvariantCulture); } catch { return 0; } }

        public static List<UIElement> Build(Snapshot s)
        {
            var o = new List<UIElement>(); Connection.Idle = Connection.IdleOf(s.Net);
            var games = s.Perf.Where(r => Json.S(r, "game") != "" && Kit.Date(Json.Get(r, "date")) != null).GroupBy(r => Json.S(r, "game"))
                .OrderByDescending(g => Kit.Date(Json.Get(g.Last(), "date"))).ToList();
            if (games.Count == 0)
                o.Add(Ui.Card("Nothing measured yet", "E7FC", new object[] { new Line("While you play, a minute of each game is measured every 25 minutes (menus and lobbies don't count): its frame rate, the slowest frames, the graphics card's heat. Play a few minutes and it shows here.", "dim") }));
            // what's going on first (a test under way, a driver on test), then the games played this month, then the rest in a
            // line each (10/22 audit: a game last played weeks ago led the page)
            if (s.LastSession != null) o.Add(Ui.Card("Last session", "E7FC", Data.SessionLines(s.LastSession).Cast<object>()));
            var tune = Tuning(s); if (tune != null) o.Add(tune);
            var drv = DriverTest(s); if (drv != null) o.Add(drv);
            var cut = DateTime.Now.AddDays(-30);
            var recent = games.Where(g => Kit.Date(Json.Get(g.Last(), "date")) >= cut).Take(6).ToList();
            NoteKey = SecsNoteKey(recent.Select(g => (g.Key, g.Last())));
            var hz = Native.ScreenHz();
            foreach (var g in recent) o.Add(Game(Data.GameName(g.Key), g.Key, g.ToList(), s.Tune, hz));
            var older = games.Except(recent).ToList();
            if (older.Count > 0)
                o.Add(Ui.Card(recent.Count > 0 ? "Earlier games" : "Games - not played this month", "E7FC", new object[] { Ui.Rows(older.Select(g => { var l = g.Last(); return (Data.GameName(g.Key), $"{Math.Round(Json.N(l, "fps") ?? 0)} fps average, 1% low {Math.Round(Json.N(l, "low1") ?? 0)} fps, last played {Kit.FormatWhen(Kit.Date(Json.Get(l, "date")).Value, dateOnly: true)}", "dim"); })) }));
            if (games.Count > 0) o.Add(Updates(games, s.Tune));
            var net = Connection.Card(s); if (net != null) o.Add(net);
            o.Add(Heat(s));
            o.Add(Benchmark(s));
            if (games.Count > 0) o.Add(Activity.Foot("Measured with Intel's PresentMon for one minute while the game runs. 1% low: only 1 frame in 100 is slower - what you feel as smoothness. A hitch: a frame over 50 ms."));
            return o;
        }

        // --- tuning by measurement (game-tune.ps1): the setting being tried both ways in your matches, and what each test found
        
        // 'a 75%' but 'an 85%', 'an 8%', 'an 11%', 'an 18%' - the article goes by how the number is read aloud
        internal static string A(double n) { var s = n.ToString("0", System.Globalization.CultureInfo.InvariantCulture); return (s.StartsWith("8") || s == "11" || s == "18" ? "an " : "a ") + s; }
        internal static string Say(string id, string v)
        {
            switch (id)
            {
                case "reflex": return v == "Enabled + boost" ? "Reflex Boost on" : "Reflex Boost off";
                case "vram": return double.TryParse(v, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var x) ? $"{A(Math.Round(x * 100))}% video memory budget" : v;
                case "workers": return v == "-1" ? "automatic renderer threads" : $"{v} renderer threads";
                case "uploadheaps": return v == "true" ? "GPU upload heaps on" : "GPU upload heaps off";
                default: return v;
            }
        }
        // The setting's name once and its values bare, for the "Trying now" line ('video memory budget 85% against 75%',
        // not the name three times); null for a setting without a short form - the line then uses Say's whole words
        internal static string[] Short(string id, string a, string b, string on)
        {
            string V(string v)
            {
                switch (id)
                {
                    case "reflex": return v == "Enabled + boost" ? "on" : "off";
                    case "vram": return double.TryParse(v, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var x) ? $"{Math.Round(x * 100)}%" : null;
                    case "workers": return v == "-1" ? "automatic" : v;
                    case "uploadheaps": return v == "true" ? "on" : "off";
                    default: return null;
                }
            }
            var name = id == "reflex" ? "Reflex Boost" : id == "vram" ? "video memory budget" : id == "workers" ? "renderer threads" : id == "uploadheaps" ? "GPU upload heaps" : null;
            string va = V(a), vb = V(b), von = V(on);
            return name == null || va == null || vb == null || von == null ? null : new[] { name, va, vb, von };
        }
        static UIElement Tuning(Snapshot s)
        {
            var t = s.Tune; var a = Json.Get(t, "active") as Dictionary<string, object>; var done = Json.L(t, "done").OfType<Dictionary<string, object>>().ToList();
            if (a == null && done.Count == 0) return null;
            var lines = new List<object>();
            if (a != null)
            {
                string id = Json.S(a, "id"), game = Json.S(a, "game"); var since = Kit.Date(Json.Get(a, "started")) ?? DateTime.MinValue;
                int Count(string arm) => s.Perf.Count(r => Json.S(r, "game") == game && Json.S(r, "tune") == id + ":" + arm && (Kit.Date(Json.Get(r, "date")) ?? DateTime.MinValue) >= since);
                int na = Count("a"), nb = Count("b"); var on = Json.S(a, "arm") == "b" ? Json.S(a, "b") : Json.S(a, "a");
                var sh = Short(id, Json.S(a, "a"), Json.S(a, "b"), on); var measured = $"{Math.Min(na, 4) + Math.Min(nb, 4)} of 8 minutes of play measured";
                // Which one is on goes next to its value (10/28: a closing 'On now: 75%.' wrapped its value onto a line of its own)
                bool onB = Json.S(a, "arm") == "b";
                string va = sh != null ? sh[1] : Say(id, Json.S(a, "a")), vb = sh != null ? sh[2] : Say(id, Json.S(a, "b"));
                lines.Add(new Line($"Trying now in {Data.GameName(game)}: {(sh != null ? sh[0] + " " : "")}{va} ({(onB ? "as before" : "as before, on now")}) against {vb}{(onB ? " (on now)" : "")} - {measured}.", "info"));
                lines.Add(new Line("Switched only while the game is closed, over several evenings. The new value stays only if clearly faster (Reflex: less delay to the screen); a driver or Windows update stops it and puts yours back.", "dim"));
            }
            else if (Json.Get(s.GpuState, "trial") is Dictionary<string, object> tr && Json.S(tr, "verdict") == "")
                lines.Add(new Line("Waiting: a new graphics driver is being tested first (a setting tried at the same time would muddy both results).", "dim"));
            var rows = new List<(string, string, string)>();
            foreach (var d in done.AsEnumerable().Reverse().Take(8))
            {
                string id = Json.S(d, "id"), why = Json.S(d, "why"), kept = Json.S(d, "kept"); var at = Kit.Date(Json.Get(d, "at"));
                double? aL = Json.N(d, "aLow"), bL = Json.N(d, "bLow"), aF = Json.N(d, "aFps"), bF = Json.N(d, "bFps");
                string Pct(double x, double y) => y > 0 ? $"{(x >= y ? "+" : "")}{Math.Round((x - y) / y * 100)}%" : "";
                var nums = aL != null && bL != null && aF != null && bF != null ? $" (1% low {Math.Round(aL.Value)} -> {Math.Round(bL.Value)} fps {Pct(bL.Value, aL.Value)}, average {Math.Round(aF.Value)} -> {Math.Round(bF.Value)} fps)" : "";
                if (Json.N(d, "aLatency") is double aY && Json.N(d, "bLatency") is double bY && nums != "") nums = $" (delay to the screen {aY} -> {bY} ms {Pct(bY, aY)}, " + nums.Substring(2);   // (Reflex: judged on the delay, 10/22)
                string text, level;
                if (why == "faster") { text = $"{Say(id, Json.S(d, "b"))} is faster than {Say(id, Json.S(d, "a"))}{nums}, so Messiah uses it now"; level = "ok"; }
                else if (why == "no faster") { text = $"{Say(id, Json.S(d, "b"))} was no faster{nums} - kept {Say(id, Json.S(d, "a"))}"; level = "info"; }
                else { text = $"{Json.S(d, "label")}: stopped - {why}{(kept != "" ? $"; {Say(id, kept)} kept" : "")}"; level = "dim"; }
                rows.Add((at?.ToString("MMM d") ?? "", text, level));
            }
            if (rows.Count > 0) lines.Add(Ui.Rows(rows));
            return Ui.Card("Tuned by measuring", "E9E9", lines.ToArray());
        }

        // --- a new graphics driver on test (gpu-watch.ps1): measured against the one before; clearly slower = back by itself
        static UIElement DriverTest(Snapshot s)
        {
            if (!(Json.Get(s.GpuState, "trial") is Dictionary<string, object> tr)) return null;
            var since = Kit.Date(Json.Get(tr, "since")); if (since == null || since < DateTime.Now.AddDays(-30)) return null;
            string drv = Json.S(tr, "driver"), from = Json.S(tr, "from"), verdict = Json.S(tr, "verdict"), text = Json.S(tr, "text");
            Line l;
            if (verdict == "")
            {
                var n = s.Perf.Where(r => Json.S(r, "driver") == drv && (Kit.Date(Json.Get(r, "date")) ?? DateTime.MinValue) >= since).GroupBy(r => Json.S(r, "game")).Select(g => g.Count()).DefaultIfEmpty(0).Max();
                l = new Line($"Driver {drv} (since {Kit.FormatWhen(since.Value, dateOnly: true)}) is on test against {from}: {Math.Min(n, 3)} of 3 minutes of play measured on it. If your games run clearly slower on it, Messiah goes back to {from} by itself.", "info");
            }
            else if (verdict == "passed") l = new Line($"Driver {drv} passed its test - {text}", "ok");
            else if (verdict == "rolled back") l = new Line($"Driver {drv} was undone - {text}", "warn");
            else if (verdict == "slower") l = new Line($"Driver {drv} is slower - {text}. Settings > Tools > Go back to the previous graphics driver", "warn");
            else l = new Line($"Driver {drv}: {text}", "dim");
            return Ui.Card("Graphics driver test", "E7F8", new object[] { l });
        }

        // --- the benchmark button (bench.ps1): each run with its numbers and the RAM speed it ran at, newest first
        static UIElement Benchmark(Snapshot s)
        {
            var lines = new List<object>();
            var runs = s.Bench.AsEnumerable().Reverse().Take(6).ToList();
            string N(Dictionary<string, object> r, string f, string unit) => Json.N(r, f) is double v ? $"{Math.Round(v):N0} {unit}" : "-";
            if (s.BenchRunning) lines.Add(new Line("Running now - about a minute and a half. Leave the PC alone meanwhile.", "info"));
            if (runs.Count > 0)
                lines.Add(Ui.Rows(runs.Select(r => (Kit.FormatWhen(Kit.Date(Json.Get(r, "date")).Value, dateOnly: true),
                    $"memory {N(r, "memBandwidthMBs", "MB/s")}" + (Json.N(r, "cpuMulti") != null ? $", processor {N(r, "cpuMulti", "MB/s")} all cores / {N(r, "cpuSingle", "MB/s")} one" : "") + (Json.N(r, "diskReadMBs") != null ? $", SSD {N(r, "diskReadMBs", "MB/s")}" : "") + (Json.S(r, "ram") != "" ? $" - RAM at {Json.S(r, "ram")}" : "") + (Json.S(r, "notes") != "" ? $" ({Json.S(r, "notes")})" : ""), "info"))));
            lines.Add(new Line("The same short test every time (Windows' own WinSAT): run it before and after a change - EXPO, a BIOS update, a new driver - to see what it did. Your games above measure the graphics card.", "dim"));
            return Ui.Card("Benchmark", "E9D2", lines.ToArray(), s.BenchRunning ? null : new[] { Ui.Btn("E768", "Run the benchmark", Actions.Bench) });
        }

        // --- heat and wear: the graphics card, the processor and the SSD - while gaming and over time
        static UIElement Heat(Snapshot s)
        {
            var rows = new List<(string, string, string)>();
            var g = s.Perf.LastOrDefault(r => Json.N(r, "gpuTemp") != null); var h = s.HealthLast;
            var gpu = new List<string>(); var gl = "info";
            if (g != null)
            {
                var thr = Json.S(g, "throttle");
                gpu.Add($"up to {Json.N(g, "gpuTemp")} °C while gaming" + (Json.N(g, "gpuFan") is double gf ? $", fan {gf}%" : "") + (Json.N(g, "gpuPower") is double gp ? $", {gp} W" : "") + (thr != "" ? $" - it slowed itself down ({thr.Replace(",", " and ")} limit)" : ""));
                if (thr != "" || (Json.N(g, "gpuTemp") ?? 0) >= Week.GpuHot) gl = "warn";
            }
            if (Json.N(h, "gpuIdle") is double gi) gpu.Add($"{gi} °C at idle" + (Json.N(h, "gpuIdleFan") is double fi ? $", fan {fi}%" : ""));
            rows.Add(("Graphics card", gpu.Count > 0 ? string.Join("; ", gpu) : "measured from your next game", gpu.Count > 0 ? gl : "dim"));
            // the processor: its temperature (cpu-temp.ps1's driver) while gaming and at idle, and whether it was held back
            var c = s.Perf.LastOrDefault(r => Json.N(r, "cpuLimit") != null || Json.N(r, "cpuTemp") != null);
            var cpu = new List<string>(); var cl = "ok";
            if (c != null && Json.N(c, "cpuTemp") is double ctg) { cpu.Add($"up to {ctg} °C while gaming"); if (ctg >= Week.CpuHot) cl = "warn"; }
            if (Json.N(h, "cpuIdle") is double cti) cpu.Add($"{cti} °C at idle");
            if (c != null && Json.N(c, "cpuLimit") is double lim)
            {
                if (lim >= 95) cpu.Add($"at full speed while gaming ({Json.N(c, "cpuPerf")}% of its base speed)");
                else { cpu.Add($"held back to {lim}% of its speed while gaming - nearly always heat: the CPU cooler's fan or pump, its dust, the case's air flow"); cl = "warn"; }
            }
            rows.Add(("Processor", cpu.Count > 0 ? string.Join("; ", cpu) : "measured from your next game", cpu.Count > 0 ? cl : "dim"));
            // the fans (fan-watch.ps1): the ones that spin, at their speed now
            var fl = Json.L(s.Fans, "last").OfType<Dictionary<string, object>>().Where(x => (Json.N(x, "Rpm") ?? 0) > 0 || Json.S(x, "Hw") == "gpu").ToList();
            if (fl.Count > 0)
            {
                var gpuF = fl.Where(x => Json.S(x, "Hw") == "gpu").ToList(); var parts = new List<string>();
                foreach (var x in fl.Where(x => Json.S(x, "Hw") != "gpu")) parts.Add($"{Regex.Replace(Json.S(x, "Name"), "^Pump Fan$", "pump")}: {Json.N(x, "Rpm")} RPM");
                if (gpuF.Count > 0) parts.Add(gpuF.All(x => (Json.N(x, "Rpm") ?? 0) == 0) ? "graphics card: stopped (cool - it starts as it warms)" : $"graphics card: {gpuF.Max(x => Json.N(x, "Rpm") ?? 0)} RPM");
                rows.Add(("Fans", string.Join(", ", parts), "info"));
            }
            if (h != null && (Json.N(h, "ssdTemp") != null || Json.N(h, "ssdWear") != null))
            {
                var mx = Json.N(h, "ssdTempMax");
                var parts = new List<string>();
                if (Json.N(h, "ssdTemp") is double t0) parts.Add($"{t0} °C now");
                if (mx != null) parts.Add($"{mx} °C at its hottest{(mx >= 80 ? " (it slows itself down from about 80 °C - a heatsink helps)" : "")}");
                if (Json.N(h, "ssdWear") is double w) parts.Add($"{w}% worn");
                rows.Add(("SSD", string.Join(", ", parts), mx >= 80 ? "warn" : "info"));
            }
            var lines = new List<object> { Ui.Rows(rows) };
            var grid = Ui.Pairs(new UniformGrid { Columns = 2, Margin = Ui.Th("0,8,-14,0") });
            var gt = s.Perf.Where(r => Json.N(r, "gpuTemp") != null && Kit.Date(Json.Get(r, "date")) != null).Select(r => (Kit.Date(Json.Get(r, "date")).Value, Json.N(r, "gpuTemp").Value)).ToList();
            if (gt.Count >= 2) grid.Children.Add(Pad(Charts.Chart("Graphics card while gaming", " °C", Points(s.Perf, "gpuTemp", s.Tune, true), 0, 10, hint: false)));
            var it = s.Health.Where(r => Json.N(r, "gpuIdle") != null && Kit.Date(Json.Get(r, "date")) != null).Select(r => (Kit.Date(Json.Get(r, "date")).Value, Json.N(r, "gpuIdle").Value)).ToList();
            if (it.Count >= 2) grid.Children.Add(Pad(Activity.Chart("Graphics card at idle", " °C", it, 0, 10)));
            var cg = s.Perf.Where(r => Json.N(r, "cpuTemp") != null && Kit.Date(Json.Get(r, "date")) != null).Select(r => (Kit.Date(Json.Get(r, "date")).Value, Json.N(r, "cpuTemp").Value)).ToList();
            if (cg.Count >= 2) grid.Children.Add(Pad(Charts.Chart("Processor while gaming", " °C", Points(s.Perf, "cpuTemp", s.Tune, true), 0, 10, hint: false)));
            var ci = s.Health.Where(r => Json.N(r, "cpuIdle") != null && Kit.Date(Json.Get(r, "date")) != null).Select(r => (Kit.Date(Json.Get(r, "date")).Value, Json.N(r, "cpuIdle").Value)).ToList();
            if (ci.Count >= 2) grid.Children.Add(Pad(Activity.Chart("Processor at idle", " °C", ci, 0, 10)));
            if (grid.Children.Count > 0) lines.Add(grid);
            lines.Add(new Line("Warming up over the months usually means dust - Messiah says when it's time to clean the fans and filters.", "dim"));
            return Ui.Card("Heat and wear", "E9CA", lines.ToArray());
        }

        // what holds the frame rate back, the delay to the screen and how frames get there (game-perf.ps1's gpuBusy /
        // latency / presentMode, 10/22) - so "what would make it faster" has an answer: graphics settings only help when the
        // card is the limit; at a frame cap nothing is held back
        // (10/28: the limit comes from the session's own verdict, so the card never says 'Smooth' above 'the processor is the
        // limit'; at the screen's rate nothing needs raising. The old reading only when the minute is too short for a verdict)
        // (said: the card's verdict above already names this session's cap or busy %, so only the advice is left - 10/28)
        public static Line Limit(Dictionary<string, object> last, List<double> per, int hz = 0, bool said = false)
        {
            var gb = Json.N(last, "gpuBusy"); var lat = Json.N(last, "latency"); var pm = Json.S(last, "presentMode");
            if (gb == null && lat == null && pm == "") return null;
            var kind = Verdict(new List<Dictionary<string, object>> { last }, hz)?.Kind; said = said && (kind == "Capped" || kind == "Processor" || kind == "Graphics" || kind == "Paced");   // (Paced says the % too since 10/28)
            var busy = gb ?? Json.N(last, "gpuUse"); var of = gb != null ? " of each frame" : "";
            var med = per.Count >= 10 ? per.OrderBy(x => x).ElementAt(per.Count / 2) : 0;
            bool capped = kind == null ? med > 0 && per.Count(x => Math.Abs(x - med) <= 3) >= per.Count * 0.8 : kind == "Capped";
            var parts = new List<string>(); var cls = "dim";
            if (capped) parts.Add(said ? "Nothing else holds it back" : med > 0 ? $"Steady at its frame cap (about {Math.Round(med)} fps) - nothing is holding it back" : "Steady at its frame cap - nothing is holding it back");
            else if (kind == "Smooth" && hz > 0) { }
            else if (busy >= 90 && kind != "Processor" && kind != "Paced") parts.Add(said ? "Lower graphics settings or DLSS raise the frame rate" : $"The graphics card is the limit (busy {busy}%{of}) - lower graphics settings or DLSS raise the frame rate");
            else if (busy != null && busy < 90) parts.Add(said ? "Graphics settings won't raise it; faster RAM (EXPO) and fewer background apps do" : $"The processor or the game is the limit (the graphics card is busy only {busy}%{of}) - graphics settings won't raise it; faster RAM (EXPO) and fewer background apps do");
            if (lat != null) parts.Add($"{lat} ms from the game starting a frame to it on screen");
            if (pm.Contains("Composed: Flip") && !pm.Contains("Independent")) { parts.Add("frames go through the Windows desktop compositor (about a frame of extra delay) - an overlay or a window on top of the game usually causes it"); cls = "warn"; }
            return parts.Count > 0 ? new Line(string.Join("; ", parts) + ".", cls) : null;
        }

        // a game's latest session in one line - how it ran and what holds it back (Game check-up, 10/28: every game gets a
        // verdict, not only Call of Duty's tuning). rows: that game's sessions, oldest first; hz: the screen's refresh rate (0 not
        // known). Kinds: Smooth / Capped / Processor / Graphics / Stuttery; null when the minute was too short to say (under 1000
        // frames). Hitches count against the game's own usual rate (3+ sessions) and need 5 more than usual, so a game that always
        // hitches a little isn't flagged
        internal static (string Kind, string Text)? Verdict(List<Dictionary<string, object>> rows, int hz)
        {
            var last = rows?.LastOrDefault(); if (last == null) return null;
            var frames = Json.N(last, "frames") ?? 0; var fps = Json.N(last, "fps") ?? 0; var low = Json.N(last, "low1") ?? 0;
            if (frames < 1000 || fps <= 0) return null;
            double Rate(Dictionary<string, object> r) => (Json.N(r, "stutters") ?? 0) * 10000 / Math.Max(1, Json.N(r, "frames") ?? 0);
            var st = (int)(Json.N(last, "stutters") ?? 0);
            var before = rows.Take(rows.Count - 1).Where(r => (Json.N(r, "frames") ?? 0) >= 1000).ToList();
            if (before.Count >= 2 && st >= 5)
            {
                var usualRate = Median(before.Select(Rate).ToList());
                if (Rate(last) > Math.Max(usualRate * 2, usualRate + 5))
                {
                    var usual = (int)Math.Round(usualRate * frames / 10000);
                    if (st - usual >= 5) return ("Stuttery", $"More hitches than usual: {st} in the last minute measured, usually {(usual == 0 ? "none" : "about " + usual)}");
                }
            }
            var f = Math.Round(fps); var scr = hz > 0 ? $" on a {hz} Hz screen" : "";
            if (hz > 0 && fps >= hz * 0.95) return ("Smooth", $"Smooth: {f} fps{scr}");
            // a flat line is a frame cap: second by second within 3% of the middle, or (without the seconds) a common cap
            var per = Json.L(last, "perSec").Select(Num).ToList();
            bool flat; var cap = f;   // (said as the common cap it sits at: 58.5 fps is a 60 fps cap)
            var common = new[] { 30, 60, 120, 144, 165 }.FirstOrDefault(c => Math.Abs(fps - c) <= c * 0.03); if (common > 0) cap = common;
            if (per.Count >= 10) { var med = Median(per); flat = per.Count(x => Math.Abs(x - med) <= med * 0.03) >= per.Count * 0.8; }
            else flat = common > 0 && low >= fps * 0.75;
            if (flat) return ("Capped", hz > 0 ? $"Capped at {cap} fps on a {hz} Hz screen" : $"Steady at a {cap} fps cap");
            var busy = Json.N(last, "gpuBusy") ?? Json.N(last, "gpuUse");
            if (busy >= 90) return ("Graphics", $"Held back by the graphics card ({busy}% busy): {f} fps{scr}");
            if (busy != null && busy < 70) return ("Processor", $"Held back by the processor or the game (graphics card {busy}% busy): {f} fps{scr}");
            // (10/28: 70-89% busy under the screen's rate runs well, but the card isn't what sets the pace - said so, as Limit does)
            // (with the busy %, so the limit line under it keeps only the advice - it said the 72% twice, 10/28)
            if (busy != null) return ("Paced", $"Runs well: {f} fps{scr}, 1% low {Math.Round(low)}, paced by the processor or the game (graphics card {busy}% busy)");
            return ("Smooth", $"Smooth: {f} fps{scr}, 1% low {Math.Round(low)}");
        }

        // where a Capped verdict's cap probably comes from and what to change in the game's menu (Game check-up, 10/28) - text
        // only, Messiah never changes a game's settings. Messiah's own NVIDIA cap (the screen's rate minus 3 with G-SYNC,
        // nvidia-settings.ps1) runs near the screen's rate and reads as Smooth, so a cap here is the game's or V-Sync's.
        // gsync: gsync.txt's first line (1 on, 0 off, else not known); null for a verdict that isn't Capped
        internal static string CapCause((string Kind, string Text)? v, int hz, string gsync)
        {
            if (v == null || v.Value.Kind != "Capped") return null;
            var cap = int.Parse(Regex.Match(v.Value.Text, @"(\d+) fps").Groups[1].Value);
            if (hz <= 0) return "Usually the game's own frame limit or V-Sync. Both are in the game's video settings.";
            if (Math.Abs(cap * 2 - hz) <= hz * 0.03)
                return gsync == "1" ? "Half the screen's rate usually means V-Sync at half rate in the game. Turn V-Sync off in its video settings: G-SYNC keeps it smooth without it."
                                    : "Half the screen's rate usually means V-Sync at half rate in the game. In its video settings, set V-Sync to full rate.";
            var mode = new[] { 50, 60, 75, 100, 120, 144, 165 }.Contains(cap) ? $", or the game set to {cap} Hz" : "";   // (a refresh rate a screen offers)
            return $"Most likely the game's own frame limit{mode}. In its video settings, set the frame rate limit to Unlimited and the refresh rate to {hz} Hz"
                + (gsync == "1" ? ". Messiah's NVIDIA settings keep it just under the screen's rate." : ".");
        }

        // G-SYNC on the main screen as nvidia-settings.ps1 last read it (gsync.txt: 1 on, 0 off); "" when not known
        internal static string Gsync() { try { return System.IO.File.ReadLines(System.IO.Path.Combine(Kit.Cl, "gsync.txt")).FirstOrDefault()?.Trim() ?? ""; } catch { return ""; } }

        // the verdict in a few words, for Home's Last game tile (Game check-up, 10/28: 'NBA 2K20, last session today, capped at 60
        // fps' - the bare 1% low said nothing about why); null without a verdict, so the tile keeps the 1% low
        internal static string Brief((string Kind, string Text)? v, double low)
        {
            if (v == null) return null;
            switch (v.Value.Kind)
            {
                case "Capped": return $"capped at {Regex.Match(v.Value.Text, @"(\d+) fps").Groups[1].Value} fps";
                case "Processor": return "held back by the processor";
                case "Graphics": return "held back by the graphics card";
                case "Stuttery": return "more hitches than usual";
                case "Paced": return $"runs well, 1% low {Math.Round(low)}";
                default: return $"smooth, 1% low {Math.Round(low)}";
            }
        }

        // --- the charts' words (10/22, interactive charts): a session in a line (said on hover), what changed between
        // sessions (the marks), and the session picked on a chart (Trends' charts open it here)
        internal static readonly Dictionary<string, string> Pick = new Dictionary<string, string>();   // game -> the picked session's date
        internal static string TuneWords(string tag, Dictionary<string, object> tune)
        {
            var m = Regex.Match(tag ?? "", @"^(\w+):([ab])$"); if (!m.Success) return null;
            var t = new[] { Json.Get(tune, "active") }.Concat(Json.L(tune, "done").Reverse()).OfType<Dictionary<string, object>>().FirstOrDefault(x => Json.S(x, "id") == m.Groups[1].Value);
            return t == null ? $"a setting being tried ({m.Groups[1].Value})" : "trying " + Say(m.Groups[1].Value, Json.S(t, m.Groups[2].Value));
        }
        internal static string Describe(Dictionary<string, object> r, Dictionary<string, object> tune, string field = null)
        {
            // (the chart's own value is said already: the other one of the two)
            string f = $"{Math.Round(Json.N(r, "fps") ?? 0)} fps", l = $"1% low {Math.Round(Json.N(r, "low1") ?? 0)}";
            var p = new List<string> { field == "fps" ? l : field == "low1" ? "average " + f : f + ", " + l };
            if (Json.N(r, "gpuBusy") is double gb) p.Add($"graphics card busy {gb}% of each frame");
            if (Json.N(r, "latency") is double la) p.Add($"{la} ms to the screen");
            if (Json.N(r, "gpuTemp") is double gt) p.Add($"card {gt} °C");
            if (Json.N(r, "cpuTemp") is double ct) p.Add($"processor {ct} °C");
            if (Json.S(r, "ram") is string ram && ram != "") p.Add("RAM " + ram);
            if (Json.N(r, "netPing") is double np && field != "netPing") p.Add($"ping {np:0} ms{((Json.N(r, "netLoss") ?? 0) > 0 ? $", {Json.N(r, "netLoss")}% lost" : "")}");
            if (TuneWords(Json.S(r, "tune"), tune) is string tw) p.Add(tw);
            return string.Join(", ", p);
        }
        internal static List<(DateTime D, string Text)> Marks(List<Dictionary<string, object>> rows, Dictionary<string, object> tune)
        {
            var o = new List<(DateTime, string)>();
            for (int i = 1; i < rows.Count; i++)
            {
                if (!(Kit.Date(Json.Get(rows[i], "date")) is DateTime d)) continue;
                foreach (var (field, what) in Changes)
                {
                    string a = Json.S(rows[i - 1], field), b = Json.S(rows[i], field);
                    if (a != "" && b != "" && a != b) o.Add((d, field == "settings" ? "your game settings" : $"{what} {b}"));
                }
                string ta = Json.S(rows[i - 1], "tune"), tb = Json.S(rows[i], "tune");
                if (tb != ta && TuneWords(tb, tune) is string tw) o.Add((d, tw));
            }
            return o;
        }
        // the legend under a game's charts names only the kinds of mark it has (10/27: Call of Duty's marks were all Messiah's
        // own tries, and the legend said a driver, Windows, the RAM speed or your settings)
        internal static bool IsTry(string mark) => mark.StartsWith("trying ") || mark.StartsWith("a setting being tried");
        internal static string MarkNote(List<(DateTime D, string Text)> marks)
        {
            bool tries = marks.Any(m => IsTry(m.Text)), other = marks.Any(m => !IsTry(m.Text));
            const string changed = "something changed there (a driver, Windows, the RAM speed, your settings)";
            if (!tries) return $"A dashed mark: {changed}.";
            return other ? $"A dashed mark: {changed}, or Messiah switched a setting it's trying (Tuned by measuring, above)."
                         : "A dashed mark: Messiah switched a setting it's trying there (Tuned by measuring, above).";
        }
        internal static List<ChartPt> Points(IEnumerable<Dictionary<string, object>> rows, string field, Dictionary<string, object> tune, bool named = false) =>
            rows.Where(r => Json.N(r, field) != null && Kit.Date(Json.Get(r, "date")) != null)
                .Select(r => new ChartPt { D = Kit.Date(Json.Get(r, "date")).Value, V = Json.N(r, field).Value, Key = Json.S(r, "date"), More = (named ? Data.GameName(Json.S(r, "game")) + ": " : "") + Describe(r, tune, field) }).ToList();

        // one game: its sessions over time (point at one to read it, click it to open it), and the session opened - the latest
        // unless one was picked - its numbers, what limits it, its minute second by second. It leads with the latest session's
        // verdict (Game check-up, 10/28): Smooth with a tick, the rest as plain words - a cap or a busy processor isn't an alarm
        static UIElement Game(string game, string key, List<Dictionary<string, object>> rows, Dictionary<string, object> tune, int hz)
        {
            var usual = Median(rows.Select(r => Json.N(r, "fps") ?? 0).ToList());
            Pick.TryGetValue(key, out var pk);
            var sel = new ChartSel { Key = Json.S(rows.LastOrDefault(r => Json.S(r, "date") == pk) ?? rows.Last(), "date") };
            var detail = new StackPanel();
            var v = Verdict(rows, hz);   // (the latest session's: its limit line then keeps only the advice, unless it's about hitches)
            void Open(string date)
            {
                var r = rows.LastOrDefault(x => Json.S(x, "date") == date) ?? rows.Last(); var latest = r == rows.Last();
                Pick[key] = latest ? null : date;
                detail.Children.Clear();
                foreach (var l in Session(r, rows.Count, usual, latest, key == NoteKey, hz, latest && v != null && v.Value.Kind != "Stuttery")) detail.Children.Add(l is Line ln ? Ui.LineEl(ln.Text, ln.Level) : (UIElement)l);
                if (!latest)
                {
                    var back = new TextBlock(); var hl = new System.Windows.Documents.Hyperlink(new System.Windows.Documents.Run("Back to the latest session")) { Foreground = B("Accent") };
                    hl.Click += (s, e) => { sel.Set(Json.S(rows.Last(), "date")); Open(Json.S(rows.Last(), "date")); }; back.Inlines.Add(hl); back.Margin = Ui.Th("0,2,0,0"); detail.Children.Add(back);
                }
            }
            var lines = new List<object>();
            if (v != null) lines.Add(new Line(v.Value.Text + ".", v.Value.Kind == "Smooth" ? "ok" : "info"));
            if (CapCause(v, hz, Gsync()) is string cause) lines.Add(new Line(cause, "dim"));   // (where the cap comes from, 10/28)
            var marks = Marks(rows, tune);
            var grid = Ui.Pairs(new UniformGrid { Columns = 2, Margin = Ui.Th("0,8,-14,0") });
            if (rows.Count >= 2)
            {
                grid.Children.Add(Pad(Charts.Chart("Frame rate, each session", " fps", Points(rows, "fps", tune), 0, 20, marks, p => Open(p.Key), sel, hint: false)));
                grid.Children.Add(Pad(Charts.Chart("1% low, each session", " fps", Points(rows, "low1", tune), 0, 20, marks, p => Open(p.Key), sel, hint: false)));
                lines.Add(grid);
                if (marks.Count > 0) lines.Add(new Line(MarkNote(marks), "dim"));
            }
            lines.Add(detail);
            Open(sel.Key);
            return Ui.Card(game, "E7FC", lines.ToArray());
        }
        // --test: a game's charts driven without a mouse - a point read, the range changed, a session clicked open
        internal static IEnumerable<string> ChartSelfTest()
        {
            var now = DateTime.Now; var rows = new List<Dictionary<string, object>>();
            for (int i = 0; i < 12; i++)
            {
                var r = new Dictionary<string, object> { ["date"] = now.AddDays(-40 + i * 3.5).ToString("o"), ["game"] = "cod", ["fps"] = 140 + i, ["low1"] = 100 + i, ["driver"] = i < 6 ? "1.0" : "2.0", ["ram"] = "4800 MT/s", ["gpuBusy"] = 97, ["frames"] = 8000 };
                if (i == 3) r["perSec"] = new object[] { 120, 121, 119 };
                if (i >= 9) r["tune"] = "uploadheaps:" + (i == 11 ? "b" : "a");
                rows.Add(r);
            }
            var tune = new Dictionary<string, object> { ["active"] = new Dictionary<string, object> { ["id"] = "uploadheaps", ["a"] = "true", ["b"] = "false" } };
            var card = Game("Call of Duty", "cod-selftest", rows, tune, 239);
            IEnumerable<DependencyObject> All(DependencyObject d) { yield return d; foreach (var c in LogicalTreeHelper.GetChildren(d).OfType<DependencyObject>()) foreach (var x in All(c)) yield return x; }
            StackPanel Chart(string title) => All(card).OfType<StackPanel>().FirstOrDefault(x => (x.Tag as string ?? "").StartsWith("CHART: " + title + " |"));
            ChartCtl Ctl(string title) => All(Chart(title)).OfType<Canvas>().Select(c => c.DataContext as ChartCtl).FirstOrDefault(c => c != null);
            string Words() => string.Join(" / ", All(card).OfType<TextBlock>().Select(t => t.Text).Where(t => t.StartsWith("Session opened") || t.EndsWith("second by second")).Concat(All(card).OfType<System.Windows.Documents.Run>().Select(x => x.Text).Where(x => x.StartsWith("Back to"))));
            yield return "CHARTTEST leads with: " + All(card).OfType<TextBlock>().Select(t => t.Text).FirstOrDefault(t => (t ?? "").Contains(" fps"));
            yield return "CHARTTEST tag: " + Chart("Frame rate, each session").Tag;
            var ctl = Ctl("Frame rate, each session");
            yield return $"CHARTTEST points shown: {ctl.Count}";
            yield return "CHARTTEST hover first: " + ctl.Hover(0);
            ctl.Range("All"); ctl = Ctl("Frame rate, each session");
            yield return $"CHARTTEST all: {ctl.Count} points";
            yield return "CHARTTEST hover after the driver: " + ctl.Hover(6);
            yield return "CHARTTEST hover tested: " + ctl.Hover(11);
            yield return "CHARTTEST before click: " + Words();
            ctl.Click(3);
            yield return "CHARTTEST clicked: " + Words();
            yield return "CHARTTEST other chart follows: " + (Chart("1% low, each session") != null);
            yield return "CHARTTEST hints: " + All(card).OfType<TextBlock>().Count(t => (t.Text ?? "").StartsWith("Point at"))
                + " | subtitle " + (Messiah.MainWindow.Subs.TryGetValue("Activity/Performance", out var sub) && sub.Contains("Point at a chart to read it, click a session to open it") ? "says it" : "doesn't");   // (10/27: the subtitle says it once)
        }

        // a session's numbers, what limits it, and its minute second by second (what Game opens)
        static List<object> Session(Dictionary<string, object> last, int sessions, double usual, bool latest, bool note = true, int hz = 0, bool said = false)
        {
            var when = Kit.Date(Json.Get(last, "date")).Value;
            var fps = Json.N(last, "fps") ?? 0; var low = Json.N(last, "low1") ?? 0; var st = (int)(Json.N(last, "stutters") ?? 0);
            var lines = new List<object>
            {
                new Line($"{(latest ? "" : "Session opened: ")}{Math.Round(fps)} fps average, 1% low {Math.Round(low)} fps, {st} hitch{(st == 1 ? "" : "es")} - {Kit.FormatWhen(when)}" +
                    (sessions > 1 ? $" (usual {Math.Round(usual)} fps over {sessions} sessions)" : ""), fps < usual * 0.9 && sessions > 2 ? "warn" : "info")
            };
            var gt = Json.N(last, "gpuTemp"); var thr = Json.S(last, "throttle");
            if (gt != null) lines.Add(new Line($"Graphics card up to {gt} °C{(Json.N(last, "gpuUse") is double gu ? $", {gu}% busy" : "")}{(thr != "" ? $" - it slowed itself down ({thr.Replace(",", " and ")} limit)" : "")}", thr != "" ? "warn" : "dim"));
            // drivers' time on the busiest core while playing (interrupts and deferred calls): over 15% steals time from the game
            var dpc = Json.N(last, "dpcMax");
            if (dpc != null) lines.Add(new Line(dpc >= 15 ? $"Drivers took up to {dpc}% of a core while you played - enough to cause stutters the frame rate hides (audio, network or USB drivers are the usual ones)" : $"Drivers took up to {dpc}% of a core while you played - fine", dpc >= 15 ? "warn" : "dim"));
            var per = Json.L(last, "perSec").Select(Num).ToList(); var worst = Json.L(last, "worstMs").Select(Num).ToList();
            var lim = Limit(last, per, hz, said); if (lim != null) lines.Add(lim);
            var net = Connection.Session(last, sessions > 2 && (fps < usual * 0.9 || st >= 10)); if (net != null) lines.Add(net);
            if (per.Count >= 2)
            {
                var grid = Ui.Pairs(new UniformGrid { Columns = 2, Margin = Ui.Th("0,8,-14,0") });
                grid.Children.Add(Pad(Curve(latest ? "The last minute, second by second" : $"That minute ({when:MMM d, h:mm tt}), second by second", " fps", per, false)));
                if (worst.Count >= 2) grid.Children.Add(Pad(Curve("Its slowest frame each second", " ms", worst, true)));
                lines.Add(grid);
            }
            else if (!latest) lines.Add(new Line("That session's second-by-second view isn't kept (only the newest 30 keep it).", "dim"));
            else if (note) lines.Add(new Line(SecsNote(when), "dim"));
            return lines;
        }
        // a latest session without its second-by-second view says why once, under the first game card it's missing from - not
        // under every game (10/28: the same note under Call of Duty and Apex); one from Oct 21 on lost it to the newest-30 cap or a
        // short capture - which one isn't known here, so the note doesn't say
        internal static string NoteKey;
        internal static string SecsNoteKey(IEnumerable<(string Key, Dictionary<string, object> Last)> games) =>
            games.Where(g => Json.L(g.Last, "perSec").Count() < 2).Select(g => g.Key).FirstOrDefault();
        internal static string SecsNote(DateTime when) => when < new DateTime(2026, 10, 21)
            ? "The second-by-second view shows from the next session on (sessions measured before Oct 21 kept only the totals)."
            : "This session kept only its totals - the second-by-second view shows again from the next session on.";
        static UIElement Pad(UIElement e) { ((FrameworkElement)e).Margin = Ui.Th("0,0,14,14"); return e; }

        // something that changed between sessions - a graphics driver, Windows, the RAM speed (EXPO), Memory Integrity, the game's
        // own settings: each game's sessions on the one before and on the one after, side by side, and what it came to
        internal static readonly (string Field, string What)[] Changes = { ("driver", "Graphics driver"), ("build", "Windows"), ("ram", "RAM speed"), ("hvci", "Memory Integrity"), ("settings", "Your game settings") };
        static UIElement Updates(List<IGrouping<string, Dictionary<string, object>>> games, Dictionary<string, object> tune)
        {
            var lines = new List<(string, string, string)>();
            foreach (var g in games) foreach (var v in Verdicts(Data.GameName(g.Key), g.ToList())) lines.Add((v.When, v.Text, v.Level));
            if (lines.Count == 0) lines.Add(("", NoChanges(games.Any(g => Marks(g.ToList(), tune).Any(m => IsTry(m.Text)))), "dim"));
            return Ui.Card("Before and after changes", "E895", new object[] { Ui.Rows(lines.OrderByDescending(l => l.Item1).ToList()) });
        }
        // with only Messiah's own tries on the charts, "nothing changed" under their dashed marks read wrong (10/27)
        internal static string NoChanges(bool tries) => tries
            ? "Nothing else changed between sessions yet - the dashed marks are Messiah's own tries (Tuned by measuring, above). A driver, Windows or EXPO change shows here."   // (under Ui.Rows' 160-character fold)
            : "Nothing changed between sessions yet - after the next change (a driver, Windows, EXPO, a setting), each game's sessions before and after show here with what it came to.";
        internal static List<(string When, string Text, string Level, DateTime? Decided)> Verdicts(string game, List<Dictionary<string, object>> rows)
        {
            var o = new List<(string, string, string, DateTime?)>();
            foreach (var (field, what) in Changes)
            {
                var runs = new List<(string Ver, List<Dictionary<string, object>> Rows)>();
                foreach (var r in rows) { var v = Json.S(r, field); if (v == "") continue; if (runs.Count == 0 || runs[runs.Count - 1].Ver != v) runs.Add((v, new List<Dictionary<string, object>>())); runs[runs.Count - 1].Rows.Add(r); }
                for (int i = 1; i < runs.Count; i++)
                {
                    double A(List<Dictionary<string, object>> rr, string f) => rr.Average(r => Json.N(r, f) ?? 0);
                    var before = runs[i - 1].Rows; var after = runs[i].Rows;
                    double f0 = A(before, "fps"), f1 = A(after, "fps"), l0 = A(before, "low1"), l1 = A(after, "low1");
                    var pct = f0 > 0 ? (f1 - f0) / f0 * 100 : 0; var lpct = l0 > 0 ? (l1 - l0) / l0 * 100 : 0;
                    // a verdict once there are 2 sessions on each side (one minute can be a quiet moment or a busy one)
                    string verdict, level;
                    if (before.Count < 2 || after.Count < 2) { verdict = $"too early to tell - {after.Count} session(s) since"; level = "dim"; }
                    else if (pct <= -5 || lpct <= -8) { verdict = "worse"; level = "warn"; }
                    else if (pct >= 5 || lpct >= 8) { verdict = "better"; level = "ok"; }
                    else { verdict = "about the same"; level = "info"; }
                    var from = field == "settings" ? "" : $" {runs[i - 1].Ver} -> {runs[i].Ver}";
                    var at = Kit.Date(Json.Get(after[0], "date")).Value;
                    o.Add((at.ToString("MMM d"), $"{game} - {what}{from}: {verdict} - {Math.Round(f0)} -> {Math.Round(f1)} fps ({(pct >= 0 ? "+" : "")}{Math.Round(pct)}%), 1% low {Math.Round(l0)} -> {Math.Round(l1)} ({(lpct >= 0 ? "+" : "")}{Math.Round(lpct)}%)", level, before.Count >= 2 && after.Count >= 2 ? Kit.Date(Json.Get(after[1], "date")) : null));
                }
            }
            return o;
        }
        static double Median(List<double> v) { if (v.Count == 0) return 0; var s = v.OrderBy(x => x).ToList(); int m = s.Count / 2; return s.Count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2; }

        // a minute second by second: the frame rate as a line; the slowest frames as bars (amber over 50 ms - a hitch)
        static Border Curve(string title, string unit, List<double> vals, bool bars)
        {
            var sp = new StackPanel();
            var hero = new StackPanel { Orientation = Orientation.Horizontal };
            var head = bars ? vals.Max() : Median(vals);
            hero.Children.Add(Ui.Text(Math.Round(head) + unit, B("Text"), 26, FontWeights.SemiBold, "0"));
            var sub = Ui.Text(bars ? $"   worst - {vals.Count(v => v > 50)} hitch(es) over 50 ms" : $"   typical - lowest {Math.Round(vals.Min())}{unit}", B("Sub"), 12, null, "0,0,0,5"); sub.VerticalAlignment = VerticalAlignment.Bottom; hero.Children.Add(sub);
            sp.Children.Add(hero);
            double W = 330, H = 84, lo = bars ? 0 : vals.Min(), hi = Math.Max(vals.Max(), bars ? 60 : vals.Min() + 20);
            var pad = (hi - lo) * 0.1; if (!bars) lo -= pad; hi += pad;
            double X(int i) => vals.Count == 1 ? W / 2 : i / (double)(vals.Count - 1) * (W - 12) + 6; double Y(double v) => H - 4 - (v - lo) / (hi - lo) * (H - 8);
            var cv = new Canvas { Width = W, Height = H, Margin = Ui.Th("0,10,0,0"), HorizontalAlignment = HorizontalAlignment.Left };
            foreach (var gy in new[] { 4.0, H - 4 }) cv.Children.Add(new Sh.Line { X1 = 0, X2 = W, Y1 = gy, Y2 = gy, Stroke = B("Border"), StrokeThickness = 1 });
            if (bars)
            {
                var y50 = Y(50); cv.Children.Add(new Sh.Line { X1 = 0, X2 = W, Y1 = y50, Y2 = y50, Stroke = B("Warn"), StrokeThickness = 1, StrokeDashArray = new DoubleCollection { 4, 3 }, Opacity = 0.6 });
                double bw = Math.Max(2, (W - 12) / vals.Count - 1.5);
                for (int i = 0; i < vals.Count; i++)
                {
                    var r = new Sh.Rectangle { Width = bw, Height = Math.Max(1, H - 4 - Y(vals[i])), Fill = vals[i] > 50 ? B("Warn") : B("Chart"), RadiusX = 1, RadiusY = 1, ToolTip = $"Second {i + 1}: slowest frame {vals[i]} ms" };
                    Canvas.SetLeft(r, X(i) - bw / 2); Canvas.SetTop(r, Y(vals[i])); cv.Children.Add(r);
                }
            }
            else
            {
                var line = new Sh.Polyline { Stroke = B("Chart"), StrokeThickness = 2, StrokeLineJoin = PenLineJoin.Round };
                for (int i = 0; i < vals.Count; i++) line.Points.Add(new Point(X(i), Y(vals[i])));
                cv.Children.Add(line);
                for (int i = 0; i < vals.Count; i++) { var hit = new Sh.Ellipse { Width = 12, Height = 12, Fill = Brushes.Transparent, ToolTip = $"Second {i + 1}: {vals[i]} fps" }; Canvas.SetLeft(hit, X(i) - 6); Canvas.SetTop(hit, Y(vals[i]) - 6); cv.Children.Add(hit); }
            }
            // (as wide as its card, 10/22: stretched sideways only - a minute's 60 seconds need no redraw to fit)
            cv.Margin = new Thickness(0); cv.HorizontalAlignment = HorizontalAlignment.Stretch;
            sp.Children.Add(new Viewbox { Child = cv, Stretch = Stretch.Fill, Height = H, Margin = Ui.Th("0,10,0,0") });
            // hover (10/22): a guide at the second pointed at, its value in the line under the chart
            string Rest() => $"{vals.Count} seconds - point at one to read it";
            var readout = Ui.Text(Rest(), B("Sub"), 11, null, "0,4,0,0");
            var guide = new Sh.Line { Y1 = 4, Y2 = H - 4, Stroke = B("Sub"), StrokeThickness = 1, Opacity = 0.6, IsHitTestVisible = false, Visibility = Visibility.Collapsed };
            cv.Children.Add(guide); cv.Background = Brushes.Transparent;
            cv.MouseMove += (s, e) =>
            {
                var i = (int)Math.Round((e.GetPosition(cv).X - 6) / Math.Max(1, W - 12) * (vals.Count - 1)); i = Math.Max(0, Math.Min(vals.Count - 1, i));
                guide.X1 = guide.X2 = X(i); guide.Visibility = Visibility.Visible;
                readout.Text = bars ? $"Second {i + 1}: slowest frame {vals[i]} ms{(vals[i] > 50 ? " - a hitch" : "")}" : $"Second {i + 1}: {vals[i]} fps"; readout.Foreground = B("Text");
            };
            cv.MouseLeave += (s, e) => { guide.Visibility = Visibility.Collapsed; readout.Text = Rest(); readout.Foreground = B("Sub"); };
            sp.Children.Add(readout);
            sp.Tag = $"CHART: {title} | {vals.Count} seconds, {(bars ? "worst" : "typical")} {Math.Round(head)}{unit}";
            return Ui.Card(title, null, new object[] { sp });
        }
    }
}
